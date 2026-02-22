## ============================================================
## horizOn SDK - Crash Reporting Manager
## ============================================================
## Handles crash reporting, non-fatal exception tracking,
## breadcrumbs, and session registration for the horizOn SDK.
## Features token bucket rate limiting, fingerprint generation,
## and device info caching.
## ============================================================
class_name HorizonCrashes
extends RefCounted

## Signals
signal crash_reported(fingerprint: String)
signal crash_report_failed(error: String)
signal session_registered(session_id: String)

## Crash type enumeration
enum CrashType {
	CRASH,
	NON_FATAL,
	ANR
}

## Breadcrumb type constants
const BREADCRUMB_NAVIGATION := "navigation"
const BREADCRUMB_USER_ACTION := "user_action"
const BREADCRUMB_LOG := "log"
const BREADCRUMB_ERROR := "error"
const BREADCRUMB_STATE := "state"

## Rate limiter constants
const TOKENS_PER_MINUTE := 5
const MAX_SESSION_REPORTS := 20
const TOKEN_REFILL_INTERVAL_SEC := 60.0

## Ring buffer limits
const MAX_BREADCRUMBS := 50
const MAX_CUSTOM_KEYS := 10

## Fingerprint constants
const MAX_FINGERPRINT_FRAMES := 5

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth

## Session state
var _sessionId: String = ""
var _userId: String = ""

## Rate limiter state
var _tokenCount: int = TOKENS_PER_MINUTE
var _sessionReportCount: int = 0
var _lastRefillTime: float = 0.0

## Breadcrumb ring buffer
var _breadcrumbs: Array[Dictionary] = []
var _breadcrumbIndex: int = 0
var _breadcrumbCount: int = 0

## Custom keys
var _customKeys: Dictionary = {}

## Device info cache
var _cachedDeviceInfo: Dictionary = {}


## Initialize the crash reporting manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth

	_sessionId = _generate_session_id()
	_lastRefillTime = Time.get_unix_time_from_system()
	_cache_device_info()

	# Pre-allocate breadcrumb ring buffer
	_breadcrumbs.resize(MAX_BREADCRUMBS)
	for i in MAX_BREADCRUMBS:
		_breadcrumbs[i] = {}

	_logger.info("Crash reporting manager initialized (session: %s)" % _sessionId)


## Register a new crash reporting session with the server.
## @return True if session registration succeeded
func register_session() -> bool:
	var request := {
		"sessionId": _sessionId,
		"userId": _get_user_id(),
		"deviceInfo": _cachedDeviceInfo,
		"sdkVersion": "godot-1.0.0",
		"timestamp": Time.get_datetime_string_from_system(true, true)
	}

	var response := await _http.postAsync("/api/v1/app/crash-reporting/session", request)

	if response.isSuccess:
		_logger.info("Crash session registered: %s" % _sessionId)
		session_registered.emit(_sessionId)
		return true

	_logger.error("Crash session registration failed: %s" % response.error)
	return false


## Record a non-fatal exception.
## @param message Error message describing the exception
## @param stack_trace Stack trace string
## @param extra_keys Optional additional key-value pairs
## @return True if the report was submitted
func record_exception(message: String, stack_trace: String = "", extra_keys: Dictionary = {}) -> bool:
	return await _submit_report(CrashType.NON_FATAL, message, stack_trace, extra_keys)


## Report a fatal crash.
## @param message Error message describing the crash
## @param stack_trace Stack trace string
## @return True if the report was submitted
func report_crash(message: String, stack_trace: String = "") -> bool:
	return await _submit_report(CrashType.CRASH, message, stack_trace)


## Record a breadcrumb for crash context.
## @param type Breadcrumb type (use BREADCRUMB_* constants)
## @param message Breadcrumb message
func record_breadcrumb(type: String, message: String) -> void:
	_add_breadcrumb(type, message)


## Add a log breadcrumb (shorthand).
## @param message Log message to record as breadcrumb
func log(message: String) -> void:
	_add_breadcrumb(BREADCRUMB_LOG, message)


## Set a custom key-value pair included with crash reports.
## Maximum 10 keys allowed; oldest keys are replaced when limit is reached.
## @param key The key name
## @param value The value (will be converted to string)
func set_custom_key(key: String, value: Variant) -> void:
	if _customKeys.size() >= MAX_CUSTOM_KEYS and not _customKeys.has(key):
		_logger.warning("Custom key limit (%d) reached. Ignoring key: %s" % [MAX_CUSTOM_KEYS, key])
		return

	_customKeys[key] = str(value)
	_logger.debug("Custom key set: %s" % key)


