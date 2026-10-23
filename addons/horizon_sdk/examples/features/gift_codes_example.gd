## Configure WELCOME2026 values separately from arbitrary giftData in the Dashboard.
## Original campaign/count/revision are flushed before HTTP and retained on every uncertain/error outcome.
extends Node
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_gift_code.gd")
const Identity = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const GIFT_CODE := "WELCOME2026"

var _busy: bool = false

## Bind these to explicit UI actions. Startup never consumes a code.
func redeemConfiguredCode() -> void:
	await _redeem(false)

func retryPendingRedemption() -> void:
	await _redeem(true)

func _redeem(retry_only: bool) -> void:
	if _busy: return
	_busy = true
	await _send(retry_only)
	_busy = false

func _send(retry_only: bool) -> void:
	var horizon: Node = get_node_or_null("/root/Horizon")
	if horizon == null or not await horizon.connect_to_server(): return
	var project: String = horizon.getConfig().api_key
	if not await _authenticate(horizon,project): return
	var user_id: String = horizon.auth.getCurrentUser().userId
	if horizon._http.apiKey != project: return
	var loaded: Dictionary = Pending.load_pending(project,user_id)
	if not loaded.success: push_error("Saved V1/corrupt intent needs recovery; original files retained"); return
	var pending: Dictionary = loaded.pending
	if pending.is_empty():
		if retry_only: return
		pending = await horizon.giftCodes.prepareRedemption(GIFT_CODE)
		if pending.is_empty() or horizon._http.apiKey != project or horizon.auth.getCurrentUser().userId != user_id: return
		if not Pending.store(project,pending): return
	elif not retry_only:
		push_warning("Retry or reconcile the pending intent first"); return
	var result: Dictionary = await horizon.giftCodes.redeemPreparedParsed(pending)
	if not result.get("success",false): push_warning("Original tuple retained: " + horizon.giftCodes.getLastErrorCode()); return
	if horizon._http.apiKey != project or horizon.auth.getCurrentUser().userId != user_id: return
	if not Pending.confirm(project,pending): push_warning("Confirmed tuple remains available for safe replay")
	print("Current state: %s, replayed=%s" % [result.playerValues,result.replayed])

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
