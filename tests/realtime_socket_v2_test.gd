# Socket v2 (TASK-1139) against a fake socket: sends, result mapping, timeouts, tickets, reconnects, snapshots.
extends SceneTree
const U := "00000000-0000-4000-8000-000000001139"
const C := "00000000-0000-4000-8000-000000003139"
const E := "00000000-0000-4000-8000-000000004139"
const I := "00000000-0000-4000-8000-000000005139"
const T := "2026-10-16T12:00:00.000Z"
const X := "2026-10-23T12:00:00.000Z"
const TOKEN := "socket-v2-session"
class FakeSocket extends RefCounted:
	var inbound_buffer_size: int = 0
	var outbound_buffer_size: int = 0
	var max_queued_packets: int = 0
	var state: int = WebSocketPeer.STATE_CONNECTING
	var closeCode: int = -1
	var sent: Array = []
	var inbox: Array = []
	func connect_to_url(_url: String) -> int:
		state = WebSocketPeer.STATE_OPEN
		return OK
	func poll() -> void: pass
	func get_ready_state() -> int: return state
	func get_available_packet_count() -> int: return inbox.size()
	func get_packet() -> PackedByteArray: return str(inbox.pop_front()).to_utf8_buffer()
	func send_text(text: String) -> int:
		sent.append(HorizonItemModels.parse(text))
		return OK
	func get_current_outbound_buffered_amount() -> int: return 0
	func get_close_code() -> int: return closeCode
	func close(_code: int = 1000, _reason: String = "") -> void: state = WebSocketPeer.STATE_CLOSED
	func push(frame: Dictionary) -> void: inbox.append(HorizonSharedObjectModels.encode(frame))
	func last(type: String) -> Dictionary:
		for i: int in range(sent.size() - 1, -1, -1):
			if sent[i].get("type") == type: return sent[i]
		return {}
