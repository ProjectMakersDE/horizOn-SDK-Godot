## ============================================================
## horizOn SDK - Authentication Manager
## ============================================================
## Handles user authentication: signup, signin, email verification,
## password reset, name change, and session management.
## ============================================================
class_name HorizonAuth
extends RefCounted

## Signals
signal signup_completed(user: HorizonUserData)
signal signup_failed(error: String)
signal signin_completed(user: HorizonUserData)
signal signin_failed(error: String)
signal signout_completed()
signal auth_check_completed(is_valid: bool)
signal email_verified()
signal password_reset_requested()
signal password_reset_completed()
signal name_changed(new_name: String)

## Authentication types
enum AuthType {
	ANONYMOUS,
	EMAIL,
	GOOGLE
}

## Cache keys for persistent storage
const CACHE_KEY_USER_SESSION := "horizOn_UserSession"
const CACHE_KEY_ANONYMOUS_TOKEN := "horizOn_AnonymousToken"

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _currentUser: HorizonUserData


## Initialize the auth manager.
## @param http HTTP client instance
## @param logger Logger instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger) -> void:
	_http = http
	_logger = logger
	_currentUser = HorizonUserData.new()

	# Try to load cached session
	_loadCachedSession()
	_logger.info("Auth manager initialized")


## Get the current authenticated user.
## @return Current user data (may be empty if not signed in)
func getCurrentUser() -> HorizonUserData:
	return _currentUser


## Check if a user is currently signed in.
## @return True if user is signed in with valid session
func isSignedIn() -> bool:
	return _currentUser != null and _currentUser.isValid()


# ===== SIGN UP =====

## Sign up with anonymous authentication.
## Creates a new anonymous user or signs in if token exists.
## @param display_name Optional display name
## @param anonymous_token Optional existing anonymous token
## @return True if signup succeeded
func signUpAnonymous(display_name: String = "", anonymous_token: String = "") -> bool:
	if isSignedIn():
		_logger.warning("User is already signed in. Sign out first.")
		return false

	# Generate token if not provided
	if anonymous_token.is_empty():
		anonymous_token = _generateAnonymousToken()

	var request := {
		"type": "ANONYMOUS",
		"anonymousToken": anonymous_token
	}

	if not display_name.is_empty():
		request["username"] = display_name

	return await _signUp(request)


## Sign up with email and password.
## @param email User's email address
## @param password User's password (4-32 characters)
## @param username Optional display name
## @return True if signup succeeded
func signUpEmail(email: String, password: String, username: String = "") -> bool:
	if email.is_empty() or password.is_empty():
		_logger.error("Email and password are required")
		signup_failed.emit("Email and password are required")
		return false

	var request := {
		"type": "EMAIL",
		"email": email,
		"password": password
	}

	if not username.is_empty():
		request["username"] = username

	return await _signUp(request)


## Sign up with Google authentication.
## @param google_authorization_code Google OAuth authorization code
## @param google_redirect_uri The redirect URI used for OAuth (must match the one used to obtain the code)
## @param username Optional display name
## @return True if signup succeeded
func signUpGoogle(google_authorization_code: String, google_redirect_uri: String, username: String = "") -> bool:
	if google_authorization_code.is_empty():
		_logger.error("Google authorization code is required")
		signup_failed.emit("Google authorization code is required")
		return false

	if google_redirect_uri.is_empty():
		_logger.error("Google redirect URI is required")
		signup_failed.emit("Google redirect URI is required")
		return false

	var request := {
		"type": "GOOGLE",
		"googleAuthorizationCode": google_authorization_code,
		"googleRedirectUri": google_redirect_uri
	}

	if not username.is_empty():
		request["username"] = username

	return await _signUp(request)


