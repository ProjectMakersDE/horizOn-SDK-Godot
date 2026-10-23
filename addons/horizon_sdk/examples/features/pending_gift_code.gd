extends RefCounted
## Example-only immutable intent. Share the existing project identity guard across samples.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")

static func path(project: String, user_id: String) -> String:
	return "user://horizon_gift_code_" + JSON.stringify([project,user_id]).sha256_text() + ".bin"

static func valid(raw: Variant, project: String, user_id: String) -> bool:
	return raw is Dictionary and HorizonGiftCodes.validIntent(raw,project,user_id)

static func load_pending(project: String, user_id: String) -> Dictionary:
	var file: String = path(project,user_id)
	if FileAccess.file_exists(file + ".next"): return {"success": false, "pending": {}}
	if not FileAccess.file_exists(file): return {"success": true, "pending": {}}
	var saved: Dictionary = Storage._read(file)
	if saved.get("scope") != JSON.stringify([project,user_id]).sha256_text() or not valid(saved.get("pending"),project,user_id):
		return {"success": false, "pending": {}}
	return {"success": true, "pending": saved.pending}

static func store(project: String, pending: Dictionary) -> bool:
	var user_id: String = pending.get("userId", "")
	var file: String = path(project,user_id)
	return Storage._locked(file,func() -> bool:
		var loaded: Dictionary = load_pending(project,user_id)
		return not project.is_empty() and valid(pending,project,user_id) and loaded.success and loaded.pending.is_empty() and Storage._write(file,{"scope":JSON.stringify([project,user_id]).sha256_text(),"pending":pending.duplicate(true)}))

static func confirm(project: String, pending: Dictionary) -> bool:
	var file: String = path(project,str(pending.get("userId", "")))
	return Storage._locked(file,func() -> bool:
		var loaded: Dictionary = load_pending(project,str(pending.get("userId", "")))
		return loaded.success and loaded.pending == pending and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK)
