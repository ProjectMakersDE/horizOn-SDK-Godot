extends Node
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
## Configure kills(sum) and best_score(max) in the Dashboard.
## One simulated completed session. Uncertain original intent survives restart/host changes.

func _ready() -> void:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Enable the horizOn SDK plugin and import configuration"); return
	if not await horizon.connect_to_server(): return
	var project: String = horizon.getConfig().api_key
	if not await _authenticate(horizon, project): return
	var stats: HorizonStatistics = horizon.statistics
	stats.statistics_failed.connect(func(message: String, code: String): push_warning("Statistics [%s]: %s" % [code,message]))
	var snapshot: Dictionary = await stats.getStatistics()
	if snapshot.is_empty() or horizon.getConfig().api_key != project or horizon._http.apiKey != project: return
	var loaded: Dictionary = Pending.load_pending(project, snapshot.userId)
	if not loaded.success:
		push_error("Legacy/unreadable pending statistics need reconciliation; original files retained"); return
	var pending: Dictionary = loaded.pending
	if pending.is_empty():
		pending = {"userId": snapshot.userId, "operationId": stats.createOperationId(),
			"updates": [{"key": "kills", "value": 3}, {"key": "best_score", "value": 250}]}
		if not Pending.store(project, pending):
			push_error("Cannot persist original statistics intent before sending"); return
	var result: Dictionary = await stats.updateStatistics(pending.updates, pending.operationId)
	if result.is_empty():
		push_warning("Original batch retained. Inspect snapshot/status and retry that ID; do not invent another.")
		return
	if not Pending.confirm(project, pending):
		push_warning("Confirmed statistics intent retained because cleanup failed")
	for value: Dictionary in result.values:
		print("%s=%d (set=%s)" % [value.key,value.value,value.hasValue])

func _authenticate(horizon: Node, project: String) -> bool:
	if horizon.auth.isSignedIn(): return Pending.mark_identity(project)
	# Read cache errors and unusable tokens without treating them as absence of identity.
	var cache := ConfigFile.new()
	var loaded := cache.load("user://horizon_cache.cfg")
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		push_error("Identity cache needs reconciliation; no replacement guest created"); return false
	if cache.has_section_key("cache", HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN):
		if not Pending.mark_identity(project): return false
		var token: Variant = cache.get_value("cache", HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN)
		if not token is String or token.is_empty() or token.length() > 32: return false
		return await horizon.auth.signInAnonymous(token)
	var marker := Pending.identity_marker(project)
	if FileAccess.file_exists(marker) or FileAccess.file_exists(marker + ".next"):
		push_error("An identity may already exist; recover it before creating another guest"); return false
	# A lost signup response cannot silently create another account on the next launch.
	if not Pending.reserve_signup(project): return false
	return await horizon.auth.signUpAnonymous("StatisticsPlayer")
