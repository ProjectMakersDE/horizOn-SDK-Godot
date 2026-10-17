extends Node
## Explicit UI actions after connecting/restoring the original player session.
## Configure first_steps (statistic kills) and manual_hidden (manual, optional coins reward).
## The server atomically credits rewards on unlock. Nothing here grants balances locally.
const InboxSample = preload("res://addons/horizon_sdk/examples/features/inbox_example.gd")
var _claims: Node

func refresh_achievements() -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var result: Dictionary = await horizon.achievements.getAchievements(horizon.auth.getCurrentUser().userId)
	if result.success:
		for progress: Dictionary in result.data.progress:
			print("Achievement %s: %s; original pending reward: %s" % [progress.key, progress.rewardState, progress.pendingReward])
	return result

## Call explicitly after a successful statistics report; no new request on replay/no unlocks.
func refresh_after_statistics(report: Dictionary) -> Dictionary:
	if report.get("newlyUnlocked") is Array and not report.newlyUnlocked.is_empty() and not report.get("replayed", false):
		return await refresh_achievements()
	return {"success": true, "data": {}, "errorCode": "", "error": ""}

func unlock_selected(key: String) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	# Retain this same original key after an uncertain response; never invent another identity.
	var result: Dictionary = await horizon.achievements.unlock(horizon.auth.getCurrentUser().userId, key)
	if result.success:
		print("New unlocks (empty on replay): %s" % result.data.newlyUnlocked)
	return result

func deliver_selected_pending(keys: Array) -> Dictionary:
	# Compatibility status for legacy rewards. New complete unlocks need no delivery or claim.
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var result: Dictionary = await horizon.achievements.deliverRewards(horizon.auth.getCurrentUser().userId, keys)
	if result.success:
		for outcome: Dictionary in result.data.results:
			print("Reward %s: %s (%s)" % [outcome.key, outcome.state, outcome.code])
	# MIGRATION_REQUIRED means the server must safely reconcile an old reward source.
	return result

func refresh_reward_inbox() -> Dictionary:
	return await _claim_example().refresh_inbox()

func claim_delivered_reward(entry_id: String) -> Dictionary:
	# Legacy Inbox rewards only. New achievement rewards were already credited on unlock.
	# First render a fresh authorized Inbox snapshot. The shared example persists the exact
	# claim ID before HTTP and replaces Player Values only with the authoritative full state.
	return await _claim_example().claim_selected_entry(entry_id)

func _claim_example() -> Node:
	if not is_instance_valid(_claims):
		_claims = InboxSample.new()
		add_child(_claims)
	return _claims

func _authorized() -> Node:
	var horizon: Node = get_node_or_null("/root/Horizon")
	return horizon if horizon != null and horizon.auth.isSignedIn() else null

func _failure(code: String) -> Dictionary:
	return {"success": false, "data": {}, "errorCode": code, "error": code}