## Override the user ID for crash reports.
## @param user_id The user ID to associate with future crash reports
func set_user_id(user_id: String) -> void:
	_userId = user_id
	_logger.debug("Crash user ID set: %s" % user_id)


# ===== INTERNAL METHODS =====

## Core report submission with rate limiting.
## @param type Crash type (CRASH, NON_FATAL, ANR)
## @param message Error message
## @param stack_trace Stack trace string
## @param extra_keys Additional key-value pairs
## @return True if the report was submitted
func _submit_report(type: CrashType, message: String, stack_trace: String, extra_keys: Dictionary = {}) -> bool:
	if message.is_empty():
		_logger.error("Crash report message is required")
		crash_report_failed.emit("Crash report message is required")
		return false

	# Rate limiting check
	_refill_tokens()

	if _tokenCount <= 0:
		_logger.warning("Crash report rate limited (per-minute limit reached)")
		crash_report_failed.emit("Rate limited: too many reports per minute")
		return false

	if _sessionReportCount >= MAX_SESSION_REPORTS:
		_logger.warning("Crash report rate limited (session limit reached: %d)" % MAX_SESSION_REPORTS)
		crash_report_failed.emit("Rate limited: session report limit reached")
		return false

	# Consume a token
	_tokenCount -= 1
	_sessionReportCount += 1

	# Build fingerprint
	var fingerprint := _generate_fingerprint(stack_trace)

	# Build type string
	var type_str: String
	match type:
		CrashType.CRASH:
			type_str = "CRASH"
		CrashType.NON_FATAL:
			type_str = "NON_FATAL"
		CrashType.ANR:
			type_str = "ANR"

	# Collect breadcrumbs
	var breadcrumb_list: Array[Dictionary] = []
	var count := mini(_breadcrumbCount, MAX_BREADCRUMBS)
	if count > 0:
		if _breadcrumbCount <= MAX_BREADCRUMBS:
			# Buffer has not wrapped yet
			for i in count:
				if not _breadcrumbs[i].is_empty():
					breadcrumb_list.append(_breadcrumbs[i].duplicate())
		else:
			# Buffer has wrapped: read from oldest to newest
			for i in count:
				var idx := (_breadcrumbIndex + i) % MAX_BREADCRUMBS
				if not _breadcrumbs[idx].is_empty():
					breadcrumb_list.append(_breadcrumbs[idx].duplicate())

	# Merge custom keys with extra keys
	var all_keys := _customKeys.duplicate()
	for key in extra_keys:
		all_keys[key] = str(extra_keys[key])

	# Build request
	var request := {
		"sessionId": _sessionId,
		"userId": _get_user_id(),
		"type": type_str,
		"message": message,
		"fingerprint": fingerprint,
		"deviceInfo": _cachedDeviceInfo,
		"breadcrumbs": breadcrumb_list,
		"timestamp": Time.get_datetime_string_from_system(true, true)
	}

	if not stack_trace.is_empty():
		request["stackTrace"] = stack_trace

	if not all_keys.is_empty():
		request["customKeys"] = all_keys

	var response := await _http.postAsync("/api/v1/app/crash-reporting/report", request)

	if response.isSuccess:
		_logger.info("Crash report submitted (%s): %s" % [type_str, fingerprint])
		crash_reported.emit(fingerprint)
		return true

	var errorMsg := response.error
	_logger.error("Crash report submission failed: %s" % errorMsg)
	crash_report_failed.emit(errorMsg)
	return false


## Generate a SHA-256 fingerprint from the top game-code frames.
## Strips Godot engine prefixes and normalizes frames before hashing.
## @param stack_trace Raw stack trace string
## @return Hex-encoded SHA-256 fingerprint
func _generate_fingerprint(stack_trace: String) -> String:
	if stack_trace.is_empty():
		return _hash_string("no_stack_trace")

	var lines := stack_trace.split("\n", false)
	var normalized_frames: PackedStringArray = []

	for line in lines:
		var normalized := _normalize_frame(line.strip_edges())
		if not normalized.is_empty():
			normalized_frames.append(normalized)
			if normalized_frames.size() >= MAX_FINGERPRINT_FRAMES:
				break

	if normalized_frames.is_empty():
		return _hash_string(stack_trace)

	var fingerprint_input := "\n".join(normalized_frames)
	return _hash_string(fingerprint_input)


