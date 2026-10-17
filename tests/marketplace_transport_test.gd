extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/marketplace_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_marketplace.gd")
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
const PROJECT := "10000000-0000-4000-8000-000000001015"
const SELLER := "20000000-0000-4000-8000-000000001015"
const BUYER := "30000000-0000-4000-8000-000000001015"
const OTHER := "30000000-0000-4000-8000-000000001016"
const INSTANCE := "40000000-0000-4000-8000-000000001015"
const LISTING := "50000000-0000-4000-8000-000000001015"
const L2 := "50000000-0000-4000-8000-000000001016"
const L3 := "50000000-0000-4000-8000-000000001017"
const I3 := "40000000-0000-4000-8000-000000001017"
const UNKNOWN := "60000000-0000-4000-8000-000000009999"
const ENTRY := "message:70000000-0000-3000-8000-000000001015"
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var items: HorizonItems
	var playerValues: HorizonPlayerValues
	var inbox: HorizonInbox
	var marketplace: HorizonMarketplace
var _old_result: Dictionary = {}
var _new_result: Dictionary = {}
var _busy_preserved: bool = false
var _aba_result: Dictionary = {}
var checks: int = 0
func check(value: bool) -> void:
	checks += 1
	assert(value, "Marketplace native HTTP check %d" % checks)
func _initialize() -> void:
	create_timer(230).timeout.connect(func() -> void:
		push_error("Marketplace native HTTP contract timed out")
		quit(1))
	call_deferred("_run")
func actor() -> Node:
	var sample: Node = Sample.new()
	sample.project_id = PROJECT
	root.add_child(sample)
	return sample
func player(h: FixtureHorizon, id: String) -> void:
	h._http.sessionToken = "market-" + ("seller" if id == SELLER else "buyer") + "-session"
	h.auth._currentUser.userId = id
	h.auth._currentUser.accessToken = h._http.sessionToken
