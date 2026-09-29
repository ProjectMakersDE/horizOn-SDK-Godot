extends SceneTree

const TEST_PORT := 18883
const LOG_HASH := "054a3b937f3f8b4d1d82fe353243cb91288f7975e2190a338e59271f17701375"
## Largest value the server stores (2^53 - 1), exact in Godot's float JSON numbers
const MAX_SAFE_INT := 9007199254740991


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-883"
	http.activeHost = "http://127.0.0.1:%d" % TEST_PORT
	http.sessionToken = "session-token-883"
	# One retry allowed on purpose: a coded 429 must still not be retried.
	http.maxRetryAttempts = 1

	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "user-883"
	auth._currentUser.accessToken = "session-token-883"

	var leaderboard := HorizonLeaderboard.new()
	leaderboard.initialize(http, logger, auth)

	var validated := HorizonValidatedActions.new()
	validated.initialize(http, logger, auth)
	validated.setLeaderboard(leaderboard)

	var input_log := "R1:L2:J3".to_utf8_buffer()

	# Hash helper: SHA-256, 64 lower case hex characters, empty log allowed.
	if HorizonValidatedActions.computeInputLogHash(input_log) != LOG_HASH:
		_fail("computeInputLogHash must return the lower case SHA-256 hex digest")
		return
	if HorizonValidatedActions.computeInputLogHash(PackedByteArray()) != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855":
		_fail("computeInputLogHash of an empty log must be the empty SHA-256 digest")
		return

	# 1. Start a run bound to a board; the run becomes the current run.
	var run := await validated.startRun("weekly")
	if run.is_empty():
		_fail("startRun was rejected by the contract server: %s" % validated.getLastErrorCode())
		return
	if run["seed"] != 1834201177 or not (run["seed"] is int) or run["expiresInSeconds"] != 7200 or run["leaderboardKey"] != "weekly":
		_fail("startRun must map seed and expiresInSeconds to int and keep the board")
		return
	if not validated.hasActiveRun() or validated.getCurrentRun()["ticket"] != "hzn-rt1:2026-09:ticket-one":
		_fail("startRun must keep the run as the current run")
		return

	# 2. Submit with the raw log: hashed, current ticket sent, run cleared, cache dropped.
	leaderboard._cache["weekly_top_10"] = []
	var submitted := {"result": {}}
	validated.run_submitted.connect(func(result: Dictionary): submitted["result"] = result)
	var result := await validated.submitValidated(18250, input_log, "wave_3")
	if result.is_empty():
		_fail("submitValidated was rejected by the contract server: %s" % validated.getLastErrorCode())
		return
	if result["rank"] != 17 or result["bestScore"] != 21000 or result["durationSeconds"] != 734 or result["isNewHighScore"]:
		_fail("submitValidated must map the result fields")
		return
	var state: Dictionary = result["state"]
	var evidence: Dictionary = result["evidence"]
	if state["day"] != "" or not (state["values"] as Array).is_empty() or evidence["required"] or evidence["maxBytes"] != 0:
		_fail("null state and evidence must become empty objects")
		return
	if validated.hasActiveRun() or not leaderboard._cache.is_empty() or submitted["result"].is_empty():
		_fail("an accepted run must clear the current run and the leaderboard cache and emit run_submitted")
		return

	# Local: no current run, no request.
	if not (await validated.submitValidated(1, input_log)).is_empty() or validated.getLastErrorCode() != "NO_ACTIVE_RUN":
		_fail("submit without a run must fail locally with NO_ACTIVE_RUN")
		return

	# 3. + 4. Unbound run, ready hash (upper case accepted, sent lower case), earned
	# sent; 422 rule rejection exposes the code and uses the ticket up.
	run = await validated.startRun()
	if run.is_empty() or run["leaderboardKey"] != "":
		_fail("an unbound run must map leaderboardKey null to \"\"")
		return
	var failed := {"code": ""}
	validated.run_submit_failed.connect(func(_error: String, code: String): failed["code"] = code)
	var rejected := await validated.submitValidatedWithHash(0, "A".repeat(64), "", "", [{"key": "gold", "amount": 250}])
	if not rejected.is_empty() or validated.getLastErrorCode() != "DURATION_TOO_SHORT" or failed["code"] != "DURATION_TOO_SHORT":
		_fail("a 422 DURATION_TOO_SHORT must fail with that code")
		return
	if validated.hasActiveRun():
		_fail("a 422 rejection must clear the current run")
		return

	# 5. Coded 429: failed at once with RUN_RATE_LIMITED, not retried.
	if not (await validated.startRun("weekly")).is_empty() or validated.getLastErrorCode() != "RUN_RATE_LIMITED":
		_fail("a 429 RUN_RATE_LIMITED must fail at once with that code")
		return

	# 6. + 7. A 404 without code means NOT_SUPPORTED and keeps the run.
	run = await validated.startRun("weekly")
	if run.is_empty():
		_fail("startRun after the rate limit was rejected: %s" % validated.getLastErrorCode())
		return
	if not (await validated.submitValidated(500, input_log)).is_empty() or validated.getLastErrorCode() != "NOT_SUPPORTED":
		_fail("a 404 without code must fail with NOT_SUPPORTED")
		return
	if not validated.hasActiveRun():
		_fail("a 404 must keep the current run for a retry")
		return

	# Local: invalid ready hash, no request.
	if not (await validated.submitValidatedWithHash(500, "xyz")).is_empty() or validated.getLastErrorCode() != "INVALID_INPUT_LOG_HASH":
		_fail("a malformed hash must fail locally with INVALID_INPUT_LOG_HASH")
		return
	if not (await validated.submitValidatedWithHash(500, "-" + "a".repeat(63))).is_empty() or validated.getLastErrorCode() != "INVALID_INPUT_LOG_HASH":
		_fail("a signed hash must fail locally with INVALID_INPUT_LOG_HASH")
		return

	# 8. Retry with the same ticket; 403 SCORE_LIMIT_REACHED uses the ticket up.
	if not (await validated.submitValidated(500, input_log)).is_empty() or validated.getLastErrorCode() != "SCORE_LIMIT_REACHED":
		_fail("a 403 SCORE_LIMIT_REACHED must fail with that code")
		return
	if validated.hasActiveRun():
		_fail("403 SCORE_LIMIT_REACHED must clear the current run")
		return

	# 9. Normal submit to a validated only board exposes VALIDATED_SUBMIT_REQUIRED.
	if await leaderboard.submitScore(999, "weekly") or leaderboard.getLastErrorCode() != "VALIDATED_SUBMIT_REQUIRED":
		_fail("submitScore to a validated only board must expose VALIDATED_SUBMIT_REQUIRED")
		return

	# 10. Board list: validatedOnly is always a bool.
	var boards := await leaderboard.listBoards()
	if boards.size() != 2 or boards[0]["validatedOnly"] != true or boards[1]["validatedOnly"] != false:
		_fail("listBoards must expose validatedOnly (false when missing)")
		return

	# 11. to 13. LEADERBOARD_MISMATCH is checked before the ticket is consumed:
	# the run stays and the same ticket is sent again. A ticket code ends it.
	run = await validated.startRun("weekly")
	if run.is_empty():
		_fail("startRun for the mismatch check was rejected: %s" % validated.getLastErrorCode())
		return
	if not (await validated.submitValidated(700, input_log, "", "monthly")).is_empty() or validated.getLastErrorCode() != "LEADERBOARD_MISMATCH":
		_fail("a 422 LEADERBOARD_MISMATCH must fail with that code")
		return
	if not validated.hasActiveRun() or validated.getCurrentRun()["ticket"] != "hzn-rt1:2026-09:ticket-four":
		_fail("LEADERBOARD_MISMATCH must keep the current run (the ticket is not consumed)")
		return
	if not (await validated.submitValidated(700, input_log)).is_empty() or validated.getLastErrorCode() != "TICKET_EXPIRED":
		_fail("a 422 TICKET_EXPIRED must fail with that code")
		return
	if validated.hasActiveRun():
		_fail("a 422 TICKET_EXPIRED must clear the current run")
		return

	# 14. Part 2: getState() reads the server-owned values with the session,
	# maps numbers up to 2^53 - 1 to int and dailyCap null to 0, and caches them.
	var loaded := {"state": {}}
	validated.state_loaded.connect(func(loaded_state: Dictionary): loaded["state"] = loaded_state)
	var player_values := await validated.getState()
	if player_values.is_empty():
		_fail("getState was rejected by the contract server: %s" % validated.getLastErrorCode())
		return
	var gems: Dictionary = player_values["values"][1]
	if player_values["userId"] != "user-883" or player_values["day"] != "2026-09-29" or (player_values["values"] as Array).size() != 3:
		_fail("getState must map userId, day and every value")
		return
	if gems["key"] != "gems" or not (gems["balance"] is int) or gems["balance"] != MAX_SAFE_INT or gems["dailyCap"] != 0 or gems["requested"] != 0:
		_fail("getState must read 2^53 - 1 as int, dailyCap null as 0 and requested as 0")
		return
	if loaded["state"].is_empty() or not validated.hasCurrentState() or validated.getBalance("gems") != MAX_SAFE_INT or validated.getBalance("gold") != 1250:
		_fail("getState must emit state_loaded and cache the state")
		return

	# 15. + 16. Unbound run with earned: whole float amounts become int, malformed
	# entries are dropped, the result state carries requested and credited.
	run = await validated.startRun()
	if run.is_empty():
		_fail("startRun for the earned run was rejected: %s" % validated.getLastErrorCode())
		return
	var earned_result := await validated.submitValidated(0, input_log, "", "", [
		{"key": "gold", "amount": 250.0},
		{"key": "chest.gold", "amount": -1},
		{"key": "", "amount": 5},
		{"key": "gems", "amount": 1.5},
		"not an entry"
	])
	if earned_result.is_empty():
		_fail("the earned run was rejected by the contract server: %s" % validated.getLastErrorCode())
		return
	var run_state := HorizonValidatedPlayerState.fromDict(earned_result["state"])
	var gold := run_state.getValue("gold")
	if gold["requested"] != 250 or gold["credited"] != 150 or gold["balance"] != 1400 or gold["earnedToday"] != 400 or gold["dailyCap"] != 400:
		_fail("the submit state must carry requested and credited of the touched values")
		return
	if not run_state.isFullyCredited("chest.gold") or run_state.isFullyCredited("gold") or run_state.isFullyCredited("gems"):
		_fail("isFullyCredited must compare credited with requested of touched values only")
		return
	if earned_result["state"]["userId"] != "" or earned_result["leaderboardKey"] != "" or earned_result["rank"] != 0:
		_fail("an unbound submit result must map null board fields and carry no userId in state")
		return
	var cached := validated.getCurrentState()
	if validated.getBalance("gold") != 1400 or validated.getBalance("chest.gold") != 1 or cached["userId"] != "user-883" or cached["values"][2]["requested"] != 0:
		_fail("an accepted run with a state must update the cached state without per-run amounts")
		return

	# 17. + 18. A value rejection (422 INSUFFICIENT_BALANCE) uses the ticket up
	# and leaves the cached state unchanged.
	run = await validated.startRun()
	if run.is_empty():
		_fail("startRun for the spend run was rejected: %s" % validated.getLastErrorCode())
		return
	if not (await validated.submitValidated(0, input_log, "", "", [{"key": "chest.gold", "amount": -5}])).is_empty() or validated.getLastErrorCode() != "INSUFFICIENT_BALANCE":
		_fail("a 422 INSUFFICIENT_BALANCE must fail with that code")
		return
	if validated.hasActiveRun() or validated.getBalance("chest.gold") != 1:
		_fail("a value rejection must clear the run and keep the cached state")
		return

	# 19. + 20. getState errors: server code, and NOT_SUPPORTED for a bare 404.
	var state_failed := {"code": ""}
	validated.state_load_failed.connect(func(_error: String, code: String): state_failed["code"] = code)
	if not (await validated.getState()).is_empty() or validated.getLastErrorCode() != "SESSION_REQUIRED" or state_failed["code"] != "SESSION_REQUIRED":
		_fail("a 401 SESSION_REQUIRED on getState must fail with that code and emit state_load_failed")
		return
	if validated.getBalance("gold") != 1400:
		_fail("a failed getState must keep the cached state")
		return
	if not (await validated.getState()).is_empty() or validated.getLastErrorCode() != "NOT_SUPPORTED":
		_fail("a 404 without code on getState must fail with NOT_SUPPORTED")
		return

	# Player changes drop the run: sign-out, and sign-in of another player.
	validated._currentRun = {"runId": "local", "ticket": "local"}
	validated._currentRunUserId = "user-883"
	var same_user := HorizonUserData.new()
	same_user.userId = "user-883"
	auth.signin_completed.emit(same_user)
	if not validated.hasActiveRun() or not validated.hasCurrentState():
		_fail("a sign-in of the same player must keep the run and the cached state")
		return
	var other_user := HorizonUserData.new()
	other_user.userId = "user-other"
	auth.signin_completed.emit(other_user)
	if validated.hasActiveRun() or validated.hasCurrentState() or not validated.getCurrentState().is_empty():
		_fail("a sign-in of another player must drop the run and the cached state")
		return
	validated._currentRun = {"runId": "local", "ticket": "local"}
	validated._currentState = HorizonValidatedPlayerState.fromDict({"userId": "user-883", "day": "2026-09-29", "values": []})
	auth.signout_completed.emit()
	if validated.hasActiveRun() or validated.hasCurrentState():
		_fail("sign-out must drop the run and the cached state")
		return

	# Local: no session, no request.
	http.sessionToken = ""
	if not (await validated.startRun()).is_empty() or validated.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("startRun without session must fail locally with SESSION_REQUIRED")
		return
	if not (await validated.getState()).is_empty() or validated.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("getState without session must fail locally with SESSION_REQUIRED")
		return
	http.sessionToken = "session-token-883"
	auth._currentUser.clear()
	validated._currentRun = {"runId": "local", "ticket": "local"}
	if not (await validated.submitValidated(1, input_log)).is_empty() or validated.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("submitValidated without a signed-in user must fail locally with SESSION_REQUIRED")
		return

	# Models are null safe.
	var empty_result := HorizonValidatedSubmitResult.fromDict(null)
	if empty_result.accepted or empty_result.state == null or empty_result.evidence == null:
		_fail("an empty submit result must carry empty state and evidence")
		return
	var player_state := HorizonValidatedPlayerState.fromDict({
		"day": "2026-09-29",
		"values": [{"key": "gold", "balance": 1250.0, "earnedToday": 250, "dailyCap": null}]
	})
	if player_state.getBalance("gold") != 1250 or player_state.getBalance("gems") != 0 or player_state.values[0]["dailyCap"] != 0:
		_fail("player state must map numbers to int and null to 0")
		return
	var null_state := HorizonValidatedPlayerState.fromDict(null)
	if null_state.isPresent() or not null_state.isEmpty() or not null_state.getValue("gold").is_empty() or null_state.userId != "":
		_fail("a null player state must be empty and not present")
		return

	# Keep the process alive while the contract server watches for an unexpected extra request.
	await create_timer(1.8).timeout
	print("Godot validated actions transport contract passed")
	http.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
