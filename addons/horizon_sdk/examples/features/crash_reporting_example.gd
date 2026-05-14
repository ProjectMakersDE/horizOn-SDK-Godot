## ============================================================
## horizOn SDK - Crash Reporting Minimal Example
## ============================================================
## What it does: connects, registers a crash session, drops a few
## breadcrumbs, sets a custom key, then records a non-fatal
## exception with a sample stack trace.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Session registered" line and a "Reported"
## line with a fingerprint, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.crashes.crash_report_failed.connect(func(error: String):
		push_error("Crash report failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	# Anonymous sign-in is optional for crash reporting, but it lets the
	# report be attributed to a user instead of "anonymous".
	await horizon.quickSignInAnonymous("Player1")

	var registered: bool = await horizon.crashes.register_session()
	if registered:
		print("Crash session registered.")

	# Breadcrumbs and custom keys give the report context.
	horizon.crashes.record_breadcrumb(HorizonCrashes.BREADCRUMB_NAVIGATION, "Entered main menu")
	horizon.crashes.record_breadcrumb(HorizonCrashes.BREADCRUMB_USER_ACTION, "Tapped Start")
	horizon.crashes.set_custom_key("build_channel", "example")

	# record_exception submits a non-fatal report and returns whether it was accepted.
	var sample_stack := "at MainMenu.start() main_menu.gd:42\nat Button._pressed() main_menu.gd:18"
	var reported: bool = await horizon.crashes.record_exception(
		"Example non-fatal exception", sample_stack, {"retry_count": 2})
	if reported:
		print("Reported non-fatal exception to horizOn.")
	else:
		print("Report was not accepted (it may have been rate limited).")
