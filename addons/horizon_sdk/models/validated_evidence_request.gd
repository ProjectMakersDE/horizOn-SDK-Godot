## ============================================================
## horizOn SDK - Validated Evidence Request Model
## ============================================================
## Evidence request of an accepted run (Validated Actions Part 3,
## TASK-888): when `required` is true the game uploads the raw
## input log whose SHA-256 it sent with the run. Part 1 servers
## send `evidence: null`, which maps to required = false.
## ============================================================
class_name HorizonValidatedEvidenceRequest
extends RefCounted

## True when the input log must be uploaded
var required: bool = false

## Run the log belongs to ("" when not required)
var runId: String = ""

## Upload deadline, ISO 8601 UTC ("" when not required)
var uploadBefore: String = ""

## Largest accepted log size in bytes (0 when not required)
var maxBytes: int = 0


## Create an evidence request from the JSON object.
## Null safe: null gives required = false and empty fields.
## @param data Evidence dictionary (may be null)
## @return New evidence request
static func fromDict(data: Variant) -> HorizonValidatedEvidenceRequest:
	var evidence := HorizonValidatedEvidenceRequest.new()
	if not (data is Dictionary):
		return evidence
	var requiredValue: Variant = data.get("required")
	var runIdValue: Variant = data.get("runId")
	var uploadBeforeValue: Variant = data.get("uploadBefore")
	var maxBytesValue: Variant = data.get("maxBytes")
	evidence.required = requiredValue if requiredValue is bool else false
	evidence.runId = runIdValue if runIdValue is String else ""
	evidence.uploadBefore = uploadBeforeValue if uploadBeforeValue is String else ""
	evidence.maxBytes = int(maxBytesValue) if (maxBytesValue is int or maxBytesValue is float) else 0
	return evidence


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"required": required,
		"runId": runId,
		"uploadBefore": uploadBefore,
		"maxBytes": maxBytes
	}
