## ============================================================
## horizOn SDK - Validated Actions Minimal Example
## ============================================================
## What it does: signs in anonymously, starts a validated run on
## the "default" leaderboard with a run start context (build
## versions, content digest and the initial state of the
## simulation), seeds the game's randomness with the server seed,
## "plays" a short run while recording an input log, and submits
## score and log hash. The server checks the ticket and the rules of
## your API key before it writes the score.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Optional: set rules for your API key in the Dashboard under
## Validated Actions (for example a minimum duration) to see a
## rejection code.
## Expected output: the run ID and seed, then the rank and best
## score of the accepted run and whether it is sus, or a clear error
## line with the error code (for example DURATION_TOO_SHORT) on
## rejection.
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

	# 1. Get a single-use ticket with a server seed. The optional context says
	# what the run starts from; the server binds it to the run and keeps it with
	# a sus run so the run can be replayed with the same build and state.
	# Set the versions once with horizon.validatedActions.default_run_context,
	# or pass a context per run as here.
	var level_data := "level-1:walls=12;coins=40".to_utf8_buffer()
	var context := {
		"game_version": str(ProjectSettings.get_setting("application/config/version", "1.0.0")),
		"content_version": "levels-1",
		"simulation_version": "sim-1",
		"replay_format_version": "inputs-v1",
		# SHA-256 of the content bytes: the input log hash helper works for any bytes.
		"content_digest": HorizonValidatedActions.computeInputLogHash(level_data),
		"initial_state": "hp=100;x=0;y=0".to_utf8_buffer()
	}
	var run: Dictionary = await horizon.validatedActions.startRun("default", context)
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
	print("Run accepted: score %d, best %d, rank %d, new high score: %s, sus: %s" % [
		result["score"], result["bestScore"], result["rank"], result["isNewHighScore"], result["sus"]])
	if result["sus"]:
		# The run counts, but it crossed a soft threshold of your rules. The server
		# keeps it with its start context for a review and requests the input log
		# (result["evidence"]["required"]); the SDK uploads it on its own, just like
		# for a top N record. The reasons stay on the server.
		print("The run was marked sus and is kept for review")
