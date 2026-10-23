# Run against the Server repository's realtime-gateway/test/sdk-fixture.js.
extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var url: String = OS.get_environment("HORIZON_REALTIME_FIXTURE_URL")
	if url.is_empty():
		push_error("HORIZON_REALTIME_FIXTURE_URL is required")
		quit(1)
		return
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	http.activeHost = url
	http.apiKey = "fixture-key"
	http.sessionToken = "fixture-session"
	http.maxRetryAttempts = 0
	var auth := HorizonAuth.new()
	auth.initialize(http, HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	auth._currentUser.userId = "00000000-0000-4000-8000-000000000003"
	auth._currentUser.accessToken = "fixture-session"
	var realtime := HorizonRealtime.new()
	root.add_child(realtime)
	realtime.initialize(http, auth)
	var result: Dictionary = {"event": {}, "resync": 0}
	realtime.event_received.connect(func(event: Dictionary): result["event"] = event)
	realtime.resync_required.connect(func(_topic: String): result["resync"] += 1)
	var topic: String = "inbox:" + auth._currentUser.userId
	realtime.subscribe(topic)
	var deadline: int = Time.get_ticks_msec() + 15000
	while not realtime._sent.has(topic) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not realtime.isReady or not realtime._sent.has(topic):
		push_error("Realtime did not authenticate and subscribe: " + realtime.lastErrorCode)
		quit(1)
		return
	await http.getAsync("/fixture/event")
	while result["event"].is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if result["event"].get("revision", 0) != 7 or result["resync"] < 1 or realtime.pollAfterSeconds != 2:
		push_error("Realtime event/snapshot contract failed")
		quit(1)
		return
	# Subscribe from a new login callback before the next process tick.
	auth._currentUser.userId = "00000000-0000-4000-8000-000000000099"
	auth._currentUser.accessToken = "new-session"
	http.sessionToken = "new-session"
	realtime.subscribe("matches:new-user")
	if realtime._topics.has(topic) or not realtime._topics.has("matches:new-user"):
		push_error("new account subscription was lost or old account retained")
		quit(1)
		return
	realtime.close()
	if realtime.isReady:
		quit(1)
		return
	print("Realtime WebSocket transport passed")
	quit(0)
