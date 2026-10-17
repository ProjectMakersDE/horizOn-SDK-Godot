class_name HorizonMarketplace
extends RefCounted
## Ten explicit App routes. Current responses only: no purchase-history/result archive.
signal marketplace_loaded(kind: String, data: Dictionary)
signal marketplace_failed(error: String, code: String)
signal trading_state_invalidated()
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
const ENDPOINT := "/api/v1/app/marketplace"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _scope: Dictionary = {}
var _current: Dictionary = {}
var _ticket: int = 0
var _busy: bool = false
var _server_millis: int = -1
var _state_revision: int = -1
var _config_revision: int = -1
var _last_error: String = ""
var _clock_observed: int = 0

func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_player_changed)
	_auth.signup_completed.connect(_player_changed)
func getLimits(user: String) -> Dictionary:
	return await _call(user, "limits", "/limits")
func getRules(user: String, after: String = "", limit: Variant = 50, catalog_revision: Variant = null) -> Dictionary:
	if not _page(limit) or (not after.is_empty() and (not HorizonItemModels.key(after) or catalog_revision == null)) or (catalog_revision != null and not Models.integer(catalog_revision)): return _fail("INVALID_REQUEST")
	return await _call(user, "rules", "/rules", {"after": after, "limit": limit, "catalogRevision": catalog_revision})
func getMarketplace(user: String) -> Dictionary:
	return await _call(user, "state", "")
func queryListings(user: String, item_key: String = "", min_price: Variant = 0, max_price: Variant = Models.MAX, cursor: String = "", limit: Variant = 50) -> Dictionary:
	if not _page(limit) or (not item_key.is_empty() and not HorizonItemModels.key(item_key)) or not Models.integer(min_price) or not Models.integer(max_price) or min_price > max_price or (not cursor.is_empty() and not Models.cursor(cursor)): return _fail("INVALID_REQUEST")
	return await _call(user, "query", "/listings", {"itemKey": item_key, "minPrice": min_price, "maxPrice": max_price, "cursor": cursor, "limit": limit})
func getListing(user: String, listing_id: String) -> Dictionary:
	if not Models.uuid(listing_id): return _fail("INVALID_REQUEST")
	return await _call(user, "point", "/listings/" + listing_id, {}, listing_id)
func createListing(user: String, operation_id: String, issued_at: String, instance_id: String, inventory_revision: Variant, config_revision: Variant, price: Variant, duration_seconds: Variant) -> Dictionary:
	return await submitIntent("create", {"userId": user, "operationId": operation_id, "issuedAt": issued_at, "instanceId": instance_id, "expectedInventoryRevision": inventory_revision, "expectedConfigRevision": config_revision, "price": price, "durationSeconds": duration_seconds})
func buyListing(user: String, listing_id: String, operation_id: String, issued_at: String, listing_revision: Variant, expected_price: Variant, currency_key: String) -> Dictionary:
	return await submitIntent("buy", {"userId": user, "operationId": operation_id, "issuedAt": issued_at, "expectedListingRevision": listing_revision, "expectedPrice": expected_price, "expectedCurrencyKey": currency_key}, listing_id)
func cancelListing(user: String, listing_id: String, operation_id: String, issued_at: String, listing_revision: Variant) -> Dictionary:
	return await submitIntent("cancel", {"userId": user, "operationId": operation_id, "issuedAt": issued_at, "expectedListingRevision": listing_revision}, listing_id)
func submitIntent(kind: String, body: Dictionary, listing_id: String = "") -> Dictionary:
	if not Models.valid_intent(kind, body, listing_id): return _fail("INVALID_REQUEST")
	var route: String = "/listings" if kind == "create" else "/listings/" + listing_id + "/" + kind
	return await _call(body.userId, kind, route, body, listing_id)
func getOperation(user: String, operation_id: String) -> Dictionary:
	if not Models.uuid(operation_id): return _fail("INVALID_REQUEST")
	return await _call(user, "operation", "/operations/" + operation_id, {"operationId": operation_id})
func retryReturn(user: String, listing_id: String) -> Dictionary:
	if not Models.uuid(listing_id): return _fail("INVALID_REQUEST")
	return await _call(user, "return", "/listings/" + listing_id + "/retry-return", {"userId": user}, listing_id)

func getCurrent(kind: String) -> Dictionary:
	_sync_scope()
	return _current.get(kind, {}).duplicate(true) if _has_session() else {}