class FakeHttp extends HorizonHttpClient:
	var sessions: int = 0
	var sends: Array = []
	var syncs: int = 0
	var actions: Array = []
	var reply: HorizonNetworkResponse
	func postAsync(_endpoint: String, _data: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		sessions += 1
		return HorizonNetworkResponse.success({"pollAfterSeconds": 120})
	func postJsonOnceAsync(_endpoint: String, _data: Dictionary = {}, _session: bool = false, json: String = "") -> HorizonNetworkResponse:
		sends.append(json)
		return reply
	func postJsonAsync(_endpoint: String, _data: Dictionary = {}, _session: bool = false, _json: String = "") -> HorizonNetworkResponse:
		syncs += 1
		return HorizonNetworkResponse.failure("HTTP 503", 503, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
	func postJsonHeadersOnceAsync(_endpoint: String, _data: Dictionary, _session: bool, json: String, _headers: PackedStringArray) -> HorizonNetworkResponse:
		actions.append(json)
		return reply
	func getAsync(_endpoint: String, _session: bool = false) -> HorizonNetworkResponse:
		syncs += 1
		return HorizonNetworkResponse.failure("HTTP 503", 503, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
var checks: int = 0
var failures: int = 0
var sockets: Array = []
var box: Dictionary = {}
func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Socket v2 check failed: " + label)
func message(index: int) -> Dictionary: return {"id": "00000000-0000-4000-8000-%012d" % index, "channelId": C, "authorId": U, "text": "socket é/😀", "createdAt": T, "expiresAt": X}
func snapshot(from: int, to: int, known: Array = []) -> Dictionary:
	var rows: Array = []
	var ids: Array = []
	for i: int in range(from, to):
		ids.append(message(i).id)
		if message(i).id not in known: rows.append(message(i))
	return {"channel": {"id": C, "epoch": E, "kind": "project", "peerIds": [], "groupId": null, "revision": to, "expiresAt": X}, "visibleMessageIds": ids, "messages": rows, "moderation": {"muteUntil": null, "banUntil": null}, "serverTime": T}
func receipt(operation: String) -> Dictionary: return {"receipt": {"operationId": operation, "issuedAt": T, "channelId": C, "messageId": message(99).id, "createdAt": T, "expiresAt": X}, "replayed": false, "serverTime": T}
func matchView(revision: int) -> Dictionary: return {"match": {"id": I, "name": "socket", "revision": revision, "creatorId": U, "capacity": 2, "visibility": "private", "strength": 0, "status": "lobby", "participantIds": [U], "invitedIds": [], "forfeitedIds": [], "currentPlayerId": null, "turnDeadline": null, "createdAt": T, "startedAt": null, "finishedAt": null, "purgeAt": null, "finalStateRevision": null, "hasDisagreement": false, "ranked": false, "timeoutDue": false, "turnOrder": [], "turnSeconds": 60, "timeoutPolicy": "skip", "dataBase64": "AP8AgA==", "reports": [], "reportDeadline": null, "absoluteDeadline": null, "rankedLeaderboardKey": null, "ownRankedRunId": null, "notificationPending": false}, "pollAfterSeconds": 120, "serverTime": T}
func uuid(n: int) -> String: return "00000000-0000-4000-8000-%012d" % (700000 + n)
func httpReply(body: Dictionary) -> HorizonNetworkResponse:
	var response := HorizonNetworkResponse.success(body)
	response.rawBody = HorizonSharedObjectModels.encode(body)
	return response
func pump(frames: int = 3) -> void:
	for i: int in frames: await process_frame
func socket() -> FakeSocket: return sockets[-1]
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Socket v2 test timed out"); quit(1))
	call_deferred("_run")
func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := FakeHttp.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "socket-v2-key"
	http.activeHost = "http://127.0.0.1:1"
	http.sessionToken = TOKEN
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = U
	auth._currentUser.accessToken = TOKEN
	var realtime := HorizonRealtime.new()
	root.add_child(realtime)
	realtime.initialize(http, auth)
	realtime._newSocket = func() -> Object:
		var fake := FakeSocket.new()
		sockets.append(fake)
		return fake
	var chat := HorizonChat.new()
	root.add_child(chat)
	chat.initialize(http, auth, realtime)
	var matches := HorizonMatches.new()
	matches.initialize(http, auth, null, realtime)
	var send := func(operation: String) -> void:
		box.erase("chat")
		box.chat = await chat.sendMessage(U, C, operation, T, "hello")

	# HTTP fallback while no socket is ready.
	http.reply = httpReply(receipt(uuid(1)))
	send.call(uuid(1))
	await pump()
	ok(box.get("chat", {}).get("success") == true and http.sends.size() == 1 and sockets.is_empty(), "chat send uses HTTP without a ready socket")

	# Connect with the session token, ready with ticket and sendOverSocket, snapshot applied without HTTP sync.
	var changed: Array = []
	chat.channel_changed.connect(func(_id: String, view: Dictionary): changed.append(view))
	ok(chat.watchChannel(U, C), "watch channel")
	await pump()
	ok(http.sessions == 1 and sockets.size() == 1, "first connect asks the session endpoint")
	var auth_frame: Dictionary = socket().last("authenticate")
	ok(auth_frame.get("sessionToken") == TOKEN and not auth_frame.has("ticket"), "first authenticate uses the session token")
	socket().push({"type": "ready", "version": 1, "heartbeatSeconds": 30, "pollAfterSeconds": 120, "maxSubscriptions": 32, "ticket": "ticket-one", "sendOverSocket": true})
	socket().push({"type": "resync_required", "version": 1, "reason": "CONNECTED", "eventId": "a".repeat(64)})
	await pump()
	var subscribe: Dictionary = socket().last("subscribe")
	ok(subscribe.get("topic") == "chat:" + C and subscribe.get("sync") == {"epoch": null, "knownMessageIds": []}, "chat subscribe carries sync")
	socket().push({"type": "subscribed", "version": 1, "topic": "chat:" + C, "requestId": subscribe.get("requestId", 0), "snapshot": snapshot(0, 3)})
	await pump()
	ok(chat.getCached(C).get("messages", []).size() == 3 and http.syncs == 0 and changed.size() == 1, "snapshot applied without HTTP reload")

	# Chat send over the socket, 200 maps to the HTTP success value.
	send.call(uuid(2))
	await pump()
	var frame: Dictionary = socket().last("chat.send")
	ok(frame.get("channelId") == C and frame.get("operationId") == uuid(2) and frame.get("issuedAt") == T and frame.get("text") == "hello" and not frame.has("userId") and frame.get("requestId", 0) > 0, "chat.send frame")
	socket().push({"type": "result", "version": 1, "requestId": frame.get("requestId", 0), "status": 200, "result": receipt(uuid(2))})
	await pump()
	ok(box.get("chat", {}).get("success") == true and box.chat.data.receipt.operationId == uuid(2) and http.sends.size() == 1, "socket result 200 equals HTTP success")

	# Error mapping equals the HTTP path for the same status and code.
	send.call(uuid(3))
	await pump()
	frame = socket().last("chat.send")
	socket().push({"type": "result", "version": 1, "requestId": frame.get("requestId", 0), "status": 429, "code": "CHAT_RATE_LIMITED", "retryAfter": 3})
	await pump()
	var socket_error: Dictionary = box.get("chat", {})
	realtime.sendOverSocket = false
	http.reply = HorizonNetworkResponse.failure("HTTP 429", 429, HorizonErrorCodes.ErrorCode.API_RATE_LIMITED)
	http.reply.serverCode = "CHAT_RATE_LIMITED"
	send.call(uuid(3))
	await pump()
	ok(socket_error.get("success") == false and socket_error.get("errorCode") == "CHAT_RATE_LIMITED" and socket_error.get("errorCode") == box.get("chat", {}).get("errorCode") and socket_error.get("error") == box.get("chat", {}).get("error"), "socket 429 maps like HTTP")
	ok(http.sends.size() == 2, "sendOverSocket false sends over HTTP")
	realtime.sendOverSocket = true

	# Timeout: unknown outcome, retried over HTTP with the same operation id and issuedAt.
	realtime.sendTimeoutSeconds = 0.1
	http.reply = httpReply(receipt(uuid(4)))
	send.call(uuid(4))
	await pump()
	ok(socket().last("chat.send").get("operationId") == uuid(4), "timed out frame was sent")
	await create_timer(0.3).timeout
	await pump()
	var retry: Dictionary = HorizonItemModels.parse(http.sends[-1])
	ok(http.sends.size() == 3 and retry.get("operationId") == uuid(4) and retry.get("issuedAt") == T and box.get("chat", {}).get("success") == true, "timeout retries over HTTP with the same operation")
	realtime.sendTimeoutSeconds = 10.0

	# Match snapshot without HTTP reload, then a match action over the socket.
	var loaded: Array = []
	matches.matches_loaded.connect(func(kind: String, _data: Dictionary): loaded.append(kind))
	ok(realtime.subscribe("matches:" + I), "subscribe match topic")
	await pump()
	subscribe = socket().last("subscribe")
	ok(subscribe.get("topic") == "matches:" + I and not subscribe.has("sync"), "match subscribe without sync")
	socket().push({"type": "subscribed", "version": 1, "topic": "matches:" + I, "requestId": subscribe.get("requestId", 0), "snapshot": matchView(1)})
	await pump()
	ok(loaded == ["get"] and http.syncs == 0, "match snapshot applied as get response")
	var act := func() -> void: box.match = await matches.joinMatch(U, I, 1)
	act.call()
	await pump()
	frame = socket().last("match.action")
	ok(frame.get("matchId") == I and frame.get("action") == "join" and frame.get("revision") == 1 and frame.get("input") == {}, "match.action frame")
	socket().push({"type": "result", "version": 1, "requestId": frame.get("requestId", 0), "status": 200, "result": matchView(2)})
	await pump()
	ok(box.get("match", {}).get("success") == true and box.match.data.match.revision == 2 and http.actions.is_empty(), "match result 200 equals HTTP success")
	act.call()
	await pump()
	frame = socket().last("match.action")
	socket().push({"type": "result", "version": 1, "requestId": frame.get("requestId", 0), "status": 409, "code": "MATCH_REVISION_CONFLICT"})
	await pump()
	ok(box.match.get("success") == false and box.match.get("errorCode") == "MATCH_REVISION_CONFLICT", "match error code mapped")

	# Ticket refresh, 1012 short reconnect with the ticket, attempt counter unchanged.
	socket().push({"type": "ticket", "version": 1, "ticket": "ticket-two"})
	await pump()
	var attempt: int = realtime._attempt
	socket().closeCode = 1012
	socket().state = WebSocketPeer.STATE_CLOSED
	await pump(1)
	var wait: float = realtime._retryAt - Time.get_ticks_msec() / 1000.0
	ok(realtime.lastErrorCode == "SERVICE_RESTART" and wait <= 5.0 and realtime._attempt == attempt, "1012 reconnects within 5 s without backoff growth")
	realtime._retryAt = 0.0
	await pump()
	ok(sockets.size() == 2 and http.sessions == 1, "ticket reconnect needs no session call")
	auth_frame = socket().last("authenticate")
	ok(auth_frame.get("ticket") == "ticket-two" and not auth_frame.has("sessionToken"), "reconnect authenticates with the newest ticket")

	# SESSION_REQUIRED after a ticket: drop it and reconnect at once with the session token.
	socket().push({"type": "error", "version": 1, "code": "SESSION_REQUIRED"})
	await pump()
	ok(realtime._ticket.is_empty() and sockets.size() == 3 and http.sessions == 2, "SESSION_REQUIRED reconnects at once")
	auth_frame = socket().last("authenticate")
	ok(auth_frame.get("sessionToken") == TOKEN and not auth_frame.has("ticket"), "fallback authenticate uses the session token")

	# Resubscribe sends epoch and known ids, the catch-up snapshot carries only the missed message.
	socket().push({"type": "ready", "version": 1, "heartbeatSeconds": 30, "pollAfterSeconds": 120, "maxSubscriptions": 32, "ticket": "ticket-three", "sendOverSocket": true})
	await pump()
	subscribe = socket().last("subscribe")
	var known: Array = snapshot(0, 3).visibleMessageIds
	ok(subscribe.get("topic") == "chat:" + C and subscribe.get("sync") == {"epoch": E, "knownMessageIds": known}, "resubscribe sends epoch and known ids")
	socket().push({"type": "subscribed", "version": 1, "topic": "chat:" + C, "requestId": subscribe.get("requestId", 0), "snapshot": snapshot(1, 4, known)})
	await pump()
	var view: Dictionary = chat.getCached(C)
	ok(view.get("visibleMessageIds", []) == snapshot(1, 4).visibleMessageIds and view.get("messages", []).size() == 3 and http.syncs == 0, "catch-up snapshot merged with the known messages")

	# CONNECTION_LIMIT_REACHED: no socket for pollAfterSeconds, sends go over HTTP.
	socket().push({"type": "error", "version": 1, "code": "CONNECTION_LIMIT_REACHED"})
	await pump(1)
	wait = realtime._retryAt - Time.get_ticks_msec() / 1000.0
	ok(not realtime.isReady and wait > 100.0 and sockets.size() == 3, "connection limit waits pollAfterSeconds")
	http.reply = httpReply(receipt(uuid(5)))
	send.call(uuid(5))
	await pump()
	ok(http.sends.size() == 4 and box.get("chat", {}).get("success") == true, "limit falls back to HTTP")
	ok(await realtime.sendFrame({"type": "chat.send"}) == null, "no frame without a ready socket")

	var source: String = FileAccess.get_file_as_string("res://addons/horizon_sdk/core/realtime.gd")
	ok(not source.contains("print(") and not source.contains("push_error(") and not source.contains("push_warning(") and not source.contains("_logger"), "realtime never logs keys, tokens or tickets")
	realtime.close()
	if failures > 0:
		push_error("Socket v2 tests failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Realtime socket v2 tests passed (%d checks)" % checks)
	quit(0)
