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
signal boards_loaded(boards: Array[Dictionary])

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger
var _auth: HorizonAuth

## Cache for leaderboard data
var _cache: Dictionary = {}


func _normalizeBoardKey(board_key: String) -> String:
	return board_key.strip_edges()


func _buildEndpoint(board_key: String, action: String) -> String:
	var normalized_board_key := _normalizeBoardKey(board_key)
	if normalized_board_key.is_empty():
		return "/api/v1/app/leaderboard/%s" % action

	return "/api/v1/app/leaderboards/%s/%s" % [normalized_board_key.uri_encode(), action]


func _buildCacheKey(board_key: String, action: String, value: int) -> String:
	var normalized_board_key := _normalizeBoardKey(board_key)
	if normalized_board_key.is_empty():
		normalized_board_key = "default"

	return "%s_%s_%d" % [normalized_board_key, action, value]


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
## @param board_key Optional board key for multi-board leaderboards
## @return True if submission succeeded
func submitScore(score: int, board_key: String = "") -> bool:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to submit score")
		score_submit_failed.emit("User must be signed in")
		return false

	var user := _auth.getCurrentUser()

	var request := {
		"userId": user.userId,
		"score": score
	}
	var normalized_board_key := _normalizeBoardKey(board_key)
	if not normalized_board_key.is_empty():
		request["leaderboardKey"] = normalized_board_key

	var response := await _http.postAsync(_buildEndpoint(normalized_board_key, "submit"), request)

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
## @param board_key Optional board key for multi-board leaderboards
## @return Array of leaderboard entries, or empty array if failed
func getTop(limit: int = 10, use_cache: bool = true, board_key: String = "") -> Array[HorizonLeaderboardEntry]:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get leaderboard")
		return []

	if limit > 100:
		_logger.warning("Limit capped at 100 entries")
		limit = 100

	# Check cache
	var cacheKey := _buildCacheKey(board_key, "top", limit)
	if use_cache and _cache.has(cacheKey):
		_logger.debug("Cache hit: %s" % cacheKey)
		return _cache[cacheKey]

	var user := _auth.getCurrentUser()
	var endpoint := "%s?userId=%s&limit=%d" % [_buildEndpoint(board_key, "top"), user.userId, limit]

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
## @param board_key Optional board key for multi-board leaderboards
## @return Leaderboard entry with user's rank, or null if failed
func getRank(board_key: String = "") -> HorizonLeaderboardEntry:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get rank")
		return null

	var user := _auth.getCurrentUser()
	var endpoint := "%s?userId=%s" % [_buildEndpoint(board_key, "rank"), user.userId]

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
## @param board_key Optional board key for multi-board leaderboards
## @return Array of leaderboard entries, or empty array if failed
func getAround(range_count: int = 10, use_cache: bool = true, board_key: String = "") -> Array[HorizonLeaderboardEntry]:
	if not _auth.isSignedIn():
		_logger.error("User must be signed in to get leaderboard")
		return []

	# Check cache
	var cacheKey := _buildCacheKey(board_key, "around", range_count)
	if use_cache and _cache.has(cacheKey):
		_logger.debug("Cache hit: %s" % cacheKey)
		return _cache[cacheKey]

	var user := _auth.getCurrentUser()
	var endpoint := "%s?userId=%s&range=%d" % [_buildEndpoint(board_key, "around"), user.userId, range_count]

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


## List available leaderboard boards for this app.
## @return Array of board dictionaries, or empty array if failed
func listBoards() -> Array[Dictionary]:
	var response := await _http.getAsync("/api/v1/app/leaderboards")

	if response.isSuccess and response.data is Dictionary:
		var board_data: Array = response.data.get("boards", [])
		var boards: Array[Dictionary] = []
		for board in board_data:
			if board is Dictionary:
				boards.append(board)

		_logger.info("Loaded %d leaderboard boards" % boards.size())
		boards_loaded.emit(boards)
		return boards

	_logger.error("Failed to list leaderboard boards: %s" % response.error)
	return []


## Clear the leaderboard cache.
func clearCache() -> void:
	_cache.clear()
	_logger.info("Leaderboard cache cleared")
