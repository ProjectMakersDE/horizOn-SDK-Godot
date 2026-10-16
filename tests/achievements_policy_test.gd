extends SceneTree
const USER := "00000000-0000-4000-8000-000000001008"
class ControlledHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	var active: int = 0
	var peak: int = 0
	var on_start: Callable
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse:
		return await _respond(endpoint, {}, session)
	func postAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		return await _respond(endpoint, body, session)
	func _respond(endpoint: String, body: Dictionary, session: bool) -> HorizonNetworkResponse:
		calls.append({"endpoint": endpoint, "body": body.duplicate(true), "session": session})
		active += 1
		peak = maxi(active, peak)
		assert(not responses.is_empty(), "Unexpected policy-test HTTP call")
		var next: Dictionary = responses.pop_front()
		if on_start.is_valid(): on_start.call()
		await get_tree().create_timer(next.get("delay", .01)).timeout
		active -= 1
		var response := HorizonNetworkResponse.success(next.data)
		response.rawBody = next.get("raw", JSON.stringify(next.data))
		return response

func _initialize() -> void:
	create_timer(20).timeout.connect(func():
		push_error("Achievement policy contract did not complete")
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
	var achievements := HorizonAchievements.new()
	achievements.initialize(http, auth)
	assert(not HorizonPlayerValues._safeJsonIntegers('{"definitionVersion":"opaque"}'), "Existing PV/Gift numeric-version validation keeps its default")
	http.responses = [{"data": _snapshot(1, "a", 1)}]
	assert((await achievements.getAchievements(USER)).success)
	var wrong_null: Dictionary = _snapshot(2, "b", 2)
	wrong_null.definitions = null
	var missing: Dictionary = _snapshot(2, "a", 2)
	missing.erase("definitions")
	var wrong_progress_version: Dictionary = _snapshot(2, "a", 2)
	wrong_progress_version.definitions = null
	for invalid: Dictionary in [wrong_null, missing, wrong_progress_version]:
		http.responses = [{"data": invalid}]
		assert((await achievements.getAchievements(USER)).errorCode == "INVALID_RESPONSE" and achievements.getCurrentAchievements().revision == 1)
	var bad_outer: Dictionary = _unlock(2, "b", 3)
	bad_outer.newlyUnlocked = ["other"]
	http.responses = [{"data": bad_outer}]
	assert((await achievements.unlock(USER, "manual")).errorCode == "INVALID_RESPONSE" and achievements.getCurrentAchievements().is_empty())
	http.responses = [{"data": _snapshot(1, "a", 2)}]
	assert((await achievements.getAchievements(USER)).success, "An invalid outer response must not advance revision/time floors")
	var duplicate: Dictionary = _snapshot(2, "b", 3)
	duplicate.definitions.append(duplicate.definitions[0].duplicate(true))
	var hidden: Dictionary = _snapshot(2, "b", 3)
	hidden.definitions[0].hidden = true
	var foreign: Dictionary = _snapshot(2, "b", 3)
	foreign.userId = "another-player"
	var unsafe: Dictionary = _snapshot(9007199254740992, "b", 3)
	for invalid: Dictionary in [duplicate, hidden, foreign, unsafe]:
		http.responses = [{"data": invalid}]
		assert((await achievements.getAchievements(USER)).errorCode == "INVALID_RESPONSE" and achievements.getCurrentAchievements().revision == 1)
	for wire: String in ['{"thresho\\u006cd":1.0000000000000001}', '{"revision":2,"revi\\u0073ion":2}', '{"amount":"3"}']:
		# Quoted amounts are also rejected by structure normalization, not by string-token guessing.
		var raw: Dictionary = _snapshot(2, "b", 3)
		if wire.contains('"3"'):
			raw.definitions[0].rewards.values = [{"key": "coins", "amount": "3"}]
		http.responses = [{"data": raw, "raw": wire}]
		assert((await achievements.getAchievements(USER)).errorCode == "INVALID_RESPONSE" and achievements.getCurrentAchievements().revision == 1)
	http.responses = [{"data": _snapshot(10, "c", 10)}]
	assert((await achievements.getAchievements(USER)).success)
	achievements.clearCache()
	for stale: Dictionary in [_snapshot(9, "c", 11), _snapshot(11, "d", 9)]:
		http.responses = [{"data": stale}]
		assert((await achievements.getAchievements(USER)).errorCode == "STALE_RESPONSE" and achievements.getCurrentAchievements().is_empty())
	var without_cache: Dictionary = _snapshot(10, "c", 11)
	without_cache.definitions = null
	http.responses = [{"data": without_cache}]
	assert((await achievements.getAchievements(USER, "c".repeat(64))).errorCode == "INVALID_RESPONSE")
	assert(not http.calls[-1].endpoint.contains("definitionVersion"), "An unowned external version hint cannot authorize null metadata")
	http.responses = [{"data": _snapshot(10, "c", 12)}]
	assert((await achievements.getAchievements(USER)).success)
	# Serialize independent callers; each queued read gets its own current snapshot.
	auth.signout_completed.emit()
	http.responses = [{"data": _snapshot(1, "a", 1), "delay": .12}, {"data": _snapshot(2, "a", 2)}]
	var first: Dictionary = {}
	var second: Dictionary = {}
	_load(achievements, first)
	await create_timer(.02).timeout
	_load(achievements, second)
	await create_timer(.18).timeout
	assert(first.result.success and second.result.success and http.peak == 1 and achievements.getCurrentAchievements().revision == 2)
	http.responses = [{"data": _snapshot(3, "a", 3), "delay": .12}, {"data": _unlock(4, "b", 4)}]
	first.clear()
	second.clear()
	_load(achievements, first)
	await create_timer(.02).timeout
	_unlock_action(achievements, second)
	await create_timer(.18).timeout
	assert(first.result.success and second.result.success and http.peak == 1 and achievements.getCurrentAchievements().revision == 4)
	# Releasing the first waiter synchronously starts the next request before returning.
	# A request-start callback may change credentials or clear cache at exactly that boundary.
	for boundary: String in ["credentials", "clear"]:
		http.responses = [{"data": _snapshot(5, "c", 5), "delay": .12}, {"data": _snapshot(6, "d", 6)}]
		first.clear()
		second.clear()
		var starting: int = http.calls.size()
		http.on_start = func():
			if http.calls.size() == starting + 2:
				if boundary == "clear": achievements.clearCache()
				else:
					http.sessionToken = "temporary"
					http.sessionToken = "session"
		_load(achievements, first)
		await create_timer(.02).timeout
		_load(achievements, second)
		await create_timer(.18).timeout
		assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and achievements.getCurrentAchievements().is_empty(), "Waiter release cannot leak the first old-context success: " + boundary)
		http.on_start = Callable()
	var count: int = http.calls.size()
	http.responses = [{"data": _snapshot(5, "c", 5), "delay": .12}]
	first.clear()
	second.clear()
	_load(achievements, first)
	await create_timer(.02).timeout
	_load(achievements, second)
	achievements.clearCache()
	await create_timer(.15).timeout
	assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and http.calls.size() == count + 1 and achievements.getCurrentAchievements().is_empty())
	for property: String in ["activeHost", "apiKey", "sessionToken"]:
		http.responses = [{"data": _snapshot(6, "d", 6), "delay": .08}]
		var original: String = http.get(property)
		create_timer(.02).timeout.connect(func():
			http.set(property, original + "-temporary")
			http.set(property, original))
		assert((await achievements.getAchievements(USER)).errorCode == "STALE_RESPONSE" and achievements.getCurrentAchievements().is_empty(), "Unobserved context ABA is fenced: " + property)
	http.responses = [{"data": _snapshot(6, "d", 6), "delay": .08}]
	create_timer(.02).timeout.connect(func():
		auth.signout_completed.emit()
		auth.signin_completed.emit(auth.getCurrentUser()))
	assert((await achievements.getAchievements(USER)).errorCode == "STALE_RESPONSE")
	var change_on_success: Callable = func(_snapshot: Dictionary):
		http.sessionToken = "temporary"
		http.sessionToken = "session"
	achievements.achievements_loaded.connect(change_on_success)
	http.responses = [{"data": _snapshot(7, "e", 7)}]
	assert((await achievements.getAchievements(USER)).errorCode == "STALE_RESPONSE" and achievements.getCurrentAchievements().is_empty(), "Synchronous completion handlers cannot return old-session data")
	achievements.achievements_loaded.disconnect(change_on_success)
	count = http.calls.size()
	assert((await achievements.deliverRewards(USER, ["manual", "manual"])).errorCode == "INVALID_REQUEST")
	assert((await achievements.deliverRewards(USER, ["a", "b", "c", "d", "e", "f", "g", "h", "i"])).errorCode == "INVALID_REQUEST")
	assert((await achievements.unlock("other-player", "manual")).errorCode == "SESSION_FORBIDDEN")
	assert(http.calls.size() == count)
	print("Godot Achievements policy: atomic cache admission, hidden metadata, strict wire integers, version ownership, freshness, serialization and context/signal ABA passed")
	http.queue_free()
	quit(0)

