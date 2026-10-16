class_name HorizonAchievements
extends RefCounted
## Server-owned permanent unlocks and pending Inbox rewards. No polling or local value grants.

signal achievements_loaded(snapshot: Dictionary)
signal achievements_updated(snapshot: Dictionary)
signal achievements_unlocked(keys: Array)
signal achievements_failed(error: String, code: String)
signal _request_finished()

const ENDPOINT := "/api/v1/app/achievements"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _inbox: HorizonInbox
var _scope: Dictionary = {}
var _current: Dictionary = {}
var _epoch: int = 0
var _queueEpoch: int = 0
var _revision: int = -1
var _serverTime: int = -1
var _busy: bool = false
var _lastErrorCode: String = ""
var _key: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,23}\\z")
var _version: RegEx = RegEx.create_from_string("^[0-9a-f]{64}\\z")

func initialize(http: HorizonHttpClient, auth: HorizonAuth, inbox: HorizonInbox = null, statistics: HorizonStatistics = null) -> void:
	_http = http
	_auth = auth
	_inbox = inbox
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)
	if statistics != null:
		statistics.statistics_updated.connect(_statisticsChanged)

## Conditional metadata is sent only when this manager owns its matching player cache.
func getAchievements(user_id: String, definition_version: String = "") -> Dictionary:
	if not definition_version.is_empty() and _version.search(definition_version) == null:
		return _fail("INVALID_REQUEST")
	return await _call(user_id, "", {}, definition_version)

## Keep the original key on timeout. The server's permanent guard makes this repeat safe.
func unlock(user_id: String, key: String) -> Dictionary:
	if not _validKey(key): return _fail("INVALID_REQUEST")
	return await _call(user_id, "/unlock", {"key": key})

## Explicit bounded drain; failures retain the server's immutable original pending intent.
func deliverRewards(user_id: String, keys: Array) -> Dictionary:
	if keys.is_empty() or keys.size() > 8: return _fail("INVALID_REQUEST")
	var unique: Dictionary = {}
	for key: Variant in keys:
		if not _validKey(key) or unique.has(key): return _fail("INVALID_REQUEST")
		unique[key] = true
	return await _call(user_id, "/rewards/deliver", {"keys": keys.duplicate(true)})

func getCurrentAchievements() -> Dictionary:
	_syncScope()
	return _current.duplicate(true) if _hasSession() else {}

func getLastErrorCode() -> String:
	return _lastErrorCode

## Invalidate hidden metadata/in-flight work but keep freshness floors for the same identity.
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()

func _invalidate() -> void:
	_epoch += 1
	_current.clear()

