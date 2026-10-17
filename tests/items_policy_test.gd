extends SceneTree
const USER := "00000000-0000-4000-8000-000000001011"
const ITEM := "00000000-0000-4000-8000-000000003011"
class ControlledHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	var peak: int = 0
	var active: int = 0
	var on_start: Callable
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse: return await _respond(endpoint, {}, session, false)
	func postOnceAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse: return await _respond(endpoint, body, session, true)
	func postAsync(endpoint: String, body: Dictionary = {}, session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		assert(endpoint.begins_with("/api/v1/app/player-values"), "Items mutations must not use retrying POST")
		return await _respond(endpoint, body, session, false)
	func _respond(endpoint: String, body: Dictionary, session: bool, once: bool) -> HorizonNetworkResponse:
		assert(session and not responses.is_empty())
		calls.append({"endpoint": endpoint, "body": body.duplicate(true), "once": once})
		active += 1
		peak = maxi(peak, active)
		var next: Dictionary = responses.pop_front()
		if on_start.is_valid(): on_start.call()
		await get_tree().create_timer(next.get("delay", .005)).timeout
		active -= 1
		if next.has("failure"):
			var failure := HorizonNetworkResponse.failure("Refused", next.failure)
			failure.serverCode = next.get("code", "")
			return failure
		var response := HorizonNetworkResponse.success(next.data)
		response.rawBody = next.get("raw", JSON.stringify(next.data))
		return response

func _initialize() -> void:
	create_timer(25).timeout.connect(func():
		push_error("Items policy did not complete")
		quit(1))
	call_deferred("_run")
func _run() -> void:
	var parsed: Dictionary = HorizonItemModels.parse('{"min":-9007199254740991,"max":9007199254740991,"data":{"emoji":"\\ud83d\\ude00","line":"é/\\u2028\\u2029","null":null}}')
	assert(typeof(parsed.max) == TYPE_INT and parsed.max == 9007199254740991 and parsed.data.emoji == "😀")
	for invalid: String in ['{"x":1,}', '{"x":[1,]}', '{"x":1.0}', '{"x":1e0}', '{"x":01}', '{"x":9007199254740992}', '{"x":-9007199254740992}', '{"x":1,"\\u0078":2}', '{"x":"\\ud800"}', '{"x":"\\udc00"}', '{}{}', '{"x":1}//comment', '{"x":"\\q"}']:
		assert(HorizonItemModels.parse(invalid).is_empty(), invalid)
	var props: Dictionary = {"c": 9007199254740991, "b": "\b\t\n\f\r" + String.chr(31), "a": "é/😀"}
	assert(HorizonItemModels.canonical(props) == '{"a":"é/😀","b":"\\b\\t\\n\\f\\r\\u001f","c":9007199254740991}')
	assert(HorizonItemModels.canonical({"x": String.chr(0x2028) + String.chr(0x2029)}) == '{"x":"' + String.chr(0x2028) + String.chr(0x2029) + '"}')
	assert(HorizonItemModels.properties({"x": "a".repeat(248)}) != null and HorizonItemModels.properties({"x": "a".repeat(249)}) == null)
	for invalid: Variant in [{"x": null}, {"x": 1.0}, {"x": []}, {"x": {}}, {"$x": 1}]: assert(HorizonItemModels.properties(invalid) == null)
	var nul: Dictionary = HorizonItemModels.parse('{"x":"a\\u0000é/\\ud83d\\ude00\\u0000b","y":"ordinary"}')
	assert(nul.x is HorizonItemStringData and nul.x.getOriginalJson() == '"a\\u0000é/\\ud83d\\ude00\\u0000b"')
	assert(nul.x.getJson() == '"a\\u0000é/😀\\u0000b"' and nul.x.getDisplayPreview() == "a\\u0000é/😀\\u0000b")
	assert(nul.x.getUtf8ByteCount() == 11 and nul.y == "ordinary" and HorizonItemModels.properties(nul) != null)
	var boundary_template: Dictionary = catalog(1, 1).definitions[0]
	boundary_template.baseProperties.clear()
	boundary_template.propertyRules.clear()
	for index: int in range(16):
		var name: String = "propkey_%02d" % index
		boundary_template.baseProperties[name] = 0
		boundary_template.propertyRules.append({"key":name,"min":-HorizonItemModels.MAX,"max":HorizonItemModels.MAX,"maxChangePerCall":HorizonItemModels.MAX})
	boundary_template.name = "a".repeat(2048 - HorizonItemModels.canonical(boundary_template).to_utf8_buffer().size() + boundary_template.name.length())
	assert(HorizonItemModels.canonical(boundary_template).to_utf8_buffer().size() == 2048 and not HorizonItemModels.template(boundary_template).is_empty())
	boundary_template.name += "a"
	assert(HorizonItemModels.canonical(boundary_template).to_utf8_buffer().size() == 2049 and HorizonItemModels.template(boundary_template).is_empty())
	var http := ControlledHttp.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.activeHost = "https://one.invalid"
	http.apiKey = "items-project"
	http.sessionToken = "items-session"
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var values := HorizonPlayerValues.new()
	values.initialize(http, auth)
	var items := HorizonItems.new()
	items.initialize(http, auth, values)
	http.responses = [{"data": snapshot(1, 1)}]
	var result: Dictionary = await items.getInventory(USER)
	assert(result.success and typeof(result.data.instances[0].properties.power) == TYPE_INT)
	result.data.instances[0].properties.power = 0
	assert(items.getCurrentInventory().instances[0].properties.power == 9007199254740991)
	var count: int = http.calls.size()
	for bad: Variant in [-1, 1.0, "1", true, null, 9007199254740992]: assert((await items.setEquipped(USER, ITEM, bad, true)).errorCode == "INVALID_REQUEST")
	for bad: Variant in [[], [{"key":"power","amount":0}], [{"key":"power","amount":1.0}], [{"key":"power","amount":1},{"key":"power","amount":1}], [{"key":"bad.key","amount":1}]]: assert((await items.adjustProperties(USER, ITEM, 1, bad)).errorCode == "INVALID_REQUEST")
	assert((await items.setEquipped(USER, ITEM, 1, "true")).errorCode == "INVALID_REQUEST" and http.calls.size() == count)
	for wire: String in ['{"revision":1.0}', '{"revision":1e0}', '{"revision":"1"}', '{"revision":1,"revi\\u0073ion":1}', '{"properties":{"power":1.0}}']:
		http.responses = [{"data": snapshot(2, 2), "raw": wire}]
		assert((await items.getInventory(USER)).errorCode == "INVALID_RESPONSE" and items.getCurrentInventory().revision == 1)
	var bad: Dictionary = snapshot(2, 2)
	bad.instances.append(bad.instances[0].duplicate(true))
	http.responses = [{"data": bad}]
	assert((await items.getInventory(USER)).errorCode == "INVALID_RESPONSE" and items.getCurrentInventory().revision == 1)
	var page: Dictionary = catalog(5, 3)
	http.responses = [{"data": page}]
	assert((await items.getCatalog(USER, "", 1)).data.nextAfterKey == "sword")
	assert(http.calls[-1].endpoint.ends_with("?userId=" + USER + "&limit=1"))
	page.nextAfterKey = null
	http.responses = [{"data": page}]
	assert((await items.getCatalog(USER, "sword", 1, 5)).errorCode == "INVALID_RESPONSE", "A repeated/nonadvancing page is invalid")
	# Retained over-limit inventory remains available after downgrade.
	var retained: Dictionary = snapshot(2, 4)
	retained.limits.inventory = 1
	retained.instances.append(retained.instances[0].duplicate(true))
	retained.instances[1].instanceId = "00000000-0000-4000-8000-000000003012"
	http.responses = [{"data": retained}]
	assert((await items.getInventory(USER)).data.instances.size() == 2)
	items.clearCache()
	http.responses = [{"data": snapshot(1, 5)}]
	assert((await items.getInventory(USER)).errorCode == "STALE_RESPONSE", "Clear keeps same-player floors")
	for boundary: String in ["host", "project", "session"]:
		auth.signout_completed.emit()
		http.responses = [{"data": snapshot(1, 1), "delay": .08}]
		http.on_start = func():
			if boundary == "host":
				http.activeHost = "https://two.invalid"
				http.activeHost = "https://one.invalid"
			elif boundary == "project":
				http.apiKey = "other"
				http.apiKey = "items-project"
			else:
				http.sessionToken = "other"
				http.sessionToken = "items-session"
		assert((await items.getInventory(USER)).errorCode == "STALE_RESPONSE" and items.getCurrentInventory().is_empty())
		http.on_start = Callable()
	# Concurrent callers serialize while retaining caller-owned original values before waiting.
	auth.signout_completed.emit()
	http.responses = [{"data":snapshot(1,1),"delay":.1},{"failure":409,"code":"REVISION_CONFLICT"}]
	var first: Dictionary = {}
	var second: Dictionary = {}
	var changes: Array = [{"key":"power","amount":1}]
	_load(items, first)
	await create_timer(.02).timeout
	_adjust(items, changes, second)
	changes[0].amount = 99
	await create_timer(.2).timeout
	assert(first.result.success and second.result.errorCode == "REVISION_CONFLICT" and http.peak == 1 and http.calls[-1].body.changes[0].amount == 1 and http.calls[-1].body.expectedRevision == 0)
	http.responses = [{"data":snapshot(2,2),"delay":.1}]
	first.clear();second.clear()
	count = http.calls.size()
	_load(items,first)
	await create_timer(.02).timeout
	_load(items,second)
	items.clearCache()
	await create_timer(.15).timeout
	assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and http.calls.size() == count+1)
	# Successful exact-revision mutations replace full state; no local numeric synthesis.
	auth.signout_completed.emit()
	http.responses = [{"data": snapshot(4, 4)}]
	assert((await items.getInventory(USER)).success)
	var equipped: Dictionary = snapshot(5, 5)
	equipped.instances[0].equipped = true
	http.responses = [{"data": equipped}]
	assert((await items.setEquipped(USER, ITEM, 4, true)).success and http.calls[-1].once)
	var adjusted: Dictionary = snapshot(6, 6)
	adjusted.instances[0].properties.power = 8
	http.responses = [{"data": adjusted}]
	assert((await items.adjustProperties(USER, ITEM, 5, [{"key":"power","amount":-1}])).data.instances[0].properties.power == 8)
	var discarded: Dictionary = snapshot(7, 7)
	discarded.instances.clear()
	http.responses = [{"data": discarded}]
	assert((await items.discardItem(USER, ITEM, 6)).data.instances.is_empty())
	var wrong: Dictionary = snapshot(9, 8)
	http.responses = [{"data": wrong}]
	assert((await items.setEquipped(USER, ITEM, 7, true)).errorCode == "INVALID_RESPONSE" and items.getCurrentInventory().is_empty(), "Wrong revision/effect cannot confirm a mutation")
	# Response callbacks cannot return success after invalidation.
	http.responses = [{"data": snapshot(8, 8)}]
	var clear: Callable = func(_data: Dictionary): items.clearCache()
	items.inventory_loaded.connect(clear)
	assert((await items.getInventory(USER)).errorCode == "STALE_RESPONSE" and items.getCurrentInventory().is_empty())
	items.inventory_loaded.disconnect(clear)
	# PV original item references and offer quantities are additive and strict.
	var state: Dictionary = value_state()
	http.responses = [{"data": state}]
	assert((await values.getState(USER)).success)
	state.operation.items = [{"instanceId": ITEM, "itemKey": "sword"}]
	http.responses = [{"data": state}]
	result = await values.purchase(USER, "sword", "1792152000000:00000000-0000-4000-8000-000000004011")
	assert(result.success and result.state.operation.items[0].instanceId == ITEM and items.getCurrentInventory().is_empty())
	var offers: Dictionary = {"definitionVersion":1,"serverTime":"2026-10-16T12:00:10Z","definitions":[],"offers":[{"key":"sword","active":true,"costs":[{"key":"coins","amount":5}],"rewards":[],"itemRewards":[{"itemKey":"sword","quantity":1}]}]}
	http.responses = [{"data": offers, "raw": JSON.stringify(offers).replace('"quantity":1', '"quantity":1.0')}]
	assert(not (await values.getOffers(USER)).success and values.getCurrentOffers().is_empty())
	http.responses = [{"data": offers}]
	assert((await values.getOffers(USER)).data.offers[0].itemRewards[0].quantity == 1)
	var before: int = http.calls.size()
	var change: Callable = func():
		http.apiKey = "other"
		http.apiKey = "items-project"
	values.item_inventory_invalidated.connect(change)
	assert((await values.purchase(USER, "sword", "1792152000000:00000000-0000-4000-8000-000000004012")).errorCode == "STALE_RESPONSE" and http.calls.size() == before, "Invalidation callback ABA cannot retarget a purchase")
	values.item_inventory_invalidated.disconnect(change)
	assert(HorizonItemModels.limits({"catalog":2147483647,"inventory":2147483647,"receipts":2147483647}).size() == 3)
	for field: String in ["catalog", "inventory", "receipts"]:
		for invalid: Variant in [0, -1, 2147483648, 1.0, "250"]:
			var invalid_limits: Dictionary = {"catalog":6000,"inventory":250,"receipts":80}
			invalid_limits[field] = invalid
			assert(HorizonItemModels.limits(invalid_limits).is_empty())
	var physical: Dictionary = catalog(1, 10)
	physical.total = 65536
	assert(not HorizonItemModels.page(physical, "", 1).is_empty())
	physical.total = 65537
	assert(HorizonItemModels.page(physical, "", 1).is_empty(), "UInt16 lifetime slots remain a technical encoding limit")
	print("Godot Items policy: original strict integers/canonical Unicode, properties/pages/downgrades, cache floors/context ABA and additive PV receipts/rewards passed")
	http.queue_free()
	quit(0)

