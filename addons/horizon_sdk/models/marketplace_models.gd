class_name HorizonMarketplaceModels
extends RefCounted
## Lossless public Marketplace wire. Stored listing operations are server internals.
const MAX := 9007199254740991
const INT32_MAX := 2147483647
const STATUSES := ["active", "return_pending", "return_delivered", "sold", "returned"]
static var _instant := RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z\\z")
static var _currency := RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,23}\\z")
static var _cursor := RegEx.create_from_string("^[A-Za-z0-9_-]{1,512}\\z")

static func parse(raw: String) -> Dictionary:
	# Reuse the lossless Items grammar, without importing its feature-specific byte frame.
	# Full retained Marketplace state is independent of today's configured list quotas.
	var tokens: Array[RegExMatch] = HorizonItemModels._tokens.search_all(raw)
	var end: int = 0
	for token: RegExMatch in tokens:
		if token.get_string() == "-0" or not HorizonItemModels._space(raw.substr(end, token.get_start() - end)): return {}
		end = token.get_end()
	if not HorizonItemModels._space(raw.substr(end)): return {}
	var position: Array[int] = [0]
	var valid: Array[bool] = [true]
	var value: Variant = HorizonItemModels._read(tokens, position, valid, 0)
	return value if valid[0] and position[0] == tokens.size() and value is Dictionary else {}

static func integer(value: Variant, minimum: int = 0) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= MAX
static func uuid(value: Variant) -> bool:
	return HorizonItemModels.uuid(value) and value == value.to_lower()
static func currency(value: Variant) -> bool:
	return value is String and _currency.search(value) != null
static func cursor(value: Variant) -> bool:
	return value is String and _cursor.search(value) != null
static func milliseconds(value: Variant) -> int:
	if not value is String or _instant.search(value) == null: return -1
	var seconds: int = Time.get_unix_time_from_datetime_string(value)
	var millis: int = seconds * 1000 + int(value.substr(20, 3))
	return millis if millis >= 0 and millis <= MAX and timestamp(millis) == value else -1
static func timestamp(millis: int) -> String:
	return Time.get_datetime_string_from_unix_time(millis / 1000) + ".%03dZ" % (millis % 1000)
static func new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]
static func _fields(value: Dictionary, fields: Array[String]) -> bool:
	return value.size() == fields.size() and fields.all(func(key: String) -> bool: return value.has(key))

static func valid_intent(kind: String, body: Variant, listing_id: String = "") -> bool:
	if not body is Dictionary or not uuid(body.get("userId")) or not uuid(body.get("operationId")) or milliseconds(body.get("issuedAt")) < 0: return false
	match kind:
		"create":
			return listing_id.is_empty() and _fields(body, ["userId", "operationId", "issuedAt", "instanceId", "expectedInventoryRevision", "expectedConfigRevision", "price", "durationSeconds"]) and uuid(body.get("instanceId")) and integer(body.get("expectedInventoryRevision")) and integer(body.get("expectedConfigRevision")) and integer(body.get("price"), 1) and integer(body.get("durationSeconds"), 300) and body.durationSeconds <= 604800
		"buy":
			return uuid(listing_id) and _fields(body, ["userId", "operationId", "issuedAt", "expectedListingRevision", "expectedPrice", "expectedCurrencyKey"]) and integer(body.get("expectedListingRevision")) and integer(body.get("expectedPrice"), 1) and currency(body.get("expectedCurrencyKey"))
		"cancel":
			return uuid(listing_id) and _fields(body, ["userId", "operationId", "issuedAt", "expectedListingRevision"]) and integer(body.get("expectedListingRevision"))
	return false

