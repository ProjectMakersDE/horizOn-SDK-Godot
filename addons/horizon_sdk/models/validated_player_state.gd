## ============================================================
## horizOn SDK - Validated Player State Model
## ============================================================
## Server-owned values of a player (Validated Actions Part 2,
## TASK-887): currency, loot and other int64 counters that only
## accepted validated runs change. Returned by
## Horizon.validatedActions.getState() (GET .../state) and inside
## every accepted submit result (`state`).
##
## A submit `state` of null (the rules define no values, or a
## Part 1 server) maps to an empty state (day "", no values).
## All numbers are at most 9,007,199,254,740,991 (2^53 - 1), so
## Godot's float JSON numbers convert to int without loss.
## ============================================================
class_name HorizonValidatedPlayerState
extends RefCounted

## Per-run fields, present only for values touched by a submit
const RUN_FIELDS: Array[String] = ["requested", "credited"]

## Player the state belongs to. Only GET .../state sends it, "" in submit results
var userId: String = ""

## UTC day of the daily counters ("2026-09-29"), "" when empty
var day: String = ""

## One dictionary per value, sorted by key as sent by the server:
## {key: String, balance: int, earnedToday: int, dailyCap: int (0 = none)}
## plus `requested` (amount sent in `earned`) and `credited` (amount applied)
## as int, only for values touched by the run of a submit result. The server
## omits both everywhere else (GET .../state, untouched values), and so does
## this model: the keys are absent, not 0. credited < requested for a positive amount means the
## daily cap or the maximum balance clamped it. A spend is either credited
## in full or 0: grant a purchase only when credited == requested.
var values: Array[Dictionary] = []


## Create a state from the JSON object.
## Null safe: null gives an empty state, null numbers (e.g. `dailyCap`
## without a cap) become 0. Omitted or null `requested` / `credited` stay absent.
## @param data State dictionary (may be null)
## @return New state
static func fromDict(data: Variant) -> HorizonValidatedPlayerState:
	var state := HorizonValidatedPlayerState.new()
	if not (data is Dictionary):
		return state
	var userIdValue: Variant = data.get("userId")
	state.userId = userIdValue if userIdValue is String else ""
	var dayValue: Variant = data.get("day")
	state.day = dayValue if dayValue is String else ""
	var rawValues: Variant = data.get("values")
	if rawValues is Array:
		for entry in rawValues:
			if entry is Dictionary:
				var key: Variant = entry.get("key")
				var value := {
					"key": key if key is String else "",
					"balance": _int(entry.get("balance")),
					"earnedToday": _int(entry.get("earnedToday")),
					"dailyCap": _int(entry.get("dailyCap"))
				}
				for runField in RUN_FIELDS:
					if _isNumber(entry.get(runField)):
						value[runField] = int(entry.get(runField))
				state.values.append(value)
	return state


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	var valueList: Array = []
	for value in values:
		valueList.append(value.duplicate())
	return {"userId": userId, "day": day, "values": valueList}


## Check whether the state carries no values (a null state, or rules without values).
## @return True if there are no values
func isEmpty() -> bool:
	return values.is_empty()


## Check whether the server sent a state object at all (every sent state has a day).
## False for a submit result with `state: null`.
## @return True if day is set
func isPresent() -> bool:
	return not day.is_empty()


## One value by key.
## @param key Value key (e.g. "gold")
## @return A copy of the value dictionary, {} when the key is not listed
func getValue(key: String) -> Dictionary:
	for value in values:
		if value.get("key", "") == key:
			return value.duplicate()
	return {}


## Balance of one value key.
## @param key Value key (e.g. "gold")
## @return The balance, 0 when the key is not listed
func getBalance(key: String) -> int:
	return int(getValue(key).get("balance", 0))


## Check whether the run of a submit result applied the full requested amount
## of a key (credited == requested). Use it before granting a purchase.
## @param key Value key (e.g. "gold")
## @return False when the key was not touched by the run or was clamped
func isFullyCredited(key: String) -> bool:
	var value := getValue(key)
	if not value.has("requested") or int(value["requested"]) == 0:
		return false
	return int(value.get("credited", 0)) == int(value["requested"])


## Copy without the per-run amounts (no requested and credited keys),
## the shape of GET .../state. Used for the cached current state.
## @param user_id Player to set when the state carries none
## @return New state
func withoutRunAmounts(user_id: String = "") -> HorizonValidatedPlayerState:
	var copy := HorizonValidatedPlayerState.new()
	copy.userId = userId if not userId.is_empty() else user_id
	copy.day = day
	for value in values:
		var entry: Dictionary = value.duplicate()
		for runField in RUN_FIELDS:
			entry.erase(runField)
		copy.values.append(entry)
	return copy


static func _int(value: Variant) -> int:
	if _isNumber(value):
		return int(value)
	return 0


static func _isNumber(value: Variant) -> bool:
	return value is int or value is float
