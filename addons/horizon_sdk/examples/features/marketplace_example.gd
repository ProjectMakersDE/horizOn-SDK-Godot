extends Node
## Explicit two-player UI actions only. Configure the stable project UUID; never embed an admin key.
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_marketplace.gd")
@export var project_id: String = ""
var _review: Dictionary = {}
var _busy: bool = false

func read_limits() -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.getLimits(_user(h)) if h != null else _failure("SESSION_REQUIRED")
func read_rules_page(after: String = "", revision: Variant = null) -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.getRules(_user(h), after, 50, revision) if h != null else _failure("SESSION_REQUIRED")
func read_marketplace() -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.getMarketplace(_user(h)) if h != null else _failure("SESSION_REQUIRED")
func read_listings(item_key: String = "", min_price: int = 0, max_price: int = Models.MAX, cursor: String = "") -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.queryListings(_user(h), item_key, min_price, max_price, cursor) if h != null else _failure("SESSION_REQUIRED")
func read_listing(id: String) -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.getListing(_user(h), id) if h != null else _failure("SESSION_REQUIRED")
func read_inventory() -> Dictionary:
	var h: Node = _authorized()
	return await h.items.getInventory(_user(h)) if h != null else _failure("SESSION_REQUIRED")

## Uses the explicitly read current config, rules page and complete inventory. Display fee/net before confirm.
func review_create(instance_id: String, price: int, duration_seconds: int) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	var bounds: Dictionary = h.marketplace.getCurrent("limits")
	var rules: Dictionary = h.marketplace.getCurrent("rules")
	var inventory: Dictionary = h.items.getCurrentInventory()
	if bounds.is_empty() or rules.is_empty() or inventory.is_empty() or not bounds.config.enabled or rules.revision != bounds.config.revision: return _failure("REVIEW_REQUIRED")
	var original: Dictionary = {}
	for item: Dictionary in inventory.instances:
		if item.instanceId == instance_id: original = item
	if original.is_empty() or original.equipped: return _failure("REVIEW_REQUIRED")
	var rule: Dictionary = {}
	for candidate: Dictionary in rules.rules:
		if candidate.itemKey == original.itemKey: rule = candidate
	if rule.is_empty() or not rule.active or not Models.integer(price, 1) or price < rule.minPrice or price > rule.maxPrice or duration_seconds < 300 or duration_seconds > 604800: return _failure("REVIEW_REQUIRED")
	var fee: int = Models._fee(price, bounds.config.feeBps)
	_review = {"kind": "create", "listingId": "", "context": _context(h), "terms": {"instanceId": instance_id, "expectedInventoryRevision": inventory.revision, "expectedConfigRevision": bounds.config.revision, "price": price, "durationSeconds": duration_seconds}, "display": {"item": original.duplicate(true), "currencyKey": bounds.config.currencyKey, "price": price, "feeAmount": fee, "sellerNet": price - fee}}
	return {"success": true, "data": _review.display.duplicate(true), "errorCode": "", "error": ""}
