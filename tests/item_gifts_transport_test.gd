extends SceneTree
const Quickstart = preload("res://addons/horizon_sdk/examples/features/item_gifts_quickstart.gd")
const Sample = preload("res://addons/horizon_sdk/examples/features/item_gifts_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_gift.gd")
const Models = preload("res://addons/horizon_sdk/models/item_gift_models.gd")
const PROJECT := "10000000-0000-4000-8000-000000001140"
const SENDER := "20000000-0000-4000-8000-000000001140"
const RECIPIENT := "30000000-0000-4000-8000-000000001140"
const OTHER := "30000000-0000-4000-8000-000000001141"
const INSTANCE := "40000000-0000-4000-8000-000000001140"
const I2 := "40000000-0000-4000-8000-000000001141"
const GIFT := "50000000-0000-4000-8000-000000001140"
const G2 := "50000000-0000-4000-8000-000000001141"
const UNKNOWN := "60000000-0000-4000-8000-000000009999"
const OFFER_ENTRY := "message:70000000-0000-3000-8000-000000001140"
const RETURN_ENTRY := "message:70000000-0000-3000-8000-000000001141"
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var items: HorizonItems
	var playerValues: HorizonPlayerValues
	var inbox: HorizonInbox
	var itemGifts: HorizonItemGifts
var checks: int = 0
var _send_result: Dictionary = {}
func check(value: bool) -> void:
	checks += 1
	assert(value, "Item Gifts native HTTP check %d" % checks)
func _initialize() -> void:
	create_timer(110).timeout.connect(func() -> void:
		push_error("Item Gifts native HTTP contract timed out")
		quit(1))
	call_deferred("_run")
func actor() -> Node:
	var sample: Node = Sample.new()
	sample.project_id = PROJECT
	root.add_child(sample)
	return sample
func player(h: FixtureHorizon, id: String) -> void:
	h._http.sessionToken = "gift-" + ("sender" if id == SENDER else "recipient") + "-session"
	h.auth._currentUser.userId = id
	h.auth._currentUser.accessToken = h._http.sessionToken
func _send(sample: Node) -> void:
	_send_result = await sample.confirm_reviewed_send()
