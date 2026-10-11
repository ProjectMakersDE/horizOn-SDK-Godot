## ============================================================
## horizOn SDK - Cloud Save Manager
## ============================================================
## Handles cloud save operations for player progress and data.
## Supports both JSON and binary data formats. For saving from several
## devices, loadSnapshot()/loadBytesSnapshot() return the server revision
## and saveDataAtRevision()/saveBytesAtRevision() write only while the save
## is still at that revision.
## ============================================================
class_name HorizonCloudSave
extends RefCounted

## Revision when the server sent none (for example a self-hosted simpleServer).
## The state is unknown, not an empty slot.
const REVISION_UNKNOWN := -1

## Outcomes of saveDataAtRevision() and saveBytesAtRevision()
const STATUS_SAVED := "saved"
const STATUS_CONFLICT := "conflict"
const STATUS_FAILED := "failed"

## Revision headers of the cloud save endpoints. Server contract checked
## 2026-10-11 (horizOn-Server AppCloudSaveController and
## CloudSaveExceptionHandler, since 1.64.1): load answers X-Cloud-Save-Revision
## on JSON, bytes and 204 (0 = empty slot), save reads If-Match as a plain
## number and answers 409 on a mismatch, a successful save returns `revision`
## of at least 1.
const _REVISION_HEADER := "X-Cloud-Save-Revision"
const _IF_MATCH_HEADER := "If-Match"

## Signals
signal data_saved(size_bytes: int)
signal data_save_failed(error: String)
signal data_loaded(data: String)
signal data_load_failed(error: String)
signal bytes_saved(size_bytes: int)
signal bytes_loaded(data: PackedByteArray)
## Another device saved first (HTTP 409). Nothing was written.
signal save_conflict(error: String)

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

	var response = await _http.postAsync("/api/v1/app/cloud-save/save", request, true)

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

	var response = await _http.postAsync("/api/v1/app/cloud-save/load", request, true)

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

	var response = await _http.postBinaryAsync(endpoint, data, true)

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
	var request := {"userId": user.userId}

	var result = await _http.postJsonForBinaryAsync("/api/v1/app/cloud-save/load", request, true)

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


## Load the string save together with its server revision, for saving from
## several devices. Pass "revision" as expectedRevision to saveDataAtRevision().
## @return Dictionary with "success" (bool), "found" (bool), "data" (String,
##         "" when not found), "revision" (int: 0 for an empty slot,
##         REVISION_UNKNOWN when the server sent none, which means unknown and
##         not empty), "error" (String) and "statusCode" (int, 0 when the
##         request was not sent)
func loadSnapshot() -> Dictionary:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to load data")
		data_load_failed.emit("User must be signed in")
		return _snapshot(false, false, "", REVISION_UNKNOWN, "User must be signed in", 0)

	var user = _auth.getCurrentUser()
	var response = await _http.postAsync("/api/v1/app/cloud-save/load", {"userId": user.userId}, true)

	if not (response.isSuccess and response.data is Dictionary):
		_logger.error("Cloud load failed: %s" % response.error)
		data_load_failed.emit(response.error)
		return _snapshot(false, false, "", REVISION_UNKNOWN, response.error, response.statusCode)

	# An unreadable answer must not look like an empty slot: saving at its
	# revision would overwrite the stored save.
	var foundValue: Variant = response.data.get("found")
	if not (foundValue is bool) or (foundValue and not (response.data.get("saveData") is String)):
		var unreadable := "Cloud load returned an unreadable response"
		_logger.error(unreadable)
		data_load_failed.emit(unreadable)
		return _snapshot(false, false, "", REVISION_UNKNOWN, unreadable, response.statusCode)

	var revision := _revisionFromHeader(response.getHeader(_REVISION_HEADER))
	var found: bool = foundValue
	var loadedData: String = response.data["saveData"] if found else ""
	if found:
		_logger.info("Cloud data loaded: %d bytes, revision %s" % [loadedData.length(), _formatRevision(revision)])
		data_loaded.emit(loadedData)
	else:
		_logger.info("No cloud save data found, revision %s" % _formatRevision(revision))
	return _snapshot(true, found, loadedData, revision, "", response.statusCode)


