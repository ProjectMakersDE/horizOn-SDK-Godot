extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/items_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_intent.gd")
const U := "00000000-0000-4000-8000-000000001111"
const I := "00000000-0000-4000-8000-000000003111"
const OP := "1792152000000:00000000-0000-4000-8000-000000004111"
class FakeAuth extends RefCounted:
	var signed: bool = true
	var user: Dictionary = {"userId":U,"accessToken":"sample-session"}
	func isSignedIn() -> bool: return signed
	func getCurrentUser() -> Dictionary: return user
class FakeValues extends RefCounted:
	var owner: Node
	var offer: Dictionary = {"key":"sword","active":true,"costs":[{"key":"coins","amount":5}],"rewards":[],"itemRewards":[{"itemKey":"sword","quantity":1}]}
	var calls: Array = []
	var before_reply: Callable
	var response: Dictionary = {"success":false,"errorCode":"NETWORK_ERROR","error":"uncertain"}
	func getOffers(_user: String) -> Dictionary: return {"success":true,"data":{"offers":[offer.duplicate(true)]}}
	func createOperationId() -> String: return OP
	func purchase(user: String, key: String, operation: String) -> Dictionary:
		var stub: Node = Sample.new()
		var path: String = stub._path(owner, "purchase")
		stub.free()
		var pending: Dictionary = Pending.load_pending(path).pending
		assert(pending.userId == user and pending.offerKey == key and pending.operationId == operation and pending.phase == "purchase", "Original persisted before HTTP")
		calls.append({"userId":user,"offerKey":key,"operationId":operation})
		if before_reply.is_valid(): before_reply.call()
		return response.duplicate(true)
class FakeItems extends RefCounted:
	var owner: Node
	var current: Dictionary = {}
	var response: Dictionary = {"success":false,"errorCode":"NETWORK_ERROR","error":"uncertain"}
	var calls: Array = []
	func getCurrentInventory() -> Dictionary: return current.duplicate(true)
	func getInventory(_user: String) -> Dictionary: return response.duplicate(true)
	func setEquipped(user: String, instance: String, revision: Variant, equipped: bool) -> Dictionary: return _action("equip",user,instance,revision,{"equipped":equipped})
	func adjustProperties(user: String, instance: String, revision: Variant, changes: Array) -> Dictionary: return _action("adjust",user,instance,revision,{"changes":changes})
	func discardItem(user: String, instance: String, revision: Variant) -> Dictionary: return _action("discard",user,instance,revision,{})
	func _action(action: String,user: String,instance: String,revision: Variant,payload: Dictionary) -> Dictionary:
		var stub: Node = Sample.new()
		var path: String = stub._path(owner,"action")
		stub.free()
		var pending: Dictionary = Pending.load_pending(path).pending
		assert(pending.userId == user and pending.instanceId == instance and pending.expectedRevision == revision and pending.payload == payload and pending.action == action)
		calls.append(pending.duplicate(true))
		current.clear()
		return response.duplicate(true)
class FakeHorizon extends Node:
	var auth := FakeAuth.new()
	var playerValues := FakeValues.new()
	var items := FakeItems.new()
	var _http := HorizonHttpClient.new()
	func _exit_tree() -> void: _http.free()
class FailingStore extends Sample:
	func _store(_path: String,_value: Dictionary,_expected: Dictionary = {}) -> bool: return false
class FailingConfirm extends Sample:
	func _remove(_path: String,_expected: Dictionary) -> bool: return false
func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(1))
	call_deferred("_run")
