extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/groups_example.gd")
const U: String = "00000000-0000-4000-8000-000000001016"
const G: String = "00000000-0000-4000-8000-000000050000"
class Client extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var groups: HorizonGroups
var failed: bool = false
var checks: int = 0
func check(value: bool) -> void:
	checks += 1
	if not value: failed = true; push_error("Group sample assertion%d" % checks)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Group sample watchdog"); quit(1))
	call_deferred("_run")
func _run() -> void:
	var h := Client.new(); h.name = "Horizon"; root.add_child(h)
	h._http = HorizonHttpClient.new(); h.add_child(h._http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	h._http.initialize(logger); h._http.activeHost = "http://127.0.0.1:20117"; h._http.apiKey = "sample-key"; h._http.sessionToken = "sample-session"; h._http.maxRetryAttempts = 0
	h.auth = HorizonAuth.new(); h.auth.initialize(h._http, logger); h.auth._currentUser.userId = U; h.auth._currentUser.accessToken = "sample-session"
	h.groups = HorizonGroups.new(); h.groups.initialize(h._http, h.auth)
	var sample := Sample.new(); root.add_child(sample)
	check((await sample.load_member_page(G)).errorCode == "CURRENT_LIMITS_REQUIRED")
	check((await sample.refresh_groups()).success)
	var page: Dictionary = await sample.load_member_page(G)
	check(page.success and not page.restarted and page.data.nextAfterUserId == U)
	check((await sample.refresh_groups()).success)
	page = await sample.load_member_page(G, U)
	check(page.success and page.restarted and page.data.nextAfterUserId == U)
	page = await sample.load_member_page(G, U)
	check(page.success and not page.restarted and page.data.nextAfterUserId == null)
	check((await sample.load_member_page(G, "", 7)).errorCode == "INVALID_PAGE")
	h._http.setSessionToken("other"); h._http.setSessionToken("sample-session")
	check((await sample.load_member_page(G)).errorCode == "CURRENT_LIMITS_REQUIRED")
	sample.queue_free(); h._http.clearSessionToken()
	for signal_value: Signal in [h.auth.signout_completed, h.auth.signin_completed, h.auth.signup_completed]:
		for connection: Dictionary in signal_value.get_connections(): signal_value.disconnect(connection.callable)
	h.queue_free(); await process_frame; await process_frame
	print("Groups sample current-limit transport:%d assertions, failed=%s" % [checks,failed])
	quit(1 if failed else 0)
