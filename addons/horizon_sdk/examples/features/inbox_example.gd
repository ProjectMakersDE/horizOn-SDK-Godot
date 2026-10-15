extends Node
## Connect this script's functions to explicit UI actions. There is no timer or auto-claim.

func refresh_inbox() -> Dictionary:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not horizon.auth.isSignedIn():
		return {}
	var user_id: String = horizon.auth.getCurrentUser().userId
	var cached: Dictionary = horizon.inbox.getCurrentInbox()
	var result: Dictionary = await horizon.inbox.getInbox(user_id, cached.get("cursor", ""))
	if result.success:
		# Render the complete materialized entries, including unchanged responses.
		print("Inbox entries: %d; next permitted lifecycle poll after %ds" % [result.data.entries.size(), result.data.pollAfterSeconds])
	return result

## Persist the selected entry before invoking this action. On an uncertain response, call
## again with that same entry ID. The server owns the recipient, reward and replay guard.
func claim_selected_entry(entry_id: String) -> Dictionary:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not horizon.auth.isSignedIn():
		return {}
	var result: Dictionary = await horizon.inbox.claim(horizon.auth.getCurrentUser().userId, entry_id)
	if result.success:
		# SDK replaced Player Values with the authoritative state. Never add attachment amounts.
		print(result.data.playerValues.values)
	return result
