extends SceneTree
const Models = preload("res://addons/horizon_sdk/models/shared_object_models.gd")
const Sample = preload("res://addons/horizon_sdk/examples/features/shared_objects_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_shared_object.gd")
const U := "00000000-0000-4000-8000-000000001012"
const I := "00000000-0000-4000-8000-000000003012"
const T := "2026-10-16T12:00:00Z"
class FakeHttp extends HorizonHttpClient:
	var reply: Dictionary = {}
	var calls: int = 0
	var aba: bool = false
	func getAsync(_endpoint: String, _session: bool = false) -> HorizonNetworkResponse:
		calls += 1
		if aba:
			aba = false
			var before: String = apiKey
			apiKey = "changed"
			apiKey = before
		var response := HorizonNetworkResponse.success(reply.duplicate(true))
		response.rawBody = HorizonSharedObjectModels.encode(reply)
		return response
	func postJsonAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false, _json: String = "") -> HorizonNetworkResponse:
		return await getAsync(_endpoint, _session)
	func postAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		calls += 1
		var failed := HorizonNetworkResponse.failure("uncertain",503,HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
		failed.serverCode = "NETWORK_ERROR"
		return failed
class SampleManager extends RefCounted:
	var calls: int = 0
	var revision: int = 4294967296
	var current: Dictionary = {}
	func getUsage(_user: String, _collection: String) -> Dictionary:
		return {"success":true,"data":{"userId":U,"collection":"world","revision":revision},"errorCode":"","error":""}
	func getRecoveryUsage(user: String, collection: String) -> Dictionary: return await getUsage(user, collection)
	func queryRecoveryObjects(_user: String, _collection: String, _query: Dictionary) -> Dictionary:
		return {"success":true,"data":{"objects":[] if current.is_empty() else [current.duplicate(true)],"nextCursor":null},"errorCode":"","error":""}
	func createObject(_user: String, _collection: String, _revision: Variant, _bytes: PackedByteArray, _search: Dictionary, _position: Variant = null, _group: String = "") -> Dictionary:
		calls += 1
		revision += 1
		current = {"id":I,"collection":"world","ownerId":U,"revision":1,"groupId":null}
		return {"success":true,"data":{"object":current.duplicate(true)},"errorCode":"","error":""}
class FixtureHorizon extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var sharedObjects: SampleManager
	var validatedActions: HorizonValidatedActions
class FaultSample extends Sample:
	var saveAllowed: bool = true
	var ackAllowed: bool = true
	var invalidateSelectionOnStore: bool = false
	func _store(file: String, intent: Dictionary) -> bool:
		if not saveAllowed: return false
		var saved: bool = super._store(file, intent)
		if invalidateSelectionOnStore: clear_review()
		return saved
	func _confirm(file: String, intent: Dictionary) -> bool: return ackAllowed and super._confirm(file, intent)
var checks: int = 0
func ok(value: bool) -> void:
	checks += 1
	assert(value)
func row() -> Dictionary: return {"id": I, "collection": "world", "ownerId": U, "groupId": null, "revision": 1, "dataBase64": "AP8BAIA=", "search": {"power": 9007199254740991, "label": "ordinary"}, "position": {"x": 9007199254740991, "y": -1}, "createdAt": T, "updatedAt": T, "expiresAt": null}
func caps() -> Dictionary: return {"collections": 2, "storageBytes": 5242880, "objectBytes": 2048}
func usage() -> Dictionary: return {"userId": U, "collection": "world", "revision": 4294967296, "count": 3, "limits": caps(), "pollAfterSeconds": 120, "serverTime": T}
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for raw: String in ['{"revision":1.5}', '{"revision":1e2}', '{"revision":9007199254740992}', '{"revision":-9007199254740992}', '{"revision":1,"revi\\u0073ion":2}', '{"x":"\\ud800"}', '{"x":[1,]}', '{"x":01}']:
		ok(Models.parse(raw).is_empty())
	ok(Models.parse('{"revision":9007199254740991}').revision == 9007199254740991)
	var nul: Variant = Models.parse('{"label":"a\\u0000é/😀"}').label
	ok(nul is HorizonItemStringData and nul.getJson() == '"a\\u0000é/😀"')
	ok(Models.search({"label": nul}) and Models.encode({"label": nul}) == '{"label":"a\\u0000é/😀"}')
	ok(Models.encode({"position": null, "false": false, "empty": {}}) == '{"empty":{},"false":false,"position":null}')
	ok(Models.object(row(), "world").data == PackedByteArray([0,255,1,0,128]))
	for key: String in ["groupId", "position", "expiresAt"]:
		var missing: Dictionary = row()
		missing.erase(key)
		ok(Models.object(missing, "world").is_empty())
	for invalid: Variant in ["A", "AA", "AA=", "AB==", "AA==\n", "!!!!", 1, null]:
		ok(Models.decodeBytes(invalid) == null)
	ok(Models.decodeBytes("") is PackedByteArray)
	var large := PackedByteArray()
	large.resize(65536)
	var retained: Dictionary = row()
	retained.dataBase64 = Marshalls.raw_to_base64(large)
	ok(Models.object(retained, "world").data.size() == 65536) # Retained data may exceed current2KiB tier.
	large.resize(65537)
	ok(Models.decodeBytes(Marshalls.raw_to_base64(large)) == null)
	ok(Models.usage(usage(), "world", U))
	var point: Dictionary = {"object": row(), "pollAfterSeconds": 120, "serverTime": T}
	ok(not Models.response(point, "get", U, "world", I, null, {}).is_empty())
	ok(Models.response(point, "get", U, "other", I, null, {}).is_empty())
	var page: Dictionary = {"objects": [], "nextCursor": "exact-original", "pollAfterSeconds": 120, "serverTime": T}
	ok(not Models.response(page, "query", U, "world", "", null, {"mode": "rectangle", "limit": 50}).is_empty())
	ok(Models.response(page, "query", U, "world", "", null, {"mode": "random", "limit": 50}).is_empty())
	page.objects = [row(), row()]
	ok(Models.response(page, "query", U, "world", "", null, {"mode": "owner", "limit": 50}).is_empty())
	page.objects = []
	for n: int in range(17):
		var entry: Dictionary = retained.duplicate(true)
		entry.id = "00000000-0000-4000-8000-%012d" % n
		page.objects.append(entry)
	ok(Models.response(page, "query", U, "world", "", null, {"mode": "list", "limit": 50}).is_empty())
	for invalid: Dictionary in [{"mode":"field","field":"power","equal":1.0}, {"mode":"field","field":"power","equal":1,"min":0,"max":2}, {"mode":"random","field":"label","min":"a","max":"b"}, {"mode":"list","userId":U}, {"mode":"rectangle","minX":0,"maxX":1,"minY":0,"maxY":1,"limit":51}]:
		ok(not Models.query(invalid))
	ok(Models.query({"mode":"owner","ownerId":U,"cursor":"verbatim-next"}))
	var manager := HorizonSharedObjects.new()
	manager._revisions = {"object:world:" + I: 2}
	ok(not manager._fresh("get", "world", point))
	manager._revisions.clear()
	manager._record("delete", "world", {"objectId":I,"usage":usage(),"serverTime":T})
	ok(not manager._fresh("get", "world", point))
	for n: int in range(520): manager._cache[str(n)] = {}
	manager._trim(manager._cache, 8)
	ok(manager._cache.size() == 8)
	var extra: Dictionary = usage()
	extra.object = null
	extra.objects = [null]
	var safe_usage: Dictionary = Models.response(extra, "usage", U, "world", "", null, {})
	ok(not safe_usage.is_empty() and manager._versions("usage", "world", safe_usage).size() == 1)
	var http := FakeHttp.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "project-a"
	http.activeHost = "http://127.0.0.1:1"
	http.sessionToken = "token-a"
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = U
	auth._currentUser.accessToken = http.sessionToken
	manager = HorizonSharedObjects.new()
	manager.initialize(http, auth)
	var clock: Array[int] = [0]
	manager._nowMillis = func() -> int: return clock[0]
	http.reply = usage()
	var first: Dictionary = await manager.getUsage(U, "world")
	ok(first.success and manager.getRefreshDelaySeconds(first.identity) == 120)
	ok((await manager.getUsage(U, "world")).errorCode == "REFRESH_NOT_DUE" and http.calls == 1)
	clock[0] = 120000
	ok((await manager.getUsage(U, "world")).success and http.calls == 2)
	var other: String = "00000000-0000-4000-8000-000000001013"
	http.apiKey = "project-b"
	http.sessionToken = "token-b"
	auth._currentUser.userId = other
	auth._currentUser.accessToken = http.sessionToken
	http.reply = usage()
	http.reply.userId = other
	var second: Dictionary = await manager.getUsage(other, "world")
	ok(second.success and first.identity != second.identity and manager.getCached(first.identity).is_empty())
	http.apiKey = "project-a"
	http.apiKey = "project-b"
	var third: Dictionary = await manager.getUsage(other, "world")
	ok(third.success and third.identity != second.identity and manager.getCached(second.identity).is_empty())
	http.reply = {"objects":[],"nextCursor":"next-original","pollAfterSeconds":120,"serverTime":T}
	ok((await manager.queryObjects(other, "world", {"mode":"list"})).success)
	var before: int = http.calls
	ok((await manager.queryObjects(other, "world", {"mode":"list"})).errorCode == "REFRESH_NOT_DUE" and http.calls == before)
	ok((await manager.queryObjects(other, "world", {"mode":"list","cursor":"next-original"})).success and http.calls == before + 1)
	http.reply.nextCursor = null
	ok((await manager.queryObjects(other, "world", {"mode":"random","field":"power","min":0,"max":1})).success)
	before = http.calls
	ok((await manager.queryObjects(other, "world", {"mode":"random","field":"power","min":0,"max":1})).errorCode == "REFRESH_NOT_DUE" and http.calls == before)
	http.reply = usage()
	http.reply.userId = other
	ok((await manager.getRecoveryUsage(other, "world")).success)
	clock[0] += 120000
	http.aba = true
	ok((await manager.getUsage(other, "world")).errorCode == "STALE_RESPONSE")
	# Execute the original sample, overriding only its disk fault boundaries.
	http.apiKey = "sample-policy-project"
	http.sessionToken = "sample-policy-token"
	auth._currentUser.userId = U
	auth._currentUser.accessToken = http.sessionToken
	var h := FixtureHorizon.new()
	h.name = "Horizon"
	h._http = http
	h.auth = auth
	h.sharedObjects = SampleManager.new()
	root.add_child(h)
	var sample := FaultSample.new()
	root.add_child(sample)
	var sample_path: String = Pending.path(http.apiKey, U)
	ok((await sample.read_usage("world")).success)
	sample.saveAllowed = false
	ok((await sample.create_marker(PackedByteArray([1]), {})).errorCode == "PENDING_STORAGE_ERROR" and h.sharedObjects.calls == 0 and not FileAccess.file_exists(sample_path))
	sample.saveAllowed = true
	sample.invalidateSelectionOnStore = true
	ok((await sample.create_marker(PackedByteArray([1]), {})).errorCode == "STALE_RESPONSE" and h.sharedObjects.calls == 0)
	var saved: Dictionary = Pending.load_pending(sample_path).pending
	ok(not saved.is_empty())
	var second_sample := FaultSample.new()
	root.add_child(second_sample)
	ok((await second_sample.read_usage("world")).success)
	ok((await second_sample.create_marker(PackedByteArray([2]), {})).errorCode == "PENDING_ACTION" and h.sharedObjects.calls == 0)
	var recovery: Dictionary = await second_sample.inspect_pending()
	ok(recovery.success and recovery.data.complete and not recovery.data.has("context") and not str(recovery.data).contains("sample-policy-token"))
	ok(second_sample.acknowledge_reconciliation().errorCode == "UNCONFIRMED_ACTION" and Pending.load_pending(sample_path).pending == saved)
	ok(Pending.confirm(sample_path, saved))
	second_sample.free()
	sample.invalidateSelectionOnStore = false
	sample.ackAllowed = false
	ok((await sample.read_usage("world")).success)
	ok((await sample.create_marker(PackedByteArray([1]), {})).errorCode == "PENDING_STORAGE_ERROR" and h.sharedObjects.calls == 1 and FileAccess.file_exists(sample_path))
	saved = Pending.load_pending(sample_path).pending
	ok((await sample.inspect_pending()).success)
	ok(sample.acknowledge_reconciliation().errorCode == "PENDING_STORAGE_ERROR" and Pending.load_pending(sample_path).pending == saved)
	sample.ackAllowed = true
	ok(sample.acknowledge_reconciliation().success and not FileAccess.file_exists(sample_path))
	ok(h.sharedObjects.calls == 1) # Reconciliation did not repeat the write.
	sample.free()
	h.validatedActions = HorizonValidatedActions.new()
	h.validatedActions.initialize(http, logger, auth)
	sample = FaultSample.new()
	root.add_child(sample)
	ok((await sample.begin_defense_run(row(), "defense")).errorCode == "NETWORK_ERROR")
	h.validatedActions.discardRun()
	ok((await sample.begin_defense_run(row(), "defense")).errorCode == "PENDING_RUN")
	sample._defense = {"context":sample._context(h),"object":row(),"run":{"runId":I,"ticket":"sample-ticket"},"submitted":false}
	h.validatedActions._currentRun = {"runId":I,"ticket":"sample-ticket"}
	h.validatedActions._currentRunUserId = U
	ok((await sample.submit_defense_run(123, "R1".to_utf8_buffer())).errorCode == "NETWORK_ERROR")
	h.validatedActions.discardRun()
	ok((await sample.begin_defense_run(row(), "defense")).errorCode == "PENDING_RUN")
	sample.free()
	h.free()
	http.queue_free()
	var path: String = Pending.path("project-shared", U)
	var intent: Dictionary = {"unchanged": 9007199254740991}
	ok(Pending.store(path, intent))
	ok(not Pending.store(path, {"other": true}))
	ok(not Pending.confirm(path, {"unchanged": 1}))
	ok(Pending.load_pending(path).pending == intent)
	ok(Pending.confirm(path, intent))
	var interrupted := FileAccess.open(path + ".next", FileAccess.WRITE)
	interrupted.store_8(1)
	interrupted.close()
	ok(not Pending.load_pending(path).success)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".next"))
	var lock: String = ProjectSettings.globalize_path(path + ".lock")
	DirAccess.make_dir_absolute(lock)
	ok(not Pending.store(path, intent))
	DirAccess.remove_absolute(lock)
	print("Godot Shared Objects policy: %d assertions; strict original integer/Unicode/NUL/Base64/null/byte/page limits, retention, stale/tombstone and durable CAS/lock/interruption passed" % checks)
	quit(0)
