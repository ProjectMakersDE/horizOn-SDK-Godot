extends SceneTree
const Example = preload("res://addons/horizon_sdk/examples/features/chat_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_chat.gd")
const U := "00000000-0000-4000-8000-000000001014"
const C := "00000000-0000-4000-8000-000000003014"
const T := "2026-10-16T12:00:00.000Z"
const O := "00000000-0000-4000-8000-000000005014"
class Fixture extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var chat: HorizonChat
var http: HorizonHttpClient
var auth: HorizonAuth
var realtime: HorizonRealtime
var chat: HorizonChat
var h: Fixture
var checks: int = 0
var failures: int = 0
var updates: int = 0
var codes: Array = []
var late: Dictionary = {}
var late_sync: Dictionary = {}
var late_write: Dictionary = {}
var invalidate_feed: bool = false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		if chat != null: print("Chat fault state: ", {"watch": chat._watches, "cacheKeys": chat._cache.keys(), "codes": codes, "topics": realtime._topics, "sent": realtime._sent, "gateway": realtime.lastErrorCode})
		quit(1)
func _initialize() -> void: call_deferred("run")
func wait_for(predicate: Callable, description: String) -> void:
	var end: int = Time.get_ticks_msec() + 6000
	while not predicate.call() and Time.get_ticks_msec() < end: await process_frame
	check(predicate.call(), description)
func control(name: String) -> Dictionary:
	var result: HorizonNetworkResponse = await http.getAsync("/fixture/" + name)
	check(result.isSuccess, "fixture control " + name)
	return result.asDict()
