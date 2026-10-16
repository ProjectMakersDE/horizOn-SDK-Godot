class_name HorizonChat
extends Node
## Six REST methods plus explicit subscriptions. Only push/resync initiates feed reads.
signal channel_changed(channel_id: String, snapshot: Dictionary)
signal channel_hidden(channel_id: String)
signal chat_failed(error: String, code: String)
const ENDPOINT := "/api/v1/app/chat"
const MAX_WATCHES := 8
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _realtime: HorizonRealtime
var _scope: Dictionary = {}
var _watches: Dictionary = {}
var _cache: Dictionary = {}
var _floors: Dictionary = {}
var _serial: int = 0
var _clearing: bool = false
var _serverMillis: int = -1
var _clockMillis: int = -1
var _clockTicks: int = 0
var _nowMillis: Callable = func() -> int: return Time.get_ticks_msec()
func initialize(http: HorizonHttpClient, auth: HorizonAuth, realtime: HorizonRealtime) -> void:
	_http = http
	_auth = auth
	_realtime = realtime
	_auth.signout_completed.connect(clearCache)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)
	_realtime.event_received.connect(_event)
	_realtime.resync_required.connect(_resync)
	_realtime.connection_error.connect(_disconnected)
	_realtime.subscription_failed.connect(_subscriptionDenied)
func getLimits(user_id: String) -> Dictionary: return await _request(user_id, "limits")
func openChannel(user_id: String, kind: String, peer_id: String = "", group_id: String = "") -> Dictionary:
	var options: Dictionary = {"kind": kind}
	match kind:
		"direct":
			if not HorizonChatModels.uuid(peer_id) or peer_id == user_id or not group_id.is_empty(): return _fail("INVALID_REQUEST")
			options.peerId = peer_id
		"group":
			if not HorizonChatModels.uuid(group_id) or not peer_id.is_empty(): return _fail("INVALID_REQUEST")
			options.groupId = group_id
		"project":
			if not peer_id.is_empty() or not group_id.is_empty(): return _fail("INVALID_REQUEST")
		_: return _fail("INVALID_REQUEST")
	return await _request(user_id, "open", "", options)
func sendMessage(user_id: String, channel_id: String, operation_id: String, issued_at: String, text: String) -> Dictionary:
	if not HorizonChatModels.uuid(channel_id) or not HorizonChatModels.uuid(operation_id) or not HorizonChatModels.time(issued_at) or not HorizonChatModels.text(text): return _fail("INVALID_REQUEST")
	return await _request(user_id, "send", channel_id, {"operationId": operation_id, "issuedAt": issued_at, "text": text})
func getOperation(user_id: String, operation_id: String) -> Dictionary:
	if not HorizonChatModels.uuid(operation_id): return _fail("INVALID_REQUEST")
	return await _request(user_id, "operation", "", {"operationId": operation_id})
func reportMessage(user_id: String, channel_id: String, message_id: String, reason: String) -> Dictionary:
	if not HorizonChatModels.uuid(channel_id) or not HorizonChatModels.uuid(message_id) or not HorizonChatModels.text(reason, 240, 960): return _fail("INVALID_REQUEST")
	return await _request(user_id, "report", channel_id, {"messageId": message_id, "reason": reason})
## Subscribe before the first snapshot. Watch capacity never silently evicts another feed.
func watchChannel(user_id: String, channel_id: String, owner: String = "") -> bool:
	if _clearing: return false
	_syncScope()
	if not _authorized(user_id) or not HorizonChatModels.uuid(channel_id) or owner.length() > 64: return false
	if _watches.has(channel_id):
		if _watches[channel_id].owners.size() >= 32 and not _watches[channel_id].owners.has(owner): return false
		if not _realtime.subscribe("chat:" + channel_id): return false
		_watches[channel_id].owners[owner] = true
		return true
	if _watches.size() >= MAX_WATCHES or not _realtime.subscribe("chat:" + channel_id): return false
	_serial += 1
	var owners: Dictionary = {}; owners[owner] = true
	_watches[channel_id] = {"user": user_id, "serial": _serial, "authorization": 0, "syncing": false, "dirty": false, "owners": owners}
	return true
