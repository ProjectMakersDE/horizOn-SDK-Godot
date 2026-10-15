## Server-owned balances. Keep an operation ID stable across every retry of one action.
class_name HorizonPlayerValues
extends RefCounted

const ENDPOINT := "/api/v1/app/player-values"
const MAX_SAFE_INTEGER: int = 9007199254740991
var lastErrorCode: String = ""
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _identity: String = ""
var _epoch: int = 0
var _revision: int = -1
var _definition: int = -1
var _serverMillis: int = -1
var _observedAt: int = 0
var _state: Dictionary = {}
var _offers: Dictionary = {}

func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	_auth.signout_completed.connect(_resetIdentity)

func getCurrentState() -> Dictionary:
	_syncIdentity()
	return _state.duplicate(true)

func getCurrentOffers() -> Dictionary:
	_syncIdentity()
	return _offers.duplicate(true)

func clearCache() -> void:
	_syncIdentity()
	_epoch += 1
	_state.clear()
	_offers.clear()

func hasServerClock() -> bool:
	_syncIdentity()
	return _serverMillis >= 0

func createOperationId() -> String:
	_syncIdentity()
	var millis: int = _serverMillis + Time.get_ticks_msec() - _observedAt if _serverMillis >= 0 else int(Time.get_unix_time_from_system() * 1000)
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%d:%s-%s-%s-%s-%s" % [millis, hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]

func getState(user_id: String) -> Dictionary:
	return await _stateCall(user_id, "", {})

func purchase(user_id: String, offer_key: String, operation_id: String) -> Dictionary:
	if offer_key.strip_edges().is_empty() or not _validOperationId(operation_id):
		return _failure("INVALID_REQUEST")
	return await _stateCall(user_id, "/purchase", {"userId": user_id, "offerKey": offer_key, "operationId": operation_id})

func adjust(user_id: String, key: String, amount: Variant, reason: String, operation_id: String) -> Dictionary:
	if typeof(amount) != TYPE_INT or not _safeNumber(amount) or amount == 0 or key.strip_edges().is_empty() or reason.strip_edges().is_empty() or not _validOperationId(operation_id):
		return _failure("INVALID_REQUEST")
	return await _stateCall(user_id, "/adjust", {"userId": user_id, "key": key, "amount": amount, "reason": reason, "operationId": operation_id})

func getOffers(user_id: String) -> Dictionary:
	if not _begin(user_id):
		return {"success": false, "data": {}, "errorCode": lastErrorCode, "error": lastErrorCode}
	var identity := _identity
	var epoch := _epoch
	var response := await _http.getAsync(ENDPOINT + "/offers?userId=" + user_id.uri_encode(), true)
	_syncIdentity()
	if identity != _identity or epoch != _epoch:
		return {"success": false, "data": {}, "errorCode": "STALE_RESPONSE", "error": "Session or cache changed"}
	if response.isSuccess and not _safeJsonIntegers(response.rawBody):
		lastErrorCode = "INVALID_RESPONSE"
		return {"success": false, "data": {}, "errorCode": lastErrorCode, "error": lastErrorCode}
	var data := _normalizeOffers(response.data) if response.isSuccess else {}
	if data.is_empty() or int(data.definitionVersion) < _definition or not _acceptClock(data.serverTime):
		lastErrorCode = "STALE_RESPONSE" if response.isSuccess else _responseCode(response)
		return {"success": false, "data": {}, "errorCode": lastErrorCode, "error": response.error}
	if int(data.definitionVersion) > _definition:
		_definition = int(data.definitionVersion)
		_state.clear()
	_offers = data.duplicate(true)
	lastErrorCode = ""
	return {"success": true, "data": data, "errorCode": "", "error": ""}

func _stateCall(user_id: String, route: String, body: Dictionary) -> Dictionary:
	if not _begin(user_id):
		return _failure(lastErrorCode)
	var identity := _identity
	var epoch := _epoch
	var response := await _http.getAsync(ENDPOINT + "?userId=" + user_id.uri_encode(), true) if route.is_empty() else await _http.postAsync(ENDPOINT + route, body, true)
	_syncIdentity()
	if identity != _identity or epoch != _epoch:
		return {"success": false, "state": {}, "errorCode": "STALE_RESPONSE", "error": "Session or cache changed"}
	var raw: Variant = response.data
	if not _safeJsonIntegers(response.rawBody if response.isSuccess else response.errorBody):
		return _failure("INVALID_RESPONSE")
	if not response.isSuccess and not response.errorBody.is_empty():
		var envelope: Variant = JSON.parse_string(response.errorBody)
		raw = envelope.get("state") if envelope is Dictionary else null
	var state := _normalizeState(raw)
	if not state.is_empty():
		if state.userId != user_id or int(state.revision) < _revision or int(state.definitionVersion) < _definition or _timeMillis(state.operationWindow.serverTime) < _serverMillis:
			return _failure("STALE_RESPONSE")
		if int(state.definitionVersion) > _definition:
			_offers.clear()
		_revision = int(state.revision)
		_definition = int(state.definitionVersion)
		_acceptClock(state.operationWindow.serverTime)
		_state = state.duplicate(true)
	elif response.isSuccess:
		return _failure("INVALID_RESPONSE")
	lastErrorCode = "" if response.isSuccess else _responseCode(response)
	return {"success": response.isSuccess, "state": state, "errorCode": lastErrorCode, "error": response.error}

