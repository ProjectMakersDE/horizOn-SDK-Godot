extends SceneTree
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_marketplace.gd")
const PROJECT := "10000000-0000-4000-8000-000000001015"
const USER := "20000000-0000-4000-8000-000000001015"
const BUYER := "30000000-0000-4000-8000-000000001015"
const INSTANCE := "40000000-0000-4000-8000-000000001015"
const LISTING := "50000000-0000-4000-8000-000000001015"
const OPERATION := "60000000-0000-4000-8000-000000001015"
const TIME := "2026-10-17T12:00:00.000Z"
var checks: int = 0
func check(value: bool) -> void:
	checks += 1
	assert(value, "Marketplace policy check %d" % checks)
func bounds() -> Dictionary:
	return {"openListingsPerPlayer": 250, "retainedListingsPerProject": 12000, "receiptsPerPlayer": 160, "historyPerPlayer": 180, "projectWritesPerMinute": 200, "playerWriteIntervalMillis": 1000, "minDurationSeconds": 300, "maxDurationSeconds": 604800, "terminalRetentionSeconds": 604800, "operationRetentionSeconds": 2592000, "queryCandidates": 256, "pageSize": 50}
func row() -> Dictionary:
	return {"id": LISTING, "revision": 1, "sellerId": USER, "buyerId": null, "returnOwnerId": USER, "item": {"instanceId": INSTANCE, "itemKey": "hat", "properties": {"power": 9007199254740991, "label": "雪/😀"}, "equipped": false, "createdAt": TIME}, "itemReference": {"instanceId": INSTANCE, "itemKey": "hat"}, "currencyKey": "1coin.gold", "price": 101, "feeBps": 333, "feeAmount": 3, "sellerNet": 98, "status": "active", "createdAt": TIME, "expiresAt": "2026-10-18T12:00:00.000Z", "terminalAt": null, "returnEntryId": null, "ownerUnavailable": false}
func body() -> Dictionary:
	return {"userId": USER, "operationId": OPERATION, "issuedAt": TIME, "instanceId": INSTANCE, "expectedInventoryRevision": 9, "expectedConfigRevision": 7, "price": 101, "durationSeconds": 300}
func record() -> Dictionary:
	return {"operationId": OPERATION, "issuedAt": TIME, "kind": "create", "listingId": LISTING, "listingRevision": 1, "recordedAt": TIME, "itemReference": {"instanceId": INSTANCE, "itemKey": "hat"}, "currencyKey": "1coin.gold", "price": 101, "feeAmount": 3, "sellerNet": 98}
func _initialize() -> void:
	if "lease-child" in OS.get_cmdline_user_args():
		var acquired: bool = Pending.acquire_send(PROJECT, USER)
		if acquired: Pending.release_send(PROJECT, USER)
		print("Marketplace second process send blocked=" + str(not acquired))
		quit(1 if acquired else 0)
		return
	check(Models.milliseconds(TIME) >= 0)
	check(Models.milliseconds("2026-02-31T12:00:00.000Z") == -1)
	check(Models.milliseconds("2026-10-17T12:00:00Z") == -1)
	check(Models.timestamp(0) == "1970-01-01T00:00:00.000Z")
	check(Models.uuid(Models.new_uuid()))
	check(Models.valid_intent("create", body()))
	for invalid: Variant in [1.0, -1, 9007199254740992, "1"]:
		var request: Dictionary = body(); request.expectedInventoryRevision = invalid
		check(not Models.valid_intent("create", request))
	for token: String in ["-0", "1.0", "1e3", "9007199254740992"]:
		check(Models.parse('{"revision":' + token + '}').is_empty())
	check(Models.parse('{"revision":1,"revision":2}').is_empty())
	check(Models.parse('{"label":"\\ud800"}').is_empty())
	check(Models._fee(9007199254740991, 10000) == 9007199254740991)
	check(not Models.listing(row()).is_empty())
	var sold: Dictionary = row(); sold.revision = 2; sold.item = null; sold.buyerId = BUYER; sold.status = "sold"; sold.terminalAt = TIME
	check(not Models.decode({"receipt": record(), "listing": sold, "replayed": true, "serverTime": TIME}, "create", USER, body()).is_empty())
	check(Models.decode({"receipt": record(), "listing": sold, "replayed": false, "serverTime": TIME}, "create", USER, body()).is_empty())
	check(not Models.decode({"receipt": record(), "listing": null, "replayed": true, "serverTime": TIME}, "create", USER, body()).is_empty())
	var changed: Dictionary = body(); changed.price = 102
	check(Models.decode({"receipt": record(), "listing": sold, "replayed": true, "serverTime": TIME}, "create", USER, changed).is_empty())
	for field: String in ["openListingsPerPlayer", "retainedListingsPerProject", "receiptsPerPlayer", "historyPerPlayer", "projectWritesPerMinute"]:
		var high: Dictionary = bounds(); high[field] = 2147483647
		check(not Models.limits(high).is_empty())
		for invalid: Variant in [0, -1, 2147483648, 1.0, "5"]:
			high[field] = invalid
			check(Models.limits(high).is_empty())
	var pending: Dictionary = {"scope": JSON.stringify([PROJECT, USER]).sha256_text(), "kind": "create", "listingId": "", "body": body(), "phase": "intent"}
	check(Pending.store(PROJECT, USER, pending))
	check(Pending.load_pending(PROJECT, USER).pending == pending)
	check(not Pending.store(PROJECT, USER, pending))
	check(not Pending.confirm(PROJECT, USER, pending))
	check(Pending.acquire_send(PROJECT, USER))
	var output: Array = []
	check(OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/marketplace_policy_test.gd", "--", "lease-child"], output, true) == 0)
	Pending.release_send(PROJECT, USER)
	var confirmed: Dictionary = pending.duplicate(true); confirmed.phase = "confirmed"; confirmed.confirmed = {"kind": "create", "operationId": OPERATION, "listingId": LISTING}
	check(Pending.store(PROJECT, USER, confirmed, pending))
	check(not Pending.confirm(PROJECT, USER, pending))
	check(Pending.confirm(PROJECT, USER, confirmed))
	check(Pending.load_pending(PROJECT, USER).pending.is_empty())
	print("PASS Marketplace policy: %d checks, exact replay/retained listing/Int32/lossless values and real second-process send lease" % checks)
	print("MARKETPLACE_USERDIR " + OS.get_user_data_dir())
	quit(0)
