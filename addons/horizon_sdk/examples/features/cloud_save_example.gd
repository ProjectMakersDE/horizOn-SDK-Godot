## ============================================================
## horizOn SDK - Cloud Save Minimal Example
## ============================================================
## What it does: signs in anonymously, saves a small progress
## Dictionary to the cloud, then loads it back.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Saved" line with a byte count and a "Loaded"
## line echoing the stored values, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.cloudSave.data_save_failed.connect(func(error: String):
		push_error("Cloud save failed: %s" % error))
	horizon.cloudSave.data_load_failed.connect(func(error: String):
		push_error("Cloud load failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before using cloud save.")
		return

	# saveObject serializes a Dictionary to JSON and stores it.
	var progress := {"level": 7, "coins": 240, "unlocked": ["sword", "shield"]}
	var saved: bool = await horizon.cloudSave.saveObject(progress)
	if not saved:
		push_error("Progress was not saved.")
		return
	print("Saved progress for level %d." % progress["level"])

	# loadObject returns an empty Dictionary on failure or when nothing is stored.
	var loaded: Dictionary = await horizon.cloudSave.loadObject()
	if loaded.is_empty():
		print("No cloud save found yet.")
		return
	print("Loaded progress: level %d, coins %d" % [loaded.get("level", 0), loaded.get("coins", 0)])
