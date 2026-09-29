## ============================================================
## horizOn SDK - Player Profile Minimal Example
## ============================================================
## What it does: signs in anonymously, loads the player profile
## with the cosmetic catalog, picks the first available avatar,
## keeps frame and badges, and saves the profile. Then shows the
## profile on the top leaderboard entries.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Create a few cosmetics (type "avatar") in the Dashboard under
## Player Profile before running.
## Expected output: the catalog, the saved profile, and one line
## per leaderboard entry with its avatar, or a clear error line
## with the error code on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals. `code` is the server error code, for example
	# COSMETIC_LOCKED, or SESSION_REQUIRED when nobody is signed in.
	horizon.playerProfile.profile_load_failed.connect(func(error: String, code: String):
		push_error("Loading the profile failed [%s]: %s" % [code, error]))
	horizon.playerProfile.profile_update_failed.connect(func(error: String, code: String):
		push_error("Saving the profile failed [%s]: %s" % [code, error]))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before using the player profile.")
		return

	# One call returns profile, unlocks and the catalog with an `available` flag.
	var result: Dictionary = await horizon.playerProfile.getProfile()
	if result.is_empty():
		return

	var profile: Dictionary = result["profile"]
	print("Current profile: %s" % JSON.stringify(profile))
	for cosmetic in horizon.playerProfile.getCosmetics("avatar"):
		print("Avatar %s (available: %s)" % [cosmetic["id"], cosmetic["available"]])

	# Pick the first avatar the player may select.
	var avatar_id := ""
	for cosmetic in horizon.playerProfile.getCosmetics("avatar"):
		if cosmetic["available"]:
			avatar_id = cosmetic["id"]
			break
	if avatar_id.is_empty():
		print("No available avatar in the catalog, create one in the Dashboard.")
		return

	# PUT replaces the whole profile: pass the current frame and badges to keep them.
	var updated: Dictionary = await horizon.playerProfile.setProfile(
		avatar_id, profile["frameId"], profile["badges"])
	if updated.is_empty():
		print("Profile not saved, error code: %s" % horizon.playerProfile.getLastErrorCode())
		return
	print("Saved profile: %s" % JSON.stringify(updated["profile"]))

	# Every leaderboard entry carries the player's profile. Unknown IDs mean "not set".
	var entries: Array[HorizonLeaderboardEntry] = await horizon.leaderboard.getTop(5, false)
	for entry in entries:
		var avatar := entry.profile.avatarId if entry.profile.hasAvatar() else "(none)"
		print("#%d %s %d avatar=%s badges=%s" % [entry.position, entry.username, entry.score, avatar, entry.profile.badges])
