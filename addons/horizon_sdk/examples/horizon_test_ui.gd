## ============================================================
## horizOn SDK - Test UI Controller
## ============================================================
## Complete example UI for testing all horizOn SDK endpoints.
## Demonstrates how to use every SDK feature.
##
## Setup:
##   1. Import config JSON via Project > Tools > horizOn: Import Config
##   2. Run this scene to test all SDK features
## ============================================================
extends Control

# ===== UI REFERENCES =====

# Connection Panel
@onready var _lblConfigStatus: Label = %LblConfigStatus
@onready var _btnConnect: Button = %BtnConnect
@onready var _btnDisconnect: Button = %BtnDisconnect
@onready var _lblConnectionStatus: Label = %LblConnectionStatus

# Authentication Panel
@onready var _txtEmail: LineEdit = %TxtEmail
@onready var _txtPassword: LineEdit = %TxtPassword
@onready var _txtDisplayName: LineEdit = %TxtDisplayName
@onready var _txtAnonymousToken: LineEdit = %TxtAnonymousToken
@onready var _btnSignUpEmail: Button = %BtnSignUpEmail
@onready var _btnSignInEmail: Button = %BtnSignInEmail
@onready var _btnSignInAnonymous: Button = %BtnSignInAnonymous
@onready var _btnSignOut: Button = %BtnSignOut
@onready var _btnCheckAuth: Button = %BtnCheckAuth
@onready var _btnChangeName: Button = %BtnChangeName
@onready var _lblAuthStatus: Label = %LblAuthStatus
@onready var _txtAuthResponse: TextEdit = %TxtAuthResponse

# Google Auth Panel
@onready var _txtGoogleAuthCode: LineEdit = %TxtGoogleAuthCode
@onready var _txtGoogleRedirectUri: LineEdit = %TxtGoogleRedirectUri
@onready var _btnGoogleSignUp: Button = %BtnGoogleSignUp
@onready var _btnGoogleSignIn: Button = %BtnGoogleSignIn
@onready var _txtGoogleAuthResponse: TextEdit = %TxtGoogleAuthResponse

# Password Reset Panel
@onready var _txtForgotEmail: LineEdit = %TxtForgotEmail
@onready var _btnForgotPassword: Button = %BtnForgotPassword
@onready var _txtResetToken: LineEdit = %TxtResetToken
@onready var _txtNewPassword: LineEdit = %TxtNewPassword
@onready var _btnResetPassword: Button = %BtnResetPassword

# Email Verification Panel
@onready var _txtVerifyToken: LineEdit = %TxtVerifyToken
@onready var _btnVerifyEmail: Button = %BtnVerifyEmail

# Remote Config Panel
@onready var _txtConfigKey: LineEdit = %TxtConfigKey
@onready var _btnConfigGet: Button = %BtnConfigGet
@onready var _btnConfigAll: Button = %BtnConfigAll
@onready var _btnConfigClear: Button = %BtnConfigClear
@onready var _txtConfigResponse: TextEdit = %TxtConfigResponse

# News Panel
@onready var _txtNewsLimit: LineEdit = %TxtNewsLimit
@onready var _txtNewsLanguage: LineEdit = %TxtNewsLanguage
@onready var _btnNewsLoad: Button = %BtnNewsLoad
@onready var _btnNewsClear: Button = %BtnNewsClear
@onready var _txtNewsResponse: TextEdit = %TxtNewsResponse

# Leaderboard Panel
@onready var _txtScore: LineEdit = %TxtScore
@onready var _btnLeaderboardSubmit: Button = %BtnLeaderboardSubmit
@onready var _btnLeaderboardTop: Button = %BtnLeaderboardTop
@onready var _btnLeaderboardRank: Button = %BtnLeaderboardRank
@onready var _btnLeaderboardAround: Button = %BtnLeaderboardAround
@onready var _txtLeaderboardResponse: TextEdit = %TxtLeaderboardResponse

