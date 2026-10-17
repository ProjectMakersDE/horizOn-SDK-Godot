extends RefCounted
## Static coroutine owns the send lease independently of a disposable UI Node.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_marketplace.gd")
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
static func failure(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
static func context(h: Node, project: String) -> String:
	return JSON.stringify([project, h.auth.getCurrentUser().userId, h._http.apiKey, h._http.activeHost, h._http.sessionToken, h._http.getContextGeneration()])
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
		var now: int = h.marketplace.getServerNow()
		if now < 0: return failure("REVIEW_REQUIRED")
		var body: Dictionary = review.terms.duplicate(true)
		body.merge({"userId": user, "operationId": Models.new_uuid(), "issuedAt": Models.timestamp(now)})
		pending = {"scope": JSON.stringify([project, user]).sha256_text(), "kind": review.kind, "listingId": review.listingId, "body": body, "phase": "intent"}
		if not Pending.store(project, user, pending): return failure("PENDING_STORAGE_ERROR")
	if pending.is_empty(): return failure("NO_PENDING_OPERATION")
	var original_context: String = context(h, project)
	if pending.phase == "intent":
		var result: Dictionary = await h.marketplace.getOperation(user, pending.body.operationId) if lookup_only else await h.marketplace.submitIntent(pending.kind, pending.body, pending.listingId)
		if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
		if not result.success: return result
		var receipt: Dictionary = result.data.receipt
		if not Models.matches_receipt(receipt, pending.kind, pending.body, pending.listingId): return failure("INVALID_RESPONSE")
		var confirmed: Dictionary = pending.duplicate(true)
		confirmed.phase = "confirmed"
		confirmed.confirmed = {"kind": receipt.kind, "operationId": receipt.operationId, "listingId": receipt.listingId}
		if not Pending.store(project, user, confirmed, pending): return failure("PENDING_STORAGE_ERROR")
		pending = confirmed
	var inventory: Dictionary = await h.items.getInventory(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not inventory.success: return inventory
	var values: Dictionary = await h.playerValues.getState(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not values.success: return values
	var market: Dictionary = await h.marketplace.getMarketplace(user)
	if not same(h, project, original_context, owner): return failure("STALE_RESPONSE")
	if not market.success: return market
	if not Pending.confirm(project, user, pending): return failure("PENDING_STORAGE_ERROR")
	return {"success": true, "data": {"confirmed": pending.confirmed.duplicate(), "inventory": inventory.data, "playerValues": values.state, "marketplace": market.data.state}, "errorCode": "", "error": ""}