## Normalize a stack frame by stripping line numbers, addresses, and engine prefixes.
## @param frame Raw stack frame string
## @return Normalized frame string
func _normalize_frame(frame: String) -> String:
	if frame.is_empty():
		return ""

	var normalized := frame

	# Strip Godot engine prefixes (e.g., "res://", "user://")
	normalized = normalized.replace("res://", "")
	normalized = normalized.replace("user://", "")

	# Strip memory addresses (e.g., "0x7fff12345678")
	var addr_regex := RegEx.new()
	addr_regex.compile("0x[0-9a-fA-F]+")
	normalized = addr_regex.sub(normalized, "", true)

	# Strip line numbers (e.g., ":42", " line 42")
	var line_regex := RegEx.new()
	line_regex.compile(":\\d+")
	normalized = line_regex.sub(normalized, "", true)

	var line_word_regex := RegEx.new()
	line_word_regex.compile("\\bline \\d+\\b")
	normalized = line_word_regex.sub(normalized, "", true)

	# Strip leading "at " prefix common in stack traces
	if normalized.begins_with("at "):
		normalized = normalized.substr(3)

	# Collapse whitespace
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")

	return normalized.strip_edges()


## Compute SHA-256 hash of a string.
## @param input The string to hash
## @return Hex-encoded SHA-256 hash
func _hash_string(input: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(input.to_utf8_buffer())
	var digest := ctx.finish()
	return digest.hex_encode()


## Add a breadcrumb to the ring buffer.
## @param type Breadcrumb type
## @param message Breadcrumb message
func _add_breadcrumb(type: String, message: String) -> void:
	var breadcrumb := {
		"type": type,
		"message": message,
		"timestamp": Time.get_datetime_string_from_system(true, true)
	}

	_breadcrumbs[_breadcrumbIndex] = breadcrumb
	_breadcrumbIndex = (_breadcrumbIndex + 1) % MAX_BREADCRUMBS
	_breadcrumbCount += 1

	_logger.debug("Breadcrumb [%s]: %s" % [type, message])


## Refill rate limiter tokens based on elapsed time.
func _refill_tokens() -> void:
	var now := Time.get_unix_time_from_system()
	var elapsed := now - _lastRefillTime

	if elapsed >= TOKEN_REFILL_INTERVAL_SEC:
		var refills := int(elapsed / TOKEN_REFILL_INTERVAL_SEC)
		_tokenCount = mini(_tokenCount + refills * TOKENS_PER_MINUTE, TOKENS_PER_MINUTE)
		_lastRefillTime = now


## Cache device information from OS.* APIs.
func _cache_device_info() -> void:
	var engine_info := Engine.get_version_info()

	_cachedDeviceInfo = {
		"os": OS.get_name(),
		"osVersion": OS.get_version(),
		"model": OS.get_model_name(),
		"locale": OS.get_locale(),
		"processorName": OS.get_processor_name(),
		"processorCount": OS.get_processor_count(),
		"godotVersion": "%s.%s.%s" % [engine_info.major, engine_info.minor, engine_info.patch],
		"renderer": RenderingServer.get_video_adapter_name(),
		"platform": OS.get_name(),
		"staticMemoryMB": int(OS.get_static_memory_usage() / 1048576)
	}

	# Screen size (may not be available in headless mode)
	if DisplayServer.get_name() != "headless":
		var screen_size := DisplayServer.screen_get_size()
		_cachedDeviceInfo["screenWidth"] = screen_size.x
		_cachedDeviceInfo["screenHeight"] = screen_size.y


## Get the user ID from override or auth.
## @return User ID string
func _get_user_id() -> String:
	# Explicit override takes priority
	if not _userId.is_empty():
		return _userId

	# Fall back to authenticated user
	if _auth != null and _auth.isSignedIn():
		var user := _auth.getCurrentUser()
		if user != null and not user.userId.is_empty():
			return user.userId

	return "anonymous"


## Generate a random session ID.
## @return 32-character hex session ID
func _generate_session_id() -> String:
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(randi() % 256)
	return bytes.hex_encode()
