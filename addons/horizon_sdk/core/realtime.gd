## Optional change notifications. Socket v2 (TASK-1139) also sends chat messages and match lobby/turn
## actions over the socket while it is ready and the gateway allows it. Everything else stays HTTP.
class_name HorizonRealtime
extends Node

signal event_received(event: Dictionary)
signal resync_required(topic: String)
signal polling_required(topic: String, poll_after_seconds: int)
signal connection_error(code: String)
signal subscription_failed(topic: String, code: String)
## The `subscribed` frame carried the current view (exact JSON). The feature applies it instead of an HTTP reload.
signal snapshot_received(topic: String, snapshot_json: String)
signal _send_settled(request_id: int)
const TICKET_MAX_AGE_SECONDS := 540.0
const MAX_FRAME_BYTES := 262144

## Optional full ws/wss URL for a separately exposed Dev gateway.
var gatewayUrl: String = ""
var pollAfterSeconds: int = 120
var isReady: bool = false
var lastErrorCode: String = ""
## Set by the gateway's `ready` frame. False sends everything over HTTP.
var sendOverSocket: bool = false
var sendTimeoutSeconds: float = 10.0
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _socket: Object
var _newSocket: Callable = func() -> Object: return WebSocketPeer.new()
## Resume ticket, memory only. Never logged or written to disk.
var _ticket: String = ""
var _ticketAt: float = 0.0
var _usedTicket: bool = false
var _sends: Dictionary = {}
var _syncProviders: Dictionary = {}
var _topics: Dictionary = {}
var _sent: Dictionary = {}
var _pending: String = ""
var _requestId: int = 0
var _pendingRequestId: int = 0
var _pendingCanceled: bool = false
var _clientId: String = ""
var _token: String = ""
var _userId: String = ""
var _contextGeneration: int = -1
var _generation: int = 0
var _attempt: int = 0
var _retryAt: float = 0.0
var _pollAt: float = 0.0
var _lastFrameAt: float = 0.0
var _pingAt: float = 0.0
var _connectDeadline: float = 0.0
var _connecting: bool = false
var _authenticated: bool = false
var _unsupported: bool = false

func initialize(http: HorizonHttpClient, auth: HorizonAuth) -> void:
	_http = http
	_auth = auth
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var value: String = bytes.hex_encode()
	_clientId = "%s-%s-%s-%s-%s" % [value.substr(0, 8), value.substr(8, 4), value.substr(12, 4), value.substr(16, 4), value.substr(20)]

func subscribe(topic: String) -> bool:
	_syncIdentity()
	if not _validTopic(topic) or (_topics.size() >= 32 and not _topics.has(topic)):
		return false
	_topics[topic] = true
	return true

## An allocated subscription is not authorized until the current socket acknowledges it.
func isSubscribed(topic: String) -> bool:
	_syncIdentity()
	return isReady and _topics.has(topic) and _sent.has(topic)

func setPollAfterSeconds(seconds: int) -> void:
	pollAfterSeconds = maxi(1, seconds)
	_pollAt = Time.get_ticks_msec() / 1000.0 + pollAfterSeconds

func unsubscribe(topic: String) -> void:
	if not _topics.has(topic):
		return
	_topics.erase(topic)
	_sent.erase(topic)
	if _pending == topic:
		_pendingCanceled = true
	if isReady:
		_requestId += 1
		_send({"type": "unsubscribe", "topic": topic, "requestId": _requestId})
	if _topics.is_empty():
		_disconnect()

func close() -> void:
	_topics.clear()
	_ticket = ""
	_disconnect()

## Catch-up input sent with every (re)subscription of topics with this prefix, for example chat epoch and known ids.
func setSyncProvider(prefix: String, provider: Callable) -> void:
	_syncProviders[prefix] = provider

## Sends a `chat.send` or `match.action` frame and waits for its `result`, mapped like the HTTP response.
## Null means the frame was not sent (socket not ready) or the outcome is unknown (closed, timeout):
## the caller sends over HTTP with the same operation, which the server treats idempotently.
func sendFrame(frame: Dictionary) -> HorizonNetworkResponse:
	_syncIdentity()
	if not isReady or not sendOverSocket or _socket == null:
		return null
	_requestId += 1
	var id: int = _requestId
	var entry: Dictionary = {"deadline": Time.get_ticks_msec() / 1000.0 + sendTimeoutSeconds, "response": null}
	_sends[id] = entry
	var payload: Dictionary = frame.duplicate()
	payload.requestId = id
	_send(payload, HorizonSharedObjectModels.encode(payload))
	while _sends.has(id):
		await _send_settled
	return entry.response