# Cloud Save Panel
@onready var _optSaveContentType: OptionButton = %OptSaveContentType
@onready var _txtSaveData: TextEdit = %TxtSaveData
@onready var _btnSaveSave: Button = %BtnSaveSave
@onready var _btnSaveLoad: Button = %BtnSaveLoad
@onready var _txtSaveResponse: TextEdit = %TxtSaveResponse

# Gift Code Panel
@onready var _txtGiftCode: LineEdit = %TxtGiftCode
@onready var _btnGiftCodeValidate: Button = %BtnGiftCodeValidate
@onready var _btnGiftCodeRedeem: Button = %BtnGiftCodeRedeem
@onready var _txtGiftCodeResponse: TextEdit = %TxtGiftCodeResponse

# Feedback Panel
@onready var _txtFeedbackTitle: LineEdit = %TxtFeedbackTitle
@onready var _optFeedbackCategory: OptionButton = %OptFeedbackCategory
@onready var _txtFeedbackMessage: TextEdit = %TxtFeedbackMessage
@onready var _txtFeedbackEmail: LineEdit = %TxtFeedbackEmail
@onready var _btnFeedbackSubmit: Button = %BtnFeedbackSubmit
@onready var _txtFeedbackResponse: TextEdit = %TxtFeedbackResponse

# User Log Panel
@onready var _txtUserLogMessage: LineEdit = %TxtUserLogMessage
@onready var _optUserLogType: OptionButton = %OptUserLogType
@onready var _txtUserLogErrorCode: LineEdit = %TxtUserLogErrorCode
@onready var _btnUserLogCreate: Button = %BtnUserLogCreate
@onready var _txtUserLogResponse: TextEdit = %TxtUserLogResponse

# Reference to the Horizon singleton
var _horizon: Node


func _ready() -> void:
	# Get reference to the Horizon autoload
	_horizon = get_node_or_null("/root/Horizon")
	if _horizon == null:
		push_error("Horizon autoload not found! Make sure the plugin is enabled.")
		return

	_connectSignals()
	_initializeDropdowns()
	_loadCachedAnonymousToken()
	_updateConfigStatus()
	_updateUIState()

	# Connect to Horizon signals
	_horizon.sdk_initialized.connect(_onSdkInitialized)
	_horizon.sdk_connected.connect(_onSdkConnected)
	_horizon.sdk_connection_failed.connect(_onSdkConnectionFailed)
	_horizon.sdk_disconnected.connect(_onSdkDisconnected)

	_horizon.auth.signin_completed.connect(_onSignInCompleted)
	_horizon.auth.signin_failed.connect(_onSignInFailed)
	_horizon.auth.signup_completed.connect(_onSignUpCompleted)
	_horizon.auth.signup_failed.connect(_onSignUpFailed)
	_horizon.auth.signout_completed.connect(_onSignOutCompleted)


