class_name HorizonItems
extends RefCounted
## One owned inventory and one explicit catalog page. No mutation retries or polling.
signal inventory_loaded(snapshot: Dictionary)
signal inventory_updated(snapshot: Dictionary)
signal catalog_loaded(page: Dictionary)
signal items_failed(error: String, code: String)
signal _request_finished()
const ENDPOINT := "/api/v1/app/items"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _scope: Dictionary = {}
var _current: Dictionary = {}
var _page: Dictionary = {}
var _revision: int = -1
var _catalogRevision: int = -1
var _serverTime: int = -1
var _epoch: int = 0
var _queueEpoch: int = 0
var _busy: bool = false
var _lastErrorCode: String = ""
var _uuid: RegEx = HorizonItemModels._uuid

func initialize(http: HorizonHttpClient, auth: HorizonAuth, values: HorizonPlayerValues = null) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)
	if values != null: values.item_inventory_invalidated.connect(clearCache)

func getInventory(user_id: String) -> Dictionary: return await _call(user_id, "")
func getCatalog(user_id: String, after_key: String = "", limit: Variant = 50, catalog_revision: Variant = null) -> Dictionary:
	if (not after_key.is_empty() and not HorizonItemModels.key(after_key)) or typeof(limit) != TYPE_INT or limit < 1 or limit > 50 or (catalog_revision != null and not HorizonItemModels.integer(catalog_revision)): return _fail("INVALID_REQUEST")
	return await _call(user_id, "/catalog", {"afterKey": after_key, "limit": limit, "catalogRevision": catalog_revision})
func adjustProperties(user_id: String, instance_id: String, expected_revision: Variant, changes: Variant) -> Dictionary:
	if not changes is Array or changes.is_empty() or changes.size() > 8: return _fail("INVALID_REQUEST")
	var seen: Dictionary = {}
	for entry: Variant in changes:
		if not entry is Dictionary or entry.keys().size() != 2 or not HorizonItemModels.key(entry.get("key")) or not HorizonItemModels.integer(entry.get("amount"), -HorizonItemModels.MAX) or entry.amount == 0 or seen.has(entry.key): return _fail("INVALID_REQUEST")
		seen[entry.key] = true
	return await _mutate(user_id, instance_id, expected_revision, "/adjust", {"changes": changes.duplicate(true)})
func setEquipped(user_id: String, instance_id: String, expected_revision: Variant, equipped: Variant) -> Dictionary:
	if not equipped is bool: return _fail("INVALID_REQUEST")
	return await _mutate(user_id, instance_id, expected_revision, "/equip", {"equipped": equipped})
func discardItem(user_id: String, instance_id: String, expected_revision: Variant) -> Dictionary:
	return await _mutate(user_id, instance_id, expected_revision, "/discard", {})
func _mutate(user: String, instance: String, revision: Variant, route: String, body: Dictionary) -> Dictionary:
	if not HorizonItemModels.uuid(instance) or not HorizonItemModels.integer(revision): return _fail("INVALID_REQUEST")
	body.instanceId = instance
	body.expectedRevision = revision
	return await _call(user, route, body)
func getCurrentInventory() -> Dictionary:
	_syncScope()
	return _current.duplicate(true) if _hasSession() else {}
func getCurrentCatalogPage() -> Dictionary:
	_syncScope()
	return _page.duplicate(true) if _hasSession() else {}
func getLastErrorCode() -> String: return _lastErrorCode
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()
func _invalidate() -> void:
	_epoch += 1
	_current.clear()
	_page.clear()

func _call(user: String, route: String, payload: Dictionary = {}) -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not HorizonItemModels.uuid(user): return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var queued: int = _queueEpoch
	var body: Dictionary = payload.duplicate(true)
	while _busy: await _request_finished
	_syncScope()
	if scope != _scope or queued != _queueEpoch: return _fail("STALE_RESPONSE")
	_busy = true
	var mutation: bool = route in ["/adjust", "/equip", "/discard"]
	if mutation: _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT + route + "?userId=" + user.uri_encode()
	if route == "/catalog":
		endpoint += "&limit=" + str(body.limit)
		if not body.afterKey.is_empty(): endpoint += "&afterKey=" + body.afterKey.uri_encode()
		if body.catalogRevision != null: endpoint += "&catalogRevision=" + str(body.catalogRevision)
	body.userId = user
	var response: HorizonNetworkResponse = await _http.postOnceAsync(ENDPOINT + route, body, true) if mutation else await _http.getAsync(endpoint, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401: clearCache()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	else:
		var raw: Dictionary = HorizonItemModels.parse(response.rawBody)
		var data: Dictionary = HorizonItemModels.page(raw, payload.afterKey, payload.limit) if route == "/catalog" else HorizonItemModels.inventory(raw, user)
		if data.is_empty() or (mutation and not _effect(data, route, body)): result = _fail("INVALID_RESPONSE")
		elif HorizonPlayerValues._timeMillis(data.serverTime) < _serverTime or (route == "/catalog" and (data.revision < _catalogRevision or (payload.catalogRevision != null and data.revision != payload.catalogRevision))) or (route != "/catalog" and data.revision < _revision): result = _fail("STALE_RESPONSE")
		else:
			_serverTime = HorizonPlayerValues._timeMillis(data.serverTime)
			if route == "/catalog":
				_catalogRevision = data.revision
				_page = data.duplicate(true)
			else:
				_revision = data.revision
				_current = data.duplicate(true)
			_lastErrorCode = ""
			result = {"success": true, "data": data, "errorCode": "", "error": ""}
			if route == "/catalog": catalog_loaded.emit(data.duplicate(true))
			elif mutation: inventory_updated.emit(data.duplicate(true))
			else: inventory_loaded.emit(data.duplicate(true))
			_syncScope()
			if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	_busy = false
	_request_finished.emit()
	_syncScope()
	if result.success and (scope != _scope or queued != _queueEpoch): return _fail("STALE_RESPONSE")
	return result

func _effect(snapshot: Dictionary, route: String, body: Dictionary) -> bool:
	if snapshot.revision != body.expectedRevision + 1: return false
	var target: Dictionary = {}
	for item: Dictionary in snapshot.instances:
		if item.instanceId.to_lower() == body.instanceId.to_lower(): target = item
	if route == "/discard": return target.is_empty()
	return not target.is_empty() and (route != "/equip" or target.equipped == body.equipped)

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
	_catalogRevision = -1

func _validUuid(value: Variant) -> bool: return value is String and _uuid.search(value) != null
func _nonnegative(value: Variant) -> bool: return HorizonItemModels.integer(value)
func _time(value: Variant) -> bool: return value is String and HorizonPlayerValues._timeMillis(value) >= 0

func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = error if not error.is_empty() else code
	items_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
