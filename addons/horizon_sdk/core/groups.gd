class_name HorizonGroups
extends RefCounted
## Explicit reviewed group commands. No command receipts, hidden refresh, polling or page loops.
signal groups_loaded(snapshot: Dictionary)
signal groups_updated(snapshot: Dictionary)
signal group_loaded(group: Dictionary)
signal members_loaded(page: Dictionary)
signal pending_loaded(snapshot: Dictionary)
signal groups_failed(error: String, code: String)
signal _request_finished()

const ENDPOINT := "/api/v1/app/groups"
const ROLES := ["leader", "officer", "member"]
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _scope: Dictionary = {}
var _current: Dictionary = {}
var _floors: Dictionary = {}
var _staged: Dictionary = {}
var _fragments: Dictionary = {}
var _revision: int = -1
var _serverTime: int = -1
var _epoch: int = 0
var _queueEpoch: int = 0
var _busy: bool = false
var _lastErrorCode: String = ""
var _uuid: RegEx = RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
var _nonblank: RegEx = RegEx.create_from_string("[^\\s\\p{Z}\\x{001c}-\\x{001f}]")
var _profileId: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,31}\\z")

func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)

func getGroups(user_id: String) -> Dictionary:
	return await _call(user_id, "mine")

func getGroup(user_id: String, group_id: String) -> Dictionary:
	return await _call(user_id, "group", group_id)

func getMembers(user_id: String, group_id: String, after_user_id: String = "", limit: Variant = 50) -> Dictionary:
	if (not after_user_id.is_empty() and not _validUuid(after_user_id)) or typeof(limit) != TYPE_INT or limit < 1 or limit >= 2147483647: return _fail("INVALID_PAGE")
	return await _call(user_id, "members", group_id, {"afterUserId": after_user_id, "limit": limit})

func getPending(user_id: String, group_id: String) -> Dictionary:
	return await _call(user_id, "pending", group_id)

func createGroup(user_id: String, expected_player_revision: Variant, name: String, description: String = "", join_mode: String = "open", data: Variant = {}) -> Dictionary:
	if typeof(expected_player_revision) != TYPE_INT or not _nonnegative(expected_player_revision): return _fail("INVALID_REVISION")
	if not _metadata(name, description, join_mode, data): return _fail("INVALID_GROUP")
	return await _call(user_id, "create", "", {"expectedPlayerRevision": expected_player_revision, "name": name, "description": description, "joinMode": join_mode, "data": HorizonGroupJsonData.fromDictionary(data) if data is Dictionary else data})

func updateGroup(user_id: String, group_id: String, expected_revision: Variant, name: String, description: String, join_mode: String, data: Variant) -> Dictionary:
	if typeof(expected_revision) != TYPE_INT or not _nonnegative(expected_revision): return _fail("INVALID_REVISION")
	if not _metadata(name, description, join_mode, data): return _fail("INVALID_GROUP")
	return await _call(user_id, "update", group_id, {"expectedRevision": expected_revision, "name": name, "description": description, "joinMode": join_mode, "data": HorizonGroupJsonData.fromDictionary(data) if data is Dictionary else data})

func joinGroup(user_id: String, group_id: String, expected_revision: Variant) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "join")
func requestJoin(user_id: String, group_id: String, expected_revision: Variant) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "request")
func invitePlayer(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "invite", target_user_id)
func acceptInvite(user_id: String, group_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "accept-invite", "", request_id)
func declineInvite(user_id: String, group_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "decline-invite", "", request_id)
func cancelInvite(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "cancel-invite", target_user_id, request_id)
func acceptRequest(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "accept-request", target_user_id, request_id)
func declineRequest(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "decline-request", target_user_id, request_id)
func cancelRequest(user_id: String, group_id: String, expected_revision: Variant, request_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "cancel-request", "", request_id)
func leaveGroup(user_id: String, group_id: String, expected_revision: Variant) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "leave")
func removeMember(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "remove", target_user_id)
func setMemberRole(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String, role: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "role", target_user_id, "", role)
func transferLeadership(user_id: String, group_id: String, expected_revision: Variant, target_user_id: String) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "transfer", target_user_id)
func deleteGroup(user_id: String, group_id: String, expected_revision: Variant) -> Dictionary:
	return await _action(user_id, group_id, expected_revision, "delete")

func getCurrentGroups() -> Dictionary:
	_syncScope()
	return _current.duplicate(true) if _hasSession() else {}
func getLastErrorCode() -> String: return _lastErrorCode

## Optional realtime invalidations are hints. Explicit HTTP reads reload content.
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()
func _invalidate() -> void:
	_epoch += 1
	_current.clear()

