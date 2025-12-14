## ============================================================
## horizOn SDK - News Manager
## ============================================================
## Handles loading news articles from the server.
## Supports filtering by language and limiting results.
## ============================================================
class_name HorizonNews
extends RefCounted

## Signals
signal news_loaded(entries: Array[HorizonNewsEntry])
signal news_load_failed(error: String)

## Dependencies
var _http: HorizonHttpClient
var _logger: HorizonLogger

## Cache for news entries
var _cache: Array[HorizonNewsEntry] = []
var _cacheKey: String = ""


## Initialize the news manager.
## @param http HTTP client instance
## @param logger Logger instance
func initialize(http: HorizonHttpClient, logger: HorizonLogger) -> void:
	_http = http
	_logger = logger
	_logger.info("News manager initialized")


## Load news articles from the server.
## @param limit Number of articles to load (0-100, default 20)
## @param language_code Optional language filter (e.g., "en", "de")
## @param use_cache Whether to use cached data if available
## @return Array of news entries
func loadNews(limit: int = 20, language_code: String = "", use_cache: bool = true) -> Array[HorizonNewsEntry]:
	# Clamp limit
	limit = clampi(limit, 0, 100)

	# Build cache key
	var cacheKey := "news_%d_%s" % [limit, language_code]

	# Check cache
	if use_cache and cacheKey == _cacheKey and not _cache.is_empty():
		_logger.debug("News cache hit")
		return _cache

	# Build endpoint
	var endpoint := "/api/v1/app/news?limit=%d" % limit
	if not language_code.is_empty():
		endpoint += "&languageCode=%s" % language_code.uri_encode()

	var response := await _http.getAsync(endpoint)

	if response.isSuccess and response.data is Array:
		var entries := HorizonNewsEntry.fromArray(response.data)

		# Update cache
		_cache = entries
		_cacheKey = cacheKey

		_logger.info("Loaded %d news entries" % entries.size())
		news_loaded.emit(entries)
		return entries

	_logger.error("Failed to load news: %s" % response.error)
	news_load_failed.emit(response.error)
	return []


## Get cached news without making a request.
## @return Cached news entries, or empty array if not cached
func getCachedNews() -> Array[HorizonNewsEntry]:
	return _cache


## Clear the news cache.
func clearCache() -> void:
	_cache.clear()
	_cacheKey = ""
	_logger.info("News cache cleared")
