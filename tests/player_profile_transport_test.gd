extends SceneTree

const TEST_PORT := 18881


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-881"
	http.activeHost = "http://127.0.0.1:%d" % TEST_PORT
	http.sessionToken = "session-token-881"
	http.maxRetryAttempts = 0

	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "user-881"
	auth._currentUser.accessToken = "session-token-881"

	var player_profile := HorizonPlayerProfile.new()
	player_profile.initialize(http, logger, auth)

	var gift_codes := HorizonGiftCodes.new()
	gift_codes.initialize(http, logger, auth)
	gift_codes.setPlayerProfile(player_profile)

	# 1. GET with userId query and Bearer session; null slots become "".
	var loaded := await player_profile.getProfile()
	if loaded.is_empty():
		_fail("getProfile was rejected by the contract server: %s" % player_profile.getLastErrorCode())
		return
	var loaded_profile: Dictionary = loaded.get("profile", {})
	if loaded_profile.get("avatarId") != "" or loaded_profile.get("frameId") != "" or not (loaded_profile.get("badges") as Array).is_empty():
		_fail("getProfile must map null slots to \"\" and []")
		return
	if player_profile.getCosmetics("avatar").size() != 1 or not player_profile.isAvailable("badge.supporter") or player_profile.isAvailable("frame.gold"):
		_fail("getCosmetics / isAvailable do not match the catalog")
		return

	# 2. PUT with the whole profile; the empty frame is sent as a missing slot.
	var updated := await player_profile.setProfile("avatar.zombie_07", "", ["badge.supporter"])
	if updated.is_empty():
		_fail("setProfile was rejected by the contract server: %s" % player_profile.getLastErrorCode())
		return
	if not player_profile.getCurrentProfileData().hasAvatar() or player_profile.getLastErrorCode() != "":
		_fail("setProfile must cache the updated profile and reset the error code")
		return

	# 3. Server error body: the `code` is exposed and the failure signal fires.
	var signalled := {"code": ""}
	player_profile.profile_update_failed.connect(func(_error: String, code: String): signalled["code"] = code)
	var locked := await player_profile.setProfile("", "frame.gold", [])
	if not locked.is_empty() or player_profile.getLastErrorCode() != "COSMETIC_LOCKED" or signalled["code"] != "COSMETIC_LOCKED":
		_fail("a 403 COSMETIC_LOCKED must fail with that code")
		return
	if player_profile.getCurrentProfile().is_empty():
		_fail("a failed setProfile must keep the last successful result")
		return

	# 4. Gift code with grants: grantedUnlocks in the result, profile cache dropped.
	var redeemed := await gift_codes.redeem("SUPPORTER")
	if redeemed.get("grantedUnlocks", []) != ["badge.supporter"]:
		_fail("redeem must return grantedUnlocks")
		return
	if not player_profile.getCurrentProfile().is_empty():
		_fail("redeem with grantedUnlocks must clear the cached player profile")
		return

	# Local pre-checks: none of these may reach the server.
	if not (await player_profile.setProfile("", "", ["a", "b", "c", "d"])).is_empty() or player_profile.getLastErrorCode() != "INVALID_BADGES":
		_fail("more than 3 badges must fail locally with INVALID_BADGES")
		return
	if not (await player_profile.setProfile("", "", ["badge.supporter", "badge.supporter"])).is_empty() or player_profile.getLastErrorCode() != "INVALID_BADGES":
		_fail("a duplicate badge must fail locally with INVALID_BADGES")
		return
	if not (await player_profile.setProfile("Bad ID", "", [])).is_empty() or player_profile.getLastErrorCode() != "INVALID_COSMETIC_ID":
		_fail("an invalid ID must fail locally with INVALID_COSMETIC_ID")
		return

	http.sessionToken = ""
	if not (await player_profile.getProfile()).is_empty() or player_profile.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("getProfile without session must fail locally with SESSION_REQUIRED")
		return
	http.sessionToken = "session-token-881"
	auth._currentUser.clear()
	if not (await player_profile.setProfile("", "", [])).is_empty() or player_profile.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("setProfile without a signed-in user must fail locally with SESSION_REQUIRED")
		return

	# Leaderboard entries carry a null safe profile.
	var entry := HorizonLeaderboardEntry.fromDict({
		"position": 1, "username": "Anon", "score": 10,
		"profile": {"avatarId": null, "frameId": "frame.gold", "badges": null}
	})
	if entry.profile.hasAvatar() or entry.profile.frameId != "frame.gold" or not entry.profile.badges.is_empty():
		_fail("leaderboard entry profile must map null to \"\" and []")
		return
	if HorizonLeaderboardEntry.fromDict({"position": 2}).profile == null:
		_fail("leaderboard entry without profile must get an empty profile")
		return

	# Keep the process alive while the contract server watches for an unexpected extra request.
	await create_timer(1.8).timeout
	print("Godot player profile transport contract passed")
	http.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
