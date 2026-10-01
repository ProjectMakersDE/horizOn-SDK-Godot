## ============================================================
## horizOn SDK - Player Profile Manager
## ============================================================
## Loads and sets the signed-in player's profile: avatar, frame
## and up to three badges, plus the unlocks and the cosmetic
## catalog of the API key. Both calls need a player session
## (Authorization: Bearer). The server stores only IDs; the game
## maps them to its own assets.
## ============================================================
class_name HorizonPlayerProfile
extends RefCounted

## Signals
signal profile_loaded(profile: Dictionary)
signal profile_load_failed(error: String, code: String)
signal profile_updated(profile: Dictionary)
signal profile_update_failed(error: String, code: String)

## Endpoint of both calls (GET with ?userId=, PUT with JSON body)
const ENDPOINT := "/api/v1/app/player-profile"

## Pattern every cosmetic ID must match (checked again by the server)
const COSMETIC_ID_PATTERN := "^[a-z0-9][a-z0-9._-]{0,31}$"

## Fallback limits until the first response delivered the real ones
const DEFAULT_MAX_BADGES := 3
const DEFAULT_MAX_UNLOCKS := 25

## Error codes. SESSION_REQUIRED, INVALID_BADGES and INVALID_COSMETIC_ID
## are also produced locally (no request is sent). All others come from
## the `code` field of the server error body.
const ERROR_SESSION_REQUIRED := "SESSION_REQUIRED"
const ERROR_SESSION_FORBIDDEN := "SESSION_FORBIDDEN"
const ERROR_INVALID_BADGES := "INVALID_BADGES"
const ERROR_INVALID_COSMETIC_ID := "INVALID_COSMETIC_ID"
const ERROR_COSMETIC_NOT_FOUND := "COSMETIC_NOT_FOUND"
const ERROR_COSMETIC_TYPE_MISMATCH := "COSMETIC_TYPE_MISMATCH"
const ERROR_COSMETIC_LOCKED := "COSMETIC_LOCKED"
const ERROR_PLAYER_NOT_FOUND := "PLAYER_NOT_FOUND"
const ERROR_UNLOCK_LIMIT_REACHED := "UNLOCK_LIMIT_REACHED"

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth

## State
var _currentProfile: Dictionary = {}
var _lastErrorCode: String = ""
var _cosmeticIdRegex: RegEx


## Initialize the player profile manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_cosmeticIdRegex = RegEx.new()
	_cosmeticIdRegex.compile(COSMETIC_ID_PATTERN)

	# The cached profile belongs to one player: drop it when the player changes.
	_auth.signout_completed.connect(clearCache)
	_auth.signin_completed.connect(_onPlayerChanged)
	_auth.signup_completed.connect(_onPlayerChanged)

	_logger.info("Player profile manager initialized")


## Load profile, unlocks and cosmetic catalog of the signed-in player.
## Sends GET /api/v1/app/player-profile?userId=<current user>.
## @return The response as Dictionary (userId, profile, unlocks, cosmetics,
##         limits), or {} on failure (then getLastErrorCode() is set)
func getProfile() -> Dictionary:
	if not _hasSession():
		return _fail("User must be signed in to load the player profile", ERROR_SESSION_REQUIRED, false)

	var user := _auth.getCurrentUser()
	var endpoint := "%s?userId=%s" % [ENDPOINT, user.userId.uri_encode()]
	var response := await _http.getAsync(endpoint, true)

	if response.isSuccess and response.data is Dictionary:
		var result := _storeResult(response.data)
		_logger.info("Player profile loaded (%d cosmetics)" % (result["cosmetics"] as Array).size())
		profile_loaded.emit(result)
		return result

	return _fail(_errorMessage(response, "Failed to load player profile"), _errorCodeOf(response), false)


