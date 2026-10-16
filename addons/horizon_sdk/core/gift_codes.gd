## ============================================================
## horizOn SDK - Gift Code Manager
## ============================================================
## Handles gift code validation and redemption.
## Gift codes can contain in-game rewards like currency or items.
## ============================================================
class_name HorizonGiftCodes
extends RefCounted

## Signals
signal code_validated(code: String, is_valid: bool)
signal code_redeemed(code: String, gift_data: String)
signal code_redeem_failed(code: String, error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth
var _playerProfile: HorizonPlayerProfile
var _values: HorizonPlayerValues
var _epoch: int = 0


## Initialize the gift code manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_changedUser)
	_auth.signup_completed.connect(_changedUser)
	_logger.info("Gift code manager initialized")


## Connect the player profile manager, so a redeem that grants unlocks
## drops its cached profile. Called by the Horizon singleton.
## @param player_profile Player profile manager (may be null)
func setPlayerProfile(player_profile: HorizonPlayerProfile) -> void:
	_playerProfile = player_profile


## Share the singleton's full server-owned balance cache.
func setPlayerValues(values: HorizonPlayerValues) -> void:
	_values = values


## Validate a gift code without redeeming it.
## @param code The gift code to validate
## @return True if code is valid and can be redeemed, false otherwise, null on error
func validate(code: String) -> Variant:
	if code.is_empty():
		_logger.error("Gift code is required")
		return null

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to validate gift code")
		return null

	var user := _auth.getCurrentUser()

	var request := {
		"code": code,
		"userId": user.userId
	}

	var scope: Dictionary = _scope()
	var epoch: int = _epoch
	var response := await _http.postAsync("/api/v1/app/gift-codes/validate", request)
	if scope != _scope() or epoch != _epoch: return null

	if response.isSuccess and response.data is Dictionary:
		var isValid: bool = response.data.get("valid", false)
		_logger.info("Gift code %s validation: %s" % [code, "valid" if isValid else "invalid"])
		code_validated.emit(code, isValid)
		return isValid

	_logger.error("Gift code validation failed: %s" % response.error)
	return null


## Redeem using the original caller-persisted ID (1..128 UTF-16 units).
## The empty default preserves legacy omission and allows only one transport attempt.
## Never replace an uncertain ID. grantedValues are already booked, never add them locally.
## Existing signals and giftData parsing remain available.
func redeem(code: String, idempotency_id: String = "") -> Dictionary:
	if code.is_empty():
		code_redeem_failed.emit(code, "Gift code is required")
		return {}
	if not _auth.isSignedIn() or _http.sessionToken.is_empty() or _auth.getCurrentUser().accessToken != _http.sessionToken:
		code_redeem_failed.emit(code, "User must be signed in")
		return {}
	if not idempotency_id.is_empty() and (_isBlankId(idempotency_id) or idempotency_id.to_utf16_buffer().size() > 256):
		return _failure(code, "INVALID_REQUEST", "Keep one nonblank original ID of at most128 UTF-16 units")
	var scope: Dictionary = _scope()
	var epoch: int = _epoch
	var values_epoch: int = _values.getCacheEpoch() if _values != null else -1
	var request: Dictionary = {"code": code, "userId": scope.user}
	if not idempotency_id.is_empty(): request.idempotencyId = idempotency_id
	var response: HorizonNetworkResponse = await _http.postAsync("/api/v1/app/gift-codes/redeem", request, true)
	if scope != _scope() or epoch != _epoch:
		return _failure(code, "STALE_RESPONSE", "Session or cache changed; retain the original redemption intent")
	if not response.isSuccess:
		return _failure(code, response.serverCode if not response.serverCode.is_empty() else "HTTP_%d" % response.statusCode, response.error)
	if not response.data is Dictionary or typeof(response.data.get("success")) != TYPE_BOOL or not HorizonPlayerValues._safeJsonIntegers(response.rawBody):
		return _failure(code, "INVALID_RESPONSE", "Invalid gift-code response; retain the original intent")
	var raw: Dictionary = response.data
	var message: Variant = raw.get("message", "")
	var gift_data: Variant = raw.get("giftData", "")
	if not message is String or (gift_data != null and not gift_data is String) or (raw.has("replayed") and typeof(raw.replayed) != TYPE_BOOL):
		return _failure(code, "INVALID_RESPONSE", "Invalid gift-code result")
	var grants: Variant = _parseGrantedValues(raw.get("grantedValues", []))
	var state: Variant = raw.get("playerValues")
	if grants == null or (state != null and HorizonPlayerValues._normalizeState(state).is_empty()) or (not grants.is_empty() and state == null):
		return _failure(code, "INVALID_RESPONSE", "Invalid server-owned value snapshot")
	if state != null:
		if _values != null and values_epoch != _values.getCacheEpoch():
			return _failure(code,"STALE_RESPONSE","Value cache changed; retain the original redemption intent")
		state = HorizonPlayerValues._normalizeState(state)
		if state.userId != scope.user:
			return _failure(code, "INVALID_RESPONSE", "Value snapshot belongs to another player")
		if raw.success and _values != null and not _values.acceptServerState(scope.user, state):
			return _failure(code, "STALE_RESPONSE", "A newer value snapshot is already retained")
	var unlocks: Array = _parseGrantedUnlocks(raw.get("grantedUnlocks"))
	if raw.success:
		if not unlocks.is_empty() and _playerProfile != null: _playerProfile.clearCache()
		code_redeemed.emit(code, gift_data if gift_data is String else "")
	else:
		code_redeem_failed.emit(code, message)
	return {"success": raw.success, "message": message, "giftData": gift_data, "grantedUnlocks": unlocks,
		"grantedValues": grants, "playerValues": state, "replayed": raw.get("replayed", false), "errorCode": ""}

## Parsed arbitrary giftData never becomes authoritative Player Values.
func redeemParsed(code: String, idempotency_id: String = "") -> Dictionary:
	var result: Dictionary = await redeem(code, idempotency_id)
	if result.is_empty(): return {}
	var parsed: Dictionary = {"success": result.success, "message": result.message,
		"grantedUnlocks": result.grantedUnlocks, "grantedValues": result.grantedValues,
		"playerValues": result.playerValues, "replayed": result.replayed, "errorCode": result.errorCode}
	var gift_data: Variant = result.giftData
	var rewards: Variant = JSON.parse_string(gift_data) if gift_data is String and not gift_data.is_empty() else null
	parsed.rewards = rewards if rewards is Dictionary else {}
	if gift_data != null and gift_data != "" and not rewards is Dictionary: parsed.rawGiftData = gift_data
	return parsed

## Generate once, persist with the original code before redeem(), then reuse across retries.
static func createRedemptionId() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20)]

