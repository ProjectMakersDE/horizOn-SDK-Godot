extends SceneTree
const U: String = "00000000-0000-4000-8000-000000001016"
const RUN: String = "00000000-0000-4000-8000-000000005016"
const Sample = preload("res://addons/horizon_sdk/examples/features/matches_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_match.gd")
class Client extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var matches: HorizonMatches
	var validatedActions: HorizonValidatedActions
var checks: int = 0
var failed: bool = false
func ok(value: bool) -> void:
	checks += 1
	if not value: failed = true; push_error("Configured transport assertion %d" % checks)
func uid(n: int) -> String: return "00000000-0000-4000-8000-%012d" % n
func digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new(); hashing.start(HashingContext.HASH_SHA256); hashing.update(bytes)
	return hashing.finish().hex_encode()
func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("Configured native HTTP watchdog"); quit(1))
	call_deferred("_run")
func _run() -> void:
	var h := Client.new(); h.name = "Horizon"; root.add_child(h)
	h._http = HorizonHttpClient.new(); h.add_child(h._http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	h._http.initialize(logger); h._http.activeHost = "http://127.0.0.1:20116"; h._http.apiKey = "configured-key"; h._http.sessionToken = "configured-session"; h._http.connectionTimeoutSeconds = 60; h._http.maxRetryAttempts = 0
	h.auth = HorizonAuth.new(); h.auth.initialize(h._http,logger); h.auth._currentUser.userId = U; h.auth._currentUser.accessToken = "configured-session"
	var friends := HorizonFriends.new(); friends.initialize(h._http,h.auth)
	var high: Dictionary = await friends.getFriends(U)
	ok(high.success and high.data.friends.size() == 201 and high.data.incoming.size() == 21 and high.data.blocked.size() == 101)
	if not high.success: quit(1); return
	ok(high.data.friends[0].since != null and high.data.friends[1].since == null and high.data.friends[2].since == null and high.data.outgoing[2].createdAt == null)
	var original: Dictionary = high.data.outgoing[0].duplicate(true)
	var lower: Dictionary = await friends.getFriends(U)
	ok(lower.success and lower.data.limits.maxFriends == 1 and lower.data.friends.size() == 201 and lower.data.outgoing.size() == 21)
	ok((await friends.cancelRequest(U,original.userId,1,original.requestId)).errorCode == "REVISION_CONFLICT")
	var groups := HorizonGroups.new(); groups.initialize(h._http,h.auth)
	high = await groups.getGroups(U)
	ok(high.success and high.data.groups.size() == 6 and high.data.groups[0].memberCount == 501 and high.data.limits.size() == 11)
	if not high.success: quit(1); return
	ok(high.data.incomingInvites[1].createdAt == null and high.data.outgoingRequests[2].createdAt == null)
	var group: Dictionary = high.data.groups[0]
	ok(group.data.getJson().contains("9007199254740993") and group.data.getJson().contains("1.0000000000000000000001"))
	var page: Dictionary = await groups.getMembers(U,uid(50000),"",51)
	ok(page.success and page.data.members.size() == 51)
	var pending: Dictionary = await groups.getPending(U,uid(50000))
	ok(pending.success and pending.data.invitations.size() == 21 and pending.data.joinRequests[2].createdAt == null)
	lower = await groups.getGroups(U)
	ok(lower.success and lower.data.groups.size() == 6 and lower.data.limits.maxNameBytes == 1 and lower.data.groups[0].name == group.name)
	ok((await groups.updateGroup(U,uid(50000),1,group.name,group.description,group.joinMode,group.data)).errorCode == "INVALID_GROUP")
	var large_group: Dictionary = await groups.getGroup(U,uid(50000))
	ok(large_group.success and digest(large_group.data.data.getJson().to_utf8_buffer()) == "6b5f2516c8539d8dd0d5b9db33ddff429a982215e84d61167704224f31c26eff")
	var shared := HorizonSharedObjects.new(); shared.initialize(h._http,h.auth)
	var catalog: Dictionary = await shared.getCollections(U)
	ok(catalog.success and catalog.data.limits.collections == 101 and catalog.data.limits.storageBytes == 4294967296 and catalog.data.definitions[0].maxObjectsPerOwner == 101)
	var usage: Dictionary = await shared.getUsage(U,"world")
	ok(usage.success and usage.data.count == 101 and usage.data.limits.objectBytes == 1024)
	var retained: Dictionary = await shared.getObject(U,"world",uid(160000))
	ok(retained.success and retained.data.object.data.size() == 1048576 and digest(retained.data.object.data) == "00757de1b6664f1982235fa82bc5030aa4c76069b5f1a269db3ee394175f723a")
	var realtime := HorizonRealtime.new(); h.add_child(realtime); realtime.initialize(h._http,h.auth)
	h.validatedActions = HorizonValidatedActions.new(); h.validatedActions.initialize(h._http,logger,h.auth)
	h.matches = HorizonMatches.new(); h.matches.initialize(h._http,h.auth,h.validatedActions,realtime)
	var limits: Dictionary = await h.matches.getLimits(U)
	ok(limits.success and limits.data.limits.retainedMatches == 0 and limits.data.limits.historyRetentionSeconds == 0 and limits.data.limits.stateBytes == 14648*1024)
	var ledger: Dictionary = await h.matches.getMatches(U)
	ok(ledger.success and ledger.data.active.size() == 11 and ledger.data.invites.size() == 21 and ledger.data.recent.size() == 101 and ledger.data.pendingResults.size() == 201)
	var point: Dictionary = await h.matches.getMatch(U,uid(180000))
	ok(point.success and point.data.match.data.size() == 14648*1024 and digest(point.data.match.data) == "d12011f3d43c3012b201dd6ea5c40c1e421ad4f6a35e2ce2a5eb8f88899f2fe2")
	var sample := Sample.new(); root.add_child(sample)
	ok((await sample.read_matches()).success)
	var file: String = Pending.path(h._http.apiKey,U)
	var options: Dictionary = {"name":"Maximum original","capacity":2,"visibility":"private","strength":0,"turnSeconds":60,"timeoutPolicy":"skip","ranked":false,"dataBase64":point.data.match.dataBase64,"inviteeIds":[]}
	ok((await sample.create_reviewed(options)).errorCode == "UNAVAILABLE")
	var maximum_original: Dictionary = Pending.load_pending(file).pending
	ok(maximum_original.expectedRevision == 1 and HorizonMatchModels.parse(maximum_original.bodyJson).dataBase64 == options.dataBase64)
	sample.free(); sample = Sample.new(); root.add_child(sample)
	ok((await sample.create_reviewed(options)).errorCode == "REVIEW_REQUIRED" and Pending.load_pending(file).pending == maximum_original)
	ok((await sample.inspect_pending()).success and Pending.load_pending(file).pending == maximum_original)
	ok(sample.acknowledge_reconciliation().success and Pending.load_pending(file).pending.is_empty())
	ok((await sample.read_matches()).success)
	ok((await sample.recover_pending_ranked_result(uid(210000))).errorCode == "UNAVAILABLE")
	var saved: Dictionary = Pending.load_pending(file).pending
	ok(saved.matchId == uid(210000) and saved.expectedRevision == 5 and saved.bodyJson == '{"finalStateRevision":5}')
	sample.free(); sample = Sample.new(); root.add_child(sample)
	ok((await sample.retry_original_report_or_run()).success and h.validatedActions.getCurrentRun().runId == RUN)
	ok(Pending.load_pending(file).pending.is_empty())
	var chat := HorizonChat.new(); h.add_child(chat); chat.initialize(h._http,h.auth,realtime)
	var chat_limits: Dictionary = await chat.getLimits(U)
	ok(chat_limits.success and chat_limits.data.limits.channelsPerAccount == 2001 and chat_limits.data.limits.sendsPerAccountMinute == 121 and chat_limits.data.limits.reportsPerProject == 201)
	sample.queue_free(); h._http.clearSessionToken()
	for auth_signal: Signal in [h.auth.signout_completed,h.auth.signin_completed,h.auth.signup_completed]:
		for connection: Dictionary in auth_signal.get_connections(): auth_signal.disconnect(connection.callable)
	h.queue_free()
	await process_frame
	await process_frame
	print("Configured actual native transport: %d assertions; failed=%s" % [checks,failed])
	quit(1 if failed else 0)