func _run() -> void:
	var horizon := FakeHorizon.new()
	horizon.name = "Horizon"
	horizon._http.apiKey = "items-sample-project"
	horizon._http.sessionToken = "sample-session"
	horizon._http.activeHost = "https://one.invalid"
	horizon.playerValues.owner = horizon
	horizon.items.owner = horizon
	root.add_child(horizon)
	var sample: Node = Sample.new()
	root.add_child(sample)
	var path: String = sample._path(horizon,"purchase")
	var action: String = sample._path(horizon,"action")
	assert(not FileAccess.file_exists(path) and not FileAccess.file_exists(action))
	assert((await sample.purchase_reviewed_offer()).errorCode == "REVIEW_REQUIRED")
	horizon.auth.signed = false
	assert((await sample.review_offer("sword")).errorCode == "SESSION_REQUIRED")
	horizon.auth.signed = true
	assert((await sample.review_offer("sword")).success)
	horizon.playerValues.offer.costs[0].amount = 6
	assert((await sample.purchase_reviewed_offer()).errorCode == "OFFER_CHANGED" and horizon.playerValues.calls.is_empty())
	var failing: Node = FailingStore.new()
	root.add_child(failing)
	assert((await failing.review_offer("sword")).success)
	assert((await failing.purchase_reviewed_offer()).errorCode == "PENDING_STORAGE_ERROR" and horizon.playerValues.calls.is_empty())
	failing.free()
	# Interrupted writes and an existing process lock block both kinds of new intent.
	var next := FileAccess.open(action+".next",FileAccess.WRITE)
	next.store_var({"partial":true},false);next.close()
	assert((await sample.purchase_reviewed_offer()).errorCode == "PENDING_STORAGE_ERROR")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(action+".next"))
	var lock: String = ProjectSettings.globalize_path(Pending._lock(path)+".lock")
	assert(DirAccess.make_dir_absolute(lock) == OK)
	assert((await sample.purchase_reviewed_offer()).errorCode == "PENDING_STORAGE_ERROR" and horizon.playerValues.calls.is_empty())
	DirAccess.remove_absolute(lock)
	assert((await sample.purchase_reviewed_offer()).errorCode == "NETWORK_ERROR")
	var original: Dictionary = Pending.load_pending(path).pending
	assert(original.operationId == OP)
	assert((await sample.purchase_reviewed_offer()).errorCode == "PENDING_PURCHASE")
	assert(not Pending.store(action,{"action":"other"}), "Concurrent sample cannot replace a purchase with an action")
	assert(not Pending.confirm(path,dict_wrong(original)))
	horizon._http.activeHost = "https://two.invalid"
	assert(sample._path(horizon,"purchase") == path)
	assert((await sample.retry_pending_purchase()).errorCode == "NETWORK_ERROR" and horizon.playerValues.calls[1] == horizon.playerValues.calls[0])
	horizon.playerValues.response = {"success":false,"errorCode":"OPERATION_EXPIRED","error":"expired original"}
	assert((await sample.retry_pending_purchase()).errorCode == "OPERATION_EXPIRED" and Pending.load_pending(path).pending == original)
	horizon.playerValues.response = {"success":true,"state":{"operation":{"operationId":OP,"items":[{"instanceId":I,"itemKey":"sword"}]}}}
	for wrong: Variant in [null, "", "1792152000000:00000000-0000-4000-8000-000000004112"]:
		horizon.playerValues.response.state.operation.operationId = wrong
		assert((await sample.retry_pending_purchase()).errorCode == "INVALID_RESPONSE" and Pending.load_pending(path).pending == original, "Unrelated/missing receipt never confirms a purchase")
	horizon.playerValues.response.state.operation.erase("operationId")
	assert((await sample.retry_pending_purchase()).errorCode == "INVALID_RESPONSE" and Pending.load_pending(path).pending == original)
	horizon.playerValues.response.state.operation.operationId = OP
	horizon.playerValues.before_reply = func():
		horizon._http.apiKey = "other"
		horizon._http.apiKey = "items-sample-project"
	assert((await sample.retry_pending_purchase()).errorCode == "STALE_RESPONSE" and Pending.load_pending(path).pending == original)
	horizon.playerValues.before_reply = Callable()
	assert((await sample.retry_pending_purchase()).errorCode == "NETWORK_ERROR")
	var confirmed: Dictionary = Pending.load_pending(path).pending
	assert(confirmed.phase == "inventory")
	var attempts: int = horizon.playerValues.calls.size()
	sample.free()
	sample = Sample.new();root.add_child(sample)
	horizon.items.response = {"success":true,"data":{"userId":U,"revision":1,"instances":[{"instanceId":I,"itemKey":"sword"}]}}
	assert((await sample.retry_pending_purchase()).success and horizon.playerValues.calls.size() == attempts and not FileAccess.file_exists(path), "Restart after confirmed purchase uses GET only")
	# Partial/corrupt data never authorizes a replacement ID or delta.
	var corrupt := FileAccess.open(path,FileAccess.WRITE)
	corrupt.store_var({"userId":U},false);corrupt.close()
	assert((await sample.retry_pending_purchase()).errorCode == "PENDING_STORAGE_ERROR")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	horizon.items.response = {"success":false,"errorCode":"NETWORK_ERROR","error":"uncertain"}
	horizon.items.current = {"userId":U,"revision":1,"instances":[{"instanceId":I}]}
	assert((await sample.equip_item(I,0,true)).errorCode == "REVIEW_REQUIRED" and horizon.items.calls.is_empty())
	assert((await sample.equip_item(I,1,true)).errorCode == "NETWORK_ERROR")
	var pending_action: Dictionary = Pending.load_pending(action).pending
	assert((await sample.discard_item(I,1)).errorCode == "PENDING_ACTION" and horizon.items.calls.size() == 1)
	assert(sample.acknowledge_action_reconciliation().errorCode == "REVIEW_REQUIRED")
	horizon.items.current = {"userId":U,"revision":2,"instances":[{"instanceId":I}]}
	failing = FailingConfirm.new();root.add_child(failing)
	assert(failing.acknowledge_action_reconciliation().errorCode == "PENDING_STORAGE_ERROR" and Pending.load_pending(action).pending == pending_action)
	failing.free()
	assert(sample.acknowledge_action_reconciliation().success and not FileAccess.file_exists(action))
	# A late completion cannot remove another durable original.
	assert(Pending.store(path, original))
	assert(not Pending.confirm(path,confirmed) and Pending.load_pending(path).pending == original)
	assert(Pending.confirm(path,original))
	print("Godot Items actual sample: durable original before send, changed-offer reconfirmation, storage/cross-process/scope/corruption/expiry guards, inventory-only restart recovery and explicit action reconciliation passed")
	sample.free();horizon.free();quit(0)
func dict_wrong(original: Dictionary) -> Dictionary:
	var changed: Dictionary = original.duplicate(true)
	changed.operationId = "1792152000000:00000000-0000-4000-8000-000000004112"
	return changed
