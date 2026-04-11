## ============================================================
## horizOn SDK - Email Sending Manager
## ============================================================
## Handles sending transactional emails to users via
## pre-defined templates. Supports immediate and scheduled delivery.
## ============================================================
class_name HorizonEmailSending
extends RefCounted

## Signals
signal email_sent(response: Dictionary)
signal email_send_failed(error: String)
signal email_cancelled(email_id: String)
signal email_cancel_failed(email_id: String, error: String)
signal email_status_received(response: Dictionary)
signal email_status_failed(email_id: String, error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth


## Initialize the email sending manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("Email sending manager initialized")


## Send an email to a registered user using a pre-defined template.
## @param user_id The horizOn user ID of the recipient
## @param template_slug Template slug defined in Dashboard
## @param variables Variable values for the template (empty dict if none)
## @param language Language code (e.g., "en", "de")
## @param scheduled_at Optional ISO 8601 timestamp for scheduled delivery
## @return Dictionary with id, status, scheduledAt — or empty dict on failure
func send_email(user_id: String, template_slug: String, variables: Dictionary, language: String, scheduled_at: String = "") -> Dictionary:
	if user_id.is_empty():
		_logger.error("User ID is required")
		email_send_failed.emit("User ID is required")
		return {}

	if template_slug.is_empty():
		_logger.error("Template slug is required")
		email_send_failed.emit("Template slug is required")
		return {}

	if language.is_empty():
		_logger.error("Language is required")
		email_send_failed.emit("Language is required")
		return {}

	var request := {
		"userId": user_id,
		"templateSlug": template_slug,
		"variables": variables,
		"language": language
	}

	if not scheduled_at.is_empty():
		request["scheduledAt"] = scheduled_at

	var response := await _http.postAsync("/api/v1/app/email-sending/send", request)

	if response.isSuccess and response.data is Dictionary:
		_logger.info("Email queued: %s" % response.data.get("id", ""))
		email_sent.emit(response.data)
		return response.data

	_logger.error("Email send failed: %s" % response.error)
	email_send_failed.emit(response.error)
	return {}


## Cancel a pending or scheduled email before it is sent.
## @param email_id The email ID returned by send_email
## @return Dictionary with message — or empty dict on failure
func cancel_email(email_id: String) -> Dictionary:
	if email_id.is_empty():
		_logger.error("Email ID is required")
		email_cancel_failed.emit(email_id, "Email ID is required")
		return {}

	var response := await _http.deleteAsync("/api/v1/app/email-sending/%s" % email_id)

	if response.isSuccess and response.data is Dictionary:
		_logger.info("Email cancelled: %s" % email_id)
		email_cancelled.emit(email_id)
		return response.data

	_logger.error("Email cancel failed: %s" % response.error)
	email_cancel_failed.emit(email_id, response.error)
	return {}


## Get the current status of a specific email.
## @param email_id The email ID returned by send_email
## @return Dictionary with full status details — or empty dict on failure
func get_email_status(email_id: String) -> Dictionary:
	if email_id.is_empty():
		_logger.error("Email ID is required")
		email_status_failed.emit(email_id, "Email ID is required")
		return {}

	var response := await _http.getAsync("/api/v1/app/email-sending/%s" % email_id)

	if response.isSuccess and response.data is Dictionary:
		_logger.info("Email status: %s = %s" % [email_id, response.data.get("status", "")])
		email_status_received.emit(response.data)
		return response.data

	_logger.error("Email status failed: %s" % response.error)
	email_status_failed.emit(email_id, response.error)
	return {}
