extends RefCounted
## Example-only compare-and-swap storage. Purchases/actions share one project/player lock.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
static func _lock(path: String) -> String: return path.replace("_purchase_", "_slot_").replace("_action_", "_slot_")
static func _other(path: String) -> String: return path.replace("_purchase_", "_action_") if path.contains("_purchase_") else path.replace("_action_", "_purchase_")
static func _interrupted(path: String) -> bool: return FileAccess.file_exists(path + ".next") or FileAccess.file_exists(_other(path) + ".next")
static func load_pending(path: String) -> Dictionary:
	if _interrupted(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_lock(path) + ".lock")): return {"success": false, "pending": {}}
	return _read(path)
static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"success": true, "pending": {}}
	var value: Dictionary = Storage._read(path)
	return {"success": not value.is_empty(), "pending": value}
static func store(path: String, value: Dictionary, expected: Dictionary = {}) -> bool:
	return Storage._locked(_lock(path), func() -> bool:
		if _interrupted(path): return false
		var loaded: Dictionary = _read(path)
		if not loaded.success or loaded.pending != expected: return false
		if expected.is_empty() and FileAccess.file_exists(_other(path)): return false
		return Storage._write(path, value.duplicate(true)))
static func confirm(path: String, expected: Dictionary) -> bool:
	return Storage._locked(_lock(path), func() -> bool:
		if _interrupted(path) or expected.is_empty(): return false
		var loaded: Dictionary = _read(path)
		return loaded.success and loaded.pending == expected and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