## Internal signup implementation.
func _signUp(request: Dictionary) -> bool:
	var response := await _http.postAsync("/api/v1/app/user-management/signup", request)

	if response.isSuccess and response.data is Dictionary:
		var data: Dictionary = response.data
		if data.has("userId") and not data.get("userId", "").is_empty():
			_updateCurrentUser(data)
			_cacheSession()
			_logger.info("User signed up successfully: %s" % data.get("userId"))
			signup_completed.emit(_currentUser)
			return true

	var errorMsg := response.error
	if errorMsg.is_empty() and response.data is Dictionary:
		errorMsg = response.data.get("message", "Signup failed")

	if response.statusCode == 409:
		errorMsg = "User already exists. Try signing in instead."

	_logger.error("Signup failed: %s" % errorMsg)
	signup_failed.emit(errorMsg)
	return false


# ===== SIGN IN =====

## Sign in with email and password.
## @param email User's email address
## @param password User's password
## @return True if signin succeeded
func signInEmail(email: String, password: String) -> bool:
	if email.is_empty() or password.is_empty():
		_logger.error("Email and password are required")
		signin_failed.emit("Email and password are required")
		return false

	var request := {
		"type": "EMAIL",
		"email": email,
		"password": password
	}

	return await _signIn(request)


## Sign in with anonymous token.
## @param anonymous_token The anonymous token from previous session
## @return True if signin succeeded
func signInAnonymous(anonymous_token: String) -> bool:
	if anonymous_token.is_empty():
		_logger.error("Anonymous token is required for sign in")
		signin_failed.emit("Anonymous token is required")
		return false

	var request := {
		"type": "ANONYMOUS",
		"anonymousToken": anonymous_token
	}

	return await _signIn(request)


## Sign in with Google authentication.
## @param google_authorization_code Google OAuth authorization code
## @param google_redirect_uri The redirect URI used for OAuth (must match the one used to obtain the code)
## @return True if signin succeeded
func signInGoogle(google_authorization_code: String, google_redirect_uri: String) -> bool:
	if google_authorization_code.is_empty():
		_logger.error("Google authorization code is required")
		signin_failed.emit("Google authorization code is required")
		return false

	if google_redirect_uri.is_empty():
		_logger.error("Google redirect URI is required")
		signin_failed.emit("Google redirect URI is required")
		return false

	var request := {
		"type": "GOOGLE",
		"googleAuthorizationCode": google_authorization_code,
		"googleRedirectUri": google_redirect_uri
	}

	return await _signIn(request)


## Try to restore anonymous session from cached token.
## @return True if session was restored
func restoreAnonymousSession() -> bool:
	var cachedToken := getCachedAnonymousToken()

	if cachedToken.is_empty():
		_logger.warning("No cached anonymous token found")
		return false

	_logger.info("Attempting to restore anonymous session...")
	return await signInAnonymous(cachedToken)


## Internal signin implementation.
func _signIn(request: Dictionary) -> bool:
	var response := await _http.postAsync("/api/v1/app/user-management/signin", request)

	if response.isSuccess and response.data is Dictionary:
		var data: Dictionary = response.data
		var authStatus := data.get("authStatus", "")

		if authStatus == HorizonErrorCodes.AUTH_STATUS_AUTHENTICATED:
			_updateCurrentUser(data)
			_cacheSession()
			_logger.info("User signed in successfully: %s" % data.get("userId"))
			signin_completed.emit(_currentUser)
			return true

	var errorMsg := response.error
	if errorMsg.is_empty() and response.data is Dictionary:
		errorMsg = response.data.get("message", "Signin failed")

	_logger.error("Signin failed: %s" % errorMsg)
	signin_failed.emit(errorMsg)
	return false


# ===== CHECK AUTH =====

