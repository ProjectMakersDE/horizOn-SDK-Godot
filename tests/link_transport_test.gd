extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
func _run() -> void:
	var logger: HorizonLogger = HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http: HorizonHttpClient = HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "link-fixture"
	http.activeHost = "http://127.0.0.1:18930"
	http.maxRetryAttempts = 0
	var auth: HorizonAuth = HorizonAuth.new()
	auth.initialize(http, logger)
	if await auth.linkEmail("a@example.invalid", "not-a-real-password"):
		_fail("Link without a signed-in guest must fail locally")
		return
	auth._currentUser.updateFromAuthResponse({"userId": "guest-1", "accessToken": "session-1", "isAnonymous": true, "anonymousToken": "guest-token-0123456789abcdefghijk"})
	auth._saveAnonymousToken("guest-token-0123456789abcdefghijk")
	if await auth.linkEmail("a@example.invalid", "not-a-real-password"):
		_fail("409 must fail the link")
		return
	if not auth.getCurrentUser().isAnonymous or not auth.hasCachedAnonymousToken():
		_fail("A failed link must keep the guest identity")
		return
	if not await auth.linkGoogle("code", "http://localhost/cb"):
		_fail("Google link must succeed")
		return
	var user := auth.getCurrentUser()
	if user.isAnonymous or user.userId != "guest-1" or user.accessToken != "session-1" or user.authType != "GOOGLE" or auth.hasCachedAnonymousToken():
		_fail("Link must keep user and session, drop the guest flag and the stored token")
		return
	auth._currentUser.isAnonymous = true
	if not await auth.linkApple("identity-token"):
		_fail("Apple link must succeed")
		return
	if auth.getCurrentUser().authType != "APPLE":
		_fail("Apple link must update the auth type")
		return
	print("Godot link: guest account linked with the same user ID")
	# The cached session would leak into the next contract test of this project.
	auth.signOut(false)
	auth.clearAnonymousToken()
	http.queue_free()
	quit(0)
