extends Node
## Two copies run under TWO distinct signed-in players. Call each step from an explicit UI decision:
## A read_matches/create_reviewed(invite B), B read_match/join, A read_match/start,
## A/B read_match/turn in server turn order, finish, then each player read_match/report.
## A timeout requires explicit timeout. Missing/disagreeing reports never imply a winner.
## Realtime/reconnect only invalidates; call read_match explicitly. notificationPending may remain
## true with a full Inbox: the successful game move is still valid, never repeat it for a notice.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_match.gd")
var _ledger: Dictionary = {}
var _match: Dictionary = {}
var _recovery: Dictionary = {}
var _selection: int = 0
var _busy: bool = false
var _ranked: Dictionary = {}
func clear_review() -> void:
	_selection += 1
	_ledger.clear()
	_match.clear()
	_recovery.clear()
func read_matches() -> Dictionary:
	return await _read("")
func read_match(match_id: String) -> Dictionary:
	return await _read(match_id)
func _read(id: String) -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	clear_review()
	var selection: int = _selection
	var context: String = _context(h)
	_busy = true
	var result: Dictionary = await h.matches.getMatches(_user(h), true) if id.is_empty() else await h.matches.getMatch(_user(h), id, true)
	_busy = false
	if selection != _selection or not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success:
		if id.is_empty(): _ledger = {"data": result.data.duplicate(true), "context": context}
		else: _match = {"data": result.data.match.duplicate(true), "context": context}
	return result
func find_open(minimum: int, maximum: int, cursor: String = "") -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	return await h.matches.findOpenMatches(_user(h), minimum, maximum, 20, cursor)
func create_reviewed(options: Dictionary) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _ledger.is_empty() or not _same(h, _ledger.context): return _fail("REVIEW_REQUIRED")
	return await _new(h, "create", "", _ledger.data.revision, options)