func _connectSignals() -> void:
	# Connection
	_btnConnect.pressed.connect(_onConnectClicked)
	_btnDisconnect.pressed.connect(_onDisconnectClicked)

	# Authentication
	_btnSignUpEmail.pressed.connect(_onSignUpEmailClicked)
	_btnSignInEmail.pressed.connect(_onSignInEmailClicked)
	_btnSignInAnonymous.pressed.connect(_onSignInAnonymousClicked)
	_btnSignOut.pressed.connect(_onSignOutClicked)
	_btnCheckAuth.pressed.connect(_onCheckAuthClicked)
	_btnChangeName.pressed.connect(_onChangeNameClicked)

	# Google Auth
	_btnGoogleSignUp.pressed.connect(_onGoogleSignUpClicked)
	_btnGoogleSignIn.pressed.connect(_onGoogleSignInClicked)

	# Password Reset
	_btnForgotPassword.pressed.connect(_onForgotPasswordClicked)
	_btnResetPassword.pressed.connect(_onResetPasswordClicked)

	# Email Verification
	_btnVerifyEmail.pressed.connect(_onVerifyEmailClicked)

	# Remote Config
	_btnConfigGet.pressed.connect(_onConfigGetClicked)
	_btnConfigAll.pressed.connect(_onConfigAllClicked)
	_btnConfigClear.pressed.connect(_onConfigClearClicked)

	# News
	_btnNewsLoad.pressed.connect(_onNewsLoadClicked)
	_btnNewsClear.pressed.connect(_onNewsClearClicked)

	# Leaderboard
	_btnLeaderboardSubmit.pressed.connect(_onLeaderboardSubmitClicked)
	_btnLeaderboardTop.pressed.connect(_onLeaderboardTopClicked)
	_btnLeaderboardRank.pressed.connect(_onLeaderboardRankClicked)
	_btnLeaderboardAround.pressed.connect(_onLeaderboardAroundClicked)

	# Cloud Save
	_btnSaveSave.pressed.connect(_onSaveSaveClicked)
	_btnSaveLoad.pressed.connect(_onSaveLoadClicked)

	# Gift Code
	_btnGiftCodeValidate.pressed.connect(_onGiftCodeValidateClicked)
	_btnGiftCodeRedeem.pressed.connect(_onGiftCodeRedeemClicked)

	# Feedback
	_btnFeedbackSubmit.pressed.connect(_onFeedbackSubmitClicked)

	# User Log
	_btnUserLogCreate.pressed.connect(_onUserLogCreateClicked)


func _initializeDropdowns() -> void:
	# Feedback categories
	_optFeedbackCategory.add_item("GENERAL", 0)
	_optFeedbackCategory.add_item("BUG", 1)
	_optFeedbackCategory.add_item("FEATURE", 2)

	# User log types
	_optUserLogType.add_item("INFO", 0)
	_optUserLogType.add_item("WARN", 1)
	_optUserLogType.add_item("ERROR", 2)

	# Cloud save content type
	_optSaveContentType.add_item("JSON (application/json)", 0)
	_optSaveContentType.add_item("Binary (application/octet-stream)", 1)


func _loadCachedAnonymousToken() -> void:
	if _horizon == null:
		return
	var cachedToken: String = _horizon.auth.getCachedAnonymousToken()
	if not cachedToken.is_empty():
		_txtAnonymousToken.text = cachedToken


func _updateConfigStatus() -> void:
	if _horizon == null:
		_lblConfigStatus.text = "Config: Error - SDK not loaded"
		return

	if _horizon.isInitialized():
		var config = _horizon.getConfig()
		if config != null:
			_lblConfigStatus.text = "Config: %d hosts loaded" % config.hosts.size()
		else:
			_lblConfigStatus.text = "Config: Loaded (no details)"
	else:
		_lblConfigStatus.text = "Config: NOT FOUND - Use Project > Tools > horizOn: Import Config"


func _updateUIState() -> void:
	if _horizon == null:
		return

	var isInitialized: bool = _horizon.isInitialized()
	var isConnected: bool = _horizon.isConnected()
	var isSignedIn: bool = _horizon.isSignedIn()

	# Connection status
	if isConnected:
		_lblConnectionStatus.text = "Status: Connected to %s" % _horizon.getActiveHost()
	elif isInitialized:
		_lblConnectionStatus.text = "Status: Disconnected (Ready to connect)"
	else:
		_lblConnectionStatus.text = "Status: Not configured"

	# Auth status
	if isSignedIn:
		var user = _horizon.getCurrentUser()
		var userInfo: String = user.email if not user.email.is_empty() else user.userId
		_lblAuthStatus.text = "Signed in as: %s (%s)" % [user.displayName, userInfo]
	else:
		_lblAuthStatus.text = "Not Signed In"

	# Enable/disable buttons
	_btnConnect.disabled = not isInitialized or isConnected
	_btnDisconnect.disabled = not isConnected

	_btnSignUpEmail.disabled = not isConnected or isSignedIn
	_btnSignInEmail.disabled = not isConnected or isSignedIn
	_btnSignInAnonymous.disabled = not isConnected or isSignedIn

	_btnSignOut.disabled = not isSignedIn
	_btnCheckAuth.disabled = not isSignedIn
	_btnChangeName.disabled = not isSignedIn
	_btnGoogleSignUp.disabled = not isConnected or isSignedIn
	_btnGoogleSignIn.disabled = not isConnected or isSignedIn

	var requiresAuth: bool = isConnected and isSignedIn
	_btnLeaderboardSubmit.disabled = not requiresAuth
	_btnLeaderboardRank.disabled = not requiresAuth
	_btnLeaderboardAround.disabled = not requiresAuth
	_btnSaveSave.disabled = not requiresAuth
	_btnSaveLoad.disabled = not requiresAuth
	_btnGiftCodeValidate.disabled = not requiresAuth
	_btnGiftCodeRedeem.disabled = not requiresAuth
	_btnFeedbackSubmit.disabled = not requiresAuth
	_btnUserLogCreate.disabled = not requiresAuth


