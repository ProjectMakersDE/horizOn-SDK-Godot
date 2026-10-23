extends SceneTree

const USER := "00000000-0000-4000-8000-000000001006"
const ENTRY := "message:00000000-0000-4000-8000-000000001006"
const ITEM_ENTRY := "message:00000000-0000-4000-8000-000000001007"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	var http := HorizonHttpClient.new()
	root.add_child(http)
	http.initialize(logger)
	http.apiKey = "inbox-project"
	http.sessionToken = "inbox-session"
	http.activeHost = "http://127.0.0.1:18906"
	http.maxRetryAttempts = 0
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = http.sessionToken
	var values := HorizonPlayerValues.new()
	values.initialize(http, auth)
	var inbox := HorizonInbox.new()
	inbox.initialize(http, auth, values)
	var loaded: Dictionary = await inbox.getInbox(USER)
	if not loaded.success or loaded.data.entries[0].attachment.values[0].amount != 9007199254740991 or typeof(loaded.data.entries[0].attachment.values[0].amount) != TYPE_INT:
		_fail("Actual HTTP must preserve safe int64 attachment amounts"); return
	loaded.data.entries.clear()
	if inbox.getCurrentInbox().entries.size() != 1:
		_fail("Caller data must not mutate the cached inbox"); return
	loaded = await inbox.getInbox(USER, "cursor-one")
	if not loaded.success or not loaded.data.unchanged or loaded.data.entries.size() != 1:
		_fail("Unchanged empty wire entries must materialize the full cache"); return
	loaded = await inbox.getInbox(USER, "cursor-one")
	if not loaded.success or loaded.data.cursor != "expired" or not loaded.data.entries[0].overdue:
		_fail("Equal revision with a changed expiry cursor must replace the snapshot"); return
	var read_result: Dictionary = await inbox.markRead(USER, ENTRY)
	if not read_result.success or not read_result.data.entries[0].read:
		_fail("Read must POST the original user/entry and replace the snapshot"); return
	var claimed: Dictionary = await inbox.claim(USER, ENTRY)
	if not claimed.success or claimed.data.replayed or values.getCurrentState().values[0].balance != 9007199254740991:
		_fail("Claim must adopt the authoritative Player Values snapshot"); return
	claimed = await inbox.claim(USER, ENTRY)
	if not claimed.success or not claimed.data.replayed or values.getCurrentState().values[0].balance != 9007199254740991:
		_fail("Claim replay must keep the entry ID and never add a delta"); return
	var denied: Dictionary = await inbox.remove(USER, ENTRY)
	if denied.success or denied.errorCode != "UNCLAIMED_REWARD" or not inbox.getCurrentInbox().is_empty():
		_fail("Failed mutation must expose its code and invalidate the old snapshot"); return
	loaded = await inbox.getInbox(USER)
	if not loaded.success or loaded.data.entries.size() != 552 or loaded.data.limits.freeTextBytes != 512 or HorizonInbox.getFreeText(loaded.data.entries[0]).to_utf8_buffer().size() != 512:
		_fail("Configured free text and retained entries above lowered quotas must remain readable over HTTP"); return
	if not HorizonInbox.canClaim(loaded.data.entries[1]) or HorizonInbox.getSource(loaded.data.entries[1]).get("kind") != HorizonInbox.SourceKind.MARKET_RETURN:
		_fail("An item-only Market descriptor must be typed and claimable"); return
	for replayed: bool in [false, true]:
		claimed = await inbox.claim(USER, ITEM_ENTRY)
		if not claimed.success or claimed.data.replayed != replayed or claimed.data.items != [{"instanceId": USER, "itemKey": "sword"}] or values.getCurrentState().values[0].balance != 9007199254740991:
			_fail("Item return and replay must preserve references without adding local rewards"); return
	if (await inbox.getInbox("other-user")).errorCode != "SESSION_FORBIDDEN" or (await inbox.claim(USER, "broken")).errorCode != "INVALID_REQUEST":
		_fail("Foreign users and malformed entry IDs must fail locally"); return
	http.sessionToken = ""
	if (await inbox.getInbox(USER)).errorCode != "SESSION_REQUIRED":
		_fail("Signed-out reads must fail locally"); return
	await create_timer(1.8).timeout
	print("Godot Inbox REST, unchanged/expiry, int64, read, claim/replay and removal contract passed")
	http.queue_free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