func snapshot(revision: int, tick: int) -> Dictionary:
	return {"userId":USER,"revision":revision,"instances":[{"instanceId":ITEM,"itemKey":"sword","properties":{"power":9007199254740991,"label":"é/😀"},"equipped":false,"createdAt":"2026-10-16T12:00:00Z"}],"limits":{"catalog":5000,"inventory":150,"receipts":50},"serverTime":"2026-10-16T12:00:%02dZ" % tick}
func catalog(revision: int, tick: int) -> Dictionary:
	return {"revision":revision,"definitions":[{"key":"sword","name":"Sword","type":"weapon","rarity":"common","active":true,"baseProperties":{"power":9},"propertyRules":[{"key":"power","min":0,"max":10,"maxChangePerCall":1}]}],"nextAfterKey":"sword","total":2,"limits":{"catalog":5000,"inventory":150,"receipts":50},"serverTime":"2026-10-16T12:00:%02dZ" % tick}
func value_state() -> Dictionary:
	return {"userId":USER,"revision":1,"definitionVersion":1,"values":[{"key":"coins","balance":95,"earnedToday":0,"dailyCap":null}],"operationWindow":{"serverTime":"2026-10-16T12:00:10Z","oldestAcceptedAt":"2026-09-16T12:00:00Z"},"operation":{"operationId":"1792152000000:00000000-0000-4000-8000-000000004011","replayed":true,"applied":[],"items":[]}}

func _load(items: HorizonItems, box: Dictionary) -> void: box.result = await items.getInventory(USER)
func _adjust(items: HorizonItems, changes: Array, box: Dictionary) -> void: box.result = await items.adjustProperties(USER, ITEM, 0, changes)
