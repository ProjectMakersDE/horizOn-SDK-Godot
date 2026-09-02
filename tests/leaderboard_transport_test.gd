extends SceneTree

const TEST_PORT := 18720


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-720"
	http.activeHost = "http://127.0.0.1:%d" % TEST_PORT
	http.sessionToken = "session-token-720"
	http.maxRetryAttempts = 0

	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "user-720"
	auth._currentUser.accessToken = "session-token-720"

	var leaderboard := HorizonLeaderboard.new()
	leaderboard.initialize(http, logger, auth)

	var submitted := await leaderboard.submitScore(4242, "season one")
	if not submitted:
		_fail("signed SubmitScore request was rejected by the contract server")
		return

	auth._currentUser.clear()
	var rejected_without_session := not await leaderboard.submitScore(99, "season one")
	if not rejected_without_session:
		_fail("SubmitScore must reject a missing session")
		return

	# Keep the process alive while the contract server watches for an unexpected second request.
	await create_timer(1.8).timeout
	print("Godot leaderboard transport contract passed")
	http.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
