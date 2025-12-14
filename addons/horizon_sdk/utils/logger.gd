## ============================================================
## horizOn SDK - Logger Utility
## ============================================================
## Provides consistent logging functionality with log levels
## and formatted output for the horizOn SDK.
## ============================================================
class_name HorizonLogger
extends RefCounted

## Log level enumeration
enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3,
	NONE = 4
}

## Current log level - messages below this level are filtered
var log_level: LogLevel = LogLevel.INFO

## Prefix for all log messages
const LOG_PREFIX := "[horizOn]"


## Initialize the logger with a specific log level.
## @param level The minimum log level to display
func _init(level: LogLevel = LogLevel.INFO) -> void:
	log_level = level


## Set the current log level.
## @param level The minimum log level to display
func setLogLevel(level: LogLevel) -> void:
	log_level = level


## Log a debug message.
## @param message The message to log
## @param context Optional context object for additional information
func debug(message: String, context: Variant = null) -> void:
	if log_level <= LogLevel.DEBUG:
		var formatted := _formatMessage("DEBUG", message, context)
		print(formatted)


## Log an info message.
## @param message The message to log
## @param context Optional context object for additional information
func info(message: String, context: Variant = null) -> void:
	if log_level <= LogLevel.INFO:
		var formatted := _formatMessage("INFO", message, context)
		print(formatted)


## Log a warning message.
## @param message The message to log
## @param context Optional context object for additional information
func warning(message: String, context: Variant = null) -> void:
	if log_level <= LogLevel.WARNING:
		var formatted := _formatMessage("WARN", message, context)
		push_warning(formatted)


## Log an error message.
## @param message The message to log
## @param context Optional context object for additional information
func error(message: String, context: Variant = null) -> void:
	if log_level <= LogLevel.ERROR:
		var formatted := _formatMessage("ERROR", message, context)
		push_error(formatted)


## Format a log message with timestamp and context.
## @param level_str The log level string
## @param message The message to format
## @param context Optional context object
## @return Formatted log message string
func _formatMessage(level_str: String, message: String, context: Variant) -> String:
	var timestamp := Time.get_datetime_string_from_system(false, true)
	var base := "%s [%s] %s %s" % [LOG_PREFIX, timestamp, level_str, message]

	if context != null:
		if context is Dictionary or context is Array:
			base += " | Context: %s" % JSON.stringify(context)
		else:
			base += " | Context: %s" % str(context)

	return base
