## ============================================================
## horizOn SDK - Configuration Resource
## ============================================================
## Stores API key, backend hosts, and SDK settings.
## Created automatically by importing horizOn config JSON file.
## ============================================================
@tool
class_name HorizonConfig
extends Resource

## Path where the config resource should be saved
const RESOURCE_PATH := "res://addons/horizon_sdk/horizon_config.tres"

## API Configuration
@export_group("API Configuration")
@export var api_key: String = ""
@export var hosts: PackedStringArray = PackedStringArray(["https://horizon.pm"])

## Environment Settings
@export_group("Environment")
@export_enum("production", "staging", "development") var environment: String = "production"

## Connection Settings
@export_group("Connection")
@export_range(5, 60) var connection_timeout_seconds: int = 10
@export_range(1, 10) var max_retry_attempts: int = 3
@export_range(0.5, 10.0) var retry_delay_seconds: float = 1.0

## Logging Settings
@export_group("Logging")
@export_enum("DEBUG", "INFO", "WARNING", "ERROR", "NONE") var log_level: String = "INFO"


## Validate the configuration.
## @return True if configuration is valid
func is_valid() -> bool:
	if api_key.is_empty():
		push_error("[HorizonConfig] API key is not set")
		return false

	if hosts.is_empty():
		push_error("[HorizonConfig] No hosts configured")
		return false

	for host in hosts:
		if host.is_empty():
			push_error("[HorizonConfig] Invalid host URL found")
			return false

		if not host.begins_with("http://") and not host.begins_with("https://"):
			push_error("[HorizonConfig] Host URL must start with http:// or https://: %s" % host)
			return false

	return true


## Load the configuration from the default resource path.
## @return The loaded configuration, or null if not found
static func load_config() -> HorizonConfig:
	if not ResourceLoader.exists(RESOURCE_PATH):
		push_error("[HorizonConfig] Configuration not found at %s. Please import horizOn config JSON using Project > Tools > horizOn > Import Config" % RESOURCE_PATH)
		return null

	var config = ResourceLoader.load(RESOURCE_PATH) as HorizonConfig
	if config == null:
		push_error("[HorizonConfig] Failed to load configuration from %s" % RESOURCE_PATH)
		return null

	return config


## Create a new configuration from JSON data.
## @param json_data Dictionary parsed from JSON config file
## @return New HorizonConfig instance
static func from_json(json_data: Dictionary) -> HorizonConfig:
	var config = HorizonConfig.new()

	config.api_key = json_data.get("apiKey", "")

	# Support both "backendUrl" (single string) and "backendDomains" (array)
	var backend_url = json_data.get("backendUrl", "")
	var domains = json_data.get("backendDomains", [])

	if backend_url is String and not backend_url.is_empty():
		config.hosts = PackedStringArray([backend_url])
	elif domains is Array and not domains.is_empty():
		config.hosts = PackedStringArray(domains)

	return config


## Convert configuration to dictionary for debugging.
## @return Dictionary representation (API key masked)
func to_dict() -> Dictionary:
	return {
		"apiKey": _mask_api_key(api_key),
		"hosts": Array(hosts),
		"environment": environment,
		"connectionTimeoutSeconds": connection_timeout_seconds,
		"maxRetryAttempts": max_retry_attempts,
		"retryDelaySeconds": retry_delay_seconds,
		"logLevel": log_level
	}


## Mask API key for display (show only first 4 and last 4 characters).
func _mask_api_key(key: String) -> String:
	if key.is_empty():
		return "Not set"

	if key.length() <= 8:
		return "*".repeat(key.length())

	return "%s%s%s" % [key.substr(0, 4), "*".repeat(key.length() - 8), key.substr(key.length() - 4)]
