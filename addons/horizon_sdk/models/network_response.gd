## ============================================================
## horizOn SDK - Network Response Models
## ============================================================
## Data classes for network responses from the horizOn API.
## Provides typed access to response data with error handling.
## ============================================================
class_name HorizonNetworkResponse
extends RefCounted

## Whether the request was successful
var isSuccess: bool = false

## Response data (Dictionary or Array depending on endpoint)
var data: Variant = null

## Error message if request failed
var error: String = ""

## HTTP status code
var statusCode: int = 0

## Error code enum value
var errorCode: int = 0


## Create a successful response.
## @param response_data The response data
## @param status The HTTP status code
## @return A new successful response
static func success(response_data: Variant, status: int = 200) -> HorizonNetworkResponse:
	var response := HorizonNetworkResponse.new()
	response.isSuccess = true
	response.data = response_data
	response.statusCode = status
	response.errorCode = HorizonErrorCodes.ErrorCode.NONE
	return response


## Create a failed response.
## @param error_message The error message
## @param status The HTTP status code
## @param code The error code enum value
## @return A new failed response
static func failure(error_message: String, status: int = 0, code: int = HorizonErrorCodes.ErrorCode.UNKNOWN) -> HorizonNetworkResponse:
	var response := HorizonNetworkResponse.new()
	response.isSuccess = false
	response.error = error_message
	response.statusCode = status
	response.errorCode = code
	return response


## Get data as a Dictionary (with null safety).
## @return Dictionary or empty dict if not available
func asDict() -> Dictionary:
	if data is Dictionary:
		return data
	return {}


## Get data as an Array (with null safety).
## @return Array or empty array if not available
func asArray() -> Array:
	if data is Array:
		return data
	return []


## Get a string value from the response data.
## Safely handles null values.
## @param key The key to look up
## @param default_value Default value if key not found or null
## @return The string value or default
func getString(key: String, default_value: String = "") -> String:
	if data is Dictionary:
		var val = data.get(key)
		return val if val is String else default_value
	return default_value


## Get an int value from the response data.
## Safely handles null values.
## @param key The key to look up
## @param default_value Default value if key not found or null
## @return The int value or default
func getInt(key: String, default_value: int = 0) -> int:
	if data is Dictionary:
		var val = data.get(key)
		return int(val) if val != null else default_value
	return default_value


## Get a bool value from the response data.
## Safely handles null values.
## @param key The key to look up
## @param default_value Default value if key not found or null
## @return The bool value or default
func getBool(key: String, default_value: bool = false) -> bool:
	if data is Dictionary:
		var val = data.get(key)
		return val if val is bool else default_value
	return default_value
