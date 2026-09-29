## ============================================================
## horizOn SDK - Validated Player State Model
## ============================================================
## Server-owned values of a player (Validated Actions Part 2,
## TASK-887). Part 1 servers send `state: null` in every submit
## result, which maps to an empty state (day "", no values).
## Part 2 adds getState() on Horizon.validatedActions and may
## extend this model.
## ============================================================
class_name HorizonValidatedPlayerState
extends RefCounted

## UTC day of the daily counters ("2026-09-29"), "" when empty
var day: String = ""

## One dictionary per value, sorted by key as sent by the server:
## {key: String, balance: int, earnedToday: int, dailyCap: int (0 = none),
##  requested: int, credited: int} (requested / credited only in submit
## results, 0 otherwise)
var values: Array[Dictionary] = []


## Create a state from the JSON object.
## Null safe: null gives an empty state, null numbers become 0.
## @param data State dictionary (may be null)
## @return New state
static func fromDict(data: Variant) -> HorizonValidatedPlayerState:
	var state := HorizonValidatedPlayerState.new()
	if not (data is Dictionary):
		return state
	var dayValue: Variant = data.get("day")
	state.day = dayValue if dayValue is String else ""
	var rawValues: Variant = data.get("values")
	if rawValues is Array:
		for entry in rawValues:
			if entry is Dictionary:
				var key: Variant = entry.get("key")
				state.values.append({
					"key": key if key is String else "",
					"balance": _int(entry.get("balance")),
					"earnedToday": _int(entry.get("earnedToday")),
					"dailyCap": _int(entry.get("dailyCap")),
					"requested": _int(entry.get("requested")),
					"credited": _int(entry.get("credited"))
				})
	return state


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	var valueList: Array = []
	for value in values:
		valueList.append(value.duplicate())
	return {"day": day, "values": valueList}


## Check whether the state carries no values (always true in Part 1).
## @return True if there are no values
func isEmpty() -> bool:
	return values.is_empty()


## Balance of one value key.
## @param key Value key (e.g. "gold")
## @return The balance, 0 when the key is not listed
func getBalance(key: String) -> int:
	for value in values:
		if value.get("key", "") == key:
			return int(value.get("balance", 0))
	return 0


static func _int(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	return 0
