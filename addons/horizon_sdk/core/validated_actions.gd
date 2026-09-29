## ============================================================
## horizOn SDK - Validated Actions Manager
## ============================================================
## Server-checked runs. startRun() gets a single-use ticket with a
## server seed; the game seeds its deterministic randomness with it
## and records an input log. submitValidated() sends the score and
## the SHA-256 of the log; the server checks ticket and the rules of
## the API key before it writes anything. All calls need a player
## session (Authorization: Bearer).
##
## Part 1 (TASK-883): run lifecycle, hash helper, error codes.
## Part 2 (TASK-887) adds getState() and the `state` of submit
## results, Part 3 (TASK-888) adds uploadEvidence() and the
## automatic upload in _afterAccepted(). See the "PART 2" and
## "PART 3" markers below.
## ============================================================
class_name HorizonValidatedActions
extends RefCounted

## Signals (Part 1)
signal run_started(run: Dictionary)
signal run_start_failed(error: String, code: String)
signal run_submitted(result: Dictionary)
signal run_submit_failed(error: String, code: String)

## Endpoints
const ENDPOINT_RUNS := "/api/v1/app/validated-actions/runs"
const ENDPOINT_SUBMIT := "/api/v1/app/validated-actions/submit"

## Length of a SHA-256 hex digest
const INPUT_LOG_HASH_LENGTH := 64
const HEX_DIGITS := "0123456789abcdefABCDEF"

## Local error codes (no request is sent)
const ERROR_SESSION_REQUIRED := "SESSION_REQUIRED"
const ERROR_NO_ACTIVE_RUN := "NO_ACTIVE_RUN"
const ERROR_INVALID_INPUT_LOG_HASH := "INVALID_INPUT_LOG_HASH"
## A 404 without `code`: the backend has no Validated Actions (e.g. simpleServer)
const ERROR_NOT_SUPPORTED := "NOT_SUPPORTED"

## Server error codes (`code` of the error body), Part 1
const ERROR_SESSION_FORBIDDEN := "SESSION_FORBIDDEN"
const ERROR_PLAYER_NOT_FOUND := "PLAYER_NOT_FOUND"
const ERROR_LEADERBOARD_NOT_FOUND := "LEADERBOARD_NOT_FOUND"
const ERROR_SCORE_REQUIRED := "SCORE_REQUIRED"
const ERROR_PLAYER_NAME_REQUIRED := "PLAYER_NAME_REQUIRED"
const ERROR_TICKET_INVALID := "TICKET_INVALID"
const ERROR_TICKET_EXPIRED := "TICKET_EXPIRED"
const ERROR_TICKET_FOREIGN := "TICKET_FOREIGN"
const ERROR_TICKET_CONSUMED := "TICKET_CONSUMED"
const ERROR_LEADERBOARD_MISMATCH := "LEADERBOARD_MISMATCH"
const ERROR_STAGE_REQUIRED := "STAGE_REQUIRED"
const ERROR_STAGE_UNKNOWN := "STAGE_UNKNOWN"
const ERROR_SCORE_ABOVE_MAX := "SCORE_ABOVE_MAX"
const ERROR_SCORE_BELOW_MIN := "SCORE_BELOW_MIN"
const ERROR_STAGE_SCORE_ABOVE_MAX := "STAGE_SCORE_ABOVE_MAX"
const ERROR_STAGE_SCORE_BELOW_MIN := "STAGE_SCORE_BELOW_MIN"
const ERROR_DURATION_TOO_SHORT := "DURATION_TOO_SHORT"
const ERROR_SCORE_RATE_TOO_HIGH := "SCORE_RATE_TOO_HIGH"
const ERROR_SCORE_LIMIT_REACHED := "SCORE_LIMIT_REACHED"
const ERROR_RUN_RATE_LIMITED := "RUN_RATE_LIMITED"
const ERROR_RUN_CAPACITY_REACHED := "RUN_CAPACITY_REACHED"
const ERROR_VALIDATED_ACTIONS_UNAVAILABLE := "VALIDATED_ACTIONS_UNAVAILABLE"
## Normal leaderboard submit to a "validated only" board (see HorizonLeaderboard)
const ERROR_VALIDATED_SUBMIT_REQUIRED := "VALIDATED_SUBMIT_REQUIRED"