# ===== SDK SIGNAL HANDLERS =====

func _onSdkInitialized() -> void:
	_updateConfigStatus()
	_updateUIState()


func _onSdkConnected(_host: String) -> void:
	_updateUIState()


func _onSdkConnectionFailed(error: String) -> void:
	_lblConnectionStatus.text = "Status: Connection Failed - %s" % error
	_updateUIState()


func _onSdkDisconnected() -> void:
	_updateUIState()


func _onSignInCompleted(user: HorizonUserData) -> void:
	_txtDisplayName.text = user.displayName
	_txtAuthResponse.text = "Success!\nUser ID: %s\nEmail: %s\nDisplay Name: %s\nAuth Type: %s\nAccess Token: %s" % [
		user.userId, user.email, user.displayName, user.authType, user.accessToken
	]
	if not user.anonymousToken.is_empty():
		_txtAnonymousToken.text = user.anonymousToken
	_updateUIState()


func _onSignInFailed(error: String) -> void:
	_txtAuthResponse.text = "Sign in failed: %s" % error
	_updateUIState()


func _onSignUpCompleted(user: HorizonUserData) -> void:
	_txtDisplayName.text = user.displayName
	_txtAuthResponse.text = "Sign up success!\nUser ID: %s\nEmail: %s\nDisplay Name: %s\nAuth Type: %s\nAccess Token: %s" % [
		user.userId, user.email, user.displayName, user.authType, user.accessToken
	]
	if not user.anonymousToken.is_empty():
		_txtAnonymousToken.text = user.anonymousToken
	_updateUIState()


func _onSignUpFailed(error: String) -> void:
	_txtAuthResponse.text = "Sign up failed: %s" % error
	_updateUIState()


func _onSignOutCompleted() -> void:
	_txtAuthResponse.text = "Signed out successfully"
	_updateUIState()


# ===== CONNECTION HANDLERS =====

func _onConnectClicked() -> void:
	if not _horizon.isInitialized():
		_lblConnectionStatus.text = "Error: Config not imported. Use Project > Tools > horizOn: Import Config"
		return

	_lblConnectionStatus.text = "Status: Connecting..."
	var connected: bool = await _horizon.connect_to_server()

	if not connected:
		_lblConnectionStatus.text = "Status: Connection Failed"

	_updateUIState()


func _onDisconnectClicked() -> void:
	_horizon.disconnect_from_server()
	_updateUIState()


# ===== AUTHENTICATION HANDLERS =====

func _onSignUpEmailClicked() -> void:
	var email = _txtEmail.text.strip_edges()
	var password = _txtPassword.text.strip_edges()
	var displayName = _txtDisplayName.text.strip_edges()

	if email.is_empty() or password.is_empty():
		_txtAuthResponse.text = "Error: Email and password are required"
		return

	_txtAuthResponse.text = "Signing up..."
	var success: bool = await _horizon.auth.signUpEmail(email, password, displayName)

	if not success:
		_txtAuthResponse.text = "Sign up failed. Check console for details."
	_updateUIState()