func _begin(user_id: String) -> bool:
	_syncIdentity()
	var user := _auth.getCurrentUser()
	lastErrorCode = "SESSION_REQUIRED" if user == null or not user.isValid() or _http.sessionToken.is_empty() or user.accessToken != _http.sessionToken else "SESSION_FORBIDDEN" if user.userId != user_id else ""
	return lastErrorCode.is_empty()

func _syncIdentity() -> void:
	var value: String = _auth.getCurrentUser().userId + "|" + _http.sessionToken + "|" + _http.apiKey + "|" + _http.activeHost
	if value != _identity:
		_resetIdentity()
		_identity = value

func _resetIdentity() -> void:
	_identity = ""
	_epoch += 1
	_revision = -1
	_definition = -1
	_serverMillis = -1
	_state.clear()
	_offers.clear()
	lastErrorCode = ""

func _failure(code: String) -> Dictionary:
	lastErrorCode = code
	return {"success": false, "state": {}, "errorCode": code, "error": code}

func _acceptClock(value: String) -> bool:
	var millis := _timeMillis(value)
	if millis < 0 or millis < _serverMillis:
		return false
	_serverMillis = millis
	_observedAt = Time.get_ticks_msec()
	return true

static func _timeMillis(value: Variant) -> int:
	if not value is String or not value.contains("T") or not value.ends_with("Z"):
		return -1
	var seconds := Time.get_unix_time_from_datetime_string(value)
	var fraction: String = value.get_slice(".", 1).trim_suffix("Z") if value.contains(".") else ""
	return seconds * 1000 + int((fraction + "000").substr(0, 3)) if seconds > 0 else -1

static func _safeNumber(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER and float(value) == floor(float(value))

static func _normalizeBalances(raw: Variant) -> Variant:
	if not raw is Array:
		return null
	var values: Array = raw.duplicate(true)
	for value: Variant in values:
		if not value is Dictionary or not value.get("key") is String or not _safeNumber(value.get("balance")) or not _safeNumber(value.get("earnedToday")):
			return null
		value.balance = int(value.balance)
		value.earnedToday = int(value.earnedToday)
		if value.get("dailyCap") != null:
			if not _safeNumber(value.dailyCap):
				return null
			value.dailyCap = int(value.dailyCap)
	return values

static func _normalizeState(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not raw.get("userId") is String or not _safeNumber(raw.get("revision")) or raw.revision < 0 or not _safeNumber(raw.get("definitionVersion")) or raw.definitionVersion < 0 or not raw.get("operationWindow") is Dictionary or _timeMillis(raw.operationWindow.get("serverTime")) < 0:
		return {}
	var values: Variant = _normalizeBalances(raw.get("values"))
	if values == null:
		return {}
	var state: Dictionary = raw.duplicate(true)
	state.values = values
	state.revision = int(state.revision)
	state.definitionVersion = int(state.definitionVersion)
	if state.get("operation") is Dictionary:
		for delta: Variant in state.operation.get("applied", []):
			if not delta is Dictionary or not _safeNumber(delta.get("amount")):
				return {}
			delta.amount = int(delta.amount)
	return state

static func _normalizeOffers(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not _safeNumber(raw.get("definitionVersion")) or raw.definitionVersion < 0 or not raw.get("offers") is Array or _timeMillis(raw.get("serverTime")) < 0:
		return {}
	var definitions: Variant = _normalizeBalances(raw.get("definitions"))
	if definitions == null:
		return {}
	var result: Dictionary = raw.duplicate(true)
	result.definitions = definitions
	result.definitionVersion = int(result.definitionVersion)
	for offer: Variant in result.offers:
		if not offer is Dictionary:
			return {}
		for field: String in ["costs", "rewards"]:
			if not offer.get(field) is Array:
				return {}
			for amount: Variant in offer[field]:
				if not amount is Dictionary or not _safeNumber(amount.get("amount")):
					return {}
				amount.amount = int(amount.amount)
		if offer.get("purchasesPerDay") != null:
			if not _safeNumber(offer.purchasesPerDay):
				return {}
			offer.purchasesPerDay = int(offer.purchasesPerDay)
	return result

static func _validOperationId(value: String) -> bool:
	var expression := RegEx.new()
	expression.compile("^[0-9]{1,16}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	return expression.search(value) != null and int(value.get_slice(":", 0)) > 0

static func _safeJsonIntegers(json: String) -> bool:
	var expression := RegEx.new()
	expression.compile('"(balance|earnedToday|dailyCap|amount|revision|definitionVersion|purchasesPerDay)"\\s*:\\s*([^,}\\]\\s]+)')
	for item: RegExMatch in expression.search_all(json):
		var value := item.get_string(2)
		if value == "null" and item.get_string(1) in ["dailyCap", "purchasesPerDay"]:
			continue
		if not value.is_valid_int() or value.length() > 17 or not _safeNumber(int(value)):
			return false
	return true

static func _responseCode(response: HorizonNetworkResponse) -> String:
	return response.serverCode if not response.serverCode.is_empty() else "HTTP_%d" % response.statusCode
