extends SceneTree
const USER := "00000000-0000-4000-8000-000000001009"
const PEER := "00000000-0000-4000-8000-000000001010"
const REQUEST := "00000000-0000-4000-8000-000000002009"
class ControlledHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	var active: int = 0
	var peak: int = 0
	var on_start: Callable
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse:
		return await _respond(endpoint, {}, session, false)
	func postOnceAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		return await _respond(endpoint, body, session, true)
	func postAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		assert(false, "Friends must never use automatically repeated POST")
		return HorizonNetworkResponse.failure("Wrong transport")
	func _respond(endpoint: String, body: Dictionary, session: bool, once: bool) -> HorizonNetworkResponse:
		assert(session and not responses.is_empty(), "Unexpected policy HTTP")
		calls.append({"endpoint": endpoint, "body": body.duplicate(true), "once": once})
		active += 1
		peak = maxi(peak, active)
		var next: Dictionary = responses.pop_front()
		if on_start.is_valid(): on_start.call()
		await get_tree().create_timer(next.get("delay", .01)).timeout
		active -= 1
		if next.has("failure"):
			var failure := HorizonNetworkResponse.failure("Refused", next.failure)
			failure.serverCode = next.get("code", "")
			return failure
		var response := HorizonNetworkResponse.success(next.data)
		response.rawBody = next.get("raw", JSON.stringify(next.data))
		return response

