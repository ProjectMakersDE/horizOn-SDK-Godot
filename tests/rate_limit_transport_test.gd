extends SceneTree
class ObservedClient extends HorizonHttpClient:
	var waits: Array[float] = []
	func _rateLimitDelay(after: float) -> float:
		var seconds: float = super._rateLimitDelay(after)
		waits.append(seconds)
		return seconds
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var logger: HorizonLogger = HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http: ObservedClient = ObservedClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "rate-key"
	http.sessionToken = "rate-session"
	http.activeHost = "http://127.0.0.1:20096"
	http.maxRetryAttempts = 1
	http.retryDelaySeconds = .01
	http._retryRandom.seed = 996
	var unique: Dictionary = {}
	for _sample: int in range(512):
		var delay: float = http._rateLimitDelay(5.0)
		assert(delay >= 5.0 and delay <= 6.0,"0–20% jitter never shortens the server minimum")
		unique[delay] = true
	assert(unique.size() > 1,"Retry delays must spread requests rather than stay constant")
	for invalid: float in [0.0,-1.0,INF,NAN]:
		var delay: float = http._rateLimitDelay(invalid)
		assert(is_finite(delay) and delay >= 1.0 and delay <= 1.2,"Invalid hints have a finite conservative fallback")
	seed(996)
	var game_random: int = randi()
	seed(996)
	http._rateLimitDelay(1.0)
	assert(randi() == game_random,"Transport jitter never consumes the game global RNG")
	http.waits.clear()
	var response: HorizonNetworkResponse = await http.getAsync("/api/v1/app/news?case=read",true)
	assert(response.isSuccess and http.waits.size() == 1)
	var original: Dictionary = {"userId":"00000000-0000-4000-8000-000000000996","operationId":"1792152000000:00000000-0000-4000-8000-000000000996","updates":[{"key":"kills","value":3}]}
	create_timer(.05).timeout.connect(func(): original.updates[0].value = 999)
	response = await http.postAsync("/api/v1/app/statistics",original,true)
	assert(response.isSuccess and http.waits.size() == 2,"Mutable caller data cannot replace the serialized original request")
	for pair: Array in [["feature","CUSTOM_FUTURE_FEATURE"],["feature_lower","future_soft_limit"]]:
		response = await http.getAsync("/api/v1/app/news?case=" + pair[0],true)
		assert(not response.isSuccess and response.statusCode == 429 and response.serverCode == pair[1] and response.getHeader("Retry-After") == "60")
		assert(http.waits.size() == 2,"Any nonempty feature code returns without waiting/retry")
	response = await http.getAsync("/api/v1/app/news?case=exhaust",true)
	assert(not response.isSuccess and response.statusCode == 429 and http.waits.size() == 3,"Maximum retry budget is unchanged")
	original.operationId = "1792152000000:00000000-0000-4000-8000-000000000997"
	original.updates[0].value = 3
	create_timer(.05).timeout.connect(func():
		http.sessionToken = "temporary"
		http.sessionToken = "rate-session")
	response = await http.postAsync("/api/v1/app/statistics",original,true)
	assert(not response.isSuccess and response.serverCode == "SESSION_CHANGED" and http.waits.size() == 4,"A credential ABA during jitter cannot issue another HTTP request")
	for wait: float in http.waits: assert(wait >= 1.0 and wait <= 1.2)
	await create_timer(1.8).timeout
	print("Godot TASK996:512 bounded varied jitter samples, isolated game RNG,9 real HTTP requests and exact retry policy passed")
	http.queue_free()
	quit(0)
