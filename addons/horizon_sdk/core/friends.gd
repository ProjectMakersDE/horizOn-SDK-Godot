class_name HorizonFriends
extends RefCounted
## Complete own-player relationships. Revisions and request UUIDs always come from the reviewed snapshot.

signal friends_loaded(snapshot: Dictionary)
signal friends_updated(snapshot: Dictionary)
signal player_found(player: Dictionary)
signal friends_failed(error: String, code: String)
signal _request_finished()

const ENDPOINT := "/api/v1/app/friends"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _scope: Dictionary = {}
var _current: Dictionary = {}
var _epoch: int = 0
var _queueEpoch: int = 0
var _revision: int = -1
var _serverTime: int = -1
var _busy: bool = false
var _lastErrorCode: String = ""
var _uuid: RegEx = RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
var _profileId: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,31}\\z")
var _friendCode: RegEx = RegEx.create_from_string("^H-[A-Za-z0-9_-]{21}[AQgw]\\z")

func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)

func getFriends(user_id: String) -> Dictionary:
	return await _call(user_id, "")

func findPlayer(user_id: String, query: String) -> Dictionary:
	if not _validUuid(query) and _friendCode.search(query) == null: return _fail("INVALID_REQUEST")
	return await _call(user_id, "/find", {"query": query})

func sendRequest(user_id: String, target_user_id: String, expected_revision: Variant) -> Dictionary:
	return await _mutate(user_id, target_user_id, expected_revision, "/request")