func _initialize() -> void:
	create_timer(20).timeout.connect(func():
		push_error("Friends policy contract did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	var http := ControlledHttp.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "project"
	http.sessionToken = "session"
	http.activeHost = "https://one.invalid"
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var friends := HorizonFriends.new()
	friends.initialize(http, auth)
	assert(friends._code(USER) == "H-AAAAAAAAQACAAAAAAAAQCQ")
	var codes: Array = []
	friends.friends_failed.connect(func(_error: String, code: String): codes.append(code))
	http.responses = [{"data": _snapshot(friends, 1, 1)}]
	assert((await friends.getFriends(USER)).success)
	var count: int = http.calls.size()
	for revision: Variant in [-1, 1.0, 1.5, "1", true, null, 9007199254740992]:
		assert((await friends.sendRequest(USER, PEER, revision)).errorCode == "INVALID_REQUEST")
	for query: String in ["name-prefix", "user@example.invalid", "H-" + "A".repeat(21) + "B", PEER + "\n"]:
		assert((await friends.findPlayer(USER, query)).errorCode == "INVALID_REQUEST")
	assert((await friends.acceptRequest(USER, PEER, 1, "")).errorCode == "INVALID_REQUEST")
	assert((await friends.cancelRequest(USER, PEER, 1, "1-2-3-4-5")).errorCode == "INVALID_REQUEST")
	assert((await friends.blockPlayer(USER, USER, 1)).errorCode == "INVALID_REQUEST")
	assert((await friends.getFriends(PEER)).errorCode == "SESSION_FORBIDDEN" and http.calls.size() == count)
	# Invalid full responses leave the previous cache and both freshness floors intact.
	var wrong_code: Dictionary = _snapshot(friends, 2, 2)
	wrong_code.friendCode = friends._code(PEER)
	var invalid_badge: Dictionary = _snapshot(friends, 2, 2)
	invalid_badge.friends[0].display.profile.badges = ["invalid badge"]
	var bad_time: Dictionary = _snapshot(friends, 2, 2)
	bad_time.friends[0].lastActiveAt = 0
	var foreign: Dictionary = _snapshot(friends, 2, 2)
	foreign.userId = PEER
	var duplicate: Dictionary = _snapshot(friends, 2, 2)
	duplicate.blocked = [{"userId": PEER, "blockedAt": "2026-10-16T12:00:00Z"}, {"userId": PEER.to_upper(), "blockedAt": "2026-10-16T12:00:00Z"}]
	for invalid: Dictionary in [wrong_code, invalid_badge, bad_time, foreign, duplicate]:
		http.responses = [{"data": invalid}]
		assert((await friends.getFriends(USER)).errorCode == "INVALID_RESPONSE" and friends.getCurrentFriends().revision == 1)
	for wire: String in ['{"revi\\u0073ion":1.0000000000000001}', '{"revision":2,"revi\\u0073ion":2}', '{"maxFriends":2e1}', '{"revision":"2"}', '{"revision":9007199254740992}']:
		http.responses = [{"data": _snapshot(friends, 2, 2), "raw": wire}]
		assert((await friends.getFriends(USER)).errorCode == "INVALID_RESPONSE" and friends.getCurrentFriends().revision == 1)
	# Lookup has only public fields, must match the exact query and never replaces private cache.
	var found: Dictionary = {"userId": PEER, "friendCode": friends._code(PEER), "display": _display(), "blocked": [USER], "email": "private", "lastActiveAt": "2026-10-16T12:00:00Z"}
	found.display.profile["secret"] = "private"
	http.responses = [{"data": found}]
	var result: Dictionary = await friends.findPlayer(USER, PEER.to_upper())
	assert(result.success and result.data.keys().size() == 3 and result.data.display.profile.keys().size() == 3 and friends.getCurrentFriends().revision == 1)
	http.responses = [{"data": found}]
	assert((await friends.findPlayer(USER, friends._code(USER))).errorCode == "INVALID_RESPONSE")
	# The original request ID, including its exact spelling, is preserved; no fresh revision is inferred.
	var original_id: String = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa".to_upper()
	http.responses = [{"failure": 409, "code": "FRIEND_REQUEST_NOT_FOUND"}]
	assert((await friends.acceptRequest(USER, PEER, 4294967296, original_id)).errorCode == "FRIEND_REQUEST_NOT_FOUND")
	assert(http.calls[-1].once and http.calls[-1].body == {"userId": USER, "targetUserId": PEER, "expectedRevision": 4294967296, "requestId": original_id} and friends.getCurrentFriends().is_empty())
	# Read all globally bounded retained friends after downgrade, including crossed requests.
	var retained: Dictionary = _snapshot(friends, 2, 2)
	retained.friends = []
	for index: int in range(21):
		retained.friends.append({"userId": "00000000-0000-4000-8000-%012d" % (index + 5000), "since": "2026-10-16T12:00:00Z", "lastActiveAt": null, "display": _display()})
	retained.incoming = [{"userId": PEER, "requestId": REQUEST, "createdAt": "2026-10-16T12:00:00Z", "display": _display()}]
	retained.outgoing = retained.incoming.duplicate(true)
	http.responses = [{"data": retained}]
	assert((await friends.getFriends(USER)).data.friends.size() == 21 and friends.getCurrentFriends().limits.maxFriends == 20)
	for stale: Dictionary in [_snapshot(friends, 1, 3), _snapshot(friends, 3, 1)]:
		http.responses = [{"data": stale}]
		assert((await friends.getFriends(USER)).errorCode == "STALE_RESPONSE" and friends.getCurrentFriends().revision == 2)
	friends.clearCache()
	http.responses = [{"data": _snapshot(friends, 1, 4)}]
	assert((await friends.getFriends(USER)).errorCode == "STALE_RESPONSE" and friends.getCurrentFriends().is_empty(), "A clear cannot reset the same-player freshness floor")
	# Independent callers serialize, but a queued mutation still uses its reviewed original revision.
	auth.signout_completed.emit()
	http.responses = [{"data": _snapshot(friends, 1, 1), "delay": .12}, {"failure": 409, "code": "REVISION_CONFLICT"}]
	var first: Dictionary = {}
	var second: Dictionary = {}
	_load(friends, first)
	await create_timer(.02).timeout
	_remove(friends, second)
	await create_timer(.18).timeout
	assert(first.result.success and second.result.errorCode == "REVISION_CONFLICT" and http.peak == 1 and http.calls[-1].body.expectedRevision == 0)
	for boundary: String in ["clear", "credentials"]:
		http.responses = [{"data": _snapshot(friends, 2, 2), "delay": .12}, {"data": _snapshot(friends, 3, 3)}]
		first.clear()
		second.clear()
		var starting: int = http.calls.size()
		http.on_start = func():
			if http.calls.size() == starting + 2:
				if boundary == "clear": friends.clearCache()
				else:
					http.sessionToken = "temporary"
					http.sessionToken = "session"
		_load(friends, first)
		await create_timer(.02).timeout
		_load(friends, second)
		await create_timer(.18).timeout
		assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and friends.getCurrentFriends().is_empty())
		http.on_start = Callable()
	for property: String in ["activeHost", "apiKey", "sessionToken"]:
		http.responses = [{"data": _snapshot(friends, 4, 4), "delay": .08}]
		var original: String = http.get(property)
		create_timer(.02).timeout.connect(func():
			http.set(property, original + "-temporary")
			http.set(property, original))
		assert((await friends.getFriends(USER)).errorCode == "STALE_RESPONSE" and friends.getCurrentFriends().is_empty(), "Synchronous context generation fences " + property + " ABA")
	http.responses = [{"data": _snapshot(friends, 4, 4), "delay": .12}]
	first.clear()
	second.clear()
	count = http.calls.size()
	_load(friends, first)
	await create_timer(.02).timeout
	_load(friends, second)
	friends.clearCache()
	await create_timer(.15).timeout
	assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and http.calls.size() == count + 1)
	var on_loaded: Callable = func(_snapshot_value: Dictionary):
		http.sessionToken = "temporary"
		http.sessionToken = "session"
	friends.friends_loaded.connect(on_loaded)
	http.responses = [{"data": _snapshot(friends, 5, 5)}]
	assert((await friends.getFriends(USER)).errorCode == "STALE_RESPONSE" and friends.getCurrentFriends().is_empty(), "Synchronous success handlers cannot return old-session data")
	friends.friends_loaded.disconnect(on_loaded)
	auth.signout_completed.emit()
	assert(friends.getCurrentFriends().is_empty())
	http.sessionToken = ""
	assert((await friends.getFriends(USER)).errorCode == "SESSION_REQUIRED")
	print("Godot Friends policy: explicit safe revisions/request identity, public-only lookup, nullable login, downgrade retention, exact wire lexemes, serialization and callback/queue/context ABA passed")
	http.queue_free()
	quit(0)

func _snapshot(manager: HorizonFriends, revision: int, second: int) -> Dictionary:
	return {"userId": USER, "revision": revision, "friendCode": manager._code(USER), "friends": [{"userId": PEER, "since": "2026-10-16T12:00:00Z", "display": _display(), "lastActiveAt": null}], "incoming": [], "outgoing": [], "blocked": [], "limits": {"maxFriends": 20, "maxIncomingRequests": 20, "maxOutgoingRequests": 20, "maxBlocked": 100}, "serverTime": "2026-10-16T12:00:%02dZ" % second}

func _display() -> Dictionary:
	return {"name": null, "profile": {"avatarId": null, "frameId": null, "badges": []}}

func _load(manager: HorizonFriends, result: Dictionary) -> void:
	result.result = await manager.getFriends(USER)

func _remove(manager: HorizonFriends, result: Dictionary) -> void:
	result.result = await manager.removeFriend(USER, PEER, 0)
