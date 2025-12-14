## ============================================================
## horizOn SDK - User Logs Manager
## ============================================================
## Handles creating user log entries for tracking player actions,
## errors, and events. Note: Not available for FREE accounts.
## ============================================================
class_name HorizonUserLogs
extends RefCounted

## Log type enumeration (matches server)
enum LogType {
	INFO,
	WARN,
	ERROR
}

## Signals
signal log_created(id: String, created_at: String)
signal log_create_failed(error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth


## Initialize the user logs manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("User logs manager initialized")


## Create a user log entry.
## @param type Log type (INFO, WARN, ERROR)
## @param message Log message (max 1000 characters)
## @param error_code Optional error code (max 50 characters)
## @return Dictionary with id and createdAt, or empty dict on failure
func createLog(type: LogType, message: String, error_code: String = "") -> Dictionary:
	if message.is_empty():
		_logger.error("Log message is required")
		log_create_failed.emit("Log message is required")
		return {}

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to create logs")
		log_create_failed.emit("User must be signed in")
		return {}

	var user := _auth.getCurrentUser()

	var type_str: String
	match type:
		LogType.INFO:
			type_str = "INFO"
		LogType.WARN:
			type_str = "WARN"
		LogType.ERROR:
			type_str = "ERROR"

	var request := {
		"message": message,
		"type": type_str,
		"userId": user.userId
	}

	if not error_code.is_empty():
		request["errorCode"] = error_code

	var response := await _http.postAsync("/api/v1/app/user-logs/create", request)

	if response.isSuccess and response.data is Dictionary:
		var id: String = response.data.get("id", "")
		var createdAt: String = response.data.get("createdAt", "")

		if not id.is_empty():
			_logger.info("User log created: %s" % id)
			log_created.emit(id, createdAt)
			return {
				"id": id,
				"createdAt": createdAt
			}

	var errorMsg := response.error
	if response.statusCode == 403:
		errorMsg = "User logs feature not available for FREE accounts"

	_logger.error("User log creation failed: %s" % errorMsg)
	log_create_failed.emit(errorMsg)
	return {}


## Create an INFO log entry (convenience method).
## @param message Log message
## @return Dictionary with id and createdAt, or empty dict on failure
func info(message: String) -> Dictionary:
	return await createLog(LogType.INFO, message)


## Create a WARN log entry (convenience method).
## @param message Log message
## @param error_code Optional error code
## @return Dictionary with id and createdAt, or empty dict on failure
func warn(message: String, error_code: String = "") -> Dictionary:
	return await createLog(LogType.WARN, message, error_code)


## Create an ERROR log entry (convenience method).
## @param message Log message
## @param error_code Optional error code
## @return Dictionary with id and createdAt, or empty dict on failure
func error(message: String, error_code: String = "") -> Dictionary:
	return await createLog(LogType.ERROR, message, error_code)


## Log a game event (convenience method for INFO).
## @param event_name Name of the event
## @param details Optional event details
## @return Dictionary with id and createdAt, or empty dict on failure
func logEvent(event_name: String, details: String = "") -> Dictionary:
	var message := event_name
	if not details.is_empty():
		message += ": %s" % details
	return await info(message)


## Log an error with stack trace (convenience method).
## @param error_message Error message
## @param stack_trace Optional stack trace or additional context
## @return Dictionary with id and createdAt, or empty dict on failure
func logError(error_message: String, stack_trace: String = "") -> Dictionary:
	var message := error_message
	if not stack_trace.is_empty():
		message += "\nStack: %s" % stack_trace

	# Truncate to API limit
	if message.length() > 1000:
		message = message.substr(0, 997) + "..."

	return await error(message)
