class_name HorizonMatchModels
extends RefCounted
## Exact JSON integers, explicit nulls and opaque state. No game-state interpretation.
const MAX := 9007199254740991
const STATE_BYTES := 14648 * 1024 # BSON/Jackson string envelope; not the current MATCH_STATE_KIB quota.
const RESULT_BYTES := 256
const STATUSES := ["lobby", "active", "reporting", "confirmed", "disputed", "unconfirmed", "cancelled"]
const TERMINAL := ["confirmed", "disputed", "unconfirmed", "cancelled"]
const ACTIONS := ["join", "decline", "start", "turn", "timeout", "leave", "cancel"]
const SUMMARY := ["id", "name", "revision", "creatorId", "capacity", "visibility", "strength", "status", "participantIds", "invitedIds", "forfeitedIds", "currentPlayerId", "turnDeadline", "createdAt", "startedAt", "finishedAt", "purgeAt", "finalStateRevision", "hasDisagreement", "ranked", "timeoutDue"]
const VIEW := ["turnOrder", "turnSeconds", "timeoutPolicy", "dataBase64", "reports", "reportDeadline", "absoluteDeadline", "rankedLeaderboardKey", "ownRankedRunId", "notificationPending"]
static var _base64: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]*+={0,2}\\z")
static var _hash: RegEx = RegEx.create_from_string("^[a-f0-9]{64}\\z")
static var _signed: RegEx = RegEx.create_from_string("^-?(0|[1-9][0-9]*)\\z")
static func integer(value: Variant, minimum: int = 0) -> bool: return HorizonItemModels.integer(value, minimum)
static func uuid(value: Variant) -> bool: return HorizonItemModels.uuid(value)
static func time(value: Variant) -> bool: return HorizonItemModels.time(value)
static func parse(raw: String) -> Dictionary: return HorizonItemModels.parseTransport(raw)
static func encode(value: Variant) -> String: return HorizonSharedObjectModels.encode(value)
static func encodeBytes(bytes: PackedByteArray) -> String: return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)
static func decodeBytes(value: Variant, maximum: int = STATE_BYTES) -> Variant:
	if not value is String or value.length() % 4 != 0 or value.length() > int((maximum + 2) / 3) * 4 or _base64.search(value) == null: return null
	var bytes: PackedByteArray = PackedByteArray() if value.is_empty() else Marshalls.base64_to_raw(value)
	return bytes if bytes.size() <= maximum and encodeBytes(bytes) == value else null
static func text(value: Variant, maximum: int, nonblank: bool = false) -> bool:
	if not HorizonSharedObjectModels.text(value, maximum): return false
	if not nonblank or value is HorizonItemStringData: return true
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if (code >= 0x09 and code <= 0x0d) or (code >= 0x1c and code <= 0x20) or code == 0x00a0 or code == 0x1680 or (code >= 0x2000 and code <= 0x200a) or code == 0x2028 or code == 0x2029 or code == 0x202f or code == 0x205f or code == 0x3000: continue
		return true
	return false
static func fields(value: Variant, required: Array, exact: bool = false) -> bool:
	if not value is Dictionary or (exact and value.size() != required.size()): return false
	for key: String in required:
		if not value.has(key): return false
	return true
static func ids(value: Variant, maximum: int = 8) -> bool:
	if not value is Array or value.size() > maximum: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not uuid(id) or seen.has(id.to_lower()): return false
		seen[id.to_lower()] = true
	return true
static func limits(value: Variant) -> bool:
	var names: Array[String] = ["activeMatches", "stateBytes", "retainedMatches", "pendingInvites", "settlementMatches", "historyRetentionSeconds", "rankedSettlementSeconds"]
	if not fields(value, names): return false
	for key: String in names:
		if not integer(value[key], 0 if key in ["retainedMatches", "historyRetentionSeconds"] else 1) or value[key] > 2147483647: return false
	return value.stateBytes <= STATE_BYTES