func _snapshot(revision: int, version: String, second: int) -> Dictionary:
	return {"userId": USER, "revision": revision, "definitionVersion": version.repeat(64), "definitions": [{"key": "manual", "name": "Manual", "description": "", "imageUrl": null, "hidden": false, "active": true, "mode": "manual", "condition": null, "rewards": {"values": []}}], "progress": [], "limits": {"maxDefinitions": 20, "maxLifetimeKeys": 500}, "serverTime": "2026-10-16T12:00:%02dZ" % second}

func _unlock(revision: int, version: String, second: int) -> Dictionary:
	var snapshot: Dictionary = _snapshot(revision, version, second)
	snapshot.progress = [{"key": "manual", "unlockedAt": "2026-10-16T12:00:00Z", "rewardState": "none", "inboxEntryId": null, "pendingReward": null}]
	return {"achievements": snapshot, "newlyUnlocked": ["manual"], "replayed": false, "deliveryResults": [{"key": "manual", "state": "none", "inboxEntryId": null, "code": null}]}

func _load(manager: HorizonAchievements, result: Dictionary) -> void:
	result.result = await manager.getAchievements(USER)

func _unlock_action(manager: HorizonAchievements, result: Dictionary) -> void:
	result.result = await manager.unlock(USER, "manual")
