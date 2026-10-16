extends Node
## Connect this script's functions to explicit UI actions. There is no timer or auto-claim.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_inbox_claim.gd")

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

## A new intent requires the exact claimable entry in the current authorized snapshot.
## An uncertain original remains retryable even if that entry is now claimed or absent.
func claim_selected_entry(entry_id: String) -> Dictionary:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not horizon.auth.isSignedIn():
		return _failure("SESSION_REQUIRED")
	if horizon._http.sessionToken.is_empty() or horizon.auth.getCurrentUser().accessToken != horizon._http.sessionToken:
		return _failure("SESSION_REQUIRED")
	var user_id: String = horizon.auth.getCurrentUser().userId
	var project: String = horizon._http.apiKey
	var loaded: Dictionary = Pending.load_pending(project, user_id)
	if not loaded.success:
		return _failure("PENDING_STORAGE_ERROR")
	var pending: Dictionary = loaded.pending
	if not pending.is_empty() and pending.entryId != entry_id:
		return _failure("PENDING_CLAIM")
	if pending.is_empty():
		var snapshot: Dictionary = horizon.inbox.getCurrentInbox()
		if not _claimable(snapshot, user_id, entry_id):
			return _failure("ENTRY_NOT_CLAIMABLE")
		pending = {"userId": user_id, "entryId": entry_id}
		if not Pending.store(project, pending):
			return _failure("PENDING_STORAGE_ERROR")
	# Persisted original ID exists before the first HTTP call. Never pick another on timeout.
	var context_generation: int = horizon._http.getContextGeneration()
	var result: Dictionary = await horizon.inbox.claim(user_id, pending.entryId)
	# Claim-completion signals are synchronous and may change credentials before returning here.
	if horizon._http.getContextGeneration() != context_generation or not horizon.auth.isSignedIn() or horizon.auth.getCurrentUser().userId != user_id or horizon._http.apiKey != project or horizon.auth.getCurrentUser().accessToken != horizon._http.sessionToken:
		return _failure("STALE_RESPONSE")
	if result.success:
		if result.data.get("entryId") != pending.entryId:
			return _failure("INVALID_RESPONSE")
		if not Pending.confirm(project, pending):
			return _failure("PENDING_STORAGE_ERROR")
		# SDK replaced Player Values with the authoritative state. Never add attachment amounts.
		print(result.data.playerValues.values)
	return result

func _claimable(snapshot: Dictionary, user_id: String, entry_id: String) -> bool:
	if snapshot.get("userId") != user_id or not snapshot.get("entries") is Array:
		return false
	for entry: Variant in snapshot.entries:
		if entry is Dictionary and entry.get("id") == entry_id and typeof(entry.get("claimed")) == TYPE_BOOL and not entry.claimed:
			var attachment: Variant = entry.get("attachment")
			return attachment is Dictionary and attachment.get("values") is Array and not attachment.values.is_empty()
	return false

func _failure(code: String) -> Dictionary:
	return {"success": false, "data": {}, "errorCode": code, "error": code}
