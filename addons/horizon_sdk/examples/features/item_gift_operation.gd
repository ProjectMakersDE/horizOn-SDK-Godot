extends RefCounted
## Static coroutine owns the send lease independently of a disposable UI Node.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_gift.gd")
const Models = preload("res://addons/horizon_sdk/models/item_gift_models.gd")
static func failure(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
static func context(h: Node, project: String) -> String:
	return JSON.stringify([project, h.auth.getCurrentUser().userId, h._http.apiKey, h._http.activeHost, h._http.sessionToken, h._http.getContextGeneration()])
## A sign-out, player switch, host or project change while awaiting makes the reply stale for this original.
static func same(h: Node, project: String, original: String, owner: WeakRef) -> bool:
	var screen: Variant = owner.get_ref()
	return is_instance_valid(screen) and screen.project_id == project and is_instance_valid(h) and h.is_inside_tree() and h.auth.isSignedIn() and h.auth.getCurrentUser().accessToken == h._http.sessionToken and context(h, project) == original
static func run(h: Node, project: String, user: String, owner: WeakRef, review: Dictionary, lookup_only: bool) -> Dictionary:
	if not Pending.acquire_send(project, user): return failure("PENDING_STORAGE_BUSY")
	# This static frame remains alive if the caller's Node is freed while awaiting HTTP.
	var result: Dictionary = await apply(h, project, user, owner, review, lookup_only)
	Pending.release_send(project, user)
	return result
static func apply(h: Node, project: String, user: String, owner: WeakRef, review: Dictionary, lookup_only: bool) -> Dictionary:
	var loaded: Dictionary = Pending.load_pending(project, user)
	if not loaded.success: return failure("PENDING_STORAGE_ERROR")
	var pending: Dictionary = loaded.pending
	if not review.is_empty():
		if not pending.is_empty(): return failure("PENDING_OPERATION")
		var now: int = h.itemGifts.getServerNow()
		if now < 0: return failure("REVIEW_REQUIRED")
		var body: Dictionary = review.terms.duplicate(true)
		body.merge({"userId": user, "operationId": Models.new_uuid(), "issuedAt": Models.timestamp(now)})
		pending = {"scope": JSON.stringify([project, user]).sha256_text(), "body": body, "phase": "intent"}
		if not Pending.store(project, user, pending): return failure("PENDING_STORAGE_ERROR")
	if pending.is_empty(): return failure("NO_PENDING_OPERATION")
	var original_context: String = context(h, project)
	if pending.phase == "intent":
		var result: Dictionary = await h.itemGifts.getOperation(user, pending.body.operationId) if lookup_only else await h.itemGifts.submitIntent(pending.body)
		if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
		if not result.success: return result
		var receipt: Dictionary = result.data.receipt
		if not Models.matches_receipt(receipt, pending.body): return failure("INVALID_RESPONSE")
		var confirmed: Dictionary = pending.duplicate(true)
		confirmed.phase = "confirmed"
		confirmed.confirmed = {"operationId": receipt.operationId, "giftId": receipt.giftId}
		if not Pending.store(project, user, confirmed, pending): return failure("PENDING_STORAGE_ERROR")
		pending = confirmed
	# The item left the inventory and a fee may be charged: read both, never adjust them locally.
	var inventory: Dictionary = await h.items.getInventory(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not inventory.success: return inventory
	var values: Dictionary = await h.playerValues.getState(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not values.success: return values
	var gifts: Dictionary = await h.itemGifts.getState(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not gifts.success: return gifts
	if not Pending.confirm(project, user, pending): return failure("PENDING_STORAGE_ERROR")
	return {"success": true, "data": {"confirmed": pending.confirmed.duplicate(), "inventory": inventory.data, "playerValues": values.state, "itemGifts": gifts.data.state}, "errorCode": "", "error": ""}
