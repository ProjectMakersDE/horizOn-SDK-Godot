extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/items_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_intent.gd")
const U := "00000000-0000-4000-8000-000000001011"
const I := "00000000-0000-4000-8000-000000003011"
const J := "00000000-0000-4000-8000-000000003012"
const R := 4294967296
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var items: HorizonItems
	var playerValues: HorizonPlayerValues
func _initialize() -> void:
	create_timer(25).timeout.connect(func():
		push_error("Items HTTP contract did not complete")
		quit(1))
	call_deferred("_run")
func _run() -> void:
	var http := HorizonHttpClient.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.activeHost = "http://127.0.0.1:20111"
	http.apiKey = "items-key"
	http.sessionToken = "items-session"
	http.maxRetryAttempts = 3
	http.retryDelaySeconds = .02
	http.connectionTimeoutSeconds = 1
	var horizon := FixtureHorizon.new()
	horizon.name = "Horizon"
	horizon._http = http
	horizon.auth = HorizonAuth.new()
	horizon.auth.initialize(http, logger)
	horizon.auth._currentUser.userId = U
	horizon.auth._currentUser.accessToken = http.sessionToken
	horizon.playerValues = HorizonPlayerValues.new()
	horizon.playerValues.initialize(http, horizon.auth)
	horizon.items = HorizonItems.new()
	horizon.items.initialize(http, horizon.auth, horizon.playerValues)
	root.add_child(horizon)
	var sample: Node = Sample.new()
	root.add_child(sample)
	assert((await sample.load_catalog_page()).data.definitions[0].key == "sword")
	assert((await sample.review_offer("sword")).success)
	assert((await sample.purchase_reviewed_offer()).errorCode == "OFFER_CHANGED")
	# No hidden transport retry for this fixture: stop after the deliberately uncertain purchase.
	http.maxRetryAttempts = 0
	assert((await sample.purchase_reviewed_offer()).errorCode == "HTTP_503")
	var path: String = sample._path(horizon, "purchase")
	var original: Dictionary = Pending.load_pending(path).pending
	assert(original.phase == "purchase" and not original.operationId.is_empty())
	sample.free()
	sample = Sample.new()
	root.add_child(sample)
	assert((await sample.retry_pending_purchase()).errorCode == "SESSION_REQUIRED")
	assert(Pending.load_pending(path).pending.phase == "inventory")
	var result: Dictionary = await sample.retry_pending_purchase()
	assert(result.success and result.data.originalItems[0].instanceId == I and not FileAccess.file_exists(path))
	var property: Variant = result.data.inventory.instances[0].properties.text
	assert(property is HorizonItemStringData and property.getJson() == '"a\\u0000é/😀\\u001f"' and property.getDisplayPreview() == "a\\u0000é/😀" + String.chr(31))
	assert(result.data.inventory.instances[1].properties.title == "ordinary" and result.data.inventory.instances[1].properties.max == 9007199254740991)
	http.maxRetryAttempts = 3
	assert((await sample.equip_item(I, R, true)).data.revision == R+1)
	assert((await sample.adjust_item(I, R+1, [{"key":"power","amount":1}])).data.instances[0].properties.power == 10)
	assert((await sample.discard_item(I, R+2)).data.instances.size() == 1)
	assert((await sample.equip_item(J, R+3, true)).errorCode == "HTTP_503")
	assert((await sample.equip_item(J, R+3, true)).errorCode == "PENDING_ACTION")
	assert((await sample.refresh_inventory()).data.revision == R+4)
	assert(sample.acknowledge_action_reconciliation().success)
	assert((await sample.discard_item(J, R+4)).errorCode == "RATE_LIMITED")
	assert((await sample.refresh_inventory()).data.revision == R+4)
	assert(sample.acknowledge_action_reconciliation().success)
	assert(not (await sample.adjust_item(J, R+4, [{"key":"max","amount":-1}])).success)
	assert((await sample.refresh_inventory()).data.revision == R+5)
	assert(sample.acknowledge_action_reconciliation().success)
	var expired: Dictionary = {"userId":U,"project":http.apiKey.sha256_text(),"offerKey":"sword","operationId":"1792152000000:00000000-0000-4000-8000-000000004011","phase":"purchase"}
	assert(Pending.store(path, expired))
	assert((await sample.retry_pending_purchase()).errorCode == "OPERATION_EXPIRED")
	assert(Pending.load_pending(path).pending == expired)
	assert(Pending.confirm(path, expired)) # Test fixture cleanup only; a game retains/reconciles this guard.
	await create_timer(1.8).timeout
	print("Godot actual Items example: catalog/review/price-change, persisted purchase/replay/inventory-only recovery, lossless NUL+Unicode/64-bit, equip/adjust/discard, original revisions and once-only uncertain actions passed")
	sample.free()
	horizon.free()
	http.queue_free()
	quit(0)
