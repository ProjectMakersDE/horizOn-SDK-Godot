extends SceneTree
const Models = preload("res://addons/horizon_sdk/models/item_gift_models.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_gift.gd")
const PROJECT := "10000000-0000-4000-8000-000000001140"
const USER := "20000000-0000-4000-8000-000000001140"
const RECIPIENT := "30000000-0000-4000-8000-000000001140"
const INSTANCE := "40000000-0000-4000-8000-000000001140"
const GIFT := "50000000-0000-4000-8000-000000001140"
const OPERATION := "60000000-0000-4000-8000-000000001140"
const ENTRY := "message:70000000-0000-3000-8000-000000001140"
const TIME := "2026-11-16T10:00:00.000Z"
var checks: int = 0
func check(value: bool) -> void:
	checks += 1
	assert(value, "Item Gifts policy check %d" % checks)
func bounds() -> Dictionary:
	return {"openGiftsPerPlayer": 3, "retainedGiftsPerProject": 50, "projectWritesPerMinute": 10, "historyPerPlayer": 20, "receivedPageSize": 50, "playerWriteIntervalMillis": 1000, "expirySeconds": 604800, "terminalRetentionSeconds": 604800, "operationRetentionSeconds": 2592000}
func body() -> Dictionary:
	return {"userId": USER, "operationId": OPERATION, "issuedAt": TIME, "recipientId": RECIPIENT, "instanceId": INSTANCE, "expectedInventoryRevision": 9, "expectedConfigRevision": 3}
func view() -> Dictionary:
	return {"id": GIFT, "revision": 2, "senderId": USER, "recipientId": RECIPIENT, "returnOwnerId": USER, "itemReference": {"instanceId": INSTANCE, "itemKey": "hat"}, "currencyKey": null, "fee": 0, "configRevision": 3, "status": "offered", "createdAt": TIME, "expiresAt": "2026-11-23T10:00:00.000Z", "terminalAt": null, "declinedAt": null, "offerEntryId": ENTRY, "returnEntryId": null, "ownerUnavailable": false}
func record() -> Dictionary:
	return {"operationId": OPERATION, "issuedAt": TIME, "giftId": GIFT, "giftRevision": 2, "recordedAt": TIME, "recipientId": RECIPIENT, "itemReference": {"instanceId": INSTANCE, "itemKey": "hat"}, "currencyKey": null, "fee": 0, "configRevision": 3}
func entry(gift: Variant) -> Dictionary:
	return {"userId": RECIPIENT, "cursor": "c", "revision": 1, "broadcastRevision": 1, "serverTime": TIME, "pollAfterSeconds": 120, "unchanged": false, "counts": {}, "limits": {"targeted": 1, "broadcasts": 1}, "entries": [{"id": ENTRY, "kind": "message", "type": "item_gift", "reference": GIFT, "textKey": "horizon.item_gifts.offer", "parameters": {"senderId": USER}, "createdAt": TIME, "expiresAt": TIME, "read": false, "claimed": false, "overdue": false, "attachment": {"values": [], "itemGift": gift}}]}
