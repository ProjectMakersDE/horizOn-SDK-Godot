extends RefCounted
## Example journal: bounded, checksummed plain JSON, exclusive create/ACK and atomic replacement.
## A damaged/partial/stale lock is deliberately blocked, never treated as a vacant send slot.
const Storage = preload("res://addons/horizon_sdk/examples/features/pending_statistics.gd")
const MAX_BYTES := 16384
static func path(project: String, user: String) -> String: return "user://horizon_chat_" + JSON.stringify([project, user]).sha256_text() + ".json"
static func valid(value: Variant, project: String, user: String) -> bool:
	return value is Dictionary and value.size() == 6 and value.get("project") == project.sha256_text() and value.get("userId") == user and HorizonChatModels.uuid(value.get("operationId")) and HorizonChatModels.time(value.get("issuedAt")) and HorizonChatModels.uuid(value.get("channelId")) and HorizonChatModels.text(value.get("text"))
static func load_pending(project: String, user: String) -> Dictionary:
	var file: String = path(project, user)
	if FileAccess.file_exists(file + ".next") or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(file + ".lock")): return _failure()
	return _read(file, project, user)
static func store(project: String, user: String, intent: Dictionary) -> bool:
	var file: String = path(project, user)
	if not valid(intent, project, user): return false
	return Storage._locked(file, func() -> bool:
		var previous: Dictionary = _read(file, project, user)
		return previous.success and previous.pending.is_empty() and _write(file, {"project": project.sha256_text(), "userId": user, "pending": intent.duplicate(true), "ack": previous.ack}))
static func confirm(project: String, user: String, intent: Dictionary, receipt: Dictionary) -> bool:
	var file: String = path(project, user)
	if not valid(intent, project, user) or not HorizonChatModels.receipt(receipt) or receipt.operationId != intent.operationId or receipt.channelId != intent.channelId or receipt.issuedAt != intent.issuedAt: return false
	return Storage._locked(file, func() -> bool:
		var previous: Dictionary = _read(file, project, user)
		return previous.success and previous.pending == intent and _write(file, {"project": project.sha256_text(), "userId": user, "pending": {}, "ack": receipt.duplicate(true)}))
static func _read(file: String, project: String, user: String) -> Dictionary:
	if FileAccess.file_exists(file + ".next"): return _failure()
	if not FileAccess.file_exists(file): return {"success": true, "pending": {}, "ack": {}}
	var stream: FileAccess = FileAccess.open(file, FileAccess.READ)
	if stream == null: return _failure()
	var size: int = stream.get_length()
	if size < 1 or size > MAX_BYTES: stream.close(); return _failure()
	var bytes: PackedByteArray = stream.get_buffer(size)
	stream.close()
	var raw: String = bytes.get_string_from_utf8()
	if raw.to_utf8_buffer() != bytes: return _failure()
	var wrapper: Dictionary = HorizonChatModels.parse(raw)
	if wrapper.size() != 3 or wrapper.get("version") != 1 or not wrapper.get("data") is String or not wrapper.get("sha256") is String or wrapper.data.sha256_text() != wrapper.sha256: return _failure()
	var value: Dictionary = HorizonChatModels.parse(wrapper.data)
	if value.size() != 4 or value.get("project") != project.sha256_text() or value.get("userId") != user or not value.get("pending") is Dictionary or not value.get("ack") is Dictionary: return _failure()
	if not value.pending.is_empty() and not valid(value.pending, project, user): return _failure()
	if not value.ack.is_empty() and not HorizonChatModels.receipt(value.ack): return _failure()
	return {"success": true, "pending": value.pending, "ack": value.ack}
static func _write(file: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(file + ".next"): return false
	var payload: String = HorizonSharedObjectModels.encode(value)
	var bytes: PackedByteArray = JSON.stringify({"version": 1, "data": payload, "sha256": payload.sha256_text()}).to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return false
	var stream: FileAccess = FileAccess.open(file + ".next", FileAccess.WRITE)
	if stream == null: return false
	stream.store_buffer(bytes)
	stream.flush()
	var error: Error = stream.get_error()
	stream.close()
	return error == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(file + ".next"), ProjectSettings.globalize_path(file)) == OK
static func _failure() -> Dictionary: return {"success": false, "pending": {}, "ack": {}}
