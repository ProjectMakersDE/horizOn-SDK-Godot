## ============================================================
## horizOn SDK - Validated Submit Result Model
## ============================================================
## Result of an accepted validated run
## (POST /api/v1/app/validated-actions/submit). Horizon.validatedActions
## returns it as Dictionary (toDict()); this class is the null safe
## mapping. `state` belongs to Part 2 (TASK-887) and `evidence` to
## Part 3 (TASK-888); both are empty in Part 1.
## ============================================================
class_name HorizonValidatedSubmitResult
extends RefCounted

## Always true on success
var accepted: bool = false

## Run ID
var runId: String = ""

## Board written to ("" for a run without board)
var leaderboardKey: String = ""

## Submitted score (0 for a run without board)
var score: int = 0

## Player's best score on the board after the write (0 without board)
var bestScore: int = 0

## True if this run set a new personal best
var isNewHighScore: bool = false

## 1-based rank after the write (0 without board)
var rank: int = 0

## Server-measured run duration in seconds
var durationSeconds: int = 0

## Server-owned values after the run [Part 2], empty in Part 1
var state: HorizonValidatedPlayerState = HorizonValidatedPlayerState.new()

## Evidence request [Part 3], required = false in Part 1
var evidence: HorizonValidatedEvidenceRequest = HorizonValidatedEvidenceRequest.new()


## Create a result from the JSON response.
## Null safe: null strings become "", null numbers 0, null `state`
## and `evidence` become empty objects. Scores up to 2^53 survive
## Godot's float JSON numbers.
## @param data Response dictionary (may be null)
## @return New result
static func fromDict(data: Variant) -> HorizonValidatedSubmitResult:
	var result := HorizonValidatedSubmitResult.new()
	if not (data is Dictionary):
		return result
	var acceptedValue: Variant = data.get("accepted")
	var runIdValue: Variant = data.get("runId")
	var boardValue: Variant = data.get("leaderboardKey")
	var highScoreValue: Variant = data.get("isNewHighScore")
	result.accepted = acceptedValue if acceptedValue is bool else false
	result.runId = runIdValue if runIdValue is String else ""
	result.leaderboardKey = boardValue if boardValue is String else ""
	result.score = _int(data.get("score"))
	result.bestScore = _int(data.get("bestScore"))
	result.isNewHighScore = highScoreValue if highScoreValue is bool else false
	result.rank = _int(data.get("rank"))
	result.durationSeconds = _int(data.get("durationSeconds"))
	result.state = HorizonValidatedPlayerState.fromDict(data.get("state"))
	result.evidence = HorizonValidatedEvidenceRequest.fromDict(data.get("evidence"))
	return result


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"accepted": accepted,
		"runId": runId,
		"leaderboardKey": leaderboardKey,
		"score": score,
		"bestScore": bestScore,
		"isNewHighScore": isNewHighScore,
		"rank": rank,
		"durationSeconds": durationSeconds,
		"state": state.toDict(),
		"evidence": evidence.toDict()
	}


## Check whether the run was written to a leaderboard.
## @return True if leaderboardKey is not empty
func hasLeaderboard() -> bool:
	return not leaderboardKey.is_empty()


static func _int(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0
