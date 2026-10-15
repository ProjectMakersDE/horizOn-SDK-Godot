extends Node
const PendingPurchase = preload("res://addons/horizon_sdk/examples/features/pending_purchase.gd")
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
	var scope: String = horizon.getConfig().api_key + "|" + user_id
	var path: String = "user://horizon_values_pending_" + scope.sha256_text() + ".bin"
	var legacy_paths: Array[String] = []
	var hosts: PackedStringArray = horizon.getConfig().hosts.duplicate()
	if not hosts.has(horizon.getActiveHost()): hosts.append(horizon.getActiveHost())
	for host: String in hosts:
		legacy_paths.append("user://horizon_values_pending_" + (host + "|" + scope).sha256_text() + ".bin")
	var saved: Dictionary = PendingPurchase.load_pending(path, legacy_paths, user_id)
	if not saved.success:
		push_error("Pending purchases need reconciliation; original files retained")
		return
	var pending: Dictionary = saved.pending
	if pending.is_empty():
		pending = {"userId": user_id, "offerKey": "energy-pack", "operationId": values.createOperationId()}
		if not PendingPurchase.store(path, pending): return
	var result: Dictionary = await values.purchase(pending.userId, pending.offerKey, pending.operationId)
	if not result.state.is_empty(): print(result.state.values)
	if result.success:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		push_warning("Purchase [%s]. Original intent retained; never replace an expired operation automatically." % result.errorCode)
