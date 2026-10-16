## Configure WELCOME2026 values separately from arbitrary giftData in the Dashboard.
## Original UUID + code are flushed before HTTP and retained on every uncertain/error outcome.
extends Node
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_gift_code.gd")
const Identity = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const GIFT_CODE := "WELCOME2026"

func _ready() -> void:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not await horizon.connect_to_server(): return
	var project: String = horizon.getConfig().api_key
	if not await _authenticate(horizon,project): return
	var user_id: String = horizon.auth.getCurrentUser().userId
	if horizon._http.apiKey != project: return
	var loaded: Dictionary = Pending.load_pending(project,user_id)
	if not loaded.success:
		push_error("Saved redemption needs reconciliation; original files retained"); return
	var pending: Dictionary = loaded.pending
	if pending.is_empty():
		pending = {"userId":user_id,"code":GIFT_CODE,"idempotencyId":HorizonGiftCodes.createRedemptionId()}
		if not Pending.store(project,pending):
			push_error("Cannot persist the original redemption before sending"); return
	var result: Dictionary = await horizon.giftCodes.redeemParsed(pending.code,pending.idempotencyId)
	if result.is_empty() or not result.get("success",false):
		push_warning("Redemption unresolved. Read current state and retry the original ID/code; no replacement guest or intent created."); return
	if not Pending.confirm(project,pending): push_warning("Confirmed intent retained because exact cleanup failed")
	print("Opaque giftData rewards: %s" % JSON.stringify(result.rewards))
	print("Already booked values (do not add again): %s" % JSON.stringify(result.grantedValues))
	if result.playerValues != null: print("Current server balances: %s" % JSON.stringify(result.playerValues.values))
	print("Unlocked cosmetics: %s, replayed=%s" % [result.grantedUnlocks,result.replayed])

func _authenticate(horizon: Node,project: String) -> bool:
	if horizon.auth.isSignedIn(): return Identity.mark_identity(project)
	var cache: ConfigFile = ConfigFile.new()
	var loaded: Error = cache.load("user://horizon_cache.cfg")
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND: return false
	if cache.has_section_key("cache",HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN):
		if not Identity.mark_identity(project): return false
		var token: Variant = cache.get_value("cache",HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN)
		if not token is String or token.is_empty() or token.length() > 32: return false
		return await horizon.auth.signInAnonymous(token)
	var marker: String = Identity.identity_marker(project)
	if FileAccess.file_exists(marker) or FileAccess.file_exists(marker + ".next"): return false
	if not Identity.reserve_signup(project): return false
	return await horizon.auth.signUpAnonymous("GiftCodePlayer")
