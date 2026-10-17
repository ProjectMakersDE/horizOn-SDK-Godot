## Bounded server snapshots. Call on game lifecycle events; there is no background poller.
class_name HorizonInbox
extends RefCounted

signal inbox_loaded(snapshot: Dictionary)
signal inbox_updated(snapshot: Dictionary)
signal entry_claimed(result: Dictionary)
signal inbox_failed(error: String, code: String)
signal _request_finished()

const ENDPOINT := "/api/v1/app/inbox"
enum SourceKind { UNKNOWN, FRIEND_REQUEST, FRIEND_ACCEPTED, GROUP_INVITATION, GROUP_REQUEST, GROUP_INVITATION_ACCEPTED, GROUP_REQUEST_ACCEPTED, MATCH_TURN, MARKET_RETURN }
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _values: HorizonPlayerValues
var _scope: Dictionary = {}
var _epoch: int = 0
var _queueEpoch: int = 0
var _revision: int = -1
var _broadcastRevision: int = -1
var _serverTime: int = -1
var _current: Dictionary = {}
var _busy: bool = false
var _lastErrorCode: String = ""

func initialize(http: HorizonHttpClient, auth: HorizonAuth, values: HorizonPlayerValues) -> void:
	_http = http
	_auth = auth
	_values = values
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)

func getCurrentInbox() -> Dictionary:
	_syncScope()
	return _current.duplicate(true)

func getLastErrorCode() -> String:
	return _lastErrorCode

## Invalidate cached contents and in-flight requests, retaining freshness watermarks.
## Optional realtime notifications may call this; notification metadata is never inbox data.
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()

func _invalidate() -> void:
	_epoch += 1
	_current.clear()

func getInbox(user_id: String, since: String = "") -> Dictionary:
	return await _call(user_id, "", "", since)

func markRead(user_id: String, entry_id: String) -> Dictionary:
	return await _call(user_id, "/read", entry_id)

func remove(user_id: String, entry_id: String) -> Dictionary:
	return await _call(user_id, "/remove", entry_id)

## Retrying the same entry ID is safe, including after a timeout. Never add reward deltas locally.
func claim(user_id: String, entry_id: String) -> Dictionary:
	return await _call(user_id, "/claim", entry_id)