## Full match detail may have expired. Only the original minimal source authorizes
## this explicit ranked recovery; expiresAt is never permission to mint a replacement.
func recover_pending_ranked_result(match_id: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _ledger.is_empty() or not _same(h, _ledger.context): return _fail("REVIEW_REQUIRED")
	for source: Dictionary in _ledger.data.pendingResults:
		if source.matchId == match_id:
			return await _new(h, "ranked-run", source.matchId, source.finalStateRevision, {"finalStateRevision": source.finalStateRevision})
	return _fail("ORIGINAL_SOURCE_REQUIRED")
## kind: join/decline/start/turn/timeout/leave/cancel/result/ranked-run. body uses exact REST fields.
## The player must first review read_match. For turn pass dataBase64 + finish explicitly;
## for result pass the original finalStateRevision/resultBase64/sorted winnerIds.
func perform_reviewed(kind: String, body: Dictionary = {}) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _match.is_empty() or not _same(h, _match.context): return _fail("REVIEW_REQUIRED")
	if kind in ["result", "ranked-run"] and (body.get("finalStateRevision") != _match.data.finalStateRevision or (kind == "ranked-run" and _match.data.status != "confirmed")): return _fail("REVIEW_REQUIRED")
	return await _new(h, kind, _match.data.id, _match.data.revision, body)
func _new(h: Node, kind: String, id: String, revision: Variant, body: Dictionary) -> Dictionary:
	if _busy: return _fail("BUSY")
	var loaded: Dictionary = _load(h)
	if not loaded.success: return loaded
	if not loaded.pending.is_empty(): return _fail("PENDING_ACTION")
	var frozen: Dictionary = body.duplicate(true)
	for field: String in ["inviteeIds", "turnOrder", "winnerIds"]:
		if frozen.has(field) and HorizonMatchModels.ids(frozen[field]):
			var canonical: Array = []
			for id_value: String in frozen[field]: canonical.append(id_value.to_lower())
			frozen[field] = canonical
	var intent: Dictionary = {"userId": _user(h), "project": h._http.apiKey.sha256_text(), "kind": kind, "matchId": id, "expectedRevision": revision, "bodyJson": HorizonMatchModels.encode(frozen)}
	if not _valid(intent, h): return _fail("INVALID_REQUEST")
	var context: String = _context(h)
	var selection: int = _selection
	if not _store(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
	if not _same(h, context) or selection != _selection: return _fail("STALE_RESPONSE")
	return await _send(h, intent, context, selection)
func _send(h: Node, intent: Dictionary, context: String, selection: int) -> Dictionary:
	_busy = true
	var body: Dictionary = HorizonMatchModels.parse(intent.bodyJson)
	var result: Dictionary
	var user: String = intent.userId
	var id: String = intent.matchId
	var revision: int = intent.expectedRevision
	match intent.kind:
		"create": result = await h.matches.createMatch(user, revision, body)
		"join": result = await h.matches.joinMatch(user, id, revision)
		"decline": result = await h.matches.declineInvite(user, id, revision)
		"start": result = await h.matches.startMatch(user, id, revision, body.turnOrder)
		"turn": result = await h.matches.submitTurn(user, id, revision, Marshalls.base64_to_raw(body.dataBase64), body.finish)
		"timeout": result = await h.matches.advanceTimeout(user, id, revision)
		"leave": result = await h.matches.leaveMatch(user, id, revision)
		"cancel": result = await h.matches.cancelMatch(user, id, revision)
		"result": result = await h.matches.reportResult(user, id, body.finalStateRevision, Marshalls.base64_to_raw(body.resultBase64), body.winnerIds)
		_: result = await h.matches.startRankedRun(user, id, body.finalStateRevision)
	_busy = false
	if not _same(h, context) or selection != _selection: return _fail("STALE_RESPONSE")
	if result.success:
		if not _confirm(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
		clear_review()
		if result.data.has("match"): _match = {"data": result.data.match.duplicate(true), "context": context}
		if intent.kind == "ranked-run": _ranked = {"runId": result.data.runId, "matchId": id, "finalStateRevision": body.finalStateRevision, "context": context}
	elif intent.kind == "ranked-run" and result.errorCode in ["RUN_EXPIRED", "RUN_ALREADY_USED"]:
		_recovery = {"intent": intent.duplicate(true), "data": {"terminalCode": result.errorCode}, "context": context, "terminalRun": true, "generation": h._http.getContextGeneration()}
	return result # Every failure keeps the immutable original, even after an auth/host change.
## Only immutable report/run recovery can explicitly resend the original. Never retry a create/turn.
func retry_original_report_or_run() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = _load(h)
	if not loaded.success: return loaded
	if loaded.pending.is_empty() or loaded.pending.kind not in ["result", "ranked-run"]: return _fail("RECOVERY_READ_REQUIRED")
	return await _send(h, loaded.pending, _context(h), _selection)
## Read-only recovery after a lost response/restart. Does not assume that the original succeeded.
func inspect_pending() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = _load(h)
	if not loaded.success or loaded.pending.is_empty(): return loaded if not loaded.success else _fail("NO_PENDING_ACTION")
	var intent: Dictionary = loaded.pending
	var context: String = _context(h)
	var selection: int = _selection
	_recovery.clear()
	_busy = true
	var departure: bool = intent.kind in ["decline", "leave"]
	var result: Dictionary = await h.matches.getMatches(_user(h), true) if intent.kind == "create" or departure else await h.matches.getMatch(_user(h), intent.matchId, true)
	_busy = false
	if not _same(h, context) or selection != _selection: return _fail("STALE_RESPONSE")
	if result.success: _recovery = {"intent": intent.duplicate(true), "data": result.data.duplicate(true), "context": context, "departure": departure}
	return result # A 404 does NOT prove that an unknown public join did not commit.
## Render recovered state first, then require an explicit player confirmation. A higher monotone CAS
## revision prevents any still-late original create/action from applying. Departure also accepts
## complete ledger absence (no remaining membership/invite). Ranked terminal errors allow only an
## explicit ACK of the expired/consumed original; no replacement run. No fabricated success.
func acknowledge_reconciliation() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = _load(h)
	if not loaded.success or loaded.pending.is_empty() or _recovery.is_empty() or loaded.pending != _recovery.intent or not _same(h, _recovery.context): return _fail("REVIEW_REQUIRED")
	var intent: Dictionary = loaded.pending
	if intent.kind == "result": return _fail("ORIGINAL_RECOVERY_REQUIRED")
	if intent.kind == "ranked-run":
		if not _recovery.get("terminalRun", false): return _fail("ORIGINAL_RECOVERY_REQUIRED")
	elif _recovery.get("departure", false):
		for category: String in ["active", "invites", "recent"]:
			for row: Dictionary in _recovery.data[category]:
				if row.id == intent.matchId and row.revision <= intent.expectedRevision: return _fail("UNCONFIRMED_ACTION")
	else:
		var revision: int = _recovery.data.revision if intent.kind == "create" else _recovery.data.match.revision
		if revision <= intent.expectedRevision: return _fail("UNCONFIRMED_ACTION")
	if not _confirm(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
	var result: Dictionary = _recovery.data.duplicate(true)
	if intent.kind == "ranked-run":
		var body: Dictionary = HorizonMatchModels.parse(intent.bodyJson)
		h.validatedActions._retireMatchRun(intent.userId, intent.matchId, body.finalStateRevision, _recovery.generation)
	clear_review()
	return {"success": true, "data": result, "errorCode": "", "error": ""}
## Confirmed-match recipe: after perform_reviewed("ranked-run", {finalStateRevision: ...}),
## run the game's short post-match rule check using returned seed, then submit the ACTUAL score/log.
## This cannot retrospectively validate every asynchronous turn or grant client-authored rewards.
func submit_ranked_check(score: int, input_log: PackedByteArray) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _busy or _ranked.is_empty() or not _same(h, _ranked.context) or h.validatedActions.getCurrentRun().get("runId") != _ranked.runId: return _fail("RUN_REVIEW_REQUIRED")
	_busy = true
	var result: Dictionary = await h.validatedActions.submitValidated(score, input_log)
	_busy = false
	if not _same(h, _ranked.context): return _fail("STALE_RESPONSE")
	if result.is_empty(): return _fail(h.validatedActions.getLastErrorCode())
	if not result.get("accepted", false) or result.get("runId") != _ranked.runId: return _fail("INVALID_RESPONSE")
	_ranked.clear()
	return {"success": true, "data": result, "errorCode": "", "error": ""}
func _valid(intent: Variant, h: Node) -> bool:
	if not intent is Dictionary or intent.size() != 6 or intent.get("project") != h._http.apiKey.sha256_text() or intent.get("userId") != _user(h) or not HorizonMatchModels.integer(intent.get("expectedRevision")) or intent.expectedRevision >= HorizonMatchModels.MAX or not intent.get("bodyJson") is String: return false
	var body: Dictionary = HorizonMatchModels.parse(intent.bodyJson)
	if intent.get("kind") == "create": return intent.get("matchId") == "" and HorizonMatchModels.createOptions(body) and _user(h) not in body.inviteeIds
	if not HorizonMatchModels.uuid(intent.get("matchId")): return false
	match intent.get("kind"):
		"join", "decline", "timeout", "leave", "cancel": return body.is_empty() and intent.bodyJson == "{}"
		"start": return body.size() == 1 and HorizonMatchModels.ids(body.get("turnOrder")) and body.turnOrder.size() >= 2
		"turn": return body.size() == 2 and body.get("finish") is bool and HorizonMatchModels.decodeBytes(body.get("dataBase64")) is PackedByteArray
		"result":
			if body.size() != 3 or not HorizonMatchModels.integer(body.get("finalStateRevision"), 1) or not HorizonMatchModels.decodeBytes(body.get("resultBase64"), 256) is PackedByteArray or not HorizonMatchModels.ids(body.get("winnerIds")): return false
			var sorted: Array = body.winnerIds.duplicate()
			sorted.sort()
			return sorted == body.winnerIds
		"ranked-run": return body.size() == 1 and HorizonMatchModels.integer(body.get("finalStateRevision"), 1)
	return false
func _load(h: Node) -> Dictionary:
	var loaded: Dictionary = Pending.load_pending(_path(h))
	if not loaded.success or (not loaded.pending.is_empty() and not _valid(loaded.pending, h)): return _fail("PENDING_STORAGE_ERROR")
	return loaded
func _path(h: Node) -> String: return Pending.path(h._http.apiKey, _user(h))
func _user(h: Node) -> String: return h.auth.getCurrentUser().userId
func _context(h: Node) -> String: return JSON.stringify([h._http.getContextGeneration(), _user(h), h.auth.getCurrentUser().accessToken, h._http.apiKey, h._http.activeHost, h._http.sessionToken])
func _same(h: Node, context: String) -> bool: return _authorized() == h and _context(h) == context
func _authorized() -> Node:
	var h: Node = get_node_or_null("/root/Horizon")
	return h if h != null and h.auth.isSignedIn() and not h._http.sessionToken.is_empty() and h.auth.getCurrentUser().accessToken == h._http.sessionToken else null
func _store(path: String, intent: Dictionary) -> bool: return Pending.store(path, intent)
func _confirm(path: String, intent: Dictionary) -> bool: return Pending.confirm(path, intent)
func _fail(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