static func createOptions(value: Variant) -> bool:
	if not fields(value, ["name", "capacity", "visibility", "strength", "turnSeconds", "timeoutPolicy", "ranked", "dataBase64", "inviteeIds"], true): return false
	return text(value.name, 120, true) and integer(value.capacity, 2) and value.capacity <= 8 and value.visibility in ["open", "private"] and integer(value.strength, -MAX) and integer(value.turnSeconds, 60) and value.turnSeconds <= 604800 and value.timeoutPolicy in ["skip", "forfeit"] and value.ranked is bool and decodeBytes(value.dataBase64) is PackedByteArray and ids(value.inviteeIds, 7) and value.inviteeIds.size() < value.capacity
static func cursor(value: Variant) -> Dictionary:
	if not value is String or value.is_empty() or value.length() > 256 or _base64.search(value) == null: return {}
	var bytes: PackedByteArray = Marshalls.base64_to_raw(value)
	if encodeBytes(bytes) != value: return {}
	for byte: int in bytes:
		if byte < 32 or byte > 126: return {}
	var parts: PackedStringArray = bytes.get_string_from_ascii().split("|")
	if parts.size() != 4 or parts[0] != "m1" or _hash.search(parts[1]) == null or _signed.search(parts[2]) == null or parts[2].length() > 17 or not integer(int(parts[2]), -MAX) or str(int(parts[2])) != parts[2] or not uuid(parts[3]) or parts[3] != parts[3].to_lower(): return {}
	return {"strength": int(parts[2]), "id": parts[3]}
static func summary(raw: Variant) -> Dictionary:
	if not fields(raw, SUMMARY) or not uuid(raw.id) or not text(raw.name, 120, true) or not integer(raw.revision, 1) or not uuid(raw.creatorId) or not integer(raw.capacity, 2) or raw.capacity > 8 or raw.visibility not in ["open", "private"] or not integer(raw.strength, -MAX) or raw.status not in STATUSES: return {}
	if not ids(raw.participantIds) or raw.participantIds.is_empty() or raw.participantIds.size() > raw.capacity or raw.creatorId not in raw.participantIds or not ids(raw.invitedIds, 7) or not ids(raw.forfeitedIds): return {}
	for id: String in raw.invitedIds:
		if id in raw.participantIds: return {}
	for id: String in raw.forfeitedIds:
		if id not in raw.participantIds: return {}
	if not raw.hasDisagreement is bool or not raw.ranked is bool or not raw.timeoutDue is bool or not time(raw.createdAt): return {}
	for key: String in ["turnDeadline", "startedAt", "finishedAt", "purgeAt"]:
		if raw[key] != null and not time(raw[key]): return {}
	if raw.currentPlayerId != null and (not uuid(raw.currentPlayerId) or raw.currentPlayerId not in raw.participantIds or raw.currentPlayerId in raw.forfeitedIds): return {}
	if raw.finalStateRevision != null and (not integer(raw.finalStateRevision, 1) or raw.finalStateRevision > raw.revision): return {}
	if raw.status == "active":
		if raw.currentPlayerId == null or raw.turnDeadline == null or raw.startedAt == null or raw.finishedAt != null or raw.purgeAt != null or raw.finalStateRevision != null: return {}
	elif raw.currentPlayerId != null or raw.turnDeadline != null or raw.timeoutDue: return {}
	if raw.status == "lobby" and (raw.startedAt != null or raw.finishedAt != null or raw.purgeAt != null or raw.finalStateRevision != null or not raw.forfeitedIds.is_empty()): return {}
	if raw.status == "reporting" and (raw.startedAt == null or raw.finalStateRevision == null or raw.finishedAt != null or raw.purgeAt != null): return {}
	if raw.status in TERMINAL and (raw.finishedAt == null or raw.purgeAt == null): return {}
	var result: Dictionary = {}
	for key: String in SUMMARY: result[key] = raw[key]
	return result.duplicate(true)