func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.activeHost = "http://127.0.0.1:20140"
	http.apiKey = "gift-fixture-key"
	http.maxRetryAttempts = 2
	http.retryDelaySeconds = .02
	http.connectionTimeoutSeconds = 5
	var h := FixtureHorizon.new()
	h.name = "Horizon"
	h._http = http
	h.auth = HorizonAuth.new()
	h.auth.initialize(http, logger)
	player(h, SENDER)
	h.playerValues = HorizonPlayerValues.new()
	h.playerValues.initialize(http, h.auth)
	h.items = HorizonItems.new()
	h.items.initialize(http, h.auth, h.playerValues)
	h.inbox = HorizonInbox.new()
	h.inbox.initialize(http, h.auth, h.playerValues)
	h.itemGifts = HorizonItemGifts.new()
	h.itemGifts.initialize(http, h.auth)
	root.add_child(h)
	var sample: Node = actor()
	# Local guards send nothing.
	check((await h.itemGifts.getConfig(OTHER)).errorCode == "SESSION_FORBIDDEN")
	check((await h.itemGifts.getGift(SENDER, "bad")).errorCode == "INVALID_REQUEST")
	check((await h.itemGifts.declineGift(SENDER, GIFT, -1)).errorCode == "INVALID_REQUEST")
	check((await h.itemGifts.sendGift(SENDER, UNKNOWN, "2026-11-16T10:00:00Z", RECIPIENT, INSTANCE, 9, 3)).errorCode == "INVALID_REQUEST")
	check(sample.review_send(RECIPIENT, INSTANCE).errorCode == "REVIEW_REQUIRED")
	var config: Dictionary = await sample.read_config()
	check(config.success and config.data.config.fee == Models.Market.MAX and config.data.limits.openGiftsPerPlayer == 2147483647)
	check((await sample.read_inventory()).data.instances[0].instanceId == INSTANCE)
	check(sample.review_send(SENDER, INSTANCE).errorCode == "REVIEW_REQUIRED")
	var quote: Dictionary = sample.review_send(RECIPIENT, INSTANCE)
	check(quote.success and quote.data.fee == Models.Market.MAX and quote.data.currencyKey == "1coin.gold" and quote.data.recipientId == RECIPIENT)
	# Uncertain send: the original is on disk before the POST and survives the screen.
	var failed: Dictionary = await sample.confirm_reviewed_send()
	check(not failed.success and failed.errorCode == "STATE_CONFLICT")
	var saved: Dictionary = Pending.load_pending(PROJECT, SENDER).pending
	check(saved.phase == "intent" and Models.valid_intent(saved.body) and saved.body.recipientId == RECIPIENT)
	sample.free()
	sample = actor()
	check(not (await sample.recover_original_operation()).success)
	var confirmed: Dictionary = Pending.load_pending(PROJECT, SENDER).pending
	check(confirmed.phase == "confirmed" and confirmed.confirmed.giftId == GIFT and confirmed.body == saved.body)
	sample.free()
	sample = actor()
	var current: Dictionary = await sample.retry_pending()
	check(current.success and current.data.inventory.instances.is_empty() and current.data.itemGifts.sent[0].id == GIFT)
	check(Pending.load_pending(PROJECT, SENDER).pending.is_empty())
	var replay: Dictionary = await h.itemGifts.submitIntent(saved.body)
	check(replay.success and replay.data.replayed and replay.data.receipt.giftId == GIFT and replay.data.gift.status == "offered")
	check(h.itemGifts.getCurrent("send").is_empty() and h.itemGifts.getCurrent("operation").is_empty())
	var altered: Dictionary = saved.body.duplicate(true)
	altered.recipientId = OTHER
	check((await h.itemGifts.submitIntent(altered)).errorCode == "OPERATION_CONFLICT")
	var unknown: Dictionary = saved.duplicate(true)
	unknown.body.operationId = UNKNOWN
	check(Pending.store(PROJECT, SENDER, unknown))
	check((await sample.recover_original_operation()).errorCode == "OPERATION_NOT_FOUND")
	check(Pending.load_pending(PROJECT, SENDER).pending == unknown)
	# Fixture-only cleanup of its artificial unresolved file; the sample exposes no deletion API.
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(Pending.path(PROJECT, SENDER))) == OK)
	# A player switch while the POST is in flight fences the reply. The original stays with the sender only.
	check((await sample.read_inventory()).data.instances[0].instanceId == I2)
	check(sample.review_send(RECIPIENT, I2).success)
	_send(sample)
	await create_timer(.1).timeout
	player(h, RECIPIENT)
	while _send_result.is_empty(): await create_timer(.02).timeout
	check(_send_result.errorCode == "STALE_RESPONSE")
	check(Pending.load_pending(PROJECT, RECIPIENT).pending.is_empty() and h.itemGifts.getCurrent("config").is_empty())
	check((await sample.retry_pending()).errorCode == "NO_PENDING_OPERATION")
	var second: Dictionary = Pending.load_pending(PROJECT, SENDER).pending
	check(second.phase == "intent" and second.body.instanceId == I2 and second.body.userId == SENDER)
	player(h, SENDER)
	var resumed: Dictionary = await sample.retry_pending()
	check(resumed.success and resumed.data.confirmed.giftId == G2 and resumed.data.itemGifts.sent.size() == 2 and resumed.data.itemGifts.limits.openGiftsPerPlayer == 1)
	check(Pending.load_pending(PROJECT, SENDER).pending.is_empty())
	# Recipient: received offers, decline with replay, claim through the Inbox.
	player(h, RECIPIENT)
	var received: Dictionary = await sample.read_gifts()
	check(received.success and received.data.state.received.size() == 2 and received.data.state.sent.is_empty())
	check((await Quickstart.read_one_gift(sample, GIFT)).data.gift.status == "offered")
	var declined: Dictionary = await Quickstart.decline_reviewed_gift(sample, GIFT)
	check(declined.success and not declined.data.replayed and declined.data.returnDelivery == "delivered" and declined.data.gift.declinedAt != null)
	check(h.itemGifts.getCurrent("gift").is_empty())
	var again: Dictionary = await h.itemGifts.declineGift(RECIPIENT, GIFT, 2)
	check(again.success and again.data.replayed)
	var offers: Dictionary = await h.inbox.getInbox(RECIPIENT)
	var offer: Dictionary = offers.data.entries[0]
	var source: Dictionary = HorizonInbox.getSource(offer)
	check(source.kind == HorizonInbox.SourceKind.ITEM_GIFT_OFFER and source.giftId == G2 and source.senderId == SENDER and HorizonInbox.canClaim(offer))
	check(offer.attachment.itemGift.direction == "offer" and offer.attachment.itemGift.instanceId == I2)
	var accepted: Dictionary = await sample.claim_gift_entry(OFFER_ENTRY)
	check(accepted.success and accepted.data.items[0].instanceId == I2 and not HorizonInbox.canClaim(accepted.data.inbox.entries[0]))
	check((await sample.read_gift(UNKNOWN)).errorCode == "GIFT_NOT_FOUND")
	# Sender: return entry claim and server errors.
	player(h, SENDER)
	var returns: Dictionary = await h.inbox.getInbox(SENDER)
	var back: Dictionary = HorizonInbox.getSource(returns.data.entries[0])
	check(back.kind == HorizonInbox.SourceKind.ITEM_GIFT_RETURN and back.giftId == GIFT and back.recipientId == RECIPIENT and back.reason == "declined")
	var reclaimed: Dictionary = await sample.claim_gift_entry(RETURN_ENTRY)
	check(reclaimed.success and reclaimed.data.items[0].instanceId == INSTANCE)
	check((await h.itemGifts.submitIntent(altered)).errorCode == "ITEM_GIFTS_RATE_LIMITED")
	check((await h.itemGifts.getConfig(SENDER)).errorCode == "INVALID_RESPONSE")
	check(Pending.load_pending(PROJECT, SENDER).pending.is_empty() and Pending.load_pending(PROJECT, RECIPIENT).pending.is_empty())
	print("PASS Item Gifts native HTTP: %d checks/all six routes,durable original send,read-only recovery,identity-switch fence,decline replay and Inbox offer/return claims" % checks)
	quit(0)