func getLastErrorCode() -> String: return _last_error
func getServerNow() -> int:
	_sync_scope()
	return _server_millis + Time.get_ticks_msec() - _clock_observed if _server_millis >= 0 and _has_session() else -1
func clearCache() -> void:
	# Old completions cannot release a newer request's busy ticket. Keep same-scope watermarks.
	_ticket += 1
	_busy = false
	_current.clear()
func _page(limit: Variant) -> bool: return typeof(limit) == TYPE_INT and limit >= 1 and limit <= 50
func _call(user: String, kind: String, route: String, payload: Dictionary = {}, listing_id: String = "") -> Dictionary:
	_sync_scope()
	if not _has_session(): return _fail("SESSION_REQUIRED")
	if user != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not Models.uuid(user): return _fail("INVALID_REQUEST")
	if _busy: return _fail("REQUEST_IN_PROGRESS")
	_busy = true
	_ticket += 1
	var ticket: int = _ticket
	var scope: Dictionary = _scope.duplicate()
	var request: Dictionary = payload.duplicate(true)
	var mutation: bool = kind in ["create", "buy", "cancel", "return"]
	var endpoint: String = ENDPOINT + route
	if not mutation:
		endpoint += "?userId=" + user.uri_encode()
		if kind == "rules":
			endpoint += "&limit=" + str(request.limit)
			if not request.after.is_empty(): endpoint += "&after=" + request.after.uri_encode()
			if request.catalogRevision != null: endpoint += "&catalogRevision=" + str(request.catalogRevision)
		elif kind == "query":
			endpoint += "&minPrice=" + str(request.minPrice) + "&maxPrice=" + str(request.maxPrice) + "&limit=" + str(request.limit)
			if not request.itemKey.is_empty(): endpoint += "&itemKey=" + request.itemKey.uri_encode()
			if not request.cursor.is_empty(): endpoint += "&cursor=" + request.cursor.uri_encode()
	var response: HorizonNetworkResponse = await _http.postOnceAsync(endpoint, request, true) if mutation else await _http.getAsync(endpoint, true)
	_sync_scope()
	if ticket != _ticket or scope != _scope: return _fail("STALE_RESPONSE")
	_busy = false
	if not response.isSuccess:
		if response.statusCode == 401: clearCache()
		return _fail(HorizonInbox._responseCode(response), response.error)
	var data: Dictionary = Models.decode(Models.parse(response.rawBody), kind, user, request, listing_id)
	if data.is_empty(): return _fail("INVALID_RESPONSE")
	var millis: int = Models.milliseconds(data.serverTime)
	if millis < _server_millis or (kind == "state" and data.state.revision < _state_revision) or (kind == "limits" and data.config.revision < _config_revision) or (kind == "rules" and data.revision < _config_revision): return _fail("STALE_RESPONSE")
	if kind == "point" and _current.has("point") and _current.point.listing.id == listing_id and data.listing.revision < _current.point.listing.revision: return _fail("STALE_RESPONSE")
	_server_millis = millis
	_clock_observed = Time.get_ticks_msec()
	if kind == "state": _state_revision = data.state.revision
	if kind == "limits": _config_revision = data.config.revision
	if kind == "rules": _config_revision = data.revision
	# Results/operation lookups are returned to the caller, never retained as a trade history.
	if kind in ["limits", "rules", "state", "query", "point"]: _current[kind] = data.duplicate(true)
	if mutation:
		_current.erase("state")
		_current.erase("query")
		_current.erase("point")
		trading_state_invalidated.emit()
	marketplace_loaded.emit(kind, data.duplicate(true))
	_sync_scope()
	if ticket != _ticket or scope != _scope: return _fail("STALE_RESPONSE")
	_last_error = ""
	return {"success": true, "data": data, "errorCode": "", "error": ""}
func _has_session() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return user != null and _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken
func _sync_scope() -> void:
	var user: HorizonUserData = _auth.getCurrentUser()
	var current: Dictionary = {"user": user.userId if user != null else "", "authToken": user.accessToken if user != null else "", "project": _http.apiKey, "host": _http.activeHost, "token": _http.sessionToken, "generation": _http.getContextGeneration()}
	if current != _scope:
		_reset()
		_scope = current
func _player_changed(_user: HorizonUserData) -> void: _reset()
func _reset() -> void:
	clearCache()
	_scope = {}
	_server_millis = -1
	_state_revision = -1
	_config_revision = -1
func _fail(code: String, error: String = "") -> Dictionary:
	_last_error = code
	var message: String = error if not error.is_empty() else code
	marketplace_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
