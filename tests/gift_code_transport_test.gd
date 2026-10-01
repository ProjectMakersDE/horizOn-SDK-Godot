extends SceneTree

const TEST_PORT := 18724


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-886"
	http.activeHost = "http://127.0.0.1:%d" % TEST_PORT
	http.sessionToken = "session-token-886"
	http.maxRetryAttempts = 0

	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = "user-886"
	auth._currentUser.accessToken = "session-token-886"

	var gift_codes := HorizonGiftCodes.new()
	gift_codes.initialize(http, logger, auth)

	var redeemed := await gift_codes.redeem("SUMMER2026")
	if not redeemed.get("success", false):
		_fail("session-bound redeem request was rejected by the contract server")
		return

	# A signed-in user without a transport session must not reach the server.
	http.sessionToken = ""
	var without_session := await gift_codes.redeem("SUMMER2026")
	if not without_session.is_empty():
		_fail("redeem must not send a request without a session token")
		return

	# No signed-in user must not reach the server either.
	http.sessionToken = "session-token-886"
	auth._currentUser.clear()
	var without_user := await gift_codes.redeem("SUMMER2026")
	if not without_user.is_empty():
		_fail("redeem must reject a missing user")
		return

	# Keep the process alive while the contract server watches for an unexpected second request.
	await create_timer(1.8).timeout
	print("Godot gift code transport contract passed")
	http.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
