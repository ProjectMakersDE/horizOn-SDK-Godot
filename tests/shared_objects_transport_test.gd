extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/shared_objects_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_shared_object.gd")
const U := "00000000-0000-4000-8000-000000001012"
const I := "00000000-0000-4000-8000-000000003012"
const J := "00000000-0000-4000-8000-000000003013"
const M := 9007199254740991
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var sharedObjects: HorizonSharedObjects
	var validatedActions: HorizonValidatedActions
func _initialize() -> void:
	create_timer(35).timeout.connect(func():
		push_error("Shared Objects HTTP contract timed out")
		quit(1))
	call_deferred("_run")
func _run() -> void:
	var http := HorizonHttpClient.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.activeHost = "http://127.0.0.1:20112"
	http.apiKey = "objects-key"
	http.sessionToken = "objects-session"
	http.maxRetryAttempts = 3
	http.retryDelaySeconds = .02
	http.connectionTimeoutSeconds = 1
	var h := FixtureHorizon.new()
	h.name = "Horizon"
	h._http = http
	h.auth = HorizonAuth.new()
	h.auth.initialize(http, logger)
	h.auth._currentUser.userId = U
	h.auth._currentUser.accessToken = http.sessionToken
	h.sharedObjects = HorizonSharedObjects.new()
	h.sharedObjects.initialize(http, h.auth)
	h.validatedActions = HorizonValidatedActions.new()
	h.validatedActions.initialize(http, logger, h.auth)
	root.add_child(h)
	var clock: Array[int] = [0]
	h.sharedObjects._nowMillis = func() -> int: return clock[0]
	var path: String = Pending.path(http.apiKey, U)
	var savesObserved: Array[int] = [0]
	var observeMutations: Array[bool] = [true]
	http.request_started.connect(func(url: String, method: String):
		if method in ["POST", "PUT", "DELETE"] and not url.ends_with("/query") and observeMutations[0]:
			assert(FileAccess.file_exists(path))
			assert(Pending.load_pending(path).pending.expectedRevision >= 1)
			savesObserved[0] += 1)
	var first: Dictionary = await h.sharedObjects.getCollections(U, "", 1)
	assert(first.success and first.data.nextAfterKey == "alpha")
	assert((await h.sharedObjects.getCollections(U, first.data.nextAfterKey, 1, first.data.revision)).data.definitions[0].key == "world")
	var sample: Node = Sample.new()
	root.add_child(sample)
	assert((await sample.load_collections()).data.definitions[0].maxObjectBytes == 65536)
	assert((await sample.read_usage("world")).data.revision == 4294967296)
	var search: Dictionary = HorizonSharedObjectModels.parse('{"power":9007199254740991,"label":"a\\u0000é/😀"}')
	var position: Dictionary = {"x": M, "y": -1}
	var bytes := PackedByteArray([0,255,1,0,128])
	var created: Dictionary = await sample.create_marker(bytes, search, position)
	assert(created.success and created.data.object.data == bytes and created.data.object.groupId == null and created.data.object.expiresAt == null)
	assert(created.data.object.search.label is HorizonItemStringData)
	assert(not FileAccess.file_exists(path))
	assert((await sample.read_marker("world", I)).success)
	assert((await sample.update_reviewed_marker(PackedByteArray(), search, position)).data.object.data.is_empty())
	var query: Dictionary = await sample.query_rectangle("world", -M, M, -M, M)
	assert(query.success and query.data.nextCursor == "cursor-original")
	assert((await sample.query_rectangle("world", -M, M, -M, M, query.data.nextCursor)).data.objects.is_empty())
	assert((await sample.delete_reviewed_marker()).data.deleted)
	assert((await sample.read_usage("world")).success)
	assert((await sample.create_marker(bytes, search, position)).errorCode == "HTTP_503")
	var original: Dictionary = Pending.load_pending(path).pending
	assert(original.kind == "create" and original.expectedRevision == 4294967299)
	sample.free()
	sample = Sample.new()
	root.add_child(sample)
	var recovery: Dictionary = await sample.inspect_pending()
	assert(recovery.success and recovery.data.complete)
	assert(Pending.load_pending(path).pending == original)
	assert(sample.acknowledge_reconciliation().success and not FileAccess.file_exists(path))
	assert(savesObserved[0] == 4)
	observeMutations[0] = false
	assert((await sample.begin_defense_run(recovery.data.objects[0], "defense")).errorCode == "VALIDATED_ACTIONS_UNAVAILABLE")
	assert((await sample.begin_defense_run(recovery.data.objects[0], "defense")).errorCode == "INITIAL_STATE_TOO_LARGE")
	var started: Dictionary = await sample.begin_defense_run(recovery.data.objects[0], "defense")
	assert(started.success and started.data.run.seed == 42 and started.data.defense.data == bytes)
	assert((await sample.begin_defense_run(started.data.defense, "defense")).errorCode == "PENDING_RUN")
	assert((await sample.submit_defense_run(123, "R1".to_utf8_buffer())).errorCode == "TICKET_EXPIRED")
	assert((await sample.begin_defense_run(recovery.data.objects[0], "defense")).success)
	h.validatedActions.discardRun() # Known positive start, no submit was sent.
	assert((await sample.begin_defense_run(recovery.data.objects[0], "defense")).success)
	var validated: Dictionary = await sample.submit_defense_run(123, "R1".to_utf8_buffer())
	assert(validated.success and validated.data.defenseId == J and validated.data.defenseRevision == 1 and validated.data.validatedResult.accepted)
	assert((await sample.submit_defense_run(123, "R1".to_utf8_buffer())).errorCode == "RUN_REVIEW_REQUIRED")
	var criteria: Dictionary = {"mode":"field","field":"power","equal":M}
	create_timer(.01).timeout.connect(func(): criteria.equal = 0)
	assert((await h.sharedObjects.queryObjects(U, "world", criteria)).success)
	var large: Dictionary = await h.sharedObjects.queryObjects(U, "world", {"mode":"list", "limit":50})
	assert(large.success and large.data.objects.size() == 16 and large.data.objects[15].data.size() == 65536)
	assert((await h.sharedObjects.getObject(U, "world", J)).success)
	assert((await h.sharedObjects.updateObject(U, "world", J, 1, PackedByteArray(), search, position)).errorCode == "HTTP_503")
	assert((await h.sharedObjects.deleteObject(U, "world", J, 1)).errorCode == "STORAGE_LIMIT_REACHED")
	assert(not (await h.sharedObjects.updateObject(U, "world", J, 1, PackedByteArray(), search, position)).success)
	await create_timer(.55).timeout
	assert((await h.sharedObjects.getObject(U, "world", J)).errorCode == "INVALID_RESPONSE")
	assert((await h.sharedObjects.getObject(U, "world", J)).success)
	assert((await h.sharedObjects.getObject(U, "world", J)).errorCode == "REFRESH_NOT_DUE")
	clock[0] += 120000
	assert((await h.sharedObjects.getObject(U, "world", J)).errorCode == "STALE_RESPONSE")
	clock[0] += 120000
	create_timer(.03).timeout.connect(func():
		http.activeHost = "http://127.0.0.1:9"
		http.activeHost = "http://127.0.0.1:20112")
	assert((await h.sharedObjects.getObject(U, "world", J)).errorCode == "STALE_RESPONSE")
	await create_timer(1.8).timeout
	print("Godot actual Shared Objects sample/all7 routes: opaque binary+NUL/64-bit/nulls, original If-Match, durable pre-send create/update/delete, restart/read-only reconciliation, explicit cursor, read-query frozen retry, strict/stale/ABA Cloud VA defense start/submit and single503/429/timeout passed")
	sample.free()
	h.free()
	http.queue_free()
	quit(0)