func _scope() -> Dictionary:
	return {"host": _http.activeHost, "project": _http.apiKey, "session": _http.sessionToken, "user": _auth.getCurrentUser().userId, "generation": _http.getContextGeneration()}

func _reset() -> void:
	_epoch += 1

func _changedUser(_user: HorizonUserData) -> void:
	_reset()

func _failure(code: String, error_code: String, message: String) -> Dictionary:
	code_redeem_failed.emit(code, message)
	return {"success": false, "message": message, "giftData": "", "grantedUnlocks": [],
		"grantedValues": [], "playerValues": null, "replayed": false, "errorCode": error_code}

## Match Kotlin Char.isWhitespace (Java whitespace or space characters), not locale trimming.
## Godot strip_edges() omits NBSP and other Unicode spaces. Never rewrite the caller's ID.
static func _isBlankId(value: String) -> bool:
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if (code >= 0x09 and code <= 0x0d) or (code >= 0x1c and code <= 0x20) or code == 0x00a0 or code == 0x1680 or (code >= 0x2000 and code <= 0x200a) or code == 0x2028 or code == 0x2029 or code == 0x202f or code == 0x205f or code == 0x3000:
			continue
		return false
	return true

static func _parseGrantedValues(raw: Variant) -> Variant:
	if not raw is Array or raw.size() > 8: return null
	var values: Array = []
	var keys: Dictionary = {}
	var expression: RegEx = RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,23}\\z")
	for amount: Variant in raw:
		if not amount is Dictionary or not amount.get("key") is String or expression.search(amount.key) == null or keys.has(amount.key) or not HorizonPlayerValues._safeNumber(amount.get("amount")) or amount.amount <= 0:
			return null
		keys[amount.key] = true
		values.append({"key": amount.key, "amount": int(amount.amount)})
	return values

func _parseGrantedUnlocks(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for id: Variant in value:
			if id is String and not id.is_empty(): result.append(id)
	return result
