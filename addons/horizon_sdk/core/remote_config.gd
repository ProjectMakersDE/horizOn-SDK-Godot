## ============================================================
## horizOn SDK - Remote Config Manager
## ============================================================
## Handles remote configuration retrieval from the server.
## Supports fetching individual keys or all configuration values.
## ============================================================
class_name HorizonRemoteConfig
extends RefCounted

## Signals
signal config_loaded(key: String, value: String)
signal all_configs_loaded(configs: Dictionary)
signal config_load_failed(error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger

## Cache for config values
var _cache: Dictionary = {}


## Initialize the remote config manager.
## @param http HTTP client instance
## @param logger Logger instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger) -> void:
	_http = http
	_logger = logger
	_logger.info("Remote config manager initialized")


## Get a single configuration value by key.
## @param key The configuration key
## @param use_cache Whether to use cached value if available
## @return The config value, or empty string if not found
func getConfig(key: String, use_cache: bool = true) -> String:
	if key.is_empty():
		_logger.error("Config key is required")
		return ""

	# Check cache
	if use_cache and _cache.has(key):
		_logger.debug("Config cache hit: %s" % key)
		return _cache[key]

	var endpoint := "/api/v1/app/remote-config/%s" % key.uri_encode()
	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var found: bool = response.data.get("found", false)
		if found:
			var value: String = str(response.data.get("configValue", ""))
			_cache[key] = value
			_logger.info("Config loaded: %s = %s" % [key, value])
			config_loaded.emit(key, value)
			return value
		else:
			_logger.warning("Config key not found: %s" % key)
			return ""

	_logger.error("Failed to get config %s: %s" % [key, response.error])
	config_load_failed.emit(response.error)
	return ""


## Get all configuration values.
## @param use_cache Whether to use cached values if available
## @return Dictionary of all config key-value pairs
func getAllConfigs(use_cache: bool = true) -> Dictionary:
	# Check cache
	if use_cache and not _cache.is_empty():
		_logger.debug("Using cached configs")
		return _cache.duplicate()

	var response := await _http.getAsync("/api/v1/app/remote-config/all")

	if response.isSuccess and response.data is Dictionary:
		var configs: Dictionary = response.data.get("configs", {})
		var total: int = response.data.get("total", 0)

		# Update cache
		_cache = configs.duplicate()

		_logger.info("Loaded %d config values" % total)
		all_configs_loaded.emit(configs)
		return configs

	_logger.error("Failed to get all configs: %s" % response.error)
	config_load_failed.emit(response.error)
	return {}


## Get a config value as an integer.
## @param key The configuration key
## @param default_value Default value if not found or not parseable
## @param use_cache Whether to use cached value
## @return Integer value
func getInt(key: String, default_value: int = 0, use_cache: bool = true) -> int:
	var value := await getConfig(key, use_cache)
	if value.is_empty():
		return default_value
	if value.is_valid_int():
		return value.to_int()
	return default_value


## Get a config value as a float.
## @param key The configuration key
## @param default_value Default value if not found or not parseable
## @param use_cache Whether to use cached value
## @return Float value
func getFloat(key: String, default_value: float = 0.0, use_cache: bool = true) -> float:
	var value := await getConfig(key, use_cache)
	if value.is_empty():
		return default_value
	if value.is_valid_float():
		return value.to_float()
	return default_value


## Get a config value as a boolean.
## @param key The configuration key
## @param default_value Default value if not found
## @param use_cache Whether to use cached value
## @return Boolean value (true if value is "true", "1", "yes")
func getBool(key: String, default_value: bool = false, use_cache: bool = true) -> bool:
	var value := await getConfig(key, use_cache)
	if value.is_empty():
		return default_value
	var lower := value.to_lower()
	return lower == "true" or lower == "1" or lower == "yes"


## Get a config value as a JSON-parsed object.
## @param key The configuration key
## @param use_cache Whether to use cached value
## @return Parsed JSON (Dictionary, Array, or null if invalid)
func getJson(key: String, use_cache: bool = true) -> Variant:
	var value := await getConfig(key, use_cache)
	if value.is_empty():
		return null
	return JSON.parse_string(value)


## Clear the configuration cache.
func clearCache() -> void:
	_cache.clear()
	_logger.info("Remote config cache cleared")


## Check if a specific key exists (from cache or server).
## @param key The configuration key
## @param use_cache Whether to check cache first
## @return True if key exists
func hasKey(key: String, use_cache: bool = true) -> bool:
	if use_cache and _cache.has(key):
		return true

	var value := await getConfig(key, false)
	return not value.is_empty()
