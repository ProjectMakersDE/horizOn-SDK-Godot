## ============================================================
## horizOn SDK - Validated Actions Minimal Example
## ============================================================
## What it does: signs in anonymously, starts a validated run on
## the "default" leaderboard, seeds the game's randomness with the
## server seed, "plays" a short run while recording an input log,
## and submits score and log hash. The server checks the ticket and
## the rules of your API key before it writes the score.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Optional: set rules for your API key in the Dashboard under
## Validated Actions (for example a minimum duration) to see a
## rejection code.
## Expected output: the run ID and seed, then the rank and best
## score of the accepted run, or a clear error line with the error
## code (for example DURATION_TOO_SHORT) on rejection.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals. `code` is the server error code, for example
	# DURATION_TOO_SHORT or TICKET_EXPIRED, or a local code such as SESSION_REQUIRED.
	horizon.validatedActions.run_start_failed.connect(func(error: String, code: String):
		push_error("Starting the run failed [%s]: %s" % [code, error]))
	horizon.validatedActions.run_submit_failed.connect(func(error: String, code: String):
		push_error("The run was not accepted [%s]: %s" % [code, error]))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before starting a validated run.")
		return

	# 1. Get a single-use ticket with a server seed.
	var run: Dictionary = await horizon.validatedActions.startRun("default")
	if run.is_empty():
		return
	print("Run %s started, seed %d, valid for %d s" % [run["runId"], run["seed"], run["expiresInSeconds"]])

	# 2. Seed deterministic randomness and record the inputs of the run.
	var rng := RandomNumberGenerator.new()
	rng.seed = run["seed"]
	var input_log := PackedByteArray()
	var score := 0
	for _step in 20:
		var input := rng.randi_range(0, 3)  # stands in for a player input
		input_log.append(input)
		score += input * 10
	# A real game plays here; the server measures the duration itself.
	await get_tree().create_timer(2.0).timeout

	# 3. Submit: the SDK hashes the log (SHA-256) and sends it with the ticket.
	var result: Dictionary = await horizon.validatedActions.submitValidated(score, input_log)
	if result.is_empty():
		print("Run rejected, error code: %s" % horizon.validatedActions.getLastErrorCode())
		return
	print("Run accepted: score %d, best %d, rank %d, new high score: %s" % [
		result["score"], result["bestScore"], result["rank"], result["isNewHighScore"]])
