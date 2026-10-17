extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var logger: HorizonLogger = HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http: HorizonHttpClient = HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-statistics"
	http.activeHost = "http://127.0.0.1:18805"
	http.sessionToken = "statistics-session"
	http.maxRetryAttempts = 0
	var auth: HorizonAuth = HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "statistics-user"
	auth._currentUser.accessToken = "statistics-session"
	var stats: HorizonStatistics = HorizonStatistics.new()
	stats.initialize(http, logger, auth)
	var first: Dictionary = await stats.getStatistics()
	if first.is_empty() or first["values"][0]["value"] != -9007199254740991 or typeof(first["values"][0]["value"]) != TYPE_INT:
		_fail("Snapshot must preserve the exact safe negative integer"); return
	var second: Dictionary = await stats.getStatistics()
	if second.is_empty() or stats.getCurrentDefinitions().size() != 1:
		_fail("Unchanged catalog must fold from cache"); return
	var operation: String = stats.createOperationId()
	var batch: Array = [{"key":"kills", "value":9007199254740991}]
	var applied: Dictionary = await stats.updateStatistics(batch, operation)
	if applied.is_empty() or applied.get("operationId") != operation:
		_fail("Explicit ID and exact safe integer batch rejected: " + stats.getLastErrorCode()); return
	var replay: Dictionary = await stats.updateStatistics(batch, operation)
	if not replay.get("replayed",false) or replay.get("revision") != 3:
		_fail("Same ID must replay without increment"); return
	var conflict: Dictionary = await stats.updateStatistics([{"key":"kills","value":1}], operation)
	if not conflict.is_empty() or stats.getLastErrorCode() != "OPERATION_CONFLICT" or stats.getLastSubmittedOperationId() != operation:
		_fail("Conflicting payload must expose code and retain original ID"); return
	if (await stats.getDefinitions()).is_empty() or not stats.getCurrentStatistics().is_empty():
		_fail("New catalog must invalidate the old projection"); return
	if not (await stats.getStatistics()).is_empty() or stats.getLastErrorCode() != "STATE_CONFLICT":
		_fail("Revision watermark must survive catalog invalidation"); return
	if (await stats.getStatistics()).is_empty():
		_fail("New UTC bucket snapshot rejected"); return
	if not (await stats.getStatistics()).is_empty() or stats.getCurrentStatistics()["values"][0]["value"] != 3:
		_fail("Delayed older UTC projection must not replace equal revision"); return
	var cleared: Dictionary = {"done":false,"value":{}}
	_loadAsync(stats, cleared)
	await create_timer(.08).timeout
	stats.clearCache()
	await create_timer(.3).timeout
	if not cleared["done"] or not cleared["value"].is_empty() or not stats.getCurrentStatistics().is_empty():
		_fail("Cache epoch must reject old conditional response"); return
	if (await stats.getStatistics()).is_empty():
		_fail("Full catalog reload after clear must recover"); return
	var old: Dictionary = {"done":false,"value":{}}
	_loadAsync(stats,old)
	await create_timer(.08).timeout
	http.sessionToken="fresh-session"
	auth._currentUser.accessToken="fresh-session"
	if not stats.getCurrentStatistics().is_empty():
		_fail("Session change must clear cache"); return
	if (await stats.getStatistics()).is_empty():
		_fail("Fresh session snapshot rejected"); return
	await create_timer(.45).timeout
	if not old["done"] or not old["value"].is_empty() or stats.getCurrentStatistics()["values"][0]["value"] != 9:
		_fail("Late old-session response must preserve fresh cache"); return
	http.maxRetryAttempts = 1
	http.retryDelaySeconds = .15
	var retry: Dictionary = {"done":false,"value":{}}
	var retry_batch: Array = [{"key":"kills","value":9007199254740991}]
	_updateAsync(stats, retry_batch, stats.createOperationId(), retry)
	await create_timer(.06).timeout
	retry_batch[0]["value"] = 1
	await create_timer(.25).timeout
	if not retry["done"] or retry["value"].is_empty():
		_fail("503 retry must preserve original payload and operation ID"); return
	var aborted: Dictionary = {"done":false,"value":{}}
	_updateAsync(stats, [{"key":"kills","value":1}], stats.createOperationId(), aborted)
	await create_timer(.06).timeout
	http.sessionToken = "replacement-session"
	auth._currentUser.accessToken = "replacement-session"
	http.apiKey = "replacement-project"
	await create_timer(.25).timeout
	if not aborted["done"] or not aborted["value"].is_empty() or stats.getLastErrorCode() != "SESSION_CHANGED":
		_fail("Backoff must abort before sending old request with new credentials"); return
	for invalid: Array in [[{"key":"kills","value":1.0}], [{"key":"kills","value":9007199254740992}], [{"key":"kills","value":1},{"key":"kills","value":2}]]:
		if not (await stats.updateStatistics(invalid,operation)).is_empty() or stats.getLastErrorCode() != "INVALID_REQUEST":
			_fail("Invalid numbers or duplicate keys must fail locally"); return
	http.sessionToken = "fresh-session"
	auth._currentUser.accessToken = "fresh-session"
	http.apiKey = "project-statistics"
	var large_batch: Array = []
	for i: int in range(201): large_batch.append({"key": "stat%d" % i, "value": i})
	var large_operation: String = stats.createOperationId()
	var large_result: Dictionary = await stats.updateStatistics(large_batch, large_operation)
	if large_result.is_empty() or large_result["values"].size() != 201 or stats.getCurrentDefinitions().size() != 201:
		_fail("Admin-configured catalog above100 must remain usable"); return
	var reduced_replay: Dictionary = await stats.updateStatistics(large_batch, large_operation)
	if not reduced_replay.get("replayed", false) or reduced_replay["definitions"].size() != 1:
		_fail("Original large batch must replay after a catalog reduction"); return
	http.sessionToken=""
	if not (await stats.getStatistics()).is_empty() or stats.getLastErrorCode() != "SESSION_REQUIRED":
		_fail("Missing session must fail locally"); return
	await create_timer(1.2).timeout
	print("Godot statistics transport, watermark, cache epoch and session contract passed")
	http.queue_free()
	quit(0)

func _loadAsync(stats: HorizonStatistics, result: Dictionary) -> void:
	result["value"] = await stats.getStatistics()
	result["done"] = true

func _updateAsync(stats: HorizonStatistics, batch: Array, operation: String, result: Dictionary) -> void:
	result["value"] = await stats.updateStatistics(batch, operation)
	result["done"] = true

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
