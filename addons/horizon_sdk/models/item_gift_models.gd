class_name HorizonItemGiftModels
extends RefCounted
## Strict public Item Gifts wire. Gift views carry item references only, never a copied item.
const Market = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
const INT32_MAX := 2147483647
const STATUSES := ["offered", "claimed", "return_pending", "return_delivered", "returned"]
const TERMINAL := ["claimed", "returned"]
const SEND_FIELDS: Array[String] = ["userId", "operationId", "issuedAt", "recipientId", "instanceId", "expectedInventoryRevision", "expectedConfigRevision"]
const GIFT_FIELDS: Array[String] = ["id", "revision", "senderId", "recipientId", "returnOwnerId", "currencyKey", "fee", "configRevision", "status", "createdAt", "expiresAt", "terminalAt", "declinedAt", "offerEntryId", "returnEntryId", "ownerUnavailable"]

## Exact safe integers survive because the lossless Marketplace/Items grammar is reused.
static func parse(raw: String) -> Dictionary: return Market.parse(raw)
static func integer(value: Variant, minimum: int = 0) -> bool: return Market.integer(value, minimum)
static func uuid(value: Variant) -> bool: return Market.uuid(value)
static func milliseconds(value: Variant) -> int: return Market.milliseconds(value)
static func timestamp(millis: int) -> String: return Market.timestamp(millis)
static func new_uuid() -> String: return Market.new_uuid()

static func valid_intent(body: Variant) -> bool:
	if not body is Dictionary or body.size() != SEND_FIELDS.size() or not SEND_FIELDS.all(func(key: String) -> bool: return body.has(key)): return false
	return uuid(body.userId) and uuid(body.operationId) and milliseconds(body.issuedAt) >= 0 and uuid(body.recipientId) and uuid(body.instanceId) and integer(body.expectedInventoryRevision) and integer(body.expectedConfigRevision)

