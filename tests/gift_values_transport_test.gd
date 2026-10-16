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
	var result: Dictionary = await gifts.redeem("VALUES",_id(1))
	if not _check(result.success and result.grantedValues[0].amount == 4294967296 and typeof(result.grantedValues[0].amount) == TYPE_INT and values.getCurrentState().values[0].balance == 4294967296,"Exact int64 grant and complete cache handoff"): return
	if not _check(profile.clears == 1 and not result.replayed,"Existing cosmetic cache invalidation preserved"): return
	result.playerValues.values[0].balance = 0
	if not _check(values.getCurrentState().values[0].balance == 4294967296,"Caller cannot change the cached snapshot"): return
	result = await gifts.redeem("VALUES",_id(1))
	if not _check(result.success and result.replayed and result.grantedValues[0].amount == 4294967296 and values.getCurrentState().values[0].balance == 4294967297,"Replay returns original grant and current balance, never adds deltas"): return
	result = await gifts.redeemParsed("PARSED",_id(2))
	if not _check(result.success and result.rewards.gold == 13 and result.grantedValues.is_empty() and result.playerValues == null and not result.replayed,"Legacy payload parsing and additive defaults preserved"): return
	result = await gifts.redeem("NULL",_id(3))
	if not _check(result.success and result.giftData == null,"Nullable original payload remains null"): return
	result = await gifts.redeem("BOUNDARY","x".repeat(128))
	if not _check(result.success,"Exactly128 ASCII ID units are accepted"): return
	result = await gifts.redeem("UNICODE","😀".repeat(64))
	if not _check(result.success,"Exactly128 UTF16 units remain unchanged on HTTP"): return
	result = await gifts.redeem("MAX",_id(4))
	if not _check(not result.success and result.errorCode == "MAX_BALANCE_REACHED" and values.getCurrentState().revision == 3,"Permanent business refusal preserves cache and code"): return
	result = await gifts.redeem("LEGACY")
	if not _check(not result.success and result.errorCode == "HTTP_503","Legacy outcome has one attempt and no invented ID"): return
	result = await gifts.redeem("RETRY",_id(5))
	if not _check(result.success and result.replayed and result.grantedValues[0].amount == 9007199254740991 and typeof(result.playerValues.values[0].balance) == TYPE_INT,"Lost explicit-ID response retries the exact request and retains safe maximum"): return
	result = await gifts.redeem("OPAQUE",_id(16))
	if not _check(result.success and result.giftData == '{"amount":1.0000000000000001}',"Opaque legacy JSON text is never interpreted as authoritative money"): return
	for item: Array in [["ESCAPED_AMOUNT",17],["ESCAPED_BALANCE",18],["DUPLICATE",19],["FRACTION",6],["STRING",7],["UNSAFE",8],["WRONG",9]]:
		result = await gifts.redeem(item[0],_id(item[1]))
		if not _check(not result.success and result.errorCode == "INVALID_RESPONSE" and values.getCurrentState().revision == 4,"Invalid response must not alter cache: " + item[0]): return
	result = await gifts.redeem("OLD",_id(10))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE" and values.getCurrentState().revision == 4,"Late lower revision cannot replace cache"): return
	create_timer(.04).timeout.connect(values.clearCache)
	result = await gifts.redeem("LEGACYCACHE")
	if not _check(result.success and result.giftData == '{"legacy":true}' and profile.clears == 2 and values.getCurrentState().is_empty(),"Unrelated PV invalidation cannot discard consumed legacy payload/callback/cosmetic refresh"): return
	create_timer(.04).timeout.connect(values.clearCache)
	result = await gifts.redeem("CACHE",_id(11))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE" and values.getCurrentState().is_empty(),"Explicit cache epoch fences late handoff"): return
	create_timer(.04).timeout.connect(func():
		http.sessionToken = "changed-session"
		auth._currentUser.accessToken = http.sessionToken)
	result = await gifts.redeem("SESSION",_id(12))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE" and values.getCurrentState().is_empty(),"Session change fences late handoff"): return
	http.sessionToken = "fixture-session-1007"
	auth._currentUser.accessToken = http.sessionToken
	create_timer(.04).timeout.connect(func():
		auth.signout_completed.emit()
		auth.signin_completed.emit(auth.getCurrentUser()))
	result = await gifts.redeem("ABA",_id(13))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE","Signout/signin ABA fences identical final credentials"): return
	for item: Array in [["HOSTABA",20,"activeHost"],["PROJECTABA",21,"apiKey"],["TOKENABA",22,"sessionToken"]]:
		var property: String = item[2]
		var original: String = http.get(property)
		create_timer(.04).timeout.connect(func():
			http.set(property,original + "-temporary")
			http.set(property,original))
		result = await gifts.redeem(item[0],_id(item[1]))
		if not _check(not result.success and result.errorCode == "STALE_RESPONSE","Synchronous context generation rejects " + item[0]): return
	http.retryDelaySeconds = .12
	create_timer(.04).timeout.connect(func():
		http.sessionToken = "changed-session"
		auth._currentUser.accessToken = http.sessionToken)
	result = await gifts.redeem("BACKOFF",_id(14))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE","Backoff cannot resend under changed identity"): return
	http.sessionToken = "fixture-session-1007"
	auth._currentUser.accessToken = http.sessionToken
	create_timer(.04).timeout.connect(func():
		http.sessionToken = "temporary-backoff-session"
		http.sessionToken = "fixture-session-1007")
	result = await gifts.redeem("BACKOFFABA",_id(23))
	if not _check(not result.success and result.errorCode == "STALE_RESPONSE","Backoff rejects credential ABA without another HTTP attempt"): return
	var invalid_ids: Array[String] = [" ", "x".repeat(129), "😀".repeat(65), " \t\u00a0\u2007\u202f"]
	var blank_codes: Array[int] = [0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x00a0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
	for code: int in range(0x2000, 0x200b): blank_codes.append(code)
	for code: int in blank_codes: invalid_ids.append(String.chr(code))
	if not _check(not HorizonGiftCodes._isBlankId("\u200b") and not HorizonGiftCodes._isBlankId("\u0085") and not HorizonGiftCodes._isBlankId("\u00a0original\u00a0"), "Only the server's exact whitespace set is blank; nonblank caller IDs are never trimmed"): return
	for bad: String in invalid_ids:
		result = await gifts.redeem("LOCAL",bad)
		if not _check(not result.success and result.errorCode == "INVALID_REQUEST","Invalid explicit ID must fail before HTTP"): return
	if not _check(events.redeemed == 9,"Rejected/stale responses never emit a success callback"): return
	http.sessionToken = ""
	if not _check((await gifts.redeem("UNSIGNED",_id(15))).is_empty(),"Unsigned redemption is not sent"): return
	await create_timer(1.8).timeout
	print("Godot gift values: %d native assertions,28 exact HTTP requests" % assertions)
	http.queue_free()
	quit(0)