func _onSignInEmailClicked() -> void:
	var email = _txtEmail.text.strip_edges()
	var password = _txtPassword.text.strip_edges()

	if email.is_empty() or password.is_empty():
		_txtAuthResponse.text = "Error: Email and password are required"
		return

	_txtAuthResponse.text = "Signing in..."
	var success: bool = await _horizon.auth.signInEmail(email, password)

	if not success:
		_txtAuthResponse.text = "Sign in failed. Check console for details."
	_updateUIState()


func _onSignInAnonymousClicked() -> void:
	var manualToken = _txtAnonymousToken.text.strip_edges()

	if not manualToken.is_empty():
		_txtAuthResponse.text = "Signing in with provided anonymous token..."
		var success: bool = await _horizon.auth.signInAnonymous(manualToken)
		if not success:
			_txtAuthResponse.text = "Anonymous sign in failed."
	elif _horizon.auth.hasCachedAnonymousToken():
		_txtAuthResponse.text = "Restoring anonymous session..."
		var success: bool = await _horizon.auth.restoreAnonymousSession()
		if not success:
			_txtAuthResponse.text = "Creating new anonymous user..."
			var displayName = _txtDisplayName.text.strip_edges()
			await _horizon.auth.signUpAnonymous(displayName)
	else:
		_txtAuthResponse.text = "Creating new anonymous user..."
		var displayName = _txtDisplayName.text.strip_edges()
		await _horizon.auth.signUpAnonymous(displayName)

	_updateUIState()


func _onSignOutClicked() -> void:
	_horizon.auth.signOut()


func _onCheckAuthClicked() -> void:
	_txtAuthResponse.text = "Checking authentication..."
	var isValid: bool = await _horizon.auth.checkAuth()
	_txtAuthResponse.text = "Session is valid!" if isValid else "Session is invalid or expired"
	_updateUIState()


func _onChangeNameClicked() -> void:
	var newName = _txtDisplayName.text.strip_edges()

	if newName.is_empty():
		_txtAuthResponse.text = "Error: Please enter a new display name"
		return

	_txtAuthResponse.text = "Changing display name..."
	var success: bool = await _horizon.auth.changeName(newName)

	if success:
		_txtAuthResponse.text = "Display name changed successfully!"
	else:
		_txtAuthResponse.text = "Failed to change display name"
	_updateUIState()


# ===== GOOGLE AUTH HANDLERS =====

func _onGoogleSignUpClicked() -> void:
	var authCode = _txtGoogleAuthCode.text.strip_edges()
	var redirectUri = _txtGoogleRedirectUri.text.strip_edges()
	var displayName = _txtDisplayName.text.strip_edges()

	if authCode.is_empty():
		_txtGoogleAuthResponse.text = "Error: Google authorization code is required"
		return

	if redirectUri.is_empty():
		_txtGoogleAuthResponse.text = "Error: Redirect URI is required"
		return

	_txtGoogleAuthResponse.text = "Signing up with Google..."
	var success: bool = await _horizon.auth.signUpGoogle(authCode, redirectUri, displayName)

	if success:
		_txtGoogleAuthResponse.text = "Google sign up successful!"
	else:
		_txtGoogleAuthResponse.text = "Google sign up failed. Check console for details."
	_updateUIState()


func _onGoogleSignInClicked() -> void:
	var authCode = _txtGoogleAuthCode.text.strip_edges()
	var redirectUri = _txtGoogleRedirectUri.text.strip_edges()

	if authCode.is_empty():
		_txtGoogleAuthResponse.text = "Error: Google authorization code is required"
		return

	if redirectUri.is_empty():
		_txtGoogleAuthResponse.text = "Error: Redirect URI is required"
		return

	_txtGoogleAuthResponse.text = "Signing in with Google..."
	var success: bool = await _horizon.auth.signInGoogle(authCode, redirectUri)

	if success:
		_txtGoogleAuthResponse.text = "Google sign in successful!"
	else:
		_txtGoogleAuthResponse.text = "Google sign in failed. Check console for details."
	_updateUIState()


