class_name HorizonChatModels
extends RefCounted
## Chat text is plain Unicode; numeric wire tokens, nulls and identities stay exact.
const MAX := 9007199254740991
const RETENTION_MILLIS := 604800000
static var _uuid: RegEx = RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z")
static var _time: RegEx = RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z\\z")
static func uuid(value: Variant) -> bool: return value is String and _uuid.search(value) != null
static func integer(value: Variant, maximum: int = MAX) -> bool: return typeof(value) == TYPE_INT and value >= 0 and value <= maximum
static func fields(value: Variant, names: Array) -> bool:
	if not value is Dictionary: return false
	for name: String in names:
		if not value.has(name): return false
	return true
static func time(value: Variant) -> bool:
	if not value is String or _time.search(value) == null: return false
	var year: int = value.substr(0, 4).to_int()
	var month: int = value.substr(5, 2).to_int()
	var day: int = value.substr(8, 2).to_int()
	var days: Array[int] = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year < 1970 or month < 1 or month > 12 or day < 1 or day > days[month - 1] or value.substr(11, 2).to_int() > 23 or value.substr(14, 2).to_int() > 59 or value.substr(17, 2).to_int() > 59: return false
	var seconds: int = Time.get_unix_time_from_datetime_string(value.substr(0, 19))
	return seconds >= 0 and Time.get_datetime_string_from_unix_time(seconds) == value.substr(0, 19)
static func millis(value: String) -> int: return Time.get_unix_time_from_datetime_string(value.substr(0, 19)) * 1000 + value.substr(20, 3).to_int()
static func stamp(value: int) -> String: return Time.get_datetime_string_from_unix_time(value / 1000) + ".%03dZ" % (value % 1000)
static func blank(value: String) -> bool:
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if (code >= 9 and code <= 13) or (code >= 28 and code <= 32) or code in [0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] or (code >= 0x2000 and code <= 0x200a): continue
		return false
	return true
static func text(value: Variant, characters: int = 500, bytes: int = 2000) -> bool:
	if not value is String or value.length() > characters or value.to_utf8_buffer().size() > bytes or blank(value): return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if (code < 32 and code not in [9, 10]) or (code >= 127 and code <= 159) or (code >= 0xd800 and code <= 0xdfff): return false
	return true
static func ids(value: Variant) -> bool:
	if not value is Array or value.size() > 20: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not uuid(id) or seen.has(id): return false
		seen[id] = true
	return true
static func moderation(value: Variant) -> bool:
	if not fields(value, ["muteUntil", "banUntil"]): return false
	for name: String in ["muteUntil", "banUntil"]:
		if value[name] != null and not time(value[name]): return false
	return true
static func channel(value: Variant, id: String = "") -> bool:
	if not fields(value, ["id", "epoch", "kind", "peerIds", "groupId", "revision", "expiresAt"]) or not uuid(value.id) or (not id.is_empty() and value.id != id) or not uuid(value.epoch) or not integer(value.revision) or not time(value.expiresAt) or not ids(value.peerIds): return false
	match value.kind:
		"direct": return value.peerIds.size() == 2 and value.peerIds[0] < value.peerIds[1] and value.groupId == null
		"group": return value.peerIds.is_empty() and uuid(value.groupId)
		"project": return value.peerIds.is_empty() and value.groupId == null
	return false
static func message(value: Variant, id: String) -> bool:
	return fields(value, ["id", "channelId", "authorId", "text", "createdAt", "expiresAt"]) and uuid(value.id) and value.channelId == id and uuid(value.authorId) and text(value.text) and time(value.createdAt) and time(value.expiresAt) and millis(value.expiresAt) > millis(value.createdAt) and millis(value.expiresAt) - millis(value.createdAt) <= RETENTION_MILLIS
