extends SceneTree
const Models = preload("res://addons/horizon_sdk/models/match_models.gd")
const U := "00000000-0000-4000-8000-000000001013"
const V := "00000000-0000-4000-8000-000000002013"
const W := "00000000-0000-4000-8000-000000003013"
const I := "00000000-0000-4000-8000-000000004013"
const RUN := "00000000-0000-4000-8000-000000005013"
const T := "2026-10-16T12:00:00Z"
class FakeHttp extends HorizonHttpClient:
	var reply: Dictionary = {}
	var calls: int = 0
	var hook: Callable
	var raw: String = ""
	var lastBody: String = ""
	var failed: bool = false
	func _response() -> HorizonNetworkResponse:
		calls += 1
		if hook.is_valid(): hook.call()
		if failed: return HorizonNetworkResponse.failure("uncertain generic start",503,HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
		var response := HorizonNetworkResponse.success(reply.duplicate(true))
		response.rawBody = Models.encode(reply) if raw.is_empty() else raw
		return response
	func getAsync(_endpoint: String, _session: bool = false) -> HorizonNetworkResponse: return _response()
	func postJsonHeadersOnceAsync(_endpoint: String, _body: Dictionary, _session: bool, json: String, _headers: PackedStringArray) -> HorizonNetworkResponse:
		lastBody = json
		return _response()
	func postAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse: return _response()
var checks: int = 0
var failures: int = 0
func ok(value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Matches check failed at %s" % checks)
func summary() -> Dictionary: return {"id":I,"name":"opaque é/😀","revision":1,"creatorId":U,"capacity":2,"visibility":"private","strength":-9007199254740991,"status":"lobby","participantIds":[U],"invitedIds":[V],"forfeitedIds":[],"currentPlayerId":null,"turnDeadline":null,"createdAt":T,"startedAt":null,"finishedAt":null,"purgeAt":null,"finalStateRevision":null,"hasDisagreement":false,"ranked":false,"timeoutDue":false}
func view() -> Dictionary: return summary().merged({"turnOrder":[],"turnSeconds":60,"timeoutPolicy":"skip","dataBase64":"AP8AgA==","reports":[],"reportDeadline":null,"absoluteDeadline":null,"rankedLeaderboardKey":null,"ownRankedRunId":null,"notificationPending":false})
func point() -> Dictionary: return {"match":view(),"pollAfterSeconds":120,"serverTime":T}
func caps() -> Dictionary: return {"activeMatches":2,"stateBytes":1024,"retainedMatches":20,"pendingInvites":20,"settlementMatches":20,"historyRetentionSeconds":604800,"rankedSettlementSeconds":604800}
func mine() -> Dictionary: return {"userId":U,"revision":4294967296,"active":[summary()],"invites":[],"pendingResults":[],"recent":[],"limits":caps(),"pollAfterSeconds":120,"serverTime":T}
func options() -> Dictionary: return {"name":"opaque é/😀","capacity":2,"visibility":"private","strength":-9007199254740991,"turnSeconds":60,"timeoutPolicy":"skip","ranked":false,"dataBase64":"AP8AgA==","inviteeIds":[V]}
func run() -> Dictionary: return {"runId":RUN,"ticket":"original-opaque-ticket","seed":42,"leaderboardKey":"ranked","issuedAt":T,"expiresAt":"2026-10-16T12:30:00Z","expiresInSeconds":1800}
func _initialize() -> void:
	create_timer(15).timeout.connect(func(): push_error("Matches policy timed out"); quit(1))
	call_deferred("_run")
func _run() -> void:
	for raw: String in ['{"revision":1.0}', '{"revision":1e0}', '{"revision":9007199254740992}', '{"revision":-9007199254740992}', '{"revision":1,"revi\\u0073ion":2}', '{"x":"\\ud800"}', '{"x":01}', '{"x":[1,]}']:
		ok(Models.parse(raw).is_empty())
	ok(Models.parse('{"revision":9007199254740991}').revision == Models.MAX)
	ok(Models.parse('{"strength":-9007199254740991}').strength == -Models.MAX)
	ok(Models.decodeBytes("AP8AgA==") == PackedByteArray([0,255,0,128]))
	ok(Models.decodeBytes("") is PackedByteArray)
	for bad: Variant in ["AP8AgA=", "AP8AgA==\n", "AB==", "!!!!", true, null]: ok(Models.decodeBytes(bad) == null)
	var large := PackedByteArray()
	large.resize(8192)
	ok(Models.decodeBytes(Models.encodeBytes(large)).size() == 8192)
	large.resize(Models.STATE_BYTES + 1)
	ok(Models.decodeBytes(Models.encodeBytes(large)) == null)
	for space: int in [0x09,0x1c,0x00a0,0x1680,0x2007,0x202f,0x3000]: ok(not Models.text(String.chr(space),120,true))
	ok(Models.text(String.chr(0x85),120,true)) # JVM does not classify NEL as a blank character.
	ok(Models.createOptions(options()))
	for replacement: Dictionary in [{"capacity":2.0},{"strength":"1"},{"ranked":0},{"inviteeIds":[V,V]},{"dataBase64":"Zg"},{"name":""},{"extra":true}]:
		ok(not Models.createOptions(options().merged(replacement,true)))
	var nul: Variant = Models.parse('{"name":"a\\u0000é"}').name
	ok(nul is HorizonItemStringData and Models.text(nul,120,true))
	var nul_point: Dictionary = point()
	nul_point.match.name = nul
	var decoded: Dictionary = Models.response(Models.parse(Models.encode(nul_point)),"get",U,I)
	ok(not decoded.is_empty() and decoded.match.name.getJson() == '"a\\u0000é"')
	ok(decoded.match.data == PackedByteArray([0,255,0,128]))
	for required: String in Models.SUMMARY + Models.VIEW:
		var missing: Dictionary = point()
		missing.match.erase(required)
		ok(Models.response(missing,"get",U,I).is_empty())
	var invited: Dictionary = point()
	invited.match.dataBase64 = null
	ok(Models.response(invited,"get",V,I).match.data == null)
	ok(Models.response(invited,"get",U,I).is_empty())
	ok(Models.response(point(),"get",V,I).is_empty())
	invited.match.invitedIds = []
	ok(not Models.response(invited,"decline",V,I,0).is_empty())
	ok(Models.response(invited,"get",V,I).is_empty())
	var recent: Dictionary = summary()
	recent.merge({"capacity":3,"participantIds":[U,V,W],"invitedIds":[],"forfeitedIds":[U],"status":"active","currentPlayerId":V,"turnDeadline":"2026-10-16T12:01:00Z","startedAt":T},true)
	var ledger: Dictionary = mine()
	ledger.active = []
	ledger.recent = [recent]
	ok(not Models.response(ledger,"mine",U).is_empty())
	ledger.active = [recent]
	ledger.recent = []
	ok(Models.response(ledger,"mine",U).is_empty())
	ledger.active = []
	recent.forfeitedIds = []
	ledger.recent = [recent]
	ok(Models.response(ledger,"mine",U).is_empty())
	var report_view: Dictionary = view()
	report_view.merge({"status":"reporting","revision":5,"finalStateRevision":5,"participantIds":[U,V],"invitedIds":[],"turnOrder":[U,V],"startedAt":T,"absoluteDeadline":"2026-11-15T12:00:00Z","reportDeadline":"2026-10-17T12:00:00Z","reports":[{"userId":U,"finalStateRevision":5,"resultBase64":"","winnerIds":[U],"reportedAt":T}]},true)
	ok(not Models.view(report_view,U,"get").is_empty())
	report_view.reports[0].winnerIds = [V,U]
	ok(Models.view(report_view,U,"get").is_empty())
	report_view.reports[0].winnerIds = [U]
	report_view.reports[0].resultBase64 = Models.encodeBytes(large)
	ok(Models.view(report_view,U,"get").is_empty())
	var cursor: String = Models.encodeBytes(("m1|" + "a".repeat(64) + "|-1|" + I).to_ascii_buffer())
	ok(Models.cursor(cursor).strength == -1)
	for bad: String in [cursor+"\n", "Zg==", Models.encodeBytes(("m1|"+"a".repeat(64)+"|-0|"+I).to_ascii_buffer())]: ok(Models.cursor(bad).is_empty())
	ok(not Models.response({"matches":[],"nextCursor":cursor,"pollAfterSeconds":120,"serverTime":T},"open",U,"",null,{"minStrength":-10,"maxStrength":10,"limit":20,"cursor":""}).is_empty())
	ok(not Models.run(run()).is_empty())
	for replacement: Dictionary in [{"seed":42.0},{"seed":2147483647},{"ticket":""},{"expiresInSeconds":0},{"leaderboardKey":null},{"runId":null}]: ok(Models.run(run().merged(replacement,true)).is_empty())
	var http := FakeHttp.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "matches-policy"
	http.activeHost = "http://127.0.0.1:1"
	http.sessionToken = "matches-policy-token"
	var auth := HorizonAuth.new()
	auth.initialize(http,logger)
	auth._currentUser.userId = U
	auth._currentUser.accessToken = http.sessionToken
	var validated := HorizonValidatedActions.new()
	validated.initialize(http,logger,auth)
	var manager := HorizonMatches.new()
	var realtime := HorizonRealtime.new()
	manager.initialize(http,auth,validated,realtime)
	var clock: Array[int] = [0]
	manager._nowMillis = func() -> int: return clock[0]
	http.reply = mine()
	var first: Dictionary = await manager.getMatches(U)
	ok(first.success)
	var calls: int = http.calls
	ok((await manager.getMatches(U)).errorCode == "REFRESH_NOT_DUE" and http.calls == calls)
	ok((await manager.getMatches(U,true)).success and http.calls == calls+1)
	first.data.active[0].name = "modified by caller"
	ok(manager.getCached(first.identity).active[0].name == "opaque é/😀")
	clock[0] = 120000
	ok((await manager.getMatches(U)).success)
	http.reply = point()
	var point_result: Dictionary = await manager.getMatch(U,I)
	ok(point_result.success)
	point_result.data.match.data[0] = 42
	ok(manager.getCached(point_result.identity).match.data[0] == 0)
	http.reply.match.revision = 2
	ok((await manager.getMatch(U,I,true)).success)
	http.reply.match.revision = 1
	ok((await manager.getMatch(U,I,true)).errorCode == "STALE_RESPONSE")
	http.hook = func():
		var before: String = http.apiKey
		http.apiKey = "other-project"
		http.apiKey = before
	ok((await manager.getMatch(U,I,true)).errorCode == "STALE_RESPONSE")
	http.hook = Callable()
	ok(manager.getCached(point_result.identity).is_empty())
	http.reply = point()
	manager.matches_loaded.connect(func(_kind: String,_data: Dictionary): manager.clearCache(),CONNECT_ONE_SHOT)
	ok((await manager.getMatch(U,I,true)).errorCode == "STALE_RESPONSE")
	var lease: int = validated._claimRunStart()
	ok(lease > 0 and validated._claimRunStart() == 0)
	validated._onSignedOut()
	ok(validated._claimRunStart() == 0)
	validated._releaseRunStart(lease+1)
	ok(validated._claimRunStart() == 0)
	validated._releaseRunStart(lease)
	var next_lease: int = validated._claimRunStart()
	ok(next_lease > lease)
	validated._releaseRunStart(lease)
	ok(validated._claimRunStart() == 0)
	validated._releaseRunStart(next_lease)
	http.reply = run()
	var ranked: Dictionary = await manager.startRankedRun(U,I,5)
	ok(ranked.success and validated.getCurrentRun().runId == RUN)
	ok((await manager.startRankedRun(U,I,5)).success)
	ok(not validated._retireMatchRun(U,W,5,http.getContextGeneration()) and validated.hasActiveRun())
	ok(validated._retireMatchRun(U,I,5,http.getContextGeneration()) and not validated.hasActiveRun())
	ok((await manager.startRankedRun(U,I,5)).success)
	calls = http.calls
	ok((await validated.startRun("ranked")).is_empty() and validated.getLastErrorCode() == "RUN_IN_PROGRESS" and http.calls == calls)
	calls = http.calls
	ok((await manager.startRankedRun(U,W,5)).errorCode == "RUN_IN_PROGRESS" and http.calls == calls)
	validated.discardRun()
	http.hook = func():
		ok(validated._runStartLease != 0 and validated._claimRunStart() == 0)
	var generic: Dictionary = await validated.startRun("ranked")
	ok(generic.runId == RUN and validated._runStartLease == 0)
	ok(not validated._retireMatchRun(U,I,5,http.getContextGeneration()) and validated.hasActiveRun())
	http.hook = Callable()
	validated.discardRun()
	validated.run_started.connect(func(_run: Dictionary):
		http.activeHost = "http://other-region"
		http.activeHost = "http://127.0.0.1:1",CONNECT_ONE_SHOT)
	ok((await manager.startRankedRun(U,I,5)).errorCode == "STALE_RESPONSE")
	calls = http.calls
	manager._cache.wire = {"metadata":true}
	realtime.event_received.emit({"topic":"friends:" + U})
	ok(manager._cache.has("wire") and http.calls == calls)
	realtime.event_received.emit({"topic":"matches:" + I,"revision":6})
	ok(manager._cache.is_empty() and http.calls == calls)
	manager._cache.wire = {"metadata":true}
	realtime.resync_required.emit("matches:" + I)
	ok(manager._cache.is_empty() and http.calls == calls)
	manager._cache.wire = {"metadata":true}
	realtime.connection_error.emit("DISCONNECTED")
	ok(manager._cache.is_empty() and http.calls == calls)
	validated.discardRun()
	http.failed = true
	var failed_callback: Array[bool] = [false]
	validated.run_start_failed.connect(func(_error: String,_code: String): failed_callback[0] = validated._claimRunStart() == 0,CONNECT_ONE_SHOT)
	ok((await validated.startRun("ranked")).is_empty() and failed_callback[0] and validated._runStartLease == 0)
	for number: int in range(520): manager._versions[str(number)] = number
	manager._trim(manager._versions,512)
	ok(manager._versions.size() == 512)
	if failures == 0: print("PASS: Matches native policy checks=%s" % checks)
	realtime.free()
	http.queue_free()
	quit(0 if failures == 0 else 1)
