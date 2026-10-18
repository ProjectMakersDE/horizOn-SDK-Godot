extends SceneTree
const U = "00000000-0000-4000-8000-000000001016"
const G = "00000000-0000-4000-8000-000000600001"
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_match.gd")
var checks: int = 0
func check(value: bool) -> void:
	checks += 1
	if not value: push_error("Groups metadata assertion%d" % checks); quit(1)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Groups metadata watchdog"); quit(1))
	call_deferred("_run")
func _run() -> void:
	var http := HorizonHttpClient.new(); root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger); http.apiKey = "metadata-key"; http.sessionToken = "metadata-session"; http.activeHost = "http://127.0.0.1:20118"; http.maxRetryAttempts = 0
	var auth := HorizonAuth.new(); auth.initialize(http,logger); auth._currentUser.userId = U; auth._currentUser.accessToken = "metadata-session"
	var groups := HorizonGroups.new(); groups.initialize(http,auth)
	var read: Dictionary = await groups.getGroup(U,G)
	check(read.success and read.data.name is HorizonItemStringData and read.data.description is HorizonItemStringData)
	check(read.data.name.getOriginalJson() == '"a\\u0000z"' and read.data.description.getOriginalJson() == '"d\\u0000z"')
	check(read.data.nameJson == '"a\\u0000z"' and read.data.name.getDisplayPreview() == 'a\\u0000z')
	check(HorizonGroupJsonData.metadataString('"a\\\\u0000z"') is String)
	# Native typed method rejects a carrier before reaching the transport. Expression
	# captures the expected argument error without producing an uncaught script error.
	var expression := Expression.new()
	check(expression.parse('updateGroup(user, group, 1, metadata, "", "open", {})', ["user","group","metadata"]) == OK)
	expression.execute([U,G,read.data.name],groups,false)
	check(expression.has_execute_failed())
	check((await groups.updateGroupOriginalMetadata(U,G,1,'"x" trailing','""',"open",{})).errorCode == "INVALID_GROUP")
	check((await groups.updateGroupOriginalMetadata(U,G,1,'123','""',"open",{})).errorCode == "INVALID_GROUP")
	var original: Dictionary = {"expectedRevision":1,"nameJson":'"edited\\u0000z"',"descriptionJson":read.data.descriptionJson,"joinMode":"open","dataJson":read.data.data.getJson()}
	var path: String = "user://groups-metadata-original.bin"
	check(Pending.store(path,original))
	var result: Dictionary = await groups.updateGroupOriginalMetadata(U,G,1,original.nameJson,original.descriptionJson,"open",HorizonGroupJsonData.fromJson(original.dataJson))
	check(not result.success and Pending.load_pending(path).pending == original)
	var saved: Dictionary = Pending.load_pending(path).pending
	result = await groups.updateGroupOriginalMetadata(U,G,saved.expectedRevision,saved.nameJson,saved.descriptionJson,saved.joinMode,HorizonGroupJsonData.fromJson(saved.dataJson))
	check(result.success and result.data.group.name is HorizonItemStringData and result.data.group.name.getOriginalJson() == saved.nameJson)
	check(Pending.load_pending(path).pending == original and Pending.confirm(path,original))
	http.queue_free(); await process_frame
	print("Groups metadata: %d native assertions; original NUL tokens, typed rejection, explicit edit and identical durable retry passed" % checks)
	quit(0)