func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.activeHost = "http://127.0.0.1:20115"
	http.apiKey = "market-fixture-key"
	http.maxRetryAttempts = 2
	http.retryDelaySeconds = .02
	http.connectionTimeoutSeconds = 5
	var h := FixtureHorizon.new()
	h.name = "Horizon"
	h._http = http
	h.auth = HorizonAuth.new()
	h.auth.initialize(http, logger)
	player(h, SELLER)
	h.items = HorizonItems.new()
	h.playerValues = HorizonPlayerValues.new()
	h.playerValues.initialize(http, h.auth)
	h.items.initialize(http, h.auth, h.playerValues)
	h.inbox = HorizonInbox.new()
	h.inbox.initialize(http, h.auth, h.playerValues)
	h.marketplace = HorizonMarketplace.new()
	h.marketplace.initialize(http, h.auth)
	root.add_child(h)
	var sample: Node = actor()
	check((await h.marketplace.getLimits(OTHER)).errorCode == "SESSION_FORBIDDEN")
	check((await h.marketplace.getListing(SELLER, "bad")).errorCode == "INVALID_REQUEST")
	check((await h.marketplace.getRules(SELLER, "hat", 1)).errorCode == "INVALID_REQUEST")
	check((await h.marketplace.queryListings(SELLER, "hat", 1, 200, "", 51)).errorCode == "INVALID_REQUEST")
	check((await sample.read_limits()).data.limits.retainedListingsPerProject == 12000)
	check((await h.marketplace.getRules(SELLER, "", 1)).data.nextCursor == "hat")
	check((await h.marketplace.getRules(SELLER, "hat", 1, 7)).data.rules[0].itemKey == "wand")
	var high: Dictionary = await sample.read_marketplace()
	check(high.success and high.data.state.openListings.size() == 2051 and high.data.state.history.size() == 151)
	check(high.data.state.limits.openListingsPerPlayer == 3000)
	var lower: Dictionary = await sample.read_marketplace()
	check(lower.success and lower.data.state.openListings.size() == 2051 and lower.data.state.history.size() == 151 and lower.data.state.limits.openListingsPerPlayer == 1)
	lower.data.state.openListings.clear()
	check(h.marketplace.getCurrent("state").state.openListings.size() == 2051)
	var empty_page: Dictionary = await h.marketplace.queryListings(SELLER, "hat", 1, 200, "", 1)
	check(empty_page.success and empty_page.data.listings.is_empty() and not empty_page.data.nextCursor.is_empty())
	var next_page: Dictionary = await h.marketplace.queryListings(SELLER, "hat", 1, 200, empty_page.data.nextCursor, 1)
	check(next_page.success and next_page.data.listings[0].id == LISTING)
	var point: Dictionary = await sample.read_listing(LISTING)
	check(point.success and point.data.listing.item.instanceId == INSTANCE)
	var original: Dictionary = point.data.listing.item.duplicate(true)
	check((await sample.read_inventory()).data.instances[0].instanceId == INSTANCE)
	check((await sample.read_rules_page()).success)
	var quote: Dictionary = sample.review_create(INSTANCE, 101, 300)
	check(quote.success and quote.data.feeAmount == 3 and quote.data.sellerNet == 98 and quote.data.currencyKey == "1coin.gold")
	if OS.get_environment("HORIZON_MARKETPLACE_DESTROY_DURING_SEND") == "1":
		sample.call_deferred("confirm_reviewed_trade")
		await create_timer(.04).timeout
		sample.free()
		await create_timer(.4).timeout
		check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Pending.path(PROJECT, SELLER) + ".sending")))
		sample = actor()
	else:
		check(not (await sample.confirm_reviewed_trade()).success)
	var saved: Dictionary = Pending.load_pending(PROJECT, SELLER).pending
	check(saved.phase == "intent" and Models.valid_intent("create", saved.body))
	check(not saved.has("item") and not saved.has("receipt"))
	sample.free()
	sample = actor()
	check(not (await sample.recover_original_operation()).success)
	var confirmed: Dictionary = Pending.load_pending(PROJECT, SELLER).pending
	check(confirmed.phase == "confirmed" and confirmed.confirmed.size() == 3 and confirmed.body == saved.body)
	check(not confirmed.confirmed.has("price") and not confirmed.confirmed.has("itemReference"))
	sample.free()
	sample = actor()
	var current: Dictionary = await sample.retry_pending()
	check(current.success and current.data.inventory.instances.is_empty() and current.data.playerValues.values[0].balance == 98)
	check(current.data.marketplace.history[0].status == "sold" and Pending.load_pending(PROJECT, SELLER).pending.is_empty())
	var replay: Dictionary = await h.marketplace.submitIntent("create", saved.body)
	check(replay.success and replay.data.replayed and replay.data.receipt.listingRevision == 1 and replay.data.listing.revision == 2 and replay.data.listing.item == null)
	check(h.marketplace.getCurrent("create").is_empty() and h.marketplace.getCurrent("operation").is_empty())
	var altered: Dictionary = saved.body.duplicate(true)
	altered.price = 102
	check((await h.marketplace.submitIntent("create", altered)).errorCode == "OPERATION_CONFLICT")
	var unknown: Dictionary = saved.duplicate(true)
	unknown.body.operationId = UNKNOWN
	check(Pending.store(PROJECT, SELLER, unknown))
	check((await sample.recover_original_operation()).errorCode == "OPERATION_NOT_FOUND")
	check(Pending.load_pending(PROJECT, SELLER).pending == unknown)
	# Fixture-only cleanup of its artificial unresolved file; no such deletion API is exposed by the sample.
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(Pending.path(PROJECT, SELLER))) == OK)
	player(h, BUYER)
	check(h.marketplace.getCurrent("state").is_empty())
	check((await sample.read_listing(L2)).success)
	check(sample.review_buy(L2).success)
	check(not (await sample.confirm_reviewed_trade()).success)
	var buyer_original: Dictionary = Pending.load_pending(PROJECT, BUYER).pending
	sample.free()
	sample = actor()
	var purchased: Dictionary = await sample.retry_pending()
	check(purchased.success and purchased.data.inventory.instances.is_empty())
	check(purchased.data.confirmed.operationId == buyer_original.body.operationId and Pending.load_pending(PROJECT, BUYER).pending.is_empty())
	check((await h.marketplace.buyListing(BUYER, LISTING, UNKNOWN, Models.timestamp(h.marketplace.getServerNow()), 1, 101, "1coin.gold")).errorCode == "LISTING_UNAVAILABLE")
	player(h, SELLER)
	check((await sample.read_listing(L3)).success)
	check(sample.review_cancel(L3).success)
	check((await sample.confirm_reviewed_trade()).success)
	check((await sample.retry_return_delivery(L3)).data.delivery == "pending")
	var delivered: Dictionary = await sample.retry_return_delivery(L3)
	check(delivered.data.delivery == "delivered" and delivered.data.listing.returnEntryId == ENTRY and delivered.data.listing.item.instanceId == I3)
	check((await sample.claim_return(ENTRY)).errorCode == "INVENTORY_FULL")
	var claimed: Dictionary = await sample.claim_return(ENTRY)
	check(claimed.success and not claimed.data.replayed and claimed.data.items[0].instanceId == I3)
	var inventory: Dictionary = await sample.read_inventory()
	check(inventory.data.instances.size() == 1 and inventory.data.instances[0].instanceId == I3 and inventory.data.instances[0].createdAt == original.createdAt)
	check(HorizonItemModels.canonical(inventory.data.instances[0].properties) == HorizonItemModels.canonical(original.properties))
	check((await h.items.discardItem(SELLER, I3, 11)).success)
	var claimed_again: Dictionary = await sample.claim_return(ENTRY)
	check(claimed_again.success and claimed_again.data.replayed and claimed_again.data.items[0].instanceId == I3)
	check((await sample.read_inventory()).data.instances.is_empty())
	check((await sample.retry_return_delivery(L3)).data.delivery == "returned")
	player(h, BUYER)
	check((await sample.read_listing(L3)).errorCode == "LISTING_NOT_FOUND")
	check((await sample.read_limits()).errorCode == "INVALID_RESPONSE")
	_old_read(h)
	await create_timer(.04).timeout
	h.marketplace.clearCache()
	_new_read(h)
	while _old_result.is_empty() or _new_result.is_empty(): await create_timer(.02).timeout
	check(_old_result.errorCode == "STALE_RESPONSE" and _new_result.success and _busy_preserved)
	check(h.marketplace.getCurrent("state").state.revision == 9)
	check((await sample.read_marketplace()).errorCode == "STALE_RESPONSE")
	_aba_read(h)
	await create_timer(.04).timeout
	http.sessionToken = "other-session"
	http.sessionToken = "market-buyer-session"
	while _aba_result.is_empty(): await create_timer(.02).timeout
	check(_aba_result.errorCode == "STALE_RESPONSE" and h.marketplace.getCurrent("state").is_empty())
	check(Pending.load_pending(PROJECT, SELLER).pending.is_empty() and Pending.load_pending(PROJECT, BUYER).pending.is_empty())
	print("PASS Marketplace native HTTP: %d checks/all10 routes,2051 retained opens+151 history,exact durable original retries,minimal success,original escrow claim/resale and context fences" % checks)
	quit(0)
func _old_read(h: FixtureHorizon) -> void:
	_old_result = await h.marketplace.getMarketplace(BUYER)
	_busy_preserved = (await h.marketplace.getLimits(BUYER)).errorCode == "REQUEST_IN_PROGRESS"
func _new_read(h: FixtureHorizon) -> void:
	_new_result = await h.marketplace.getMarketplace(BUYER)
func _aba_read(h: FixtureHorizon) -> void:
	_aba_result = await h.marketplace.getLimits(BUYER)
