## Bounded server snapshots. Call on game lifecycle events; there is no background poller.
class_name HorizonInbox
extends RefCounted

signal inbox_loaded(snapshot: Dictionary)
signal inbox_updated(snapshot: Dictionary)
signal entry_claimed(result: Dictionary)
signal inbox_failed(error: String, code: String)
signal _request_finished()

const ENDPOINT := "/api/v1/app/inbox"
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
		if raw.get("entryId") != entry_id or typeof(raw.get("replayed")) != TYPE_BOOL or not _values.acceptServerState(user_id, raw.get("playerValues")):
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
	for field: String in ["targeted", "broadcasts"]:
		if not _nonnegative(result.limits.get(field)):
			return {}
		result.limits[field] = int(result.limits[field])
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
		# Downgrades prevent new deliveries, but cannot hide retained valuable messages.
		# Use the server's global storage bounds, independent of the current plan limits.
		if result.entries.size() > 550:
			return {}
		var ids: Dictionary = {}
		var kinds: Dictionary = {"message": 0, "broadcast": 0}
		for entry: Variant in result.entries:
			if not entry is Dictionary or not _validEntryId(entry.get("id", "")) or ids.has(entry.id) or not entry.get("kind") in ["message", "broadcast"] or not entry.id.begins_with(entry.kind + ":"):
				return {}
			ids[entry.id] = true
			kinds[entry.kind] += 1
			if kinds.message > 50 or kinds.broadcast > 500:
				return {}
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
				if not entry.attachment is Dictionary or not entry.attachment.get("values") is Array or entry.attachment.values.size() > 8:
					return {}
				var keys: Dictionary = {}
				for amount: Variant in entry.attachment.values:
					if not amount is Dictionary or not amount.get("key") is String or keys.has(amount.key) or not _nonnegative(amount.get("amount")) or amount.amount <= 0:
						return {}
					keys[amount.key] = true
					amount.amount = int(amount.amount)
	return result

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
