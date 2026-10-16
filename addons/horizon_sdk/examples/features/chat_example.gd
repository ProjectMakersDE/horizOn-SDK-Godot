extends Node
## Bind feed_changed to a plain Label/RichTextLabel with BBCode DISABLED, never parse markup.
## Buttons: choose_channel -> push feed, send_text, inspect_pending, retry_original, report.
## Offline/permissions hide text. No timer/automatic send or price/state/ID substitution.
signal feed_changed(snapshot: Dictionary)
signal feed_hidden()
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_chat.gd")
var _channel: String = ""
var _selection: int = 0
var _busy: bool = false
var _watchOwner: String = ""
var _feedContext: String = ""
func _ready() -> void:
	_watchOwner = _uuid()
	var h: Node = get_node_or_null("/root/Horizon")
	if h != null:
		h.chat.channel_changed.connect(func(id: String, data: Dictionary):
			if id == _channel: _publish_feed())
		h.chat.channel_hidden.connect(func(id: String):
			if id == _channel: feed_hidden.emit())
func current_feed() -> Dictionary:
	var h: Node = _authorized()
	return h.chat.getCached(_channel) if h != null and not _channel.is_empty() and _same(h, _feedContext) else {}
func _publish_feed() -> void:
	var current: Dictionary = current_feed()
	if current.is_empty(): feed_hidden.emit()
	else: feed_changed.emit(current)
func _exit_tree() -> void:
	_selection += 1
	var h: Node = get_node_or_null("/root/Horizon")
	if h != null and not _channel.is_empty(): h.chat.stopWatching(_channel, _watchOwner)
	_channel = ""
	_feedContext = ""
func choose_channel(kind: String, peer_id: String = "", group_id: String = "") -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	_selection += 1
	var previous: String = _channel
	_channel = ""
	_feedContext = ""
	if not previous.is_empty(): h.chat.stopWatching(previous, _watchOwner)
	feed_hidden.emit()
	var context: String = _context(h)
	var selection: int = _selection
	_busy = true
	var result: Dictionary = await h.chat.openChannel(_user(h), kind, peer_id, group_id)
	_busy = false
	if selection != _selection or not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success:
		_channel = result.data.channel.id
		_feedContext = context
		if not h.chat.watchChannel(_user(h), _channel, _watchOwner): return _fail("SUBSCRIPTION_REQUIRED")
		_publish_feed()
	return result
func send_text(text: String) -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _channel.is_empty() or h.chat.getCached(_channel).is_empty(): return _fail("CHANNEL_REVIEW_REQUIRED")
	var loaded: Dictionary = Pending.load_pending(h._http.apiKey, _user(h))
	if not loaded.success: return _fail("PENDING_STORAGE_ERROR")
	if not loaded.pending.is_empty(): return _fail("PENDING_ACTION")
	var issued: String = h.chat.getServerTime()
	if not HorizonChatModels.time(issued) or not HorizonChatModels.text(text): return _fail("INVALID_REQUEST")
	var intent: Dictionary = {"project": h._http.apiKey.sha256_text(), "userId": _user(h), "operationId": _uuid(), "issuedAt": issued, "channelId": _channel, "text": text}
	var context: String = _context(h)
	if not Pending.store(h._http.apiKey, _user(h), intent): return _fail("PENDING_STORAGE_ERROR")
	if not _same(h, context): return _fail("STALE_RESPONSE")
	return await _send(h, intent, context)
## Explicit retry only. Missing/expired receipts never authorize another original operation.
func retry_original() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = Pending.load_pending(h._http.apiKey, _user(h))
	if not loaded.success: return _fail("PENDING_STORAGE_ERROR")
	if loaded.pending.is_empty(): return _fail("NO_PENDING_ACTION")
	return await _send(h, loaded.pending, _context(h))
func inspect_pending() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = Pending.load_pending(h._http.apiKey, _user(h))
	if not loaded.success: return _fail("PENDING_STORAGE_ERROR")
	if loaded.pending.is_empty(): return _fail("NO_PENDING_ACTION")
	var intent: Dictionary = loaded.pending
	var context: String = _context(h)
	_busy = true
	var result: Dictionary = await h.chat.getOperation(_user(h), intent.operationId)
	_busy = false
	if not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success and not Pending.confirm(h._http.apiKey, _user(h), intent, result.data.receipt): return _fail("PENDING_STORAGE_ERROR")
	return result
func report(message_id: String, original_reason: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _channel.is_empty(): return _fail("CHANNEL_REVIEW_REQUIRED")
	return await h.chat.reportMessage(_user(h), _channel, message_id, original_reason)
func _send(h: Node, intent: Dictionary, context: String) -> Dictionary:
	_busy = true
	var result: Dictionary = await h.chat.sendMessage(intent.userId, intent.channelId, intent.operationId, intent.issuedAt, intent.text)
	_busy = false
	if not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success and not Pending.confirm(h._http.apiKey, _user(h), intent, result.data.receipt): return _fail("PENDING_STORAGE_ERROR")
	return result
func _uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var raw: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [raw.substr(0, 8), raw.substr(8, 4), raw.substr(12, 4), raw.substr(16, 4), raw.substr(20)]
func _authorized() -> Node:
	if not is_inside_tree(): return null
	var h: Node = get_node_or_null("/root/Horizon")
	return h if h != null and h.auth.isSignedIn() and not h._http.sessionToken.is_empty() and h.auth.getCurrentUser().accessToken == h._http.sessionToken else null
func _user(h: Node) -> String: return h.auth.getCurrentUser().userId
func _context(h: Node) -> String: return JSON.stringify([h._http.getContextGeneration(), _user(h), h._http.apiKey, h._http.activeHost, h._http.sessionToken])
func _same(h: Node, context: String) -> bool: return _authorized() == h and _context(h) == context
func _fail(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
