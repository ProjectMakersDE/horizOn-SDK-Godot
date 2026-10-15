extends RefCounted
## Durable example intent migration: project + player owns a purchase; a regional host does not.

static func load_pending(path: String, legacy_paths: Array[String], user_id: String) -> Dictionary:
	var paths: Array[String] = [path]
	for legacy: String in legacy_paths:
		if not paths.has(legacy):
			paths.append(legacy)
	# Old files contain no project metadata. Never overlook an unrecognised pending intent
	# for this player just because its original regional host was removed from configuration.
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null:
		return {"success": false, "pending": {}}
	for file_name: String in directory.get_files():
		var candidate: String = path.get_base_dir().path_join(file_name)
		if file_name.begins_with("horizon_values_pending_") and file_name.ends_with(".bin") and not paths.has(candidate):
			var saved: Variant = _read(candidate)
			if saved is Dictionary and saved.get("userId") == user_id:
				return {"success": false, "pending": {}}
	var pending: Dictionary = {}
	for candidate: String in paths:
		if not FileAccess.file_exists(candidate):
			continue
		var saved: Variant = _read(candidate)
		if not saved is Dictionary or saved.get("userId") != user_id or not saved.get("offerKey") is String or saved.offerKey.is_empty() or not saved.get("operationId") is String or not HorizonPlayerValues._validOperationId(saved.operationId):
			return {"success": false, "pending": {}}
		if not pending.is_empty() and pending != saved:
			return {"success": false, "pending": {}}
		pending = saved
	if not pending.is_empty():
		# Copy durably before removing any regional aliases. A partial migration is retryable.
		if not FileAccess.file_exists(path) and not store(path, pending):
			return {"success": false, "pending": {}}
		for legacy: String in legacy_paths:
			if legacy != path and FileAccess.file_exists(legacy) and DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy)) != OK:
				return {"success": false, "pending": {}}
	return {"success": true, "pending": pending}

static func store(path: String, pending: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(pending, false)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

static func _read(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var saved: Variant = file.get_var(false)
	file.close()
	return saved
