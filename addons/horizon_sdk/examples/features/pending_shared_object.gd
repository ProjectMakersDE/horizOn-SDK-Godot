extends RefCounted
## Example-only immutable original write. No token/host in its project/player namespace.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
static func path(project: String, user: String) -> String: return "user://horizon_shared_object_" + JSON.stringify([project, user]).sha256_text() + ".bin"
static func load_pending(file: String) -> Dictionary:
	if FileAccess.file_exists(file + ".next") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(file + ".lock")): return {"success": false, "pending": {}}
	return _read(file)
static func _read(file: String) -> Dictionary:
	if not FileAccess.file_exists(file): return {"success": true, "pending": {}}
	var value: Dictionary = Storage._read(file)
	return {"success": not value.is_empty(), "pending": value}
static func store(file: String, value: Dictionary) -> bool:
	return Storage._locked(file, func() -> bool:
		var loaded: Dictionary = _read(file)
		return not FileAccess.file_exists(file + ".next") and loaded.success and loaded.pending.is_empty() and Storage._write(file, value.duplicate(true)))
static func confirm(file: String, expected: Dictionary) -> bool:
	return Storage._locked(file, func() -> bool:
		if FileAccess.file_exists(file + ".next") or expected.is_empty(): return false
		var loaded: Dictionary = _read(file)
		return loaded.success and loaded.pending == expected and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK)