static func limits(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var result: Dictionary = {}
	# Configured quotas are positive Int32 values. Lowering them never truncates retained gifts.
	for field: String in ["openGiftsPerPlayer", "retainedGiftsPerProject", "projectWritesPerMinute", "historyPerPlayer", "receivedPageSize"]:
		if not integer(raw.get(field), 1) or raw[field] > INT32_MAX: return {}
		result[field] = raw[field]
	for field: String in ["playerWriteIntervalMillis", "expirySeconds", "terminalRetentionSeconds", "operationRetentionSeconds"]:
		if not integer(raw.get(field), 1): return {}
		result[field] = raw[field]
	return result

## A free gift has currencyKey null and fee 0. A paid gift names its Player Values currency.
static func fee_pair(currency_key: Variant, fee: Variant) -> bool:
	if not integer(fee): return false
	return currency_key == null if fee == 0 else Market.currency(currency_key)

static func config(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not integer(raw.get("revision")) or not raw.get("enabled") is bool or not raw.has("currencyKey") or not fee_pair(raw.currencyKey, raw.get("fee")): return {}
	return {"revision": raw.revision, "enabled": raw.enabled, "currencyKey": raw.currencyKey, "fee": raw.fee}

static func _entry_id(value: Variant) -> bool:
	return value == null or (value is String and value.begins_with("message:") and uuid(value.trim_prefix("message:")))

static func gift(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("id")) or not integer(raw.get("revision"), 1) or not uuid(raw.get("senderId")) or not uuid(raw.get("recipientId")) or not uuid(raw.get("returnOwnerId")) or raw.senderId == raw.recipientId: return {}
	if not raw.has("currencyKey") or not fee_pair(raw.currencyKey, raw.get("fee")) or not integer(raw.get("configRevision")) or not raw.get("status") in STATUSES or not raw.get("ownerUnavailable") is bool: return {}
	if not raw.has("terminalAt") or not raw.has("declinedAt") or not raw.has("offerEntryId") or not raw.has("returnEntryId") or not _entry_id(raw.offerEntryId) or not _entry_id(raw.returnEntryId): return {}
	var created: int = milliseconds(raw.get("createdAt"))
	if created < 0 or milliseconds(raw.get("expiresAt")) < created: return {}
	if (raw.status in TERMINAL) != (raw.terminalAt != null) or (raw.terminalAt != null and milliseconds(raw.terminalAt) < 0): return {}
	if raw.declinedAt != null and (milliseconds(raw.declinedAt) < 0 or raw.status in ["offered", "claimed"]): return {}
	var ref: Dictionary = Market.item_reference(raw.get("itemReference"))
	if ref.is_empty(): return {}
	var result: Dictionary = {}
	for field: String in GIFT_FIELDS:
		result[field] = raw[field]
	result.itemReference = ref
	return result

static func receipt(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("operationId")) or milliseconds(raw.get("issuedAt")) < 0 or not uuid(raw.get("giftId")) or not integer(raw.get("giftRevision"), 1) or milliseconds(raw.get("recordedAt")) < 0: return {}
	if not uuid(raw.get("recipientId")) or not raw.has("currencyKey") or not fee_pair(raw.currencyKey, raw.get("fee")) or not integer(raw.get("configRevision")): return {}
	var ref: Dictionary = Market.item_reference(raw.get("itemReference"))
	if ref.is_empty(): return {}
	var result: Dictionary = {}
	for field: String in ["operationId", "issuedAt", "giftId", "giftRevision", "recordedAt", "recipientId", "currencyKey", "fee", "configRevision"]:
		result[field] = raw[field]
	result.itemReference = ref
	return result

## The receipt must prove the exact original intent: same identity, recipient, item and config revision.
static func matches_receipt(value: Dictionary, body: Dictionary) -> bool:
	if value.is_empty() or not value.get("itemReference") is Dictionary: return false
	return value.get("operationId") == body.get("operationId") and value.get("issuedAt") == body.get("issuedAt") and value.get("recipientId") == body.get("recipientId") and value.itemReference.get("instanceId") == body.get("instanceId") and value.get("configRevision") == body.get("expectedConfigRevision")

static func _rows(raw: Variant) -> Variant:
	if not raw is Array: return null
	var rows: Array = []
	var ids: Dictionary = {}
	for value: Variant in raw:
		var row: Dictionary = gift(value)
		if row.is_empty() or ids.has(row.id): return null
		ids[row.id] = true
		rows.append(row)
	return rows

static func decode(raw: Dictionary, kind: String, user: String, request: Dictionary = {}, gift_id: String = "") -> Dictionary:
	if milliseconds(raw.get("serverTime")) < 0: return {}
	var result: Dictionary = {"serverTime": raw.serverTime}
	match kind:
		"config":
			var conf: Dictionary = config(raw.get("config"))
			var bounds: Dictionary = limits(raw.get("limits"))
			if conf.is_empty() or bounds.is_empty(): return {}
			result.merge({"config": conf, "limits": bounds})
		"state":
			var state: Variant = raw.get("state")
			if not state is Dictionary or state.get("userId") != user or not integer(state.get("revision")): return {}
			var bounds: Dictionary = limits(state.get("limits"))
			var sent: Variant = _rows(state.get("sent"))
			var history: Variant = _rows(state.get("history"))
			var received: Variant = _rows(state.get("received"))
			var window: Variant = state.get("operationWindow")
			if bounds.is_empty() or sent == null or history == null or received == null or not window is Dictionary or milliseconds(window.get("serverTime")) < 0 or milliseconds(window.get("acceptAfter")) < 0: return {}
			var ids: Dictionary = {}
			for row: Dictionary in sent:
				if row.status in TERMINAL or row.returnOwnerId != user: return {}
				ids[row.id] = true
			for row: Dictionary in history:
				if not row.status in TERMINAL or ids.has(row.id) or not user in [row.senderId, row.recipientId, row.returnOwnerId]: return {}
				ids[row.id] = true
			for row: Dictionary in received:
				if row.status != "offered" or row.recipientId != user: return {}
			result.state = {"userId": user, "revision": state.revision, "sent": sent, "history": history, "received": received, "operationWindow": {"serverTime": window.serverTime, "acceptAfter": window.acceptAfter}, "limits": bounds}
		"gift":
			var row: Dictionary = gift(raw.get("gift"))
			if row.is_empty() or row.id != gift_id or not user in [row.senderId, row.recipientId, row.returnOwnerId]: return {}
			result.gift = row
		"decline":
			var row: Dictionary = gift(raw.get("gift"))
			if row.is_empty() or row.id != gift_id or row.recipientId != user or row.declinedAt == null or not raw.get("replayed") is bool or not raw.get("returnDelivery") in ["pending", "delivered", "returned"]: return {}
			if not raw.replayed and row.revision <= request.expectedGiftRevision: return {}
			result.merge({"gift": row, "replayed": raw.replayed, "returnDelivery": raw.returnDelivery})
		"operation", "send":
			var record: Dictionary = receipt(raw.get("receipt"))
			if record.is_empty() or record.operationId != request.operationId: return {}
			result.receipt = record
			if kind == "send":
				if not matches_receipt(record, request) or not raw.get("replayed") is bool or not raw.has("gift"): return {}
				var row: Dictionary = {} if raw.gift == null else gift(raw.gift)
				if raw.gift != null and (row.is_empty() or row.id != record.giftId or row.revision < record.giftRevision or row.senderId != user or row.recipientId != record.recipientId or row.itemReference != record.itemReference or row.currencyKey != record.currencyKey or row.fee != record.fee or row.configRevision != record.configRevision): return {}
				if not raw.replayed and (row.is_empty() or row.revision != record.giftRevision or row.status != "offered"): return {}
				result.merge({"gift": null if raw.gift == null else row, "replayed": raw.replayed})
		_: return {}
	return result
