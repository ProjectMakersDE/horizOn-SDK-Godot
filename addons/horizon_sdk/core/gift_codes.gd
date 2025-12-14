## ============================================================
## horizOn SDK - Gift Code Manager
## ============================================================
## Handles gift code validation and redemption.
## Gift codes can contain in-game rewards like currency or items.
## ============================================================
class_name HorizonGiftCodes
extends RefCounted

## Signals
signal code_validated(code: String, is_valid: bool)
signal code_redeemed(code: String, gift_data: String)
signal code_redeem_failed(code: String, error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth


## Initialize the gift code manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("Gift code manager initialized")


## Validate a gift code without redeeming it.
## @param code The gift code to validate
## @return True if code is valid and can be redeemed, false otherwise, null on error
func validate(code: String) -> Variant:
	if code.is_empty():
		_logger.error("Gift code is required")
		return null

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to validate gift code")
		return null

	var user := _auth.getCurrentUser()

	var request := {
		"code": code,
		"userId": user.userId
	}

	var response := await _http.postAsync("/api/v1/app/gift-codes/validate", request)

	if response.isSuccess and response.data is Dictionary:
		var isValid: bool = response.data.get("valid", false)
		_logger.info("Gift code %s validation: %s" % [code, "valid" if isValid else "invalid"])
		code_validated.emit(code, isValid)
		return isValid

	_logger.error("Gift code validation failed: %s" % response.error)
	return null


## Redeem a gift code to receive rewards.
## @param code The gift code to redeem
## @return RedeemResult dictionary with success, message, and giftData, or null on error
func redeem(code: String) -> Dictionary:
	if code.is_empty():
		_logger.error("Gift code is required")
		code_redeem_failed.emit(code, "Gift code is required")
		return {}

	if not _auth.isSignedIn():
		_logger.error("User must be signed in to redeem gift code")
		code_redeem_failed.emit(code, "User must be signed in")
		return {}

	var user := _auth.getCurrentUser()

	var request := {
		"code": code,
		"userId": user.userId
	}

	var response := await _http.postAsync("/api/v1/app/gift-codes/redeem", request)

	if response.isSuccess and response.data is Dictionary:
		var success: bool = response.data.get("success", false)
		var message: String = response.data.get("message", "")
		var giftData: String = response.data.get("giftData", "")

		if success:
			_logger.info("Gift code %s redeemed successfully" % code)
			code_redeemed.emit(code, giftData)
		else:
			_logger.warning("Gift code %s redemption failed: %s" % [code, message])
			code_redeem_failed.emit(code, message)

		return {
			"success": success,
			"message": message,
			"giftData": giftData
		}

	_logger.error("Gift code redemption error: %s" % response.error)
	code_redeem_failed.emit(code, response.error)
	return {
		"success": false,
		"message": response.error,
		"giftData": ""
	}


## Redeem a gift code and parse the gift data as JSON.
## @param code The gift code to redeem
## @return Dictionary with success bool and parsed rewards, or null on error
func redeemParsed(code: String) -> Dictionary:
	var result := await redeem(code)
	if result.is_empty():
		return {}

	var parsed := {}
	parsed["success"] = result.get("success", false)
	parsed["message"] = result.get("message", "")

	var giftData: String = result.get("giftData", "")
	if not giftData.is_empty():
		var parsedGift := JSON.parse_string(giftData)
		if parsedGift is Dictionary:
			parsed["rewards"] = parsedGift
		else:
			parsed["rewards"] = {}
			parsed["rawGiftData"] = giftData
	else:
		parsed["rewards"] = {}

	return parsed
