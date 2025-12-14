## ============================================================
## horizOn SDK - Error Codes
## ============================================================
## Defines error codes and messages for the horizOn SDK.
## Maps HTTP status codes to meaningful error messages.
## ============================================================
class_name HorizonErrorCodes
extends RefCounted

## HTTP Status Codes
const HTTP_OK := 200
const HTTP_CREATED := 201
const HTTP_NO_CONTENT := 204
const HTTP_BAD_REQUEST := 400
const HTTP_UNAUTHORIZED := 401
const HTTP_FORBIDDEN := 403
const HTTP_NOT_FOUND := 404
const HTTP_CONFLICT := 409
const HTTP_RATE_LIMITED := 429
const HTTP_SERVER_ERROR := 500

## SDK Error Codes
enum ErrorCode {
	NONE = 0,
	UNKNOWN = 1,
	NETWORK_ERROR = 100,
	CONNECTION_TIMEOUT = 101,
	NO_INTERNET = 102,
	SSL_ERROR = 103,
	INVALID_RESPONSE = 104,

	## Authentication Errors
	AUTH_INVALID_CREDENTIALS = 200,
	AUTH_USER_NOT_FOUND = 201,
	AUTH_USER_NOT_VERIFIED = 202,
	AUTH_USER_DEACTIVATED = 203,
	AUTH_USER_DELETED = 204,
	AUTH_TOKEN_EXPIRED = 205,
	AUTH_INVALID_TOKEN = 206,
	AUTH_USER_EXISTS = 207,
	AUTH_NOT_SIGNED_IN = 208,

	## API Errors
	API_INVALID_REQUEST = 300,
	API_UNAUTHORIZED = 301,
	API_FORBIDDEN = 302,
	API_NOT_FOUND = 303,
	API_RATE_LIMITED = 304,
	API_SERVER_ERROR = 305,

	## Configuration Errors
	CONFIG_NOT_FOUND = 400,
	CONFIG_INVALID = 401,
	CONFIG_API_KEY_MISSING = 402,
	CONFIG_NO_HOSTS = 403,

	## SDK Errors
	SDK_NOT_INITIALIZED = 500,
	SDK_NOT_CONNECTED = 501,
	SDK_ALREADY_INITIALIZED = 502,
}

## Authentication status strings from server
const AUTH_STATUS_AUTHENTICATED := "AUTHENTICATED"
const AUTH_STATUS_USER_NOT_FOUND := "USER_NOT_FOUND"
const AUTH_STATUS_INVALID_CREDENTIALS := "INVALID_CREDENTIALS"
const AUTH_STATUS_USER_NOT_VERIFIED := "USER_NOT_VERIFIED"
const AUTH_STATUS_USER_DEACTIVATED := "USER_DEACTIVATED"
const AUTH_STATUS_USER_DELETED := "USER_DELETED"
const AUTH_STATUS_TOKEN_EXPIRED := "TOKEN_EXPIRED"
const AUTH_STATUS_INVALID_TOKEN := "INVALID_TOKEN"