func stopWatching(channel_id: String, owner: String = "") -> void:
	if not _watches.has(channel_id): return
	_watches[channel_id].owners.erase(owner)
	if _watches[channel_id].owners.is_empty(): _stop(channel_id)
func _stop(channel_id: String) -> void:
	_watches.erase(channel_id)
	_realtime.unsubscribe("chat:" + channel_id)
	_hide(channel_id)
	_floors.erase(channel_id)
func clearCache() -> void:
	if _clearing: return
	_clearing = true
	for id: String in _watches.keys(): _stop(id)
	_scope.clear()
	_serverMillis = -1
	_clockMillis = -1
	_clearing = false
func getCached(channel_id: String) -> Dictionary:
	_syncScope()
	_prune(channel_id)
	return _cache.get(channel_id, {}).duplicate(true) if _available(channel_id) else {}
func getServerTime() -> String:
	_syncScope()
	return "" if _clockMillis < 0 else HorizonChatModels.stamp(_effectiveMillis())
## One explicit raw REST read, including disconnected capability checks. Never adopts a feed.
## Empty epoch encodes null. Known IDs describe only the caller's original complete snapshot.
func requestChannelSnapshot(user_id: String, channel_id: String, epoch: String = "", known_message_ids: Array[String] = []) -> Dictionary:
	if not HorizonChatModels.uuid(channel_id) or (not epoch.is_empty() and not HorizonChatModels.uuid(epoch)) or not HorizonChatModels.ids(known_message_ids): return _fail("INVALID_REQUEST")
	var original: Dictionary = {"epoch": null if epoch.is_empty() else epoch, "knownMessageIds": known_message_ids.duplicate()}
	var result: Dictionary = await _request(user_id, "sync", channel_id, original, true)
	result.erase("_httpStatus")
	if not result.success: return result
	var known: Array = original.knownMessageIds if original.epoch == result.data.channel.epoch else []
	var returned: Dictionary = {}
	for row: Dictionary in result.data.messages:
		if row.id in known: return _fail("INVALID_RESPONSE")
		returned[row.id] = true
	for id: String in result.data.visibleMessageIds:
		if not returned.has(id) and id not in known: return _fail("INVALID_RESPONSE")
	return result
## Explicit read is allowed only on an acknowledged current subscription, never offline fallback.
func syncChannel(user_id: String, channel_id: String) -> Dictionary:
	_syncScope()
	if not _authorized(user_id): return _fail("SESSION_REQUIRED" if not _session() else "SESSION_FORBIDDEN")
	if not _available(channel_id) or _watches[channel_id].user != user_id: return _fail("SUBSCRIPTION_REQUIRED")
	if _watches[channel_id].syncing: return _fail("SYNC_IN_PROGRESS")
	var watch: Dictionary = _watches[channel_id]
	watch.syncing = true
	watch.dirty = false
	var serial: int = watch.serial
	var authorization: int = watch.authorization
	_prune(channel_id)
	var original: Dictionary = _cache.get(channel_id, {}).duplicate(true)
	var options: Dictionary = {"epoch": original.channel.epoch if not original.is_empty() else null, "knownMessageIds": original.visibleMessageIds.duplicate() if not original.is_empty() else []}
	var result: Dictionary = await _request(user_id, "sync", channel_id, options)
	if not _watches.has(channel_id) or _watches[channel_id].serial != serial: return _fail("STALE_RESPONSE")
	watch = _watches[channel_id]
	if authorization != watch.authorization or not _available(channel_id): result = _fail("STALE_RESPONSE")
	elif result.success:
		var complete: Dictionary = _merge(channel_id, result.data, original)
		if complete.is_empty(): _hide(channel_id); result = _fail("INVALID_RESPONSE")
		else:
			_cache[channel_id] = complete
			_record(channel_id, complete)
			result.data = complete.duplicate(true)
			channel_changed.emit(channel_id, complete.duplicate(true))
			_syncScope()
			if not _watches.has(channel_id) or _watches[channel_id].serial != serial or authorization != _watches[channel_id].authorization or not _available(channel_id): result = _fail("STALE_RESPONSE")
	else:
		var status: int = result.get("_httpStatus", 0)
		if status == 401: clearCache()
		elif status in [403, 404]: _stop(channel_id)
		else: _hide(channel_id)
		result = _fail(result.errorCode, result.error)
	if _watches.has(channel_id) and _watches[channel_id].serial == serial:
		_watches[channel_id].syncing = false
		if _watches[channel_id].dirty and _available(channel_id): _drain.call_deferred(channel_id, serial)
	return result
