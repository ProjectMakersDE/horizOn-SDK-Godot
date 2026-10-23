extends SceneTree

const USER := "00000000-0000-4000-8000-000000001006"
const ENTRY := "broadcast:" + USER

class ControlledHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	var active: int = 0
	var peak: int = 0
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse:
		return await _respond(endpoint, {}, session)
	func postAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		return await _respond(endpoint, body, session)
	func _respond(endpoint: String, body: Dictionary, session: bool) -> HorizonNetworkResponse:
		calls.append({"endpoint": endpoint, "body": body.duplicate(true), "session": session})
		active += 1
		peak = maxi(active, peak)
		var next: Dictionary = responses.pop_front()
		await get_tree().create_timer(next.get("delay", .01)).timeout
		active -= 1
		var response: HorizonNetworkResponse = HorizonNetworkResponse.success(next.data)
		response.rawBody = next.get("raw", JSON.stringify(next.data))
		return response

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if HorizonInbox._safeJson('{"amount":9007199254740991.1}') or HorizonInbox._safeJson('{"revision":9007199254740992}') or not HorizonInbox._safeJson('{"parameters":{"note":"escaped \\\"amount\\\":9007199254740992"},"amount":9007199254740991}'):
		_fail("Number-token validation must reject rounding and ignore string contents"); return
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := ControlledHttp.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project"
	http.activeHost = "https://one.invalid"
	http.sessionToken = "session"
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var values := HorizonPlayerValues.new()
	values.initialize(http, auth)
	var inbox := HorizonInbox.new()
	inbox.initialize(http, auth, values)
	if not _compactContracts(inbox):
		_fail("Compact sources, configurable limits, free text and valuable attachments must validate without losing retained state"); return
	http.responses = [{"data": _snapshot(1, 10), "delay": .12}, {"data": _snapshot(2, 11)}]
	var first: Dictionary = {}
	var followup: Dictionary = {}
	_load(inbox, first)
	await create_timer(.02).timeout
	_load(inbox, followup)
	await create_timer(.2).timeout
	if not first.result.success or not followup.result.success or http.peak != 1 or http.calls.size() != 2 or inbox.getCurrentInbox().revision != 2:
		_fail("Concurrent reads must serialize and perform the needed follow-up GET"); return
	http.responses = [{"data": _snapshot(3, 12), "delay": .1}]
	var cleared: Dictionary = {}
	_load(inbox, cleared)
	await create_timer(.02).timeout
	inbox.clearCache()
	await create_timer(.12).timeout
	if cleared.result.errorCode != "STALE_RESPONSE" or not inbox.getCurrentInbox().is_empty():
		_fail("clearCache must fence in-flight GETs"); return
	for stale: Dictionary in [_snapshot(1, 13), _snapshot(2, 9), _snapshot(3, 13, 0)]:
		http.responses = [{"data": stale}]
		if (await inbox.getInbox(USER)).errorCode != "STALE_RESPONSE":
			_fail("Independent revision/broadcast/time watermarks must survive invalidation"); return
	var invalid: Dictionary = _snapshot(3, 14)
	invalid.unchanged = true
	http.responses = [{"data": invalid}]
	if (await inbox.getInbox(USER, "unknown-cursor")).errorCode != "INVALID_RESPONSE" or http.calls[-1].endpoint.contains("since="):
		_fail("Unknown cursor without a cache must force a full snapshot"); return
	http.responses = [{"data": _snapshot(3, 14), "raw": '{"revision":9007199254740991.1}'}]
	if (await inbox.getInbox(USER)).errorCode != "INVALID_RESPONSE":
		_fail("Unsafe original JSON must be rejected before conversion"); return
	http.responses = [{"data": _snapshot(3, 14)}]
	if not (await inbox.getInbox(USER)).success:
		_fail("Fresh full snapshot must recover"); return
	# An old GET cannot restore pre-mutation state after a queued mutation completes.
	http.responses = [{"data": _snapshot(4, 15), "delay": .1}, {"data": _snapshot(5, 16)}]
	var loading: Dictionary = {}
	var removal: Dictionary = {}
	_load(inbox, loading)
	await create_timer(.02).timeout
	_remove(inbox, removal)
	await create_timer(.15).timeout
	if not loading.result.success or not removal.result.success or inbox.getCurrentInbox().revision != 5 or http.peak != 1:
		_fail("Mutation and GET must serialize without resurrecting older entries"); return
	# Multiple queued player actions and a follow-up refresh must all execute.
	http.responses = [{"data": _snapshot(6, 17), "delay": .1}, {"data": _snapshot(7, 18)}, {"data": _snapshot(8, 19)}, {"data": _snapshot(9, 20)}]
	var chain: Array[Dictionary] = [{}, {}, {}, {}]
	_load(inbox, chain[0])
	await create_timer(.02).timeout
	_read(inbox, chain[1])
	_remove(inbox, chain[2])
	_load(inbox, chain[3])
	await create_timer(.2).timeout
	for action: Dictionary in chain:
		if not action.get("result", {}).get("success", false):
			_fail("A queued mutation must not cancel later queued actions or refreshes"); return
	if inbox.getCurrentInbox().revision != 9 or http.peak != 1:
		_fail("The final queued refresh must supply the current state"); return
	var retained: Dictionary = _snapshot(10, 21)
	retained.limits = {"targeted": 10, "broadcasts": 10}
	for i: int in range(21):
		retained.entries.append(_entry(i))
	http.responses = [{"data": retained}]
	if not (await inbox.getInbox(USER)).success or inbox.getCurrentInbox().entries.size() != 21:
		_fail("Retained valuable messages must remain readable after a plan downgrade"); return
	# Session A -> B -> A and an explicit clear both fence old and queued responses.
	for field: String in ["token", "host", "project", "user"]:
		http.responses = [{"data": _snapshot(6, 17), "delay": .1}]
		var pending: Dictionary = {}
		var queued: Dictionary = {}
		_load(inbox, pending)
		await create_timer(.02).timeout
		_load(inbox, queued)
		var original: String
		match field:
			"token":
				original = http.sessionToken
				http.sessionToken = "changed"
				auth._currentUser.accessToken = "changed"
			"host":
				original = http.activeHost
				http.activeHost = "https://two.invalid"
			"project":
				original = http.apiKey
				http.apiKey = "another-project"
			"user":
				original = auth._currentUser.userId
				auth._currentUser.userId = "another-user"
		if not inbox.getCurrentInbox().is_empty():
			_fail("Changed context must immediately hide cached contents"); return
		match field:
			"token":
				http.sessionToken = original
				auth._currentUser.accessToken = original
			"host": http.activeHost = original
			"project": http.apiKey = original
			"user": auth._currentUser.userId = original
		inbox.getCurrentInbox()
		await create_timer(.12).timeout
		if pending.result.errorCode != "STALE_RESPONSE" or queued.result.errorCode != "STALE_RESPONSE" or not inbox.getCurrentInbox().is_empty():
			_fail("A-B-A context epochs must fence old and queued requests: " + field); return
	# An invalid claim must not alter either cache; old PV state cannot overwrite a newer state.
	var pv: Dictionary = {"userId": USER, "revision": 9, "definitionVersion": 1, "values": [{"key": "coins", "balance": 9, "earnedToday": 0}], "operationWindow": {"serverTime": "2026-10-16T12:00:30Z"}}
	if not values.acceptServerState(USER, pv):
		_fail("Fresh authoritative values should be accepted"); return
	var wrong_claim: Dictionary = {"entryId": ENTRY, "replayed": true, "inbox": _snapshot(7, 31), "playerValues": pv.duplicate(true)}
	wrong_claim.playerValues.revision = 8
	http.responses = [{"data": wrong_claim}]
	if (await inbox.claim(USER, ENTRY)).success or values.getCurrentState().values[0].balance != 9:
		_fail("An older claim must not replace newer Player Values"); return
	auth.signout_completed.emit()
	if not inbox.getCurrentInbox().is_empty():
		_fail("Signout signal must clear snapshots"); return
	print("Godot Inbox serialization, mutation, cursor, watermark, malformed JSON and context-race policy passed")
	http.queue_free()
	quit(0)

