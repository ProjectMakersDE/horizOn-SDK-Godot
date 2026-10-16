extends SceneTree
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_chat.gd")
const U := "00000000-0000-4000-8000-000000001014"
const V := "00000000-0000-4000-8000-000000002014"
const C := "00000000-0000-4000-8000-000000003014"
const E := "00000000-0000-4000-8000-000000004014"
const T := "2026-10-16T12:00:00.000Z"
const X := "2026-10-23T12:00:00.000Z"
const O := "00000000-0000-4000-8000-000000005014"
var checks: int = 0
var failed: bool = false
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
func channel(revision: int = 1, epoch: String = E) -> Dictionary: return {"id": C, "epoch": epoch, "kind": "project", "peerIds": [], "groupId": null, "revision": revision, "expiresAt": X}
func message(index: int) -> Dictionary: return {"id": "00000000-0000-4000-8000-%012d" % index, "channelId": C, "authorId": U, "text": "plain é/😀\n\t<text>", "createdAt": T, "expiresAt": X}
func snapshot(count: int, revision: int = 1, epoch: String = E) -> Dictionary:
	var rows: Array = []
	var ids: Array = []
	for i: int in count: rows.append(message(i)); ids.append(rows[-1].id)
	return {"channel": channel(revision, epoch), "visibleMessageIds": ids, "messages": rows, "moderation": {"muteUntil": null, "banUntil": null}, "serverTime": T}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for valid: String in ["hello", "é😀\n\t", "x".repeat(500), "😀".repeat(500)]: check(HorizonChatModels.text(valid), "valid scalar/plain text")
	for invalid: Variant in ["", " \t\n", String.chr(0xa0), String.chr(0x202f), "x".repeat(501), "😀".repeat(501), "a\r", "a" + String.chr(127), "a" + String.chr(0x85), null, 42]: check(not HorizonChatModels.text(invalid), "invalid chat text")
	check(HorizonChatModels.time(T) and not HorizonChatModels.time("2026-02-30T12:00:00.000Z"), "canonical real calendar timestamp")
	for invalid: Variant in ["2026-10-16T12:00:00Z", "2026-10-16T12:00:00.000+00:00", 42, null]: check(not HorizonChatModels.time(invalid), "reject noncanonical timestamp")
	check(HorizonChatModels.stamp(HorizonChatModels.millis(T) + 1234) == "2026-10-16T12:00:01.234Z", "server clock roundtrip")
	check(not HorizonChatModels.uuid("ABCDEF01-0000-4000-8000-000000003014"), "UUID canonical lowercase")
	var raw: String = HorizonSharedObjectModels.encode(snapshot(1))
	check(not HorizonChatModels.envelope(raw, "sync", U, C).is_empty(), "strict native snapshot")
	for replacement: String in ['1.0', '1e0', '"1"', '9007199254740992', '-1']:
		check(HorizonChatModels.envelope(raw.replace('"revision":1', '"revision":' + replacement), "sync", U, C).is_empty(), "wire integer token rejected " + replacement)
	check(HorizonChatModels.parse('{"revision":1,"revi\\u0073ion":2}').is_empty(), "duplicate decoded fields rejected")
	check(HorizonChatModels.parse('{"text":"\\ud800"}').is_empty(), "invalid surrogate rejected")
	var bad: Dictionary = snapshot(1)
	bad.messages[0].text = HorizonItemStringData._fromParts(PackedStringArray(["before", "after"]), '"before\\u0000after"')
	check(HorizonChatModels.envelope(HorizonSharedObjectModels.encode(bad), "sync", U, C).is_empty(), "NUL text never silently truncated")
	bad = snapshot(1); bad.channel.erase("groupId")
	check(HorizonChatModels.envelope(HorizonSharedObjectModels.encode(bad), "sync", U, C).is_empty(), "explicit nullable fields required")
	bad = snapshot(1); bad.visibleMessageIds.append(bad.visibleMessageIds[0])
	check(HorizonChatModels.envelope(HorizonSharedObjectModels.encode(bad), "sync", U, C).is_empty(), "duplicate visible ID rejected")
	var chat := HorizonChat.new()
	root.add_child(chat)
	var original: Dictionary = snapshot(100)
	check(chat._merge(C, original, {}).messages.size() == 100, "full hundred-row cache")
	chat._record(C, original)
	var delta: Dictionary = snapshot(100, 2); delta.messages = []
	check(chat._merge(C, delta, original).messages.size() == 100, "known hundred IDs need no payload reload")
	delta.visibleMessageIds.pop_front(); delta.visibleMessageIds.append(message(100).id); delta.messages = [message(100)]
	var merged: Dictionary = chat._merge(C, delta, original)
	check(merged.messages.size() == 100 and merged.messages[0].id == message(1).id and merged.messages[-1].id == message(100).id, "atomic removal plus one unknown payload in full order")
	bad = delta.duplicate(true); bad.messages.clear()
	check(chat._merge(C, bad, original).is_empty(), "missing unknown payload fails closed")
	bad = delta.duplicate(true); bad.messages.append(message(1))
	check(chat._merge(C, bad, original).is_empty(), "unexpected cached payload rejected")
	bad = original.duplicate(true); bad.channel.revision = 0
	check(chat._merge(C, bad, {}).is_empty(), "monotone revision guard")
	var next_epoch: String = "00000000-0000-4000-8000-000000004015"
	bad = snapshot(1, 0, next_epoch)
	check(not chat._merge(C, bad, original).is_empty(), "new epoch starts fresh revision and full payload")
	chat._record(C, bad)
	check(chat._merge(C, original, {}).is_empty(), "retired epoch cannot restore old feed")
	bad = snapshot(1); bad.messages[0].expiresAt = T
	check(not HorizonChatModels.message(bad.messages[0], C), "nonpositive expiry invalid")
	var receipt: Dictionary = {"operationId": O, "issuedAt": T, "channelId": C, "messageId": message(0).id, "createdAt": T, "expiresAt": X}
	var intent: Dictionary = {"project": "policy-key".sha256_text(), "userId": U, "operationId": O, "issuedAt": T, "channelId": C, "text": "original é😀"}
	var file: String = Pending.path("policy-key", U)
	check(Pending.path("policy-key", U) != Pending.path("other-project", U) and Pending.path("policy-key", U) != Pending.path("policy-key", V), "journal namespace binds project/player")
	check(Pending.store("policy-key", U, intent), "durable save before HTTP")
	check(Pending.load_pending("policy-key", U).pending == intent, "fresh instance/restart preserves exact original")
	check(not Pending.store("policy-key", U, intent), "unresolved original blocks replacement")
	var wrong: Dictionary = receipt.duplicate(true); wrong.issuedAt = "2026-10-16T12:00:01.000Z"
	check(not Pending.confirm("policy-key", U, intent, wrong), "foreign original receipt cannot ACK")
	check(Pending.confirm("policy-key", U, intent, receipt), "success receipt atomically persisted")
	var saved: Dictionary = Pending.load_pending("policy-key", U)
	check(saved.success and saved.pending.is_empty() and saved.ack == receipt, "durable acknowledged outcome")
	var newer: Dictionary = intent.duplicate(true); newer.operationId = "00000000-0000-4000-8000-000000005015"
	check(Pending.store("policy-key", U, newer), "next explicit original after acknowledged prior")
	check(not Pending.confirm("policy-key", U, intent, receipt) and Pending.load_pending("policy-key", U).pending == newer, "late ACK cannot free newer original")
	var stream: FileAccess = FileAccess.open(file + ".next", FileAccess.WRITE); stream.store_string("partial"); stream.close()
	check(not Pending.load_pending("policy-key", U).success, "partial durable write blocks recovery")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file + ".next"))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(file + ".lock"))
	check(not Pending.load_pending("policy-key", U).success and not Pending.store("policy-key", U, intent), "cross-instance lock blocks another writer")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file + ".lock"))
	stream = FileAccess.open(file, FileAccess.WRITE); stream.store_buffer(PackedByteArray([0, 1, 255, 0, 128])); stream.close()
	check(not Pending.load_pending("policy-key", U).success and not Pending.store("policy-key", U, intent), "corrupted original is never vacant")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	chat.queue_free()
	print("Chat policy/storage: %d checks, failed=%s" % [checks, failed])
	quit(1 if failed else 0)
