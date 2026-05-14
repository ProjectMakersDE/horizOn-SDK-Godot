## ============================================================
## horizOn SDK - Auth Minimal Example
## ============================================================
## What it does: connects to horizOn, then creates (or restores)
## an anonymous account and prints the resulting user.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a "Signed in" line with a user ID, or a clear
## error line if connection or sign-in failed.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals: surface failures even when the
	# return value is already false.
	horizon.auth.signup_failed.connect(func(error: String):
		push_error("Anonymous sign-up failed: %s" % error))
	horizon.auth.signin_failed.connect(func(error: String):
		push_error("Anonymous sign-in failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server. Check your config.")
		return

	# quickSignInAnonymous restores a cached anonymous session if one
	# exists, otherwise it creates a fresh anonymous user.
	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Anonymous sign-in did not complete.")
		return

	var user: HorizonUserData = horizon.getCurrentUser()
	print("Signed in. User ID: %s, display name: %s" % [user.userId, user.displayName])

	# Optional: change the display name, then verify the session is still valid.
	var renamed: bool = await horizon.auth.changeName("Player1Renamed")
	if renamed:
		print("Display name updated to: %s" % horizon.getCurrentUser().displayName)

	var still_valid: bool = await horizon.auth.checkAuth()
	print("Session valid: %s" % still_valid)
