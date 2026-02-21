## ============================================================
## horizOn SDK - Main Singleton
## ============================================================
## Official Godot SDK for horizOn Backend-as-a-Service.
## Access all features through this singleton: Horizon.auth,
## Horizon.leaderboard, Horizon.cloudSave, etc.
##
## Quick Start:
##   1. Import config JSON via Project > Tools > horizOn: Import Config
##   2. Enable the addon in Project Settings > Plugins
##   3. Connect: await Horizon.connect_to_server()
##   4. Use services: Horizon.auth, Horizon.leaderboard, etc.
##
## Channel: ProjectMakers
## Documentation: https://docs.horizon.pm
## ============================================================
extends Node

## SDK Version
const VERSION := "1.2.0"

## Config resource path
const CONFIG_PATH := "res://addons/horizon_sdk/horizon_config.tres"

## Signals for SDK lifecycle
signal sdk_initialized()
signal sdk_connected(host: String)
signal sdk_connection_failed(error: String)
signal sdk_disconnected()

## Configuration (loaded from horizon_config.tres)
var _config: HorizonConfig
var _apiKey: String = ""
var _hosts: PackedStringArray = []
var _connectionTimeoutSeconds: int = 10
var _maxRetryAttempts: int = 3
var _retryDelaySeconds: float = 1.0
var _logLevel: int = HorizonLogger.LogLevel.INFO

## Core components
var _http: HorizonHttpClient
var _logger: HorizonLogger

## Feature managers
var auth: HorizonAuth
var leaderboard: HorizonLeaderboard
var cloudSave: HorizonCloudSave
var remoteConfig: HorizonRemoteConfig
var news: HorizonNews
var giftCodes: HorizonGiftCodes
var feedback: HorizonFeedback
var userLogs: HorizonUserLogs
var crashes: HorizonCrashes

## State
var _isInitialized: bool = false
var _isConnected: bool = false


func _ready() -> void:
	# Initialize with default log level first
	_logger = HorizonLogger.new(_logLevel)
	_logger.info("=== horizOn SDK v%s ===" % VERSION)

	# Load configuration from resource
	_loadConfig()

	# Create HTTP client as a child node (needs to be in tree for HTTPRequest)
	_http = HorizonHttpClient.new()
	_http.name = "HorizonHttpClient"
	add_child(_http)
	_http.initialize(_logger)

	# Initialize all managers
	_initializeManagers()

	# Configure HTTP client if config was loaded
	if _isInitialized:
		_applyConfig()


## Load configuration from the resource file.
func _loadConfig() -> void:
	if not ResourceLoader.exists(CONFIG_PATH):
		_logger.warning("Config not found at %s. Use Project > Tools > horizOn: Import Config" % CONFIG_PATH)
		return

	_config = ResourceLoader.load(CONFIG_PATH) as HorizonConfig
	if _config == null:
		_logger.error("Failed to load config from %s" % CONFIG_PATH)
		return

	if not _config.is_valid():
		_logger.error("Invalid configuration. Please re-import config file.")
		return

	# Extract values from config
	_apiKey = _config.api_key
	_hosts = _config.hosts
	_connectionTimeoutSeconds = _config.connection_timeout_seconds
	_maxRetryAttempts = _config.max_retry_attempts
	_retryDelaySeconds = _config.retry_delay_seconds

	# Set log level
	match _config.log_level:
		"DEBUG":
			_logLevel = HorizonLogger.LogLevel.DEBUG
		"INFO":
			_logLevel = HorizonLogger.LogLevel.INFO
		"WARNING":
			_logLevel = HorizonLogger.LogLevel.WARNING
		"ERROR":
			_logLevel = HorizonLogger.LogLevel.ERROR
		"NONE":
			_logLevel = HorizonLogger.LogLevel.NONE

	_logger.setLogLevel(_logLevel)

	_isInitialized = true
	_logger.info("Config loaded: %d hosts configured" % _hosts.size())
	sdk_initialized.emit()


## Apply configuration to HTTP client.
func _applyConfig() -> void:
	_http.apiKey = _apiKey
	_http.hosts = _hosts
	_http.connectionTimeoutSeconds = _connectionTimeoutSeconds
	_http.maxRetryAttempts = _maxRetryAttempts
	_http.retryDelaySeconds = _retryDelaySeconds


