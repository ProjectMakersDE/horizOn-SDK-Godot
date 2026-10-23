extends SceneTree
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const Sample = preload("res://addons/horizon_sdk/examples/features/statistics_example.gd")
class ExistingAuth extends RefCounted:
	func isSignedIn() -> bool: return true
class ExistingHorizon extends Node:
	var auth := ExistingAuth.new()
const OP := "1792152000000:00000000-0000-4000-8000-000000001005"
func _initialize() -> void:
	var project := "statistics-project-a"
	var user_id := "statistics-player"
	var intent := {"userId": user_id, "operationId": OP, "updates": [{"key": "kills", "value": 4294967296}, {"key": "best_score", "value": 9007199254740990}]}
	var lock_path := ProjectSettings.globalize_path(Pending.pending_path(project, user_id) + ".lock")
	assert(DirAccess.make_dir_absolute(lock_path) == OK)
	assert(not Pending.store(project, intent), "Another process serializes pending creation")
	DirAccess.remove_absolute(lock_path)
	assert(Pending.store(project, intent))
	assert(Pending.load_pending(project, user_id).pending == intent, "Exact original int64 payload survives reload")
	assert(Pending.load_pending("project-b", user_id).pending.is_empty(), "Other project cannot inherit an intent")
	assert(Pending.load_pending(project, "other-player").pending.is_empty(), "Other player cannot inherit an intent")
	assert(not Pending.store(project, intent), "Unknown original cannot be overwritten")
	var wrong := intent.duplicate(true)
	wrong.operationId = OP.replace("1005", "1006")
	assert(not Pending.confirm(project, wrong), "Delayed completion cannot delete a newer intent")
	wrong = intent.duplicate(true)
	wrong.updates[0].value = 1.0
	assert(not Pending.valid(wrong, user_id), "String/float coercion is forbidden")
	wrong.updates[0].value = 9007199254740992
	assert(not Pending.valid(wrong, user_id), "Unsafe integer rejected")
	wrong = intent.duplicate(true)
	wrong.operationId += "\n"
	assert(not Pending.valid(wrong, user_id), "Operation ID validates exact full string")
	var legacy := FileAccess.open(Pending.legacy_path(user_id), FileAccess.WRITE)
	legacy.store_var(intent, false)
	legacy.close()
	assert(not Pending.load_pending(project, user_id).success, "Unbound legacy file blocks automatic project adoption")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Pending.legacy_path(user_id)))
	assert(Pending.confirm(project, intent))
	var file := FileAccess.open(Pending.pending_path(project, user_id), FileAccess.WRITE)
	file.store_var({"corrupt": true}, false)
	file.close()
	assert(not Pending.load_pending(project, user_id).success and not Pending.store(project, intent), "Corruption remains preserved and blocks replacement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Pending.pending_path(project, user_id)))
	var active_project := "statistics-already-signed-in"
	var existing := ExistingHorizon.new()
	var sample := Sample.new()
	assert(await sample._authenticate(existing, active_project))
	sample.free()
	existing.free()
	assert(not Pending.reserve_signup(active_project), "An already signed-in player guard also prevents replacement after cache loss")
	assert(Pending.reserve_signup(project))
	assert(not Pending.reserve_signup(project), "An unknown earlier signup cannot be repeated")
	assert(Pending.mark_identity(project))
	assert(FileAccess.file_exists(Pending.identity_marker(project)), "Durable signup/recovery guard survives restart")
	print("Godot pending statistics project/player ownership, exact int64 payload, legacy, corruption, stale completion and identity guard passed")
	quit(0)