# ===== PASSWORD RESET HANDLERS =====

func _onForgotPasswordClicked() -> void:
	var email = _txtForgotEmail.text.strip_edges()

	if email.is_empty():
		_txtAuthResponse.text = "Error: Email is required"
		return

	_txtAuthResponse.text = "Sending password reset email..."
	var success: bool = await _horizon.auth.forgotPassword(email)

	if success:
		_txtAuthResponse.text = "Password reset email sent to: %s" % email
	else:
		_txtAuthResponse.text = "Failed to send password reset email"


func _onResetPasswordClicked() -> void:
	var token = _txtResetToken.text.strip_edges()
	var newPassword = _txtNewPassword.text.strip_edges()

	if token.is_empty() or newPassword.is_empty():
		_txtAuthResponse.text = "Error: Token and new password are required"
		return

	_txtAuthResponse.text = "Resetting password..."
	var success: bool = await _horizon.auth.resetPassword(token, newPassword)

	if success:
		_txtAuthResponse.text = "Password reset successfully!"
		_txtResetToken.text = ""
		_txtNewPassword.text = ""
	else:
		_txtAuthResponse.text = "Failed to reset password"


# ===== EMAIL VERIFICATION HANDLER =====

func _onVerifyEmailClicked() -> void:
	var token = _txtVerifyToken.text.strip_edges()

	if token.is_empty():
		_txtAuthResponse.text = "Error: Verification token is required"
		return

	_txtAuthResponse.text = "Verifying email..."
	var success: bool = await _horizon.auth.verifyEmail(token)

	if success:
		_txtAuthResponse.text = "Email verified successfully!"
		_txtVerifyToken.text = ""
	else:
		_txtAuthResponse.text = "Failed to verify email"
	_updateUIState()


# ===== REMOTE CONFIG HANDLERS =====

func _onConfigGetClicked() -> void:
	var key = _txtConfigKey.text.strip_edges()

	if key.is_empty():
		_txtConfigResponse.text = "Error: Config key is required"
		return

	_txtConfigResponse.text = "Loading config '%s'..." % key
	var value: String = await _horizon.remoteConfig.getConfig(key, false)

	if not value.is_empty():
		_txtConfigResponse.text = "Key: %s\nValue: %s" % [key, value]
	else:
		_txtConfigResponse.text = "Config '%s' not found" % key


func _onConfigAllClicked() -> void:
	_txtConfigResponse.text = "Loading all configs..."
	var configs: Dictionary = await _horizon.remoteConfig.getAllConfigs(false)

	if not configs.is_empty():
		var response = "Loaded %d configuration values:\n\n" % configs.size()
		for key in configs:
			response += "%s: %s\n" % [key, configs[key]]
		_txtConfigResponse.text = response
	else:
		_txtConfigResponse.text = "No configs found"


func _onConfigClearClicked() -> void:
	_horizon.remoteConfig.clearCache()
	_txtConfigResponse.text = "Cache cleared"


# ===== NEWS HANDLERS =====

func _onNewsLoadClicked() -> void:
	var limit = 20
	if not _txtNewsLimit.text.is_empty() and _txtNewsLimit.text.is_valid_int():
		limit = _txtNewsLimit.text.to_int()

	var languageCode = _txtNewsLanguage.text.strip_edges()

	_txtNewsResponse.text = "Loading news..."
	var entries = await _horizon.news.loadNews(limit, languageCode, false)

	if not entries.is_empty():
		var response = "Loaded %d news entries:\n\n" % entries.size()
		for entry in entries:
			response += "%s\n  %s\n  Released: %s\n  Language: %s\n\n" % [
				entry.title, entry.message, entry.releaseDate, entry.languageCode
			]
		_txtNewsResponse.text = response
	else:
		_txtNewsResponse.text = "No news found"


func _onNewsClearClicked() -> void:
	_horizon.news.clearCache()
	_txtNewsResponse.text = "News cache cleared"


