## ============================================================
## horizOn SDK - Localization Manager
## ============================================================
## Handles localized string retrieval from the server.
## Supports fetching individual keys or all translations for a
## language, and listing the available languages.
## ============================================================
class_name HorizonLocalization
extends RefCounted

## Signals
signal localization_loaded(key: String, value: String)
signal all_localizations_loaded(translations: Dictionary)
signal localization_load_failed(error: String)

## Supported language codes (server-side parity).
const SUPPORTED_LANGUAGES: PackedStringArray = [
	"en", "de", "es", "fr", "it", "pt", "nl", "pl",
	"ru", "ja", "zh", "ar", "ko", "tr", "id"
]

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger

## Active language used when a method is called without an explicit lang.
## Defaults to the OS locale when supported, otherwise "en".
var current_language: String = "en"

## Cache for translation values of the current language.
var _cache: Dictionary = {}

## Whether the FULL set for the current language has been loaded via
## getAllLocalizations. Single-key getLocalization fills _cache piecemeal but must
## NOT set this, otherwise getAllLocalizations would return a partial set.
var _all_loaded: bool = false


## Initialize the localization manager.
## @param http HTTP client instance
## @param logger Logger instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger) -> void:
	_http = http
	_logger = logger
	current_language = _detectDefaultLanguage()
	_logger.info("Localization manager initialized (language: %s)" % current_language)


## Get a single localized value by key.
## @param key The localization key
## @param lang Language code (empty uses current_language)
## @return The localized value, or empty string if not found
func getLocalization(key: String, lang: String = "") -> String:
	if key.is_empty():
		_logger.error("Localization key is required")
		return ""

	var lang_code := lang if not lang.is_empty() else current_language
	var use_cache := lang_code == current_language

	# Check cache (only for the current language)
	if use_cache and _cache.has(key):
		_logger.debug("Localization cache hit: %s" % key)
		return _cache[key]

	var endpoint := "/api/v1/app/localization/%s?lang=%s" % [key.uri_encode(), lang_code.uri_encode()]
	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var found: bool = response.data.get("found", false)
		if found:
			var value: String = str(response.data.get("value", ""))
			if use_cache:
				_cache[key] = value
			_logger.info("Localization loaded: %s = %s" % [key, value])
			localization_loaded.emit(key, value)
			return value
		else:
			_logger.warning("Localization key not found: %s" % key)
			return ""

	_logger.error("Failed to get localization %s: %s" % [key, response.error])
	localization_load_failed.emit(response.error)
	return ""


## Get all translations for a language.
## @param lang Language code (empty uses current_language)
## @return Dictionary of all key-value translation pairs
func getAllLocalizations(lang: String = "") -> Dictionary:
	var lang_code := lang if not lang.is_empty() else current_language
	var use_cache := lang_code == current_language

	# Return cache only if the FULL set for the current language was loaded.
	if use_cache and _all_loaded:
		_logger.debug("Using cached localizations")
		return _cache.duplicate()

	var endpoint := "/api/v1/app/localization/all?lang=%s" % lang_code.uri_encode()
	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var translations: Dictionary = response.data.get("translations", {})
		var total: int = response.data.get("total", 0)

		# Update cache (only for the current language) and mark fully loaded.
		if use_cache:
			_cache = translations.duplicate()
			_all_loaded = true

		_logger.info("Loaded %d localization values" % total)
		all_localizations_loaded.emit(translations)
		return translations

	_logger.error("Failed to get all localizations: %s" % response.error)
	localization_load_failed.emit(response.error)
	return {}


## Get the list of languages available on the server.
## @return Array of language codes
func getAvailableLanguages() -> Array:
	var response := await _http.getAsync("/api/v1/app/localization/languages")

	if response.isSuccess and response.data is Dictionary:
		var languages: Array = response.data.get("languages", [])
		var total: int = response.data.get("total", 0)
		_logger.info("Loaded %d available languages" % total)
		return languages

	_logger.error("Failed to get available languages: %s" % response.error)
	localization_load_failed.emit(response.error)
	return []


## Set the active language. Clears the cache when the language changes.
## @param lang Language code (must be one of SUPPORTED_LANGUAGES)
func setLanguage(lang: String) -> void:
	if lang == current_language:
		return

	if not SUPPORTED_LANGUAGES.has(lang):
		_logger.warning("Unsupported language '%s', keeping '%s'" % [lang, current_language])
		return

	current_language = lang
	clearCache()
	_logger.info("Language set to %s" % lang)


## Clear the localization cache.
func clearCache() -> void:
	_cache.clear()
	_all_loaded = false
	_logger.info("Localization cache cleared")


## Check if a specific key exists (from cache or server).
## @param key The localization key
## @param lang Language code (empty uses current_language)
## @return True if key exists
func hasKey(key: String, lang: String = "") -> bool:
	var lang_code := lang if not lang.is_empty() else current_language

	if lang_code == current_language and _cache.has(key):
		return true

	var value := await getLocalization(key, lang_code)
	return not value.is_empty()


## Resolve the default language from the OS locale, falling back to "en".
## @return A supported language code
func _detectDefaultLanguage() -> String:
	var locale := OS.get_locale_language()
	if SUPPORTED_LANGUAGES.has(locale):
		return locale
	return "en"
