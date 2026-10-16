class_name HorizonSharedObjects
extends RefCounted
## Explicit single pages. Mutations send once with the caller's unchanged If-Match revision.
signal objects_loaded(kind: String, data: Dictionary)
signal objects_changed(kind: String, data: Dictionary)
signal shared_objects_failed(error: String, code: String)
signal _request_finished()
const ENDPOINT := "/api/v1/app/shared-objects"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _scope: Dictionary = {}
var _cache: Dictionary = {}
var _revisions: Dictionary = {}
var _times: Dictionary = {}
var _deleted: Dictionary = {}
var _refresh: Dictionary = {}
var _nowMillis: Callable = func() -> int: return Time.get_ticks_msec()
var _epoch: int = 0
var _queueEpoch: int = 0
var _busy: bool = false
var _lastErrorCode: String = ""
func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)
func getCollections(user_id: String, after_key: String = "", limit: Variant = 50, catalog_revision: Variant = null) -> Dictionary:
	if (not after_key.is_empty() and not HorizonSharedObjectModels.key(after_key)) or not HorizonSharedObjectModels.integer(limit, 1) or limit > 50 or (catalog_revision != null and not HorizonSharedObjectModels.integer(catalog_revision)): return _fail("INVALID_REQUEST")
	return await _call(user_id, "collections", "", "", null, {"afterKey": after_key, "limit": limit, "catalogRevision": catalog_revision})
func getUsage(user_id: String, collection: String) -> Dictionary: return await _call(user_id, "usage", collection)
func getObject(user_id: String, collection: String, object_id: String) -> Dictionary:
	if not HorizonSharedObjectModels.uuid(object_id): return _fail("INVALID_REQUEST")
	return await _call(user_id, "get", collection, object_id)
func queryObjects(user_id: String, collection: String, query: Dictionary) -> Dictionary:
	if not HorizonSharedObjectModels.query(query): return _fail("INVALID_REQUEST")
	return await _call(user_id, "query", collection, "", null, query)
func createObject(user_id: String, collection: String, expected_usage_revision: Variant, data: PackedByteArray, search: Dictionary, position: Variant = null, group_id: String = "") -> Dictionary:
	if not group_id.is_empty() and not HorizonSharedObjectModels.uuid(group_id): return _fail("INVALID_REQUEST")
	var body: Dictionary = {"dataBase64": HorizonSharedObjectModels.encodeBytes(data), "search": search, "position": position}
	if not group_id.is_empty(): body.groupId = group_id
	return await _write(user_id, "create", collection, "", expected_usage_revision, data, body)
func updateObject(user_id: String, collection: String, object_id: String, expected_revision: Variant, data: PackedByteArray, search: Dictionary, position: Variant = null) -> Dictionary:
	if not HorizonSharedObjectModels.uuid(object_id): return _fail("INVALID_REQUEST")
	return await _write(user_id, "update", collection, object_id, expected_revision, data, {"dataBase64": HorizonSharedObjectModels.encodeBytes(data), "search": search, "position": position})
func deleteObject(user_id: String, collection: String, object_id: String, expected_revision: Variant) -> Dictionary:
	if not HorizonSharedObjectModels.uuid(object_id) or not HorizonSharedObjectModels.integer(expected_revision): return _fail("INVALID_REQUEST")
	return await _call(user_id, "delete", collection, object_id, expected_revision)
func _write(user: String, kind: String, collection: String, id: String, revision: Variant, bytes: PackedByteArray, body: Dictionary) -> Dictionary:
	if not HorizonSharedObjectModels.integer(revision) or revision == HorizonSharedObjectModels.MAX or bytes.size() > HorizonSharedObjectModels.MAX_OBJECT or not HorizonSharedObjectModels.search(body.search) or not HorizonSharedObjectModels.position(body.position): return _fail("INVALID_REQUEST")
	return await _call(user, kind, collection, id, revision, body)
## A cache lookup never performs network IO. identity is the exact returned request identity.
func getCached(identity: String) -> Dictionary:
	_syncScope()
	return _cache.get(identity, {}).duplicate(true) if _hasSession() else {}
## Recovery reads are explicit consistency/reconciliation, never a refresh or random search.
func getRecoveryUsage(user_id: String, collection: String) -> Dictionary: return await _call(user_id, "usage", collection, "", null, {}, true)
func queryRecoveryObjects(user_id: String, collection: String, query: Dictionary) -> Dictionary:
	if not HorizonSharedObjectModels.query(query) or query.get("mode") != "owner" or query.get("ownerId") != user_id: return _fail("INVALID_REQUEST")
	return await _call(user_id, "query", collection, "", null, query, true)
func getRefreshDelaySeconds(identity: String) -> int:
	_syncScope()
	return _delay(identity)
func _delay(identity: String) -> int:
	if not _refresh.has(identity): return 0
	var hint: Dictionary = _refresh[identity]
	var elapsed: int = floori(float(maxi(0, int(_nowMillis.call()) - hint.millis)) / 1000.0)
	return maxi(0, hint.seconds - elapsed)
func getLastErrorCode() -> String: return _lastErrorCode
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()
func _invalidate() -> void:
	_epoch += 1
	_cache.clear()
	_refresh.clear()
