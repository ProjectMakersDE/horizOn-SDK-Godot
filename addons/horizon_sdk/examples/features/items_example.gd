extends Node
## Explicit UI actions; no signup fallback, polling, automatic purchases or revision replacement.
## Configure an item offer, review it, purchase once, then explicitly read/equip/adjust/discard.
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_item_intent.gd")
var _review: Dictionary = {}
var _selection: int = 0
var _busy: bool = false

func refresh_inventory() -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.items.getInventory(horizon.auth.getCurrentUser().userId)
func load_catalog_page(after_key: String = "", catalog_revision: Variant = null) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.items.getCatalog(horizon.auth.getCurrentUser().userId, after_key, 50, catalog_revision)

## Render costs/itemRewards and require an explicit purchase confirmation afterward.
func review_offer(offer_key: String) -> Dictionary:
	if _busy: return _failure("BUSY")
	_selection += 1
	_review.clear()
	var selected: int = _selection
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var context: String = _context(horizon)
	var result: Dictionary = await horizon.playerValues.getOffers(horizon.auth.getCurrentUser().userId)
	if selected != _selection or not _same(horizon, context): return _failure("STALE_RESPONSE")
	if not result.success: return result
	var offer: Dictionary = _offer(result.data, offer_key)
	if offer.is_empty() or offer.get("itemRewards", []).is_empty(): return _failure("OFFER_NOT_FOUND")
	_review = {"offer": offer, "context": context}
	return {"success": true, "data": offer.duplicate(true), "errorCode": "", "error": ""}

func purchase_reviewed_offer() -> Dictionary:
	if _busy: return _failure("BUSY")
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	if _review.is_empty() or not _same(horizon, _review.context): return _failure("REVIEW_REQUIRED")
	var context: String = _context(horizon)
	var path: String = _path(horizon, "purchase")
	var loaded: Dictionary = _load(horizon, path, "purchase")
	if not loaded.success: return loaded
	if not loaded.pending.is_empty(): return _failure("PENDING_PURCHASE")
	var action: Dictionary = _load(horizon, _path(horizon, "action"), "action")
	if not action.success or not action.pending.is_empty(): return _failure("PENDING_ACTION")
	_busy = true
	# Refresh before a NEW purchase. Changed terms need another explicit confirmation.
	var fresh: Dictionary = await horizon.playerValues.getOffers(horizon.auth.getCurrentUser().userId)
	if not _same(horizon, context): _busy = false; return _failure("STALE_RESPONSE")
	if not fresh.success: _busy = false; return fresh
	var current: Dictionary = _offer(fresh.data, _review.offer.key)
	if current.is_empty(): _busy = false; return _failure("OFFER_NOT_FOUND")
	if current != _review.offer:
		_review = {"offer": current, "context": context}
		_busy = false
		return _failure("OFFER_CHANGED")
	var pending: Dictionary = {"userId": horizon.auth.getCurrentUser().userId, "project": horizon._http.apiKey.sha256_text(), "offerKey": current.key, "operationId": horizon.playerValues.createOperationId(), "phase": "purchase"}
	if not _store(path, pending): _busy = false; return _failure("PENDING_STORAGE_ERROR")
	if not _same(horizon, context): _busy = false; return _failure("STALE_RESPONSE")
	var result: Dictionary = await _purchase(horizon, path, pending, context)
	_busy = false
	return result

## This explicit retry never picks another ID, even after expiry or offer removal.
func retry_pending_purchase() -> Dictionary:
	if _busy: return _failure("BUSY")
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var path: String = _path(horizon, "purchase")
	var loaded: Dictionary = _load(horizon, path, "purchase")
	if not loaded.success or loaded.pending.is_empty(): return loaded if not loaded.success else _failure("NO_PENDING_PURCHASE")
	_busy = true
	var result: Dictionary = await _purchase(horizon, path, loaded.pending, _context(horizon))
	_busy = false
	return result

