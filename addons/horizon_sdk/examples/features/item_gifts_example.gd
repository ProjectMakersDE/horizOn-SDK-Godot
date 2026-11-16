extends Node
## Explicit two-player UI actions only. Configure the stable project UUID; never embed an admin key.
## Resolve a public friend code with Horizon.friends first and show the profile before review_send.
const Models = preload("res://addons/horizon_sdk/models/item_gift_models.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_gift.gd")
const Operation = preload("res://addons/horizon_sdk/examples/features/item_gift_operation.gd")
@export var project_id: String = ""
var _review: Dictionary = {}
var _decline: Dictionary = {}
var _busy: bool = false

func read_config() -> Dictionary:
	var h: Node = _authorized()
	return await h.itemGifts.getConfig(_user(h)) if h != null else _failure("SESSION_REQUIRED")
func read_gifts() -> Dictionary:
	var h: Node = _authorized()
	return await h.itemGifts.getState(_user(h)) if h != null else _failure("SESSION_REQUIRED")
func read_gift(id: String) -> Dictionary:
	var h: Node = _authorized()
	return await h.itemGifts.getGift(_user(h), id) if h != null else _failure("SESSION_REQUIRED")
func read_inventory() -> Dictionary:
	var h: Node = _authorized()
	return await h.items.getInventory(_user(h)) if h != null else _failure("SESSION_REQUIRED")

## Uses the explicitly read current config and complete inventory. Display item, recipient and fee before confirm.
func review_send(recipient_id: String, instance_id: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	var current: Dictionary = h.itemGifts.getCurrent("config")
	var inventory: Dictionary = h.items.getCurrentInventory()
	if current.is_empty() or inventory.is_empty() or not current.config.enabled or not Models.uuid(recipient_id) or recipient_id == _user(h): return _failure("REVIEW_REQUIRED")
	var original: Dictionary = {}
	for item: Dictionary in inventory.instances:
		if item.instanceId == instance_id: original = item
	if original.is_empty() or original.equipped: return _failure("REVIEW_REQUIRED")
	_review = {"context": _context(h), "terms": {"recipientId": recipient_id, "instanceId": instance_id, "expectedInventoryRevision": inventory.revision, "expectedConfigRevision": current.config.revision}, "display": {"item": original.duplicate(true), "recipientId": recipient_id, "currencyKey": current.config.currencyKey, "fee": current.config.fee}}
	return {"success": true, "data": _review.display.duplicate(true), "errorCode": "", "error": ""}

## User confirmation invokes this; no lifecycle method prepares or sends a gift.
func confirm_reviewed_send() -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	if _busy or _review.is_empty() or _review.context != _context(h): return _failure("REVIEW_REQUIRED")
	_busy = true
	var result: Dictionary = await Operation.run(h, project_id, _user(h), weakref(self), _review.duplicate(true), false)
	_busy = false
	if result.success: _review.clear()
	return result

## Restart/host changes preserve the original tuple. Confirmed originals perform GETs only.
func retry_pending() -> Dictionary: return await _resume(false)
func recover_original_operation() -> Dictionary: return await _resume(true)
func _resume(lookup_only: bool) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	if _busy: return _failure("BUSY")
	_busy = true
	var result: Dictionary = await Operation.run(h, project_id, _user(h), weakref(self), {}, lookup_only)
	_busy = false
	if result.success: _review.clear()
	return result

## Recipient only, from a current point read of an open offer.
func review_decline(gift_id: String) -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	var point: Dictionary = h.itemGifts.getCurrent("gift")
	if point.is_empty() or point.gift.id != gift_id or point.gift.status != "offered" or point.gift.recipientId != _user(h): return _failure("REVIEW_REQUIRED")
	_decline = {"context": _context(h), "giftId": gift_id, "revision": point.gift.revision}
	return {"success": true, "data": point.gift.duplicate(true), "errorCode": "", "error": ""}
## A repeated decline with the same revision replays the declined state.
func confirm_reviewed_decline() -> Dictionary:
	var h: Node = _authorized()
	if h == null: return _failure("SESSION_REQUIRED")
	if _decline.is_empty() or _decline.context != _context(h): return _failure("REVIEW_REQUIRED")
	var result: Dictionary = await h.itemGifts.declineGift(_user(h), _decline.giftId, _decline.revision)
	if result.success: _decline.clear()
	return result

## Accepting an offer and taking back a return are both the Inbox claim of that original entry.
func claim_gift_entry(entry_id: String) -> Dictionary:
	var h: Node = _authorized()
	return await h.inbox.claim(_user(h), entry_id) if h != null else _failure("SESSION_REQUIRED")
func _user(h: Node) -> String: return h.auth.getCurrentUser().userId
func _context(h: Node) -> String:
	return JSON.stringify([project_id, _user(h), h._http.apiKey, h._http.activeHost, h._http.sessionToken, h._http.getContextGeneration()])
func _authorized() -> Node:
	var h: Node = get_node_or_null("/root/Horizon")
	return h if Models.uuid(project_id) and h != null and h.auth.isSignedIn() and h.auth.getCurrentUser().accessToken == h._http.sessionToken and not h._http.sessionToken.is_empty() else null
func _failure(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
