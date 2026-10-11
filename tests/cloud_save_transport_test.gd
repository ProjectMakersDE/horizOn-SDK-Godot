extends SceneTree

var TEST_DATA := PackedByteArray([0, 255, 128, 10, 42])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-892"
	http.activeHost = "http://127.0.0.1:18892"
	http.maxRetryAttempts = 0
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "user-892"
	auth._currentUser.accessToken = "session-token-892"
	http.setSessionToken("session-token-892")
	var saves := HorizonCloudSave.new()
	saves.initialize(http, logger, auth)
	var events := {"saved": 0, "loaded": "", "bytes_saved": 0, "bytes_loaded": 0, "errors": 0}
	saves.data_saved.connect(func(size_bytes: int): events["saved"] = size_bytes)
	saves.data_loaded.connect(func(data: String): events["loaded"] = data)
	saves.bytes_saved.connect(func(size_bytes: int): events["bytes_saved"] = size_bytes)
	saves.bytes_loaded.connect(func(_data: PackedByteArray): events["bytes_loaded"] += 1)
	saves.data_load_failed.connect(func(_error: String): events["errors"] += 1)

	if not await saves.saveData('{"level":5}') or events["saved"] != 11:
		_fail("JSON save must send the Bearer session and emit its size")
		return
	if await saves.loadData() != '{"level":5}' or events["loaded"] != '{"level":5}':
		_fail("JSON load must send the Bearer session and return its data")
		return
	if not await saves.saveBytes(TEST_DATA) or events["bytes_saved"] != TEST_DATA.size():
		_fail("binary save must send the Bearer session and raw bytes")
		return
	if await saves.loadBytes() != TEST_DATA or events["bytes_loaded"] != 1:
		_fail("binary load must POST JSON and preserve all response bytes")
		return
	if not (await saves.loadBytes()).is_empty() or events["bytes_loaded"] != 1 or events["errors"] != 0:
		_fail("204 must mean absent data without a failure or loaded signal")
		return
	if not (await saves.loadBytes()).is_empty() or events["errors"] != 1:
		_fail("401 must fail and emit data_load_failed")
		return

	# Revision flow (TASK-1018): load with revision, save with If-Match, 409 is a conflict.
	var counts := {"conflicts": 0, "save_failures": 0, "writes": 0}
	saves.save_conflict.connect(func(_error: String): counts["conflicts"] += 1)
	saves.data_saved.connect(func(_size: int): counts["writes"] += 1)
	saves.bytes_saved.connect(func(_size: int): counts["writes"] += 1)
	saves.data_save_failed.connect(func(_error: String): counts["save_failures"] += 1)

	var snapshot := await saves.loadSnapshot()
	if not snapshot["success"] or not snapshot["found"] or snapshot["data"] != '{"level":5}' or snapshot["revision"] != 3:
		_fail("loadSnapshot must return the data with the X-Cloud-Save-Revision header")
		return
	var written := await saves.saveDataAtRevision('{"level":5}', snapshot["revision"])
	if written["status"] != HorizonCloudSave.STATUS_SAVED or not written["success"] or written["revision"] != 4 or written["dataSizeBytes"] != 11:
		_fail("saveDataAtRevision must send If-Match and return the new revision")
		return
	# Retries stay on for the conflicts: a retried 409 would reach the next scripted
	# request and fail the mock server.
	http.maxRetryAttempts = 2
	var writesBefore: int = counts["writes"]
	var stale := await saves.saveDataAtRevision('{"level":5}', 3)
	if counts["writes"] != writesBefore:
		_fail("a 409 must not emit data_saved")
		return
	if stale["status"] != HorizonCloudSave.STATUS_CONFLICT or not stale["conflict"] or stale["success"] or stale["revision"] != HorizonCloudSave.REVISION_UNKNOWN or stale["statusCode"] != 409 or counts["conflicts"] != 1 or counts["save_failures"] != 0:
		_fail("a 409 must be a conflict that emits save_conflict and not data_save_failed")
		return
	var bytesSnapshot := await saves.loadBytesSnapshot()
	if not bytesSnapshot["success"] or not bytesSnapshot["found"] or bytesSnapshot["data"] != TEST_DATA or bytesSnapshot["revision"] != 7:
		_fail("loadBytesSnapshot must return the bytes with their revision")
		return
	var emptySnapshot := await saves.loadBytesSnapshot()
	if not emptySnapshot["success"] or emptySnapshot["found"] or not emptySnapshot["data"].is_empty() or emptySnapshot["revision"] != 0:
		_fail("a 204 snapshot must be an empty slot at revision 0")
		return
	var firstBytes := await saves.saveBytesAtRevision(TEST_DATA, 0)
	if firstBytes["status"] != HorizonCloudSave.STATUS_SAVED or firstBytes["revision"] != 1:
		_fail("saveBytesAtRevision must send If-Match: 0 for an empty slot and return revision 1")
		return
	writesBefore = counts["writes"]
	var staleBytes := await saves.saveBytesAtRevision(TEST_DATA, 1)
	if counts["writes"] != writesBefore:
		_fail("a binary 409 must not emit bytes_saved")
		return
	if staleBytes["status"] != HorizonCloudSave.STATUS_CONFLICT or counts["conflicts"] != 2 or counts["save_failures"] != 0:
		_fail("a binary 409 must be a conflict as well")
		return
	http.maxRetryAttempts = 0
	var unknown := await saves.loadSnapshot()
	if not unknown["success"] or unknown["found"] or unknown["revision"] != HorizonCloudSave.REVISION_UNKNOWN or events["errors"] != 1:
		_fail("a load without revision header must report an unknown revision, not an empty slot")
		return
	var bytesUnknown := await saves.loadBytesSnapshot()
	if not bytesUnknown["success"] or not bytesUnknown["found"] or bytesUnknown["revision"] != HorizonCloudSave.REVISION_UNKNOWN:
		_fail("a binary load without revision header must report an unknown revision")
		return
	var savedUnknown := await saves.saveDataAtRevision('{"level":5}', 0)
	if savedUnknown["status"] != HorizonCloudSave.STATUS_SAVED or savedUnknown["revision"] != HorizonCloudSave.REVISION_UNKNOWN:
		_fail("a save answer without revision must report an unknown revision")
		return
	var emptyJson := await saves.loadSnapshot()
	if not emptyJson["success"] or emptyJson["found"] or emptyJson["revision"] != 0:
		_fail("an empty JSON slot must be found=false at revision 0")
		return
	var unreadable := await saves.loadSnapshot()
	if unreadable["success"] or unreadable["revision"] != HorizonCloudSave.REVISION_UNKNOWN or events["errors"] != 2:
		_fail("a load answer without found must fail, never look like an empty slot")
		return
	var unconfirmed := await saves.saveDataAtRevision('{"level":5}', 7)
	if unconfirmed["status"] != HorizonCloudSave.STATUS_FAILED or unconfirmed["error"].is_empty():
		_fail("a save answer without success must fail with a message")
		return
	if (await saves.saveDataAtRevision('{"level":5}', 7))["status"] != HorizonCloudSave.STATUS_FAILED:
		_fail("a string success must not count as written")
		return
	var fractional := await saves.saveDataAtRevision('{"level":5}', 7)
	if fractional["status"] != HorizonCloudSave.STATUS_SAVED or fractional["revision"] != HorizonCloudSave.REVISION_UNKNOWN:
		_fail("a fractional save revision must be unknown")
		return
	var saveBody := {"userId": "user-892", "saveData": '{"level":5}'}
	var featureLimit: HorizonNetworkResponse = await http.postAsync("/api/v1/app/cloud-save/save", saveBody, true)
	var accountLimit: HorizonNetworkResponse = await http.postAsync("/api/v1/app/cloud-save/save", saveBody, true)
	if featureLimit.statusCode != 429 or featureLimit.getHeader("Retry-After") != "30" or accountLimit.statusCode != 429 or accountLimit.getHeader("Retry-After") != "1":
		_fail("JSON 429 answers must keep their response headers")
		return
	var negative := await saves.saveDataAtRevision("x", -1)
	if negative["status"] != HorizonCloudSave.STATUS_FAILED or negative["statusCode"] != 0:
		_fail("a negative expected revision must fail locally")
		return
	if (await saves.saveBytesAtRevision(TEST_DATA, -1))["status"] != HorizonCloudSave.STATUS_FAILED:
		_fail("a negative expected revision must fail locally for bytes")
		return
	if (await saves.saveDataAtRevision("", -1))["error"] != "Save data is required" or (await saves.saveBytesAtRevision(PackedByteArray(), -1))["error"] != "Save data is required":
		_fail("missing data must be reported before an invalid revision")
		return

	# None of these unsigned calls may reach the contract server.
	auth._currentUser.clear()
	http.clearSessionToken()
	if await saves.saveData("x") or not (await saves.loadData()).is_empty() or await saves.saveBytes(TEST_DATA) or not (await saves.loadBytes()).is_empty():
		_fail("unsigned Cloud Save operations must fail locally")
		return
	if (await saves.loadSnapshot())["success"] or (await saves.loadBytesSnapshot())["success"] or (await saves.saveDataAtRevision("x", 0))["success"] or (await saves.saveBytesAtRevision(TEST_DATA, 0))["success"]:
		_fail("unsigned revision operations must fail locally")
		return
	if (await saves.saveDataAtRevision("x", -1))["error"] != "expectedRevision must be 0 (empty slot) or a revision from a snapshot or save":
		_fail("an invalid revision must be reported before the missing sign-in")
		return
	await create_timer(1.8).timeout
	http.queue_free()
	print("Godot Cloud Save transport contract passed")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