func _purchase(horizon: Node, path: String, pending: Dictionary, context: String) -> Dictionary:
	if pending.phase == "purchase":
		var result: Dictionary = await horizon.playerValues.purchase(pending.userId, pending.offerKey, pending.operationId)
		if not _same(horizon, context): return _failure("STALE_RESPONSE")
		if not result.success: return result # Original intent retained on every uncertain/expired outcome.
		var receipt: Variant = result.get("state", {}).get("operation")
		if not receipt is Dictionary or receipt.get("operationId") != pending.operationId or HorizonItemModels.references(receipt.get("items")) == null: return _failure("INVALID_RESPONSE")
		var original: Dictionary = pending.duplicate(true)
		pending.phase = "inventory"
		pending.items = result.state.operation.items.duplicate(true)
		if not _store(path, pending, original): return _failure("PENDING_STORAGE_ERROR")
	# A failed refresh never becomes a second purchase. Restart resumes this phase with GET only.
	var inventory: Dictionary = await horizon.items.getInventory(pending.userId)
	if not _same(horizon, context): return _failure("STALE_RESPONSE")
	if not inventory.success: return inventory
	if not _remove(path, pending): return _failure("PENDING_STORAGE_ERROR")
	_review.clear()
	return {"success": true, "data": {"inventory": inventory.data, "originalItems": pending.items}, "errorCode": "", "error": ""}

## Each action uses the exact selected instance and revision from the current authorized snapshot.
func equip_item(instance_id: String, revision: Variant, equipped: bool) -> Dictionary:
	return await _new_action("equip", instance_id, revision, {"equipped": equipped})
func adjust_item(instance_id: String, revision: Variant, changes: Array) -> Dictionary:
	return await _new_action("adjust", instance_id, revision, {"changes": changes.duplicate(true)})
## Discard destroys this unique instance. Wire this only to a separate explicit confirmation.
func discard_item(instance_id: String, revision: Variant) -> Dictionary:
	return await _new_action("discard", instance_id, revision, {})
func _new_action(action: String, instance: String, revision: Variant, payload: Dictionary) -> Dictionary:
	if _busy: return _failure("BUSY")
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var path: String = _path(horizon, "action")
	var loaded: Dictionary = _load(horizon, path, "action")
	if not loaded.success or not loaded.pending.is_empty(): return _failure("PENDING_ACTION")
	var purchase: Dictionary = _load(horizon, _path(horizon, "purchase"), "purchase")
	if not purchase.success or not purchase.pending.is_empty(): return _failure("PENDING_PURCHASE")
	var snapshot: Dictionary = horizon.items.getCurrentInventory()
	if snapshot.get("revision") != revision or not HorizonItemModels.integer(revision) or not _contains(snapshot, instance): return _failure("REVIEW_REQUIRED")
	var context: String = _context(horizon)
	var pending: Dictionary = {"userId": horizon.auth.getCurrentUser().userId, "project": horizon._http.apiKey.sha256_text(), "action": action, "instanceId": instance, "expectedRevision": revision, "payload": payload}
	if not _valid(pending, horizon, "action") or not _store(path, pending): return _failure("PENDING_STORAGE_ERROR")
	if not _same(horizon, context): return _failure("STALE_RESPONSE")
	_busy = true
	var result: Dictionary = await _send_action(horizon, pending)
	_busy = false
	if not _same(horizon, context): return _failure("STALE_RESPONSE")
	if result.success and not _remove(path, pending): return _failure("PENDING_STORAGE_ERROR")
	return result

## Explicitly inspect the current inventory after uncertainty. This method acknowledges that
## review; it does not replay an old delta against a silently substituted new revision.
func acknowledge_action_reconciliation() -> Dictionary:
	if _busy: return _failure("BUSY")
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var path: String = _path(horizon, "action")
	var loaded: Dictionary = _load(horizon, path, "action")
	if not loaded.success or loaded.pending.is_empty(): return _failure("NO_PENDING_ACTION")
	var current: Dictionary = horizon.items.getCurrentInventory()
	if current.is_empty() or current.revision < loaded.pending.expectedRevision: return _failure("REVIEW_REQUIRED")
	if not _remove(path, loaded.pending): return _failure("PENDING_STORAGE_ERROR")
	return {"success": true, "data": current, "errorCode": "", "error": ""}