func _call(user: String, kind: String, collection: String = "", id: String = "", expected: Variant = null, options: Dictionary = {}, recovery: bool = false) -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not HorizonSharedObjectModels.uuid(user) or (kind != "collections" and not HorizonSharedObjectModels.key(collection)): return _fail("INVALID_REQUEST")
	# Freeze complete bytes before queueing, including any lossless search-string wrappers.
	var original: String = HorizonSharedObjectModels.encode(options)
	var body: Dictionary = HorizonSharedObjectModels.parse(original)
	if body.is_empty() and not options.is_empty(): return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var queued: int = _queueEpoch
	while _busy: await _request_finished
	_syncScope()
	if scope != _scope or queued != _queueEpoch: return _fail("STALE_RESPONSE")
	var identity: String = HorizonSharedObjectModels.encode([scope, kind, collection, id, expected, body]).sha256_text()
	var continuation: bool = not str(body.get("cursor", "")).is_empty() or not str(body.get("afterKey", "")).is_empty()
	if not recovery and kind not in ["create", "update", "delete"] and not continuation and _delay(identity) > 0:
		var throttled: Dictionary = _fail("REFRESH_NOT_DUE")
		throttled.retryAfterSeconds = _delay(identity)
		return throttled
	_busy = true
	var mutation: bool = kind in ["create", "update", "delete"]
	if mutation: _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT + ("/collections" if kind == "collections" else "/" + collection + ("/usage" if kind == "usage" else "/query" if kind == "query" else "/objects" + ("/" + id if not id.is_empty() else "")))
	var query: String = "?userId=" + user.uri_encode()
	if kind == "collections":
		query += "&limit=" + str(body.limit)
		if not body.afterKey.is_empty(): query += "&afterKey=" + body.afterKey.uri_encode()
		if body.catalogRevision != null: query += "&catalogRevision=" + str(body.catalogRevision)
	var headers := PackedStringArray(["If-Match: " + str(expected)]) if mutation else PackedStringArray()
	var request: Dictionary = body.duplicate(true)
	request.userId = user
	var json: String = HorizonSharedObjectModels.encode(request)
	var response: HorizonNetworkResponse
	match kind:
		"create": response = await _http.postJsonHeadersOnceAsync(endpoint, request, true, json, headers)
		"update": response = await _http.putJsonHeadersOnceAsync(endpoint, request, true, json, headers)
		"delete": response = await _http.deleteOnceAsync(endpoint + query, true, headers)
		"query": response = await _http.postJsonAsync(endpoint, request, true, json)
		_: response = await _http.getAsync(endpoint + query, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401: clearCache()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	else:
		var data: Dictionary = HorizonSharedObjectModels.response(HorizonSharedObjectModels.parse(response.rawBody), kind, user, collection, id, expected, body)
		if data.is_empty() or not _effect(kind, data, body): result = _fail("INVALID_RESPONSE")
		elif not _fresh(kind, collection, data): result = _fail("STALE_RESPONSE")
		else:
			_record(kind, collection, data)
			_cache[identity] = data.duplicate(true)
			if not mutation: _refresh[identity] = {"millis": int(_nowMillis.call()), "seconds": 120 if kind == "collections" else data.pollAfterSeconds}
			_trim(_refresh, 512)
			_trim(_cache, 8)
			_lastErrorCode = ""
			result = {"success": true, "data": data, "identity": identity, "errorCode": "", "error": ""}
			if mutation: objects_changed.emit(kind, data.duplicate(true))
			else: objects_loaded.emit(kind, data.duplicate(true))
			_syncScope()
			if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	_busy = false
	_request_finished.emit()
	_syncScope()
	if result.success and (scope != _scope or queued != _queueEpoch): return _fail("STALE_RESPONSE")
	return result
func _effect(kind: String, data: Dictionary, body: Dictionary) -> bool:
	if kind in ["create", "update"]:
		return data.object.dataBase64 == body.dataBase64 and HorizonSharedObjectModels.encode(data.object.search) == HorizonSharedObjectModels.encode(body.search) and data.object.position == body.position and (kind != "create" or data.object.groupId == body.get("groupId"))
	if kind == "query":
		for row: Dictionary in data.objects:
			if (body.has("ownerId") and row.ownerId != body.ownerId) or (body.has("groupId") and row.groupId != body.groupId): return false
	return true
func _versions(kind: String, collection: String, data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if kind == "collections": result.catalog = data.revision
	elif kind == "usage": result["usage:" + collection + ":" + data.userId] = data.revision
	elif kind in ["create", "update", "delete"]: result["usage:" + collection + ":" + data.usage.userId] = data.usage.revision
	if kind in ["get", "create", "update"]: result["object:" + collection + ":" + data.object.id] = data.object.revision
	if kind == "query":
		for row: Dictionary in data.objects: result["object:" + collection + ":" + row.id] = row.revision
	return result
func _fresh(kind: String, collection: String, data: Dictionary) -> bool:
	var resource: String = kind + ":" + collection
	if HorizonPlayerValues._timeMillis(data.serverTime) < _times.get(resource, -1): return false
	var versions: Dictionary = _versions(kind, collection, data)
	for key: String in versions:
		if versions[key] < _revisions.get(key, -1) or _deleted.has(key): return false
	return true
func _record(kind: String, collection: String, data: Dictionary) -> void:
	_times[kind + ":" + collection] = HorizonPlayerValues._timeMillis(data.serverTime)
	_revisions.merge(_versions(kind, collection, data), true)
	if kind == "delete": _deleted["object:" + collection + ":" + data.objectId] = true
	_trim(_revisions, 512)
	_trim(_times, 512)
	_trim(_deleted, 512)
func _trim(values: Dictionary, maximum: int) -> void:
	while values.size() > maximum: values.erase(values.keys()[0])
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
	_revisions.clear()
	_times.clear()
	_deleted.clear()
func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = error if not error.is_empty() else code
	shared_objects_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