func _call(user_id: String, route: String, payload: Dictionary, version_hint: String = "") -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user_id != _scope.user: return _fail("SESSION_FORBIDDEN")
	var scope: Dictionary = _scope.duplicate()
	var queue_epoch: int = _queueEpoch
	while _busy:
		await _request_finished
	_syncScope()
	if scope != _scope or queue_epoch != _queueEpoch: return _fail("STALE_RESPONSE")
	_busy = true
	var sent_version: String = ""
	if route.is_empty() and not _current.is_empty() and (version_hint.is_empty() or version_hint == _current.definitionVersion):
		sent_version = _current.definitionVersion
	if not route.is_empty(): _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT + "?userId=" + user_id.uri_encode()
	if not sent_version.is_empty(): endpoint += "&definitionVersion=" + sent_version
	var body: Dictionary = payload.duplicate(true)
	body.userId = user_id
	var response: HorizonNetworkResponse = await _http.getAsync(endpoint, true) if route.is_empty() else await _http.postAsync(ENDPOINT + route, body, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch:
		result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401: clearCache()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	elif not HorizonInbox._safeJson(response.rawBody) or not HorizonPlayerValues._safeJsonIntegers(response.rawBody, ["revision", "threshold", "maxDefinitions", "maxLifetimeKeys", "amount"]):
		result = _fail("INVALID_RESPONSE")
	else:
		result = _consume(response.data, user_id, route, body, sent_version)
		if result.success:
			if not route.is_empty() and _inbox != null:
				for outcome: Dictionary in result.data.get("deliveryResults", result.data.get("results", [])):
					if outcome.state == "delivered":
						_inbox.clearCache()
						break
			if route.is_empty(): achievements_loaded.emit(result.data.duplicate(true))
			else: achievements_updated.emit(result.data.achievements.duplicate(true))
			_syncScope()
			if scope != _scope or epoch != _epoch:
				result = _fail("STALE_RESPONSE")
			elif not route.is_empty() and not result.data.get("newlyUnlocked", []).is_empty():
				achievements_unlocked.emit(result.data.newlyUnlocked.duplicate())
				_syncScope()
				if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	_busy = false
	_request_finished.emit()
	# Releasing a waiter may synchronously start HTTP and run its credential/cache handlers.
	# A queued mutation's own invalidation is allowed; an external clear or identity change is not.
	_syncScope()
	if result.success and (scope != _scope or queue_epoch != _queueEpoch):
		return _fail("STALE_RESPONSE")
	return result

## Validate the complete outer response before changing any cache or watermark.
func _consume(raw: Variant, user_id: String, route: String, body: Dictionary, sent_version: String) -> Dictionary:
	_lastErrorCode = "INVALID_RESPONSE"
	if not raw is Dictionary: return _fail("INVALID_RESPONSE")
	var snapshot: Dictionary = _normalize(raw if route.is_empty() else raw.get("achievements"), user_id, sent_version)
	if snapshot.is_empty(): return _fail(_lastErrorCode)
	var data: Dictionary = snapshot
	if not route.is_empty():
		data = raw.duplicate(true)
		data.achievements = snapshot
		var requested: Array = [body.key] if route == "/unlock" else body.keys
		var outcomes: Variant = _outcomes(raw.get("deliveryResults") if route == "/unlock" else raw.get("results"), requested)
		if outcomes == null: return _fail("INVALID_RESPONSE")
		if route == "/unlock":
			if typeof(raw.get("replayed")) != TYPE_BOOL or not raw.get("newlyUnlocked") is Array:
				return _fail("INVALID_RESPONSE")
			if raw.newlyUnlocked != ([] if raw.replayed else [body.key]): return _fail("INVALID_RESPONSE")
			var unlocked: bool = false
			for progress: Dictionary in snapshot.progress:
				if progress.key == body.key: unlocked = true
			if not unlocked: return _fail("INVALID_RESPONSE")
			data.deliveryResults = outcomes
		else:
			data.results = outcomes
	_current = snapshot.duplicate(true)
	_revision = snapshot.revision
	_serverTime = HorizonPlayerValues._timeMillis(snapshot.serverTime)
	_lastErrorCode = ""
	return {"success": true, "data": data, "errorCode": "", "error": ""}

func _normalize(raw: Variant, user_id: String, sent_version: String) -> Dictionary:
	if not raw is Dictionary or raw.get("userId") != user_id or not raw.has("definitions") or not _nonnegative(raw.get("revision")) or not raw.get("definitionVersion") is String or _version.search(raw.definitionVersion) == null or not _time(raw.get("serverTime")):
		return {}
	if raw.revision < _revision or HorizonPlayerValues._timeMillis(raw.serverTime) < _serverTime:
		_lastErrorCode = "STALE_RESPONSE"
		return {}
	if not raw.get("progress") is Array or raw.progress.size() > 500 or not raw.get("limits") is Dictionary:
		return {}
	for field: String in ["maxDefinitions", "maxLifetimeKeys"]:
		if not _nonnegative(raw.limits.get(field)): return {}
	if raw.limits.maxDefinitions > 250 or raw.limits.maxLifetimeKeys < 1 or raw.limits.maxLifetimeKeys > 500: return {}
	var progress: Array = []
	var unlocked: Dictionary = {}
	for item: Variant in raw.progress:
		if not item is Dictionary or not _validKey(item.get("key")) or unlocked.has(item.key) or not _time(item.get("unlockedAt")) or not item.get("rewardState") in ["none", "pending", "delivered"]: return {}
		unlocked[item.key] = true
		var entry_id: Variant = item.get("inboxEntryId")
		var pending: Variant = item.get("pendingReward")
		if entry_id != null and not HorizonInbox._validEntryId(entry_id): return {}
		if item.rewardState == "delivered" and entry_id == null: return {}
		if item.rewardState != "delivered" and entry_id != null: return {}
		if item.rewardState == "pending":
			if not pending is Dictionary or not _time(pending.get("issuedAt")): return {}
			var amounts: Variant = _amounts(pending.get("values"))
			if amounts == null or amounts.is_empty(): return {}
			pending = {"issuedAt": pending.issuedAt, "values": amounts}
		elif pending != null:
			return {}
		progress.append({"key": item.key, "unlockedAt": item.unlockedAt, "rewardState": item.rewardState, "inboxEntryId": entry_id, "pendingReward": pending})
	var definitions: Variant = raw.get("definitions")
	if definitions == null:
		if sent_version.is_empty() or _current.is_empty() or raw.definitionVersion != sent_version or _current.definitionVersion != sent_version or raw.revision != _current.revision: return {}
		definitions = _current.definitions.duplicate(true)
	if not definitions is Array or definitions.size() > 250: return {}
	var normalized: Array = []
	var keys: Dictionary = {}
	for definition: Variant in definitions:
		var parsed: Dictionary = _definition(definition)
		if parsed.is_empty() or keys.has(parsed.key) or (parsed.hidden and not unlocked.has(parsed.key)): return {}
		keys[parsed.key] = true
		normalized.append(parsed)
	return {"userId": user_id, "revision": int(raw.revision), "definitionVersion": raw.definitionVersion, "definitions": normalized, "progress": progress, "limits": {"maxDefinitions": int(raw.limits.maxDefinitions), "maxLifetimeKeys": int(raw.limits.maxLifetimeKeys)}, "serverTime": raw.serverTime}

func _definition(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _validKey(raw.get("key")) or not raw.get("name") is String or raw.name.is_empty() or raw.name.to_utf8_buffer().size() > 120 or not raw.get("description") is String or raw.description.to_utf8_buffer().size() > 512 or typeof(raw.get("hidden")) != TYPE_BOOL or typeof(raw.get("active")) != TYPE_BOOL or not raw.get("mode") in ["manual", "statistic"]: return {}
	var image: Variant = raw.get("imageUrl")
	if image != null and (not image is String or image.length() > 2048 or not (image.to_lower().begins_with("http://") or image.to_lower().begins_with("https://"))): return {}
	var condition: Variant = raw.get("condition")
	if raw.mode == "statistic":
		if not condition is Dictionary or not _validKey(condition.get("statisticKey")) or not _nonnegative(condition.get("threshold")): return {}
		condition = {"statisticKey": condition.statisticKey, "threshold": int(condition.threshold)}
	elif condition != null:
		return {}
	if not raw.get("rewards") is Dictionary: return {}
	var rewards: Variant = _amounts(raw.rewards.get("values"))
	if rewards == null: return {}
	return {"key": raw.key, "name": raw.name, "description": raw.description, "imageUrl": image, "hidden": raw.hidden, "active": raw.active, "mode": raw.mode, "condition": condition, "rewards": {"values": rewards}}

func _amounts(raw: Variant) -> Variant:
	if not raw is Array or raw.size() > 8: return null
	var values: Array = []
	var keys: Dictionary = {}
	for value: Variant in raw:
		if not value is Dictionary or not _validKey(value.get("key")) or keys.has(value.key) or not _nonnegative(value.get("amount")) or value.amount == 0: return null
		keys[value.key] = true
		values.append({"key": value.key, "amount": int(value.amount)})
	return values

func _outcomes(raw: Variant, requested: Array) -> Variant:
	if not raw is Array or raw.size() != requested.size(): return null
	var seen: Dictionary = {}
	var outcomes: Array = []
	for item: Variant in raw:
		if not item is Dictionary or not item.get("key") in requested or seen.has(item.key) or not item.get("state") in ["none", "pending", "delivered"]: return null
		seen[item.key] = true
		var entry: Variant = item.get("inboxEntryId")
		var code: Variant = item.get("code")
		if entry != null and not HorizonInbox._validEntryId(entry): return null
		if (item.state == "delivered" and entry == null) or (item.state != "delivered" and entry != null): return null
		if code != null and (not code is String or code.length() > 128): return null
		outcomes.append({"key": item.key, "state": item.state, "inboxEntryId": entry, "code": code})
	return outcomes

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

func _statisticsChanged(snapshot: Dictionary) -> void:
	if snapshot.get("newlyUnlocked") is Array and not snapshot.newlyUnlocked.is_empty() and not snapshot.get("replayed", false):
		clearCache()

func _validKey(value: Variant) -> bool: return value is String and _key.search(value) != null
func _nonnegative(value: Variant) -> bool: return HorizonPlayerValues._safeNumber(value) and value >= 0
func _time(value: Variant) -> bool: return value is String and HorizonPlayerValues._timeMillis(value) >= 0

func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = error if not error.is_empty() else code
	achievements_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
