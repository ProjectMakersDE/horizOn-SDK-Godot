extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/friends_example.gd")
const A := "00000000-0000-4000-8000-000000001009"
const B := "00000000-0000-4000-8000-000000001010"
const C := "00000000-0000-4000-8000-000000001011"
const D := "00000000-0000-4000-8000-000000001012"
const E := "00000000-0000-4000-8000-000000001013"
const F := "00000000-0000-4000-8000-000000001014"
const G := "00000000-0000-4000-8000-000000001015"
const H := "00000000-0000-4000-8000-000000001016"
const R1 := "00000000-0000-4000-8000-000000002001"
const R2 := "00000000-0000-4000-8000-000000002002"
const R3 := "00000000-0000-4000-8000-000000002003"
const R4 := "00000000-0000-4000-8000-000000002004"
const R := 4294967296
class FixtureHorizon extends Node:
	var auth: HorizonAuth
	var friends: HorizonFriends

func _initialize() -> void:
	create_timer(20).timeout.connect(func():
		push_error("Friends HTTP contract did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	var http := HorizonHttpClient.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "friends-key"
	http.sessionToken = "friend-session-a"
	http.activeHost = "http://127.0.0.1:20109"
	http.maxRetryAttempts = 3
	http.retryDelaySeconds = .02
	http.connectionTimeoutSeconds = 1
	var horizon := FixtureHorizon.new()
	horizon.name = "Horizon"
	horizon.auth = HorizonAuth.new()
	horizon.auth.initialize(http, logger)
	horizon.auth._currentUser.userId = A
	horizon.auth._currentUser.accessToken = http.sessionToken
	horizon.friends = HorizonFriends.new()
	horizon.friends.initialize(http, horizon.auth)
	root.add_child(horizon)
	var sample: Node = Sample.new()
	root.add_child(sample)
	var result: Dictionary = await sample.refresh_friends()
	assert(result.success and result.data.revision == R and typeof(result.data.revision) == TYPE_INT)
	assert(result.data.friends[0].lastActiveAt == null and result.data.friends[0].display.name == null)
	assert(not result.data.blocked[0].has("email") and not result.data.blocked[0].has("lastActiveAt"))
	result.data.incoming.clear()
	assert(horizon.friends.getCurrentFriends().incoming.size() == 2, "Callers cannot mutate the retained authoritative snapshot")
	result = await sample.find_exact(horizon.friends._code(B))
	assert(result.success and result.data.userId == B and not result.data.has("blocked") and not result.data.has("email"))
	assert(horizon.friends.getCurrentFriends().revision == R, "Exact public lookup cannot replace own private relationships")
	assert((await sample.change_relationship("request", F, R)).data.revision == R + 1)
	assert((await sample.change_relationship("accept", C, R + 1, R1)).data.friends.size() == 2)
	assert((await sample.change_relationship("decline", G, R + 2, R4)).data.incoming.is_empty())
	assert((await sample.change_relationship("cancel", D, R + 3, R2)).data.outgoing.size() == 1)
	assert((await sample.change_relationship("remove", B, R + 4)).data.friends.size() == 1)
	result = await sample.change_relationship("block", C, R + 5)
	assert(result.success and result.data.friends.is_empty() and result.data.blocked.size() == 2)
	assert((await sample.change_relationship("unblock", E, R + 6)).data.blocked.size() == 1)
	result = await sample.change_relationship("request", H, R + 7)
	assert(not result.success and result.errorCode == "HTTP_503" and horizon.friends.getCurrentFriends().is_empty())
	assert((await sample.refresh_friends()).data.outgoing.size() == 2, "Only explicit refresh reconciles an uncertain command; no hidden retry")
	result = await sample.change_relationship("cancel", F, R + 8, R3)
	assert(not result.success and result.errorCode == "RATE_LIMITED", "An unreceipted command returns global 429 without another send")
	assert((await sample.refresh_friends()).data.revision == R + 8)
	result = await sample.change_relationship("cancel", F, R + 8, R3)
	assert(not result.success and horizon.friends.getCurrentFriends().is_empty(), "Timeout is uncertain and sends only once")
	assert((await sample.refresh_friends()).data.outgoing.size() == 1)
	create_timer(.04).timeout.connect(func():
		http.sessionToken = "temporary"
		http.sessionToken = "friend-session-a")
	assert((await sample.refresh_friends()).errorCode == "STALE_RESPONSE" and horizon.friends.getCurrentFriends().is_empty())
	horizon.auth._currentUser.userId = B
	horizon.auth._currentUser.accessToken = "friend-session-b"
	http.sessionToken = "friend-session-b"
	result = await sample.refresh_friends()
	assert(result.success and result.data.userId == B and result.data.blocked.is_empty(), "A second player never receives the first player's private blocklist")
	await create_timer(1.8).timeout
	print("Godot actual Friends example: 17 real HTTP requests, all nine endpoints, exact public lookup, full snapshots, explicit 503/429/timeout reconciliation and player/session fences passed")
	sample.free()
	horizon.free()
	http.queue_free()
	quit(0)