static func reconnectDelay(attempt: int, random_fraction: float) -> float:
	return clampf(random_fraction, 0.0, 1.0) * minf(30.0, pow(2.0, mini(attempt, 5)))

static func canPoll(topic: String) -> bool:
	return not topic.begins_with("chat:")

static func _validTopic(topic: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^(inbox|matches|chat|friends|groups):[A-Za-z0-9._-]{1,96}$")
	return pattern.search(topic) != null

func _process(_delta: float) -> void:
	if _http == null or _auth == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for id: int in _sends.keys():
		if _sends.has(id) and now >= _sends[id].deadline:
			_settle(id, null)
	_syncIdentity()
	if _topics.is_empty() or _token.is_empty():
		return
	if isReady and now - _lastFrameAt > 90.0:
		_failed("HEARTBEAT_TIMEOUT")
		return
	if _socket != null:
		_socket.poll()
		var state: int = _socket.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not _authenticated:
				_authenticated = true
				var authenticate: Dictionary = {"type": "authenticate", "version": 1, "apiKey": _http.apiKey, "clientId": _clientId}
				_usedTicket = _ticketUsable(now)
				if _usedTicket:
					authenticate.ticket = _ticket
				else:
					authenticate.sessionToken = _token
				_send(authenticate)
				if _socket == null:
					return
			while _socket.get_available_packet_count() > 0:
				if _syncIdentity():
					return
				var packet: PackedByteArray = _socket.get_packet()
				if packet.size() > MAX_FRAME_BYTES:
					_failed("INVALID_FRAME")
					return
				var text: String = packet.get_string_from_utf8()
				var frame: Variant = JSON.parse_string(text)
				if frame is Dictionary:
					_handle(frame, text)
					if _socket == null:
						return
			if isReady:
				if _pending.is_empty():
					for topic: String in _topics:
						if not _sent.has(topic):
							_pending = topic
							_pendingCanceled = false
							_requestId += 1
							_pendingRequestId = _requestId
							var subscribe: Dictionary = {"type": "subscribe", "topic": topic, "requestId": _pendingRequestId}
							var provider: Callable = _syncProviders.get(topic.get_slice(":", 0) + ":", Callable())
							if provider.is_valid():
								subscribe.sync = provider.call(topic)
							_send(subscribe, HorizonSharedObjectModels.encode(subscribe))
							break
				if now >= _pingAt and _pending.is_empty():
					_send({"type": "ping"})
					_pingAt = now + 30.0
		elif state == WebSocketPeer.STATE_CLOSED:
			# 1012: gateway update. Reconnect soon with the ticket, the backoff does not grow.
			if _socket.get_close_code() == 1012:
				_failed("SERVICE_RESTART", randf() * 5.0)
			else:
				_failed("CONNECTION_CLOSED")
			return
		if not isReady and now > _connectDeadline:
			_failed("CONNECTION_TIMEOUT")
	if not isReady:
		if now >= _pollAt:
			_pollAt = now + pollAfterSeconds
			for topic: String in _topics.keys():
				if _syncIdentity():
					return
				if _topics.has(topic) and canPoll(topic):
					polling_required.emit(topic, pollAfterSeconds)
		if _socket == null and not _connecting and not _unsupported and now >= _retryAt:
			_beginConnect()

func _beginConnect() -> void:
	_connecting = true
	# A held ticket reconnects without a backend call.
	if not _ticketUsable(Time.get_ticks_msec() / 1000.0):
		var generation: int = _generation
		var response: HorizonNetworkResponse = await _http.postAsync("/api/v1/app/realtime/session", {}, true)
		if generation != _generation or not is_inside_tree():
			return
		_connecting = false
		if not response.isSuccess:
			_unsupported = response.serverCode == "NOT_SUPPORTED" or response.statusCode == 501
			_failed("NOT_SUPPORTED" if _unsupported else response.serverCode)
			return
		pollAfterSeconds = maxi(1, int(response.asDict().get("pollAfterSeconds", 120)))
	_connecting = false
	_socket = _newSocket.call()
	_socket.inbound_buffer_size = MAX_FRAME_BYTES
	_socket.outbound_buffer_size = 65536
	_socket.max_queued_packets = 64
	var url: String = _http.activeHost.trim_suffix("/").replace("https://", "wss://").replace("http://", "ws://") + "/api/v1/app/realtime/socket"
	if not gatewayUrl.is_empty():
		url = gatewayUrl
	if (not url.begins_with("ws://") and not url.begins_with("wss://")) or "?" in url or "@" in url:
		_failed("INVALID_GATEWAY_URL")
		return
	var result: int = _socket.connect_to_url(url)
	_connectDeadline = Time.get_ticks_msec() / 1000.0 + 10.0
	if result != OK:
		_failed("CONNECTION_FAILED")

func _handle(frame: Dictionary, text: String = "") -> void:
	_lastFrameAt = Time.get_ticks_msec() / 1000.0
	if int(frame.get("version", 0)) != 1:
		_failed("INVALID_FRAME")
		return
	match str(frame.get("type", "")):
		"ready":
			isReady = true
			_attempt = 0
			sendOverSocket = frame.get("sendOverSocket") == true
			_storeTicket(frame.get("ticket"))
			pollAfterSeconds = maxi(1, int(frame.get("pollAfterSeconds", 120)))
			_pingAt = Time.get_ticks_msec() / 1000.0 + 30.0
		"unsubscribed":
			if int(frame.get("requestId", 0)) == _pendingRequestId and str(frame.get("topic", "")) == _pending:
				_sent.erase(_pending)
				_pending = ""
		"subscribed":
			var topic: String = str(frame.get("topic", ""))
			if int(frame.get("requestId", 0)) == _pendingRequestId and topic == _pending:
				var accepted: bool = not _pendingCanceled and _topics.has(topic)
				if accepted:
					_sent[topic] = true
				_pending = ""
				# With a snapshot the client is current: no resync_required follows for this topic.
				if accepted and frame.get("snapshot") is Dictionary:
					var exact: Variant = _exact(frame, text).get("snapshot")
					if exact is Dictionary:
						snapshot_received.emit(topic, HorizonSharedObjectModels.encode(exact))
					else:
						resync_required.emit(topic)
		"ticket":
			if isReady:
				_storeTicket(frame.get("ticket"))
		"result":
			var request: int = int(frame.get("requestId", 0))
			if _sends.has(request):
				_settle(request, _resultResponse(frame, text))
		"event":
			if _topics.has(str(frame.get("topic", ""))):
				event_received.emit(frame)
			_send({"type": "ack", "eventId": str(frame.get("eventId", ""))})
		"resync_required":
			if str(frame.get("reason", "")) == "PERMISSIONS_CHANGED":
				_sent.clear()
			var topic: String = str(frame.get("topic", ""))
			if topic.is_empty():
				for subscribed: String in _topics.keys():
					if _syncIdentity():
						return
					if _topics.has(subscribed):
						resync_required.emit(subscribed)
			elif _topics.has(topic):
				resync_required.emit(topic)
			_send({"type": "ack", "eventId": str(frame.get("eventId", ""))})
		"error":
			var code: String = str(frame.get("code", ""))
			if code == "SESSION_REQUIRED" and _usedTicket and not isReady:
				# The ticket was refused: drop it and reconnect at once with the session token.
				_ticket = ""
				_failed(code, 0.0)
				return
			if code == "CONNECTION_LIMIT_REACHED":
				# No socket for this session for a while, everything goes over HTTP meanwhile.
				_failed(code, float(pollAfterSeconds))
				return
			if code == "SUBSCRIPTION_FORBIDDEN" and int(frame.get("requestId", 0)) == _pendingRequestId:
				var denied: String = str(frame.get("topic", ""))
				_topics.erase(denied)
				_sent.erase(denied)
				_pending = ""
				subscription_failed.emit(denied, "SUBSCRIPTION_FORBIDDEN")
			lastErrorCode = str(frame.get("code", "GATEWAY_UNAVAILABLE"))
			connection_error.emit(lastErrorCode)

## A delay of 0 or more replaces the backoff and keeps the attempt counter.
func _failed(code: String, delay: float = -1.0) -> void:
	_disconnect()
	lastErrorCode = code
	if delay >= 0.0:
		_retryAt = Time.get_ticks_msec() / 1000.0 + delay
	else:
		_retryAt = Time.get_ticks_msec() / 1000.0 + reconnectDelay(_attempt, randf())
		_attempt += 1
	connection_error.emit(code)

func _disconnect() -> void:
	_generation += 1
	if _socket != null:
		_socket.close()
	_socket = null
	isReady = false
	sendOverSocket = false
	_usedTicket = false
	_connecting = false
	_authenticated = false
	_sent.clear()
	_pending = ""
	# Results of this socket can no longer arrive: their outcome is unknown.
	for id: int in _sends.keys():
		_settle(id, null)

func _exit_tree() -> void:
	close()

func _send(frame: Dictionary, text: String = "") -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if _socket.get_current_outbound_buffered_amount() > 65536:
			_failed("SLOW_CONSUMER")
			return
		if _socket.send_text(text if not text.is_empty() else JSON.stringify(frame)) != OK:
			_failed("SLOW_CONSUMER")

func _settle(id: int, response: HorizonNetworkResponse) -> void:
	if not _sends.has(id):
		return
	_sends[id].response = response
	_sends.erase(id)
	_send_settled.emit(id)

func _ticketUsable(now: float) -> bool:
	return not _ticket.is_empty() and now - _ticketAt < TICKET_MAX_AGE_SECONDS

func _storeTicket(value: Variant) -> void:
	if value is String and not value.is_empty() and value.length() <= 1024:
		_ticket = value
		_ticketAt = Time.get_ticks_msec() / 1000.0

## Exact integers and strings for payloads that features validate like an HTTP body.
static func _exact(frame: Dictionary, text: String) -> Dictionary:
	if text.is_empty():
		return HorizonItemModels.parse(HorizonSharedObjectModels.encode(frame))
	return HorizonItemModels.parse(text)

## The same success value or error the HTTP call would have produced for this status and code.
func _resultResponse(frame: Dictionary, text: String) -> HorizonNetworkResponse:
	var status: int = int(frame.get("status", 0))
	if status >= 200 and status < 300:
		var body: Variant = _exact(frame, text).get("result")
		if not body is Dictionary:
			return HorizonNetworkResponse.failure("Invalid result frame", 0, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
		var success: HorizonNetworkResponse = HorizonNetworkResponse.success(body, status)
		success.rawBody = HorizonSharedObjectModels.encode(body)
		return success
	var code: String = frame.get("code") if frame.get("code") is String else ""
	var retry: Variant = frame.get("retryAfter")
	var failure: HorizonNetworkResponse = HorizonNetworkResponse.failure("HTTP %d" % status, status, HorizonErrorCodes.ErrorCode.API_RATE_LIMITED if status == 429 else HorizonErrorCodes.fromHttpStatus(status))
	failure.serverCode = code
	var body: Dictionary = {"code": code}
	if (retry is int or retry is float) and retry > 0:
		failure.headers = PackedStringArray(["Retry-After: %d" % int(retry)])
		body.retryAfter = int(retry)
	failure.errorBody = JSON.stringify(body)
	if status == 429 and _http != null:
		_http.rate_limited.emit(maxf(1.0, float(retry) if (retry is int or retry is float) else 1.0))
	return failure

func _syncIdentity() -> bool:
	if _http == null or _auth == null:
		return false
	var changed: bool = false
	var context: int = _http.getContextGeneration()
	if context != _contextGeneration:
		_ticket = ""
		_disconnect()
		_contextGeneration = context
		_unsupported = false
		_attempt = 0
		changed = true
	var user: String = _auth.getCurrentUser().userId if _auth.isSignedIn() else ""
	if user != _userId:
		if not _userId.is_empty():
			close()
		_userId = user
		changed = true
	if _http.sessionToken != _token:
		_ticket = ""
		_disconnect()
		_token = _http.sessionToken
		_unsupported = false
		_attempt = 0
		changed = true
	return changed
