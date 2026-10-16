extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/matches_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_match.gd")
const U := "00000000-0000-4000-8000-000000001013"
const V := "00000000-0000-4000-8000-00000000a013"
const W := "00000000-0000-4000-8000-000000003013"
const I := "00000000-0000-4000-8000-000000004013"
const J := "00000000-0000-4000-8000-000000004014"
const K := "00000000-0000-4000-8000-000000004015"
const L := "00000000-0000-4000-8000-000000004016"
const R := 4294967296
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var matches: HorizonMatches
	var validatedActions: HorizonValidatedActions
var checks: int = 0
var failures: int = 0
var durableSends: int = 0
var observeDurability: bool = true
var generic: Dictionary = {}
func ok(value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Matches check failed at %s" % checks)
func _initialize() -> void:
	create_timer(45).timeout.connect(func():push_error("Matches HTTP timed out");quit(1))
	call_deferred("_run")
func client(user: String) -> FixtureHorizon:
	var h := FixtureHorizon.new()
	h._http = HorizonHttpClient.new()
	root.add_child(h._http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	h._http.initialize(logger)
	h._http.activeHost = "http://127.0.0.1:" + (OS.get_environment("HORIZON_MATCHES_TEST_PORT") if not OS.get_environment("HORIZON_MATCHES_TEST_PORT").is_empty() else "20113")
	h._http.apiKey = "matches-key"
	h._http.sessionToken = "matches-" + user.right(4)
	h._http.maxRetryAttempts = 3
	h._http.retryDelaySeconds = .02
	h._http.connectionTimeoutSeconds = 1
	h.auth = HorizonAuth.new()
	h.auth.initialize(h._http,logger)
	h.auth._currentUser.userId = user
	h.auth._currentUser.accessToken = h._http.sessionToken
	h.validatedActions = HorizonValidatedActions.new()
	h.validatedActions.initialize(h._http,logger,h.auth)
	h.matches = HorizonMatches.new()
	h.matches.initialize(h._http,h.auth,h.validatedActions)
	h._http.request_started.connect(func(url: String,method: String):
		if observeDurability and method == "POST" and "/matches" in url:
			var loaded: Dictionary = Pending.load_pending(Pending.path(h._http.apiKey,user))
			ok(loaded.success and not loaded.pending.is_empty())
			durableSends += 1)
	return h
func use_client(h: FixtureHorizon) -> void:
	var current: Node = root.get_node_or_null("Horizon")
	if current != null: root.remove_child(current)
	h.name = "Horizon"
	root.add_child(h)
func options() -> Dictionary: return {"name":"opaque é/😀","capacity":2,"visibility":"private","strength":-9007199254740991,"turnSeconds":60,"timeoutPolicy":"skip","ranked":true,"dataBase64":"AP8AgA==","inviteeIds":[V.to_upper()]}
func _generic_start(h: FixtureHorizon) -> void: generic = await h.validatedActions.startRun("ranked")
func _run() -> void:
	var a: FixtureHorizon = client(U)
	var b: FixtureHorizon = client(V)
	use_client(a)
	var sa: Node = Sample.new()
	var sb: Node = Sample.new()
	root.add_child(sa)
	root.add_child(sb)
	var caps: Dictionary = await a.matches.getLimits(U)
	ok(caps.success and caps.data.capabilities.matchesRanked)
	ok((await sa.read_matches()).data.revision == R)
	var created: Dictionary = await sa.create_reviewed(options())
	ok(created.success and created.data.playerRevision == R+1 and created.data.match.data == PackedByteArray([0,255,0,128]))
	use_client(b)
	ok((await sb.read_match(I)).data.match.data == null)
	ok((await sb.perform_reviewed("join")).data.match.participantIds == [U,V])
	use_client(a)
	ok((await sa.read_match(I)).data.match.revision == 2)
	ok((await sa.perform_reviewed("start",{"turnOrder":[U,V]})).data.match.currentPlayerId == U)
	var moved: Dictionary = await sa.perform_reviewed("turn",{"dataBase64":"AQD/","finish":false})
	ok(moved.success and moved.data.match.data == PackedByteArray([1,0,255]) and moved.data.match.notificationPending)
	use_client(b)
	ok((await sb.read_match(I)).data.match.currentPlayerId == V)
	ok((await sb.perform_reviewed("turn",{"dataBase64":"AoAA","finish":false})).data.match.currentPlayerId == U)
	use_client(a)
	ok((await sa.read_match(I)).success)
	ok((await sa.perform_reviewed("turn",{"dataBase64":"AwD/","finish":true})).data.match.status == "reporting")
	use_client(b)
	ok((await sb.read_match(I)).data.match.finalStateRevision == 6)
	use_client(a)
	var report: Dictionary = {"finalStateRevision":6,"resultBase64":"/wCA","winnerIds":[U]}
	ok((await sa.perform_reviewed("result",report)).data.match.status == "reporting") # Missing B: no winner inferred.
	use_client(b)
	ok((await sb.perform_reviewed("result",report)).data.match.status == "confirmed")
	use_client(a)
	ok((await sa.read_match(I)).data.match.revision == 8)
	var ranked: Dictionary = await sa.perform_reviewed("ranked-run",{"finalStateRevision":6})
	ok(ranked.success and a.validatedActions.getCurrentRun().seed == 42)
	ok((await a.validatedActions.startRun("other")).is_empty() and a.validatedActions.getLastErrorCode() == "RUN_IN_PROGRESS")
	ok((await sa.submit_ranked_check(123,"R1".to_utf8_buffer())).data.accepted)
	var page: Dictionary = await sa.find_open(-10,10)
	ok(page.success and page.data.matches.is_empty() and page.data.nextCursor != null)
	ok((await sa.find_open(-10,10,page.data.nextCursor)).data.nextCursor == null)
	ok((await sa.read_matches()).data.revision == R+1)
	ok((await sa.create_reviewed(options())).errorCode == "HTTP_503")
	var path: String = Pending.path(a._http.apiKey,U)
	var original: Dictionary = Pending.load_pending(path).pending
	ok(original.expectedRevision == R+1)
	ok((await sa.create_reviewed(options())).errorCode == "PENDING_ACTION")
	sa.free()
	sa = Sample.new()
	root.add_child(sa)
	var host: String = a._http.activeHost
	a._http.activeHost = "http://other-region"
	ok(Pending.path(a._http.apiKey,U) == path and Pending.load_pending(path).pending == original)
	a._http.activeHost = host
	ok((await sa.inspect_pending()).data.revision == R+2)
	ok(sa.acknowledge_reconciliation().success and not FileAccess.file_exists(path))
	use_client(b)
	ok((await sb.read_match(J)).data.match.data == null)
	ok((await sb.perform_reviewed("decline")).errorCode == "HTTP_503")
	ok((await sb.inspect_pending()).success and sb.acknowledge_reconciliation().success)
	observeDurability = false
	use_client(a)
	ok((await a.matches.cancelMatch(U,J,2)).data.match.status == "cancelled")
	ok((await b.matches.leaveMatch(V,K,10)).data.match.forfeitedIds == [V])
	ok((await b.matches.getMatches(V,true)).data.recent[0].status == "active")
	ok((await a.matches.advanceTimeout(U,K,11)).data.match.currentPlayerId == U)
	ok((await a.matches.getMatch(U,K,true)).data.match.status == "unconfirmed")
	ok((await b.matches.reportResult(V,L,6,PackedByteArray([1]),[U])).data.match.status == "disputed")
	# Same final revision/result/winners across an explicit uncertain report recovery.
	ok((await a.matches.reportResult(U,I,6,PackedByteArray([255,0,128]),[U])).errorCode == "HTTP_503")
	ok((await a.matches.reportResult(U,I,6,PackedByteArray([255,0,128]),[U])).data.replayed)
	ok((await a.matches.submitTurn(U,K,13,PackedByteArray([1,0,255]))).errorCode == "MATCH_REVISION_CONFLICT")
	ok((await b.matches.joinMatch(V,J,3)).errorCode == "HTTP_503")
	ok(not (await a.matches.advanceTimeout(U,K,13)).success)
	await create_timer(.6).timeout
	ok((await a.matches.getMatch(U,I,true)).errorCode == "INVALID_RESPONSE")
	create_timer(.03).timeout.connect(func():a._http.activeHost="http://other-region";a._http.activeHost=host)
	ok((await a.matches.getMatch(U,I,true)).errorCode == "STALE_RESPONSE")
	# Starts share one lease, including general VA API and callbacks after explicit discard.
	call_deferred("_generic_start",a)
	while a.validatedActions._runStartLease == 0: await process_frame
	ok((await a.matches.startRankedRun(U,I,6)).errorCode == "RUN_IN_PROGRESS")
	while generic.is_empty(): await process_frame
	ok(a.validatedActions.hasActiveRun())
	ok((await a.matches.startRankedRun(U,I,6)).errorCode == "RUN_IN_PROGRESS") # foreign/unbound even same server ID
	a.validatedActions.discardRun()
	var reentrant: Array[Dictionary] = []
	a.validatedActions.run_started.connect(func(_run: Dictionary):
		a.validatedActions.discardRun()
		reentrant.append(await a.validatedActions.startRun("ranked")),CONNECT_ONE_SHOT)
	ok((await a.matches.startRankedRun(U,I,6)).success)
	ok(reentrant.size() == 1 and reentrant[0].is_empty())
	ok((await a.matches.startRankedRun(U,I,6)).data.ticket == "resealed-original-run")
	ok(a.validatedActions.getCurrentRun().ticket == "resealed-original-run")
	# Explicit terminal original-run acknowledgement cannot produce a replacement run.
	observeDurability = true
	use_client(a)
	ok((await sa.read_match(I)).data.match.ownRankedRunId != null)
	ok((await sa.perform_reviewed("ranked-run", {"finalStateRevision":6})).errorCode == "HTTP_503")
	ok(sa.acknowledge_reconciliation().errorCode == "REVIEW_REQUIRED")
	ok((await sa.retry_original_report_or_run()).errorCode == "RUN_EXPIRED")
	ok(FileAccess.file_exists(path) and sa.acknowledge_reconciliation().data.terminalCode == "RUN_EXPIRED")
	ok(not FileAccess.file_exists(path) and not a.validatedActions.hasActiveRun())
	ok((await sa.read_match("00000000-0000-4000-8000-000000004018")).success)
	ok((await sa.perform_reviewed("ranked-run", {"finalStateRevision":6})).success)
	ok(a.validatedActions.getCurrentRun().runId == "00000000-0000-4000-8000-000000005014")
	use_client(b)
	ok((await sb.read_match("00000000-0000-4000-8000-000000004017")).success)
	ok((await sb.perform_reviewed("leave")).errorCode == "HTTP_503")
	ok((await sb.inspect_pending()).success and sb.acknowledge_reconciliation().success)
	ok(durableSends == 15)
	if failures == 0: print("PASS: Matches native HTTP checks=%s, two-player actual sample/all14 routes, durable pre-send/restart/original CAS, binary/null/64bit, pending Inbox, agreement/disagreement/missing, timeout, once-only faults, ABA, shared VA lease and original ranked recovery"%checks)
	sa.free();sb.free()
	if a.is_inside_tree(): root.remove_child(a)
	if b.is_inside_tree(): root.remove_child(b)
	a._http.queue_free();b._http.queue_free();a.free();b.free()
	quit(0 if failures == 0 else 1)
