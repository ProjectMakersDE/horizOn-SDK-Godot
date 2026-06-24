## ============================================================
## horizOn SDK - Localization Minimal Example
## ============================================================
## What it does: connects, reads a single localized value, lists the
## available languages, switches the active language, then fetches all
## translations for the current language at once.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: the requested key's value, the language list, and a
## count of all translations, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.localization.localization_load_failed.connect(func(error: String):
		push_error("Localization load failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	# Localization does not require sign-in.
	# getLocalization returns an empty string when the key is missing.
	var greeting: String = await horizon.localization.getLocalization("greeting")
	if greeting.is_empty():
		print("Localization key 'greeting' is not set.")
	else:
		print("greeting = %s" % greeting)

	# getAvailableLanguages returns every language code the server has, or [].
	var languages: Array = await horizon.localization.getAvailableLanguages()
	print("Available languages: %s" % ", ".join(languages))

	# setLanguage switches the active language and clears the cache.
	# An explicit lang argument also overrides the active language per call.
	horizon.localization.setLanguage("de")
	var greeting_de: String = await horizon.localization.getLocalization("greeting", "de")
	print("greeting (de) = %s" % greeting_de)

	# getAllLocalizations returns every key-value pair for the language, or {}.
	var all_translations: Dictionary = await horizon.localization.getAllLocalizations()
	print("Loaded %d translations for '%s'." % [all_translations.size(), horizon.localization.current_language])