func _action(user_id: String, group_id: String, revision: Variant, action: String, target: String = "", request_id: String = "", role: String = "") -> Dictionary:
	if typeof(revision) != TYPE_INT or not _nonnegative(revision): return _fail("INVALID_REVISION")
	var targeted: bool = action in ["invite", "cancel-invite", "accept-request", "decline-request", "remove", "role", "transfer"]
	var pending: bool = action in ["accept-invite", "decline-invite", "cancel-invite", "accept-request", "decline-request", "cancel-request"]
	if (targeted and (not _validUuid(target) or target.to_lower() == user_id.to_lower())) or (pending and not _validUuid(request_id)) or (action == "role" and role not in ["officer", "member"]): return _fail("INVALID_GROUP_ACTION")
	var body: Dictionary = {"expectedRevision": revision}
	if targeted: body.targetUserId = target
	if pending: body.requestId = request_id
	if action == "role": body.role = role
	return await _call(user_id, action, group_id, body)

func _call(user_id: String, kind: String, group_id: String = "", payload: Dictionary = {}) -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user_id != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not _validUuid(user_id) or (kind not in ["mine", "create"] and not _validUuid(group_id)): return _fail("INVALID_GROUP_ACTION")
	var scope: Dictionary = _scope.duplicate()
	var queued: int = _queueEpoch
	var body: Dictionary = payload.duplicate(true)
	while _busy: await _request_finished
	_syncScope()
	if scope != _scope or queued != _queueEpoch: return _fail("STALE_RESPONSE")
	_busy = true
	var mutation: bool = kind not in ["mine", "group", "members", "pending"]
	if mutation: _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT
	if kind not in ["mine", "create"]: endpoint += "/" + group_id.uri_encode()
	if kind not in ["mine", "group", "create", "update"]: endpoint += "/" + kind
	var response: HorizonNetworkResponse
	if mutation:
		body.userId = user_id
		var original_json: String = ""
		if body.get("data") is HorizonGroupJsonData:
			var opaque: HorizonGroupJsonData = body.data
			body.erase("data")
			original_json = JSON.stringify(body).trim_suffix("}") + ',"data":' + opaque.getJson() + "}"
			# Telemetry receives a preview; the wire body uses the captured original.
			body.data = opaque.getPreview()
		response = await _http.putOnceAsync(endpoint, body, true, original_json) if kind == "update" else await _http.postJsonOnceAsync(endpoint, body, true, original_json)
	else:
		endpoint += "?userId=" + user_id.uri_encode()
		if kind == "members":
			endpoint += "&limit=" + str(body.limit)
			if not body.afterUserId.is_empty(): endpoint += "&afterUserId=" + body.afterUserId.uri_encode()
		response = await _http.getAsync(endpoint, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch:
		result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode in [401, 403, 404]: _current.clear()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	elif not _wire(response.rawBody):
		result = _fail("INVALID_RESPONSE")
	else:
		_lastErrorCode = "INVALID_RESPONSE"
		_staged = _floors.duplicate()
		_fragments = HorizonGroupJsonData.extract(response.rawBody)
		var data: Dictionary = {} if _fragments.has("_invalid") else _normalize(response.data, kind, user_id, group_id, body)
		_fragments.clear()
		if data.is_empty():
			result = _fail(_lastErrorCode)
		else:
			_floors = _staged.duplicate()
			var own: Dictionary = data.groups if mutation else data
			if mutation or kind == "mine":
				_current = own.duplicate(true)
				_revision = own.revision
			if own.has("serverTime"): _serverTime = maxi(_serverTime, HorizonPlayerValues._timeMillis(own.serverTime))
			_lastErrorCode = ""
			result = {"success": true, "data": data, "errorCode": "", "error": ""}
			if mutation: groups_updated.emit(data.duplicate(true))
			elif kind == "mine": groups_loaded.emit(data.duplicate(true))
			elif kind == "group": group_loaded.emit(data.duplicate(true))
			elif kind == "members": members_loaded.emit(data.duplicate(true))
			else: pending_loaded.emit(data.duplicate(true))
			_syncScope()
			if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	_busy = false
	_request_finished.emit()
	_syncScope()
	if result.success and (scope != _scope or queued != _queueEpoch): return _fail("STALE_RESPONSE")
	return result

func _normalize(raw: Variant, kind: String, user: String, group_id: String, query: Dictionary) -> Dictionary:
	if not raw is Dictionary: return {}
	if kind == "mine": return _mine(raw, user)
	if kind == "group": return _group(raw, user, group_id)
	if kind == "members": return _members(raw, group_id, query)
	if kind == "pending": return _pending(raw, group_id)
	var own: Dictionary = _mine(raw.get("groups"), user)
	if own.is_empty() or not raw.has("group"): return {}
	var group: Variant = raw.group
	if group == null and kind not in ["leave", "delete"]: return {}
	if group != null:
		group = _group(group, user, "" if kind == "create" else group_id)
		if group.is_empty(): return {}
	return {"groups": own, "group": group}

func _mine(raw: Variant, user: String) -> Dictionary:
	if not raw is Dictionary or raw.get("userId") != user or not _nonnegative(raw.get("revision")) or not _stamp(raw.get("serverTime")) or not raw.get("limits") is Dictionary: return {}
	if raw.revision < _revision: return _stale()
	var limits: Dictionary = {}
	for field: String in ["maxMembers", "maxGroupsPerPlayer", "maxInvitations", "maxJoinRequests", "maxDataBytes", "memberPageSize", "maxPlayerInvitations", "maxPlayerRequests", "maxNameBytes", "maxDescriptionBytes", "maxDataDepth"]:
		if not _nonnegative(raw.limits.get(field)) or raw.limits[field] < 1 or raw.limits[field] > 2147483647: return {}
		limits[field] = int(raw.limits[field])
	if not raw.get("groups") is Array: return {}
	var result: Dictionary = {"userId": user, "revision": int(raw.revision), "limits": limits, "groups": [], "serverTime": raw.serverTime}
	var seen: Dictionary = {}
	for entry: Variant in raw.groups:
		var group: Dictionary = _group(entry, user)
		if group.is_empty() or not group.has("myRole") or seen.has(group.id.to_lower()): return {}
		seen[group.id.to_lower()] = true
		result.groups.append(group)
	for field: String in ["incomingInvites", "outgoingRequests"]:
		var rows: Variant = raw.get(field)
		if not rows is Array: return {}
		result[field] = []
		for row: Variant in rows:
			if not row is Dictionary or not _validUuid(row.get("groupId")) or not _validUuid(row.get("requestId")) or not _validUuid(row.get("issuerId")) or (row.get("createdAt") != null and not _time(row.createdAt)) or seen.has(row.groupId.to_lower()) or not row.has("group"): return {}
			seen[row.groupId.to_lower()] = true
			var public: Variant = row.group
			if public != null:
				public = _group(public, user, row.groupId, false)
				if public.is_empty(): return {}
			result[field].append({"groupId": row.groupId, "requestId": row.requestId, "issuerId": row.issuerId, "createdAt": row.get("createdAt"), "group": public})
	return result

func _group(raw: Variant, user: String, expected: String = "", private_allowed: bool = true) -> Dictionary:
	if not raw is Dictionary or not _validUuid(raw.get("id")) or (not expected.is_empty() and raw.id.to_lower() != expected.to_lower()) or not _nonnegative(raw.get("revision")) or not _nonnegative(raw.get("memberCount")) or raw.memberCount < 1 or raw.memberCount > 2147483647 or not _validUuid(raw.get("leaderId")) or not _time(raw.get("createdAt")) or not _time(raw.get("updatedAt")): return {}
	if not _metadata(raw.get("name"), raw.get("description"), raw.get("joinMode"), {}): return {}
	var key: String = raw.id.to_lower()
	if raw.revision < _staged.get(key, -1): return _stale()
	_staged[key] = int(raw.revision)
	var result: Dictionary = {}
	for field: String in ["id", "name", "description", "joinMode", "leaderId", "createdAt", "updatedAt"]: result[field] = raw[field]
	result.revision = int(raw.revision)
	result.memberCount = int(raw.memberCount)
	if private_allowed and raw.get("myRole") != null:
		if raw.myRole not in ROLES or (raw.myRole == "leader") != (raw.leaderId.to_lower() == user.to_lower()) or not raw.get("data") is Dictionary or not _fragments.has(key): return {}
		var original: HorizonGroupJsonData = HorizonGroupJsonData.fromJson(_fragments[key])
		if original == null: return {}
		result.myRole = raw.myRole
		result.data = original
	return result

func _members(raw: Dictionary, group_id: String, query: Dictionary) -> Dictionary:
	if not _pageHeader(raw, group_id) or not raw.get("members") is Array or raw.members.size() > query.limit or not raw.has("nextAfterUserId"): return {}
	var entries: Array = []
	var previous: String = query.afterUserId.to_lower()
	for row: Variant in raw.members:
		if not row is Dictionary or not _validUuid(row.get("userId")) or row.userId.to_lower() <= previous or row.get("role") not in ROLES or not _time(row.get("joinedAt")): return {}
		var display: Dictionary = _display(row.get("display"))
		if display.is_empty(): return {}
		entries.append({"userId": row.userId, "role": row.role, "joinedAt": row.joinedAt, "display": display})
		previous = row.userId.to_lower()
	var after: Variant = raw.nextAfterUserId
	if after != null and (not _validUuid(after) or entries.size() != query.limit or after.to_lower() != previous): return {}
	return {"groupId": raw.groupId, "revision": int(raw.revision), "members": entries, "nextAfterUserId": after, "serverTime": raw.serverTime}

func _pending(raw: Dictionary, group_id: String) -> Dictionary:
	if not _pageHeader(raw, group_id): return {}
	var result: Dictionary = {"groupId": raw.groupId, "revision": int(raw.revision), "serverTime": raw.serverTime}
	var seen: Dictionary = {}
	for field: String in ["invitations", "joinRequests"]:
		var rows: Variant = raw.get(field)
		if not rows is Array: return {}
		result[field] = []
		for row: Variant in rows:
			if not row is Dictionary or not _validUuid(row.get("userId")) or not _validUuid(row.get("requestId")) or not _validUuid(row.get("issuerId")) or (row.get("createdAt") != null and not _time(row.createdAt)) or seen.has(row.userId.to_lower()): return {}
			seen[row.userId.to_lower()] = true
			result[field].append({"userId": row.userId, "requestId": row.requestId, "issuerId": row.issuerId, "createdAt": row.get("createdAt")})
	return result

func _pageHeader(raw: Dictionary, group_id: String) -> bool:
	if not _validUuid(raw.get("groupId")) or raw.groupId.to_lower() != group_id.to_lower() or not _nonnegative(raw.get("revision")) or not _stamp(raw.get("serverTime")): return false
	var key: String = group_id.to_lower()
	if raw.revision < _staged.get(key, -1):
		_stale()
		return false
	_staged[key] = int(raw.revision)
	return true

func _display(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw.get("name") != null and not raw.name is String) or not raw.get("profile") is Dictionary: return {}
	var profile: Dictionary = {}
	for field: String in ["avatarId", "frameId"]:
		var value: Variant = raw.profile.get(field)
		if value != null and (not value is String or _profileId.search(value) == null): return {}
		profile[field] = value
	var badges: Variant = raw.profile.get("badges")
	if not badges is Array or badges.size() > 3: return {}
	var seen: Dictionary = {}
	for badge: Variant in badges:
		if not badge is String or _profileId.search(badge) == null or seen.has(badge): return {}
		seen[badge] = true
	profile.badges = badges.duplicate()
	return {"name": raw.get("name"), "profile": profile}

func _metadata(name: Variant, description: Variant, mode: Variant, data: Variant) -> bool:
	if not name is String or _nonblank.search(name) == null or not description is String or mode not in ["open", "request", "invite"]: return false
	if data is HorizonGroupJsonData: return data.isValid()
	return data is Dictionary and HorizonGroupJsonData.fromDictionary(data) != null

func _jsonValue(value: Variant, depth: int) -> bool:
	return HorizonGroupJsonData.isJsonValue(value, depth)

## Protocol counters require original integer lexemes. Arbitrary group data permits
## finite JSON numbers, including keys named revision; do not apply counter rules there.
func _wire(json: String) -> bool:
	if not HorizonPlayerValues._safeJsonIntegers(json, []): return false
	var tokens: RegEx = RegEx.create_from_string('"(?:[^"\\\\]++|\\\\.)*+"|[{}\\[\\]:,]|true|false|null|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
	var matches: Array[RegExMatch] = tokens.search_all(json)
	var stack: Array[bool] = []
	var data_next: bool = false
	for index: int in range(matches.size()):
		var text: String = matches[index].get_string()
		if text in ["{", "["]:
			stack.append(data_next or (not stack.is_empty() and stack.back()))
			data_next = false
		elif text in ["}", "]"]:
			if stack.is_empty(): return false
			stack.pop_back()
		elif text.begins_with('"') and index + 1 < matches.size() and matches[index + 1].get_string() == ":":
			data_next = JSON.parse_string(text) == "data"
		elif text not in [":", ","]:
			if not text.begins_with('"') and text not in ["true", "false", "null"] and not (data_next or (not stack.is_empty() and stack.back())):
				if not text.is_valid_int() or text.length() > 17 or not HorizonPlayerValues._safeNumber(int(text)): return false
			data_next = false
	return stack.is_empty()

func _stamp(value: Variant) -> bool:
	if not _time(value): return false
	if HorizonPlayerValues._timeMillis(value) < _serverTime:
		_stale()
		return false
	return true
func _stale() -> Dictionary:
	_lastErrorCode = "STALE_RESPONSE"
	return {}
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
	_floors.clear()
	_staged.clear()
	_fragments.clear()
	_revision = -1
	_serverTime = -1
func _validUuid(value: Variant) -> bool: return value is String and _uuid.search(value) != null
func _nonnegative(value: Variant) -> bool: return HorizonPlayerValues._safeNumber(value) and value >= 0
func _time(value: Variant) -> bool: return value is String and HorizonPlayerValues._timeMillis(value) >= 0
func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = error if not error.is_empty() else code
	groups_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
