## ============================================================
## horizOn SDK - Feedback Manager
## ============================================================
## Handles user feedback submission for bug reports,
## feature requests, and general feedback.
## ============================================================
class_name HorizonFeedback
extends RefCounted

## Signals
signal feedback_submitted()
signal feedback_submit_failed(error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth


## Initialize the feedback manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("Feedback manager initialized")


## Submit user feedback.
## @param title Feedback title (1-100 characters)
## @param message Feedback message (1-2048 characters)
## @param category Optional category (e.g., "BUG", "FEATURE", "GENERAL")
## @param email Optional email for follow-up
## @param include_device_info Whether to include device information
## @return True if submission succeeded
func submit(title: String, message: String, category: String = "", email: String = "", include_device_info: bool = true) -> bool:
	if title.is_empty():
		_logger.error("Feedback title is required")
		feedback_submit_failed.emit("Feedback title is required")
		return false

	if message.is_empty():
		_logger.error("Feedback message is required")
		feedback_submit_failed.emit("Feedback message is required")
		return false

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to submit feedback")
		feedback_submit_failed.emit("User must be signed in")
		return false

	var user := _auth.getCurrentUser()

	var request := {
		"title": title,
		"message": message,
		"userId": user.userId
	}

	if not category.is_empty():
		request["category"] = category

	if not email.is_empty():
		request["email"] = email

	if include_device_info:
		request["deviceInfo"] = _getDeviceInfo()

	var response := await _http.postAsync("/api/v1/app/user-feedback/submit", request)

	if response.isSuccess:
		_logger.info("Feedback submitted successfully")
		feedback_submitted.emit()
		return true

	_logger.error("Feedback submission failed: %s" % response.error)
	feedback_submit_failed.emit(response.error)
	return false


## Submit a bug report (convenience method).
## @param title Bug title
## @param description Bug description
## @param email Optional email for follow-up
## @return True if submission succeeded
func submitBugReport(title: String, description: String, email: String = "") -> bool:
	return await submit(title, description, "BUG", email, true)


## Submit a feature request (convenience method).
## @param title Feature title
## @param description Feature description
## @param email Optional email for follow-up
## @return True if submission succeeded
func submitFeatureRequest(title: String, description: String, email: String = "") -> bool:
	return await submit(title, description, "FEATURE", email, false)


## Get device information for bug reports.
## @return Device info string (max 500 characters)
func _getDeviceInfo() -> String:
	var info := []

	# OS and platform
	info.append("OS: %s" % OS.get_name())
	info.append("Model: %s" % OS.get_model_name())

	# Godot version
	var engine := Engine.get_version_info()
	info.append("Godot: %s.%s.%s" % [engine.major, engine.minor, engine.patch])

	# Screen
	var screen_size := DisplayServer.screen_get_size()
	info.append("Screen: %dx%d" % [screen_size.x, screen_size.y])

	# Renderer
	info.append("Renderer: %s" % RenderingServer.get_video_adapter_name())

	# Memory (if available)
	var memory := OS.get_static_memory_usage()
	if memory > 0:
		info.append("Memory: %d MB" % (memory / 1048576))

	var result := " | ".join(info)

	# Truncate to 500 chars (API limit)
	if result.length() > 500:
		result = result.substr(0, 497) + "..."

	return result
