class_name HorizonMatches
extends RefCounted
## Explicit reads and one-shot commands. Neither consensus nor a timeout proves a game outcome.
signal matches_loaded(kind: String, data: Dictionary)
signal matches_changed(kind: String, data: Dictionary)
signal matches_failed(error: String, code: String)
signal _request_finished()
const ENDPOINT := "/api/v1/app/matches"
var _http: HorizonHttpClient
var _auth: HorizonAuth
var _validated: HorizonValidatedActions
var _scope: Dictionary = {}
var _cache: Dictionary = {}
var _versions: Dictionary = {}
var _times: Dictionary = {}
var _refresh: Dictionary = {}
var _runIds: Dictionary = {}
var _epoch: int = 0
var _queueEpoch: int = 0
var _busy: bool = false
var _lastErrorCode: String = ""
var _nowMillis: Callable = func() -> int: return Time.get_ticks_msec()
func initialize(http: HorizonHttpClient, auth: HorizonAuth, validated: HorizonValidatedActions = null, realtime: HorizonRealtime = null) -> void:
	_http = http
	_auth = auth
	_validated = validated
	_auth.signout_completed.connect(_reset)
	_auth.signin_completed.connect(_playerChanged)
	_auth.signup_completed.connect(_playerChanged)
	if realtime != null:
		realtime.event_received.connect(_realtimeEvent)
		realtime.resync_required.connect(_realtimeResync)
		realtime.connection_error.connect(_realtimeError)
func encodeState(bytes: PackedByteArray) -> String: return HorizonMatchModels.encodeBytes(bytes)
func getMatches(user_id: String, recovery: bool = false) -> Dictionary: return await _call(user_id, "mine", "", null, {}, recovery)
func getLimits(user_id: String) -> Dictionary: return await _call(user_id, "limits")
func findOpenMatches(user_id: String, minimum_strength: Variant, maximum_strength: Variant, limit: Variant = 20, cursor: String = "") -> Dictionary:
	if not HorizonMatchModels.integer(minimum_strength, -HorizonMatchModels.MAX) or not HorizonMatchModels.integer(maximum_strength, -HorizonMatchModels.MAX) or minimum_strength > maximum_strength or not HorizonMatchModels.integer(limit, 1) or limit > 50 or (not cursor.is_empty() and HorizonMatchModels.cursor(cursor).is_empty()): return _fail("INVALID_REQUEST")
	return await _call(user_id, "open", "", null, {"minStrength": minimum_strength, "maxStrength": maximum_strength, "limit": limit, "cursor": cursor})
func getMatch(user_id: String, match_id: String, recovery: bool = false) -> Dictionary:
	if not HorizonMatchModels.uuid(match_id): return _fail("INVALID_REQUEST")
	return await _call(user_id, "get", match_id, null, {}, recovery)
func createMatch(user_id: String, expected_player_revision: Variant, options: Dictionary) -> Dictionary:
	if not _revision(expected_player_revision) or not HorizonMatchModels.createOptions(options): return _fail("INVALID_REQUEST")
	var canonical: Dictionary = options.duplicate(true)
	canonical.inviteeIds = _canonicalIds(options.inviteeIds)
	if user_id.to_lower() in canonical.inviteeIds: return _fail("INVALID_REQUEST")
	return await _call(user_id, "create", "", expected_player_revision, canonical)
func joinMatch(user_id: String, match_id: String, expected_revision: Variant) -> Dictionary: return await _action(user_id, match_id, "join", expected_revision)
func declineInvite(user_id: String, match_id: String, expected_revision: Variant) -> Dictionary: return await _action(user_id, match_id, "decline", expected_revision)
func startMatch(user_id: String, match_id: String, expected_revision: Variant, turn_order: Array) -> Dictionary:
	if not HorizonMatchModels.ids(turn_order) or turn_order.size() < 2: return _fail("INVALID_REQUEST")
	return await _action(user_id, match_id, "start", expected_revision, {"turnOrder": _canonicalIds(turn_order)})
func submitTurn(user_id: String, match_id: String, expected_revision: Variant, state: PackedByteArray, finish: Variant = false) -> Dictionary:
	if state.size() > HorizonMatchModels.STATE_BYTES or not finish is bool: return _fail("INVALID_REQUEST")
	return await _action(user_id, match_id, "turn", expected_revision, {"dataBase64": encodeState(state), "finish": finish})
