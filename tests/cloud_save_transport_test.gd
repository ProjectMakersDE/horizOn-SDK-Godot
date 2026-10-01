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

	# None of these unsigned calls may reach the contract server.
	auth._currentUser.clear()
	http.clearSessionToken()
	if await saves.saveData("x") or not (await saves.loadData()).is_empty() or await saves.saveBytes(TEST_DATA) or not (await saves.loadBytes()).is_empty():
		_fail("unsigned Cloud Save operations must fail locally")
		return
	await create_timer(1.8).timeout
	http.queue_free()
	print("Godot Cloud Save transport contract passed")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
