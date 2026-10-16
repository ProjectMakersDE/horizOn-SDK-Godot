extends RefCounted
## Example-only original-intent storage. Project/player own data; hosts and tokens do not.
const MAX_VALUE := 9007199254740991

static func pending_path(project: String, user_id: String) -> String:
	return "user://horizon_statistics_v2_" + JSON.stringify([project, user_id]).sha256_text() + ".bin"

static func legacy_path(user_id: String) -> String:
	return "user://horizon_statistics_pending_" + user_id.sha256_text().substr(0,24) + ".bin"

static func load_pending(project: String, user_id: String) -> Dictionary:
	var path := pending_path(project, user_id)
	if FileAccess.file_exists(legacy_path(user_id)) or FileAccess.file_exists(path + ".next"):
		return {"success": false, "pending": {}}
	if not FileAccess.file_exists(path):
		return {"success": true, "pending": {}}
	var saved := _read(path)
	if saved.get("scope") != JSON.stringify([project, user_id]).sha256_text() or not valid(saved.get("pending"), user_id):
		return {"success": false, "pending": {}}
	return {"success": true, "pending": saved.pending}

static func valid(pending: Variant, user_id: String) -> bool:
	var operation := RegEx.create_from_string("^[0-9]{13}:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
	if not pending is Dictionary or pending.get("userId") != user_id or not pending.get("operationId") is String or operation.search(pending.operationId) == null or not pending.get("updates") is Array or pending.updates.size() != 2:
		return false
	for index in range(2):
		var update: Variant = pending.updates[index]
		if not update is Dictionary or update.get("key") != ("kills" if index == 0 else "best_score") or typeof(update.get("value")) != TYPE_INT or update.value < 0 or update.value > MAX_VALUE:
			return false
	return true

static func store(project: String, pending: Dictionary) -> bool:
	var user_id: String = pending.get("userId", "")
	var path := pending_path(project, user_id)
	return _locked(path, func() -> bool:
		var existing := load_pending(project, user_id)
		if not valid(pending, user_id) or not existing.success or not existing.pending.is_empty():
			return false
		return _write(path, {"scope": JSON.stringify([project, user_id]).sha256_text(), "pending": pending.duplicate(true)}))

static func confirm(project: String, pending: Dictionary) -> bool:
	var path := pending_path(project, str(pending.get("userId", "")))
	return _locked(path, func() -> bool:
		var existing := load_pending(project, str(pending.get("userId", "")))
		if not existing.success or existing.pending != pending:
			return false
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)

static func identity_marker(project: String) -> String:
	return "user://horizon_statistics_identity_" + project.sha256_text() + ".bin"

static func mark_identity(project: String) -> bool:
	var path := identity_marker(project)
	return _locked(path, func() -> bool: return FileAccess.file_exists(path) or _write(path, {"identityMayExist": true}))

static func reserve_signup(project: String) -> bool:
	var path := identity_marker(project)
	return _locked(path, func() -> bool: return not FileAccess.file_exists(path) and _write(path, {"identityMayExist": true}))

static func _locked(path: String, action: Callable) -> bool:
	var lock_path := ProjectSettings.globalize_path(path + ".lock")
	if DirAccess.make_dir_absolute(lock_path) != OK: return false
	var success: bool = action.call()
	DirAccess.remove_absolute(lock_path)
	return success

static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var value: Variant = file.get_var(false)
	var error := file.get_error()
	file.close()
	return value if error == OK and value is Dictionary else {}

static func _write(path: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(path + ".next"): return false
	var file := FileAccess.open(path + ".next", FileAccess.WRITE)
	if file == null: return false
	file.store_var(value, false)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".next"), ProjectSettings.globalize_path(path)) == OK
