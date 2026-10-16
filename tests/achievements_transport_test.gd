extends SceneTree
const USER := "00000000-0000-4000-8000-000000001008"
const ENTRY := "message:00000000-0000-4000-8000-000000001008"
class InboxProbe extends HorizonInbox:
	var invalidations: int = 0
	func clearCache() -> void: invalidations += 1

func _initialize() -> void:
	create_timer(20).timeout.connect(func():
		push_error("Achievement HTTP contract did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	var http := HorizonHttpClient.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "achievement-key"
	http.sessionToken = "achievement-session"
	http.activeHost = "http://127.0.0.1:20108"
	http.maxRetryAttempts = 1
	http.retryDelaySeconds = .02
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var inbox := InboxProbe.new()
	var statistics := HorizonStatistics.new()
	statistics.initialize(http, logger, auth)
	var achievements := HorizonAchievements.new()
	achievements.initialize(http, auth, inbox, statistics)
	var notified: Dictionary = {"keys": []}
	achievements.achievements_unlocked.connect(func(keys: Array): notified.keys.append_array(keys))
	var result: Dictionary = await achievements.getAchievements(USER)
	assert(result.success and result.data.definitions.size() == 1 and result.data.progress.is_empty(), "Locked hidden metadata is absent")
	assert(result.data.definitions[0].condition.threshold == 4294967296 and typeof(result.data.definitions[0].condition.threshold) == TYPE_INT)
	result.data.definitions[0].name = "caller mutation"
	assert(achievements.getCurrentAchievements().definitions[0].name == "first_steps")
	result = await achievements.getAchievements(USER)
	assert(result.success and result.data.definitions.size() == 1, "Matching null metadata materializes the retained player cache")
	result = await achievements.unlock(USER, "manual_hidden")
	assert(result.success and not result.data.replayed and result.data.newlyUnlocked == ["manual_hidden"] and notified.keys == ["manual_hidden"])
	assert(result.data.achievements.definitions.size() == 2 and result.data.achievements.progress[0].pendingReward.values[0].amount == 13)
	assert(result.data.deliveryResults[0].code == "INBOX_FULL" and inbox.invalidations == 0, "Full Inbox remains pending and does not invent a local grant")
	result = await achievements.unlock(USER, "manual_hidden")
	assert(result.success and result.data.replayed and result.data.newlyUnlocked.is_empty() and notified.keys.size() == 1)
	result = await achievements.getAchievements(USER)
	assert(result.success and result.data.definitions[1].rewards.values[0].amount == 99 and result.data.progress[0].pendingReward.values[0].amount == 13, "Catalogue edits cannot replace the original pending reward")
	result = await achievements.deliverRewards(USER, ["manual_hidden"])
	assert(result.success and result.data.results[0].state == "delivered" and result.data.achievements.progress[0].inboxEntryId == ENTRY and result.data.achievements.progress[0].pendingReward == null and inbox.invalidations == 1)
	result = await achievements.deliverRewards(USER, ["manual_hidden"])
	assert(result.success and result.data.results[0].inboxEntryId == ENTRY and inbox.invalidations == 2, "Repeated drain uses the same server-owned source and entry")
	result = await achievements.getAchievements(USER)
	assert(result.success and result.data.definitions.is_empty() and result.data.progress[0].key == "manual_hidden", "Empty definitions replace old metadata but permanent progress remains")
	result = await achievements.getAchievements(USER)
	assert(not result.success and result.errorCode == "INVALID_RESPONSE" and achievements.getCurrentAchievements().definitions.is_empty(), "Fractional wire threshold cannot be rounded into valid metadata")
	create_timer(.04).timeout.connect(func():
		http.sessionToken = "temporary"
		http.sessionToken = "achievement-session")
	result = await achievements.getAchievements(USER)
	assert(not result.success and result.errorCode == "STALE_RESPONSE" and achievements.getCurrentAchievements().is_empty(), "Credential ABA fences an old response without observing the intermediate state")
	result = await achievements.unlock(USER, "manual_hidden")
	assert(result.success and result.data.replayed and notified.keys.size() == 1 and inbox.invalidations == 3, "Uncertain HTTP retry retains the permanent original key and emits no duplicate unlock")
	statistics.statistics_updated.emit({"newlyUnlocked": ["first_steps"], "replayed": false})
	assert(achievements.getCurrentAchievements().is_empty(), "Accepted statistic unlock invalidates metadata without fetching or granting")
	assert((await achievements.getAchievements("other-player")).errorCode == "SESSION_FORBIDDEN")
	assert((await achievements.getAchievements(USER, "bad-version")).errorCode == "INVALID_REQUEST")
	assert((await achievements.deliverRewards(USER, [])).errorCode == "INVALID_REQUEST")
	assert((await achievements.deliverRewards(USER, ["manual_hidden", "manual_hidden"])).errorCode == "INVALID_REQUEST")
	assert((await achievements.unlock(USER, "invalid key")).errorCode == "INVALID_REQUEST")
	await create_timer(1.8).timeout
	print("Godot Achievements: 12 real HTTP requests, typed int64, hidden/version cache, original pending reward, partial handoff, replay and scope fences passed")
	http.queue_free()
	quit(0)
