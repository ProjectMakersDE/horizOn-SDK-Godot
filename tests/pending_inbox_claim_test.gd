extends SceneTree
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_inbox_claim.gd")
const Sample = preload("res://addons/horizon_sdk/examples/features/inbox_example.gd")
const USER := "00000000-0000-4000-8000-000000001006"
const ENTRY := "message:00000000-0000-4000-8000-000000001006"
const OTHER := "message:00000000-0000-4000-8000-000000001007"
const PROJECT := "inbox-example-project"

class FakeAuth extends RefCounted:
	var signed: bool = true
	var user: Dictionary = {"userId": USER, "accessToken": "inbox-example-session"}
	func isSignedIn() -> bool: return signed
	func getCurrentUser() -> Dictionary: return user

class FakeInbox extends RefCounted:
	var snapshot: Dictionary = {}
	var calls: Array = []
	var response: Dictionary = {"success": false, "data": {}, "errorCode": "NETWORK_ERROR", "error": "uncertain"}
	var before_reply: Callable
	func getCurrentInbox() -> Dictionary: return snapshot.duplicate(true)
	func claim(user_id: String, entry_id: String) -> Dictionary:
		assert(Pending.load_pending(PROJECT, user_id).pending == {"userId": user_id, "entryId": entry_id}, "The exact intent must be durable before HTTP")
		calls.append({"userId": user_id, "entryId": entry_id})
		if before_reply.is_valid(): before_reply.call()
		return response.duplicate(true)

