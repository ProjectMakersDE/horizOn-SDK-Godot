## ============================================================
## horizOn SDK - User Data Model
## ============================================================
## Data class representing the currently authenticated user.
## Stores user ID, credentials, tokens, and profile information.
## ============================================================
class_name HorizonUserData
extends RefCounted

## User's unique identifier (UUID)
var userId: String = ""

## User's email address (empty for anonymous users)
var email: String = ""

## User's display name
var displayName: String = ""

## Authentication type: "ANONYMOUS", "EMAIL", or "GOOGLE"
var authType: String = ""

## Session access token for authenticated requests
var accessToken: String = ""

## Anonymous token for anonymous user sign-in
var anonymousToken: String = ""

## Whether the user's email has been verified
var isEmailVerified: bool = false

## Whether this is an anonymous account
var isAnonymous: bool = false

## Google ID for Google-authenticated users
var googleId: String = ""

## Timestamp of last successful login
var lastLoginTime: String = ""

## Message from the server (if any)
var message: String = ""


## Check if the user data is valid (has required fields).
## @return True if user data is valid for authenticated state
func isValid() -> bool:
	return not userId.is_empty()


## Clear all user data (for sign out).
func clear() -> void:
	userId = ""
	email = ""
	displayName = ""
	authType = ""
	accessToken = ""
	anonymousToken = ""
	isEmailVerified = false
	isAnonymous = false
	googleId = ""
	lastLoginTime = ""
	message = ""


## Convert user data to a dictionary for serialization.
## @return Dictionary representation of user data
func toDict() -> Dictionary:
	return {
		"userId": userId,
		"email": email,
		"displayName": displayName,
		"authType": authType,
		"accessToken": accessToken,
		"anonymousToken": anonymousToken,
		"isEmailVerified": isEmailVerified,
		"isAnonymous": isAnonymous,
		"googleId": googleId,
		"lastLoginTime": lastLoginTime,
		"message": message
	}


## Load user data from a dictionary.
## Safely handles null values from server responses.
## @param data Dictionary containing user data
static func fromDict(data: Dictionary) -> HorizonUserData:
	var user := HorizonUserData.new()

	# Helper to safely get string (returns fallback if null or wrong type)
	var safeStr = func(key: String, fallback: String = "") -> String:
		var val = data.get(key)
		return val if val is String else fallback

	# Helper to safely get bool
	var safeBool = func(key: String, fallback: bool = false) -> bool:
		var val = data.get(key)
		return val if val is bool else fallback

	user.userId = safeStr.call("userId", "")
	user.email = safeStr.call("email", "")
	user.displayName = safeStr.call("displayName", safeStr.call("username", ""))
	user.authType = safeStr.call("authType", "")
	user.accessToken = safeStr.call("accessToken", "")
	user.anonymousToken = safeStr.call("anonymousToken", "")
	user.isEmailVerified = safeBool.call("isEmailVerified", safeBool.call("isVerified", false))
	user.isAnonymous = safeBool.call("isAnonymous", false)
	user.googleId = safeStr.call("googleId", "")
	user.lastLoginTime = safeStr.call("lastLoginTime", "")
	user.message = safeStr.call("message", "")
	return user


## Update user data from a sign-up or sign-in response.
## Only updates fields that are present and not null in the response.
## @param response Dictionary containing the auth response
func updateFromAuthResponse(response: Dictionary) -> void:
	# Helper to safely get string values (ignore null)
	var safeStr = func(key: String, fallback: String) -> String:
		var val = response.get(key)
		return val if val is String else fallback

	# Helper to safely get bool values (ignore null)
	var safeBool = func(key: String, fallback: bool) -> bool:
		var val = response.get(key)
		return val if val is bool else fallback

	userId = safeStr.call("userId", userId)
	email = safeStr.call("email", email)
	displayName = safeStr.call("username", displayName)
	accessToken = safeStr.call("accessToken", accessToken)
	anonymousToken = safeStr.call("anonymousToken", anonymousToken)
	isEmailVerified = safeBool.call("isVerified", isEmailVerified)
	isAnonymous = safeBool.call("isAnonymous", isAnonymous)
	googleId = safeStr.call("googleId", googleId)
	message = safeStr.call("message", message)
	lastLoginTime = Time.get_datetime_string_from_system(true, true)

	# Determine auth type
	if isAnonymous:
		authType = "ANONYMOUS"
	elif not googleId.is_empty():
		authType = "GOOGLE"
	elif not email.is_empty():
		authType = "EMAIL"