func review_buy(listing_id: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	var point: Dictionary = h.marketplace.getCurrent("point")
	if point.is_empty() or point.listing.id != listing_id or point.listing.status != "active" or point.listing.sellerId == _user(h): return _failure("REVIEW_REQUIRED")
	var row: Dictionary = point.listing
	_review = {"kind": "buy", "listingId": listing_id, "context": _context(h), "terms": {"expectedListingRevision": row.revision, "expectedPrice": row.price, "expectedCurrencyKey": row.currencyKey}, "display": row.duplicate(true)}
	return {"success": true, "data": row.duplicate(true), "errorCode": "", "error": ""}
func review_cancel(listing_id: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	var point: Dictionary = h.marketplace.getCurrent("point")
	if point.is_empty() or point.listing.id != listing_id or point.listing.status != "active" or point.listing.sellerId != _user(h): return _failure("REVIEW_REQUIRED")
	_review = {"kind": "cancel", "listingId": listing_id, "context": _context(h), "terms": {"expectedListingRevision": point.listing.revision}, "display": point.listing.duplicate(true)}
	return {"success": true, "data": point.listing.duplicate(true), "errorCode": "", "error": ""}

## User confirmation invokes this; no lifecycle method prepares or sends a trade.
func confirm_reviewed_trade() -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	if _busy or _review.is_empty() or _review.context != _context(h): return _failure("REVIEW_REQUIRED")
	var user: String = _user(h)
	var project: String = project_id
	if not Pending.acquire_send(project, user): return _failure("PENDING_STORAGE_BUSY")
	_busy = true
	var result: Dictionary = await _prepare_and_apply(h)
	_busy = false
	Pending.release_send(project, user)
	return result
func _prepare_and_apply(h: Node) -> Dictionary:
	var user: String = _user(h)
	var loaded: Dictionary = Pending.load_pending(project_id, user)
	if not loaded.success: return _failure("PENDING_STORAGE_ERROR")
	if not loaded.pending.is_empty(): return _failure("PENDING_OPERATION")
	var server_now: int = h.marketplace.getServerNow()
	if server_now < 0: return _failure("REVIEW_REQUIRED")
	var body: Dictionary = _review.terms.duplicate(true)
	body.merge({"userId": user, "operationId": Models.new_uuid(), "issuedAt": Models.timestamp(server_now)})
	var pending: Dictionary = {"scope": JSON.stringify([project_id, user]).sha256_text(), "kind": _review.kind, "listingId": _review.listingId, "body": body, "phase": "intent"}
	if not Pending.store(project_id, user, pending): return _failure("PENDING_STORAGE_ERROR")
	return await _apply(h, pending, false)

## Restart/host changes preserve the original tuple. Confirmed originals perform GETs only.
func retry_pending() -> Dictionary: return await _resume(false)
func recover_original_operation() -> Dictionary: return await _resume(true)
func _resume(lookup_only: bool) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	if _busy: return _failure("BUSY")
	var user: String = _user(h)
	var project: String = project_id
	if not Pending.acquire_send(project, user): return _failure("PENDING_STORAGE_BUSY")
	_busy = true
	var loaded: Dictionary = Pending.load_pending(project_id, user)
	var result: Dictionary = _failure("PENDING_STORAGE_ERROR")
	if loaded.success:
		result = _failure("NO_PENDING_OPERATION") if loaded.pending.is_empty() else await _apply(h, loaded.pending, lookup_only)
	_busy = false
	Pending.release_send(project, user)
	return result
func _apply(h: Node, pending: Dictionary, lookup_only: bool) -> Dictionary:
	var context: String = _context(h)
	var user: String = pending.body.userId
	if pending.phase == "intent":
		var result: Dictionary = await h.marketplace.getOperation(user, pending.body.operationId) if lookup_only else await h.marketplace.submitIntent(pending.kind, pending.body, pending.listingId)
		if not _same(h, context): return _failure("STALE_RESPONSE")
		if not result.success: return result #404/expired/conflict never becomes a replacement trade.
		var receipt: Dictionary = result.data.receipt
		if not Models.matches_receipt(receipt, pending.kind, pending.body, pending.listingId): return _failure("INVALID_RESPONSE")
		var confirmed: Dictionary = pending.duplicate(true)
		confirmed.phase = "confirmed"
		confirmed.confirmed = {"kind": receipt.kind, "operationId": receipt.operationId, "listingId": receipt.listingId}
		if not Pending.store(project_id, user, confirmed, pending): return _failure("PENDING_STORAGE_ERROR")
		pending = confirmed
	var inventory: Dictionary = await h.items.getInventory(user)
	if not _same(h, context): return _failure("STALE_RESPONSE")
	if not inventory.success: return inventory
	var values: Dictionary = await h.playerValues.getState(user)
	if not _same(h, context): return _failure("STALE_RESPONSE")
	if not values.success: return values
	var market: Dictionary = await h.marketplace.getMarketplace(user)
	if not _same(h, context): return _failure("STALE_RESPONSE")
	if not market.success: return market
	if not Pending.confirm(project_id, user, pending): return _failure("PENDING_STORAGE_ERROR")
	_review.clear()
	return {"success": true, "data": {"confirmed": pending.confirmed.duplicate(), "inventory": inventory.data, "playerValues": values.state, "marketplace": market.data.state}, "errorCode": "", "error": ""}
func retry_return_delivery(listing_id: String) -> Dictionary:
	var h: Node = _authorized()
	return await h.marketplace.retryReturn(_user(h), listing_id) if h != null else _failure("SESSION_REQUIRED")
func claim_return(entry_id: String) -> Dictionary:
	var h: Node = _authorized()
	# Inbox owns the stable original entry/source guard, including replay after resale/discard.
	return await h.inbox.claim(_user(h), entry_id) if h != null else _failure("SESSION_REQUIRED")
func _user(h: Node) -> String: return h.auth.getCurrentUser().userId
func _context(h: Node) -> String:
	return JSON.stringify([project_id, _user(h), h._http.apiKey, h._http.activeHost, h._http.sessionToken, h._http.getContextGeneration()])
func _same(h: Node, context: String) -> bool: return _authorized() == h and _context(h) == context
func _authorized() -> Node:
	var h: Node = get_node_or_null("/root/Horizon")
	return h if Models.uuid(project_id) and h != null and h.auth.isSignedIn() and h.auth.getCurrentUser().accessToken == h._http.sessionToken and not h._http.sessionToken.is_empty() else null
func _failure(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
