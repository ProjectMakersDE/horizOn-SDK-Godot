extends SceneTree
const USER := "00000000-0000-4000-8000-000000001007"
class ProfileProbe extends HorizonPlayerProfile:
	var clears: int = 0
	func clearCache() -> void: clears += 1
var assertions: int = 0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	assertions += 1
	return ok
func _id(n: int) -> String: return "00000000-0000-4000-8000-%012d" % n
func _run() -> void:
	var logger: HorizonLogger = HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http: HorizonHttpClient = HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "fixture-key-1007"
	http.activeHost = "http://127.0.0.1:18907"
	http.sessionToken = "fixture-session-1007"
	http.maxRetryAttempts = 2
	http.retryDelaySeconds = .02
	var auth: HorizonAuth = HorizonAuth.new()
	auth.initialize(http,logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var values: HorizonPlayerValues = HorizonPlayerValues.new()
	values.initialize(http,auth)
	var profile: ProfileProbe = ProfileProbe.new()
	var gifts: HorizonGiftCodes = HorizonGiftCodes.new()
	gifts.initialize(http,logger,auth)
	gifts.setPlayerValues(values)
	gifts.setPlayerProfile(profile)
	var events: Dictionary = {"redeemed":0}
	gifts.code_redeemed.connect(func(_code: String,_data: String): events.redeemed += 1)
	var prepared: Dictionary = await gifts.prepareRedemption("VALUES")
	var second: Dictionary = await gifts.prepareRedemption("VALUES")
	if not _check(prepared == second and prepared.expectedCount == "9007199254740993" and prepared.configRevision == "9223372036854775807","Prepared exact Int64 tuple shared by two devices"): return
	var saved: String = JSON.stringify(prepared)
	var result: Dictionary = await gifts.redeemPrepared(prepared)
	if not _check(result.get("success",false) and result.alreadyApplied and result.giftData == null and result.grantedValues.is_empty() and values.getCurrentState().values[0].balance == 100,"Lost response retries original tuple and replaces balances"): return
	result = await gifts.redeemPrepared(JSON.parse_string(saved))
	if not _check(result.success and result.alreadyApplied and result.grantedUnlocks.is_empty(),"Process restart retries same tuple without historical rewards"): return
	var reused: Dictionary = await gifts.prepareRedemption("VALUES")
	if not _check(reused.campaignId != prepared.campaignId,"Visible code can now point at another campaign"): return
	result = await gifts.redeemPrepared(prepared)
	if not _check(result.success and result.campaignId == prepared.campaignId,"Old pending identity is never retargeted by visible code reuse"): return
	for error: String in ["COUNT_AHEAD","CAMPAIGN_CHANGED","UPGRADE_REQUIRED","MIGRATION_REQUIRED","COUNTER_EXHAUSTED"]:
		var intent: Dictionary = prepared.duplicate(true)
		intent.code = error
		result = await gifts.redeemPrepared(intent)
		if not _check(not result.success and result.errorCode == error,"Domain code returned without preparing or advancing: " + error): return
	for code: String in ["NUMERIC","OVERFLOW","HISTORY"]:
		var intent: Dictionary = prepared.duplicate(true)
		intent.code = code
		result = await gifts.redeemPrepared(intent)
		if not _check(not result.success and result.errorCode == "INVALID_RESPONSE","Malformed exact counters/history refused: " + code): return
	for code: String in ["CACHE","SESSION","PROJECT","SIGNOUT"]:
		var intent: Dictionary = prepared.duplicate(true)
		intent.code = code
		create_timer(.04).timeout.connect(func():
			if code == "CACHE": values.clearCache()
			if code == "SESSION":
				http.sessionToken = "temporary"
				http.sessionToken = "fixture-session-1007"
			if code == "PROJECT":
				http.apiKey = "temporary"
				http.apiKey = "fixture-key-1007"
			if code == "SIGNOUT":
				auth.signout_completed.emit()
				auth.signin_completed.emit(auth.getCurrentUser()))
		result = await gifts.redeemPrepared(intent)
		if not _check(not result.success and result.errorCode == "STALE_RESPONSE","In-flight identity/cache fence: " + code): return
	prepared = await gifts.prepareRedemption("TWO")
	second = await gifts.prepareRedemption("TWO")
	result = await gifts.redeemPrepared(prepared)
	if not _check(result.success and not result.alreadyApplied and result.grantedValues[0].amount == 7,"Fresh slot exposes immediate grants once"): return
	result = await gifts.redeemPrepared(second)
	if not _check(result.success and result.alreadyApplied and result.grantedValues.is_empty() and result.giftData == null and values.getCurrentState().values[0].balance == 100,"Two-device contention consumes one logical slot"): return
	for code: String in ["NUMERIC","OVERFLOW"]:
		if not _check((await gifts.prepareRedemption(code)).is_empty() and gifts.getLastErrorCode() == "INVALID_RESPONSE","Malformed prepared exact count refused"): return
	for invalid: String in ["", "00","01","+1","-1","1.0","1e2"," 1","9223372036854775808"]:
		if not _check(not HorizonGiftCodes.canonicalCount(invalid),"Invalid canonical integer rejected: " + invalid): return
	var foreign: Dictionary = prepared.duplicate(true)
	foreign.userId = "another-player"
	if not _check((await gifts.redeemPrepared(foreign)).errorCode == "INVALID_REQUEST","Pending identity cannot move to another player"): return
	foreign = prepared.duplicate(true)
	foreign.projectScope = "another-project"
	if not _check((await gifts.redeemPrepared(foreign)).errorCode == "INVALID_REQUEST","Pending identity cannot move to another project"): return
	if not _check((await gifts.redeem("V1","old-id")).errorCode == "UPGRADE_REQUIRED","V1 explicit error without HTTP"): return
	http.sessionToken = ""
	if not _check((await gifts.redeemPrepared(prepared)).errorCode == "SESSION_REQUIRED","No unsigned request sent"): return
	await create_timer(1.3).timeout
	print("Godot V2 Gift: %d native assertions and25 exact HTTP requests" % assertions)
	http.queue_free()
	quit(0)