func advanceTimeout(user_id: String, match_id: String, expected_revision: Variant) -> Dictionary: return await _action(user_id, match_id, "timeout", expected_revision)
func leaveMatch(user_id: String, match_id: String, expected_revision: Variant) -> Dictionary: return await _action(user_id, match_id, "leave", expected_revision)
func cancelMatch(user_id: String, match_id: String, expected_revision: Variant) -> Dictionary: return await _action(user_id, match_id, "cancel", expected_revision)
func reportResult(user_id: String, match_id: String, final_state_revision: Variant, result: PackedByteArray, winner_ids: Array) -> Dictionary:
	if not HorizonMatchModels.uuid(match_id) or not HorizonMatchModels.integer(final_state_revision, 1) or result.size() > HorizonMatchModels.RESULT_BYTES or not HorizonMatchModels.ids(winner_ids): return _fail("INVALID_REQUEST")
	var canonical: Array = _canonicalIds(winner_ids)
	var sorted: Array = canonical.duplicate()
	sorted.sort()
	if sorted != canonical: return _fail("INVALID_REQUEST")
	return await _call(user_id, "result", match_id, null, {"finalStateRevision": final_state_revision, "resultBase64": HorizonMatchModels.encodeBytes(result), "winnerIds": canonical})
func startRankedRun(user_id: String, match_id: String, final_state_revision: Variant) -> Dictionary:
	if not HorizonMatchModels.uuid(match_id) or not HorizonMatchModels.integer(final_state_revision, 1): return _fail("INVALID_REQUEST")
	return await _call(user_id, "ranked-run", match_id, null, {"finalStateRevision": final_state_revision})
func _action(user: String, id: String, kind: String, revision: Variant, body: Dictionary = {}) -> Dictionary:
	if not HorizonMatchModels.uuid(id) or not _revision(revision): return _fail("INVALID_REQUEST")
	return await _call(user, kind, id, revision, body)
func _canonicalIds(values: Array) -> Array:
	var result: Array = []
	for value: String in values: result.append(value.to_lower())
	return result
func _revision(value: Variant) -> bool: return HorizonMatchModels.integer(value) and value < HorizonMatchModels.MAX
func getCached(identity: String) -> Dictionary:
	_syncScope()
	return _cache.get(identity, {}).duplicate(true) if _hasSession() else {}
func getLastErrorCode() -> String: return _lastErrorCode
func clearCache() -> void:
	_queueEpoch += 1
	_invalidate()
func _invalidate() -> void:
	_epoch += 1
	_cache.clear()
	_refresh.clear()
