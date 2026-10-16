extends RefCounted
## Example-only original entry identity. A regional host change never creates another slot.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")

static func path(project: String, user_id: String) -> String:
	return "user://horizon_inbox_claim_" + JSON.stringify([project, user_id]).sha256_text() + ".bin"

static func valid(pending: Variant, user_id: String) -> bool:
	return pending is Dictionary and pending.size() == 2 and not user_id.is_empty() and pending.get("userId") == user_id and HorizonInbox._validEntryId(pending.get("entryId"))

static func load_pending(project: String, user_id: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path(project, user_id) + ".lock")):
		return {"success": false, "pending": {}}
	return _load(project, user_id)

## Only storage operations holding their own atomic lock may bypass that lock check.
static func _load(project: String, user_id: String) -> Dictionary:
	var file: String = path(project, user_id)
	if project.is_empty() or user_id.is_empty() or FileAccess.file_exists(file + ".next"):
		return {"success": false, "pending": {}}
	if not FileAccess.file_exists(file):
		return {"success": true, "pending": {}}
	var saved: Dictionary = Storage._read(file)
	if saved.get("scope") != JSON.stringify([project, user_id]).sha256_text() or not valid(saved.get("pending"), user_id):
		return {"success": false, "pending": {}}
	return {"success": true, "pending": saved.pending}

static func store(project: String, pending: Dictionary) -> bool:
	var user_id: String = pending.get("userId", "")
	var file: String = path(project, user_id)
	return Storage._locked(file, func() -> bool:
		var loaded: Dictionary = _load(project, user_id)
		return valid(pending, user_id) and loaded.success and loaded.pending.is_empty() and Storage._write(file, {"scope": JSON.stringify([project, user_id]).sha256_text(), "pending": pending.duplicate(true)}))

static func confirm(project: String, pending: Dictionary) -> bool:
	var file: String = path(project, str(pending.get("userId", "")))
	return Storage._locked(file, func() -> bool:
		var loaded: Dictionary = _load(project, str(pending.get("userId", "")))
		return loaded.success and loaded.pending == pending and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK)
