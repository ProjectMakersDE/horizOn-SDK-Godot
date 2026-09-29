## ============================================================
## horizOn SDK - Validated Actions Evidence Minimal Example
## ============================================================
## What it does: signs in anonymously, plays a validated run on the
## "default" leaderboard and submits it. When the server requests
## the input log as evidence (the run became a top entry or was
## flagged), the log is uploaded so the account can replay the run
## in the Dashboard. Shows both ways:
## 1. submitValidated() with the raw log: the SDK uploads the log on
##    its own (auto_upload_evidence, on by default).
## 2. submitValidatedWithHash() with a ready hash: the game uploads
##    the log itself with uploadEvidence().
## App key: imported via Project > Tools > horizOn: Import Config.
## Dashboard setup (required to see an upload): set the evidence
## count of the "default" leaderboard (`evidenceTopN`) to 10 or
## more. With 0 the server only requests evidence of flagged runs.
## Start path: attach this script to a Node and run the scene.
## Expected output: "Evidence uploaded for run ..." for each run the
## server requested a log for, "No evidence requested" otherwise, or
## a clear error line with the code (for example PLAYER_BANNED when
## the account banned the player from the board, or
## EVIDENCE_EXPIRED after the 24 h window).
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# The upload reports through its own signals; it never changes the submit result.
	horizon.validatedActions.evidence_uploaded.connect(func(run_id: String):
		print("Evidence uploaded for run %s" % run_id))
	horizon.validatedActions.evidence_upload_failed.connect(func(run_id: String, error: String, code: String):
		push_error("Evidence upload for run %s failed [%s]: %s" % [run_id, code, error]))
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

	# 1. Raw log: the SDK uploads it in the background when requested.
	var input_log := await _playRun(horizon)
	if input_log.is_empty():
		return
	var result: Dictionary = await horizon.validatedActions.submitValidated(_scoreOf(input_log), input_log)
	if result.is_empty():
		_printRejection(horizon)
		return
	_printEvidence(result)

	# 2. Ready hash: the game keeps the bytes and uploads them itself.
	input_log = await _playRun(horizon)
	if input_log.is_empty():
		return
	var log_hash := HorizonValidatedActions.computeInputLogHash(input_log)
	result = await horizon.validatedActions.submitValidatedWithHash(_scoreOf(input_log), log_hash)
	if result.is_empty():
		_printRejection(horizon)
		return
	_printEvidence(result)
	var evidence: Dictionary = result["evidence"]
	if evidence["required"]:
		var uploaded: bool = await horizon.validatedActions.uploadEvidence(evidence["runId"], input_log)
		if not uploaded:
			var code: String = horizon.validatedActions.getLastErrorCode()
			if HorizonValidatedActions.isEvidenceRetryable(code):
				# EVIDENCE_HASH_MISMATCH (wrong bytes) or a network error: the
				# request stays open until evidence["uploadBefore"], try again later.
				print("Upload can be retried until %s" % evidence["uploadBefore"])

	# Leave time for the background upload of run 1 before the scene ends.
	await get_tree().create_timer(3.0).timeout


## Start a run, seed the randomness and record 20 inputs.
## @return The input log, empty when the run could not start
func _playRun(horizon: Node) -> PackedByteArray:
	var run: Dictionary = await horizon.validatedActions.startRun("default")
	if run.is_empty():
		push_error("Starting the run failed [%s]" % horizon.validatedActions.getLastErrorCode())
		return PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = run["seed"]
	var input_log := PackedByteArray()
	for _step in 20:
		input_log.append(rng.randi_range(0, 3))  # stands in for a player input
	# A real game plays here; the server measures the duration itself.
	await get_tree().create_timer(2.0).timeout
	return input_log


func _scoreOf(input_log: PackedByteArray) -> int:
	var score := 0
	for input in input_log:
		score += input * 10
	return score


func _printEvidence(result: Dictionary) -> void:
	var evidence: Dictionary = result["evidence"]
	if evidence["required"]:
		print("Run %s: evidence requested until %s (at most %d bytes)" % [result["runId"], evidence["uploadBefore"], evidence["maxBytes"]])
	else:
		print("Run %s accepted, rank %d. No evidence requested." % [result["runId"], result["rank"]])


func _printRejection(horizon: Node) -> void:
	var code: String = horizon.validatedActions.getLastErrorCode()
	if code == "PLAYER_BANNED":
		# Checked before the ticket is used: the run stays until discardRun().
		horizon.validatedActions.discardRun()
		print("The player is banned from this leaderboard.")
	else:
		print("Run rejected, error code: %s" % code)
