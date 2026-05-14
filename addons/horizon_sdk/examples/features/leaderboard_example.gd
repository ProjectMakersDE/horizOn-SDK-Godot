## ============================================================
## horizOn SDK - Leaderboard Minimal Example
## ============================================================
## What it does: signs in anonymously, submits a score, then reads
## back the top entries and the current player's rank.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Score submitted" line, a short top list, and
## the player's rank, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.leaderboard.score_submit_failed.connect(func(error: String):
		push_error("Score submission failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before using the leaderboard.")
		return

	# Scores are only updated server-side when higher than the previous best.
	var submitted: bool = await horizon.leaderboard.submitScore(1500)
	if not submitted:
		push_error("Score was not submitted.")
		return
	print("Score submitted: 1500")

	# getTop returns an empty array on failure, so an empty result is safe to loop.
	var top: Array[HorizonLeaderboardEntry] = await horizon.leaderboard.getTop(5, false)
	print("Top %d players:" % top.size())
	for entry in top:
		print("  #%d  %s  %d" % [entry.position, entry.username, entry.score])

	var rank: HorizonLeaderboardEntry = await horizon.leaderboard.getRank()
	if rank != null:
		print("Your rank: #%d with score %d" % [rank.position, rank.score])
	else:
		print("Rank not available yet.")
