## ============================================================
## horizOn SDK - Hello horizOn
## ============================================================
## The small front door to the horizOn SDK. This is NOT the big
## test UI, it is the shortest path to a first API response:
##   connect to server -> anonymous sign-in -> submit a score ->
##   show the result.
##
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: run hello_horizon.tscn.
## Expected output: each step prints to the Output panel and shows
## on the on-screen Label. The final line is the player's rank
## after the score submission, or a clear error message.
## ============================================================
extends Control

## On-screen status label, assigned in hello_horizon.tscn.
@onready var _status: Label = %StatusLabel

## Score submitted by this example run.
const DEMO_SCORE := 1000


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		_fail("Horizon autoload not found. Enable the horizOn SDK plugin in Project Settings.")
		return

	if not horizon.isInitialized():
		_fail("Config not imported. Use Project > Tools > horizOn: Import Config.")
		return

	# Step 1: connect to the fastest available horizOn server.
	_report("Connecting to horizOn...")
	var connected: bool = await horizon.connect_to_server()
	if not connected:
		_fail("Could not connect to any horizOn server. Check your config.")
		return

	# Step 2: anonymous sign-in. Restores a cached session if one exists,
	# otherwise creates a fresh anonymous user.
	_report("Connected. Signing in anonymously...")
	var signed_in: bool = await horizon.quickSignInAnonymous("HelloPlayer")
	if not signed_in:
		_fail("Anonymous sign-in failed.")
		return

	var user: HorizonUserData = horizon.getCurrentUser()
	_report("Signed in as %s. Submitting score..." % user.displayName)

	# Step 3: submit a leaderboard score.
	var submitted: bool = await horizon.leaderboard.submitScore(DEMO_SCORE)
	if not submitted:
		_fail("Score submission failed.")
		return

	# Step 4: read the result back and display it.
	var rank: HorizonLeaderboardEntry = await horizon.leaderboard.getRank()
	if rank != null:
		_report("Hello horizOn complete. Score %d submitted, your rank is #%d." % [DEMO_SCORE, rank.position])
	else:
		_report("Hello horizOn complete. Score %d submitted." % DEMO_SCORE)


## Print a progress line and mirror it to the on-screen label.
func _report(message: String) -> void:
	print("[Hello horizOn] %s" % message)
	if _status != null:
		_status.text = message


## Print an error line and mirror it to the on-screen label.
func _fail(message: String) -> void:
	push_error("[Hello horizOn] %s" % message)
	if _status != null:
		_status.text = "Error: %s" % message