func _call(user: String, kind: String, id: String = "", expected: Variant = null, payload: Dictionary = {}, recovery: bool = false) -> Dictionary:
	user = user.to_lower()
	id = id.to_lower()
	_syncScope()
	if not _hasSession(): return _fail("SESSION_REQUIRED")
	if user != _scope.user: return _fail("SESSION_FORBIDDEN")
	if not HorizonMatchModels.uuid(user): return _fail("INVALID_REQUEST")
	var original: String = HorizonMatchModels.encode(payload)
	var options: Dictionary = HorizonMatchModels.parse(original)
	if options.is_empty() and not payload.is_empty(): return _fail("INVALID_REQUEST")
	var scope: Dictionary = _scope.duplicate()
	var queued: int = _queueEpoch
	while _busy: await _request_finished
	_syncScope()
	if scope != _scope or queued != _queueEpoch: return _fail("STALE_RESPONSE")
	var mutation: bool = kind not in ["mine", "limits", "open", "get"]
	var identity: String = HorizonMatchModels.encode([scope, kind, id, expected, options]).sha256_text()
	var refresh_key: String = _resource(kind, id, options)
	var continuation: bool = kind == "open" and not options.cursor.is_empty()
	if not mutation and not recovery and not continuation and _delay(refresh_key) > 0:
		var refused: Dictionary = _fail("REFRESH_NOT_DUE")
		refused.retryAfterSeconds = _delay(refresh_key)
		return refused
	var lease: int = 0
	var run_binding: String = id + ":" + str(options.get("finalStateRevision", ""))
	if kind == "ranked-run":
		if _validated == null: return _fail("VALIDATED_ACTIONS_UNAVAILABLE")
		var active: Dictionary = _validated.getCurrentRun()
		if not active.is_empty() and active.get("runId") != _runIds.get(run_binding): return _fail("RUN_IN_PROGRESS")
		lease = _validated._claimRunStart()
		if lease == 0: return _fail("RUN_IN_PROGRESS")
	_busy = true
	if mutation: _invalidate()
	var epoch: int = _epoch
	var endpoint: String = ENDPOINT
	match kind:
		"limits", "open": endpoint += "/" + kind
		"get": endpoint += "/" + id
		"mine", "create": pass
		_: endpoint += "/" + id + "/" + kind
	var response: HorizonNetworkResponse
	if mutation:
		var body: Dictionary = options.duplicate(true)
		body.userId = user
		var headers := PackedStringArray(["If-Match: " + str(expected)]) if expected != null else PackedStringArray()
		response = await _http.postJsonHeadersOnceAsync(endpoint, body, true, HorizonMatchModels.encode(body), headers)
	else:
		endpoint += "?userId=" + user.uri_encode()
		if kind == "open":
			endpoint += "&minStrength=" + str(options.minStrength) + "&maxStrength=" + str(options.maxStrength) + "&limit=" + str(options.limit)
			if not options.cursor.is_empty(): endpoint += "&cursor=" + options.cursor.uri_encode()
		response = await _http.getAsync(endpoint, true)
	_syncScope()
	var result: Dictionary
	if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	elif not response.isSuccess:
		if response.statusCode == 401: clearCache()
		result = _fail(HorizonInbox._responseCode(response), response.error)
	else:
		var data: Dictionary = HorizonMatchModels.response(HorizonMatchModels.parse(response.rawBody), kind, user, id, expected, options)
		if data.is_empty() or not _effect(kind, user, data, options): result = _fail("INVALID_RESPONSE")
		elif not _fresh(kind, id, data, refresh_key, run_binding): result = _fail("STALE_RESPONSE")
		elif kind == "ranked-run" and not _validated._acceptMatchRun(data, user, scope.generation, lease, id, options.finalStateRevision): result = _fail("RUN_IN_PROGRESS")
		else:
			_syncScope()
			if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
			else:
				_record(kind, id, data, refresh_key, run_binding)
				_cache[identity] = data.duplicate(true)
				if not mutation and not continuation: _refresh[refresh_key] = {"millis": int(_nowMillis.call()), "seconds": data.pollAfterSeconds}
				_trim(_cache, 8)
				_trim(_refresh, 512)
				_lastErrorCode = ""
				result = {"success": true, "data": data.duplicate(true), "identity": identity, "errorCode": "", "error": ""}
				if mutation: matches_changed.emit(kind, data.duplicate(true))
				else: matches_loaded.emit(kind, data.duplicate(true))
				_syncScope()
				if scope != _scope or epoch != _epoch: result = _fail("STALE_RESPONSE")
	if lease != 0: _validated._releaseRunStart(lease)
	_busy = false
	_request_finished.emit()
	_syncScope()
	if result.success and (scope != _scope or queued != _queueEpoch): return _fail("STALE_RESPONSE")
	return result
func _effect(kind: String, user: String, data: Dictionary, options: Dictionary) -> bool:
	if kind == "ranked-run": return true
	if not data.has("match"): return true
	var row: Dictionary = data.match
	match kind:
		"create":
			for field: String in ["name", "capacity", "visibility", "strength", "turnSeconds", "timeoutPolicy", "ranked", "dataBase64"]:
				if HorizonMatchModels.encode(row[field]) != HorizonMatchModels.encode(options[field]): return false
			return row.participantIds == [user] and row.invitedIds == options.inviteeIds
		"join": return user in row.participantIds
		"decline": return user not in row.participantIds and user not in row.invitedIds
		"start": return row.status == "active" and row.turnOrder == options.turnOrder and row.currentPlayerId == options.turnOrder[0]
		"turn": return row.dataBase64 == options.dataBase64 and row.status == ("reporting" if options.finish else "active")
		"leave": return user not in row.participantIds or user in row.forfeitedIds or row.status in ["cancelled", "unconfirmed"]
		"cancel": return row.status == "cancelled" and row.creatorId == user
		"result":
			for report: Dictionary in row.reports:
				if report.userId == user: return report.resultBase64 == options.resultBase64 and report.winnerIds == options.winnerIds and report.finalStateRevision == options.finalStateRevision
			return false
	return true
