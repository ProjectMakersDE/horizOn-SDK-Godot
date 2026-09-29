## ============================================================
## horizOn SDK - Server-Owned Player State Minimal Example
## ============================================================
## What it does: signs in anonymously, loads the player's
## server-owned values (getState), plays an unbound validated run
## that earns 25 "gold", reads `requested` and `credited` from the
## result, and mirrors the values into the cloud save as a display
## copy. The server is the only source of truth for the balance.
## App key: imported via Project > Tools > horizOn: Import Config.
## Dashboard setup (required): in Validated Actions, add a value
## "gold" to the rules of your API key, for example maxPerRun 100
## and dailyCap 500. Without it the run fails with
## UNKNOWN_VALUE_KEY.
## Start path: attach this script to a Node and run the scene.
## Expected output: the gold balance before the run, then
## "requested 25, credited 25" and the new balance (credited is
## lower once the daily cap is reached), or a clear error line
## with the error code.
## ============================================================
extends Node

## Where the display copy lives inside the cloud save object
const MIRROR_KEY := "serverValues"


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	var validated: HorizonValidatedActions = horizon.validatedActions
	validated.state_load_failed.connect(func(error: String, code: String):
		push_error("Loading the player state failed [%s]: %s" % [code, error]))
	validated.run_submit_failed.connect(func(error: String, code: String):
		push_error("The run was not accepted [%s]: %s" % [code, error]))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return
	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before reading the player state.")
		return

	# 1. On start: read the server state and overwrite the local copy with it.
	var state: Dictionary = await validated.getState()
	if state.is_empty():
		return
	print("Gold before the run: %d" % validated.getBalance("gold"))
	await _mirrorToCloudSave(horizon, state)

	# 2. Play a run and send what it earned. Only an accepted validated run
	# changes a balance; there is no call that sets one.
	var run: Dictionary = await validated.startRun()
	if run.is_empty():
		return
	var input_log := "collected:25".to_utf8_buffer()
	await get_tree().create_timer(2.0).timeout  # a real game plays here
	var result: Dictionary = await validated.submitValidated(0, input_log, "", "", [
		{"key": "gold", "amount": 25}
	])
	if result.is_empty():
		print("Run rejected, error code: %s" % validated.getLastErrorCode())
		return

	# 3. `credited` may be lower than `requested` (daily cap or maximum balance).
	# For a spend (negative amount) grant the item only when it is credited in full.
	var run_state := HorizonValidatedPlayerState.fromDict(result["state"])
	var gold := run_state.getValue("gold")
	print("Gold: requested %d, credited %d, balance %d (today %d of %d)" % [
		gold.get("requested", 0), gold.get("credited", 0), gold.get("balance", 0),
		gold.get("earnedToday", 0), gold.get("dailyCap", 0)])

	# 4. After every accepted run: copy the values into the save (display and offline start).
	await _mirrorToCloudSave(horizon, validated.getCurrentState())


## Store the server values inside the cloud save object as a read-only copy.
## Never send a value from this copy back as a balance: balances change only
## through `earned` of a validated run, and getState() overwrites the copy.
func _mirrorToCloudSave(horizon: Node, state: Dictionary) -> void:
	var save: Dictionary = await horizon.cloudSave.loadObject()
	var mirror := {}
	for value in state.get("values", []):
		mirror[value["key"]] = value["balance"]
	save[MIRROR_KEY] = {"day": state.get("day", ""), "balances": mirror}
	if await horizon.cloudSave.saveObject(save):
		print("Cloud save mirror updated: %s" % str(mirror))
