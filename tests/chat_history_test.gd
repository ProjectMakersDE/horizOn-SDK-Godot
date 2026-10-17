extends SceneTree
const U := "00000000-0000-4000-8000-000000001014"
const C := "00000000-0000-4000-8000-000000003014"
var checks: int = 0
var failed: bool = false
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failed = true; push_error(label)
func message(index: int) -> Dictionary:
	return {"id": "00000000-0000-4000-8000-%012d" % index, "channelId": C, "authorId": U, "text": "local 雪😀\n\t" + str(index), "createdAt": "2026-10-16T12:00:00.000Z", "expiresAt": "2026-10-16T12:00:30.000Z"}
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var base: String = args[1] if args.size() == 2 else "user://history-test-" + str(Time.get_ticks_usec())
	var history := HorizonChatHistory.new("history-fixture", U, base)
	if args.size() == 2:
		if args[0] == "hold":
			history._locked(func() -> Dictionary:
				var marker: FileAccess = FileAccess.open(base.path_join("holding"), FileAccess.WRITE); marker.store_string("1"); marker.close()
				OS.delay_msec(500)
				return {"success": true})
			quit(0); return
		if args[0] == "crash":
			history._locked(func() -> Dictionary: OS.kill(OS.get_process_id()); return {})
			quit(2); return
		check(history.read_page(C).messages.size() == 50, "real process restart reads old messages without server")
		check(not history.append(C, message(149), history.capture(C)).changed, "restart keeps durable dedupe")
		print("History child checks: %d" % checks)
		quit(1 if failed else 0)
		return
	var generation: String = history.capture(C)
	for index: int in 150: check(history.append(C, message(index), generation).success, "append without rewriting existing log")
	var page: Dictionary = history.read_page(C, "", 20)
	check(page.messages.size() == 20 and page.messages[0].id == message(149).id and page.messages[-1].text == message(130).text, "bounded newest-first page preserves exact Unicode")
	var seen: int = page.messages.size()
	while not page.nextCursor.is_empty():
		page = history.read_page(C, page.nextCursor, 20)
		check(page.success, "bytecursor continuation")
		seen += page.messages.size()
	check(seen == 150, "pagination covers archive beyond live window and expiry")
	check(not history.append(C, message(1), generation).changed, "old repeated snapshot deduplicates")
	var conflict: Dictionary = message(1); conflict.text = "different"
	check(history.append(C, conflict, generation).errorCode == "LOCAL_HISTORY_CONFLICT", "immutable ID conflict visible")
	check(HorizonChatHistory.new("other-key", U, base).read_page(C).messages.is_empty(), "API key partition")
	check(HorizonChatHistory.new("history-fixture", C, base).read_page(C).messages.is_empty(), "player partition")
	var output: Array = []
	check(OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/chat_history_test.gd", "--", "restart", base], output, true) == 0, "actual second engine process restart")
	check(OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/chat_history_test.gd", "--", "crash", base], output, true) != 0, "actual process killed while archive lock held")
	check(history.read_page(C).success and history.read_page(C).messages.size() == 50, "dead lock owner recovers after hard crash without losing history")
	check(history._locked(func() -> Dictionary: return history.read_page(C)).errorCode == "LOCAL_HISTORY_BUSY", "another live owner is never replaced or removed")
	var child: int = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/chat_history_test.gd", "--", "hold", base])
	for attempt: int in 200:
		if FileAccess.file_exists(base.path_join("holding")): break
		OS.delay_msec(5)
	check(FileAccess.file_exists(base.path_join("holding")) and history.read_page(C).errorCode == "LOCAL_HISTORY_BUSY", "foreign live engine lock is never stolen")
	for attempt: int in 200:
		if not OS.is_process_running(child): break
		OS.delay_msec(5)
	check(history.read_page(C).success, "foreign live owner releases its lock normally")
	var lock_path: String = ProjectSettings.globalize_path(history._directory.path_join(".lock"))
	DirAccess.make_dir_absolute(lock_path)
	check(history.read_page(C).success, "ownerless interrupted old lock cannot block local reads")
	var index_text: String = FileAccess.get_file_as_string(history._path(C, ".index"))
	var index_file: FileAccess = FileAccess.open(history._path(C, ".index"), FileAccess.WRITE)
	index_file.store_string(index_text.substr(0, index_text.rfind("\n", index_text.length() - 2) + 1)); index_file.close()
	check(HorizonChatHistory.new("history-fixture", U, base).read_page(C).success, "completed final log row repairs its interrupted index append")
	var cursor: String = history.read_page(C).nextCursor
	check(history.clear(C).success and history.read_page(C).messages.is_empty(), "explicit channel clear")
	check(history.append(C, message(151), generation).errorCode == "LOCAL_HISTORY_STALE", "late pre-clear callback cannot resurrect history")
	check(history.read_page(C, cursor).errorCode == "LOCAL_HISTORY_STALE", "clear invalidates old cursor")
	generation = history.capture(C)
	check(history.append(C, message(152), generation).success, "new post-clear arrival can append")
	var file: FileAccess = FileAccess.open(history._path(C, ".jsonl"), FileAccess.READ_WRITE)
	file.seek_end(); file.store_string("partial"); file.close()
	check(not history.read_page(C).success, "damaged tail is reported")
	check(history.clear().success, "explicit clear can remove damaged local copies")
	check(history.append(C, message(153), generation).errorCode == "LOCAL_HISTORY_STALE", "clear all fences late callback")
	var blocker: String = base.path_join("not-a-directory")
	file = FileAccess.open(blocker, FileAccess.WRITE); file.store_string("owned test file"); file.close()
	var bad := HorizonChatHistory.new("key", U, blocker)
	check(bad.append(C, message(1), bad.capture(C)).errorCode == "LOCAL_HISTORY_IO", "real filesystem failure is visible")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	print("Chat local history: %d checks, failed=%s" % [checks, failed])
	quit(1 if failed else 0)