func _snapshot(revision: int, second: int, broadcast_revision: int = 1) -> Dictionary:
	return {"userId": USER, "cursor": "cursor-%d-%d" % [revision, second], "revision": revision, "broadcastRevision": broadcast_revision, "serverTime": "2026-10-16T12:00:%02dZ" % second, "pollAfterSeconds": 120, "unchanged": false, "entries": [], "counts": {}, "limits": {"targeted": 50, "broadcasts": 20}}

func _load(inbox: HorizonInbox, result: Dictionary) -> void:
	result.result = await inbox.getInbox(USER)

func _remove(inbox: HorizonInbox, result: Dictionary) -> void:
	result.result = await inbox.remove(USER, ENTRY)

func _read(inbox: HorizonInbox, result: Dictionary) -> void:
	result.result = await inbox.markRead(USER, ENTRY)

func _entry(index: int) -> Dictionary:
	return {"id": "broadcast:00000000-0000-4000-8000-%012d" % index, "kind": "broadcast", "type": "reward", "reference": "", "textKey": "reward", "parameters": {}, "createdAt": "2026-10-15T12:00:00Z", "expiresAt": "2026-10-16T12:00:00Z", "overdue": true, "read": false, "claimed": false, "attachment": {"values": [{"key": "coins", "amount": 1}]}}