## Used from Part 3 on: upload the input log right away when a submit
## result requests evidence and the log bytes are known.
var auto_upload_evidence: bool = true

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth
var _leaderboard: HorizonLeaderboard

## State
var _currentRun: Dictionary = {}
var _currentRunUserId: String = ""
var _lastErrorCode: String = ""


## Initialize the validated actions manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth

	# A ticket belongs to one player: drop it on sign-out and when another player signs in.
	_auth.signout_completed.connect(discardRun)
	_auth.signin_completed.connect(_onPlayerChanged)
	_auth.signup_completed.connect(_onPlayerChanged)

	_logger.info("Validated actions manager initialized")


## Set the leaderboard manager whose cache is cleared after an accepted run with a board.
## @param leaderboard Leaderboard manager instance
func setLeaderboard(leaderboard: HorizonLeaderboard) -> void:
	_leaderboard = leaderboard


# ===== PART 1: RUN LIFECYCLE =====

## Start a validated run and keep it as the current run.
## Sends POST /api/v1/app/validated-actions/runs.
## Seed the game's randomness with run["seed"] and record the input log.
## @param leaderboard_key Board to bind the ticket to, "" for an unbound run
## @return The run (runId, ticket, seed, leaderboardKey, issuedAt, expiresAt,
##         expiresInSeconds), or {} on failure (then getLastErrorCode() is set)
func startRun(leaderboard_key: String = "") -> Dictionary:
	if not _hasSession():
		return _fail("User must be signed in to start a validated run", ERROR_SESSION_REQUIRED, false)

	var user := _auth.getCurrentUser()
	var request := {"userId": user.userId}
	var boardKey := leaderboard_key.strip_edges()
	if not boardKey.is_empty():
		request["leaderboardKey"] = boardKey

	var response := await _http.postAsync(ENDPOINT_RUNS, request, true)

	if response.isSuccess and response.data is Dictionary:
		var run := HorizonValidatedRun.fromDict(response.data).toDict()
		_currentRun = run.duplicate(true)
		_currentRunUserId = user.userId
		_lastErrorCode = ""
		_logger.info("Validated run started: %s" % run["runId"])
		run_started.emit(run)
		return run

	return _fail(_errorMessage(response, "Failed to start validated run"), _errorCodeOf(response), false)


## Submit the result of the current run. Hashes the input log (SHA-256)
## and sends POST /api/v1/app/validated-actions/submit with the current ticket.
## @param score Score of the run (ignored by the server for a run without board)
## @param input_log Raw input log bytes of the run
## @param stage Stage key for stage rules, "" for none
## @param leaderboard_key Target board, "" to use the ticket's board
## @param earned [Part 2] Array of {"key": String, "amount": int}; Part 1 servers ignore it
## @return The result (accepted, runId, leaderboardKey, score, bestScore,
##         isNewHighScore, rank, durationSeconds, state, evidence), or {} on failure
func submitValidated(score: int, input_log: PackedByteArray, stage: String = "", leaderboard_key: String = "", earned: Array = []) -> Dictionary:
	# Session and run are checked before hashing so the local codes win.
	var precheck := _submitPrecheck()
	if not precheck.is_empty():
		return _fail(precheck["message"], precheck["code"], true)
	return await _submit(score, computeInputLogHash(input_log), stage, leaderboard_key, earned, input_log, true)


## Submit the result of the current run with a ready SHA-256 hash of the input log.
## @param score Score of the run (ignored by the server for a run without board)
## @param input_log_hash SHA-256 of the input log, 64 hex characters
## @param stage Stage key for stage rules, "" for none
## @param leaderboard_key Target board, "" to use the ticket's board
## @param earned [Part 2] Array of {"key": String, "amount": int}; Part 1 servers ignore it
## @return The result (same shape as submitValidated()), or {} on failure
func submitValidatedWithHash(score: int, input_log_hash: String, stage: String = "", leaderboard_key: String = "", earned: Array = []) -> Dictionary:
	var precheck := _submitPrecheck()
	if not precheck.is_empty():
		return _fail(precheck["message"], precheck["code"], true)
	var logHash := input_log_hash.strip_edges()
	if not _isValidHash(logHash):
		return _fail("The input log hash must be 64 hex characters (SHA-256)", ERROR_INVALID_INPUT_LOG_HASH, true)
	return await _submit(score, logHash.to_lower(), stage, leaderboard_key, earned, PackedByteArray(), false)


