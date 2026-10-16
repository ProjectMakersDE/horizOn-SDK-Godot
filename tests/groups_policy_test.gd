extends SceneTree
const USER := "00000000-0000-4000-8000-000000001010"
const PEER := "00000000-0000-4000-8000-000000001011"
const GROUP := "00000000-0000-4000-8000-000000003010"
const REQUEST := "00000000-0000-4000-8000-000000004010"
class ControlledHttp extends HorizonHttpClient:
	var responses: Array = []
	var calls: Array = []
	var on_start: Callable
	var active: int = 0
	var peak: int = 0
	func getAsync(endpoint: String, session: bool = false) -> HorizonNetworkResponse:
		return await _respond("GET", endpoint, {}, session)
	func postJsonOnceAsync(endpoint: String, body: Dictionary = {}, session: bool = false, original_json: String = "") -> HorizonNetworkResponse:
		return await _respond("POST", endpoint, body, session, original_json)
	func putOnceAsync(endpoint: String, body: Dictionary = {}, session: bool = false, original_json: String = "") -> HorizonNetworkResponse:
		return await _respond("PUT", endpoint, body, session, original_json)
	func postAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false, _headers: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
		assert(false, "Group writes must not use retrying transport")
		return HorizonNetworkResponse.failure("Wrong transport")
	func putAsync(_endpoint: String, _body: Dictionary = {}, _session: bool = false) -> HorizonNetworkResponse:
		assert(false, "Group PUT must not use retrying transport")
		return HorizonNetworkResponse.failure("Wrong transport")
	func _respond(method: String, endpoint: String, body: Dictionary, session: bool, original_json: String = "") -> HorizonNetworkResponse:
		assert(session and not responses.is_empty())
		calls.append({"method": method, "endpoint": endpoint, "body": body.duplicate(true), "originalJson": original_json})
		active += 1
		peak = maxi(peak, active)
		var next: Dictionary = responses.pop_front()
		if on_start.is_valid(): on_start.call()
		await get_tree().create_timer(next.get("delay", .01)).timeout
		active -= 1
		if next.has("failure"):
			var response := HorizonNetworkResponse.failure("Refused", next.failure)
			response.serverCode = next.get("code", "")
			return response
		var response := HorizonNetworkResponse.success(next.data)
		response.rawBody = next.get("raw", JSON.stringify(next.data))
		return response

func _initialize() -> void:
	create_timer(25).timeout.connect(func():
		push_error("Groups policy did not complete")
		quit(1))
	call_deferred("_run")