## Initialize all feature managers.
func _initializeManagers() -> void:
	# Authentication
	auth = HorizonAuth.new()
	auth.initialize(_http, _logger)

	# Leaderboard
	leaderboard = HorizonLeaderboard.new()
	leaderboard.initialize(_http, _logger, auth)

	# Cloud Save
	cloudSave = HorizonCloudSave.new()
	cloudSave.initialize(_http, _logger, auth)

	# Remote Config
	remoteConfig = HorizonRemoteConfig.new()
	remoteConfig.initialize(_http, _logger)

	# News
	news = HorizonNews.new()
	news.initialize(_http, _logger)

	# Gift Codes
	giftCodes = HorizonGiftCodes.new()
	giftCodes.initialize(_http, _logger, auth)

	# Feedback
	feedback = HorizonFeedback.new()
	feedback.initialize(_http, _logger, auth)

	# User Logs
	userLogs = HorizonUserLogs.new()
	userLogs.initialize(_http, _logger, auth)

	# Crash Reporting
	crashes = HorizonCrashes.new()
	crashes.initialize(_http, _logger, auth)

	_logger.info("All managers initialized")


## Connect to the best available server.
## Pings all configured hosts and connects to the one with lowest latency.
## @return True if connection succeeded
func connect_to_server() -> bool:
	if not _isInitialized:
		_logger.error("SDK not configured. Import config via Project > Tools > horizOn: Import Config")
		sdk_connection_failed.emit("SDK not configured. Import config file first.")
		return false

	_logger.info("Connecting to horizOn servers...")

	var success := await _http.connect_to_server()

	if success:
		_isConnected = true
		_logger.info("Connected to %s" % _http.activeHost)
		sdk_connected.emit(_http.activeHost)
		return true
	else:
		_isConnected = false
		_logger.error("Failed to connect to any server")
		sdk_connection_failed.emit("Failed to connect to any server")
		return false


## Disconnect from the server.
func disconnect_from_server() -> void:
	_http.disconnect_from_server()
	_isConnected = false
	_logger.info("Disconnected from server")
	sdk_disconnected.emit()


## Check if the SDK is initialized (configured).
## @return True if SDK is configured and ready
func isInitialized() -> bool:
	return _isInitialized


## Check if connected to a server.
## @return True if currently connected
func isConnected() -> bool:
	return _isConnected and _http.isConnected()


## Get the currently active server host.
## @return Host URL or empty string if not connected
func getActiveHost() -> String:
	return _http.activeHost if _isConnected else ""


## Get the loaded configuration.
## @return HorizonConfig resource or null if not loaded
func getConfig() -> HorizonConfig:
	return _config


## Get ping results for all configured hosts.
## @return Dictionary of host URL -> ping time in ms
func getHostPingResults() -> Dictionary:
	return _http.getHostPingResults()


## Get the logger instance for custom logging.
## @return Logger instance
func getLogger() -> HorizonLogger:
	return _logger


## Set the log level.
## @param level The minimum log level to display
func setLogLevel(level: HorizonLogger.LogLevel) -> void:
	_logLevel = level
	_logger.setLogLevel(level)


## Shortcut to check if user is signed in.
## @return True if a user is authenticated
func isSignedIn() -> bool:
	return auth.isSignedIn()


## Shortcut to get the current user.
## @return Current user data
func getCurrentUser() -> HorizonUserData:
	return auth.getCurrentUser()


## Get SDK version.
## @return Version string
func getVersion() -> String:
	return VERSION


# ===== CONVENIENCE METHODS FOR COMMON OPERATIONS =====

## Quick anonymous sign-in (creates new user or restores session).
## @param display_name Optional display name for new users
## @return True if signed in successfully
func quickSignInAnonymous(display_name: String = "") -> bool:
	if not isConnected():
		_logger.error("Not connected to server")
		return false

	# Try to restore existing session first
	if auth.hasCachedAnonymousToken():
		var restored := await auth.restoreAnonymousSession()
		if restored:
			return true

	# Create new anonymous user
	return await auth.signUpAnonymous(display_name)


## Quick sign-in with email (creates account if doesn't exist).
## @param email User email
## @param password User password
## @param username Optional username for new accounts
## @return True if signed in successfully
func quickSignInEmail(email: String, password: String, username: String = "") -> bool:
	if not isConnected():
		_logger.error("Not connected to server")
		return false

	# Try to sign in first
	var signedIn := await auth.signInEmail(email, password)
	if signedIn:
		return true

	# If sign-in failed, try to create account
	return await auth.signUpEmail(email, password, username)