## Replace the visible profile of the signed-in player.
## PUT replaces the whole profile: pass the current values for slots you
## do not want to change (see getCurrentProfile()).
## Sends PUT /api/v1/app/player-profile.
## @param avatar_id Avatar ID, "" clears the slot
## @param frame_id Frame ID, "" clears the slot
## @param badges Badge IDs (Strings, 0 to 3, order kept), [] clears the badges.
##        A plain Array is accepted, so profile["badges"] can be passed back as is.
## @return The updated response (same shape as getProfile()), or {} on failure
func setProfile(avatar_id: String, frame_id: String, badges: Array = []) -> Dictionary:
	if not _hasSession():
		return _fail("User must be signed in to set the player profile", ERROR_SESSION_REQUIRED, true)

	# Local pre-checks. The server checks everything again.
	var maxBadges := _currentMaxBadges()
	if badges.size() > maxBadges:
		return _fail("At most %d badges are allowed" % maxBadges, ERROR_INVALID_BADGES, true)

	# Same order as the server: badge count and duplicates first, then each ID.
	var badgeIds: Array = []
	for badge in badges:
		if badgeIds.has(badge):
			return _fail("Badge '%s' is listed twice" % str(badge), ERROR_INVALID_BADGES, true)
		badgeIds.append(badge)

	# An empty avatar or frame clears the slot and is always valid.
	for slotId in [avatar_id, frame_id]:
		if not slotId.is_empty() and not _isValidCosmeticId(slotId):
			return _fail("Invalid cosmetic ID '%s'" % slotId, ERROR_INVALID_COSMETIC_ID, true)

	for badge in badgeIds:
		if not (badge is String) or not _isValidCosmeticId(badge):
			return _fail("Invalid badge ID '%s'" % str(badge), ERROR_INVALID_COSMETIC_ID, true)

	var user := _auth.getCurrentUser()
	# Empty avatarId / frameId are dropped by the HTTP client; a missing slot
	# clears it on the server, exactly like "" or null.
	var request := {
		"userId": user.userId,
		"avatarId": avatar_id,
		"frameId": frame_id,
		"badges": badgeIds
	}

	var response := await _http.putAsync(ENDPOINT, request, true)

	if response.isSuccess and response.data is Dictionary:
		var result := _storeResult(response.data)
		_logger.info("Player profile updated")
		profile_updated.emit(result)
		return result

	return _fail(_errorMessage(response, "Failed to set player profile"), _errorCodeOf(response), true)


## Get the last successful result of getProfile() or setProfile().
## @return A copy of the cached response, or {} before the first call and after sign-out
func getCurrentProfile() -> Dictionary:
	return _currentProfile.duplicate(true)


## Get the visible profile of the last result as a typed model.
## @return Profile data (empty profile when nothing is cached)
func getCurrentProfileData() -> HorizonPlayerProfileData:
	return HorizonPlayerProfileData.fromDict(_currentProfile.get("profile"))


## Error code of the last failure: the server `code` (e.g. "COSMETIC_LOCKED"),
## a local code ("SESSION_REQUIRED", "INVALID_BADGES", "INVALID_COSMETIC_ID"),
## or the SDK error name derived from the HTTP status when the server sent
## no code (e.g. "API_RATE_LIMITED", "NETWORK_ERROR").
## @return The code, or "" after a successful call
func getLastErrorCode() -> String:
	return _lastErrorCode


## Cosmetics of the cached catalog with the given type.
## @param type "avatar", "frame" or "badge"
## @return Array of cosmetic dictionaries (id, type, locked, available)
func getCosmetics(type: String) -> Array:
	var result: Array = []
	for cosmetic in _currentProfile.get("cosmetics", []):
		if cosmetic is Dictionary and cosmetic.get("type", "") == type:
			result.append(cosmetic.duplicate())
	return result


## Check whether the player may select a cosmetic now (cached catalog).
## @param cosmetic_id Cosmetic ID
## @return True if the ID is in the catalog and available
func isAvailable(cosmetic_id: String) -> bool:
	for cosmetic in _currentProfile.get("cosmetics", []):
		if cosmetic is Dictionary and cosmetic.get("id", "") == cosmetic_id:
			return cosmetic.get("available", false)
	return false


