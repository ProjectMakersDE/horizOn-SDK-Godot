extends SceneTree
const U := "00000000-0000-4000-8000-000000001014"
const C := "00000000-0000-4000-8000-000000003014"
const E := "00000000-0000-4000-8000-000000004014"
const M := "00000000-0000-4000-8000-000000008014"
var http: HorizonHttpClient
var auth: HorizonAuth
var realtime: HorizonRealtime
var chat: HorizonChat
var checks: int = 0
var late: Dictionary = {}
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: push_error(message); quit(1)
func _initialize() -> void: call_deferred("run")
func wait_result() -> void:
	var end: int = Time.get_ticks_msec() + 4000
	while late.is_empty() and Time.get_ticks_msec() < end: await process_frame
	check(not late.is_empty(), "actual delayed raw HTTP completed")
func control(name: String) -> Dictionary:
	var result: HorizonNetworkResponse = await http.getAsync("/fixture/" + name)
	check(result.isSuccess, "fixture control " + name)
	return result.asDict()
func empty_feed() -> bool:
	return chat._cache.is_empty() and chat._watches.is_empty() and chat._floors.is_empty() and chat._serverMillis == -1 and chat._clockMillis == -1 and realtime._topics.is_empty() and chat.getCached(C).is_empty()
func run() -> void:
	var port: String = OS.get_environment("HORIZON_CHAT_SNAPSHOT_TEST_PORT")
	if port.is_empty(): port = "20116"
	http = HorizonHttpClient.new(); root.add_child(http); http.initialize(HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	http.activeHost = "http://127.0.0.1:" + port; http.apiKey = "raw-chat-key"; http.sessionToken = "raw-chat-session"
	http.maxRetryAttempts = 3; http.retryDelaySeconds = .01
	auth = HorizonAuth.new(); auth.initialize(http, HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	auth._currentUser.userId = U; auth._currentUser.accessToken = "raw-chat-session"
	realtime = HorizonRealtime.new(); root.add_child(realtime); realtime.initialize(http, auth)
	chat = HorizonChat.new(); root.add_child(chat); chat.initialize(http, auth, realtime)
	check((await chat.syncChannel(U,C)).errorCode == "SUBSCRIPTION_REQUIRED", "managed read remains subscription-only")
	var first: Dictionary = await chat.requestChannelSnapshot(U,C)
	check(first.success and first.data.messages.size() == 1 and first.data.messages[0].text == "raw original é😀", "typed raw disconnected REST snapshot succeeds")
	check(empty_feed(), "raw success creates no watch, feed or expiry clock")
	var known: Array[String] = [M]
	var incremental: Dictionary = await chat.requestChannelSnapshot(U,C,E,known)
	check(incremental.success and incremental.data.messages.is_empty() and incremental.data.visibleMessageIds == [M], "raw known-ID envelope stays incremental without cache merge")
	check(empty_feed(), "incremental result remains invisible to managed cache")
	check((await chat.requestChannelSnapshot(U,"bad")).errorCode == "INVALID_REQUEST", "channel identity checked before HTTP")
	check((await chat.requestChannelSnapshot(U,C,"bad")).errorCode == "INVALID_REQUEST", "epoch identity checked before HTTP")
	var duplicate: Array[String] = [M,M]
	check((await chat.requestChannelSnapshot(U,C,E,duplicate)).errorCode == "INVALID_REQUEST", "duplicate known IDs rejected")
	var oversized: Array[String] = []; oversized.resize(101); oversized.fill(M)
	check((await chat.requestChannelSnapshot(U,C,E,oversized)).errorCode == "INVALID_REQUEST", "known-ID hard bound rejected")
	check(int((await control("status")).count) == 2, "invalid inputs made no HTTP call")
	check((await chat.requestChannelSnapshot(U,C)).errorCode == "RAW_SNAPSHOT_FAULT", "raw503 performs one transport attempt")
	check((await chat.requestChannelSnapshot(U,C)).errorCode == "NOT_SUPPORTED", "disconnected PHP501 reaches caller once")
	for identity: String in ["host","session","project"]:
		late.clear(); read_snapshot(); await create_timer(.04).timeout
		match identity:
			"host":
				var host: String = http.activeHost; http.activeHost = "http://127.0.0.1:1"; http.activeHost = host
			"session":
				http.sessionToken = "other"; auth._currentUser.accessToken = "other"; http.sessionToken = "raw-chat-session"; auth._currentUser.accessToken = "raw-chat-session"
			"project": http.apiKey = "other"; http.apiKey = "raw-chat-key"
		await wait_result()
		check(not late.success and late.errorCode == "STALE_RESPONSE" and empty_feed(), identity + " ABA rejects late raw snapshot")
	late.clear(); read_snapshot(known); await create_timer(.04).timeout; known.append("00000000-0000-4000-8000-000000008015")
	await wait_result()
	check(late.success and late.data.messages.is_empty(), "caller list mutation cannot change frozen known-ID request")
	check((await chat.requestChannelSnapshot(U,C)).errorCode == "INVALID_RESPONSE", "missing unknown text fails closed in raw response")
	var epoch_changed: Dictionary = await chat.requestChannelSnapshot(U,C,E,[M])
	check(epoch_changed.success and epoch_changed.data.messages.size() == 1, "fresh epoch requires full unknown text rather than reusing old known IDs")
	check((await chat.requestChannelSnapshot(U,C)).errorCode == "SESSION_REQUIRED", "raw401 is explicit")
	check((await chat.requestChannelSnapshot(U,C)).success and empty_feed(), "later explicit raw read succeeds without feed adoption")
	check((await chat.syncChannel(U,C)).errorCode == "SUBSCRIPTION_REQUIRED", "raw success never authorizes managed feed")
	await create_timer(.1).timeout
	var stats: Dictionary = await control("status")
	check(int(stats.count) == 12 and stats.failure == null, "exact12 actual snapshots, no retries or background reads")
	await control("finish")
	chat.queue_free(); realtime.queue_free(); http.queue_free()
	print("Godot raw Chat: %d native checks,12 exact HTTP, disconnected/501/once-only/stale identity/immutable inputs/no cache adoption passed" % checks)
	quit(0)
func read_snapshot(ids: Array[String] = []) -> void: late = await chat.requestChannelSnapshot(U,C,E if not ids.is_empty() else "",ids)
