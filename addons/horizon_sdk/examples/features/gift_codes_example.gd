## ============================================================
## horizOn SDK - Gift Codes Minimal Example
## ============================================================
## What it does: signs in anonymously, validates a gift code, then
## redeems it and parses the reward data.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Replace "WELCOME2026" with a real code from your Dashboard
## before running.
## Expected output: a validity line and a redemption result with
## parsed rewards, or a clear error line on failure.
## ============================================================
extends Node

const GIFT_CODE := "WELCOME2026"


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.giftCodes.code_redeem_failed.connect(func(code: String, error: String):
		push_error("Gift code %s redemption failed: %s" % [code, error]))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	var signed_in: bool = await horizon.quickSignInAnonymous("Player1")
	if not signed_in:
		push_error("Sign-in required before using gift codes.")
		return

	# validate returns true/false, or null on error.
	var is_valid: Variant = await horizon.giftCodes.validate(GIFT_CODE)
	if is_valid == null:
		push_error("Could not validate the gift code.")
		return
	print("Gift code %s valid: %s" % [GIFT_CODE, is_valid])
	if not is_valid:
		print("Code is not valid, skipping redemption.")
		return

	# redeemParsed redeems the code and parses giftData as a rewards Dictionary.
	var result: Dictionary = await horizon.giftCodes.redeemParsed(GIFT_CODE)
	if result.is_empty():
		push_error("Redemption returned no result.")
		return

	if result.get("success", false):
		print("Redeemed. Rewards: %s" % JSON.stringify(result.get("rewards", {})))
	else:
		print("Redemption rejected: %s" % result.get("message", ""))