func run() -> void:
	var port: String = OS.get_environment("HORIZON_CHAT_TEST_PORT")
	var ws_port: String = OS.get_environment("HORIZON_CHAT_WS_TEST_PORT")
	if port.is_empty(): port = "20114"
	if ws_port.is_empty(): ws_port = "20115"
	http = HorizonHttpClient.new(); root.add_child(http)
	http.initialize(HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	http.activeHost = "http://127.0.0.1:" + port; http.apiKey = "chat-key"; http.sessionToken = "chat-session"
	http.maxRetryAttempts = 3; http.retryDelaySeconds = 0.01
	auth = HorizonAuth.new(); auth.initialize(http, HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	auth._currentUser.userId = U; auth._currentUser.accessToken = "chat-session"
	realtime = HorizonRealtime.new(); root.add_child(realtime); realtime.initialize(http, auth)
	realtime.gatewayUrl = "ws://127.0.0.1:" + ws_port
	chat = HorizonChat.new(); root.add_child(chat); chat.initialize(http, auth, realtime)
	chat.channel_changed.connect(func(_id: String, _data: Dictionary):
		updates += 1
		if invalidate_feed: chat.clearCache())
	chat.chat_failed.connect(func(_error: String, code: String): codes.append(code))
	h = Fixture.new(); h.name = "Horizon"; h._http = http; h.auth = auth; h.chat = chat; root.add_child(h)
	check((await chat.getLimits(U)).success, "limits and explicit null moderation")
	check((await chat.openChannel(U, "project")).success, "explicit project channel allocation")
	check((await chat.openChannel(U, "direct", "00000000-0000-4000-8000-000000002014")).success, "direct open preserves exact peer context")
	check((await chat.openChannel(U, "group", "", "00000000-0000-4000-8000-000000007014")).success, "group open preserves exact membership context")
	check((await chat.syncChannel(U, C)).errorCode == "SUBSCRIPTION_REQUIRED", "no HTTP snapshot before authorized subscription")
	check(chat.watchChannel(U, C), "subscribe before first feed")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "empty channel gets initial real WS resync")
	check(chat.getCached(C).messages.is_empty(), "empty channel is a complete usable snapshot")
	var normal_history: HorizonChatHistory = chat._history
	var io_blocker: String = "user://chat-history-io-blocker"
	var io_file: FileAccess = FileAccess.open(io_blocker, FileAccess.WRITE); io_file.store_string("test-owned blocker"); io_file.close()
	var history_errors: Array[String] = []
	chat.local_history_failed.connect(func(_channel: String, code: String): history_errors.append(code))
	chat._history = HorizonChatHistory.new(http.apiKey, U, io_blocker)
	var sent: Dictionary = await chat.sendMessage(U, C, O, T, "hello é😀\n\t<text>")
	check(sent.success and not sent.data.replayed and not sent.data.receipt.has("text"), "single send stores receipt metadata only")
	check("LOCAL_HISTORY_IO" in history_errors and sent.success, "real local I/O failure emits separate event while original server send succeeds")
	chat._history = normal_history
	DirAccess.remove_absolute(ProjectSettings.globalize_path(io_blocker))
	await wait_for(func() -> bool: return chat.getCached(C).get("messages", []).size() == 1, "first message pushed into empty channel")
	var message_id: String = sent.data.receipt.messageId
	var replay: Dictionary = await chat.sendMessage(U, C, O, T, "hello é😀\n\t<text>")
	check(replay.success and replay.data.replayed and replay.data.receipt == sent.data.receipt, "identical explicit original send replay")
	check((await chat.getOperation(U, O)).data.receipt == sent.data.receipt, "original operation status")
	check(chat.readLocalHistory(C).messages.size() == 1 and chat.readLocalHistory(C).messages[0].text == "hello é😀\n\t<text>", "confirmed original plus push plus explicit replay archives exactly once")
	check((await chat.reportMessage(U, C, message_id, "original reason é")).success, "report route once")
	check((await chat.reportMessage(U, C, message_id, "original reason é")).data.replayed, "original report replay")
	check((await chat.reportMessage(U, C, message_id, "changed reason")).errorCode == "OPERATION_CONFLICT", "changed report cannot replace original")
	await control("bulk")
	await wait_for(func() -> bool: return chat.getCached(C).get("messages", []).size() == 20, "twenty-ID incremental snapshot")
	var first: Dictionary = chat.getCached(C)
	check(first.messages[0].text == "hello é😀\n\t<text>", "immutable known text retained exactly")
	await control("shift")
	await wait_for(func() -> bool: return chat.getCached(C).get("visibleMessageIds", []).size() == 20 and message_id not in chat.getCached(C).visibleMessageIds, "full visible order removes deleted first message")
	check(chat.getCached(C).messages[-1].text == "plain 20 é😀", "only one unknown payload appended")
	check(chat.readLocalHistory(C).messages.size() == 21 and chat.readLocalHistory(C).messages[0].id == message_id, "server window eviction retains earlier device copy")
	var denied: String = "00000000-0000-4000-8000-000000003015"
	check(chat.watchChannel(U, denied), "second channel subscription requested")
	await wait_for(func() -> bool: return not realtime._topics.has("chat:" + denied), "second channel denied on actual socket")
	check(not chat.getCached(C).is_empty() and chat.getCached(denied).is_empty(), "scoped subscription denial preserves unrelated authorized feed")
	chat.stopWatching(denied)
	var before: int = int((await control("status")).syncs)
	await control("burst"); await create_timer(.5).timeout
	var after: int = int((await control("status")).syncs)
	check(after > before and after <= before + 2, "twenty metadata events coalesce into inflight plus one dirty sync")
	before = after; await create_timer(.3).timeout
	check(int((await control("status")).syncs) == before, "idle produces zero periodic sync")
	await control("bad")
	await wait_for(func() -> bool: return "INVALID_RESPONSE" in codes, "partial snapshot fails closed")
	check(chat.getCached(C).is_empty(), "incomplete new snapshot hides prior text")
	await control("restore")
	await wait_for(func() -> bool: return chat.getCached(C).get("messages", []).size() == 20, "fresh resync reloads full authorized text")
	before = int((await control("status")).syncs)
	await control("revoke")
	await wait_for(func() -> bool: return not realtime._topics.has("chat:" + C), "real WS permission revocation")
	check(chat.getCached(C).is_empty(), "permissions immediately hide cache")
	check(not chat.readLocalHistory(C).messages.is_empty(), "membership revocation retains same-identity device archive")
	check((await chat.syncChannel(U, C)).errorCode == "SUBSCRIPTION_REQUIRED", "denied websocket never becomes HTTP fallback")
	await create_timer(.15).timeout
	check(int((await control("status")).syncs) == before, "permission denial triggers no unauthorized snapshot")
	await control("allow"); check(chat.watchChannel(U, C), "explicit subscription recovery")
	await wait_for(func() -> bool: return chat.getCached(C).get("messages", []).size() == 20, "new authorized subscription reacquires snapshot")
	var connections: int = int((await control("status")).connections)
	await control("disconnect")
	await wait_for(func() -> bool: return chat.getCached(C).is_empty(), "disconnect hides text before fresh subscription")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "real WebSocket reconnect resync")
	check(int((await control("status")).connections) > connections, "new physical socket authenticated")
	before = int((await control("status")).mutations)
	for text: String in ["fault503", "fault429", "faultfeature"]:
		var failure: Dictionary = await chat.sendMessage(U, C, _id(text), T, text)
		check(not failure.success, "one-attempt mutation fault surfaced " + text)
	check(int((await control("status")).mutations) == before + 3, "network/429/feature429 mutations never automatically retry")
	check((await chat.sendMessage(U, C, _id("muted"), T, "muted")).errorCode == "CHAT_MUTED" and not chat.getCached(C).is_empty(), "send-only mute preserves readable feed")
	check((await chat.reportMessage(U, C, chat.getCached(C).messages[-1].id, "missing-message")).errorCode == "MESSAGE_NOT_FOUND" and not chat.getCached(C).is_empty(), "deleted reported message does not revoke channel")
	await control("fail-open")
	before = int((await control("status")).mutations)
	check(not (await chat.openChannel(U, "project")).success, "uncertain open surfaced")
	check(int((await control("status")).mutations) == before + 1, "open allocation has one actual HTTP attempt")
	await control("fail-report")
	before = int((await control("status")).mutations)
	check(not (await chat.reportMessage(U, C, chat.getCached(C).messages[-1].id, "fault report")).success, "uncertain report surfaced")
	check(int((await control("status")).mutations) == before + 1, "report has one actual HTTP attempt")
	await control("fail-auth")
	check((await chat.getLimits(U)).errorCode == "SESSION_REQUIRED" and chat.getCached(C).is_empty() and chat._watches.is_empty(), "session-wide 401 from limits clears every watched feed")
	check(chat.watchChannel(U, C), "explicit feed recovery before raw auth denial")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "managed feed restored before raw auth denial")
	await control("fail-auth")
	check((await chat.requestChannelSnapshot(U, C)).errorCode == "SESSION_REQUIRED" and chat.getCached(C).is_empty() and chat._watches.is_empty(), "current raw401 also revokes every private feed without adopting its reply")
	var example: Node = Example.new(); root.add_child(example)
	check((await example.choose_channel("project")).success, "actual original example selects/subscribes")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "actual example receives push feed")
	var lost: Dictionary = await example.send_text("lost-ack")
	check(not lost.success, "actual sample retains committed send with lost ACK")
	var original: Dictionary = Pending.load_pending(http.apiKey, U).pending
	check(not original.is_empty() and original.text == "lost-ack", "original operation and exact text durably saved")
	check((await example.send_text("replacement")).errorCode == "PENDING_ACTION", "unknown original blocks replacement")
	var restarted: Node = Example.new(); root.add_child(restarted)
	var recovered: Dictionary = await restarted.inspect_pending()
	check(recovered.success and recovered.data.receipt.operationId == original.operationId and Pending.load_pending(http.apiKey, U).pending.is_empty(), "fresh sample status recovery atomically ACKs original without resend")
	var another: Node = Example.new(); root.add_child(another)
	var cached_feeds: Array = []
	another.feed_changed.connect(func(data: Dictionary): cached_feeds.append(data))
	check((await another.choose_channel("project")).success and cached_feeds.size() == 1 and not cached_feeds[0].messages.is_empty(), "new scene immediately receives existing authorized cache")
	var owners: int = chat._watches[C].owners.size()
	another.queue_free(); await process_frame
	check(chat._watches[C].owners.size() == owners - 1 and not chat.getCached(C).is_empty(), "scene teardown releases only its own shared watch")
	example.queue_free(); await process_frame
	chat.stopWatching(C)
	check(not chat._watches.has(C), "all scene/manual watch owners released without leaked channel")
	check(chat.watchChannel(U, C), "fresh explicit watch after complete teardown")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "teardown does not consume permanent watch capacity")
	await wait_for(func() -> bool: return not chat._watches[C].syncing, "push settled before obsolete-response race")
	await control("late-failed-sync")
	read_sync(); await create_timer(.04).timeout
	chat.stopWatching(C); check(chat.watchChannel(U, C), "replace watch while old sync is in flight")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "new watch populated before obsolete failure")
	await wait_for(func() -> bool: return not late_sync.is_empty(), "obsolete failure received")
	check(late_sync.errorCode == "STALE_RESPONSE" and not chat.getCached(C).is_empty() and "CHAT_BANNED" not in codes, "obsolete failure cannot hide or unsubscribe newer authorized watch")
	for kind: String in ["send", "report"]:
		late_write.clear(); read_write(kind); await create_timer(.04).timeout
		chat.stopWatching(C); check(chat.watchChannel(U, C), "replace watch before late " + kind + " denial")
		await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "replacement watch readable while old " + kind + " awaits")
		await wait_for(func() -> bool: return not late_write.is_empty(), "late " + kind + " refusal received")
		check(late_write.errorCode == "STALE_RESPONSE" and not chat.getCached(C).is_empty(), "late " + kind + " denial cannot revoke replacement watch")
	var delayed_id: String = "00000000-0000-4000-8000-000000009999"
	check((await chat.sendMessage(U, C, delayed_id, T, "late-context")).success, "prepare real delayed status")
	read_late(delayed_id)
	await create_timer(.03).timeout
	var host: String = http.activeHost; http.activeHost = "http://127.0.0.1:1"; http.activeHost = host
	await wait_for(func() -> bool: return not late.is_empty(), "delayed real HTTP completes after host ABA")
	check(not late.success and late.errorCode == "STALE_RESPONSE" and chat.getCached(C).is_empty(), "host generation rejects late callback and payload")
	late.clear(); read_late(delayed_id)
	await create_timer(.03).timeout
	http.sessionToken = "other-session"; auth._currentUser.accessToken = "other-session"
	http.sessionToken = "chat-session"; auth._currentUser.accessToken = "chat-session"
	await wait_for(func() -> bool: return not late.is_empty(), "delayed HTTP completes after session ABA")
	check(not late.success and late.errorCode == "STALE_RESPONSE", "session ABA rejects late response without auth signal")
	late.clear(); read_late(delayed_id)
	await create_timer(.03).timeout
	http.apiKey = "other-project"; http.apiKey = "chat-key"
	await wait_for(func() -> bool: return not late.is_empty(), "delayed HTTP completes after project ABA")
	check(not late.success and late.errorCode == "STALE_RESPONSE", "project ABA rejects late response")
	http.apiKey = "other-project"
	check(chat.readLocalHistory(C).messages.is_empty(), "runtime project switch cannot read another key's archive")
	http.apiKey = "chat-key"
	var old_user: String = auth._currentUser.userId
	auth._currentUser.userId = "00000000-0000-4000-8000-000000002014"
	check(chat.readLocalHistory(C).messages.is_empty(), "runtime player switch cannot read prior player's archive")
	auth._currentUser.userId = old_user
	check(not chat.readLocalHistory(C).messages.is_empty(), "same identity resumes its persistent device archive")
	var old_token: String = http.sessionToken
	http.sessionToken = ""
	check(chat.readLocalHistory(C).errorCode == "SESSION_REQUIRED", "logged-out runtime cannot read device archive")
	http.sessionToken = old_token
	check((await chat.openChannel(U, "project")).success and chat.watchChannel(U, C), "fresh current context can explicitly subscribe")
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "fresh authorized snapshot for local expiry")
	var demo: VBoxContainer = load("res://addons/horizon_sdk/examples/features/chat_demo.tscn").instantiate()
	root.add_child(demo)
	await demo._open()
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "actual demo open button path subscribes")
	check(not demo._feed.bbcode_enabled and demo._kind.item_count == 3, "actual minimal UI has three contexts and plain-text rendering")
	check(not demo._feed.text.is_empty(), "new UI actually renders already cached feed before another event")
	invalidate_feed = true
	await control("burst")
	await wait_for(func() -> bool: return chat.getCached(C).is_empty(), "earlier signal listener revokes feed synchronously")
	check(demo._feed.text.is_empty(), "later recipe/demo listeners cannot resurrect captured private text")
	invalidate_feed = false
	await demo._open()
	await wait_for(func() -> bool: return not chat.getCached(C).is_empty(), "explicit recovery after signal invalidation")
	await control("short-message")
	await wait_for(func() -> bool: return chat.getCached(C).get("messages", []).any(func(row: Dictionary) -> bool: return row.text == "short-lived local expiry"), "short-lived message rendered from actual push")
	await wait_for(func() -> bool: return not chat._watches[C].syncing, "expiry snapshot settled")
	await control("late-clock-sync")
	late_sync.clear(); read_sync(); await create_timer(.04).timeout
	var before_expiry_updates: int = updates
	var ticks: int = Time.get_ticks_msec()
	chat._nowMillis = func() -> int: return ticks + 61000
	check(not chat.getCached(C).messages.any(func(row: Dictionary) -> bool: return row.text == "short-lived local expiry") and updates > before_expiry_updates, "individual local expiry emits replacement feed immediately")
	check(not "short-lived local expiry" in demo._feed.text, "local expiry also clears detached actual UI text")
	check(chat.readLocalHistory(C).messages.any(func(row: Dictionary) -> bool: return row.text == "short-lived local expiry"), "server expiry never expires local device copies")
	await wait_for(func() -> bool: return not late_sync.is_empty(), "delayed earlier server snapshot received")
	check(late_sync.success and not late_sync.data.messages.any(func(row: Dictionary) -> bool: return row.text == "short-lived local expiry"), "delayed response cannot resurrect captured expired text")
	check(HorizonChatModels.millis(chat.getServerTime()) >= HorizonChatModels.millis(T) + 61000, "effective expiry clock never rewinds to delayed server timestamp")
	before = int((await control("status")).syncs)
	await create_timer(.1).timeout
	check(int((await control("status")).syncs) == before, "local expiry launches no HTTP timer")
	chat.clearCache(); realtime.close()
	await control("unsupported")
	check((await chat.getLimits(U)).errorCode == "NOT_SUPPORTED", "PHP capability refusal remains explicit without polling fallback")
	var stats: Dictionary = await control("status")
	check(stats.failure == null, "fixture saw exact auth/paths/bodies and no hidden polling")
	await control("finish")
	check(chat.clearAllLocalHistory().success and chat.readLocalHistory(C).messages.is_empty(), "explicit identity archive clear")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Pending.path(http.apiKey, U)))
	demo.queue_free(); restarted.queue_free(); h.queue_free(); chat.queue_free(); realtime.queue_free(); http.queue_free()
	print("Chat actual HTTP+WS/sample: %d checks, %d updates, %d failures" % [checks, updates, failures])
	quit(1 if failures else 0)
func read_late(operation: String) -> void: late = await chat.getOperation(U, operation)
func read_sync() -> void: late_sync = await chat.syncChannel(U, C)
func read_write(kind: String) -> void:
	late_write = await chat.sendMessage(U, C, _id("late-denial"), T, "late-denial") if kind == "send" else await chat.reportMessage(U, C, "00000000-0000-4000-8000-000000008014", "late-missing")
func _id(value: String) -> String: return "00000000-0000-4000-8000-" + value.sha256_text().substr(0, 12)
