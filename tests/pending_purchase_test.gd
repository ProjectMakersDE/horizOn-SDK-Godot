extends SceneTree
const Pending = preload("res://addons/horizon_sdk/examples/features/pending_purchase.gd")
const OP := "1792152000000:00000000-0000-4000-8000-000000001006"
func _initialize() -> void:
	var base: String = "user://pending-test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var canonical: String = base + "/horizon_values_pending_project.bin"
	var first: String = base + "/horizon_values_pending_region1.bin"
	var second: String = base + "/horizon_values_pending_region2.bin"
	var unknown: String = base + "/horizon_values_pending_retired.bin"
	var payload: Dictionary = {"userId": "player", "offerKey": "energy-pack", "operationId": OP}
	if not Pending.store(first, payload):
		_fail("Fixture write failed"); return
	var result: Dictionary = Pending.load_pending(canonical, [first, second], "player")
	if not result.success or result.pending != payload or FileAccess.file_exists(first) or not FileAccess.file_exists(canonical):
		_fail("Regional migration must preserve the original ID and immutable payload"); return
	var conflict: Dictionary = payload.duplicate()
	conflict.operationId = OP.replace("1006", "1007")
	Pending.store(second, conflict)
	if Pending.load_pending(canonical, [first, second], "player").success or not FileAccess.file_exists(second):
		_fail("Competing regional operation IDs must block without deleting either intent"); return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(second))
	Pending.store(unknown, payload)
	if Pending.load_pending(canonical, [first, second], "player").success or not FileAccess.file_exists(unknown):
		_fail("An unrecognised retired-host intent must require reconciliation"); return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(unknown))
	Pending.store(first, payload)
	if not Pending.load_pending(canonical, [first, second], "player").success or FileAccess.file_exists(first):
		_fail("An interrupted migration with identical IDs must recover"); return
	print("Godot pending purchase regional migration, conflict and retired-host guards passed")
	quit(0)
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