class FakeHorizon extends Node:
	var auth: FakeAuth = FakeAuth.new()
	var inbox: FakeInbox = FakeInbox.new()
	var _http: HorizonHttpClient = HorizonHttpClient.new()
	func _exit_tree() -> void: _http.free()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var horizon := FakeHorizon.new()
	horizon.name = "Horizon"
	root.add_child(horizon)
	horizon._http.apiKey = PROJECT
	horizon._http.sessionToken = "inbox-example-session"
	horizon._http.activeHost = "https://one.invalid"
	var sample: Node = Sample.new()
	root.add_child(sample)
	var unclaimed: Dictionary = {"id": ENTRY, "claimed": false, "attachment": {"values": [{"key": "coins", "amount": 3}]}}
	var claimed: Dictionary = unclaimed.duplicate(true)
	claimed.claimed = true
	var invalid: Array[Dictionary] = [{}, {"userId": "another-player", "entries": [unclaimed]}, {"userId": USER, "entries": []}]
	for change: Dictionary in [{"id": OTHER}, {"claimed": true}, {"claimed": 0}, {"attachment": null}, {"attachment": {}}, {"attachment": {"values": []}}]:
		var entry: Dictionary = unclaimed.duplicate(true)
		entry.merge(change, true)
		invalid.append({"userId": USER, "entries": [entry]})
	for snapshot: Dictionary in invalid:
		horizon.inbox.snapshot = snapshot
		assert((await sample.claim_selected_entry(ENTRY)).errorCode == "ENTRY_NOT_CLAIMABLE")
		assert(Pending.load_pending(PROJECT, USER).pending.is_empty() and horizon.inbox.calls.is_empty(), "A nonclaimable ID must never occupy the slot or reach HTTP")
	horizon.auth.signed = false
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "SESSION_REQUIRED")
	horizon.auth.signed = true
	horizon._http.sessionToken = "another-session"
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "SESSION_REQUIRED" and horizon.inbox.calls.is_empty(), "A mismatched HTTP session cannot reserve a new claim")
	horizon._http.sessionToken = "inbox-example-session"
	horizon.inbox.snapshot = {"userId": USER, "entries": [unclaimed]}
	var file: String = Pending.path(PROJECT, USER)
	var lock: String = ProjectSettings.globalize_path(file + ".lock")
	assert(DirAccess.make_dir_absolute(lock) == OK)
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "PENDING_STORAGE_ERROR" and horizon.inbox.calls.is_empty(), "A concurrent storage writer must block HTTP")
	DirAccess.remove_absolute(lock)
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "NETWORK_ERROR")
	var original: Dictionary = {"userId": USER, "entryId": ENTRY}
	assert(Pending.load_pending(PROJECT, USER).pending == original)
	var before_locked_retry: int = horizon.inbox.calls.size()
	assert(DirAccess.make_dir_absolute(lock) == OK)
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "PENDING_STORAGE_ERROR" and horizon.inbox.calls.size() == before_locked_retry, "An active or abandoned lock also blocks an already persisted retry")
	DirAccess.remove_absolute(lock)
	assert(Pending.load_pending("another-project", USER).pending.is_empty())
	assert(Pending.load_pending(PROJECT, "another-player").pending.is_empty())
	assert(not Pending.confirm(PROJECT, {"userId": USER, "entryId": OTHER}), "A late different response cannot delete the original")
	horizon.inbox.snapshot = {"userId": USER, "entries": []}
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "NETWORK_ERROR", "Missing entry does not prevent original-ID recovery")
	horizon.inbox.snapshot = {"userId": USER, "entries": [claimed]}
	horizon._http.activeHost = "https://two.invalid"
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "NETWORK_ERROR", "Claimed snapshot and regional host change preserve the same original slot")
	var attempts: int = horizon.inbox.calls.size()
	assert((await sample.claim_selected_entry(OTHER)).errorCode == "PENDING_CLAIM" and horizon.inbox.calls.size() == attempts)
	var next := FileAccess.open(file + ".next", FileAccess.WRITE)
	next.store_var(original, false)
	next.close()
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "PENDING_STORAGE_ERROR" and horizon.inbox.calls.size() == attempts)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file + ".next"))
	horizon.inbox.response = {"success": true, "data": {"entryId": OTHER, "playerValues": {"values": [{"key": "coins", "balance": 3}]}}, "errorCode": "", "error": ""}
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "INVALID_RESPONSE" and Pending.load_pending(PROJECT, USER).pending == original, "A different success echo cannot confirm the original")
	horizon.inbox.response.data.entryId = ENTRY
	horizon.inbox.before_reply = func(): horizon._http.apiKey = "another-project"
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "STALE_RESPONSE" and Pending.load_pending(PROJECT, USER).pending == original, "A changed project never confirms the old original intent")
	horizon.inbox.before_reply = Callable()
	horizon._http.apiKey = PROJECT
	for field: String in ["host", "session", "project", "disconnect"]:
		horizon.inbox.before_reply = func():
			match field:
				"host":
					horizon._http.activeHost = "https://changed.invalid"
					horizon._http.activeHost = "https://two.invalid"
				"session":
					horizon._http.sessionToken = "another-session"
					horizon._http.sessionToken = "inbox-example-session"
				"project":
					horizon._http.apiKey = "another-project"
					horizon._http.apiKey = PROJECT
				"disconnect": horizon._http.sessionToken = ""
		assert((await sample.claim_selected_entry(ENTRY)).errorCode == "STALE_RESPONSE" and Pending.load_pending(PROJECT, USER).pending == original, "Synchronous completion context change or ABA preserves the original: " + field)
		horizon._http.sessionToken = "inbox-example-session"
	horizon.inbox.before_reply = Callable()
	assert((await sample.claim_selected_entry(ENTRY)).success and Pending.load_pending(PROJECT, USER).pending.is_empty())
	attempts = horizon.inbox.calls.size()
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "ENTRY_NOT_CLAIMABLE" and horizon.inbox.calls.size() == attempts, "A completed claimed entry cannot create a fresh pending slot")
	var corrupt := FileAccess.open(file, FileAccess.WRITE)
	corrupt.store_var({"corrupt": true}, false)
	corrupt.close()
	assert((await sample.claim_selected_entry(ENTRY)).errorCode == "PENDING_STORAGE_ERROR" and horizon.inbox.calls.size() == attempts)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	# The actual sample admits an item-only return using the same durable original-ID flow.
	var item: Dictionary = unclaimed.duplicate(true)
	item.attachment = {"values": [], "itemReturn": {"listingId": USER, "instanceId": USER, "itemKey": "sword"}}
	horizon.inbox.snapshot = {"userId": USER, "entries": [item]}
	horizon.inbox.response.data.items = [{"instanceId": USER, "itemKey": "sword"}]
	assert((await sample.claim_selected_entry(ENTRY)).success and Pending.load_pending(PROJECT, USER).pending.is_empty())
	sample.free()
	horizon.free()
	print("Godot Inbox sample: authorized claimable-entry admission, durable original retry, scope/concurrency/corruption guards and exact confirmation passed")
	quit(0)
