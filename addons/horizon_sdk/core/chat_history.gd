class_name HorizonChatHistory
extends RefCounted
## Device-only append log. Pagination follows local delivery order, newest page first.
## The small ID index is loaded once, then only its appended tail is read.
const MAX_ROW := 16384
var _directory: String
var _indexes: Dictionary = {}
func _init(project: String, user: String, base: String = "user://horizon/chat") -> void:
	_directory = base.path_join(JSON.stringify([project, user]).sha256_text())
func capture(channel: String) -> String:
	return _generation(channel)
func append(channel: String, message: Dictionary, generation: String) -> Dictionary:
	return _locked(func() -> Dictionary:
		if generation != _generation(channel): return _error("LOCAL_HISTORY_STALE")
		if not _valid(message, channel): return _error("LOCAL_HISTORY_INVALID")
		var state: Dictionary = _open(channel)
		if not state.success: return state
		var raw: String = HorizonSharedObjectModels.encode({"version": 1, "message": message})
		var digest: String = raw.sha256_text()
		if state.ids.has(message.id):
			return {"success": true, "changed": false} if state.ids[message.id] == digest else _error("LOCAL_HISTORY_CONFLICT")
		var bytes: PackedByteArray = (raw + "\n").to_utf8_buffer()
		if bytes.size() > MAX_ROW: return _error("LOCAL_HISTORY_INVALID")
		if not _append(_path(channel, ".jsonl"), bytes): return _error("LOCAL_HISTORY_IO")
		var index: PackedByteArray = (message.id + " " + digest + " " + str(state.end) + " " + str(bytes.size()) + "\n").to_utf8_buffer()
		if not _append(_path(channel, ".index"), index): return _error("LOCAL_HISTORY_IO")
		state.ids[message.id] = digest
		state.end += bytes.size()
		state.indexEnd += index.size()
		return {"success": true, "changed": true})
func read_page(channel: String, cursor: String = "", limit: int = 50) -> Dictionary:
	if not HorizonChatModels.uuid(channel): return _error("LOCAL_HISTORY_INVALID")
	return _locked(func() -> Dictionary:
		if limit < 1 or limit > 100: return _error("LOCAL_HISTORY_INVALID")
		var state: Dictionary = _open(channel)
		if not state.success: return state
		var generation: String = _generation(channel)
		var end: int = state.end
		if not cursor.is_empty():
			var parts: PackedStringArray = cursor.split(":")
			if parts.size() != 2 or parts[0] != generation or not parts[1].is_valid_int(): return _error("LOCAL_HISTORY_STALE")
			end = parts[1].to_int()
			if end < 0 or end > state.end: return _error("LOCAL_HISTORY_STALE")
		var rows: Array = []
		var file: FileAccess = FileAccess.open(_path(channel, ".jsonl"), FileAccess.READ) if state.end > 0 else null
		if state.end > 0 and file == null: return _error("LOCAL_HISTORY_IO")
		for ignored: int in limit:
			if end == 0: break
			var start: int = maxi(0, end - MAX_ROW - 1)
			file.seek(start)
			var bytes: PackedByteArray = file.get_buffer(end - start)
			if bytes.size() != end - start or bytes[-1] != 10: file.close(); return _error("LOCAL_HISTORY_DAMAGED")
			var boundary: int = bytes.size() - 2
			while boundary >= 0 and bytes[boundary] != 10: boundary -= 1
			if boundary < 0 and start > 0: file.close(); return _error("LOCAL_HISTORY_DAMAGED")
			var row_bytes: PackedByteArray = bytes.slice(boundary + 1, bytes.size() - 1)
			var raw: String = row_bytes.get_string_from_utf8()
			var row: Dictionary = HorizonChatModels.parse(raw)
			if raw.to_utf8_buffer() != row_bytes or row.get("version") != 1 or not _valid(row.get("message"), channel) or state.ids.get(row.message.id) != raw.sha256_text(): file.close(); return _error("LOCAL_HISTORY_DAMAGED")
			rows.push_front(row.message.duplicate(true))
			end = start + boundary + 1
		if file != null: file.close()
		return {"success": true, "messages": rows, "nextCursor": generation + ":" + str(end) if end > 0 else ""})
func clear(channel: String = "") -> Dictionary:
	if not channel.is_empty() and not HorizonChatModels.uuid(channel): return _error("LOCAL_HISTORY_INVALID")
	return _locked(func() -> Dictionary:
		var marker: String = _directory.path_join("generation" if channel.is_empty() else channel + ".generation")
		var stream: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
		if stream == null: return _error("LOCAL_HISTORY_IO")
		stream.store_string(str(Time.get_ticks_usec()) + str(randi()))
		stream.flush()
		var error: Error = stream.get_error()
		stream.close()
		if error != OK: return _error("LOCAL_HISTORY_IO")
		var files: PackedStringArray = DirAccess.get_files_at(_directory)
		for name: String in files:
			if (channel.is_empty() or name.begins_with(channel + ".")) and (name.ends_with(".jsonl") or name.ends_with(".index")):
				if DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory.path_join(name))) != OK: return _error("LOCAL_HISTORY_IO")
		_indexes.clear()
		return {"success": true})
