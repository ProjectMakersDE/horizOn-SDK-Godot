extends SceneTree
const Sample = preload("res://addons/horizon_sdk/examples/features/matches_example.gd")
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_match.gd")
const U := "00000000-0000-4000-8000-000000001013"
const V := "00000000-0000-4000-8000-000000002013"
const I := "00000000-0000-4000-8000-000000004013"
class FakeManager extends RefCounted:
	var calls: int = 0
	var revision: int = 4294967296
	var uncertain: bool = false
	var hook: Callable
	func getMatches(_user: String,_recovery: bool=false) -> Dictionary: return {"success":true,"data":{"revision":revision,"active":[],"invites":[],"recent":[],"pendingResults":[]}}
	func createMatch(_user: String,_revision: int,_options: Dictionary) -> Dictionary:
		calls += 1
		revision += 1
		if hook.is_valid(): hook.call()
		return {"success":not uncertain,"data":{"match":{"id":I,"revision":1}},"errorCode":"HTTP_503" if uncertain else "","error":""}
class Fixture extends Node:
	var _http: HorizonHttpClient
	var auth: HorizonAuth
	var matches: FakeManager
class FaultSample extends Sample:
	var saveAllowed: bool = true
	var ackAllowed: bool = true
	var selectionOnSave: bool = false
	func _store(file: String,intent: Dictionary) -> bool:
		if not saveAllowed: return false
		var success: bool = super._store(file,intent)
		if selectionOnSave: clear_review()
		return success
	func _confirm(file: String,intent: Dictionary) -> bool: return ackAllowed and super._confirm(file,intent)
var checks: int = 0
var failures: int = 0
func ok(value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("Matches check failed at %s" % checks)
func options() -> Dictionary: return {"name":"game","capacity":2,"visibility":"private","strength":1,"turnSeconds":60,"timeoutPolicy":"forfeit","ranked":false,"dataBase64":"AA==","inviteeIds":[V]}
func _initialize() -> void:
	create_timer(10).timeout.connect(func():quit(1))
	call_deferred("_run")
func _run() -> void:
	var http := HorizonHttpClient.new()
	root.add_child(http)
	var logger := HorizonLogger.new(HorizonLogger.LogLevel.NONE)
	http.initialize(logger)
	http.apiKey = "sample-matches-policy"
	http.activeHost = "http://original"
	http.sessionToken = "matches-policy-token"
	var h := Fixture.new()
	h.name = "Horizon"
	h._http = http
	h.auth = HorizonAuth.new()
	h.auth.initialize(http,logger)
	h.auth._currentUser.userId = U
	h.auth._currentUser.accessToken = http.sessionToken
	h.matches = FakeManager.new()
	root.add_child(h)
	var sample := FaultSample.new()
	root.add_child(sample)
	var path: String = Pending.path(http.apiKey,U)
	ok((await sample.read_matches()).success)
	var self_invite: Dictionary = options()
	self_invite.inviteeIds = [U.to_upper()]
	ok((await sample.create_reviewed(self_invite)).errorCode == "INVALID_REQUEST" and h.matches.calls == 0 and not FileAccess.file_exists(path))
	sample.saveAllowed = false
	ok((await sample.create_reviewed(options())).errorCode == "PENDING_STORAGE_ERROR" and h.matches.calls == 0)
	sample.saveAllowed = true
	sample.selectionOnSave = true
	ok((await sample.create_reviewed(options())).errorCode == "STALE_RESPONSE" and h.matches.calls == 0)
	var original: Dictionary = Pending.load_pending(path).pending
	ok(original.kind == "create" and original.expectedRevision == 4294967296)
	var other := FaultSample.new()
	root.add_child(other)
	ok((await other.read_matches()).success)
	ok((await other.create_reviewed(options())).errorCode == "PENDING_ACTION" and h.matches.calls == 0)
	ok((await other.inspect_pending()).success)
	ok(other.acknowledge_reconciliation().errorCode == "UNCONFIRMED_ACTION")
	ok(Pending.load_pending(path).pending == original)
	h.matches.revision += 1
	ok((await other.inspect_pending()).success)
	other.ackAllowed = false
	ok(other.acknowledge_reconciliation().errorCode == "PENDING_STORAGE_ERROR")
	ok(Pending.load_pending(path).pending == original)
	other.ackAllowed = true
	http.activeHost = "http://regional"
	ok(other.acknowledge_reconciliation().errorCode == "REVIEW_REQUIRED")
	ok(Pending.path(http.apiKey,U) == path and Pending.load_pending(path).pending == original)
	ok((await other.inspect_pending()).success and other.acknowledge_reconciliation().success)
	ok(not FileAccess.file_exists(path))
	ok((await other.read_matches()).success)
	other.ackAllowed = false
	ok((await other.create_reviewed(options())).errorCode == "PENDING_STORAGE_ERROR" and h.matches.calls == 1)
	original = Pending.load_pending(path).pending
	ok(original.expectedRevision == 4294967297)
	ok((await other.create_reviewed(options())).errorCode == "PENDING_ACTION" and h.matches.calls == 1)
	other.free()
	other = FaultSample.new()
	root.add_child(other)
	ok((await other.inspect_pending()).success and other.acknowledge_reconciliation().success)
	ok((await other.read_matches()).success)
	h.matches.hook = func():other.clear_review()
	ok((await other.create_reviewed(options())).errorCode == "STALE_RESPONSE" and h.matches.calls == 2)
	original = Pending.load_pending(path).pending
	ok(not original.is_empty() and Pending.confirm(path,original))
	h.matches.hook = Callable()
	ok((await other.read_matches()).success)
	h.matches.uncertain = true
	ok((await other.create_reviewed(options())).errorCode == "HTTP_503")
	original = Pending.load_pending(path).pending
	ok((await other.retry_original_report_or_run()).errorCode == "RECOVERY_READ_REQUIRED" and h.matches.calls == 3)
	ok(Pending.load_pending(path).pending == original)
	ok((await other.inspect_pending()).success)
	ok(other.acknowledge_reconciliation().success)
	ok((await other.read_matches()).success)
	var corrupt := FileAccess.open(path,FileAccess.WRITE)
	corrupt.store_var({"invalid":"corrupt original journal"}, false)
	corrupt.close()
	ok((await other.create_reviewed(options())).errorCode == "PENDING_STORAGE_ERROR" and h.matches.calls == 3)
	ok(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	var next_file := FileAccess.open(path+".next",FileAccess.WRITE)
	next_file.store_string("incomplete durable write")
	next_file.close()
	ok(not Pending.load_pending(path).success)
	ok(DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".next")) == OK)
	ok(not Pending.store(path,{}) or not Pending.load_pending(path).success) # An empty/corrupt journal never authorizes a replacement.
	if FileAccess.file_exists(path): ok(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	if failures == 0: print("PASS: Matches actual sample storage/restart/selection/context/ACK/corruption checks=%s"%checks)
	sample.free();other.free();h.free();http.queue_free()
	quit(0 if failures == 0 else 1)
