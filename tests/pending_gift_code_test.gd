extends SceneTree
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_gift_code.gd")
const Identity = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const Sample = preload("res://addons/horizon_sdk/examples/features/gift_codes_example.gd")
class FakeAuth extends RefCounted:
	var signed: bool = false
	var signups: int = 0
	var restores: int = 0
	func isSignedIn() -> bool: return signed
	func signUpAnonymous(_name: String) -> bool:
		signups += 1
		return false
	func signInAnonymous(_token: String) -> bool:
		restores += 1
		return false
class FakeHorizon extends Node:
	var auth: FakeAuth = FakeAuth.new()
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var project: String = "gift-project"
	var user_id: String = "00000000-0000-4000-8000-000000001007"
	var intent: Dictionary = {"protocolVersion":2,"projectScope":project.sha256_text(),"userId":user_id,"code":"WELCOME2026","campaignId":"00000000-0000-4000-8000-000000001007","expectedCount":"9007199254740993","configRevision":"9223372036854775807"}
	var file: String = Pending.path(project,user_id)
	var lock: String = ProjectSettings.globalize_path(file + ".lock")
	assert(DirAccess.make_dir_absolute(lock) == OK)
	assert(not Pending.store(project,intent),"Concurrent process cannot replace an intent")
	DirAccess.remove_absolute(lock)
	assert(Pending.store(project,intent))
	assert(Pending.load_pending(project,user_id).pending == intent,"Exact original ID/code survives reload")
	assert(not Pending.store(project,intent),"Unknown original cannot be replaced")
	assert(Pending.load_pending("other-project",user_id).pending.is_empty())
	assert(Pending.load_pending(project,"other-player").pending.is_empty())
	var wrong: Dictionary = intent.duplicate(true)
	wrong.expectedCount = "9007199254740994"
	assert(not Pending.confirm(project,wrong),"Late completion cannot delete another ID")
	wrong = intent.duplicate(true)
	wrong.code = "OTHER"
	assert(not Pending.confirm(project,wrong),"Original payload is immutable")
	wrong = intent.duplicate(true)
	wrong.expectedCount += "\n"
	assert(not Pending.valid(wrong,project,user_id),"ID validation consumes the exact full string")
	var next: FileAccess = FileAccess.open(file + ".next",FileAccess.WRITE)
	next.store_var(intent,false)
	next.close()
	assert(not Pending.load_pending(project,user_id).success and not Pending.confirm(project,intent),"Interrupted write remains for reconciliation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file + ".next"))
	assert(Pending.confirm(project,intent))
	var corrupt: FileAccess = FileAccess.open(file,FileAccess.WRITE)
	corrupt.store_var({"corrupt":true},false)
	corrupt.close()
	assert(not Pending.load_pending(project,user_id).success and not Pending.store(project,intent),"Corruption cannot silently create another booking")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	var horizon: FakeHorizon = FakeHorizon.new()
	var sample: Node = Sample.new()
	horizon.auth.signed = true
	assert(await sample._authenticate(horizon,"gift-existing"))
	assert(not Identity.reserve_signup("gift-existing"),"Existing identity guard survives cache loss")
	horizon.auth.signed = false
	assert(not await sample._authenticate(horizon,"gift-uncertain-signup"))
	assert(not await sample._authenticate(horizon,"gift-uncertain-signup"))
	assert(horizon.auth.signups == 1,"Uncertain signup is never repeated by a later sample launch")
	var cache: ConfigFile = ConfigFile.new()
	cache.set_value("cache",HorizonAuth.CACHE_KEY_ANONYMOUS_TOKEN,"known-original-token")
	assert(cache.save("user://horizon_cache.cfg") == OK)
	assert(not await sample._authenticate(horizon,"gift-restore"))
	assert(not await sample._authenticate(horizon,"gift-restore"))
	assert(horizon.auth.signups == 1 and horizon.auth.restores == 2,"Failed restore never creates a replacement guest")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://horizon_cache.cfg"))
	sample.free()
	horizon.free()
	print("Godot pending gift intent persistence, scope, original ID/payload, corruption, concurrency and identity guard passed")
	quit(0)