# ===== LEADERBOARD HANDLERS =====

func _onLeaderboardSubmitClicked() -> void:
	if not _txtScore.text.is_valid_int():
		_txtLeaderboardResponse.text = "Error: Invalid score"
		return

	var score = _txtScore.text.to_int()

	_txtLeaderboardResponse.text = "Submitting score..."
	var success: bool = await _horizon.leaderboard.submitScore(score)

	if success:
		_txtLeaderboardResponse.text = "Score submitted successfully!\nScore: %d" % score
	else:
		_txtLeaderboardResponse.text = "Score submission failed"


func _onLeaderboardTopClicked() -> void:
	_txtLeaderboardResponse.text = "Loading top players..."
	var entries = await _horizon.leaderboard.getTop(10, false)

	if not entries.is_empty():
		var response = "Top %d players:\n\n" % entries.size()
		for entry in entries:
			response += "%d. %s: %d\n" % [entry.position, entry.username, entry.score]
		_txtLeaderboardResponse.text = response
	else:
		_txtLeaderboardResponse.text = "No entries found"


func _onLeaderboardRankClicked() -> void:
	_txtLeaderboardResponse.text = "Getting your rank..."
	var entry = await _horizon.leaderboard.getRank()

	if entry != null:
		_txtLeaderboardResponse.text = "Your Position: %d\nYour Score: %d\nUsername: %s" % [
			entry.position, entry.score, entry.username
		]
	else:
		_txtLeaderboardResponse.text = "Failed to get rank"


func _onLeaderboardAroundClicked() -> void:
	_txtLeaderboardResponse.text = "Loading nearby players..."
	var entries = await _horizon.leaderboard.getAround(3, false)

	if not entries.is_empty():
		var response = "Players around you:\n\n"
		for entry in entries:
			response += "%d. %s: %d\n" % [entry.position, entry.username, entry.score]
		_txtLeaderboardResponse.text = response
	else:
		_txtLeaderboardResponse.text = "No entries found"


# ===== CLOUD SAVE HANDLERS =====

func _onSaveSaveClicked() -> void:
	var data = _txtSaveData.text.strip_edges()

	if data.is_empty():
		_txtSaveResponse.text = "Error: Data is required"
		return

	var useBinary = _optSaveContentType.selected == 1

	if useBinary:
		var binaryData: PackedByteArray
		if data.is_valid_hex_number():
			binaryData = data.hex_decode()
			_txtSaveResponse.text = "Saving binary data (hex decoded)..."
		else:
			binaryData = data.to_utf8_buffer()
			_txtSaveResponse.text = "Saving binary data (UTF-8 encoded)..."

		var success: bool = await _horizon.cloudSave.saveBytes(binaryData)

		if success:
			_txtSaveResponse.text = "Binary data saved successfully!\nSize: %d bytes" % binaryData.size()
		else:
			_txtSaveResponse.text = "Binary save failed"
	else:
		_txtSaveResponse.text = "Saving JSON data..."
		var success: bool = await _horizon.cloudSave.saveData(data)

		if success:
			_txtSaveResponse.text = "JSON data saved successfully!\nSize: %d characters" % data.length()
		else:
			_txtSaveResponse.text = "JSON save failed"


func _onSaveLoadClicked() -> void:
	var useBinary = _optSaveContentType.selected == 1

	if useBinary:
		_txtSaveResponse.text = "Loading binary data..."
		var binaryData: PackedByteArray = await _horizon.cloudSave.loadBytes()

		if not binaryData.is_empty():
			var hexData = binaryData.hex_encode()
			_txtSaveResponse.text = "Binary data loaded:\nSize: %d bytes\n\nHex:\n%s" % [binaryData.size(), hexData]
			_txtSaveData.text = hexData
		else:
			_txtSaveResponse.text = "No binary data found"
	else:
		_txtSaveResponse.text = "Loading JSON data..."
		var data: String = await _horizon.cloudSave.loadData()

		if not data.is_empty():
			_txtSaveResponse.text = "JSON data loaded:\nSize: %d characters\n\n%s" % [data.length(), data]
			_txtSaveData.text = data
		else:
			_txtSaveResponse.text = "No JSON data found"


