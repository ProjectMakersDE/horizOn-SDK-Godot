## ============================================================
## horizOn SDK - Leaderboard Manager
## ============================================================
## Handles leaderboard operations: score submission, top entries,
## user rank, and entries around user position.
## ============================================================
class_name HorizonLeaderboard
extends RefCounted

## Signals
signal score_submitted(score: int)
signal score_submit_failed(error: String)
signal top_entries_loaded(entries: Array[HorizonLeaderboardEntry])
signal rank_loaded(entry: HorizonLeaderboardEntry)
signal around_entries_loaded(entries: Array[HorizonLeaderboardEntry])

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth

## Cache for leaderboard data
var _cache: Dictionary = {}


## Initialize the leaderboard manager.
## @param http HTTP client instance
## @param logger Logger instance
## @param auth Auth manager instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger, auth: HorizonAuth) -> void:
	_http = http
	_logger = logger
	_auth = auth
	_logger.info("Leaderboard manager initialized")


## Submit a score to the leaderboard.
## Score is only updated if it's higher than the previous best.
## @param score Score value (must be positive)
## @return True if submission succeeded
func submitScore(score: int) -> bool:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to submit score")
		score_submit_failed.emit("User must be signed in")
		return false

	var user := _auth.getCurrentUser()

	var request := {
		"userId": user.userId,
		"score": score
	}

	var response := await _http.postAsync("/api/v1/app/leaderboard/submit", request)

	if response.isSuccess:
		_logger.info("Score submitted: %d" % score)
		# Invalidate cache
		_cache.clear()
		score_submitted.emit(score)
		return true

	_logger.error("Score submission failed: %s" % response.error)
	score_submit_failed.emit(response.error)
	return false


## Get top entries from the leaderboard.
## @param limit Number of entries to retrieve (max 100)
## @param use_cache Whether to use cached data if available
## @return Array of leaderboard entries, or empty array if failed
func getTop(limit: int = 10, use_cache: bool = true) -> Array[HorizonLeaderboardEntry]:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get leaderboard")
		return []

	if limit > 100:
		_logger.warning("Limit capped at 100 entries")
		limit = 100

	# Check cache
	var cacheKey := "top%d" % limit
	if use_cache and _cache.has(cacheKey):
		_logger.debug("Cache hit: %s" % cacheKey)
		return _cache[cacheKey]

	var user := _auth.getCurrentUser()
	var endpoint := "/api/v1/app/leaderboard/top?userId=%s&limit=%d" % [user.userId, limit]

	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var entriesData: Array = response.data.get("entries", [])
		var entries := HorizonLeaderboardEntry.fromArray(entriesData)

		# Cache results
		_cache[cacheKey] = entries

		_logger.info("Loaded top %d entries" % entries.size())
		top_entries_loaded.emit(entries)
		return entries

	_logger.error("Failed to get top leaderboard entries: %s" % response.error)
	return []


## Get the current user's rank in the leaderboard.
## @return Leaderboard entry with user's rank, or null if failed
func getRank() -> HorizonLeaderboardEntry:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get rank")
		return null

	var user := _auth.getCurrentUser()
	var endpoint := "/api/v1/app/leaderboard/rank?userId=%s" % user.userId

	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var entry := HorizonLeaderboardEntry.fromDict(response.data)
		_logger.info("User rank: %d (Score: %d)" % [entry.position, entry.score])
		rank_loaded.emit(entry)
		return entry

	_logger.error("Failed to get rank: %s" % response.error)
	return null


## Get leaderboard entries around the current user's position.
## @param range_count Number of entries before and after the user
## @param use_cache Whether to use cached data if available
## @return Array of leaderboard entries, or empty array if failed
func getAround(range_count: int = 10, use_cache: bool = true) -> Array[HorizonLeaderboardEntry]:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get leaderboard")
		return []

	# Check cache
	var cacheKey := "around%d" % range_count
	if use_cache and _cache.has(cacheKey):
		_logger.debug("Cache hit: %s" % cacheKey)
		return _cache[cacheKey]

	var user := _auth.getCurrentUser()
	var endpoint := "/api/v1/app/leaderboard/around?userId=%s&range=%d" % [user.userId, range_count]

	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Dictionary:
		var entriesData: Array = response.data.get("entries", [])
		var entries := HorizonLeaderboardEntry.fromArray(entriesData)

		# Cache results
		_cache[cacheKey] = entries

		_logger.info("Loaded %d entries around user" % entries.size())
		around_entries_loaded.emit(entries)
		return entries

	_logger.error("Failed to get leaderboard entries around user: %s" % response.error)
	return []


## Clear the leaderboard cache.
func clearCache() -> void:
	_cache.clear()
	_logger.info("Leaderboard cache cleared")
