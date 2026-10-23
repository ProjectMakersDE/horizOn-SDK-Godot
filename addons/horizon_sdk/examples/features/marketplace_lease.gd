extends RefCounted
## Desktop killed-owner recovery; unknown mobile/Web owners stay locked. Never delete a live/unknown lease.
static var _held: Dictionary = {}
static func acquire(raw_path: String) -> bool:
	var lock_path: String = ProjectSettings.globalize_path(raw_path)
	if _held.has(lock_path): return false
	var owner: String = "owner.%d.%s" % [OS.get_process_id(), Crypto.new().generate_random_bytes(16).hex_encode()]
	var claim: String = lock_path + ".claim." + owner
	if DirAccess.make_dir_absolute(claim) != OK: return false
	var file: FileAccess = FileAccess.open(claim.path_join(owner), FileAccess.WRITE)
	if file == null: DirAccess.remove_absolute(claim); return false
	file.store_string("1"); file.flush()
	var written: bool = file.get_error() == OK
	file.close()
	if written:
		for attempt: int in 3:
			if DirAccess.rename_absolute(claim, lock_path) == OK:
				_held[lock_path] = owner
				return true
			var owners: PackedStringArray = DirAccess.get_files_at(lock_path)
			if owners.size() != 1: break
			var parts: PackedStringArray = owners[0].split(".")
			if parts.size() != 3 or parts[0] != "owner" or not parts[1].is_valid_int() or parts[1].to_int() <= 0 or parts[2].length() != 32 or _owner_running(parts[1].to_int()) != 0: break
			if DirAccess.remove_absolute(lock_path.path_join(owners[0])) != OK: break
			DirAccess.remove_absolute(lock_path)
	DirAccess.remove_absolute(claim.path_join(owner)); DirAccess.remove_absolute(claim)
	return false
static func release(raw_path: String) -> void:
	var lock_path: String = ProjectSettings.globalize_path(raw_path)
	var owner: String = _held.get(lock_path, "")
	if owner.is_empty(): return
	if DirAccess.remove_absolute(lock_path.path_join(owner)) == OK: DirAccess.remove_absolute(lock_path)
	_held.erase(lock_path)
static func locked(raw_path: String, action: Callable) -> bool:
	if not acquire(raw_path): return false
	var result: bool = action.call()
	release(raw_path)
	return result
static func _owner_running(pid: int) -> int:
	if pid == OS.get_process_id(): return 1
	if OS.get_name() == "Windows": return 1 if OS.is_process_running(pid) else 0
	# Unix Godot's is_process_running uses waitpid, which cannot probe another app instance.
	# https://github.com/godotengine/godot/blob/master/drivers/unix/os_unix.cpp
	if OS.get_name() in ["macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD"]:
		if not FileAccess.file_exists("/usr/bin/env"): return -1
		for executable: String in ["/bin/kill", "/usr/bin/kill"]:
			if not FileAccess.file_exists(executable): continue
			var output: Array = []
			var result: int = OS.execute("/usr/bin/env", ["LC_ALL=C", executable, "-0", str(pid)], output, true)
			if result == 0: return 1
			# Distinguish missing processes from permission/probe failures. Unknown stays locked.
			var error: String = "".join(output).to_lower()
			return 0 if result == 1 and ("no such process" in error or "not found" in error) else -1
	return -1 # Mobile/Web cannot safely establish an unrelated process's liveness here.