static func view(raw: Variant, user: String, kind: String) -> Dictionary:
	var result: Dictionary = summary(raw)
	if result.is_empty() or not fields(raw, VIEW) or not ids(raw.turnOrder) or not integer(raw.turnSeconds, 60) or raw.turnSeconds > 604800 or raw.timeoutPolicy not in ["skip", "forfeit"] or not raw.notificationPending is bool: return {}
	var joined: bool = user in raw.participantIds
	var departure: bool = kind in ["leave", "decline"] and raw.status == "lobby"
	if not joined and not departure and not (raw.status == "lobby" and user in raw.invitedIds): return {}
	if raw.dataBase64 == null:
		if joined: return {}
		result.data = null
	else:
		if not joined: return {}
		var bytes: Variant = decodeBytes(raw.dataBase64)
		if not bytes is PackedByteArray: return {}
		result.data = bytes
	for key: String in ["reportDeadline", "absoluteDeadline"]:
		if raw[key] != null and not time(raw[key]): return {}
	if raw.rankedLeaderboardKey != null and (not text(raw.rankedLeaderboardKey, 128, true) or not raw.rankedLeaderboardKey is String): return {}
	if raw.ownRankedRunId != null and (not uuid(raw.ownRankedRunId) or not joined): return {}
	if raw.status == "lobby":
		if not raw.turnOrder.is_empty() or raw.absoluteDeadline != null or raw.reportDeadline != null: return {}
	elif raw.status != "cancelled" and (raw.turnOrder.size() != raw.participantIds.size() or raw.absoluteDeadline == null): return {}
	for id: String in raw.turnOrder:
		if id not in raw.participantIds: return {}
	if raw.status == "reporting" and raw.reportDeadline == null: return {}
	if not raw.reports is Array or raw.reports.size() > 8 or (not joined and not raw.reports.is_empty()): return {}
	var reports: Array = []
	var seen: Dictionary = {}
	for report: Variant in raw.reports:
		if not fields(report, ["userId", "finalStateRevision", "resultBase64", "winnerIds", "reportedAt"]) or not uuid(report.userId) or report.userId not in raw.participantIds or seen.has(report.userId) or not integer(report.finalStateRevision, 1) or report.finalStateRevision != raw.finalStateRevision or not ids(report.winnerIds) or not time(report.reportedAt): return {}
		var previous: String = ""
		for id: String in report.winnerIds:
			if id not in raw.participantIds or id <= previous: return {}
			previous = id
		var bytes: Variant = decodeBytes(report.resultBase64, RESULT_BYTES)
		if not bytes is PackedByteArray: return {}
		reports.append({"userId": report.userId, "finalStateRevision": report.finalStateRevision, "resultBase64": report.resultBase64, "result": bytes, "winnerIds": report.winnerIds.duplicate(), "reportedAt": report.reportedAt})
		seen[report.userId] = true
	for key: String in VIEW: result[key] = raw[key]
	result.reports = reports
	return result.duplicate(true)
static func run(raw: Variant) -> Dictionary:
	if not fields(raw, ["runId", "ticket", "seed", "leaderboardKey", "issuedAt", "expiresAt", "expiresInSeconds"]) or not uuid(raw.runId) or not text(raw.ticket, 32768, true) or not raw.ticket is String or not integer(raw.seed) or raw.seed > 2147483646 or not text(raw.leaderboardKey, 128, true) or not raw.leaderboardKey is String or not time(raw.issuedAt) or not time(raw.expiresAt) or not integer(raw.expiresInSeconds, 1) or raw.expiresInSeconds > 21600: return {}
	if HorizonPlayerValues._timeMillis(raw.expiresAt) <= HorizonPlayerValues._timeMillis(raw.issuedAt): return {}
	var result: Dictionary = {}
	for key: String in ["runId", "ticket", "seed", "leaderboardKey", "issuedAt", "expiresAt", "expiresInSeconds"]: result[key] = raw[key]
	return result.duplicate(true)