## SHA-256 of the raw input log bytes as 64 lower case hex characters.
## The same bytes must be uploaded later when the server requests evidence.
## @param input_log Raw input log bytes
## @return Hex digest
static func computeInputLogHash(input_log: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	# HashingContext.update() rejects an empty chunk; an empty log hashes to the empty digest.
	if not input_log.is_empty():
		context.update(input_log)
	return context.finish().hex_encode()


## The current run ({} when none). Cleared after a final submit, by
## discardRun(), on sign-out and when another player signs in.
## @return A copy of the run dictionary
func getCurrentRun() -> Dictionary:
	return _currentRun.duplicate(true)


## Check whether a run is waiting for its submit.
## An expired run still counts; the server decides (TICKET_EXPIRED).
## @return True if a current run exists
func hasActiveRun() -> bool:
	return not _currentRun.is_empty()


## Error code of the last failure: the server `code` (e.g. "DURATION_TOO_SHORT"),
## a local code ("SESSION_REQUIRED", "NO_ACTIVE_RUN", "INVALID_INPUT_LOG_HASH"),
## "NOT_SUPPORTED" for a backend without Validated Actions, or the SDK error
## name derived from the HTTP status when the server sent no code
## (e.g. "API_RATE_LIMITED", "NETWORK_ERROR").
## @return The code, or "" after a successful call
func getLastErrorCode() -> String:
	return _lastErrorCode


## Drop the current run without submitting it (the ticket expires on the server).
func discardRun() -> void:
	if not _currentRun.is_empty():
		_logger.debug("Validated run discarded: %s" % _currentRun.get("runId", ""))
	_currentRun = {}
	_currentRunUserId = ""


# ===== PART 2: SERVER-OWNED STATE (TASK-887) =====
# getState(), signals state_loaded / state_load_failed. Submit results
# already carry `state` (HorizonValidatedPlayerState, empty in Part 1).


# ===== PART 3: EVIDENCE (TASK-888) =====
# uploadEvidence(run_id, input_log), signals evidence_uploaded /
# evidence_upload_failed. The automatic upload belongs in _afterAccepted().


# ===== INTERNAL =====

func _onPlayerChanged(user: HorizonUserData) -> void:
	if _currentRun.is_empty():
		return
	if user == null or user.userId != _currentRunUserId:
		discardRun()


## A call needs a signed-in player and a transport session token.
func _hasSession() -> bool:
	return _auth.isSignedIn() and not _http.sessionToken.is_empty()


## Local checks of both submit variants.
## @return {} when the submit may be sent, else {"message", "code"}
func _submitPrecheck() -> Dictionary:
	if not _hasSession():
		return {"message": "User must be signed in to submit a validated run", "code": ERROR_SESSION_REQUIRED}
	if _currentRun.is_empty() or String(_currentRun.get("ticket", "")).is_empty():
		return {"message": "No active run, call startRun() first", "code": ERROR_NO_ACTIVE_RUN}
	return {}


## Exactly 64 hex characters, upper or lower case, no prefix or sign.
func _isValidHash(log_hash: String) -> bool:
	if log_hash.length() != INPUT_LOG_HASH_LENGTH:
		return false
	for character in log_hash:
		if not HEX_DIGITS.contains(character):
			return false
	return true


## Send the submit and apply the ticket lifecycle.
## @param input_log Raw log bytes (empty when has_log is false), kept for Part 3
func _submit(score: int, input_log_hash: String, stage: String, leaderboard_key: String, earned: Array, input_log: PackedByteArray, has_log: bool) -> Dictionary:
	var user := _auth.getCurrentUser()
	var sentTicket: String = _currentRun.get("ticket", "")
	var request := {
		"userId": user.userId,
		"ticket": sentTicket,
		"inputLogHash": input_log_hash,
		"score": score
	}
	var stageKey := stage.strip_edges()
	if not stageKey.is_empty():
		request["stage"] = stageKey
	var boardKey := leaderboard_key.strip_edges()
	if not boardKey.is_empty():
		request["leaderboardKey"] = boardKey
	var earnedList := _normalizeEarned(earned)
	if not earnedList.is_empty():
		request["earned"] = earnedList

	var response := await _http.postAsync(ENDPOINT_SUBMIT, request, true)

	if response.isSuccess and response.data is Dictionary:
		# A ticket is single use: the run is over.
		_endRun(sentTicket)
		var result := HorizonValidatedSubmitResult.fromDict(response.data)
		_lastErrorCode = ""
		_afterAccepted(result, input_log, has_log)
		var resultDict := result.toDict()
		_logger.info("Validated run accepted: %s (rank %d)" % [result.runId, result.rank])
		run_submitted.emit(resultDict)
		return resultDict

	if _isFinalRejection(response):
		# The server consumed or refused the ticket for good; a retry cannot succeed.
		_endRun(sentTicket)
	return _fail(_errorMessage(response, "Failed to submit validated run"), _errorCodeOf(response), true)


## Clear the current run if it is still the one whose ticket was sent
## (the game may have started a new run while the submit was in flight).
func _endRun(sent_ticket: String) -> void:
	if _currentRun.get("ticket", "") == sent_ticket:
		discardRun()


## Work after an accepted run: clear the leaderboard cache for a board run.
## PART 3: start the evidence upload here when result.evidence.required,
## has_log and auto_upload_evidence are true.
func _afterAccepted(result: HorizonValidatedSubmitResult, _input_log: PackedByteArray, _has_log: bool) -> void:
	if result.hasLeaderboard() and _leaderboard != null:
		_leaderboard.clearCache()


## A submit failure after which the ticket is used up: every 422 (ticket
## and rule rejections) and 403 SCORE_LIMIT_REACHED. Network errors, 400,
## 401, other 403, 404, 429 and 503 keep the run so the game may retry.
func _isFinalRejection(response: HorizonNetworkResponse) -> bool:
	if response.isSuccess:
		return false
	if response.statusCode == 422:
		return true
	return response.serverCode == ERROR_SCORE_LIMIT_REACHED


## Keep only well formed earned entries: {"key": String, "amount": int}.
func _normalizeEarned(earned: Array) -> Array:
	var result: Array = []
	for entry in earned:
		if entry is Dictionary:
			var key: Variant = entry.get("key")
			var amount: Variant = entry.get("amount")
			if key is String and not key.is_empty() and (amount is int or amount is float):
				result.append({"key": key, "amount": int(amount)})
	return result


## Server `code` when present, otherwise NOT_SUPPORTED for a bare 404,
## otherwise the SDK error name from the HTTP status.
func _errorCodeOf(response: HorizonNetworkResponse) -> String:
	if not response.serverCode.is_empty():
		return response.serverCode
	if response.isSuccess:
		# Success status but a body that is not a JSON object.
		return "INVALID_RESPONSE"
	if response.statusCode == HorizonErrorCodes.HTTP_NOT_FOUND:
		return ERROR_NOT_SUPPORTED
	var key: Variant = HorizonErrorCodes.ErrorCode.find_key(response.errorCode)
	return str(key) if key != null else "UNKNOWN"


func _errorMessage(response: HorizonNetworkResponse, fallback: String) -> String:
	if not response.error.is_empty():
		return response.error
	return fallback


## Record a failure, emit the matching signal and return {}.
func _fail(message: String, code: String, is_submit: bool) -> Dictionary:
	_lastErrorCode = code
	_logger.error("Validated run %s failed [%s]: %s" % ["submit" if is_submit else "start", code, message])
	if is_submit:
		run_submit_failed.emit(message, code)
	else:
		run_start_failed.emit(message, code)
	return {}
