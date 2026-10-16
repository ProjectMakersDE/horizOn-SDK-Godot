extends Node
## Explicit world-map/defense actions. Never repeat an uncertain create to discover its ID.
## Server verifies permissions/limits, not game outcomes. Trusted Inbox notice delivery stays backend-only.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_shared_object.gd")
var _usage: Dictionary = {}
var _object: Dictionary = {}
var _recovery: Dictionary = {}
var _defense: Dictionary = {}
var _selection: int = 0
var _busy: bool = false
func clear_review() -> void:
	_selection += 1
	_usage.clear()
	_object.clear()
	_recovery.clear()
func load_collections(after_key: String = "", catalog_revision: Variant = null) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	return await h.sharedObjects.getCollections(h.auth.getCurrentUser().userId, after_key, 50, catalog_revision)
func read_usage(collection: String) -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	clear_review()
	var selection: int = _selection
	var context: String = _context(h)
	var result: Dictionary = await h.sharedObjects.getUsage(_user(h), collection)
	if selection != _selection or not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success: _usage = {"data": result.data.duplicate(true), "context": context}
	return result
func read_marker(collection: String, object_id: String) -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	clear_review()
	var selection: int = _selection
	var context: String = _context(h)
	var result: Dictionary = await h.sharedObjects.getObject(_user(h), collection, object_id)
	if selection != _selection or not _same(h, context): return _fail("STALE_RESPONSE")
	if result.success and result.data.object.ownerId == _user(h): _object = {"data": result.data.object.duplicate(true), "context": context}
	return result
func create_marker(data: PackedByteArray, search: Dictionary, position: Variant = null, group_id: String = "") -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _usage.is_empty() or not _same(h, _usage.context): return _fail("REVIEW_REQUIRED")
	return await _new(h, "create", _usage.data.collection, "", _usage.data.revision, {"dataBase64": HorizonSharedObjectModels.encodeBytes(data), "search": search, "position": position, "groupId": group_id})
func update_reviewed_marker(data: PackedByteArray, search: Dictionary, position: Variant = null) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _object.is_empty() or not _same(h, _object.context): return _fail("REVIEW_REQUIRED")
	return await _new(h, "update", _object.data.collection, _object.data.id, _object.data.revision, {"dataBase64": HorizonSharedObjectModels.encodeBytes(data), "search": search, "position": position, "groupId": _object.data.groupId if _object.data.groupId != null else ""})
## Wire this destructive action only to a distinct explicit confirmation.
func delete_reviewed_marker() -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _object.is_empty() or not _same(h, _object.context): return _fail("REVIEW_REQUIRED")
	return await _new(h, "delete", _object.data.collection, _object.data.id, _object.data.revision, {"groupId": _object.data.groupId if _object.data.groupId != null else ""})
func query_rectangle(collection: String, min_x: int, max_x: int, min_y: int, max_y: int, cursor: String = "", group_id: String = "") -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var query: Dictionary = {"mode": "rectangle", "minX": min_x, "maxX": max_x, "minY": min_y, "maxY": max_y, "limit": 20}
	if not cursor.is_empty(): query.cursor = cursor
	if not group_id.is_empty(): query.groupId = group_id
	return await h.sharedObjects.queryObjects(_user(h), collection, query)