static func response(raw: Dictionary, kind: String, user: String, id: String = "", expected: Variant = null, options: Dictionary = {}) -> Dictionary:
	if kind == "ranked-run": return run(raw)
	if not time(raw.get("serverTime")) or not integer(raw.get("pollAfterSeconds"), 1): return {}
	var result: Dictionary = {"serverTime": raw.serverTime, "pollAfterSeconds": raw.pollAfterSeconds}
	if kind == "limits":
		if not limits(raw.get("limits")) or not fields(raw.get("config"), ["revision", "rankedLeaderboardKey"]) or not integer(raw.config.revision) or (raw.config.rankedLeaderboardKey != null and not text(raw.config.rankedLeaderboardKey, 128, true)) or not fields(raw.get("capabilities"), ["matches", "matchesRanked", "realtime"]): return {}
		for key: String in ["matches", "matchesRanked", "realtime"]:
			if not raw.capabilities[key] is bool: return {}
		if not raw.capabilities.matches: return {}
		return result.merged({"limits": raw.limits.duplicate(true), "config": raw.config.duplicate(true), "capabilities": raw.capabilities.duplicate(true)})
	if kind == "mine":
		if raw.get("userId") != user or not integer(raw.get("revision")) or not limits(raw.get("limits")): return {}
		result.merge({"userId": user, "revision": raw.revision, "limits": raw.limits.duplicate(true)})
		var seen: Dictionary = {}
		for key: String in ["active", "invites", "recent"]:
			if not raw.get(key) is Array: return {}
			var rows: Array = []
			for row: Variant in raw[key]:
				var parsed: Dictionary = summary(row)
				if parsed.is_empty() or seen.has(parsed.id): return {}
				if key == "invites":
					if parsed.status != "lobby" or user not in parsed.invitedIds or user in parsed.participantIds: return {}
				else:
					if user not in parsed.participantIds: return {}
					if key == "active" and (parsed.status not in ["lobby", "active"] or user in parsed.forfeitedIds): return {}
					if key == "recent" and (parsed.status == "lobby" or (parsed.status == "active" and user not in parsed.forfeitedIds)): return {}
				seen[parsed.id] = true
				rows.append(parsed)
			result[key] = rows
		if not raw.get("pendingResults") is Array: return {}
		var pending: Array = []
		var pending_ids: Dictionary = {}
		for row: Variant in raw.pendingResults:
			if not fields(row, ["matchId", "finalStateRevision", "ownRankedRunId", "expiresAt"]) or not uuid(row.matchId) or not integer(row.finalStateRevision, 1) or (row.ownRankedRunId != null and not uuid(row.ownRankedRunId)) or not time(row.expiresAt) or pending_ids.has(row.matchId.to_lower()): return {}
			pending_ids[row.matchId.to_lower()] = true
			pending.append({"matchId": row.matchId, "finalStateRevision": row.finalStateRevision, "ownRankedRunId": row.ownRankedRunId, "expiresAt": row.expiresAt})
		result.pendingResults = pending
		return result
	if kind == "open":
		if not raw.get("matches") is Array or raw.matches.size() > options.limit or not raw.has("nextCursor"): return {}
		var previous: Dictionary = cursor(options.cursor) if not options.cursor.is_empty() else {}
		var rows: Array = []
		for row: Variant in raw.matches:
			var parsed: Dictionary = summary(row)
			if parsed.is_empty() or parsed.status != "lobby" or parsed.visibility != "open" or parsed.participantIds.size() >= parsed.capacity or user in parsed.participantIds or parsed.strength < options.minStrength or parsed.strength > options.maxStrength: return {}
			if not previous.is_empty() and (parsed.strength < previous.strength or (parsed.strength == previous.strength and parsed.id <= previous.id)): return {}
			previous = {"strength": parsed.strength, "id": parsed.id}
			rows.append(parsed)
		if raw.nextCursor != null:
			var next: Dictionary = cursor(raw.nextCursor)
			if next.is_empty() or next.strength < options.minStrength or next.strength > options.maxStrength or (not previous.is_empty() and (next.strength < previous.strength or (next.strength == previous.strength and next.id < previous.id))) or raw.nextCursor == options.cursor: return {}
		result.matches = rows
		result.nextCursor = raw.nextCursor
		return result
	var parsed: Dictionary = view(raw.get("match"), user, kind)
	if parsed.is_empty() or (not id.is_empty() and parsed.id != id): return {}
	if kind not in ["get", "result", "create"] and parsed.revision != expected + 1: return {}
	if kind == "create":
		if not integer(raw.get("playerRevision"), 1) or raw.playerRevision != expected + 1 or parsed.creatorId != user or parsed.revision != 1 or parsed.status != "lobby": return {}
		result.playerRevision = raw.playerRevision
	if kind == "result":
		if not raw.get("replayed") is bool or parsed.finalStateRevision != options.finalStateRevision: return {}
		result.replayed = raw.replayed
	result.match = parsed
	return result
