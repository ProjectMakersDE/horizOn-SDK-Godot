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
var _lastErrorCode: String = ""


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


## Canonical Int64 strings avoid Godot JSON's floating-point number conversion.
static func canonicalCount(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 19: return false
	if value.length() > 1 and value[0] == "0": return false
	for character: String in value:
		if character < "0" or character > "9": return false
	return value.length() < 19 or value <= "9223372036854775807"

static func validIntent(intent: Variant, project: String, user: String) -> bool:
	return intent is Dictionary and intent.size() == 7 and intent.get("protocolVersion") == 2 and intent.get("projectScope") == project.sha256_text() and intent.get("userId") == user and not user.is_empty() and intent.get("code") is String and not intent.code.strip_edges().is_empty() and intent.code.length() <= 50 and _uuid(intent.get("campaignId")) and canonicalCount(intent.get("expectedCount")) and canonicalCount(intent.get("configRevision"))

static func _uuid(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z").search(value) != null

func _hasSession() -> bool:
	return _auth.isSignedIn() and not _http.sessionToken.is_empty() and _auth.getCurrentUser().accessToken == _http.sessionToken

func getLastErrorCode() -> String:
	return _lastErrorCode

## Read-only validity check, without a session requirement.
func validate(code: String) -> Variant:
	if code.strip_edges().is_empty() or code.length() > 50: return null
	var response: HorizonNetworkResponse = await _http.postAsync("/api/v1/app/gift-codes/validate", {"code":code}, false)
	if not response.isSuccess or not response.data is Dictionary or typeof(response.data.get("valid")) != TYPE_BOOL: return null
	code_validated.emit(code,response.data.valid)
	return response.data.valid

## Read-only preparation. Persist every returned field before redeemPrepared().
func prepareRedemption(code: String) -> Dictionary:
	_lastErrorCode = ""
	if code.strip_edges().is_empty() or code.length() > 50: return _prepareFailure("INVALID_REQUEST")
	if not _hasSession(): return _prepareFailure("SESSION_REQUIRED")
	var scope: Dictionary = _scope()
	var epoch: int = _epoch
	var response: HorizonNetworkResponse = await _http.postAsync("/api/v1/app/gift-codes/validate", {"code":code,"userId":scope.user,"includeIntent":true},true)
	if scope != _scope() or epoch != _epoch: return _prepareFailure("STALE_RESPONSE")
	if not response.isSuccess: return _prepareFailure(HorizonInbox._responseCode(response))
	if not response.data is Dictionary or typeof(response.data.get("valid")) != TYPE_BOOL: return _prepareFailure("INVALID_RESPONSE")
	if not response.data.valid: return _prepareFailure("CODE_NOT_ELIGIBLE")
	var raw: Dictionary = response.data
	var intent: Dictionary = {"protocolVersion":raw.get("protocolVersion"),"projectScope":str(scope.project).sha256_text(),"userId":scope.user,"code":code,"campaignId":raw.get("campaignId"),"expectedCount":raw.get("expectedCount"),"configRevision":raw.get("configRevision")}
	if not validIntent(intent,scope.project,scope.user): return _prepareFailure("INVALID_RESPONSE")
	return intent

func _prepareFailure(error: String) -> Dictionary:
	_lastErrorCode = error
	return {}

## V1 never silently advances a counter or prepares a replacement operation.
func redeem(code: String, _idempotency_id: String = "") -> Dictionary:
	return _failure(code,"UPGRADE_REQUIRED","Prepare, persist and send a V2 intent; reconcile old V1 operations")

## A restart or uncertain outcome reuses this exact scoped tuple. No preparation occurs here.
func redeemPrepared(original: Dictionary) -> Dictionary:
	_lastErrorCode = ""
	if not _hasSession(): return _failure("","SESSION_REQUIRED","Player session required")
	var scope: Dictionary = _scope()
	if not validIntent(original,scope.project,scope.user): return _failure("","INVALID_REQUEST","Original scoped V2 intent required")
	var intent: Dictionary = original.duplicate(true)
	var code: String = intent.code
	var epoch: int = _epoch
	var values_epoch: int = _values.getCacheEpoch() if _values != null else -1
	var request: Dictionary = {"code":code,"userId":intent.userId,"protocolVersion":2,"campaignId":intent.campaignId,"expectedCount":intent.expectedCount,"configRevision":intent.configRevision}
	var response: HorizonNetworkResponse = await _http.postAsync("/api/v1/app/gift-codes/redeem",request,true)
	if scope != _scope() or epoch != _epoch: return _failure(code,"STALE_RESPONSE","Identity changed; original intent retained")
	if not response.isSuccess: return _failure(code,HorizonInbox._responseCode(response),response.error)
	if not response.data is Dictionary or typeof(response.data.get("success")) != TYPE_BOOL or not HorizonPlayerValues._safeJsonIntegers(response.rawBody):
		return _failure(code,"INVALID_RESPONSE","Invalid result")
	var raw: Dictionary = response.data
	var message: Variant = raw.get("message", "")
	var gift_data: Variant = raw.get("giftData")
	if not message is String or (gift_data != null and not gift_data is String) or typeof(raw.get("replayed")) != TYPE_BOOL or typeof(raw.get("alreadyApplied")) != TYPE_BOOL or raw.replayed != raw.alreadyApplied or raw.get("campaignId") != intent.campaignId or not canonicalCount(raw.get("count")) or not canonicalCount(raw.get("configRevision")):
		return _failure(code,"INVALID_RESPONSE","Invalid sequence result")
	if str(raw.count).pad_zeros(19) <= str(intent.expectedCount).pad_zeros(19): return _failure(code,"INVALID_RESPONSE","Sequence was not consumed")
	if not raw.alreadyApplied and (raw.count != str(int(intent.expectedCount)+1) or raw.configRevision != intent.configRevision): return _failure(code,"INVALID_RESPONSE","Fresh sequence differs from prepared identity")
	var grants: Variant = _parseGrantedValues(raw.get("grantedValues", []))
	var unlocks: Variant = raw.get("grantedUnlocks", [])
	if grants == null or not unlocks is Array: return _failure(code,"INVALID_RESPONSE","Invalid grants")
	for item: Variant in unlocks:
		if not item is String: return _failure(code,"INVALID_RESPONSE","Invalid cosmetic grant")
	if raw.alreadyApplied and (gift_data != null or not grants.is_empty() or not unlocks.is_empty()): return _failure(code,"INVALID_RESPONSE","Replay must not carry historical rewards")
	var state: Variant = raw.get("playerValues")
	if (state != null and HorizonPlayerValues._normalizeState(state).is_empty()) or (not grants.is_empty() and state == null): return _failure(code,"INVALID_RESPONSE","Invalid complete state")
	if state != null:
		state = HorizonPlayerValues._normalizeState(state)
		if state.userId != scope.user: return _failure(code,"INVALID_RESPONSE","Foreign value state")
		if _values != null and (values_epoch != _values.getCacheEpoch() or (raw.success and not _values.acceptServerState(scope.user,state))): return _failure(code,"STALE_RESPONSE","Value cache changed")
	if raw.success:
		if (raw.alreadyApplied or not unlocks.is_empty()) and _playerProfile != null: _playerProfile.clearCache()
		code_redeemed.emit(code,gift_data if gift_data is String else "")
	return {"success":raw.success,"message":message,"giftData":gift_data,"grantedUnlocks":unlocks,"grantedValues":grants,"playerValues":state,"replayed":raw.replayed,"alreadyApplied":raw.alreadyApplied,"campaignId":raw.campaignId,"count":raw.count,"configRevision":raw.configRevision,"errorCode":""}

func redeemPreparedParsed(intent: Dictionary) -> Dictionary:
	var result: Dictionary = await redeemPrepared(intent)
	if not result.get("success",false): return result
	var raw: Variant = result.giftData
	var rewards: Variant = JSON.parse_string(raw) if raw is String and not raw.is_empty() else null
	result.rewards = rewards if rewards is Dictionary else {}
	return result

func redeemParsed(code: String, _idempotency_id: String = "") -> Dictionary:
	return await redeem(code,_idempotency_id)

func _scope() -> Dictionary:
	return {"host": _http.activeHost, "project": _http.apiKey, "session": _http.sessionToken, "user": _auth.getCurrentUser().userId, "generation": _http.getContextGeneration()}

func _reset() -> void:
	_epoch += 1

func _changedUser(_user: HorizonUserData) -> void:
	_reset()

func _failure(code: String, error_code: String, message: String) -> Dictionary:
	_lastErrorCode = error_code
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