## Get a human-readable error message for an error code.
## @param code The error code
## @return Human-readable error message
static func getMessage(code: ErrorCode) -> String:
	match code:
		ErrorCode.NONE:
			return "No error"
		ErrorCode.UNKNOWN:
			return "An unknown error occurred"
		ErrorCode.NETWORK_ERROR:
			return "Network error - check your internet connection"
		ErrorCode.CONNECTION_TIMEOUT:
			return "Connection timed out"
		ErrorCode.NO_INTERNET:
			return "No internet connection"
		ErrorCode.SSL_ERROR:
			return "SSL/TLS certificate error"
		ErrorCode.INVALID_RESPONSE:
			return "Invalid response from server"
		ErrorCode.AUTH_INVALID_CREDENTIALS:
			return "Invalid email or password"
		ErrorCode.AUTH_USER_NOT_FOUND:
			return "User not found"
		ErrorCode.AUTH_USER_NOT_VERIFIED:
			return "Email not verified - check your inbox"
		ErrorCode.AUTH_USER_DEACTIVATED:
			return "Account has been deactivated"
		ErrorCode.AUTH_USER_DELETED:
			return "Account has been deleted"
		ErrorCode.AUTH_TOKEN_EXPIRED:
			return "Session expired - please sign in again"
		ErrorCode.AUTH_INVALID_TOKEN:
			return "Invalid authentication token"
		ErrorCode.AUTH_USER_EXISTS:
			return "User already exists - try signing in instead"
		ErrorCode.AUTH_NOT_SIGNED_IN:
			return "User must be signed in to perform this action"
		ErrorCode.API_INVALID_REQUEST:
			return "Invalid request - check your parameters"
		ErrorCode.API_UNAUTHORIZED:
			return "Unauthorized - invalid API key or session"
		ErrorCode.API_FORBIDDEN:
			return "Access forbidden - insufficient permissions"
		ErrorCode.API_NOT_FOUND:
			return "Resource not found"
		ErrorCode.API_RATE_LIMITED:
			return "Rate limit exceeded - try again later"
		ErrorCode.API_SERVER_ERROR:
			return "Server error - try again later"
		ErrorCode.CONFIG_NOT_FOUND:
			return "Configuration not found"
		ErrorCode.CONFIG_INVALID:
			return "Invalid configuration"
		ErrorCode.CONFIG_API_KEY_MISSING:
			return "API key is missing from configuration"
		ErrorCode.CONFIG_NO_HOSTS:
			return "No server hosts configured"
		ErrorCode.SDK_NOT_INITIALIZED:
			return "SDK not initialized - call Horizon.initialize() first"
		ErrorCode.SDK_NOT_CONNECTED:
			return "Not connected to server - call Horizon.connect() first"
		ErrorCode.SDK_ALREADY_INITIALIZED:
			return "SDK is already initialized"
		_:
			return "Unknown error code: %d" % code


## Convert HTTP status code to error code.
## @param http_status The HTTP status code
## @param auth_status Optional authentication status string
## @return Corresponding error code
static func fromHttpStatus(http_status: int, auth_status: String = "") -> ErrorCode:
	# Check auth status first if provided
	if not auth_status.is_empty():
		match auth_status:
			AUTH_STATUS_AUTHENTICATED:
				return ErrorCode.NONE
			AUTH_STATUS_USER_NOT_FOUND:
				return ErrorCode.AUTH_USER_NOT_FOUND
			AUTH_STATUS_INVALID_CREDENTIALS:
				return ErrorCode.AUTH_INVALID_CREDENTIALS
			AUTH_STATUS_USER_NOT_VERIFIED:
				return ErrorCode.AUTH_USER_NOT_VERIFIED
			AUTH_STATUS_USER_DEACTIVATED:
				return ErrorCode.AUTH_USER_DEACTIVATED
			AUTH_STATUS_USER_DELETED:
				return ErrorCode.AUTH_USER_DELETED
			AUTH_STATUS_TOKEN_EXPIRED:
				return ErrorCode.AUTH_TOKEN_EXPIRED
			AUTH_STATUS_INVALID_TOKEN:
				return ErrorCode.AUTH_INVALID_TOKEN

	# Fall back to HTTP status
	match http_status:
		HTTP_OK, HTTP_CREATED, HTTP_NO_CONTENT:
			return ErrorCode.NONE
		HTTP_BAD_REQUEST:
			return ErrorCode.API_INVALID_REQUEST
		HTTP_UNAUTHORIZED:
			return ErrorCode.API_UNAUTHORIZED
		HTTP_FORBIDDEN:
			return ErrorCode.API_FORBIDDEN
		HTTP_NOT_FOUND:
			return ErrorCode.API_NOT_FOUND
		HTTP_CONFLICT:
			return ErrorCode.AUTH_USER_EXISTS
		HTTP_RATE_LIMITED:
			return ErrorCode.API_RATE_LIMITED
		_:
			if http_status >= 500:
				return ErrorCode.API_SERVER_ERROR
			return ErrorCode.UNKNOWN