## A defense is ordinary opaque data with an indexed power. This does not validate combat.
func sample_opponents(collection: String, minimum: int, maximum: int) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	return await h.sharedObjects.queryObjects(_user(h), collection, {"mode": "random", "field": "power", "min": minimum, "max": maximum, "limit": 20})
## Cloud-only recipe, invoked after the player selects a defense from sample_opponents.
## The game simulates these frozen bytes using the returned seed and records its input log.
## Its trusted backend separately retains/validates the defense/run binding before any Inbox notice.
func begin_defense_run(defense: Dictionary, leaderboard_key: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	# An explicit SDK discard of a known, never-submitted run is safe. Uncertain sends stay guarded.
	if not _defense.is_empty() and not _defense.run.is_empty() and not _defense.submitted and not h.validatedActions.hasActiveRun() and _same(h, _defense.context): _defense.clear()
	if _busy or not _defense.is_empty() or h.validatedActions.hasActiveRun(): return _fail("PENDING_RUN")
	var row: Dictionary = HorizonSharedObjectModels.object(defense, str(defense.get("collection", "")))
	if row.is_empty() or leaderboard_key.strip_edges().is_empty(): return _fail("INVALID_REQUEST")
	var context: String = _context(h)
	_defense = {"context": context, "object": row.duplicate(true), "run": {}, "submitted": false}
	_busy = true
	var run: Dictionary = await h.validatedActions.startRun(leaderboard_key, {"content_digest": HorizonValidatedActions.computeInputLogHash(row.data), "initial_state": row.data})
	_busy = false
	if not _same(h, context): return _fail("STALE_RESPONSE")
	if run.is_empty():
		var code: String = h.validatedActions.getLastErrorCode()
		if code in ["SESSION_REQUIRED", "SESSION_FORBIDDEN", "PLAYER_NOT_FOUND", "LEADERBOARD_NOT_FOUND", "PLAYER_BANNED", "INITIAL_STATE_TOO_LARGE", "INITIAL_STATE_INVALID_ENCODING", "INVALID_CONTENT_DIGEST", "RUN_RATE_LIMITED", "RUN_CAPACITY_REACHED", "VALIDATED_ACTIONS_UNAVAILABLE", "NOT_SUPPORTED"]: _defense.clear()
		return _fail(code)
	_defense.run = run.duplicate(true)
	return {"success":true,"data":{"defense":row.duplicate(true),"run":run.duplicate(true)},"errorCode":"","error":""}
## Use the game's actual score/log. No fabricated win, earned values or client Inbox delivery.
func submit_defense_run(score: int, input_log: PackedByteArray) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	if _busy or _defense.is_empty() or _defense.run.is_empty() or not _same(h, _defense.context) or h.validatedActions.getCurrentRun().get("runId") != _defense.run.runId: return _fail("RUN_REVIEW_REQUIRED")
	var context: String = _context(h)
	var frozen: Dictionary = _defense.duplicate(true)
	if not HorizonSharedObjectModels.integer(score, -HorizonSharedObjectModels.MAX): return _fail("INVALID_REQUEST")
	_defense.submitted = true
	_busy = true
	var result: Dictionary = await h.validatedActions.submitValidated(score, input_log)
	_busy = false
	if not _same(h, context): return _fail("STALE_RESPONSE")
	if result.is_empty():
		var code: String = h.validatedActions.getLastErrorCode()
		# These known terminal server rejections consume/refuse the original ticket.
		# Unknown/network outcomes retain the binding even if somebody discards the local VA run.
		if code in ["TICKET_INVALID", "TICKET_FOREIGN", "TICKET_EXPIRED", "TICKET_CONSUMED", "STAGE_REQUIRED", "STAGE_UNKNOWN", "SCORE_ABOVE_MAX", "SCORE_BELOW_MIN", "STAGE_SCORE_ABOVE_MAX", "STAGE_SCORE_BELOW_MIN", "DURATION_TOO_SHORT", "SCORE_RATE_TOO_HIGH", "SCORE_LIMIT_REACHED", "UNKNOWN_VALUE_KEY", "DUPLICATE_VALUE_KEY", "EARNED_ABOVE_MAX", "EARNED_BELOW_MIN", "INSUFFICIENT_BALANCE"]: _defense.clear()
		return _fail(code)
	if not result.get("accepted", false) or result.get("runId") != frozen.run.runId: return _fail("INVALID_RESPONSE")
	_defense.clear()
	# Client-visible information is not authority for a trusted notice or a combat result.
	return {"success":true,"data":{"defenseId":frozen.object.id,"defenderId":frozen.object.ownerId,"defenseRevision":frozen.object.revision,"defenseDigest":HorizonValidatedActions.computeInputLogHash(frozen.object.data),"validatedResult":result},"errorCode":"","error":""}
func _new(h: Node, kind: String, collection: String, id: String, revision: Variant, body: Dictionary) -> Dictionary:
	if _busy: return _fail("BUSY")
	var loaded: Dictionary = _load(h)
	if not loaded.success: return loaded
	if not loaded.pending.is_empty(): return _fail("PENDING_ACTION")
	var intent: Dictionary = {"userId": _user(h), "project": h._http.apiKey.sha256_text(), "collection": collection, "kind": kind, "objectId": id, "expectedRevision": revision, "bodyJson": HorizonSharedObjectModels.encode(body)}
	if not _valid(intent, h): return _fail("INVALID_REQUEST")
	var context: String = _context(h)
	var selection: int = _selection
	if not _store(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
	if not _same(h, context) or selection != _selection: return _fail("STALE_RESPONSE")
	_busy = true
	var frozen: Dictionary = HorizonSharedObjectModels.parse(intent.bodyJson)
	var result: Dictionary
	match kind:
		"create": result = await h.sharedObjects.createObject(intent.userId, collection, revision, Marshalls.base64_to_raw(frozen.dataBase64), frozen.search, frozen.position, frozen.groupId)
		"update": result = await h.sharedObjects.updateObject(intent.userId, collection, id, revision, Marshalls.base64_to_raw(frozen.dataBase64), frozen.search, frozen.position)
		_: result = await h.sharedObjects.deleteObject(intent.userId, collection, id, revision)
	_busy = false
	if not _same(h, context) or selection != _selection: return _fail("STALE_RESPONSE")
	if result.success:
		if not _confirm(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
		clear_review()
		if result.data.has("object"): _object = {"data": result.data.object.duplicate(true), "context": context}
	return result # Every error retains the complete original intent. No write retry method exists.

## Explicit owner recovery pages. Even after restart this performs only GET/query POST reads.
func inspect_pending(cursor: String = "") -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = _load(h)
	if not loaded.success or loaded.pending.is_empty(): return loaded if not loaded.success else _fail("NO_PENDING_ACTION")
	var intent: Dictionary = loaded.pending
	var selected: int = _selection
	var context: String = _context(h)
	if cursor.is_empty():
		_recovery.clear()
	elif _recovery.is_empty() or _recovery.get("nextCursor") != cursor or _recovery.intent != intent or _recovery.context != context: return _fail("REVIEW_REQUIRED")
	_busy = true
	var usage: Dictionary = await h.sharedObjects.getRecoveryUsage(_user(h), intent.collection)
	if not usage.success: _busy = false; return usage
	if not _same(h, context) or selected != _selection: _busy = false; return _fail("STALE_RESPONSE")
	if not cursor.is_empty() and usage.data.revision != _recovery.usage.revision: _busy = false; return _fail("RECONCILIATION_CHANGED")
	var body: Dictionary = HorizonSharedObjectModels.parse(intent.bodyJson)
	var query: Dictionary = {"mode": "owner", "ownerId": _user(h), "limit": 50}
	if not cursor.is_empty(): query.cursor = cursor
	if not body.groupId.is_empty(): query.groupId = body.groupId
	var page: Dictionary = await h.sharedObjects.queryRecoveryObjects(_user(h), intent.collection, query)
	if not page.success: _busy = false; return page
	if not _same(h, context) or selected != _selection: _busy = false; return _fail("STALE_RESPONSE")
	var final_usage: Dictionary = await h.sharedObjects.getRecoveryUsage(_user(h), intent.collection)
	_busy = false
	if not _same(h, context) or selected != _selection: return _fail("STALE_RESPONSE")
	if not final_usage.success: return final_usage
	if final_usage.data.revision != usage.data.revision: return _fail("RECONCILIATION_CHANGED")
	var rows: Array = [] if cursor.is_empty() else _recovery.objects.duplicate(true)
	rows.append_array(page.data.objects)
	if rows.size() > 100: return _fail("INVALID_RESPONSE")
	_recovery = {"intent": intent.duplicate(true), "context": context, "usage": final_usage.data.duplicate(true), "objects": rows, "nextCursor": page.data.nextCursor, "complete": page.data.nextCursor == null}
	return {"success": true, "data": _recovery_view(), "errorCode": "", "error": ""}
## Call only after rendering the complete recovered owner state and an explicit player decision.
## A monotone changed revision fences any still-late old CAS, so this cannot rebook the old create.
func acknowledge_reconciliation() -> Dictionary:
	if _busy: return _fail("BUSY")
	var h: Node = _authorized()
	if h == null: return _fail("SESSION_REQUIRED")
	var loaded: Dictionary = _load(h)
	if not loaded.success or loaded.pending.is_empty() or _recovery.is_empty() or not _recovery.complete or loaded.pending != _recovery.intent or not _same(h, _recovery.context): return _fail("REVIEW_REQUIRED")
	var intent: Dictionary = loaded.pending
	if intent.kind == "create":
		if _recovery.usage.revision <= intent.expectedRevision: return _fail("UNCONFIRMED_ACTION")
	else:
		for row: Dictionary in _recovery.objects:
			if row.id == intent.objectId and (intent.kind == "delete" or row.revision <= intent.expectedRevision): return _fail("UNCONFIRMED_ACTION")
	var result: Dictionary = _recovery_view()
	if not _confirm(_path(h), intent): return _fail("PENDING_STORAGE_ERROR")
	clear_review()
	_usage = {"data": result.usage.duplicate(true), "context": _context(h)}
	return {"success": true, "data": result, "errorCode": "", "error": ""}
func _recovery_view() -> Dictionary:
	return {"intent": _recovery.intent.duplicate(true), "usage": _recovery.usage.duplicate(true), "objects": _recovery.objects.duplicate(true), "nextCursor": _recovery.nextCursor, "complete": _recovery.complete}
func _valid(intent: Variant, h: Node) -> bool:
	if not intent is Dictionary or intent.size() != 7 or intent.get("userId") != _user(h) or intent.get("project") != h._http.apiKey.sha256_text() or not HorizonSharedObjectModels.key(intent.get("collection")) or intent.get("kind") not in ["create", "update", "delete"] or not HorizonSharedObjectModels.integer(intent.get("expectedRevision")) or not intent.get("bodyJson") is String: return false
	if (intent.kind == "create" and intent.get("objectId") != "") or (intent.kind != "create" and not HorizonSharedObjectModels.uuid(intent.get("objectId"))): return false
	var body: Dictionary = HorizonSharedObjectModels.parse(intent.bodyJson)
	if body.size() != (1 if intent.kind == "delete" else 4) or not body.get("groupId") is String or (not body.groupId.is_empty() and not HorizonSharedObjectModels.uuid(body.groupId)): return false
	if intent.kind == "delete": return true
	return HorizonSharedObjectModels.search(body.get("search")) and HorizonSharedObjectModels.position(body.get("position")) and HorizonSharedObjectModels.decodeBytes(body.get("dataBase64")) is PackedByteArray
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