func _open(channel: String) -> Dictionary:
	var generation: String = _generation(channel)
	if generation == "invalid": return _error("LOCAL_HISTORY_DAMAGED")
	var state: Dictionary = _indexes.get(channel, {})
	if state.get("generation") != generation: state = {"success": true, "ids": {}, "indexEnd": 0, "end": 0, "generation": generation}
	var index_path: String = _path(channel, ".index")
	if FileAccess.file_exists(index_path):
		var file: FileAccess = FileAccess.open(index_path, FileAccess.READ)
		if file == null: return _error("LOCAL_HISTORY_IO")
		if file.get_length() < state.indexEnd: file.close(); _indexes.erase(channel); return _open(channel)
		file.seek(state.indexEnd)
		while file.get_position() < file.get_length():
			var begin: int = file.get_position()
			var line: String = ""
			while file.get_position() < file.get_length() and line.length() < 200:
				var byte: int = file.get_8()
				if byte == 10: break
				line += String.chr(byte)
			var parts: PackedStringArray = line.split(" ")
			if parts.size() != 4 or not HorizonChatModels.uuid(parts[0]) or parts[1].length() != 64 or not parts[2].is_valid_int() or not parts[3].is_valid_int() or parts[2].to_int() != state.end or parts[3].to_int() < 1 or parts[3].to_int() > MAX_ROW or file.get_position() - begin != line.length() + 1 or state.ids.has(parts[0]): file.close(); return _error("LOCAL_HISTORY_DAMAGED")
			state.ids[parts[0]] = parts[1]
			state.end += parts[3].to_int()
			state.indexEnd = file.get_position()
		file.close()
	var log_path: String = _path(channel, ".jsonl")
	var log: FileAccess = FileAccess.open(log_path, FileAccess.READ) if FileAccess.file_exists(log_path) else null
	if log == null and FileAccess.file_exists(log_path): return _error("LOCAL_HISTORY_IO")
	var size: int = log.get_length() if log != null else 0
	if size < state.end or size - state.end > MAX_ROW:
		if log != null: log.close()
		return _error("LOCAL_HISTORY_DAMAGED")
	if size > state.end:
		# A completed log append can outlive its index write. Recover that one row.
		log.seek(state.end)
		var bytes: PackedByteArray = log.get_buffer(size - state.end)
		log.close(); log = null
		if bytes[-1] != 10: return _error("LOCAL_HISTORY_DAMAGED")
		var raw: String = bytes.slice(0, bytes.size() - 1).get_string_from_utf8()
		var row: Dictionary = HorizonChatModels.parse(raw)
		if row.get("version") != 1 or not _valid(row.get("message"), channel) or state.ids.has(row.message.id): return _error("LOCAL_HISTORY_DAMAGED")
		var digest: String = raw.sha256_text()
		var index: PackedByteArray = (row.message.id + " " + digest + " " + str(state.end) + " " + str(bytes.size()) + "\n").to_utf8_buffer()
		if not _append(index_path, index): return _error("LOCAL_HISTORY_IO")
		state.ids[row.message.id] = digest
		state.end = size
		state.indexEnd += index.size()
	if log != null: log.close()
	_indexes[channel] = state
	return state
func _generation(channel: String) -> String:
	var result: String = ""
	for path: String in [_directory.path_join("generation"), _path(channel, ".generation")]:
		var value: String = "0"
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > 64: return "invalid"
			value = file.get_as_text()
			file.close()
		result += value + "/"
	return result.sha256_text()
func _path(channel: String, suffix: String) -> String: return _directory.path_join(channel + suffix)
func _locked(action: Callable) -> Dictionary:
	if FileAccess.file_exists(_directory.get_base_dir()): return _error("LOCAL_HISTORY_IO")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) != OK: return _error("LOCAL_HISTORY_IO")
	var lock_path: String = ProjectSettings.globalize_path(_directory.path_join(".lock"))
	if DirAccess.make_dir_absolute(lock_path) != OK: return _error("LOCAL_HISTORY_BUSY")
	var result: Dictionary = action.call()
	DirAccess.remove_absolute(lock_path)
	return result
static func _append(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE_READ)
	if file == null: return false
	file.seek_end(); file.store_buffer(bytes); file.flush()
	var error: Error = file.get_error()
	file.close()
	return error == OK
static func _valid(message: Variant, channel: String) -> bool:
	return message is Dictionary and HorizonChatModels.uuid(channel) and HorizonChatModels.uuid(message.get("id")) and message.get("channelId") == channel and HorizonChatModels.uuid(message.get("authorId")) and HorizonChatModels.text(message.get("text")) and HorizonChatModels.time(message.get("createdAt")) and HorizonChatModels.time(message.get("expiresAt"))
static func _error(code: String) -> Dictionary: return {"success": false, "errorCode": code}