## Drop the cached profile. Called on sign-out, sign-in and after a gift
## code granted unlocks, so the next getProfile() shows the current state.
func clearCache() -> void:
	_currentProfile = {}
	_logger.debug("Player profile cache cleared")


# ===== INTERNAL =====

func _onPlayerChanged(_user: HorizonUserData) -> void:
	clearCache()


## A profile call needs a signed-in player and a transport session token.
func _hasSession() -> bool:
	return _auth.isSignedIn() and not _http.sessionToken.is_empty()


func _currentMaxBadges() -> int:
	var limits: Variant = _currentProfile.get("limits")
	if limits is Dictionary:
		return int(limits.get("maxBadges", DEFAULT_MAX_BADGES))
	return DEFAULT_MAX_BADGES


## Check a non-empty cosmetic ID against COSMETIC_ID_PATTERN.
func _isValidCosmeticId(cosmetic_id: String) -> bool:
	return _cosmeticIdRegex.search(cosmetic_id) != null


## Normalize a server response, cache it and reset the last error.
func _storeResult(data: Dictionary) -> Dictionary:
	var result := _normalizeResponse(data)
	_currentProfile = result.duplicate(true)
	_lastErrorCode = ""
	return result


## Bring the JSON response into a null safe shape:
## null IDs become "", missing lists become [], numbers become ints.
func _normalizeResponse(data: Dictionary) -> Dictionary:
	var userIdValue: Variant = data.get("userId")

	var unlocks: Array = []
	var rawUnlocks: Variant = data.get("unlocks")
	if rawUnlocks is Array:
		for unlock in rawUnlocks:
			if unlock is String:
				unlocks.append(unlock)

	var cosmetics: Array = []
	var rawCosmetics: Variant = data.get("cosmetics")
	if rawCosmetics is Array:
		for entry in rawCosmetics:
			if entry is Dictionary:
				var id: Variant = entry.get("id")
				var type: Variant = entry.get("type")
				var locked: Variant = entry.get("locked")
				var available: Variant = entry.get("available")
				cosmetics.append({
					"id": id if id is String else "",
					"type": type if type is String else "",
					"locked": locked if locked is bool else false,
					"available": available if available is bool else false
				})

	var limits := {"maxBadges": DEFAULT_MAX_BADGES, "maxUnlocks": DEFAULT_MAX_UNLOCKS}
	var rawLimits: Variant = data.get("limits")
	if rawLimits is Dictionary:
		var maxBadges: Variant = rawLimits.get("maxBadges")
		var maxUnlocks: Variant = rawLimits.get("maxUnlocks")
		if maxBadges != null:
			limits["maxBadges"] = int(maxBadges)
		if maxUnlocks != null:
			limits["maxUnlocks"] = int(maxUnlocks)

	return {
		"userId": userIdValue if userIdValue is String else "",
		"profile": HorizonPlayerProfileData.fromDict(data.get("profile")).toDict(),
		"unlocks": unlocks,
		"cosmetics": cosmetics,
		"limits": limits
	}


## Server `code` when present, otherwise the SDK error name from the HTTP status.
func _errorCodeOf(response: HorizonNetworkResponse) -> String:
	if not response.serverCode.is_empty():
		return response.serverCode
	if response.isSuccess:
		# Success status but a body that is not a JSON object.
		return "INVALID_RESPONSE"
	var key: Variant = HorizonErrorCodes.ErrorCode.find_key(response.errorCode)
	return str(key) if key != null else "UNKNOWN"


func _errorMessage(response: HorizonNetworkResponse, fallback: String) -> String:
	if not response.error.is_empty():
		return response.error
	return fallback


## Record a failure, emit the matching signal and return {}.
func _fail(message: String, code: String, is_update: bool) -> Dictionary:
	_lastErrorCode = code
	_logger.error("Player profile %s failed [%s]: %s" % ["update" if is_update else "load", code, message])
	if is_update:
		profile_update_failed.emit(message, code)
	else:
		profile_load_failed.emit(message, code)
	return {}