func _run() -> void:
	var http := ControlledHttp.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "groups-project"
	http.activeHost = "https://one.invalid"
	http.sessionToken = "session"
	var auth := HorizonAuth.new()
	auth.initialize(http, logger)
	auth._currentUser.userId = USER
	auth._currentUser.accessToken = "session"
	var groups := HorizonGroups.new()
	groups.initialize(http, auth)
	http.responses = [{"data": _snapshot(1, 1)}]
	var result: Dictionary = await groups.getGroups(USER)
	assert(result.success and typeof(result.data.revision) == TYPE_INT and result.data.groups[0].data.getPreview()["$key"][""] == {} and result.data.groups[0].data.getPreview().revision == 1.5)
	result.data.groups[0].data.getPreview().clear()
	assert(not groups.getCurrentGroups().groups[0].data.getPreview().is_empty(), "Own snapshot is copied")
	var original_data: String = '{"seed":9007199254740993,"huge":123456789012345678901234567890,"decimal":1.0000000000000000000001,"$":{"id":"fake","data":{"":null}},"revision":1.5}'
	var lossless: HorizonGroupJsonData = HorizonGroupJsonData.fromJson(original_data)
	assert(lossless != null and lossless.getJson() == original_data)
	assert(HorizonGroupJsonData.fromJson('  { "space": "a b" }  ').getJson() == '{"space":"a b"}')
	for invalid: String in ['{"x":1,}', '{"x":[1,]}', '{}{}', '{"x":01}', '{"x":1} garbage', '{"x":1}//comment', '{"x":"line\nraw"}'.replace("\\n", "\n")]:
		assert(HorizonGroupJsonData.fromJson(invalid) == null, "Strict JSON grammar rejects " + invalid)
	assert(HorizonGroupJsonData.fromDictionary({"seed":9007199254740993}).getJson().contains("9007199254740993"))
	var repeated: String = '{"groups":{"groups":[{"id":"' + GROUP + '","data":{"a":1,"b":"é"}}]},"group":{"data": { "b": "\\u00e9", "a": 1 },"id":"' + GROUP + '"}}'
	var fragments: Dictionary = HorizonGroupJsonData.extract(repeated)
	assert(not fragments.has("_invalid") and HorizonGroupJsonData.fromJson(fragments[GROUP]).getPreview() == {"a":1.0,"b":"é"}, "Indent/order/string-escape differences must not reject a committed mutation")
	assert(HorizonGroupJsonData.extract(repeated.replace('"a": 1', '"a": 2')).has("_invalid"), "Conflicting duplicate group data fails closed")

	assert(HorizonGroupJsonData.fromJson('{"a":1,"\\u0061":2}') == null and HorizonGroupJsonData.fromJson('[]') == null)
	assert(HorizonGroupJsonData.fromJson('{"a":1e999}') == null)
	var exact: Dictionary = _group(1)
	exact.data = lossless.getPreview()
	var raw: String = JSON.stringify(exact).replace(JSON.stringify(exact.data), original_data)
	http.responses = [{"data": exact, "raw": raw}]
	var restored: Dictionary = await groups.getGroup(USER, GROUP)
	assert(restored.success and restored.data.data.getJson() == original_data)
	var preview: Dictionary = restored.data.data.getPreview()
	preview.seed = 0
	assert(restored.data.data.getJson() == original_data and not groups.getCurrentGroups().groups[0].data.getPreview().is_empty())
	http.responses = [{"failure": 409, "code": "REVISION_CONFLICT"}]
	assert((await groups.updateGroup(USER, GROUP, 1, "Guild", "", "open", restored.data.data)).errorCode == "REVISION_CONFLICT")
	assert(http.calls[-1].originalJson.contains(original_data) and http.calls[-1].originalJson.contains('"description":""'))
	http.responses = [{"data": _snapshot(1, 1)}]
	assert((await groups.getGroups(USER)).success)

	var count: int = http.calls.size()
	for revision: Variant in [-1, 1.0, 1.5, "1", true, null, 9007199254740992]:
		assert((await groups.joinGroup(USER, GROUP, revision)).errorCode == "INVALID_REVISION")
	for bad: String in ["", "1-2-3-4-5", GROUP + "\n"]:
		assert((await groups.getGroup(USER, bad)).errorCode == "INVALID_GROUP_ACTION")
	assert((await groups.getGroups(PEER)).errorCode == "SESSION_FORBIDDEN")
	assert((await groups.acceptInvite(USER, GROUP, 1, "")).errorCode == "INVALID_GROUP_ACTION")
	assert((await groups.invitePlayer(USER, GROUP, 1, USER)).errorCode == "INVALID_GROUP_ACTION")
	assert((await groups.setMemberRole(USER, GROUP, 1, PEER, "leader")).errorCode == "INVALID_GROUP_ACTION")
	assert((await groups.getMembers(USER, GROUP, "", 50.0)).errorCode == "INVALID_PAGE")
	for metadata: Dictionary in [{"name": " ", "data": {}}, {"name": "x", "data": {"x": INF}}, {"name": "x", "data": {"x": "a".repeat(2041)}}, {"name": "é".repeat(61), "data": {}}]:
		assert((await groups.createGroup(USER, 0, metadata.name, "", "open", metadata.data)).errorCode == "INVALID_GROUP")
	assert(http.calls.size() == count, "Invalid intent never reaches HTTP")
	# Response lexemes outside arbitrary data must be exact safe integers; duplicate decoded keys fail.
	for wire: String in ['{"revision":1e0}', '{"revi\u0073ion":1.0000000000000001}', '{"revision":9007199254740992}', '{"revision":"2","revision":2}', '{"data":{"x":1,"\u0078":2}}']:
		http.responses = [{"data": _snapshot(2, 2), "raw": wire}]
		assert((await groups.getGroups(USER)).errorCode == "INVALID_RESPONSE" and groups.getCurrentGroups().revision == 1)
	# Invalid partial normalization must not poison the committed group revision floor.
	var poisoned: Dictionary = _snapshot(100, 2)
	poisoned.incomingInvites = [null]
	http.responses = [{"data": poisoned}, {"data": _snapshot(2, 2)}]
	assert((await groups.getGroups(USER)).errorCode == "INVALID_RESPONSE")
	assert((await groups.getGroups(USER)).success)
	for stale: Dictionary in [_snapshot(1, 3), _snapshot(3, 1)]:
		http.responses = [{"data": stale}]
		assert((await groups.getGroups(USER)).errorCode == "STALE_RESPONSE" and groups.getCurrentGroups().revision == 2)
	# Public metadata strips private data even if a broken server includes it.
	var public: Dictionary = _group(2)
	public.erase("myRole")
	public["email"] = "private"
	http.responses = [{"data": public}]
	result = await groups.getGroup(USER, GROUP)
	assert(result.success and not result.data.has("data") and not result.data.has("email") and groups.getCurrentGroups().revision == 2)
	var display: Dictionary = {"name": null, "profile": {"avatarId": null, "frameId": null, "badges": [], "secret": true}, "email": "private"}
	var page: Dictionary = {"groupId": GROUP, "revision": 2, "members": [{"userId": USER, "role": "leader", "joinedAt": _time(1), "display": display}], "nextAfterUserId": USER, "serverTime": _time(2)}
	http.responses = [{"data": page}]
	result = await groups.getMembers(USER, GROUP, "", 1)
	assert(result.success and result.data.nextAfterUserId == USER and result.data.members[0].display.name == null and result.data.members[0].display.profile.keys().size() == 3)
	assert(http.calls[-1].endpoint.ends_with("?userId=" + USER + "&limit=1"))
	var bad_page: Dictionary = page.duplicate(true)
	bad_page.nextAfterUserId = PEER
	http.responses = [{"data": bad_page}]
	assert((await groups.getMembers(USER, GROUP, "", 1)).errorCode == "INVALID_RESPONSE")
	# Retained memberships over a downgraded one-group tier are still readable.
	var retained: Dictionary = _snapshot(3, 3)
	var other: Dictionary = _group(1)
	other.id = PEER
	retained.groups.append(other)
	http.responses = [{"data": retained}]
	assert((await groups.getGroups(USER)).data.groups.size() == 2)
	var original: String = REQUEST.to_upper()
	http.responses = [{"failure": 409, "code": "REQUEST_NOT_FOUND"}]
	assert((await groups.acceptInvite(USER, GROUP, 4294967296, original)).errorCode == "REQUEST_NOT_FOUND")
	assert(http.calls[-1].body == {"userId": USER, "expectedRevision": 4294967296, "requestId": original} and groups.getCurrentGroups().is_empty())
	# Bound detail revision memory, independent of lifetime queried group IDs.
	for index: int in range(60):
		var row: Dictionary = _group(1)
		row.id = "00000000-0000-4000-8000-%012d" % (9000 + index)
		http.responses = [{"data": row}]
		assert((await groups.getGroup(USER, row.id)).success)
	assert(groups._floors.size() == 48)
	# Queue capture freezes the original metadata before any wait; calls are serialized.
	auth.signout_completed.emit()
	http.responses = [{"data": _snapshot(1, 1), "delay": .1}, {"failure": 409, "code": "REVISION_CONFLICT"}]
	var first: Dictionary = {}
	var second: Dictionary = {}
	var intent: Dictionary = {"original": 1.5}
	_load(groups, first)
	await create_timer(.02).timeout
	_create(groups, intent, second)
	intent.original = 99
	await create_timer(.2).timeout
	assert(first.result.success and second.result.errorCode == "REVISION_CONFLICT" and http.peak == 1 and http.calls[-1].body.data == {"original": 1.5} and http.calls[-1].body.expectedPlayerRevision == 0)
	for property: String in ["activeHost", "apiKey", "sessionToken"]:
		http.responses = [{"data": _snapshot(3, 3), "delay": .08}]
		var old: String = http.get(property)
		create_timer(.02).timeout.connect(func():
			http.set(property, old + "-temporary")
			http.set(property, old))
		assert((await groups.getGroups(USER)).errorCode == "STALE_RESPONSE" and groups.getCurrentGroups().is_empty())
	http.responses = [{"data": _snapshot(1, 1), "delay": .1}]
	first.clear()
	second.clear()
	count = http.calls.size()
	_load(groups, first)
	await create_timer(.02).timeout
	_load(groups, second)
	groups.clearCache()
	await create_timer(.15).timeout
	assert(first.result.errorCode == "STALE_RESPONSE" and second.result.errorCode == "STALE_RESPONSE" and http.calls.size() == count + 1)
	var callback: Callable = func(_data: Dictionary):
		http.sessionToken = "temporary"
		http.sessionToken = "session"
	groups.groups_loaded.connect(callback)
	http.responses = [{"data": _snapshot(2, 2)}]
	assert((await groups.getGroups(USER)).errorCode == "STALE_RESPONSE" and groups.getCurrentGroups().is_empty())
	groups.groups_loaded.disconnect(callback)
	http.sessionToken = ""
	assert((await groups.getGroups(USER)).errorCode == "SESSION_REQUIRED")
	print("Godot Groups policy: safe original revisions/IDs, arbitrary object data, bounded pages/floors, downgrade retention, atomic normalization and queue/callback/context ABA passed")
	http.queue_free()
	quit(0)

func _group(revision: int) -> Dictionary:
	return {"id": GROUP, "revision": revision, "name": "Guild", "description": "", "joinMode": "open", "leaderId": USER, "memberCount": 1, "myRole": "leader", "data": {"revision": 1.5, "$key": {"": {}, "a.b": []}}, "createdAt": _time(1), "updatedAt": _time(1)}
func _snapshot(revision: int, second: int) -> Dictionary:
	return {"userId": USER, "revision": revision, "groups": [_group(revision)], "incomingInvites": [], "outgoingRequests": [], "limits": {"maxMembers": 20, "maxGroupsPerPlayer": 1, "maxInvitations": 20, "maxJoinRequests": 20, "maxDataBytes": 2048, "memberPageSize": 50}, "serverTime": _time(second)}
func _time(second: int) -> String: return "2026-10-16T12:00:%02dZ" % second
func _load(groups: HorizonGroups, result: Dictionary) -> void: result.result = await groups.getGroups(USER)
func _create(groups: HorizonGroups, data: Dictionary, result: Dictionary) -> void: result.result = await groups.createGroup(USER, 0, "Guild", "", "open", data)
