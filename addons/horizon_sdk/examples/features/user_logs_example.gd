## ============================================================
## horizOn SDK - User Logs Minimal Example
## ============================================================
## What it does: signs in anonymously, then writes an INFO log,
## a game event, and a WARN log with an error code.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Log created" line per entry, or a clear
## error line on failure. Note: user logs are not available on
## FREE accounts and will return an empty result there.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.userLogs.log_create_failed.connect(func(error: String):
		push_error("User log failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before writing user logs.")
		return

	# createLog returns a Dictionary with id and createdAt, or {} on failure.
	var info_log: Dictionary = await horizon.userLogs.createLog(
		HorizonUserLogs.LogType.INFO, "Player opened the shop")
	if not info_log.is_empty():
		print("Log created: %s" % info_log.get("id", ""))

	# logEvent is a convenience wrapper around an INFO log.
	var event_log: Dictionary = await horizon.userLogs.logEvent("level_complete", "level 7")
	if not event_log.is_empty():
		print("Event log created: %s" % event_log.get("id", ""))

	# warn accepts an optional error code string.
	var warn_log: Dictionary = await horizon.userLogs.warn("Low memory warning", "MEM_LOW")
	if not warn_log.is_empty():
		print("Warn log created: %s" % warn_log.get("id", ""))