func _request(user: String, kind: String, id: String = "", options: Dictionary = {}, raw_snapshot: bool = false) -> Dictionary:
	_syncScope()
	if not _session(): return _fail("SESSION_REQUIRED")
	if not _authorized(user): return _fail("SESSION_FORBIDDEN")
	if not HorizonChatModels.uuid(user): return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var watched: Dictionary = _watchBinding(id)
	var payload: Dictionary = options.duplicate(true)
	var path: String = ENDPOINT
	match kind:
		"limits": path += "/limits?userId=" + user
		"operation": path += "/operations/" + options.operationId + "?userId=" + user
		"open": path += "/channels/open"
		"sync": path += "/channels/" + id + "/sync"
		"send": path += "/channels/" + id + "/messages"
		"report":
			path += "/channels/" + id + "/messages/" + options.messageId + "/report"
			payload.erase("messageId")
	var response: HorizonNetworkResponse
	if kind in ["limits", "operation"]: response = await _http.getAsync(path, true)
	else:
		payload.userId = user
		var raw: String = HorizonSharedObjectModels.encode(payload)
		response = await _http.postJsonAsync(path, payload, true, raw) if kind == "sync" and not raw_snapshot else await _http.postJsonOnceAsync(path, payload, true, raw)
	_syncScope()
	if scope != _scope: return _fail("STALE_RESPONSE")
	if not response.isSuccess:
		var code: String = HorizonInbox._responseCode(response)
		if kind != "sync" or raw_snapshot:
			if response.statusCode == 401: clearCache()
			elif response.statusCode in [403, 404] and not id.is_empty():
				if watched != _watchBinding(id): return _fail("STALE_RESPONSE")
				if code not in ["CHAT_MUTED", "MESSAGE_NOT_FOUND"]: _stop(id)
		return _requestFailure(kind, code, response.error, response.statusCode)
	var data: Dictionary = HorizonChatModels.envelope(response.rawBody, kind, user, id, options)
	if data.is_empty(): return _requestFailure(kind, "INVALID_RESPONSE")
	if raw_snapshot: return {"success": true, "data": data, "errorCode": "", "error": ""}
	var server: int = HorizonChatModels.millis(data.serverTime)
	if server < _serverMillis: return _requestFailure(kind, "STALE_RESPONSE")
	_clockMillis = maxi(server, _effectiveMillis())
	_clockTicks = int(_nowMillis.call())
	_serverMillis = server
	return {"success": true, "data": data, "errorCode": "", "error": ""}
func _merge(id: String, data: Dictionary, previous: Dictionary) -> Dictionary:
	var row: Dictionary = data.channel
	var floor: Dictionary = _floors.get(id, {})
	if not floor.is_empty():
		if HorizonChatModels.millis(data.serverTime) < floor.time or row.epoch in floor.retired or (row.epoch == floor.epoch and row.revision < floor.revision): return {}
	var known: Dictionary = {}
	if not previous.is_empty() and previous.channel.epoch == row.epoch:
		for message: Dictionary in previous.messages: known[message.id] = message.duplicate(true)
	var returned: Dictionary = {}
	for message: Dictionary in data.messages:
		if known.has(message.id): return {}
		returned[message.id] = message.duplicate(true)
	var messages: Array = []
	var visible: Array = []
	var cutoff: int = maxi(HorizonChatModels.millis(data.serverTime), _effectiveMillis())
	if HorizonChatModels.millis(row.expiresAt) <= cutoff: return {}
	for message_id: String in data.visibleMessageIds:
		if not returned.has(message_id) and not known.has(message_id): return {}
		var message: Dictionary = returned[message_id] if returned.has(message_id) else known[message_id]
		if HorizonChatModels.millis(message.expiresAt) <= HorizonChatModels.millis(data.serverTime): return {}
		if HorizonChatModels.millis(message.expiresAt) > cutoff: messages.append(message); visible.append(message_id)
	var result: Dictionary = data.duplicate(true)
	result.messages = messages
	result.visibleMessageIds = visible
	return result