func _initialize() -> void:
	check(Models.valid_intent(body()))
	for field: String in ["expectedInventoryRevision", "expectedConfigRevision"]:
		for invalid: Variant in [1.0, -1, 9007199254740992, "1", null]:
			var request: Dictionary = body(); request[field] = invalid
			check(not Models.valid_intent(request))
	var extra: Dictionary = body(); extra.price = 1
	check(not Models.valid_intent(extra))
	var upper: Dictionary = body(); upper.recipientId = "3000000A-0000-4000-8000-000000001140"
	check(not Models.valid_intent(upper))
	var missing: Dictionary = body(); missing.erase("issuedAt")
	check(not Models.valid_intent(missing))
	# Free gifts carry no currency, paid gifts always name one.
	check(Models.fee_pair(null, 0) and Models.fee_pair("1coin.gold", 9007199254740991))
	check(not Models.fee_pair("1coin.gold", 0) and not Models.fee_pair(null, 5) and not Models.fee_pair("Gold!", 5) and not Models.fee_pair(null, -1))
	check(not Models.config({"revision": 1, "enabled": true, "currencyKey": null, "fee": 0}).is_empty())
	check(Models.config({"revision": 1, "enabled": "yes", "currencyKey": null, "fee": 0}).is_empty())
	for field: String in ["openGiftsPerPlayer", "retainedGiftsPerProject", "projectWritesPerMinute", "historyPerPlayer", "receivedPageSize"]:
		var high: Dictionary = bounds(); high[field] = 2147483647
		check(not Models.limits(high).is_empty())
		for invalid: Variant in [0, -1, 2147483648, 1.0, "5"]:
			high[field] = invalid
			check(Models.limits(high).is_empty())
	check(not Models.gift(view()).is_empty())
	var self_gift: Dictionary = view(); self_gift.recipientId = USER
	check(Models.gift(self_gift).is_empty())
	var open_terminal: Dictionary = view(); open_terminal.terminalAt = TIME
	check(Models.gift(open_terminal).is_empty())
	var claimed: Dictionary = view(); claimed.status = "claimed"; claimed.terminalAt = TIME; claimed.revision = 3
	check(not Models.gift(claimed).is_empty())
	claimed.declinedAt = TIME
	check(Models.gift(claimed).is_empty())
	var bad_entry: Dictionary = view(); bad_entry.offerEntryId = "broadcast:" + GIFT
	check(Models.gift(bad_entry).is_empty())
	var unknown_status: Dictionary = view(); unknown_status.status = "expired"
	check(Models.gift(unknown_status).is_empty())
	# Send decoding proves the original intent and allows a replay without the removed gift.
	check(not Models.decode({"receipt": record(), "gift": view(), "replayed": false, "serverTime": TIME}, "send", USER, body()).is_empty())
	check(not Models.decode({"receipt": record(), "gift": null, "replayed": true, "serverTime": TIME}, "send", USER, body()).is_empty())
	check(Models.decode({"receipt": record(), "gift": null, "replayed": false, "serverTime": TIME}, "send", USER, body()).is_empty())
	var later: Dictionary = view(); later.status = "claimed"; later.terminalAt = TIME; later.revision = 3
	check(Models.decode({"receipt": record(), "gift": later, "replayed": false, "serverTime": TIME}, "send", USER, body()).is_empty())
	check(not Models.decode({"receipt": record(), "gift": later, "replayed": true, "serverTime": TIME}, "send", USER, body()).is_empty())
	var changed: Dictionary = body(); changed.recipientId = "30000000-0000-4000-8000-000000001141"
	check(Models.decode({"receipt": record(), "gift": view(), "replayed": true, "serverTime": TIME}, "send", USER, changed).is_empty())
	var other_config: Dictionary = body(); other_config.expectedConfigRevision = 4
	check(not Models.matches_receipt(Models.receipt(record()), other_config))
	check(Models.decode({"receipt": record(), "serverTime": TIME}, "operation", USER, {"operationId": OPERATION}).receipt.giftId == GIFT)
	check(Models.decode({"gift": view(), "serverTime": TIME}, "gift", "30000000-0000-4000-8000-000000001141", {}, GIFT).is_empty())
	var declined: Dictionary = view(); declined.status = "return_pending"; declined.declinedAt = TIME; declined.revision = 3
	check(not Models.decode({"gift": declined, "replayed": false, "returnDelivery": "pending", "serverTime": TIME}, "decline", RECIPIENT, {"expectedGiftRevision": 2}, GIFT).is_empty())
	check(Models.decode({"gift": declined, "replayed": false, "returnDelivery": "lost", "serverTime": TIME}, "decline", RECIPIENT, {"expectedGiftRevision": 2}, GIFT).is_empty())
	check(Models.decode({"gift": declined, "replayed": false, "returnDelivery": "pending", "serverTime": TIME}, "decline", USER, {"expectedGiftRevision": 2}, GIFT).is_empty())
	check(Models.parse('{"fee":9007199254740992}').is_empty())
	check(Models.parse('{"fee":9007199254740991}').fee == 9007199254740991)
	# Inbox exposes the itemGift attachment and rejects malformed ones before any cache update.
	var inbox := HorizonInbox.new()
	var good: Dictionary = {"giftId": GIFT, "instanceId": INSTANCE, "itemKey": "hat", "direction": "offer"}
	var normalized: Dictionary = inbox._normalize(entry(good), RECIPIENT, "")
	check(not normalized.is_empty() and HorizonInbox.canClaim(normalized.entries[0]) and HorizonInbox.getSource(normalized.entries[0]).kind == HorizonInbox.SourceKind.ITEM_GIFT_OFFER)
	for broken: Dictionary in [{"direction": "gift"}, {"direction": "return"}, {"giftId": OPERATION}, {"itemKey": "Hat"}, {"extra": true}]:
		var gift: Dictionary = good.duplicate(); gift.merge(broken, true)
		check(inbox._normalize(entry(gift), RECIPIENT, "").is_empty())
	# One original per project/player; confirm only removes the exact confirmed record.
	var pending: Dictionary = {"scope": JSON.stringify([PROJECT, USER]).sha256_text(), "body": body(), "phase": "intent"}
	check(not Pending.store(PROJECT, RECIPIENT, pending))
	check(Pending.store(PROJECT, USER, pending))
	check(Pending.load_pending(PROJECT, USER).pending == pending)
	check(Pending.load_pending(PROJECT, RECIPIENT).pending.is_empty())
	check(not Pending.store(PROJECT, USER, pending))
	check(not Pending.confirm(PROJECT, USER, pending))
	check(Pending.acquire_send(PROJECT, USER) and not Pending.acquire_send(PROJECT, USER))
	Pending.release_send(PROJECT, USER)
	var confirmed: Dictionary = pending.duplicate(true); confirmed.phase = "confirmed"; confirmed.confirmed = {"operationId": OPERATION, "giftId": GIFT}
	check(Pending.store(PROJECT, USER, confirmed, pending))
	check(not Pending.confirm(PROJECT, USER, pending))
	check(Pending.confirm(PROJECT, USER, confirmed))
	check(Pending.load_pending(PROJECT, USER).pending.is_empty())
	print("PASS Item Gifts policy: %d checks, exact intent/receipt proof, fee pairing, gift views, Inbox itemGift attachment and one durable original per player" % checks)
	quit(0)