# ===== GIFT CODE HANDLERS =====

func _onGiftCodeValidateClicked() -> void:
	var code = _txtGiftCode.text.strip_edges()

	if code.is_empty():
		_txtGiftCodeResponse.text = "Error: Gift code is required"
		return

	_txtGiftCodeResponse.text = "Validating code..."
	var isValid = await _horizon.giftCodes.validate(code)

	if isValid != null:
		_txtGiftCodeResponse.text = "Code: %s\nValid: %s" % [code, "Yes" if isValid else "No"]
	else:
		_txtGiftCodeResponse.text = "Validation request failed"


func _onGiftCodeRedeemClicked() -> void:
	var code = _txtGiftCode.text.strip_edges()

	if code.is_empty():
		_txtGiftCodeResponse.text = "Error: Gift code is required"
		return

	_txtGiftCodeResponse.text = "Redeeming code..."
	var result: Dictionary = await _horizon.giftCodes.redeem(code)

	if not result.is_empty():
		if result.get("success", false):
			_txtGiftCodeResponse.text = "Code redeemed successfully!\n\nGift Data:\n%s" % result.get("giftData", "")
		else:
			_txtGiftCodeResponse.text = "Redemption failed: %s" % result.get("message", "Unknown error")
	else:
		_txtGiftCodeResponse.text = "Redemption failed"


# ===== FEEDBACK HANDLERS =====

func _onFeedbackSubmitClicked() -> void:
	var title = _txtFeedbackTitle.text.strip_edges()
	var message = _txtFeedbackMessage.text.strip_edges()
	var email = _txtFeedbackEmail.text.strip_edges()

	if title.is_empty():
		_txtFeedbackResponse.text = "Error: Title is required"
		return

	if message.is_empty():
		_txtFeedbackResponse.text = "Error: Message is required"
		return

	var category = _optFeedbackCategory.get_item_text(_optFeedbackCategory.selected)

	_txtFeedbackResponse.text = "Submitting feedback..."
	var success: bool = await _horizon.feedback.submit(title, message, category, email, true)

	if success:
		_txtFeedbackResponse.text = "Feedback submitted successfully!\n\nTitle: %s\nCategory: %s\nMessage: %s" % [
			title, category, message
		]
		_txtFeedbackTitle.text = ""
		_txtFeedbackMessage.text = ""
	else:
		_txtFeedbackResponse.text = "Feedback submission failed"


# ===== USER LOG HANDLERS =====

func _onUserLogCreateClicked() -> void:
	var message = _txtUserLogMessage.text.strip_edges()
	var errorCode = _txtUserLogErrorCode.text.strip_edges()

	if message.is_empty():
		_txtUserLogResponse.text = "Error: Message is required"
		return

	var logType: int
	match _optUserLogType.selected:
		0:
			logType = HorizonUserLogs.LogType.INFO
		1:
			logType = HorizonUserLogs.LogType.WARN
		2:
			logType = HorizonUserLogs.LogType.ERROR
		_:
			logType = HorizonUserLogs.LogType.INFO

	_txtUserLogResponse.text = "Creating %s log..." % _optUserLogType.get_item_text(_optUserLogType.selected)
	var result: Dictionary = await _horizon.userLogs.createLog(logType, message, errorCode)

	if not result.is_empty():
		_txtUserLogResponse.text = "Log created successfully!\n\nID: %s\nCreated At: %s\nMessage: %s" % [
			result.get("id", ""), result.get("createdAt", ""), message
		]
		if not errorCode.is_empty():
			_txtUserLogResponse.text += "\nError Code: %s" % errorCode
	else:
		_txtUserLogResponse.text = "Log creation failed.\n\nNote: User logs feature is not available for FREE accounts."