static func receipt(value: Variant) -> bool:
	return fields(value, ["operationId", "issuedAt", "channelId", "messageId", "createdAt", "expiresAt"]) and uuid(value.operationId) and uuid(value.channelId) and uuid(value.messageId) and time(value.issuedAt) and time(value.createdAt) and time(value.expiresAt) and millis(value.expiresAt) > millis(value.createdAt) and millis(value.expiresAt) - millis(value.createdAt) <= RETENTION_MILLIS
static func limits(value: Variant) -> bool:
	if not fields(value, ["retainedMessagesPerPlayer", "retainedMessagesPerChannel", "retentionSeconds", "privateRetainedMessagesPerChannel", "privateRetentionSeconds", "operationWindowSeconds", "operationFutureToleranceSeconds", "messageCharacters", "messageUtf8Bytes", "channelsPerAccount", "sendsPerAccountMinute", "playerSendIntervalMillis", "channelSendIntervalMillis", "reportsPerProject", "receiptCount", "reportReceiptCount", "wordFilterTerms"]): return false
	for key: String in value:
		if not integer(value[key]): return false
	return value.retainedMessagesPerPlayer == 0 and value.retainedMessagesPerChannel == 20 and value.privateRetainedMessagesPerChannel == 15 and value.privateRetentionSeconds == 30 and value.operationWindowSeconds == 30 and value.operationFutureToleranceSeconds == 60 and value.retentionSeconds == 604800 and value.messageCharacters == 500 and value.messageUtf8Bytes == 2000 and value.channelsPerAccount <= 2000 and value.sendsPerAccountMinute <= 120 and value.reportsPerProject <= 200 and value.receiptCount == 0 and value.reportReceiptCount == 0 and value.wordFilterTerms == 100
static func parse(raw: String) -> Dictionary: return HorizonItemModels.parse(raw, 1048576)
static func envelope(raw: String, kind: String, user: String, id: String = "", options: Dictionary = {}) -> Dictionary:
	var data: Dictionary = parse(raw)
	if not time(data.get("serverTime")): return {}
	match kind:
		"limits":
			if not limits(data.get("limits")) or not moderation(data.get("moderation")) or not fields(data.get("capabilities"), ["chat", "realtime", "incrementalSync", "localHistory"]): return {}
			for key: String in ["chat", "realtime", "incrementalSync", "localHistory"]:
				if not data.capabilities[key] is bool: return {}
		"open":
			if not channel(data.get("channel")) or data.channel.kind != options.kind: return {}
			if options.kind == "direct":
				var peers: Array = [user, options.peerId]
				peers.sort()
				if data.channel.peerIds != peers: return {}
			elif options.kind == "group" and data.channel.groupId != options.groupId: return {}
		"sync":
			if not channel(data.get("channel"), id) or (data.channel.kind == "direct" and user not in data.channel.peerIds) or not ids(data.get("visibleMessageIds")) or not data.get("messages") is Array or data.messages.size() > (20 if data.channel.kind == "project" else 15) or not moderation(data.get("moderation")): return {}
			if data.visibleMessageIds.size() > (20 if data.channel.kind == "project" else 15): return {}
			var seen: Dictionary = {}
			for row: Variant in data.messages:
				if not message(row, id) or seen.has(row.id) or row.id not in data.visibleMessageIds or (data.channel.kind == "direct" and row.authorId not in data.channel.peerIds) or millis(row.expiresAt) <= millis(data.serverTime): return {}
				if millis(row.expiresAt) - millis(row.createdAt) > (RETENTION_MILLIS if data.channel.kind == "project" else 30000): return {}
				seen[row.id] = true
		"send", "operation":
			if not receipt(data.get("receipt")) or data.receipt.operationId != options.operationId: return {}
			if kind == "send" and (not data.get("replayed") is bool or data.receipt.channelId != id or data.receipt.issuedAt != options.issuedAt): return {}
		"report":
			if not uuid(data.get("reportId")) or data.get("status") not in ["open", "dismissed", "actioned", "removed"] or not data.get("replayed") is bool: return {}
		_: return {}
	return data.duplicate(true)