func _send_action(horizon: Node, pending: Dictionary) -> Dictionary:
	match pending.action:
		"equip": return await horizon.items.setEquipped(pending.userId, pending.instanceId, pending.expectedRevision, pending.payload.equipped)
		"adjust": return await horizon.items.adjustProperties(pending.userId, pending.instanceId, pending.expectedRevision, pending.payload.changes)
		"discard": return await horizon.items.discardItem(pending.userId, pending.instanceId, pending.expectedRevision)
	return _failure("INVALID_REQUEST")

func _load(horizon: Node, path: String, kind: String) -> Dictionary:
	var loaded: Dictionary = Pending.load_pending(path)
	if not loaded.success: return _failure("PENDING_STORAGE_ERROR")
	if not loaded.pending.is_empty() and not _valid(loaded.pending, horizon, kind): return _failure("PENDING_STORAGE_ERROR")
	return loaded

func _valid(value: Variant, horizon: Node, kind: String) -> bool:
	if not value is Dictionary or value.get("userId") != horizon.auth.getCurrentUser().userId or value.get("project") != horizon._http.apiKey.sha256_text(): return false
	if kind == "purchase": return value.get("phase") in ["purchase", "inventory"] and value.get("offerKey") is String and not value.offerKey.is_empty() and value.get("operationId") is String and HorizonPlayerValues._validOperationId(value.operationId) and (value.phase != "inventory" or HorizonItemModels.references(value.get("items")) != null)
	if not HorizonItemModels.uuid(value.get("instanceId")) or not HorizonItemModels.integer(value.get("expectedRevision")) or not value.get("payload") is Dictionary: return false
	match value.get("action"):
		"discard": return value.payload.is_empty()
		"equip": return value.payload.size() == 1 and value.payload.get("equipped") is bool
		"adjust":
			var changes: Variant = value.payload.get("changes")
			if value.payload.size() != 1 or not changes is Array or changes.is_empty() or changes.size() > 8: return false
			var seen: Dictionary = {}
			for entry: Variant in changes:
				if not entry is Dictionary or entry.size() != 2 or not HorizonItemModels.key(entry.get("key")) or not HorizonItemModels.integer(entry.get("amount"), -HorizonItemModels.MAX) or entry.amount == 0 or seen.has(entry.key): return false
				seen[entry.key] = true
			return true
	return false
func _offer(data: Dictionary, key: String) -> Dictionary:
	for offer: Dictionary in data.get("offers", []):
		if offer.get("key") == key and offer.get("active", false): return offer.duplicate(true)
	return {}
func _contains(snapshot: Dictionary, id: String) -> bool:
	for item: Dictionary in snapshot.get("instances", []):
		if item.instanceId == id: return true
	return false
func _path(horizon: Node, kind: String) -> String:
	# Host is a request fence, never a new purchase namespace.
	return "user://horizon_items_" + kind + "_" + JSON.stringify([horizon._http.apiKey, horizon.auth.getCurrentUser().userId]).sha256_text() + ".bin"
func _context(horizon: Node) -> String:
	return JSON.stringify([horizon._http.getContextGeneration(), horizon.auth.getCurrentUser().userId, horizon.auth.getCurrentUser().accessToken, horizon._http.apiKey, horizon._http.activeHost, horizon._http.sessionToken])
func _same(horizon: Node, context: String) -> bool: return _authorized() == horizon and _context(horizon) == context
func _authorized() -> Node:
	var horizon: Node = get_node_or_null("/root/Horizon")
	return horizon if horizon != null and horizon.auth.isSignedIn() and not horizon._http.sessionToken.is_empty() and horizon.auth.getCurrentUser().accessToken == horizon._http.sessionToken else null
func _store(path: String, value: Dictionary, expected: Dictionary = {}) -> bool: return Pending.store(path, value, expected)
func _remove(path: String, expected: Dictionary) -> bool: return Pending.confirm(path, expected)
func _failure(code: String) -> Dictionary: return {"success": false, "data": {}, "errorCode": code, "error": code}
