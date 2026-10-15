extends SceneTree
const Sdk = preload("res://addons/horizon_sdk/horizon_sdk.gd")
class RejectingHttp extends HorizonHttpClient:
	var calls: Array[String] = []
	func isConnected() -> bool:
		return true
	func postAsync(endpoint: String, _body: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		calls.append(endpoint)
		return HorizonNetworkResponse.failure("Restore temporarily unavailable", 503)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config := ConfigFile.new()
	config.load("user://horizon_cache.cfg")
	if config.has_section_key("cache", HorizonAuth.CACHE_KEY_USER_SESSION):
		config.erase_section_key("cache", HorizonAuth.CACHE_KEY_USER_SESSION)
	var original: String = "legacy-identity-".repeat(5)
	config.set_value("cache", HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN, original)
	config.save("user://horizon_cache.cfg")
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := RejectingHttp.new()
	root.add_child(http)
	http.initialize(logger)
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	var sdk := Sdk.new()
	sdk.auth = auth
	sdk._http = http
	sdk._logger = logger
	sdk._isConnected = true
	for _attempt: int in range(3):
		if not auth.hasCachedAnonymousToken() or auth.getCachedAnonymousToken() != original or await sdk.quickSignInAnonymous("replacement"):
			_fail("Legacy identity must remain present and block replacement signup"); return
	if not http.calls.is_empty():
		_fail("An unusable legacy token must fail locally without creating a new player"); return
	var reread := ConfigFile.new()
	reread.load("user://horizon_cache.cfg")
	if reread.get_value("cache", HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN) != original:
		_fail("Reading/restore failure must not delete persisted identity"); return
	original = "a-valid-server-token"
	auth._saveAnonymousToken(original)
	for _attempt: int in range(3):
		if await sdk.quickSignInAnonymous("replacement") or not auth.hasCachedAnonymousToken() or auth.getCachedAnonymousToken() != original:
			_fail("Repeated server restore failures must retain the original identity"); return
	if http.calls.size() != 3:
		_fail("Every explicit retry must attempt restore once"); return
	for endpoint: String in http.calls:
		if endpoint != "/api/v1/app/user-management/signin":
			_fail("A failed restore must never issue signup"); return
	# A new manager/process must still observe the retained identity.
	var restarted := HorizonAuth.new()
	restarted.initialize(http, logger)
	if not restarted.hasCachedAnonymousToken() or restarted.getCachedAnonymousToken() != original:
		_fail("Retained identity must survive manager restart"); return
	auth.clearAnonymousToken()
	sdk.free()
	http.queue_free()
	print("Godot anonymous identity survives legacy validation, repeated restore failure and convenience retries without replacement signup")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
