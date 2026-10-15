extends Node
## Configure an energy-pack offer in the Dashboard. This example purchases once per new intent.
## A lost response keeps the original operation ID and immutable payload in user://.
func _ready() -> void:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not await horizon.connect_to_server(): return
	if not horizon.auth.isSignedIn():
		if horizon.auth.hasCachedAnonymousToken():
			if not await horizon.auth.restoreAnonymousSession():
				push_error("Restore failed; saved identity and pending purchase retained")
				return
		elif not await horizon.auth.signUpAnonymous("ValuesPlayer"): return
	var user_id: String = horizon.auth.getCurrentUser().userId
	var values: HorizonPlayerValues = horizon.playerValues
	var loaded: Dictionary = await values.getState(user_id)
	if not loaded.success: return
	var scope: String = horizon.getActiveHost() + "|" + horizon.getConfig().api_key + "|" + user_id
	var path: String = "user://horizon_values_pending_" + scope.sha256_text() + ".bin"
	var pending: Dictionary
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return
		var saved: Variant = file.get_var(false)
		file.close()
		if not saved is Dictionary or saved.get("userId") != user_id or not saved.get("operationId") is String or not saved.get("offerKey") is String:
			push_error("Pending purchase needs reconciliation; file retained")
			return
		pending = saved
	else:
		pending = {"userId": user_id, "offerKey": "energy-pack", "operationId": values.createOperationId()}
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return
		file.store_var(pending, false)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK: return
	var result: Dictionary = await values.purchase(pending.userId, pending.offerKey, pending.operationId)
	if not result.state.is_empty(): print(result.state.values)
	if result.success:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		push_warning("Purchase [%s]. Original intent retained; never replace an expired operation automatically." % result.errorCode)
