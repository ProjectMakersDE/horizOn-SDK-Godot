extends SceneTree
func _initialize() -> void:
	var realtime := HorizonRealtime.new()
	if not realtime.subscribe("inbox:player") or realtime.subscribe("inbox:") or realtime.subscribe("chat:bad/value"):
		push_error("invalid subscription policy")
		quit(1)
		return
	if HorizonRealtime.canPoll("chat:group") or not HorizonRealtime.canPoll("matches:game"):
		push_error("chat must never fall back to polling")
		quit(1)
		return
	if HorizonRealtime.reconnectDelay(100, 1.0) != 30.0 or HorizonRealtime.reconnectDelay(0, 0.5) != 0.5:
		push_error("jitter must grow and be capped")
		quit(1)
		return
	for i: int in range(31):
		if not realtime.subscribe("matches:%d" % i):
			quit(1)
			return
	if realtime.subscribe("matches:overflow"):
		push_error("subscription count must be bounded")
		quit(1)
		return
	# An old subscribed response can precede the unsubscribe response after a quick resubscribe.
	realtime._pending = "matches:0"
	realtime.unsubscribe("matches:0")
	realtime.subscribe("matches:0")
	realtime._handle({"type": "subscribed", "version": 1, "topic": "matches:0"})
	realtime._handle({"type": "unsubscribed", "version": 1, "topic": "matches:0"})
	if realtime._sent.has("matches:0"):
		push_error("late unsubscribe must clear confirmed state")
		quit(1)
		return
	# Callbacks may close the manager while the global resync enumerates desired subscriptions.
	realtime.resync_required.connect(func(_topic: String): realtime.close())
	realtime._handle({"type": "resync_required", "version": 1})
	if not realtime._topics.is_empty():
		quit(1)
		return
	realtime.free()
	print("Realtime policy tests passed")
	quit(0)
