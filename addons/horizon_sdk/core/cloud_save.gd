## ============================================================
## horizOn SDK - Cloud Save Manager
## ============================================================
## Handles cloud save operations for player progress and data.
## Supports both JSON and binary data formats.
## ============================================================
class_name HorizonCloudSave
extends RefCounted

## Signals
signal data_saved(size_bytes: int)
signal data_save_failed(error: String)
signal data_loaded(data: String)
signal data_load_failed(error: String)
signal bytes_saved(size_bytes: int)
signal bytes_loaded(data: PackedByteArray)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth


## Initialize the cloud save manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("Cloud save manager initialized")


## Save string data to the cloud (JSON mode).
## @param data String data to save
## @return True if save succeeded
func saveData(data: String) -> bool:
	if data.is_empty():
		_logger.error("Save data is required")
		data_save_failed.emit("Save data is required")
		return false

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to save data")
		data_save_failed.emit("User must be signed in")
		return false

	var user = _auth.getCurrentUser()

	var request = {
		"userId": user.userId,
		"saveData": data
	}

	var response = await _http.postAsync("/api/v1/app/cloud-save/save", request)

	if response.isSuccess and response.data is Dictionary:
		var success: bool = response.data.get("success", false)
		if success:
			var sizeBytes: int = response.data.get("dataSizeBytes", data.length())
			_logger.info("Cloud data saved: %d bytes" % sizeBytes)
			data_saved.emit(sizeBytes)
			return true

	_logger.error("Cloud save failed: %s" % response.error)
	data_save_failed.emit(response.error)
	return false


## Load string data from the cloud (JSON mode).
## @return Loaded string data, or empty string if failed
func loadData() -> String:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to load data")
		data_load_failed.emit("User must be signed in")
		return ""

	var user = _auth.getCurrentUser()

	var request = {
		"userId": user.userId
	}

	var response = await _http.postAsync("/api/v1/app/cloud-save/load", request)

	if response.isSuccess and response.data is Dictionary:
		var found: bool = response.data.get("found", false)
		if found:
			var loadedData: String = response.data.get("saveData", "")
			_logger.info("Cloud data loaded: %d bytes" % loadedData.length())
			data_loaded.emit(loadedData)
			return loadedData
		else:
			_logger.info("No cloud save data found")
			return ""

	_logger.error("Cloud load failed: %s" % response.error)
	data_load_failed.emit(response.error)
	return ""


## Save raw binary data to the cloud.
## Uses application/octet-stream content type.
## @param data Binary data to save
## @return True if save succeeded
func saveBytes(data: PackedByteArray) -> bool:
	if data.is_empty():
		_logger.error("Save data is required")
		data_save_failed.emit("Save data is required")
		return false

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to save data")
		data_save_failed.emit("User must be signed in")
		return false

	var user = _auth.getCurrentUser()
	var endpoint = "/api/v1/app/cloud-save/save?userId=%s" % user.userId

	var response = await _http.postBinaryAsync(endpoint, data)

	if response.isSuccess and response.data is Dictionary:
		var success: bool = response.data.get("success", false)
		if success:
			var sizeBytes: int = response.data.get("dataSizeBytes", data.size())
			_logger.info("Cloud data saved (binary): %d bytes" % sizeBytes)
			bytes_saved.emit(sizeBytes)
			return true

	_logger.error("Cloud save (binary) failed: %s" % response.error)
	data_save_failed.emit(response.error)
	return false


## Load raw binary data from the cloud.
## @return Binary data, or empty array if not found or failed
func loadBytes() -> PackedByteArray:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to load data")
		data_load_failed.emit("User must be signed in")
		return PackedByteArray()

	var user = _auth.getCurrentUser()
	var endpoint = "/api/v1/app/cloud-save/load?userId=%s" % user.userId

	var result = await _http.getBinaryAsync(endpoint)

	if result.get("success", false):
		if result.get("found", false):
			var data: PackedByteArray = result.get("data", PackedByteArray())
			_logger.info("Cloud data loaded (binary): %d bytes" % data.size())
			bytes_loaded.emit(data)
			return data
		else:
			_logger.info("No cloud save data found (binary)")
			return PackedByteArray()

	_logger.error("Cloud load (binary) failed: %s" % result.get("error", "Unknown error"))
	data_load_failed.emit(result.get("error", "Unknown error"))
	return PackedByteArray()


## Save a Dictionary as JSON to the cloud.
## @param obj Dictionary to save
## @return True if save succeeded
func saveObject(obj: Dictionary) -> bool:
	var json = JSON.stringify(obj)
	return await saveData(json)


## Load a Dictionary from JSON in the cloud.
## @return Loaded Dictionary, or empty dict if failed
func loadObject() -> Dictionary:
	var json = await loadData()
	if json.is_empty():
		return {}

	var parsed = JSON.parse_string(json)
	if parsed is Dictionary:
		return parsed

	_logger.warning("Failed to parse cloud save as Dictionary")
	return {}


## Save a typed object (Resource or custom class) to the cloud.
## Uses Godot's var_to_str for serialization.
## @param obj Object to save
## @return True if save succeeded
func saveVariant(obj: Variant) -> bool:
	var serialized = var_to_str(obj)
	return await saveData(serialized)


## Load a typed object from the cloud.
## Uses Godot's str_to_var for deserialization.
## @return Loaded object, or null if failed
func loadVariant() -> Variant:
	var data = await loadData()
	if data.is_empty():
		return null

	return str_to_var(data)