static func limits(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var result: Dictionary = {}
	for field: String in ["openListingsPerPlayer", "retainedListingsPerProject", "receiptsPerPlayer", "historyPerPlayer", "projectWritesPerMinute"]:
		if not integer(raw.get(field), 1) or raw[field] > INT32_MAX: return {}
		result[field] = raw[field]
	# Existing protocol fields are distinct from the configurable five quotas.
	for field: String in ["playerWriteIntervalMillis", "minDurationSeconds", "maxDurationSeconds", "terminalRetentionSeconds", "operationRetentionSeconds", "queryCandidates", "pageSize"]:
		if not integer(raw.get(field), 1): return {}
		result[field] = raw[field]
	if result.minDurationSeconds > result.maxDurationSeconds: return {}
	return result
static func config(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not integer(raw.get("revision")) or not raw.get("enabled") is bool or not raw.has("currencyKey") or not raw.has("feeBps"): return {}
	if raw.currencyKey != null and not currency(raw.currencyKey): return {}
	if raw.feeBps != null and (not integer(raw.feeBps) or raw.feeBps > 10000): return {}
	if raw.enabled and (raw.currencyKey == null or raw.feeBps == null): return {}
	return {"revision": raw.revision, "enabled": raw.enabled, "currencyKey": raw.currencyKey, "feeBps": raw.feeBps}
static func reference(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("instanceId")) or not HorizonItemModels.key(raw.get("itemKey")): return {}
	return {"instanceId": raw.instanceId, "itemKey": raw.itemKey}
static func original_item(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("instanceId")) or not HorizonItemModels.key(raw.get("itemKey")) or not raw.get("equipped") is bool or raw.equipped or not HorizonItemModels.time(raw.get("createdAt")): return {}
	var properties: Variant = HorizonItemModels.properties(raw.get("properties"))
	if properties == null: return {}
	return {"instanceId": raw.instanceId, "itemKey": raw.itemKey, "properties": properties, "equipped": false, "createdAt": raw.createdAt}
static func _fee(price: int, bps: int) -> int:
	# Avoid both floating point and the overflowing price*bps intermediate.
	return (price / 10000) * bps + ((price % 10000) * bps) / 10000
static func listing(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("id")) or not integer(raw.get("revision"), 1) or not uuid(raw.get("sellerId")) or not uuid(raw.get("returnOwnerId")) or not raw.has("buyerId") or not raw.has("item") or not raw.has("terminalAt") or not raw.has("returnEntryId"): return {}
	if raw.buyerId != null and not uuid(raw.buyerId): return {}
	if not currency(raw.get("currencyKey")) or not integer(raw.get("price"), 1) or not integer(raw.get("feeBps")) or raw.feeBps > 10000 or not integer(raw.get("feeAmount")) or not integer(raw.get("sellerNet")): return {}
	if raw.feeAmount != _fee(raw.price, raw.feeBps) or raw.sellerNet != raw.price - raw.feeAmount or not raw.get("status") in STATUSES or not raw.get("ownerUnavailable") is bool: return {}
	if milliseconds(raw.get("createdAt")) < 0 or milliseconds(raw.get("expiresAt")) < milliseconds(raw.createdAt): return {}
	var terminal: bool = raw.status in ["sold", "returned"]
	if terminal != (raw.item == null) or terminal != (raw.terminalAt != null) or (raw.terminalAt != null and milliseconds(raw.terminalAt) < 0): return {}
	if (raw.status == "sold") != (raw.buyerId != null): return {}
	if raw.returnEntryId != null and (not raw.returnEntryId is String or not raw.returnEntryId.begins_with("message:") or not uuid(raw.returnEntryId.trim_prefix("message:"))): return {}
	var ref: Dictionary = reference(raw.get("itemReference"))
	if ref.is_empty(): return {}
	var item: Dictionary = {} if raw.item == null else original_item(raw.item)
	if raw.item != null and (item.is_empty() or reference(item) != ref): return {}
	var result: Dictionary = {}
	for field: String in ["id", "revision", "sellerId", "buyerId", "returnOwnerId", "currencyKey", "price", "feeBps", "feeAmount", "sellerNet", "status", "createdAt", "expiresAt", "terminalAt", "returnEntryId", "ownerUnavailable"]:
		result[field] = raw[field]
	result.itemReference = ref
	result.item = null if raw.item == null else item
	return result
static func receipt(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not uuid(raw.get("operationId")) or not raw.get("kind") in ["create", "buy", "cancel"] or not uuid(raw.get("listingId")) or not integer(raw.get("listingRevision"), 1): return {}
	if milliseconds(raw.get("issuedAt")) < 0 or milliseconds(raw.get("recordedAt")) < 0 or not currency(raw.get("currencyKey")) or not integer(raw.get("price"), 1) or not integer(raw.get("feeAmount")) or not integer(raw.get("sellerNet")) or raw.feeAmount > raw.price or raw.sellerNet != raw.price - raw.feeAmount: return {}
	var ref: Dictionary = reference(raw.get("itemReference"))
	if ref.is_empty(): return {}
	var result: Dictionary = {}
	for field: String in ["operationId", "issuedAt", "kind", "listingId", "listingRevision", "recordedAt", "currencyKey", "price", "feeAmount", "sellerNet"]:
		result[field] = raw[field]
	result.itemReference = ref
	return result
static func matches_receipt(value: Dictionary, kind: String, body: Dictionary, listing_id: String) -> bool:
	if value.get("operationId") != body.get("operationId") or value.get("issuedAt") != body.get("issuedAt") or value.get("kind") != kind: return false
	if kind == "create": return value.itemReference.instanceId == body.instanceId and value.price == body.price
	if value.listingId != listing_id: return false
	return kind != "buy" or (value.price == body.expectedPrice and value.currencyKey == body.expectedCurrencyKey)
static func _listing_rows(raw: Variant, maximum: int = -1) -> Variant:
	if not raw is Array or (maximum >= 0 and raw.size() > maximum): return null
	var rows: Array = []
	var ids: Dictionary = {}
	for value: Variant in raw:
		var row: Dictionary = listing(value)
		if row.is_empty() or ids.has(row.id): return null
		ids[row.id] = true
		rows.append(row)
	return rows

static func decode(raw: Dictionary, kind: String, user: String, request: Dictionary = {}, listing_id: String = "") -> Dictionary:
	if milliseconds(raw.get("serverTime")) < 0: return {}
	var result: Dictionary = {"serverTime": raw.serverTime}
	match kind:
		"limits":
			var bounds: Dictionary = limits(raw.get("limits"))
			var conf: Dictionary = config(raw.get("config"))
			var capabilities: Variant = raw.get("capabilities")
			if bounds.is_empty() or conf.is_empty() or not capabilities is Dictionary or capabilities.get("marketplace") != true or not capabilities.get("realtime") is bool: return {}
			result.merge({"limits": bounds, "config": conf, "capabilities": capabilities.duplicate(true)})
		"rules":
			if not integer(raw.get("revision")) or not raw.get("rules") is Array or raw.rules.size() > request.limit or not raw.has("nextCursor"): return {}
			if request.get("catalogRevision") != null and raw.revision != request.catalogRevision: return {}
			var previous: String = request.get("after", "")
			for rule: Variant in raw.rules:
				if not rule is Dictionary or not HorizonItemModels.key(rule.get("itemKey")) or rule.itemKey <= previous or not rule.get("active") is bool or not integer(rule.get("minPrice"), 1) or not integer(rule.get("maxPrice"), 1) or rule.minPrice > rule.maxPrice: return {}
				previous = rule.itemKey
			if raw.nextCursor != null and (not HorizonItemModels.key(raw.nextCursor) or raw.rules.is_empty() or raw.nextCursor != previous): return {}
			result.merge({"revision": raw.revision, "rules": raw.rules.duplicate(true), "nextCursor": raw.nextCursor})
		"state":
			var state: Variant = raw.get("state")
			if not state is Dictionary or state.get("userId") != user or not integer(state.get("revision")): return {}
			var bounds: Dictionary = limits(state.get("limits"))
			var open: Variant = _listing_rows(state.get("openListings"))
			var history: Variant = _listing_rows(state.get("history"))
			var window: Variant = state.get("operationWindow")
			var moderation: Variant = state.get("moderation")
			if bounds.is_empty() or open == null or history == null or not window is Dictionary or milliseconds(window.get("serverTime")) < 0 or milliseconds(window.get("acceptAfter")) < 0 or not moderation is Dictionary or not moderation.has("banUntil") or not moderation.get("reason") is String: return {}
			if moderation.banUntil != null and milliseconds(moderation.banUntil) < 0: return {}
			var ids: Dictionary = {}
			for row: Dictionary in open:
				if row.status in ["sold", "returned"] or row.returnOwnerId != user: return {}
				ids[row.id] = true
			for row: Dictionary in history:
				if not row.status in ["sold", "returned"] or ids.has(row.id) or not user in [row.sellerId, row.buyerId, row.returnOwnerId]: return {}
				ids[row.id] = true
			result.state = {"userId": user, "revision": state.revision, "openListings": open, "history": history, "operationWindow": window.duplicate(true), "moderation": moderation.duplicate(true), "limits": bounds}
		"query":
			var rows: Variant = _listing_rows(raw.get("listings"), request.limit)
			if rows == null or not raw.has("nextCursor") or (raw.nextCursor != null and not cursor(raw.nextCursor)): return {}
			for row: Dictionary in rows:
				if row.status != "active" or (not request.get("itemKey", "").is_empty() and row.itemReference.itemKey != request.itemKey) or row.price < request.minPrice or row.price > request.maxPrice: return {}
			result.merge({"listings": rows, "nextCursor": raw.nextCursor})
		"point", "return":
			var row: Dictionary = listing(raw.get("listing"))
			if row.is_empty() or row.id != listing_id: return {}
			result.listing = row
			if kind == "return":
				if not raw.get("delivery") in ["pending", "delivered", "returned"] or row.returnOwnerId != user: return {}
				result.delivery = raw.delivery
		"operation", "create", "buy", "cancel":
			var record: Dictionary = receipt(raw.get("receipt"))
			if record.is_empty() or record.operationId != request.operationId: return {}
			result.receipt = record
			if kind != "operation":
				if not matches_receipt(record, kind, request, listing_id) or not raw.get("replayed") is bool or not raw.has("listing"): return {}
				var row: Dictionary = {} if raw.listing == null else listing(raw.listing)
				if raw.listing != null and (row.is_empty() or row.id != record.listingId or row.revision < record.listingRevision or row.itemReference != record.itemReference or row.price != record.price or row.currencyKey != record.currencyKey or row.feeAmount != record.feeAmount or row.sellerNet != record.sellerNet): return {}
				if not raw.replayed and (row.is_empty() or row.revision != record.listingRevision or row.status != {"create": "active", "buy": "sold", "cancel": "return_pending"}[kind]): return {}
				result.merge({"listing": null if raw.listing == null else row, "replayed": raw.replayed})
		_: return {}
	return result
