extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/achievements_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_inbox_claim.gd")
const USER := "00000000-0000-4000-8000-000000001008"
const ENTRY := "message:00000000-0000-4000-8000-000000001008"
class FixtureHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse:
		return _respond(endpoint, {}, session)
	func postAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		return _respond(endpoint, body, session)
	func _respond(endpoint: String, body: Dictionary, session: bool) -> HorizonNetworkResponse:
		assert(session and not responses.is_empty())
		if endpoint.ends_with("/claim"):
			assert(Pending.load_pending(apiKey, USER).pending == {"userId": USER, "entryId": ENTRY}, "The real sample must persist before each claim")
		calls.append({"endpoint": endpoint, "body": body.duplicate(true)})
		var next: Dictionary = responses.pop_front()
		if next.has("failure"): return HorizonNetworkResponse.failure("unknown claim response", next.failure)
		var response := HorizonNetworkResponse.success(next.data)
		response.rawBody = JSON.stringify(next.data)
		return response
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var inbox: HorizonInbox
	var playerValues: HorizonPlayerValues
	var achievements: HorizonAchievements

func _initialize() -> void:
	create_timer(15).timeout.connect(func():
		push_error("Achievement example flow did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	var http := FixtureHttp.new()
	root.add_child(http)
	http.initialize(HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	http.apiKey = "achievement-example-project"
	http.sessionToken = "achievement-example-session"
	http.activeHost = "https://example.invalid"
	var horizon := FixtureHorizon.new()
	horizon.name = "Horizon"
	horizon._http = http
	horizon.auth = HorizonAuth.new()
	horizon.auth.initialize(http, HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	horizon.auth._currentUser.userId = USER
	horizon.auth._currentUser.accessToken = http.sessionToken
	horizon.playerValues = HorizonPlayerValues.new()
	horizon.playerValues.initialize(http, horizon.auth)
	horizon.inbox = HorizonInbox.new()
	horizon.inbox.initialize(http, horizon.auth, horizon.playerValues)
	horizon.achievements = HorizonAchievements.new()
	horizon.achievements.initialize(http, horizon.auth, horizon.inbox)
	root.add_child(horizon)
	var sample: Node = Sample.new()
	root.add_child(sample)
	var pending: Dictionary = _achievements(false)
	http.responses = [{"data": pending}]
	var first: Dictionary = await sample.refresh_achievements()
	assert(first.success and horizon.playerValues.getCurrentState().is_empty(), "Pending 13 must not grant the current catalogue's 99 locally")
	var count: int = http.calls.size()
	assert((await sample.refresh_after_statistics({"newlyUnlocked": [], "replayed": true})).success and http.calls.size() == count)
	http.responses = [{"data": {"achievements": _achievements(true), "results": [{"key": "manual_hidden", "state": "delivered", "inboxEntryId": ENTRY, "code": null}]}}]
	assert((await sample.deliver_selected_pending(["manual_hidden"])).success and horizon.playerValues.getCurrentState().is_empty(), "Handoff remains separate from value claim")
	http.responses = [{"data": _inbox(false)}]
	assert((await sample.refresh_reward_inbox()).success)
	http.responses = [{"failure": 503}]
	assert((await sample.claim_delivered_reward(ENTRY)).errorCode == "HTTP_503")
	assert(Pending.load_pending(http.apiKey, USER).pending.entryId == ENTRY and horizon.playerValues.getCurrentState().is_empty())
	var values: Dictionary = {"userId": USER, "revision": 1, "definitionVersion": 1, "values": [{"key": "coins", "balance": 13, "earnedToday": 0}], "operationWindow": {"serverTime": "2026-10-16T12:00:08Z"}}
	http.responses = [{"data": {"entryId": ENTRY, "replayed": true, "inbox": _inbox(true), "playerValues": values}}]
	assert((await sample.claim_delivered_reward(ENTRY)).success)
	assert(horizon.playerValues.getCurrentState().values[0].balance == 13 and Pending.load_pending(http.apiKey, USER).pending.is_empty(), "Original claim replay replaces the full balance once")
	assert(http.calls[-1].body == http.calls[-2].body and http.calls.size() == 5)
	assert((await sample.claim_delivered_reward(ENTRY)).errorCode == "ENTRY_NOT_CLAIMABLE" and http.calls.size() == 5)
	sample.free()
	horizon.free()
	http.queue_free()
	print("Godot actual Achievements example: original pending 13 vs catalogue 99, explicit handoff, durable uncertain claim replay and authoritative balance replacement passed")
	quit(0)

func _achievements(delivered: bool) -> Dictionary:
	return {"userId": USER, "revision": 2 if delivered else 1, "definitionVersion": ("b" if delivered else "a").repeat(64), "definitions": [{"key": "manual_hidden", "name": "Hidden", "description": "", "imageUrl": null, "hidden": true, "active": true, "mode": "manual", "condition": null, "rewards": {"values": [{"key": "coins", "amount": 99}]}}], "progress": [{"key": "manual_hidden", "unlockedAt": "2026-10-16T12:00:00Z", "rewardState": "delivered" if delivered else "pending", "inboxEntryId": ENTRY if delivered else null, "pendingReward": null if delivered else {"issuedAt": "2026-10-16T12:00:00Z", "values": [{"key": "coins", "amount": 13}]}}], "limits": {"maxDefinitions": 20, "maxLifetimeKeys": 500}, "serverTime": "2026-10-16T12:00:05Z" if delivered else "2026-10-16T12:00:04Z"}

func _inbox(claimed: bool) -> Dictionary:
	return {"userId": USER, "revision": 2 if claimed else 1, "broadcastRevision": 0, "cursor": "claimed" if claimed else "unclaimed", "serverTime": "2026-10-16T12:00:08Z" if claimed else "2026-10-16T12:00:06Z", "pollAfterSeconds": 120, "unchanged": false, "entries": [{"id": ENTRY, "kind": "message", "type": "achievement", "reference": "manual_hidden", "textKey": "horizon.achievement.unlocked", "parameters": {"key": "manual_hidden"}, "createdAt": "2026-10-16T12:00:00Z", "expiresAt": "2026-11-15T12:00:00Z", "overdue": false, "read": claimed, "claimed": claimed, "attachment": {"values": [{"key": "coins", "amount": 13}]}}], "counts": {}, "limits": {"targeted": 10, "broadcasts": 10}}
