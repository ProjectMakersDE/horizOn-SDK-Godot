## ============================================================
## horizOn SDK - Validated Run Model
## ============================================================
## A started validated run (POST /api/v1/app/validated-actions/runs):
## the single-use ticket plus the server seed the game uses for its
## deterministic randomness. Horizon.validatedActions returns it as
## Dictionary (toDict()); this class is the null safe mapping.
## ============================================================
class_name HorizonValidatedRun
extends RefCounted

## Run ID (ticket ID)
var runId: String = ""

## Opaque ticket token, sent back unchanged with the submit
var ticket: String = ""

## Server seed for the run (0 to 2,147,483,646)
var seed: int = 0

## Board the ticket is bound to ("" = unbound)
var leaderboardKey: String = ""

## Issue time, ISO 8601 UTC ("2026-09-29T14:00:00.120Z")
var issuedAt: String = ""

## Expiry time, ISO 8601 UTC
var expiresAt: String = ""

## Lifetime at issue in seconds
var expiresInSeconds: int = 0


## Create a run from the JSON response.
## Null safe: a missing dictionary gives an empty run, null strings
## become "" and numbers (parsed as float by Godot) become int.
## @param data Response dictionary (may be null)
## @return New run
static func fromDict(data: Variant) -> HorizonValidatedRun:
	var run := HorizonValidatedRun.new()
	if not (data is Dictionary):
		return run
	run.runId = _string(data.get("runId"))
	run.ticket = _string(data.get("ticket"))
	run.seed = _int(data.get("seed"))
	run.leaderboardKey = _string(data.get("leaderboardKey"))
	run.issuedAt = _string(data.get("issuedAt"))
	run.expiresAt = _string(data.get("expiresAt"))
	run.expiresInSeconds = _int(data.get("expiresInSeconds"))
	return run


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"runId": runId,
		"ticket": ticket,
		"seed": seed,
		"leaderboardKey": leaderboardKey,
		"issuedAt": issuedAt,
		"expiresAt": expiresAt,
		"expiresInSeconds": expiresInSeconds
	}


## Check whether the run carries a ticket.
## @return True if ticket is not empty
func hasTicket() -> bool:
	return not ticket.is_empty()


static func _string(value: Variant) -> String:
	return value if value is String else ""


static func _int(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0
