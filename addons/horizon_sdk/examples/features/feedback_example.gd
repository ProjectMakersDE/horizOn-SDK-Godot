## ============================================================
## horizOn SDK - Feedback Minimal Example
## ============================================================
## What it does: signs in anonymously, submits a general feedback
## message, then submits a bug report via the convenience method.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Feedback submitted" line per submission, or
## a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.feedback.feedback_submit_failed.connect(func(error: String):
		push_error("Feedback submission failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before submitting feedback.")
		return

	# submit(title, message, category, email, include_device_info).
	var submitted: bool = await horizon.feedback.submit(
		"Great game", "Loving the new leaderboard feature.", "GENERAL", "", true)
	if submitted:
		print("Feedback submitted.")

	# submitBugReport is a convenience wrapper that tags the category as BUG.
	var bug_submitted: bool = await horizon.feedback.submitBugReport(
		"Score not updating", "My score stayed the same after a higher run.")
	if bug_submitted:
		print("Bug report submitted.")