func _call(user_id: String, route: String, entry_id: String = "", since: String = "") -> Dictionary:
	_syncScope()
	if not _hasSession():
		return _fail("SESSION_REQUIRED")
	if user_id != _scope.user:
		return _fail("SESSION_FORBIDDEN")
	if since.length() > 128 or (not route.is_empty() and not _validEntryId(entry_id)):
		return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var queued_epoch: int = _queueEpoch
	# Every waiting caller performs its own follow-up request. No stale in-flight GET is shared.
	while _busy:
		await _request_finished
	_syncScope()
	if scope != _scope or queued_epoch != _queueEpoch:
		return _fail("STALE_RESPONSE")
	_busy = true
	if not route.is_empty():
		_invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT + "?userId=" + user_id.uri_encode()
	var sent_cursor: String = ""
	if route.is_empty() and not _current.is_empty() and since == _current.cursor:
		sent_cursor = since
		endpoint += "&since=" + since.uri_encode()
	var response: HorizonNetworkResponse = await _http.getAsync(endpoint, true) if route.is_empty() else await _http.postAsync(ENDPOINT + route, {"userId": user_id, "entryId": entry_id}, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch:
		result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401:
			clearCache()
		result = _fail(_responseCode(response), response.error)
	elif not _safeJson(response.rawBody):
		result = _fail("INVALID_RESPONSE")
	else:
		result = _consume(response.data, user_id, route, entry_id, sent_cursor)
	_busy = false
	_request_finished.emit()
	return result

func _consume(raw: Variant, user_id: String, route: String, entry_id: String, sent_cursor: String) -> Dictionary:
	if not raw is Dictionary:
		return _fail("INVALID_RESPONSE")
	var snapshot: Variant = raw.get("inbox") if route == "/claim" else raw
	var normalized: Dictionary = _normalize(snapshot, user_id, sent_cursor)
	if normalized.is_empty():
		return _fail("INVALID_RESPONSE")
	var millis: int = HorizonPlayerValues._timeMillis(normalized.serverTime)
	if normalized.revision < _revision or normalized.broadcastRevision < _broadcastRevision or millis < _serverTime:
		return _fail("STALE_RESPONSE")
	if route == "/claim":
		if raw.get("entryId") != entry_id or typeof(raw.get("replayed")) != TYPE_BOOL or not _validItems(raw.get("items", [])) or not _values.acceptServerState(user_id, raw.get("playerValues")):
			return _fail("INVALID_RESPONSE")
	_revision = normalized.revision
	_broadcastRevision = normalized.broadcastRevision
	_serverTime = millis
	_current = normalized.duplicate(true)
	_lastErrorCode = ""
	var data: Dictionary = raw.duplicate(true) if route == "/claim" else normalized
	if route == "/claim":
		data.inbox = normalized
		data.playerValues = _values.getCurrentState()
		data.items = raw.get("items", []).duplicate(true)
		entry_claimed.emit(data.duplicate(true))
	elif route.is_empty():
		inbox_loaded.emit(data.duplicate(true))
	else:
		inbox_updated.emit(data.duplicate(true))
	return {"success": true, "data": data, "errorCode": "", "error": ""}

func _normalize(raw: Variant, user_id: String, sent_cursor: String) -> Dictionary:
	if not raw is Dictionary or raw.get("userId") != user_id or not raw.get("cursor") is String or raw.cursor.is_empty() or raw.cursor.length() > 128 or HorizonPlayerValues._timeMillis(raw.get("serverTime")) < 0 or typeof(raw.get("unchanged")) != TYPE_BOOL or not raw.get("entries") is Array or not raw.get("counts") is Dictionary or not raw.get("limits") is Dictionary:
		return {}
	var result: Dictionary = raw.duplicate(true)
	for field: String in ["revision", "broadcastRevision", "pollAfterSeconds"]:
		if not _nonnegative(raw.get(field)):
			return {}
		result[field] = int(raw[field])
	if result.pollAfterSeconds < 1:
		return {}
	var defaults: Dictionary = {"freeTexts": 2, "freeTextBytes": 256, "freeTextRetentionDays": 7}
	for field: String in ["targeted", "broadcasts", "freeTexts", "freeTextBytes", "freeTextRetentionDays"]:
		var limit: Variant = result.limits.get(field, defaults.get(field))
		if not _nonnegative(limit) or limit < 1 or limit > 2147483647:
			return {}
		result.limits[field] = int(limit)
	for count: Variant in result.counts.values():
		if not count is Dictionary:
			return {}
		for field: String in ["total", "unread", "claimable"]:
			if not _nonnegative(count.get(field)):
				return {}
			count[field] = int(count[field])
	if result.unchanged:
		if sent_cursor.is_empty() or _current.is_empty() or sent_cursor != _current.cursor or result.cursor != sent_cursor or not result.entries.is_empty() or result.revision != _current.revision or result.broadcastRevision != _current.broadcastRevision:
			return {}
		result.entries = _current.entries.duplicate(true)
	else:
		# Configured quotas govern writes. Retained entries remain readable after an admin lowers them.
		var ids: Dictionary = {}
		for entry: Variant in result.entries:
			if not entry is Dictionary or not _validEntryId(entry.get("id", "")) or ids.has(entry.id) or not entry.get("kind") in ["message", "broadcast"] or not entry.id.begins_with(entry.kind + ":"):
				return {}
			ids[entry.id] = true
			for field: String in ["type", "reference", "textKey", "createdAt", "expiresAt"]:
				if not entry.get(field) is String:
					return {}
			if HorizonPlayerValues._timeMillis(entry.createdAt) < 0 or HorizonPlayerValues._timeMillis(entry.expiresAt) < 0 or not entry.get("parameters") is Dictionary:
				return {}
			for parameter: Variant in entry.parameters.values():
				if not parameter is String:
					return {}
			for field: String in ["overdue", "read", "claimed"]:
				if typeof(entry.get(field)) != TYPE_BOOL:
					return {}
			if entry.get("attachment") != null:
				if not entry.attachment is Dictionary:
					return {}
				for field: Variant in entry.attachment:
					if field not in ["values", "itemReturn"]:
						return {}
				var amounts: Variant = entry.attachment.get("values", [])
				if not amounts is Array or amounts.size() > 8:
					return {}
				entry.attachment.values = amounts
				var keys: Dictionary = {}
				for amount: Variant in amounts:
					if not amount is Dictionary or amount.size() != 2 or not amount.get("key") is String or amount.key.is_empty() or amount.key.length() > 24 or keys.has(amount.key) or not _nonnegative(amount.get("amount")) or amount.amount <= 0:
						return {}
					keys[amount.key] = true
					amount.amount = int(amount.amount)
				var item: Variant = entry.attachment.get("itemReturn")
				if item != null and (not item is Dictionary or item.size() != 3 or not _uuid(item.get("listingId")) or not _uuid(item.get("instanceId")) or not _itemKey(item.get("itemKey"))):
					return {}
			if _sourceKind(entry) != SourceKind.UNKNOWN and getSource(entry).is_empty():
				return {}
			if entry.kind == "message" and entry.type == "free_text" and entry.textKey == "horizon.inbox.free_text" and not isFreeText(entry):
				return {}
	return result

## Navigation metadata only. Keep the original entry ID for read/remove/claim and use the source API for actions.
static func getSource(entry: Dictionary) -> Dictionary:
	var kind: SourceKind = _sourceKind(entry)
	if kind == SourceKind.UNKNOWN or not _uuid(entry.get("reference")):
		return {}
	var result: Dictionary = {"kind": kind, "sourceId": String(entry.reference).to_lower()}
	var parameters: Variant = entry.get("parameters")
	if not parameters is Dictionary:
		return {}
	if kind in [SourceKind.FRIEND_REQUEST, SourceKind.FRIEND_ACCEPTED]:
		if not _uuid(parameters.get("userId")):
			return {}
		result.userId = String(parameters.userId).to_lower()
	elif kind in [SourceKind.GROUP_INVITATION, SourceKind.GROUP_REQUEST, SourceKind.GROUP_INVITATION_ACCEPTED, SourceKind.GROUP_REQUEST_ACCEPTED]:
		if not _uuid(parameters.get("groupId")):
			return {}
		result.groupId = String(parameters.groupId).to_lower()
	elif kind == SourceKind.MATCH_TURN:
		var revision: Variant = parameters.get("revision")
		if not _uuid(parameters.get("matchId")) or String(parameters.matchId).to_lower() != result.sourceId or not revision is String or not revision.is_valid_int() or revision.begins_with("+") or revision.length() > 16 or not _nonnegative(int(revision)):
			return {}
		result.revision = int(revision)
	elif kind == SourceKind.MARKET_RETURN:
		var attachment: Variant = entry.get("attachment")
		if not attachment is Dictionary or not attachment.get("itemReturn") is Dictionary or not _uuid(attachment.itemReturn.get("listingId")) or String(attachment.itemReturn.listingId).to_lower() != result.sourceId:
			return {}
	return result

static func _sourceKind(entry: Dictionary) -> SourceKind:
	if entry.get("kind") != "message":
		return SourceKind.UNKNOWN
	match str(entry.get("type")) + ":" + str(entry.get("textKey")):
		"friend_request:horizon.friends.request": return SourceKind.FRIEND_REQUEST
		"friend_accept:horizon.friends.accept": return SourceKind.FRIEND_ACCEPTED
		"group_invite:horizon.groups.invite": return SourceKind.GROUP_INVITATION
		"group_request:horizon.groups.request": return SourceKind.GROUP_REQUEST
		"group_accept-invite:horizon.groups.accept-invite": return SourceKind.GROUP_INVITATION_ACCEPTED
		"group_accept-request:horizon.groups.accept-request": return SourceKind.GROUP_REQUEST_ACCEPTED
		"match_turn:horizon.matches.your_turn": return SourceKind.MATCH_TURN
		"marketplace:marketplace.item_return": return SourceKind.MARKET_RETURN
	return SourceKind.UNKNOWN

static func isFreeText(entry: Dictionary) -> bool:
	return entry.get("kind") == "message" and entry.get("type") == "free_text" and entry.get("textKey") == "horizon.inbox.free_text" and entry.get("parameters") is Dictionary and entry.parameters.get("text") is String

## Render as plain text, with markup/rich-text disabled.
static func getFreeText(entry: Dictionary) -> String:
	return entry.parameters.text if isFreeText(entry) else ""

static func canClaim(entry: Dictionary) -> bool:
	var attachment: Variant = entry.get("attachment")
	return typeof(entry.get("claimed")) == TYPE_BOOL and not entry.claimed and attachment is Dictionary and ((attachment.get("values") is Array and not attachment.values.is_empty()) or attachment.get("itemReturn") is Dictionary)

static func _validItems(value: Variant) -> bool:
	if not value is Array or value.size() > 4:
		return false
	var ids: Dictionary = {}
	for item: Variant in value:
		if not item is Dictionary or not _uuid(item.get("instanceId")) or not _itemKey(item.get("itemKey")) or ids.has(String(item.instanceId).to_lower()):
			return false
		ids[String(item.instanceId).to_lower()] = true
	return true

static func _uuid(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z").search(value) != null

static func _itemKey(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}\\z").search(value) != null

func _hasSession() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return user != null and _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken

func _syncScope() -> void:
	var user: HorizonUserData = _auth.getCurrentUser()
	var value: Dictionary = {"host": _http.activeHost, "project": _http.apiKey, "token": _http.sessionToken, "user": user.userId if user != null else ""}
	if value != _scope:
		_reset()
		_scope = value

func _playerChanged(_user: HorizonUserData) -> void:
	_reset()

func _reset() -> void:
	clearCache()
	_scope = {}
	_revision = -1
	_broadcastRevision = -1
	_serverTime = -1
	_lastErrorCode = ""

func _fail(code: String, message: String = "") -> Dictionary:
	_lastErrorCode = code
	var error: String = message if not message.is_empty() else code
	inbox_failed.emit(error, code)
	return {"success": false, "data": {}, "errorCode": code, "error": error}

static func _validEntryId(value: Variant) -> bool:
	if not value is String:
		return false
	var expression: RegEx = RegEx.new()
	expression.compile("^(message|broadcast):[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
	return expression.search(value) != null

static func _nonnegative(value: Variant) -> bool:
	return HorizonPlayerValues._safeNumber(value) and value >= 0

## Check number lexemes before Godot's JSON float conversion can round an unsafe integer.
## String tokens are skipped, so text/parameters containing JSON-like text remain valid.
static func _safeJson(value: String) -> bool:
	var tokens: RegEx = RegEx.new()
	tokens.compile('"(?:[^"\\\\]|\\\\.)*"|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
	for token: RegExMatch in tokens.search_all(value):
		var text: String = token.get_string()
		if not text.begins_with('"') and (not text.is_valid_int() or text.length() > 17 or not HorizonPlayerValues._safeNumber(int(text))):
			return false
	return true

static func _responseCode(response: HorizonNetworkResponse) -> String:
	if not response.serverCode.is_empty():
		return response.serverCode
	match response.statusCode:
		0: return "NETWORK_ERROR"
		401: return "SESSION_REQUIRED"
		403: return "SESSION_FORBIDDEN"
		429: return "RATE_LIMITED"
		_: return "HTTP_%d" % response.statusCode
