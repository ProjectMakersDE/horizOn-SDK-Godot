## Optional change notifications. All state and message contents are still fetched over HTTP.
class_name HorizonRealtime
extends Node

signal event_received(event: Dictionary)
signal resync_required(topic: String)
signal polling_required(topic: String, poll_after_seconds: int)
signal connection_error(code: String)

## Optional full ws/wss URL for a separately exposed Dev gateway.
var gatewayUrl: String = ""
var pollAfterSeconds: int = 120
var isReady: bool = false
var lastErrorCode: String = ""
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _socket: WebSocketPeer
var _topics: Dictionary = {}
var _sent: Dictionary = {}
var _pending: String = ""
var _clientId: String = ""
var _token: String = ""
var _userId: String = ""
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

func setPollAfterSeconds(seconds: int) -> void:
	pollAfterSeconds = maxi(1, seconds)
	_pollAt = Time.get_ticks_msec() / 1000.0 + pollAfterSeconds

func unsubscribe(topic: String) -> void:
	if not _topics.has(topic):
		return
	_topics.erase(topic)
	_sent.erase(topic)
	if isReady:
		_send({"type": "unsubscribe", "topic": topic})
	if _topics.is_empty():
		_disconnect()

func close() -> void:
	_topics.clear()
	_disconnect()

static func reconnectDelay(attempt: int, random_fraction: float) -> float:
	return clampf(random_fraction, 0.0, 1.0) * minf(30.0, pow(2.0, mini(attempt, 5)))

static func canPoll(topic: String) -> bool:
	return not topic.begins_with("chat:")

static func _validTopic(topic: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^(inbox|matches|chat):[A-Za-z0-9._-]{1,96}$")
	return pattern.search(topic) != null

func _process(_delta: float) -> void:
	if _http == null or _auth == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
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
				_send({"type": "authenticate", "version": 1, "apiKey": _http.apiKey, "sessionToken": _token, "clientId": _clientId})
				if _socket == null:
					return
			while _socket.get_available_packet_count() > 0:
				if _syncIdentity():
					return
				var packet: PackedByteArray = _socket.get_packet()
				if packet.size() > 8192:
					_failed("INVALID_FRAME")
					return
				var frame: Variant = JSON.parse_string(packet.get_string_from_utf8())
				if frame is Dictionary:
					_handle(frame)
					if _socket == null:
						return
			if isReady:
				if _pending.is_empty():
					for topic: String in _topics:
						if not _sent.has(topic):
							_pending = topic
							_send({"type": "subscribe", "topic": topic})
							break
				if now >= _pingAt and _pending.is_empty():
					_send({"type": "ping"})
					_pingAt = now + 30.0
		elif state == WebSocketPeer.STATE_CLOSED:
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
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 65536
	_socket.outbound_buffer_size = 65536
	_socket.max_queued_packets = 64
	var url: String = _http.activeHost.trim_suffix("/").replace("https://", "wss://").replace("http://", "ws://") + "/api/v1/app/realtime/socket"
	if not gatewayUrl.is_empty():
		url = gatewayUrl
	if (not url.begins_with("ws://") and not url.begins_with("wss://")) or "?" in url or "@" in url:
		_failed("INVALID_GATEWAY_URL")
		return
	var result: Error = _socket.connect_to_url(url)
	_connectDeadline = Time.get_ticks_msec() / 1000.0 + 10.0
	if result != OK:
		_failed("CONNECTION_FAILED")

func _handle(frame: Dictionary) -> void:
	_lastFrameAt = Time.get_ticks_msec() / 1000.0
	if int(frame.get("version", 0)) != 1:
		_failed("INVALID_FRAME")
		return
	match str(frame.get("type", "")):
		"ready":
			isReady = true
			_attempt = 0
			pollAfterSeconds = maxi(1, int(frame.get("pollAfterSeconds", 120)))
			_pingAt = Time.get_ticks_msec() / 1000.0 + 30.0
		"unsubscribed":
			_sent.erase(str(frame.get("topic", "")))
			if str(frame.get("topic", "")) == _pending:
				_pending = ""
		"subscribed":
			var topic: String = str(frame.get("topic", ""))
			if topic == _pending:
				_sent[topic] = true
				_pending = ""
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
		"error":
			if str(frame.get("code", "")) == "SUBSCRIPTION_FORBIDDEN":
				var denied: String = str(frame.get("topic", ""))
				_topics.erase(denied)
				_sent.erase(denied)
				_pending = ""
			lastErrorCode = str(frame.get("code", "GATEWAY_UNAVAILABLE"))
			connection_error.emit(lastErrorCode)

func _failed(code: String) -> void:
	_disconnect()
	lastErrorCode = code
	_retryAt = Time.get_ticks_msec() / 1000.0 + reconnectDelay(_attempt, randf())
	_attempt += 1
	connection_error.emit(code)

func _disconnect() -> void:
	_generation += 1
	if _socket != null:
		_socket.close()
	_socket = null
	isReady = false
	_connecting = false
	_authenticated = false
	_sent.clear()
	_pending = ""

func _exit_tree() -> void:
	close()

func _send(frame: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if _socket.get_current_outbound_buffered_amount() > 65536:
			_failed("SLOW_CONSUMER")
			return
		if _socket.send_text(JSON.stringify(frame)) != OK:
			_failed("SLOW_CONSUMER")

func _syncIdentity() -> bool:
	if _http == null or _auth == null:
		return false
	var changed: bool = false
	var user: String = _auth.getCurrentUser().userId if _auth.isSignedIn() else ""
	if user != _userId:
		if not _userId.is_empty():
			close()
		_userId = user
		changed = true
	if _http.sessionToken != _token:
		_disconnect()
		_token = _http.sessionToken
		_unsupported = false
		_attempt = 0
		changed = true
	return changed
