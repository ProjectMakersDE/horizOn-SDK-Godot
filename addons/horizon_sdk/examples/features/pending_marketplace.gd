extends RefCounted
## One unresolved original, not purchase history. A separate directory lease spans awaited sends.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const Models = preload("res://addons/horizon_sdk/models/marketplace_models.gd")
static func path(project: String, user: String) -> String:
	return "user://horizon_marketplace_" + JSON.stringify([project, user]).sha256_text() + ".bin"
static func valid(value: Variant, project: String, user: String) -> bool:
	if not Models.uuid(project) or not Models.uuid(user) or not value is Dictionary or value.get("scope") != JSON.stringify([project, user]).sha256_text() or not value.get("kind") is String or not value.get("body") is Dictionary or value.body.get("userId") != user or not value.get("listingId") is String or not value.get("phase") in ["intent", "confirmed"]: return false
	if not Models.valid_intent(value.kind, value.body, value.listingId): return false
	if value.phase == "intent": return value.size() == 5
	var result: Variant = value.get("confirmed")
	return value.size() == 6 and result is Dictionary and result.size() == 3 and result.get("kind") == value.kind and result.get("operationId") == value.body.operationId and Models.uuid(result.get("listingId")) and (value.kind == "create" or result.listingId == value.listingId)
static func load_pending(project: String, user: String) -> Dictionary:
	var file: String = path(project, user)
	if FileAccess.file_exists(file + ".next"): return {"success": false, "pending": {}}
	if not FileAccess.file_exists(file): return {"success": true, "pending": {}}
	var pending: Dictionary = Storage._read(file)
	return {"success": valid(pending, project, user), "pending": pending if valid(pending, project, user) else {}}
static func store(project: String, user: String, value: Dictionary, expected: Dictionary = {}) -> bool:
	var file: String = path(project, user)
	return Storage._locked(file, func() -> bool:
		var loaded: Dictionary = load_pending(project, user)
		if not valid(value, project, user) or not loaded.success or loaded.pending != expected: return false
		return Storage._write(file, value.duplicate(true)) and Storage._read(file) == value)
static func confirm(project: String, user: String, expected: Dictionary) -> bool:
	var file: String = path(project, user)
	return Storage._locked(file, func() -> bool:
		var loaded: Dictionary = load_pending(project, user)
		return loaded.success and not expected.is_empty() and loaded.pending == expected and expected.phase == "confirmed" and DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK)
static func acquire_send(project: String, user: String) -> bool:
	return DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path(project, user) + ".sending")) == OK
static func release_send(project: String, user: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path(project, user) + ".sending"))
