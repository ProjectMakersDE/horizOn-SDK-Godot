extends Node
## Configure kills(sum) and best_score(max) in the project's Dashboard.
## Reports one simulated completed session and persists an uncertain batch/ID across restarts.

func _ready() -> void:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Enable the horizOn SDK plugin and import configuration"); return
	if not await horizon.connect_to_server(): return
	if not horizon.auth.isSignedIn():
		if horizon.auth.hasCachedAnonymousToken():
			if not await horizon.auth.restoreAnonymousSession():
				push_error("Restore failed; saved identity and pending statistics retained")
				return
		elif not await horizon.auth.signUpAnonymous("StatisticsPlayer"):
			return
	var stats: HorizonStatistics = horizon.statistics
	stats.statistics_failed.connect(func(message: String, code: String): push_warning("Statistics [%s]: %s" % [code,message]))
	var snapshot: Dictionary = await stats.getStatistics()
	if snapshot.is_empty(): return
	# Binary Variant storage preserves int64. JSON.parse_string would load JSON integers as floats.
	var path: String = "user://horizon_statistics_pending_" + str(snapshot["userId"]).sha256_text().substr(0,24) + ".bin"
	var pending: Dictionary = {}
	if FileAccess.file_exists(path):
		var saved: FileAccess = FileAccess.open(path,FileAccess.READ)
		if saved == null: push_error("Cannot read pending statistics batch"); return
		var stored: Variant = saved.get_var(false)
		saved.close()
		if not stored is Dictionary or stored.get("userId") != snapshot["userId"]:
			push_error("Pending statistics need reconciliation; file retained"); return
		pending = stored
	else:
		pending = {"userId":snapshot["userId"],"operationId":stats.createOperationId(),
			"updates":[{"key":"kills","value":3},{"key":"best_score","value":250}]}
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		if file == null: push_error("Cannot persist original statistics intent before sending"); return
		file.store_var(pending,false)
		file.flush()
		var error: Error = file.get_error()
		file.close()
		if error != OK: push_error("Statistics intent could not be saved"); return
	var result: Dictionary = await stats.updateStatistics(pending["updates"],pending["operationId"])
	if result.is_empty():
		push_warning("Original batch retained. Inspect snapshot/status and retry that ID; do not invent another.")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for value: Dictionary in result["values"]:
		print("%s=%d (set=%s)" % [value["key"],value["value"],value["hasValue"]])