## Load the binary save together with its server revision, for saving from
## several devices. Pass "revision" as expectedRevision to saveBytesAtRevision().
## @return Dictionary like loadSnapshot(), with "data" as PackedByteArray
##         (empty when not found, which the server answers with HTTP 204)
func loadBytesSnapshot() -> Dictionary:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to load data")
		data_load_failed.emit("User must be signed in")
		return _snapshot(false, false, PackedByteArray(), REVISION_UNKNOWN, "User must be signed in", 0)

	var user = _auth.getCurrentUser()
	var result = await _http.postJsonForBinaryAsync("/api/v1/app/cloud-save/load", {"userId": user.userId}, true)
	var statusCode: int = result.get("statusCode", 0)

	if not result.get("success", false):
		var error: String = result.get("error", "Unknown error")
		_logger.error("Cloud load (binary) failed: %s" % error)
		data_load_failed.emit(error)
		return _snapshot(false, false, PackedByteArray(), REVISION_UNKNOWN, error, statusCode)

	var revision := _revisionFromHeader(HorizonNetworkResponse.findHeader(result.get("headers", PackedStringArray()), _REVISION_HEADER))
	var found: bool = result.get("found", false)
	var data: PackedByteArray = result.get("data", PackedByteArray()) if found else PackedByteArray()
	if found:
		_logger.info("Cloud data loaded (binary): %d bytes, revision %s" % [data.size(), _formatRevision(revision)])
		bytes_loaded.emit(data)
	else:
		_logger.info("No cloud save data found (binary), revision %s" % _formatRevision(revision))
	return _snapshot(true, found, data, revision, "", statusCode)


## Save a string only if the cloud save is still at expectedRevision (sends
## If-Match). When another device saved first, nothing is written, "status" is
## STATUS_CONFLICT and save_conflict is emitted: load a new snapshot and decide.
## The SDK never retries or overwrites a conflict.
## @param data String data to save
## @param expectedRevision Revision from the last snapshot or save, 0 for an empty slot
## @return Dictionary with "status" (STATUS_SAVED, STATUS_CONFLICT or
##         STATUS_FAILED), "success" (bool), "conflict" (bool), "revision" (int,
##         the new revision after a save, REVISION_UNKNOWN otherwise or when the
##         server sent none), "dataSizeBytes" (int), "error" (String) and
##         "statusCode" (int, 0 when the request was not sent)
func saveDataAtRevision(data: String, expectedRevision: int) -> Dictionary:
	var localError := _checkConditionalSave(data.is_empty(), expectedRevision)
	if not localError.is_empty():
		return _writeFailedLocally(localError)

	var user = _auth.getCurrentUser()
	var request = {
		"userId": user.userId,
		"saveData": data
	}
	var response = await _http.postAsync("/api/v1/app/cloud-save/save", request, true, _ifMatch(expectedRevision))
	return _toWriteResult(response, "Cloud save", false, data.length())


## Save raw bytes only if the cloud save is still at expectedRevision (sends
## If-Match). Same outcomes as saveDataAtRevision().
## @param data Binary data to save
## @param expectedRevision Revision from the last snapshot or save, 0 for an empty slot
## @return Dictionary like saveDataAtRevision()
func saveBytesAtRevision(data: PackedByteArray, expectedRevision: int) -> Dictionary:
	var localError := _checkConditionalSave(data.is_empty(), expectedRevision)
	if not localError.is_empty():
		return _writeFailedLocally(localError)

	var user = _auth.getCurrentUser()
	var endpoint = "/api/v1/app/cloud-save/save?userId=%s" % user.userId
	var response = await _http.postBinaryAsync(endpoint, data, true, _ifMatch(expectedRevision))
	return _toWriteResult(response, "Cloud save (binary)", true, data.size())


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