func _compactContracts(inbox: HorizonInbox) -> bool:
	var snapshot: Dictionary = _snapshot(9007199254740991, 1)
	snapshot.limits = {"targeted": 1000, "broadcasts": 2000, "freeTexts": 4, "freeTextBytes": 512, "freeTextRetentionDays": 30}
	if inbox._normalize(snapshot, USER, "").get("limits", {}).get("broadcasts") != 2000:
		return false
	snapshot.limits.targeted = 1
	snapshot.limits.broadcasts = 1
	for i: int in range(551):
		snapshot.entries.append(_entry(i))
	if inbox._normalize(snapshot, USER, "").get("entries", []).size() != 551:
		return false
	var entry: Dictionary = _entry(1)
	entry.merge({"id": "message:" + USER, "kind": "message", "type": "free_text", "reference": "", "textKey": "horizon.inbox.free_text", "parameters": {"text": "ä".repeat(256)}, "attachment": null, "createdAt": "2030-01-01T00:00:00Z"}, true)
	snapshot.entries = [entry]
	var normalized: Dictionary = inbox._normalize(snapshot, USER, "")
	if normalized.is_empty() or HorizonInbox.getFreeText(normalized.entries[0]).to_utf8_buffer().size() != 512:
		return false
	var cases: Array = [
		["friend_request", "horizon.friends.request", "userId", HorizonInbox.SourceKind.FRIEND_REQUEST],
		["friend_accept", "horizon.friends.accept", "userId", HorizonInbox.SourceKind.FRIEND_ACCEPTED],
		["group_invite", "horizon.groups.invite", "groupId", HorizonInbox.SourceKind.GROUP_INVITATION],
		["group_request", "horizon.groups.request", "groupId", HorizonInbox.SourceKind.GROUP_REQUEST],
		["group_accept-invite", "horizon.groups.accept-invite", "groupId", HorizonInbox.SourceKind.GROUP_INVITATION_ACCEPTED],
		["group_accept-request", "horizon.groups.accept-request", "groupId", HorizonInbox.SourceKind.GROUP_REQUEST_ACCEPTED],
		["match_turn", "horizon.matches.your_turn", "matchId", HorizonInbox.SourceKind.MATCH_TURN]]
	for case: Array in cases:
		entry.type = case[0]
		entry.textKey = case[1]
		entry.reference = USER
		entry.parameters = {case[2]: USER}
		if case[0] == "match_turn":
			entry.parameters.revision = "9007199254740991"
		if inbox._normalize(snapshot, USER, "").is_empty() or HorizonInbox.getSource(entry).get("kind") != case[3]:
			return false
		entry.reference = "bad"
		if not inbox._normalize(snapshot, USER, "").is_empty():
			return false
	entry.merge({"type": "group_accept-invite", "textKey": "horizon.groups.accept-invite", "reference": "00000000-0000-4000-8000-000000001007", "parameters": {"groupId": USER}}, true)
	if inbox._normalize(snapshot, USER, "").is_empty() or HorizonInbox.getSource(entry).get("groupId") != USER:
		return false
	entry.merge({"type": "marketplace", "textKey": "marketplace.item_return", "reference": USER, "parameters": {}, "attachment": {"values": [], "itemReturn": {"listingId": USER, "instanceId": USER, "itemKey": "sword"}}}, true)
	if inbox._normalize(snapshot, USER, "").is_empty() or not HorizonInbox.canClaim(entry) or HorizonInbox.getSource(entry).get("kind") != HorizonInbox.SourceKind.MARKET_RETURN:
		return false
	for field: String in ["attachment", "itemReturn", "values"]:
		var broken: Dictionary = snapshot.duplicate(true)
		if field == "attachment": broken.entries[0].attachment.unknownReward = 1
		elif field == "itemReturn": broken.entries[0].attachment.itemReturn.unknownReward = 1
		else: broken.entries[0].attachment.values = [{"key": "gold", "amount": 1, "unknownReward": 1}]
		if not inbox._normalize(broken, USER, "").is_empty():
			return false
	return HorizonInbox._validItems([{"instanceId": USER, "itemKey": "sword"}]) and not HorizonInbox._validItems([{"instanceId": "bad", "itemKey": "sword"}])

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