func _resource(kind: String, id: String, options: Dictionary) -> String:
	if kind in ["get", "create", "join", "decline", "start", "turn", "timeout", "leave", "cancel", "result"]: return "match:" + id
	if kind == "open": return "open:" + HorizonMatchModels.encode([options.minStrength, options.maxStrength, options.limit]).sha256_text()
	return kind
func _versionEntries(data: Dictionary) -> Dictionary:
	var versions: Dictionary = {}
	if data.has("userId") and data.has("revision"): versions.ledger = data.revision
	if data.has("playerRevision"): versions.ledger = data.playerRevision
	if data.has("match"): versions["match:" + data.match.id] = data.match.revision
	for key: String in ["active", "invites", "recent"]:
		for row: Dictionary in data.get(key, []): versions["match:" + row.id] = row.revision
	if data.has("config"): versions.config = data.config.revision
	return versions
func _fresh(kind: String, _id: String, data: Dictionary, resource: String, run_binding: String) -> bool:
	if kind == "ranked-run": return not _runIds.has(run_binding) or _runIds[run_binding] == data.runId
	if data.has("match"): resource = "match:" + data.match.id
	if HorizonPlayerValues._timeMillis(data.serverTime) < _times.get(resource, -1): return false
	var versions: Dictionary = _versionEntries(data)
	for key: String in versions:
		if versions[key] < _versions.get(key, -1): return false
	return true
func _record(kind: String, _id: String, data: Dictionary, resource: String, run_binding: String) -> void:
	if kind == "ranked-run": _runIds[run_binding] = data.runId
	else:
		if data.has("match"): resource = "match:" + data.match.id
		_times[resource] = HorizonPlayerValues._timeMillis(data.serverTime)
		_versions.merge(_versionEntries(data), true)
		if data.has("match") and data.match.ownRankedRunId != null and data.match.finalStateRevision != null: _runIds[data.match.id + ":" + str(data.match.finalStateRevision)] = data.match.ownRankedRunId
	_trim(_times, 512)
	_trim(_versions, 512)
	_trim(_runIds, 128)
func _delay(resource: String) -> int:
	if not _refresh.has(resource): return 0
	var hint: Dictionary = _refresh[resource]
	return maxi(0, hint.seconds - floori(float(maxi(0, int(_nowMillis.call()) - hint.millis)) / 1000.0))
func _trim(values: Dictionary, maximum: int) -> void:
	while values.size() > maximum: values.erase(values.keys()[0])
func _syncScope() -> void:
	var user: HorizonUserData = _auth.getCurrentUser()
	var current: Dictionary = {"user": user.userId if user != null else "", "authToken": user.accessToken if user != null else "", "project": _http.apiKey, "host": _http.activeHost, "token": _http.sessionToken, "generation": _http.getContextGeneration()}
	if current != _scope:
		_reset()
		_scope = current
func _hasSession() -> bool:
	var user: HorizonUserData = _auth.getCurrentUser()
	return user != null and _auth.isSignedIn() and not _http.sessionToken.is_empty() and user.accessToken == _http.sessionToken
func _realtimeEvent(event: Dictionary) -> void: _realtimeResync(str(event.get("topic", "")))
func _realtimeResync(topic: String) -> void:
	if topic.is_empty() or topic.begins_with("matches:"): clearCache()
func _realtimeError(_code: String) -> void: clearCache()
func _playerChanged(_user: HorizonUserData) -> void: _reset()
func _reset() -> void:
	clearCache()
	_scope = {}
	_versions.clear()
	_times.clear()
	_runIds.clear()
func _fail(code: String, error: String = "") -> Dictionary:
	_lastErrorCode = code
	var message: String = code if error.is_empty() else error
	matches_failed.emit(message, code)
	return {"success": false, "data": {}, "errorCode": code, "error": message}
