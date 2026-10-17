extends SceneTree
const USER := "00000000-0000-4000-8000-000000001004"
const OP := "1792065600000:00000000-0000-4000-8000-000000001004"
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	if HorizonPlayerValues._safeJsonIntegers('{"balance":9007199254740991.1}') or HorizonPlayerValues._safeJsonIntegers('{"amount":9007199254740992}') or HorizonPlayerValues._safeNumber(-9223372036854775807 - 1):
		_fail("fractional and out-of-range numbers must not round into safe integers")
		return
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "fixture-key-1004"
	http.activeHost = "http://127.0.0.1:18905"
	http.sessionToken = "fixture-session-1004"
	http.maxRetryAttempts = 0
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var values := HorizonPlayerValues.new()
	values.initialize(http, auth)
	var loaded := await values.getState(USER)
	if not loaded.success or loaded.state.values[0].balance != 9007199254740991 or typeof(loaded.state.values[0].balance) != TYPE_INT or loaded.state.values[0].dailyCap != null or loaded.state.values[1].dailyCap != 0:
		_fail("safe int64 and nullable caps must survive actual HTTP parsing")
		return
	var generated := values.createOperationId()
	if not HorizonPlayerValues._validOperationId(generated) or absi(int(generated.get_slice(":", 0)) - HorizonPlayerValues._timeMillis("2026-10-15T12:00:10Z")) > 5000:
		_fail("operation ID must use learned server clock")
		return
	loaded.state.values[0].balance = 1
	if values.getCurrentState().values[0].balance != 9007199254740991:
		_fail("caller must not mutate manager cache")
		return
	var offers := await values.getOffers(USER)
	if not offers.success or typeof(offers.data.offers[0].costs[0].amount) != TYPE_INT:
		_fail("offer costs must remain int64")
		return
	var expired := await values.purchase(USER, "energy-pack", OP)
	if expired.success or expired.errorCode != "OPERATION_EXPIRED" or expired.state.revision != 11 or values.getCurrentState().revision != 11:
		_fail("business failure must return and cache current state, with no new operation")
		return
	var adjusted := await values.adjust(USER, "gold", -9007199254740991, "debug", OP.replace("1004", "1005"))
	if not adjusted.success:
		_fail("valid adjustment must use exact signed int64 request")
		return
	create_timer(.04).timeout.connect(values.clearCache)
	if (await values.getState(USER)).errorCode != "STALE_RESPONSE" or not values.getCurrentState().is_empty():
		_fail("clearCache must invalidate in-flight responses")
		return
	if (await values.getState(USER)).errorCode != "STALE_RESPONSE":
		_fail("revision watermark must survive clearCache")
		return
	if not (await values.getOffers(USER)).success or not values.getCurrentState().is_empty():
		_fail("new catalogue must clear old snapshot")
		return
	if (await values.getState(USER)).errorCode != "STALE_RESPONSE" or (await values.getState(USER)).errorCode != "STALE_RESPONSE":
		_fail("revision and time watermark must survive catalogue invalidation")
		return
	if not (await values.getState(USER)).success:
		_fail("fresh revision and time must load")
		return
	var expanded := await values.getOffers(USER)
	if not expanded.success or expanded.data.definitions.size() != 80 or expanded.data.offers.size() != 1201 or expanded.data.offers[0].get("purchasesPerDay") != null:
		_fail("configured catalogues above former tariff defaults remain readable without offer-day quotas")
		return
	var retained := await values.getState(USER)
	if not retained.success or retained.state.values.size() != 80:
		_fail("all configured balances above the old64 ceiling must survive HTTP/cache")
		return
	var compact_op: String = OP.replace("1004", "1006")
	var fresh := await values.purchase(USER, "energy-pack", compact_op)
	if not fresh.success or fresh.state.operation.replayed or fresh.state.operation.applied.size() != 2:
		_fail("fresh purchase keeps its original request and immediate applied values")
		return
	var replay := await values.purchase(USER, "energy-pack", compact_op)
	if not replay.success or not replay.state.operation.replayed or replay.state.operation.operationId != compact_op or not replay.state.operation.applied.is_empty() or not replay.state.operation.items.is_empty():
		_fail("compact replay confirms the same original with no copied historical deltas/references")
		return
	var current: Dictionary = values.getCurrentState()
	if current.values.size() != 80 or current.values[0].balance != 33 or current.values[0].earnedToday != 50 or current.values[0].dailyCap != 0 or not values.getCurrentOffers().is_empty():
		_fail("current balances survive a lowered cap; replay replaces state and retires older catalogue without polling")
		return
	create_timer(.04).timeout.connect(func():
		auth._currentUser.clear()
		http.sessionToken = ""
		auth.signout_completed.emit())
	if (await values.getState(USER)).errorCode != "STALE_RESPONSE" or not values.getCurrentState().is_empty():
		_fail("signout must reject late balance")
		return
	if (await values.getState(USER)).errorCode != "SESSION_REQUIRED":
		_fail("signed out request must fail locally")
		return
	if (await values.adjust(USER, "gold", 9007199254740992, "debug", OP)).errorCode != "INVALID_REQUEST" or (await values.adjust(USER, "gold", 1.5, "debug", OP)).errorCode != "INVALID_REQUEST":
		_fail("unsafe and fractional adjustment must fail locally")
		return
	await create_timer(1.8).timeout
	print("Godot player values REST,80balances/1201offers, compact replay, safe int64, clock and stale response races passed")
	http.queue_free()
	quit(0)
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