func _record(id: String, data: Dictionary) -> void:
	var row: Dictionary = data.channel
	var retired: Array = _floors.get(id, {}).get("retired", []).duplicate()
	if _floors.has(id) and _floors[id].epoch != row.epoch:
		retired.append(_floors[id].epoch)
		while retired.size() > 16: retired.pop_front()
	_floors[id] = {"epoch": row.epoch, "revision": row.revision, "time": HorizonChatModels.millis(data.serverTime), "retired": retired}
func _event(event: Dictionary) -> void:
	var topic: String = str(event.get("topic", ""))
	if topic.begins_with("chat:") and _available(topic.trim_prefix("chat:")): _queue(topic.trim_prefix("chat:"))
func _resync(topic: String) -> void:
	if not topic.begins_with("chat:"): return
	var id: String = topic.trim_prefix("chat:")
	if not _watches.has(id): return
	_hide(id)
	if _available(id): _queue(id)
func _disconnected(_code: String) -> void:
	if _code == "SUBSCRIPTION_FORBIDDEN" and _realtime.isReady: return
	for id: String in _watches.keys(): _hide(id)
func _subscriptionDenied(topic: String, _code: String) -> void:
	if topic.begins_with("chat:"): _hide(topic.trim_prefix("chat:"))
func _watchBinding(id: String) -> Dictionary:
	return {"serial": _watches[id].serial, "authorization": _watches[id].authorization} if _watches.has(id) else {}
func _hide(id: String) -> void:
	_cache.erase(id)
	if _watches.has(id): _watches[id].authorization += 1
	channel_hidden.emit(id)
func _queue(id: String) -> void:
	if not _watches.has(id): return
	_watches[id].dirty = true
	if not _watches[id].syncing: _drain.call_deferred(id, _watches[id].serial)
func _drain(id: String, serial: int) -> void:
	if _watches.has(id) and _watches[id].serial == serial and _watches[id].dirty and not _watches[id].syncing and _available(id): await syncChannel(_watches[id].user, id)
func _available(id: String) -> bool: return _watches.has(id) and _realtime.isSubscribed("chat:" + id)
func _prune(id: String) -> void:
	if not _cache.has(id): return
	var now: int = _effectiveMillis()
	if not _available(id) or HorizonChatModels.millis(_cache[id].channel.expiresAt) <= now: _hide(id); return
	var rows: Array = []
	var ids: Array = []
	for row: Dictionary in _cache[id].messages:
		if HorizonChatModels.millis(row.expiresAt) > now: rows.append(row); ids.append(row.id)
	var changed: bool = rows.size() != _cache[id].messages.size()
	_cache[id].messages = rows
	_cache[id].visibleMessageIds = ids
	if changed: channel_changed.emit(id, _cache[id].duplicate(true))
func _effectiveMillis() -> int:
	return -1 if _clockMillis < 0 else _clockMillis + maxi(0, int(_nowMillis.call()) - _clockTicks)
func _process(_delta: float) -> void:
	if _http == null: return
	_syncScope()
	for id: String in _cache.keys(): _prune(id)
func _session() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return user != null and _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken
func _authorized(user: String) -> bool: return _session() and user == _auth.getCurrentUser().userId
func _syncScope() -> void:
	var user: HorizonUserData = _auth.getCurrentUser()
	var current: Dictionary = {"generation": _http.getContextGeneration(), "user": user.userId if user != null else "", "authToken": user.accessToken if user != null else "", "project": _http.apiKey, "host": _http.activeHost, "token": _http.sessionToken}
	if _scope != current: clearCache(); _scope = current
func _playerChanged(_user: HorizonUserData) -> void: clearCache()
func _fail(code: String, error: String = "") -> Dictionary:
	var message: String = error if not error.is_empty() else code
	chat_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
func _requestFailure(kind: String, code: String, error: String = "", status: int = 0) -> Dictionary:
	if kind != "sync": return _fail(code, error)
	return {"success": false, "data": {}, "errorCode": code, "error": error if not error.is_empty() else code, "_httpStatus": status}