## Check if the current session token is still valid.
## @return True if session is valid
func checkAuth() -> bool:
	if not isSignedIn():
		_logger.warning("No user signed in")
		auth_check_completed.emit(false)
		return false

	var request := {
		"userId": _currentUser.userId,
		"sessionToken": _currentUser.accessToken
	}

	var response := await _http.postAsync("/api/v1/app/user-management/check-auth", request)

	if response.isSuccess and response.data is Dictionary:
		var isAuthenticated: bool = response.data.get("isAuthenticated", false)
		if isAuthenticated:
			_logger.info("Session token is valid")
			auth_check_completed.emit(true)
			return true

	_logger.warning("Session token is invalid or expired")
	signOut() # Clear invalid session
	auth_check_completed.emit(false)
	return false


# ===== EMAIL VERIFICATION =====

## Verify email with verification token.
## @param token Verification token from email
## @return True if verification succeeded
func verifyEmail(token: String) -> bool:
	if token.is_empty():
		_logger.error("Verification token is required")
		return false

	var request := {"token": token}
	var response := await _http.postAsync("/api/v1/app/user-management/verify-email", request)

	if response.isSuccess:
		if _currentUser != null:
			_currentUser.isEmailVerified = true
			_cacheSession()
		_logger.info("Email verified successfully")
		email_verified.emit()
		return true

	_logger.error("Email verification failed: %s" % response.error)
	return false


# ===== PASSWORD RESET =====

## Request a password reset email.
## @param email User's email address
## @return True if request succeeded (always returns true to prevent email enumeration)
func forgotPassword(email: String) -> bool:
	if email.is_empty():
		_logger.error("Email is required")
		return false

	var request := {"email": email}
	var response := await _http.postAsync("/api/v1/app/user-management/forgot-password", request)

	if response.isSuccess:
		_logger.info("Password reset email sent")
		password_reset_requested.emit()
		return true

	_logger.error("Password reset request failed: %s" % response.error)
	return false


## Reset password with reset token.
## @param token Reset token from email
## @param new_password New password (4-128 characters)
## @return True if reset succeeded
func resetPassword(token: String, new_password: String) -> bool:
	if token.is_empty() or new_password.is_empty():
		_logger.error("Token and new password are required")
		return false

	var request := {
		"token": token,
		"newPassword": new_password
	}

	var response := await _http.postAsync("/api/v1/app/user-management/reset-password", request)

	if response.isSuccess:
		_logger.info("Password reset successful")
		password_reset_completed.emit()
		return true

	_logger.error("Password reset failed: %s" % response.error)
	return false


# ===== CHANGE NAME =====

## Change the display name of the current user.
## @param new_name New display name (1-50 characters)
## @return True if name change succeeded
func changeName(new_name: String) -> bool:
	if not isSignedIn():
		_logger.error("User must be signed in to change name")
		return false

	if new_name.is_empty():
		_logger.error("New name is required")
		return false

	var request := {
		"userId": _currentUser.userId,
		"sessionToken": _currentUser.accessToken,
		"newName": new_name
	}

	var response := await _http.postAsync("/api/v1/app/user-management/change-name", request)

	if response.isSuccess and response.data is Dictionary:
		var isAuthenticated: bool = response.data.get("isAuthenticated", false)
		if isAuthenticated:
			_currentUser.displayName = new_name
			_cacheSession()
			_logger.info("Display name changed to: %s" % new_name)
			name_changed.emit(new_name)
			return true

	_logger.error("Name change failed: %s" % response.error)
	return false


# ===== SIGN OUT =====

## Sign out the current user.
## @param keep_anonymous_token If true, preserves anonymous token for future sign-in
func signOut(keep_anonymous_token: bool = true) -> void:
	# Save anonymous token before clearing if needed
	var anonymousTokenToKeep := ""
	if keep_anonymous_token and _currentUser != null and _currentUser.isAnonymous:
		if not _currentUser.anonymousToken.is_empty():
			anonymousTokenToKeep = _currentUser.anonymousToken
			_logger.info("Preserving anonymous token for future sign-in")

	_currentUser.clear()
	_clearCachedSession()

	_http.clearSessionToken()

	# Restore anonymous token to cache if keeping it
	if not anonymousTokenToKeep.is_empty():
		_saveAnonymousToken(anonymousTokenToKeep)

	_logger.info("User signed out")
	signout_completed.emit()


