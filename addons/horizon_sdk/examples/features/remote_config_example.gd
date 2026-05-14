## ============================================================
## horizOn SDK - Remote Config Minimal Example
## ============================================================
## What it does: connects, reads a single config value, reads it
## again as a typed value, then fetches all configs at once.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: the requested key's value, a typed read, and a
## count of all configs, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.remoteConfig.config_load_failed.connect(func(error: String):
		push_error("Remote config load failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	# Remote config does not require sign-in.
	# getConfig returns an empty string when the key is missing.
	var welcome: String = await horizon.remoteConfig.getConfig("welcome_message", false)
	if welcome.is_empty():
		print("Config key 'welcome_message' is not set.")
	else:
		print("welcome_message = %s" % welcome)

	# Typed getters fall back to the supplied default when missing or unparseable.
	var max_lives: int = await horizon.remoteConfig.getInt("max_lives", 3)
	print("max_lives = %d" % max_lives)

	# getAllConfigs returns every key-value pair, or {} on failure.
	var all_configs: Dictionary = await horizon.remoteConfig.getAllConfigs(false)
	print("Loaded %d config values." % all_configs.size())
