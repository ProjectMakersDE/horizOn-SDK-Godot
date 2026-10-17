extends SceneTree
const GroupSupport = preload("res://tests/groups_policy_test.gd")
const MatchSupport = preload("res://tests/matches_policy_test.gd")
const SharedSupport = preload("res://tests/shared_objects_policy_test.gd")
const U: String = "00000000-0000-4000-8000-000000001010"
const T: String = "2026-10-16T12:00:00Z"
var checks: int = 0
func ok(value: bool) -> void:
	checks += 1
	assert(value)
func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	call_deferred("_run")
func _run() -> void:
	var json: String = '{"large":"' + "é".repeat(2048) + '","seed":9007199254740993,"decimal":1.0000000000000000000001}'
	var original: HorizonGroupJsonData = HorizonGroupJsonData.fromJson(json)
	ok(original != null and original.getJson() == json and original.isValid())
	var deep: String = '{"x":'.repeat(32) + "null" + "}".repeat(32)
	ok(HorizonGroupJsonData.fromJson(deep) != null)
	ok(HorizonGroupJsonData.fromJson('{"x":'.repeat(1025) + "null" + "}".repeat(1025)) == null)
	var cycle: Dictionary = {}; cycle.self = cycle
	ok(HorizonGroupJsonData.fromDictionary(cycle) == null); cycle.clear()
	var groups := HorizonGroups.new()
	ok(groups._metadata("é".repeat(200), "d".repeat(2048), "open", original))
	var transport := GroupSupport.ControlledHttp.new(); root.add_child(transport)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	transport.initialize(logger); transport.apiKey = "config-policy"; transport.activeHost = "https://one.invalid"; transport.sessionToken = "session"
	var auth := HorizonAuth.new(); auth.initialize(transport,logger); auth._currentUser.userId = U; auth._currentUser.accessToken = "session"
	groups.initialize(transport,auth)
	var group_data: Dictionary = {"id": "00000000-0000-4000-8000-000000003010", "revision": 1, "name": "é".repeat(200), "description": "d".repeat(2048), "joinMode": "open", "leaderId": U, "memberCount": 501, "createdAt": T, "updatedAt": T, "myRole": "leader", "data": {}}
	var limits: Dictionary = {"maxMembers": 501, "maxGroupsPerPlayer": 6, "maxInvitations": 21, "maxJoinRequests": 21, "maxDataBytes": 8192, "memberPageSize": 51, "maxPlayerInvitations": 21, "maxPlayerRequests": 21, "maxNameBytes": 512, "maxDescriptionBytes": 4096, "maxDataDepth": 32}
	var snapshot: Dictionary = {"userId": U, "revision": 1, "groups": [group_data], "incomingInvites": [], "outgoingRequests": [], "limits": limits, "serverTime": T}
	transport.responses = [{"data": snapshot}]
	var accepted: Dictionary = await groups.getGroups(U)
	ok(accepted.success and accepted.data.limits.size() == 11 and accepted.data.groups[0].memberCount == 501)
	# Lower policy never changes an existing group's readable metadata or membership count.
	snapshot.revision = 2
	for field: String in snapshot.limits: snapshot.limits[field] = 1
	transport.responses = [{"data": snapshot}]
	accepted = await groups.getGroups(U)
	ok(accepted.success and accepted.data.groups[0].name == group_data.name and accepted.data.limits.maxMembers == 1)
	var support := MatchSupport.new()
	var caps: Dictionary = support.caps()
	caps.merge({"activeMatches": 11, "stateBytes": HorizonMatchModels.STATE_BYTES, "retainedMatches": 0, "pendingInvites": 21, "settlementMatches": 201, "historyRetentionSeconds": 0}, true)
	ok(HorizonMatchModels.limits(caps))
	caps.retainedMatches = 2147483648; ok(not HorizonMatchModels.limits(caps)); caps.retainedMatches = 0
	var ledger: Dictionary = support.mine(); ledger.limits = caps
	ledger.pendingResults = [{"matchId": support.I, "finalStateRevision": 1, "ownRankedRunId": null, "expiresAt": T}]
	var parsed: Dictionary = HorizonMatchModels.response(ledger,"mine",support.U)
	ok(not parsed.is_empty() and parsed.pendingResults[0].ownRankedRunId == null)
	ledger.pendingResults[0].ownRankedRunId = support.RUN
	parsed = HorizonMatchModels.response(ledger,"mine",support.U)
	ok(parsed.pendingResults[0].ownRankedRunId == support.RUN and parsed.pendingResults[0].size() == 4)
	ledger.pendingResults.append(ledger.pendingResults[0]); ok(HorizonMatchModels.response(ledger,"mine",support.U).is_empty())
	support.free()
	ok(HorizonSharedObjectModels.limits({"collections": 101, "storageBytes": 4294967296, "objectBytes": 1048576}))
	var shared := SharedSupport.new()
	var usage: Dictionary = shared.usage(); usage.count = 101
	ok(HorizonSharedObjectModels.usage(usage,"world",shared.U))
	shared.free()
	var bytes := PackedByteArray(); bytes.resize(65537)
	ok(HorizonSharedObjectModels.decodeBytes(HorizonSharedObjectModels.encodeBytes(bytes)).size() == 65537)
	var chat: Dictionary = {"retainedMessagesPerPlayer":0,"retainedMessagesPerChannel":20,"retentionSeconds":604800,"privateRetainedMessagesPerChannel":15,"privateRetentionSeconds":30,"operationWindowSeconds":30,"operationFutureToleranceSeconds":60,"messageCharacters":500,"messageUtf8Bytes":2000,"channelsPerAccount":2001,"sendsPerAccountMinute":121,"playerSendIntervalMillis":3000,"channelSendIntervalMillis":2000,"reportsPerProject":201,"receiptCount":0,"reportReceiptCount":0,"wordFilterTerms":100}
	ok(HorizonChatModels.limits(chat))
	for field: String in ["channelsPerAccount","sendsPerAccountMinute","reportsPerProject"]: chat[field] = 0
	ok(HorizonChatModels.limits(chat))
	chat.channelsPerAccount = 2147483648; ok(not HorizonChatModels.limits(chat))
	transport.queue_free()
	await process_frame
	print("Configured limits policy passed: %d assertions; live configured metadata, retained reads, exact source references and physical types" % checks)
	quit()