func acceptRequest(user_id: String, target_user_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _requestAction(user_id, target_user_id, expected_revision, request_id, "/accept")

func declineRequest(user_id: String, target_user_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _requestAction(user_id, target_user_id, expected_revision, request_id, "/decline")

func cancelRequest(user_id: String, target_user_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _requestAction(user_id, target_user_id, expected_revision, request_id, "/cancel")

func removeFriend(user_id: String, target_user_id: String, expected_revision: Variant) -> Dictionary:
	return await _mutate(user_id, target_user_id, expected_revision, "/remove")

func blockPlayer(user_id: String, target_user_id: String, expected_revision: Variant) -> Dictionary:
	return await _mutate(user_id, target_user_id, expected_revision, "/block")

func unblockPlayer(user_id: String, target_user_id: String, expected_revision: Variant) -> Dictionary:
	return await _mutate(user_id, target_user_id, expected_revision, "/unblock")

func getCurrentFriends() -> Dictionary:
	_syncScope()
	return _current.duplicate(true) if _hasSession() else {}

func getLastErrorCode() -> String:
	return _lastErrorCode

## Realtime is only a hint. A game explicitly reloads HTTP after invalidation/reconnect.
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()

func _invalidate() -> void:
	_epoch += 1
	_current.clear()

func _requestAction(user_id: String, target: String, revision: Variant, request_id: String, route: String) -> Dictionary:
	if not _validUuid(request_id): return _fail("INVALID_REQUEST")
	return await _mutate(user_id, target, revision, route, request_id)

func _mutate(user_id: String, target: String, revision: Variant, route: String, request_id: String = "") -> Dictionary:
	if not _validUuid(target) or target.to_lower() == user_id.to_lower() or typeof(revision) != TYPE_INT or not _nonnegative(revision):
		return _fail("INVALID_REQUEST")
	var body: Dictionary = {"targetUserId": target, "expectedRevision": revision}
	if not request_id.is_empty(): body.requestId = request_id
	return await _call(user_id, route, body)

func _call(user_id: String, route: String, payload: Dictionary = {}) -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user_id != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not _validUuid(user_id): return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var queue_epoch: int = _queueEpoch
	while _busy:
		await _request_finished
	_syncScope()
	if scope != _scope or queue_epoch != _queueEpoch: return _fail("STALE_RESPONSE")
	_busy = true
	var mutation: bool = not route.is_empty() and route != "/find"
	if mutation: _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT + route + "?userId=" + user_id.uri_encode()
	if route == "/find": endpoint += "&query=" + payload.query.uri_encode()
	var body: Dictionary = payload.duplicate(true)
	body.userId = user_id
	# These commands have no permanent receipts. Even an internal transport retry after
	# 503/timeout/429 could affect a newer relationship; reconcile with an explicit GET.
	var response: HorizonNetworkResponse = await _http.postOnceAsync(ENDPOINT + route, body, true) if mutation else await _http.getAsync(endpoint, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch:
		result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401: clearCache()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	elif not HorizonInbox._safeJson(response.rawBody) or not HorizonPlayerValues._safeJsonIntegers(response.rawBody, ["revision", "maxFriends", "maxIncomingRequests", "maxOutgoingRequests", "maxBlocked"]):
		result = _fail("INVALID_RESPONSE")
	else:
		_lastErrorCode = "INVALID_RESPONSE"
		var data: Dictionary = _normalizePlayer(response.data, payload.query) if route == "/find" else _normalize(response.data, user_id)
		if data.is_empty():
			result = _fail(_lastErrorCode)
		else:
			if route != "/find":
				_current = data.duplicate(true)
				_revision = data.revision
				_serverTime = HorizonPlayerValues._timeMillis(data.serverTime)
			_lastErrorCode = ""
			result = {"success": true, "data": data, "errorCode": "", "error": ""}
			if route == "/find": player_found.emit(data.duplicate(true))
			elif mutation: friends_updated.emit(data.duplicate(true))
			else: friends_loaded.emit(data.duplicate(true))
			_syncScope()
			if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	_busy = false
	_request_finished.emit()
	_syncScope()
	if result.success and (scope != _scope or queue_epoch != _queueEpoch): return _fail("STALE_RESPONSE")
	return result

func _normalize(raw: Variant, user_id: String) -> Dictionary:
	if not raw is Dictionary or raw.get("userId") != user_id or not _nonnegative(raw.get("revision")) or not _time(raw.get("serverTime")) or raw.get("friendCode") != _code(user_id) or not raw.get("limits") is Dictionary:
		return {}
	if raw.revision < _revision or HorizonPlayerValues._timeMillis(raw.serverTime) < _serverTime:
		_lastErrorCode = "STALE_RESPONSE"
		return {}
	var limits: Dictionary = {}
	for field: String in ["maxFriends", "maxIncomingRequests", "maxOutgoingRequests", "maxBlocked"]:
		if not _nonnegative(raw.limits.get(field)): return {}
		limits[field] = int(raw.limits[field])
	for limit: int in limits.values():
		if limit < 1 or limit > 2147483647: return {} # Positive Int32 operator configuration.
	var result: Dictionary = {"userId": user_id, "revision": int(raw.revision), "friendCode": raw.friendCode, "limits": limits, "serverTime": raw.serverTime}
	for field: String in ["friends", "incoming", "outgoing", "blocked"]:
		var rows: Variant = raw.get(field)
		if not rows is Array: return {} # Retained relationships survive current-limit reductions.
		var normalized: Array = []
		var seen: Dictionary = {}
		for row: Variant in rows:
			if not row is Dictionary or not _validUuid(row.get("userId")) or row.userId.to_lower() == user_id.to_lower() or seen.has(row.userId.to_lower()): return {}
			seen[row.userId.to_lower()] = true
			var entry: Dictionary = {"userId": row.userId}
			if field == "blocked":
				if not _time(row.get("blockedAt")): return {}
				entry.blockedAt = row.blockedAt
			else:
				var display: Dictionary = _display(row.get("display"))
				if display.is_empty(): return {}
				entry.display = display
				if field == "friends":
					if (row.get("since") != null and not _time(row.since)) or (row.get("lastActiveAt") != null and not _time(row.lastActiveAt)): return {}
					entry.since = row.get("since")
					entry.lastActiveAt = row.get("lastActiveAt")
				else:
					if not _validUuid(row.get("requestId")) or (row.get("createdAt") != null and not _time(row.createdAt)): return {}
					entry.requestId = row.requestId
					entry.createdAt = row.get("createdAt")
			normalized.append(entry)
		result[field] = normalized
	return result

func _normalizePlayer(raw: Variant, query: String) -> Dictionary:
	if not raw is Dictionary or not _validUuid(raw.get("userId")) or raw.get("friendCode") != _code(raw.userId): return {}
	if (_validUuid(query) and raw.userId.to_lower() != query.to_lower()) or (not _validUuid(query) and raw.friendCode != query): return {}
	var display: Dictionary = _display(raw.get("display"))
	if display.is_empty(): return {}
	return {"userId": raw.userId, "friendCode": raw.friendCode, "display": display}

func _display(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw.get("name") != null and not raw.name is String) or not raw.get("profile") is Dictionary: return {}
	var profile: Dictionary = {}
	for field: String in ["avatarId", "frameId"]:
		var id: Variant = raw.profile.get(field)
		if id != null and (not id is String or _profileId.search(id) == null): return {}
		profile[field] = id
	var badges: Variant = raw.profile.get("badges")
	if not badges is Array or badges.size() > 3: return {}
	var seen: Dictionary = {}
	for badge: Variant in badges:
		if not badge is String or _profileId.search(badge) == null or seen.has(badge): return {}
		seen[badge] = true
	profile.badges = badges.duplicate()
	return {"name": raw.get("name"), "profile": profile}

func _code(user_id: String) -> String:
	var hex: String = user_id.replace("-", "")
	var bytes := PackedByteArray()
	for index: int in range(0, 32, 2): bytes.append(hex.substr(index, 2).hex_to_int())
	return "H-" + Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("==")

func _syncScope() -> void:
	var user: HorizonUserData = _auth.getCurrentUser()
	var current: Dictionary = {"user": user.userId if user != null else "", "authToken": user.accessToken if user != null else "", "project": _http.apiKey, "host": _http.activeHost, "token": _http.sessionToken, "generation": _http.getContextGeneration()}
	if current != _scope:
		_reset()
		_scope = current

func _hasSession() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return user != null and _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken

func _playerChanged(_user: HorizonUserData) -> void: _reset()

func _reset() -> void:
	clearCache()
	_scope = {}
	_revision = -1
	_serverTime = -1

func _validUuid(value: Variant) -> bool: return value is String and _uuid.search(value) != null
func _nonnegative(value: Variant) -> bool: return HorizonPlayerValues._safeNumber(value) and value >= 0
func _time(value: Variant) -> bool: return value is String and HorizonPlayerValues._timeMillis(value) >= 0

func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = error if not error.is_empty() else code
	friends_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
