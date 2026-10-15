class_name HorizonStatistics
extends RefCounted
## Explicit session batches. Sign-in never fetches statistics or generates retry IDs.

signal statistics_loaded(snapshot: Dictionary)
signal statistics_updated(snapshot: Dictionary)
signal definitions_loaded(catalog: Dictionary)
signal statistics_failed(error: String, code: String)

const ENDPOINT := "/api/v1/app/statistics"
const MAX_VALUE: int = 9007199254740991
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _logger: HorizonLogger
var _current: Dictionary = {}
var _definitions: Array = []
var _version: int = -1
var _clockOffset: int = 0
var _maxRevision: int = -1
var _serverTime: int = 0
var _cacheEpoch: int = 0
var _lastScope: Dictionary = {}
var _lastErrorCode: String = ""
var _lastOperationId: String = ""
var _keyRegex: RegEx = RegEx.new()
var _operationRegex: RegEx = RegEx.new()

func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_keyRegex.compile("^[a-z0-9][a-z0-9._-]{0,23}\\z")
	_operationRegex.compile("^[0-9]{13}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
	_auth.signout_completed.connect(clearCache)
	_auth.signin_completed.connect(_onPlayerChanged)
	_auth.signup_completed.connect(_onPlayerChanged)

func getStatistics() -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("Player session required", "SESSION_REQUIRED")
	var scope: Dictionary = _scope()
	var epoch: int = _cacheEpoch
	var endpoint: String = ENDPOINT + "?userId=" + str(scope["user"]).uri_encode()
	if _version >= 0: endpoint += "&definitionVersion=%d" % _version
	var response: HorizonNetworkResponse = await _http.getAsync(endpoint, true)
	if not _sameScope(scope, epoch): return _fail("Request context changed while loading statistics", _lastErrorCode)
	if not response.isSuccess: return _networkFailure(response)
	var result: Dictionary = _acceptSnapshot(response.data)
	if result.is_empty(): return _fail("Invalid or stale statistics response", _lastErrorCode)
	statistics_loaded.emit(result.duplicate(true))
	return result

func getDefinitions() -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("Player session required", "SESSION_REQUIRED")
	var scope: Dictionary = _scope()
	var epoch: int = _cacheEpoch
	var endpoint: String = ENDPOINT + "/definitions"
	if _version >= 0: endpoint += "?definitionVersion=%d" % _version
	var response: HorizonNetworkResponse = await _http.getAsync(endpoint, true)
	if not _sameScope(scope, epoch): return _fail("Request context changed while loading definitions", _lastErrorCode)
	if not response.isSuccess: return _networkFailure(response)
	if not response.data is Dictionary or not _acceptCatalog(response.data): return _fail("Invalid statistics definitions", "INVALID_RESPONSE")
	_lastErrorCode = ""
	var result: Dictionary = {"definitionVersion": _version, "definitions": _definitions.duplicate(true)}
	definitions_loaded.emit(result.duplicate(true))
	return result

## Persist operation_id and the original immutable updates before sending. Never replace an
## uncertain ID automatically. Old/evicted unknown IDs fail closed as OPERATION_EXPIRED.
func updateStatistics(updates: Array, operation_id: String) -> Dictionary:
	_syncScope()
	if not _hasSession(): return _fail("Player session required", "SESSION_REQUIRED")
	if _operationRegex.search(operation_id) == null or updates.is_empty() or updates.size() > 100:
		return _fail("A timestamp:UUID and 1 to 100 updates are required", "INVALID_REQUEST")
	var keys: Dictionary = {}
	for update: Variant in updates:
		if not update is Dictionary or not update.get("key") is String or _keyRegex.search(update["key"]) == null:
			return _fail("Invalid statistic key", "INVALID_REQUEST")
		var value: Variant = update.get("value")
		if typeof(value) != TYPE_INT or value < -MAX_VALUE or value > MAX_VALUE or keys.has(update["key"]):
			return _fail("Updates require unique keys and safe int values", "INVALID_REQUEST")
		keys[update["key"]] = true
	var scope: Dictionary = _scope()
	var epoch: int = _cacheEpoch
	var body: Dictionary = {"userId": scope["user"], "operationId": operation_id, "updates": updates.duplicate(true)}
	_lastOperationId = operation_id
	var response: HorizonNetworkResponse = await _http.postAsync(ENDPOINT, body, true)
	if not _sameScope(scope, epoch): return _fail("Request context changed while updating statistics", _lastErrorCode)
	if not response.isSuccess: return _networkFailure(response)
	if not response.data is Dictionary or response.data.get("operationId") != operation_id:
		return _fail("Response does not match the original operation", "INVALID_RESPONSE")
	var result: Dictionary = _acceptSnapshot(response.data)
	if result.is_empty(): return _fail("Invalid or stale statistics response", _lastErrorCode)
	statistics_updated.emit(result.duplicate(true))
	return result

func createOperationId() -> String:
	_syncScope()
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%d:%s-%s-%s-%s-%s" % [int(Time.get_unix_time_from_system() * 1000) + _clockOffset,
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func getCurrentStatistics() -> Dictionary:
	_syncScope()
	return _current.duplicate(true)

func getCurrentDefinitions() -> Array:
	_syncScope()
	return _definitions.duplicate(true)

func getLastErrorCode() -> String:
	return _lastErrorCode

func getLastSubmittedOperationId() -> String:
	return _lastOperationId

func clearCache() -> void:
	_current = {}
	_definitions = []
	_version = -1
	_clockOffset = 0
	_maxRevision = -1
	_serverTime = 0
	_cacheEpoch += 1
	_lastErrorCode = ""
	_lastOperationId = ""

func _onPlayerChanged(_user: HorizonUserData) -> void:
	clearCache()

func _scope() -> Dictionary:
	var user: HorizonUserData = _auth.getCurrentUser()
	return {"user": user.userId if user != null else "", "token": _http.sessionToken, "host": _http.activeHost, "project": _http.apiKey}

func _syncScope() -> void:
	var current: Dictionary = _scope()
	if current != _lastScope:
		clearCache()
		_lastScope = current

func _sameScope(scope: Dictionary, epoch: int) -> bool:
	_syncScope()
	if _scope() != scope:
		_lastErrorCode = "SESSION_CHANGED"
		return false
	if epoch != _cacheEpoch:
		_lastErrorCode = "STATE_CONFLICT"
		return false
	return true

func _hasSession() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken

func _safeInteger(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value >= -MAX_VALUE and value <= MAX_VALUE and floorf(float(value)) == float(value)

func _acceptCatalog(data: Dictionary) -> bool:
	var version: Variant = data.get("definitionVersion")
	if not _safeInteger(version) or version < 0 or int(version) < _version: return false
	var definitions: Variant = data.get("definitions")
	if definitions == null:
		return int(version) == _version
	if not definitions is Array or definitions.size() > 100: return false
	var normalized: Array = definitions.duplicate(true)
	var keys: Dictionary = {}
	for definition: Variant in normalized:
		if not definition is Dictionary or not definition.get("key") is String or _keyRegex.search(definition["key"]) == null or keys.has(definition["key"]): return false
		keys[definition["key"]] = true
		var bound: Variant = definition.get("maxPerUpdate")
		if bound != null:
			if not _safeInteger(bound) or bound <= 0: return false
			definition["maxPerUpdate"] = int(bound)
	if int(version) > _version: _current = {}
	_definitions = normalized
	_version = int(version)
	return true

func _acceptSnapshot(data: Variant) -> Dictionary:
	_lastErrorCode = "INVALID_RESPONSE"
	if not data is Dictionary or data.get("userId") != _scope()["user"] or not _safeInteger(data.get("revision")) or data["revision"] < 0: return {}
	var version: Variant = data.get("definitionVersion")
	if not _safeInteger(version): return {}
	if int(version) < _version or int(data["revision"]) < _maxRevision:
		_lastErrorCode = "STATE_CONFLICT"
		return {}
	var window: Variant = data.get("operationWindow")
	if not window is Dictionary or not _safeInteger(window.get("serverTimeUnixMillis")) or window["serverTimeUnixMillis"] < 1000000000000 or window["serverTimeUnixMillis"] > 9999999999999 or not _safeInteger(window.get("maxAgeSeconds")) or window["maxAgeSeconds"] <= 0 or not _safeInteger(window.get("maxFutureSkewSeconds")) or window["maxFutureSkewSeconds"] < 0: return {}
	if int(window["serverTimeUnixMillis"]) < _serverTime:
		_lastErrorCode = "STATE_CONFLICT"
		return {}
	if not _acceptCatalog(data): return {}
	var values: Variant = data.get("values")
	if not values is Array or values.size() != _definitions.size(): return {}
	var result: Dictionary = data.duplicate(true)
	var keys: Dictionary = {}
	for value: Variant in result["values"]:
		if not value is Dictionary or not value.get("key") is String or not _safeInteger(value.get("value")) or typeof(value.get("hasValue")) != TYPE_BOOL or keys.has(value["key"]): return {}
		keys[value["key"]] = true
		value["value"] = int(value["value"])
	for definition: Dictionary in _definitions:
		if not keys.has(definition["key"]): return {}
	result["revision"] = int(data["revision"])
	result["definitionVersion"] = _version
	result["definitions"] = _definitions.duplicate(true)
	result["operationWindow"] = {"serverTimeUnixMillis": int(window["serverTimeUnixMillis"]), "maxAgeSeconds": int(window["maxAgeSeconds"]), "maxFutureSkewSeconds": int(window["maxFutureSkewSeconds"])}
	_clockOffset = int(window["serverTimeUnixMillis"]) - int(Time.get_unix_time_from_system() * 1000)
	_current = result.duplicate(true)
	_maxRevision = int(data["revision"])
	_serverTime = int(window["serverTimeUnixMillis"])
	_lastErrorCode = ""
	return result

func _networkFailure(response: HorizonNetworkResponse) -> Dictionary:
	if response.statusCode == 401: clearCache()
	var code: String = response.serverCode
	if code.is_empty():
		match response.statusCode:
			0: code = "NETWORK_ERROR"
			401: code = "SESSION_REQUIRED"
			403: code = "SESSION_FORBIDDEN"
			409: code = "STATE_CONFLICT"
			410: code = "OPERATION_EXPIRED"
			429: code = "RATE_LIMITED"
			_: code = "HTTP_%d" % response.statusCode
	return _fail(response.error, code)

func _fail(message: String, code: String) -> Dictionary:
	_lastErrorCode = code
	_logger.warning("Statistics request failed (%s)" % code)
	statistics_failed.emit(message, code)
	return {}
