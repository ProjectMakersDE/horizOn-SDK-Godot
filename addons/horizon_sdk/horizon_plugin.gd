## ============================================================
## horizOn SDK - Editor Plugin
## ============================================================
## Provides editor integration for the horizOn SDK including
## autoload registration and config import functionality.
## ============================================================
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "Horizon"
const AUTOLOAD_PATH := "res://addons/horizon_sdk/horizon_sdk.gd"
const CONFIG_PATH := "res://addons/horizon_sdk/horizon_config.tres"

var _import_dialog: FileDialog
var _config_editor: Control


func _enter_tree() -> void:
	# Add the Horizon autoload singleton
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

	# Add tool menu items
	add_tool_menu_item("horizOn: Import Config...", _on_import_config_pressed)
	add_tool_menu_item("horizOn: Edit Config", _on_edit_config_pressed)
	add_tool_menu_item("horizOn: Clear Cache", _on_clear_cache_pressed)

	print("[horizOn] Plugin enabled. Use Project > Tools > horizOn to import config.")


func _exit_tree() -> void:
	# Remove the autoload singleton
	remove_autoload_singleton(AUTOLOAD_NAME)

	# Remove tool menu items
	remove_tool_menu_item("horizOn: Import Config...")
	remove_tool_menu_item("horizOn: Edit Config")
	remove_tool_menu_item("horizOn: Clear Cache")

	# Cleanup dialogs
	if _import_dialog:
		_import_dialog.queue_free()
		_import_dialog = null

	if _config_editor:
		_config_editor.queue_free()
		_config_editor = null


## Handle import config menu item
func _on_import_config_pressed() -> void:
	if _import_dialog == null:
		_import_dialog = FileDialog.new()
		_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_import_dialog.title = "Import horizOn Config JSON"
		_import_dialog.add_filter("*.json", "JSON Config Files")
		_import_dialog.file_selected.connect(_on_config_file_selected)
		get_editor_interface().get_base_control().add_child(_import_dialog)

	_import_dialog.popup_centered(Vector2i(800, 600))


## Handle config file selection
func _on_config_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error("Failed to open file: %s" % path)
		return

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		_show_error("Failed to parse JSON: %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return

	var data = json.data
	if not data is Dictionary:
		_show_error("Invalid config format: expected JSON object")
		return

	# Validate required fields
	if not data.has("apiKey") or data.apiKey.is_empty():
		_show_error("Config file missing 'apiKey' field")
		return

	# Accept both "backendUrl" (string) and "backendDomains" (array)
	var has_backend_url: bool = data.has("backendUrl") and data.backendUrl is String and not data.backendUrl.is_empty()
	var has_backend_domains: bool = data.has("backendDomains") and data.backendDomains is Array and not data.backendDomains.is_empty()

	if not has_backend_url and not has_backend_domains:
		_show_error("Config file missing 'backendUrl' or 'backendDomains'")
		return

	# Create config resource
	var config := HorizonConfig.from_json(data)

	if not config.is_valid():
		_show_error("Invalid configuration data")
		return

	# Save the config resource
	var save_error := ResourceSaver.save(config, CONFIG_PATH)
	if save_error != OK:
		_show_error("Failed to save config resource: error %d" % save_error)
		return

	# Refresh the file system
	get_editor_interface().get_resource_filesystem().scan()

	# Show success message
	_show_info(
		"Configuration imported successfully!\n\n" +
		"API Key: %s\n" % _mask_api_key(config.api_key) +
		"Hosts: %d configured\n\n" % config.hosts.size() +
		"Saved to: %s" % CONFIG_PATH
	)

	print("[horizOn] Config imported: %d hosts configured" % config.hosts.size())


## Handle edit config menu item
func _on_edit_config_pressed() -> void:
	if not ResourceLoader.exists(CONFIG_PATH):
		_show_error(
			"No configuration found.\n\n" +
			"Please import a config file first using:\n" +
			"Project > Tools > horizOn: Import Config..."
		)
		return

	# Open the config resource in the inspector
	var config := ResourceLoader.load(CONFIG_PATH) as HorizonConfig
	if config:
		get_editor_interface().edit_resource(config)
		get_editor_interface().inspect_object(config)
		print("[horizOn] Editing config resource")
	else:
		_show_error("Failed to load config resource")


## Handle clear cache menu item
func _on_clear_cache_pressed() -> void:
	var cache_path := "user://horizon_cache.cfg"
	if FileAccess.file_exists(cache_path):
		var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
		if err == OK:
			_show_info("Cache cleared successfully!\n\nCleared: %s" % cache_path)
			print("[horizOn] Cache cleared: %s" % cache_path)
		else:
			_show_error("Failed to clear cache: error %d" % err)
	else:
		_show_info("No cache file found.\n\nCache location: %s" % cache_path)


## Show error dialog
func _show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "horizOn - Error"
	dialog.dialog_text = message
	dialog.dialog_hide_on_ok = true
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())


## Show info dialog
func _show_info(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "horizOn"
	dialog.dialog_text = message
	dialog.dialog_hide_on_ok = true
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())


## Mask API key for display
func _mask_api_key(key: String) -> String:
	if key.is_empty():
		return "Not set"
	if key.length() <= 8:
		return "*".repeat(key.length())
	return "%s%s%s" % [key.substr(0, 4), "*".repeat(key.length() - 8), key.substr(key.length() - 4)]
