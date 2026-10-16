extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/groups_example.gd")
const A := "00000000-0000-4000-8000-000000001010"
const B := "00000000-0000-4000-8000-000000001011"
const G := "00000000-0000-4000-8000-000000003010"
const H := "00000000-0000-4000-8000-000000003011"
const J := "00000000-0000-4000-8000-000000003012"
const R := 4294967296
class FixtureHorizon extends Node:
	var auth: HorizonAuth
	var groups: HorizonGroups
var _http: HorizonHttpClient
var _horizon: FixtureHorizon

func _initialize() -> void:
	create_timer(25).timeout.connect(func():
		push_error("Groups HTTP contract did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	_http = HorizonHttpClient.new()
	root.add_child(_http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	_http.initialize(logger)
	_http.apiKey = "groups-key"
	_http.activeHost = "http://127.0.0.1:20110"
	_http.maxRetryAttempts = 3
	_http.retryDelaySeconds = .02
	_http.connectionTimeoutSeconds = 1
	_horizon = FixtureHorizon.new()
	_horizon.name = "Horizon"
	_horizon.auth = HorizonAuth.new()
	_horizon.auth.initialize(_http, logger)
	_horizon.groups = HorizonGroups.new()
	_horizon.groups.initialize(_http, _horizon.auth)
	root.add_child(_horizon)
	var sample: Node = Sample.new()
	root.add_child(sample)
	_player(A)
	var result: Dictionary = await sample.refresh_groups()
	assert(result.success and typeof(result.data.revision) == TYPE_INT and result.data.revision == R)
	var data: HorizonGroupJsonData = HorizonGroupJsonData.fromJson('{"revision":1.5,"$key":{"a.b":[],"":{}},"fraction":1e-10,"seed":9007199254740993,"huge":123456789012345678901234567890,"precise":1.0000000000000000000001,"unicode":"é/😀"}')
	assert(data != null and data.getJson().contains("é/😀"))
	result = await sample.create_group(R, "Guild", "open", data)
	assert(result.success and result.data.group.id == G and result.data.group.myRole == "leader")
	result = await sample.inspect_group(G)
	if not result.success: print("Group detail diagnostic: ", result)
	assert(result.success, str(result))
	data = result.data.data
	result = await sample.update_group(G, 1, "Guild", "", "request", data)
	if not result.success: print("Group update diagnostic: ", result)
	assert(result.success)
	assert((await sample.confirm_action("invite", G, 2, B)).success)
	_player(B)
	result = await sample.refresh_groups()
	assert(result.success and not result.data.incomingInvites[0].group.has("data"))
	assert((await sample.confirm_action("accept-invite", G, 3, "", _request(1))).success)
	result = await sample.load_member_page(G)
	assert(result.success and result.data.members.size() == 2 and result.data.members[0].display.name == null and not result.data.members[0].display.has("email"))
	assert((await sample.load_pending(G)).errorCode == "GROUP_PERMISSION_DENIED")
	assert((await sample.inspect_group(G)).data.myRole == "member")
	assert((await sample.confirm_action("leave", G, 4)).data.group == null)
	assert((await sample.confirm_action("request", G, 5)).success)
	_player(A)
	assert((await sample.load_pending(G)).data.joinRequests[0].requestId == _request(2))
	assert((await sample.confirm_action("decline-request", G, 6, B, _request(2))).success)
	_player(B)
	assert((await sample.confirm_action("request", G, 7)).success)
	assert((await sample.confirm_action("cancel-request", G, 8, "", _request(3))).success)
	_player(A)
	assert((await sample.confirm_action("invite", G, 9, B)).success)
	assert((await sample.confirm_action("cancel-invite", G, 10, B, _request(4))).success)
	assert((await sample.confirm_action("invite", G, 11, B)).success)
	_player(B)
	assert((await sample.confirm_action("decline-invite", G, 12, "", _request(5))).success)
	_player(A)
	assert((await sample.confirm_action("invite", G, 13, B)).success)
	_player(B)
	assert((await sample.confirm_action("accept-invite", G, 14, "", _request(6))).success)
	_player(A)
	assert((await sample.confirm_action("role", G, 15, B, "", "officer")).success)
	assert((await sample.confirm_action("remove", G, 16, B)).success)
	_player(B)
	assert((await sample.confirm_action("request", G, 17)).success)
	_player(A)
	assert((await sample.confirm_action("accept-request", G, 18, B, _request(7))).success)
	assert((await sample.confirm_action("transfer", G, 19, B)).data.group.myRole == "member")
	assert((await sample.confirm_action("leave", G, 20)).data.group == null)
	_player(B)
	assert((await sample.confirm_action("delete", G, 21)).data.groups.groups.is_empty())
	_player(A)
	assert((await sample.confirm_action("join", J, 42)).data.group.myRole == "member")
	assert((await sample.confirm_action("leave", J, 43)).data.group == null)
	assert(data.getJson().contains("9007199254740993") and data.getJson().contains("123456789012345678901234567890") and data.getJson().contains("1.0000000000000000000001"))
	assert((await sample.create_group(R + 1000, "Guild", "open", data)).errorCode == "HTTP_503")
	assert((await sample.refresh_groups()).data.groups[0].id == H, "Explicit read reconciles uncertain creation, no second create")
	assert((await sample.confirm_action("invite", H, 1, B)).errorCode == "INBOX_FULL")

	assert((await sample.update_group(H, 1, "Guild", "", "request", data)).errorCode == "HTTP_503")
	assert((await sample.inspect_group(H)).data.revision == 2, "PUT has exactly one actual transport attempt")
	assert((await sample.confirm_action("delete", H, 2)).errorCode == "RATE_LIMITED")
	assert((await sample.refresh_groups()).data.groups[0].id == H)
	assert(not (await sample.confirm_action("delete", H, 2)).success, "Uncertain timeout must not retry")
	assert((await sample.refresh_groups()).data.groups.is_empty())
	create_timer(.04).timeout.connect(func():
		_http.sessionToken = "temporary"
		_http.sessionToken = "group-session-a")
	assert((await sample.refresh_groups()).errorCode == "STALE_RESPONSE" and _horizon.groups.getCurrentGroups().is_empty())
	await create_timer(1.8).timeout
	print("Godot actual Groups example: all20 HTTP routes, two-player invitation/roles/transfer/leave, private data/pages, full Inbox and original single-attempt503/429/timeout reconciliation passed")
	sample.free()
	_horizon.free()
	_http.queue_free()
	quit(0)

func _request(index: int) -> String: return "00000000-0000-4000-8000-%012d" % (4010 + index)
func _player(user: String) -> void:
	_http.sessionToken = "group-session-a" if user == A else "group-session-b"
	_horizon.auth._currentUser.userId = user
	_horizon.auth._currentUser.accessToken = _http.sessionToken