# ===== HELPER METHODS =====

## Update current user data from auth response.
func _updateCurrentUser(response: Dictionary) -> void:
	_currentUser.updateFromAuthResponse(response)

	# Set session token in HTTP client
	if not _currentUser.accessToken.is_empty():
		_http.setSessionToken(_currentUser.accessToken)

	# Save anonymous token for future sign-in
	if _currentUser.isAnonymous and not _currentUser.anonymousToken.is_empty():
		_saveAnonymousToken(_currentUser.anonymousToken)


## Generate a unique anonymous token.
## @return 32-character unique token
func _generateAnonymousToken() -> String:
	# Generate a GUID-like token without dashes (max 32 chars per API spec)
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(randi() % 256)
	return bytes.hex_encode()


## Cache the current session to persistent storage.
func _cacheSession() -> void:
	if _currentUser != null and _currentUser.isValid():
		var json := JSON.stringify(_currentUser.toDict())
		_saveToStorage(CACHE_KEY_USER_SESSION, json)


## Load cached session from persistent storage.
func _loadCachedSession() -> void:
	var json := _loadFromStorage(CACHE_KEY_USER_SESSION)
	if not json.is_empty():
		var parsed := JSON.parse_string(json)
		if parsed is Dictionary:
			_currentUser = HorizonUserData.fromDict(parsed)
			if _currentUser.isValid():
				_http.setSessionToken(_currentUser.accessToken)
				_logger.info("Cached session loaded")
				# Fire and forget auth check
				checkAuth()
			else:
				_logger.warning("Cached session is invalid")


## Clear cached session from persistent storage.
func _clearCachedSession() -> void:
	_deleteFromStorage(CACHE_KEY_USER_SESSION)


## Save anonymous token for future sign-in.
func _saveAnonymousToken(token: String) -> void:
	if not token.is_empty():
		_saveToStorage(CACHE_KEY_ANONYMOUS_TOKEN, token)
		_logger.debug("Anonymous token saved")


## Get cached anonymous token.
## @return The cached token, or empty string if not found
func getCachedAnonymousToken() -> String:
	var token := _loadFromStorage(CACHE_KEY_ANONYMOUS_TOKEN)
	# Validate token length (API requires max 32 chars)
	if not token.is_empty() and token.length() <= 32:
		return token

	if not token.is_empty():
		_logger.warning("Cached anonymous token has invalid format. Clearing cache.")
		clearAnonymousToken()

	return ""


## Clear cached anonymous token.
func clearAnonymousToken() -> void:
	_deleteFromStorage(CACHE_KEY_ANONYMOUS_TOKEN)
	_logger.info("Anonymous token cleared from cache")


## Check if there is a cached anonymous token.
## @return True if anonymous token is cached
func hasCachedAnonymousToken() -> bool:
	return not getCachedAnonymousToken().is_empty()


# ===== STORAGE HELPERS =====

## Save data to persistent storage using a config file.
func _saveToStorage(key: String, value: String) -> void:
	var config := ConfigFile.new()
	var path := "user://horizon_cache.cfg"
	config.load(path) # Load existing data if any
	config.set_value("cache", key, value)
	config.save(path)


## Load data from persistent storage.
func _loadFromStorage(key: String) -> String:
	var config := ConfigFile.new()
	var path := "user://horizon_cache.cfg"
	if config.load(path) == OK:
		return config.get_value("cache", key, "")
	return ""


## Delete data from persistent storage.
func _deleteFromStorage(key: String) -> void:
	var config := ConfigFile.new()
	var path := "user://horizon_cache.cfg"
	if config.load(path) == OK:
		if config.has_section_key("cache", key):
			config.erase_section_key("cache", key)
			config.save(path)