func _checkConditionalSave(dataMissing: bool, expectedRevision: int) -> String:
	if dataMissing:
		return "Save data is required"
	if expectedRevision < 0:
		return "expectedRevision must be 0 (empty slot) or a revision from a snapshot or save"
	if not _auth.isSignedIn():
		return "User must be signed in to save data"
	return ""


func _ifMatch(expectedRevision: int) -> PackedStringArray:
	return PackedStringArray(["%s: %d" % [_IF_MATCH_HEADER, expectedRevision]])


func _toWriteResult(response: HorizonNetworkResponse, operation: String, binary: bool, fallbackSize: int) -> Dictionary:
	# Saved only when the server confirms the write with a real boolean "success": true.
	if response.isSuccess and response.data is Dictionary and response.data.get("success") is bool and response.data["success"]:
		var revision := _revisionFromSave(response.data.get("revision"))
		var sizeBytes: int = response.data.get("dataSizeBytes", fallbackSize)
		_logger.info("%s written: %d bytes, revision %s" % [operation, sizeBytes, _formatRevision(revision)])
		if binary:
			bytes_saved.emit(sizeBytes)
		else:
			data_saved.emit(sizeBytes)
		return _writeResult(STATUS_SAVED, revision, sizeBytes, "", response.statusCode)

	if response.statusCode == 409:
		var conflict := "Cloud save changed on another device (HTTP 409). Nothing was written. Load a new snapshot before saving again."
		_logger.warning("%s conflict: %s" % [operation, conflict])
		save_conflict.emit(conflict)
		return _writeResult(STATUS_CONFLICT, REVISION_UNKNOWN, 0, conflict, response.statusCode)

	var error: String = response.error if not response.isSuccess else "Cloud save response did not confirm the write"
	_logger.error("%s failed: %s" % [operation, error])
	data_save_failed.emit(error)
	return _writeResult(STATUS_FAILED, REVISION_UNKNOWN, 0, error, response.statusCode)


func _writeFailedLocally(error: String) -> Dictionary:
	_logger.error(error)
	data_save_failed.emit(error)
	return _writeResult(STATUS_FAILED, REVISION_UNKNOWN, 0, error, 0)


func _writeResult(status: String, revision: int, sizeBytes: int, error: String, statusCode: int) -> Dictionary:
	return {
		"status": status,
		"success": status == STATUS_SAVED,
		"conflict": status == STATUS_CONFLICT,
		"revision": revision,
		"dataSizeBytes": sizeBytes,
		"error": error,
		"statusCode": statusCode
	}


func _snapshot(success: bool, found: bool, data: Variant, revision: int, error: String, statusCode: int) -> Dictionary:
	return {
		"success": success,
		"found": found,
		"data": data,
		"revision": revision,
		"error": error,
		"statusCode": statusCode
	}


## Revision from the load header, REVISION_UNKNOWN when it is missing or not a number.
func _revisionFromHeader(value: String) -> int:
	var trimmed := value.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_int():
		return REVISION_UNKNOWN
	var revision := trimmed.to_int()
	return revision if revision >= 0 else REVISION_UNKNOWN


## Revision from a successful save. A written save is at least revision 1,
## so a missing value or 0 means the server sent none.
func _revisionFromSave(value: Variant) -> int:
	if not (value is int or value is float):
		return REVISION_UNKNOWN
	if value is float and (value != floor(value) or value >= 9223372036854775807.0):
		return REVISION_UNKNOWN
	var revision := int(value)
	return revision if revision > 0 else REVISION_UNKNOWN


func _formatRevision(revision: int) -> String:
	return "unknown" if revision == REVISION_UNKNOWN else str(revision)
