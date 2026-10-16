extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var logger: HorizonLogger = HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http: HorizonHttpClient = HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "signup-once-fixture"
	http.activeHost = "http://127.0.0.1:18917"
	http.maxRetryAttempts = 3
	http.retryDelaySeconds = .01
	http.connectionTimeoutSeconds = 1
	var auth: HorizonAuth = HorizonAuth.new()
	auth.initialize(http,logger)
	auth._currentUser.clear()
	http.sessionToken = ""
	if await auth.signUpAnonymous("Once"):
		push_error("Uncertain503 must not become a successful replacement signup"); quit(1); return
	if await auth.signUpEmail("fixture@example.invalid","not-a-real-password","Once"):
		push_error("Uncertain timeout must not become a successful replacement signup"); quit(1); return
	if auth.isSignedIn():
		push_error("No new local identity may be fabricated"); quit(1); return
	await create_timer(1.8).timeout
	print("Godot signup503/timeout each use one actual HTTP attempt")
	http.queue_free()
	quit(0)
