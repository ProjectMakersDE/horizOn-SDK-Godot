## ============================================================
## horizOn SDK - Email Sending Minimal Example
## ============================================================
## What it does: signs in anonymously, sends a transactional email
## to the current user from a Dashboard template, then checks the
## delivery status of that email.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Replace "welcome" with a template slug that exists in your
## Dashboard before running.
## Expected output: a "Queued" line with an email ID and a status
## line, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.email_sending.email_send_failed.connect(func(error: String):
		push_error("Email send failed: %s" % error))
	horizon.email_sending.email_status_failed.connect(func(email_id: String, error: String):
		push_error("Email status check failed for %s: %s" % [email_id, error]))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required to resolve the recipient user ID.")
		return

	var user_id: String = horizon.getCurrentUser().userId

	# send_email(user_id, template_slug, variables, language, scheduled_at="").
	# Returns a Dictionary with id, status, scheduledAt, or {} on failure.
	var result: Dictionary = await horizon.email_sending.send_email(
		user_id, "welcome", {"playerName": "Player1"}, "en")
	if result.is_empty():
		push_error("Email was not queued.")
		return

	var email_id: String = result.get("id", "")
	print("Queued email %s with status %s" % [email_id, result.get("status", "")])

	# get_email_status returns the current delivery status, or {} on failure.
	var status: Dictionary = await horizon.email_sending.get_email_status(email_id)
	if not status.is_empty():
		print("Current status: %s" % status.get("status", "unknown"))
