class_name HorizonItemGifts
extends RefCounted
## Six explicit App routes. Claiming an offer or a return stays Horizon.inbox.claim(user, entryId).
signal item_gifts_loaded(kind: String, data: Dictionary)
signal item_gifts_failed(error: String, code: String)
signal gift_state_invalidated()
const Models = preload("res://addons/horizon_sdk/models/item_gift_models.gd")
const ENDPOINT := "/api/v1/app/item-gifts"
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
func getConfig(user: String) -> Dictionary:
	return await _call(user, "config", "/config")
func getState(user: String) -> Dictionary:
	return await _call(user, "state", "")
func getGift(user: String, gift_id: String) -> Dictionary:
	if not Models.uuid(gift_id): return _fail("INVALID_REQUEST")
	return await _call(user, "gift", "/" + gift_id, {}, gift_id)
func getOperation(user: String, operation_id: String) -> Dictionary:
	if not Models.uuid(operation_id): return _fail("INVALID_REQUEST")
	return await _call(user, "operation", "/operations/" + operation_id, {"operationId": operation_id})
## One attempt per call. Persist all seven fields first and resend them unchanged after uncertainty.
func sendGift(user: String, operation_id: String, issued_at: String, recipient_id: String, instance_id: String, inventory_revision: Variant, config_revision: Variant) -> Dictionary:
	return await submitIntent({"userId": user, "operationId": operation_id, "issuedAt": issued_at, "recipientId": recipient_id, "instanceId": instance_id, "expectedInventoryRevision": inventory_revision, "expectedConfigRevision": config_revision})
func submitIntent(body: Dictionary) -> Dictionary:
	if not Models.valid_intent(body): return _fail("INVALID_REQUEST")
	return await _call(body.userId, "send", "", body)
func declineGift(user: String, gift_id: String, gift_revision: Variant) -> Dictionary:
	if not Models.uuid(gift_id) or not Models.integer(gift_revision): return _fail("INVALID_REQUEST")
	return await _call(user, "decline", "/" + gift_id + "/decline", {"userId": user, "expectedGiftRevision": gift_revision}, gift_id)

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
func _call(user: String, kind: String, route: String, payload: Dictionary = {}, gift_id: String = "") -> Dictionary:
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
	var mutation: bool = kind in ["send", "decline"]
	var endpoint: String = ENDPOINT + route
	if not mutation: endpoint += "?userId=" + user.uri_encode()
	var response: HorizonNetworkResponse = await _http.postOnceAsync(endpoint, request, true) if mutation else await _http.getAsync(endpoint, true)
	_sync_scope()
	if ticket != _ticket or scope != _scope: return _fail("STALE_RESPONSE")
	_busy = false
	if not response.isSuccess:
		if response.statusCode == 401: clearCache()
		return _fail(HorizonInbox._responseCode(response), response.error)
	var data: Dictionary = Models.decode(Models.parse(response.rawBody), kind, user, request, gift_id)
	if data.is_empty(): return _fail("INVALID_RESPONSE")
	var millis: int = Models.milliseconds(data.serverTime)
	if millis < _server_millis or (kind == "state" and data.state.revision < _state_revision) or (kind == "config" and data.config.revision < _config_revision): return _fail("STALE_RESPONSE")
	if kind == "gift" and _current.has("gift") and _current.gift.gift.id == gift_id and data.gift.revision < _current.gift.gift.revision: return _fail("STALE_RESPONSE")
	_server_millis = millis
	_clock_observed = Time.get_ticks_msec()
	if kind == "state": _state_revision = data.state.revision
	if kind == "config": _config_revision = data.config.revision
	# Receipts and operation lookups go to the caller only. No gift history is kept on the device.
	if kind in ["config", "state", "gift"]: _current[kind] = data.duplicate(true)
	if mutation:
		_current.erase("state")
		_current.erase("gift")
		gift_state_invalidated.emit()
	item_gifts_loaded.emit(kind, data.duplicate(true))
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
	item_gifts_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
