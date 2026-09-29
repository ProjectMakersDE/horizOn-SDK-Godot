extends SceneTree

const TEST_PORT := 18896
const TOKEN_ONE := "srvTokenOne_0123456789abcdefghij"
const TOKEN_TWO := "srvTokenTwo-0123456789abcdefghij"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# A session or token from an earlier run must not leak into this one.
	_clearAuthCache()

	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "project-key-896"
	http.activeHost = "http://127.0.0.1:%d" % TEST_PORT
	http.maxRetryAttempts = 0

	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	var events := {"signup": 0, "signin": 0, "signup_failed": 0}
	auth.signup_completed.connect(func(_user: HorizonUserData): events["signup"] += 1)
	auth.signin_completed.connect(func(_user: HorizonUserData): events["signin"] += 1)
	auth.signup_failed.connect(func(_error: String): events["signup_failed"] += 1)

	# 1. + 2. Signup sends no token, stores the issued one and signs in with it.
	if not await auth.signUpAnonymous("player-896"):
		_fail("anonymous signup without token was rejected by the contract server")
		return
	var user := auth.getCurrentUser()
	if not auth.isSignedIn() or http.sessionToken != "session-896-a" or user.accessToken != "session-896-a":
		_fail("signup without access token must sign in with the issued token")
		return
	if not user.isAnonymous or user.authType != "ANONYMOUS" or user.anonymousToken != TOKEN_ONE or user.userId != "user-896":
		_fail("the anonymous user must keep the issued token although the signin response omits it")
		return
	if auth.getCachedAnonymousToken() != TOKEN_ONE:
		_fail("the issued token must be stored for restoreAnonymousSession")
		return
	if events["signup"] != 1 or events["signin"] != 1:
		_fail("signup must emit signup_completed and signin_completed once each")
		return

	# 3. Sign out keeping the token, then restore the session with it.
	auth.signOut(true)
	if auth.isSignedIn() or not http.sessionToken.is_empty():
		_fail("signOut must clear the session")
		return
	if not await auth.restoreAnonymousSession():
		_fail("restoreAnonymousSession with the stored token was rejected")
		return
	user = auth.getCurrentUser()
	if http.sessionToken != "session-896-b" or not user.isAnonymous or user.anonymousToken != TOKEN_ONE:
		_fail("restoreAnonymousSession must keep the anonymous token and flag")
		return

	# 4. The deprecated token argument is ignored; an access token in the
	# signup response is the session, no signin follows.
	auth.signOut(false)
	auth.clearAnonymousToken()
	if not await auth.signUpAnonymous("", "clientToken-0123456789abcdefghij"):
		_fail("signup with the deprecated token argument must still succeed")
		return
	user = auth.getCurrentUser()
	if http.sessionToken != "session-896-c" or user.anonymousToken != TOKEN_TWO or not user.isAnonymous:
		_fail("a signup response with access token must be the session")
		return
	if auth.getCachedAnonymousToken() != TOKEN_TWO:
		_fail("the issued token of a direct session must be stored")
		return

	# 5. A signup response without token fails and sends no signin.
	auth.signOut(false)
	auth.clearAnonymousToken()
	var failedBefore: int = events["signup_failed"]
	if await auth.signUpAnonymous("no-token"):
		_fail("a signup response without token must fail")
		return
	if auth.isSignedIn() or events["signup_failed"] != failedBefore + 1 or not auth.getCachedAnonymousToken().is_empty():
		_fail("a signup without token must leave no session or token and emit signup_failed")
		return

	# Keep the process alive while the contract server watches for an unexpected signin.
	await create_timer(1.8).timeout
	_clearAuthCache()
	print("Godot anonymous auth transport contract passed")
	http.queue_free()
	quit(0)


func _clearAuthCache() -> void:
	var config := ConfigFile.new()
	var path := "user://horizon_cache.cfg"
	if config.load(path) != OK:
		return
	for key in [HorizonAuth.CACHE_KEY_USER_SESSION, HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN]:
		if config.has_section_key("cache", key):
			config.erase_section_key("cache", key)
	config.save(path)


func _fail(message: String) -> void:
	_clearAuthCache()
	push_error(message)
	quit(1)
