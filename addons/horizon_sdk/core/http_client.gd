## ============================================================
## horizOn SDK - HTTP Client
## ============================================================
## Core networking layer for the horizOn SDK.
## Handles HTTP requests with retry logic, rate limiting,
## authentication headers, and host selection.
## ============================================================
class_name HorizonHttpClient
extends Node

## Signals for request lifecycle
signal request_started(url: String, method: String)
signal request_completed(url: String, response: HorizonNetworkResponse)
signal request_failed(url: String, error: String)
signal rate_limited(retry_after: float)
signal host_selected(host: String, ping_ms: float)

## Connection status
enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
	FAILED
}

## Configuration
var _contextGeneration: int = 0
var _routeGeneration: int = 0
var apiKey: String = "":
	set(value):
		if apiKey != value:
			apiKey = value
			_contextGeneration += 1
			_routeGeneration += 1
var hosts: PackedStringArray = []
var activeHost: String = "":
	set(value):
		if activeHost != value:
			activeHost = value
			_contextGeneration += 1
			_routeGeneration += 1
var sessionToken: String = "":
	set(value):
		if sessionToken != value:
			sessionToken = value
			_contextGeneration += 1
var connectionTimeoutSeconds: int = 10
var maxRetryAttempts: int = 3
var retryDelaySeconds: float = 1.0

## State
var _status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var _hostPingResults: Dictionary = {}
var _logger: HorizonLogger
var _pendingRequests: int = 0
# Network backoff must not consume the game's deterministic global RNG.
var _retryRandom: RandomNumberGenerator = RandomNumberGenerator.new()


## Initialize the HTTP client.
## @param logger Logger instance for debug output
func initialize(logger: HorizonLogger) -> void:
	_logger = logger
	_retryRandom.randomize()
	_logger.info("HTTP Client initialized")


## Synchronous generation catches A→B→A context transitions, even without auth signals.
func getContextGeneration(include_session: bool = true) -> int:
	return _contextGeneration if include_session else _routeGeneration


## Get current connection status.
func getStatus() -> ConnectionStatus:
	return _status


## Check if connected.
func isConnected() -> bool:
	return _status == ConnectionStatus.CONNECTED


## Connect to the best available host.
## With a single host, connects directly with a health check (no ping round-trip).
## With multiple hosts, pings all and selects the one with lowest latency.
## @return True if connection succeeded
func connect_to_server() -> bool:
	if hosts.is_empty():
		_logger.error("No hosts configured")
		_status = ConnectionStatus.FAILED
		return false

	if apiKey.is_empty():
		_logger.error("API key not configured")
		_status = ConnectionStatus.FAILED
		return false

	_status = ConnectionStatus.CONNECTING
	_logger.info("Starting connection to horizOn servers...")
	request_started.emit("", "PING")

	# Single host: skip ping, just do a health check
	if hosts.size() == 1:
		var host: String = hosts[0]
		_logger.info("Single host configured, checking health...")
		var healthOk := await _checkHealth(host)
		if not healthOk:
			_logger.error("Host %s health check failed" % host)
			_status = ConnectionStatus.FAILED
			return false

		activeHost = host
		_status = ConnectionStatus.CONNECTED
		_logger.info("Connected to %s (single host)" % activeHost)
		host_selected.emit(activeHost, 0.0)
		return true

	# Multiple hosts: ping all and select the best one
	await _pingAllHosts()

	# Select best host
	if _hostPingResults.is_empty():
		_logger.error("No hosts responded to ping")
		_status = ConnectionStatus.FAILED
		return false

	# Find host with lowest ping
	var bestHost: String = ""
	var bestPing: float = INF

	for host in _hostPingResults:
		var ping: float = _hostPingResults[host]
		if ping < bestPing:
			bestPing = ping
			bestHost = host

	activeHost = bestHost
	_status = ConnectionStatus.CONNECTED

	_logger.info("Connected to %s (ping: %.0fms)" % [activeHost, bestPing])
	host_selected.emit(activeHost, bestPing)

	return true


## Reconnect to the server (on failure).
## @return True if reconnection succeeded
func reconnect() -> bool:
	_logger.warning("Connection lost. Attempting to reconnect...")
	_status = ConnectionStatus.RECONNECTING
	_hostPingResults.clear()
	return await connect_to_server()


## Disconnect from the server.
func disconnect_from_server() -> void:
	activeHost = ""
	sessionToken = ""
	_status = ConnectionStatus.DISCONNECTED
	_hostPingResults.clear()
	_logger.info("Disconnected from horizOn server")


## Ping all configured hosts and record response times.
func _pingAllHosts() -> void:
	_hostPingResults.clear()
	const PING_ATTEMPTS := 3

	for host in hosts:
		var bestPing: float = INF

		for i in PING_ATTEMPTS:
			var pingResult := await _pingHost(host)
			if pingResult >= 0 and pingResult < bestPing:
				bestPing = pingResult

		if bestPing < INF:
			_hostPingResults[host] = bestPing
			_logger.info("Host %s: %.0fms" % [host, bestPing])
		else:
			_logger.warning("Host %s: Failed (no successful ping)" % host)


## Ping a single host and measure response time.
## @param host The host URL to ping
## @return Ping time in ms, or -1 if failed
func _pingHost(host: String) -> float:
	var pingUrl := host + "/api/v1/public/health"
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = connectionTimeoutSeconds

	var startTime := Time.get_ticks_msec()

	var error := http.request(pingUrl, [], HTTPClient.METHOD_GET)
	if error != OK:
		http.queue_free()
		return -1.0

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]

	if response_code == 200:
		var bodyText := body.get_string_from_utf8()
		if bodyText.strip_edges() == "OK":
			return float(Time.get_ticks_msec() - startTime)

	return -1.0


## Check if a host is healthy (single request, no timing).
## @param host The host URL to check
## @return True if the host reports healthy
func _checkHealth(host: String) -> bool:
	var healthUrl := host + "/api/v1/public/health"
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = connectionTimeoutSeconds

	var error := http.request(healthUrl, [], HTTPClient.METHOD_GET)
	if error != OK:
		http.queue_free()
		return false

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]

	if response_code == 200:
		var bodyText := body.get_string_from_utf8()
		if bodyText.strip_edges() == "OK":
			return true

	return false


## Set the session token for authenticated requests.
## @param token The session token
func setSessionToken(token: String) -> void:
	sessionToken = token
	_logger.debug("Session token updated")


## Clear the session token.
func clearSessionToken() -> void:
	sessionToken = ""
	_logger.debug("Session token cleared")


## Make a GET request.
## @param endpoint The API endpoint (e.g., "/api/v1/app/news")
## @param useSessionToken Whether to include Authorization header
## @return Network response
func getAsync(endpoint: String, useSessionToken: bool = false) -> HorizonNetworkResponse:
	return await _sendRequest(endpoint, HTTPClient.METHOD_GET, {}, useSessionToken)


## Make a POST request with JSON body.
## @param endpoint The API endpoint
## @param data Request body data (will be JSON-encoded)
## @param useSessionToken Whether to include Authorization header
## @param extraHeaders Additional request headers as "Name: value" lines (e.g. If-Match)
## @return Network response
func postAsync(endpoint: String, data: Dictionary = {}, useSessionToken: bool = false, extraHeaders: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
	return await _sendRequest(endpoint, HTTPClient.METHOD_POST, data, useSessionToken, extraHeaders)


## Make a PUT request with JSON body.
## Same headers, retries and error handling as postAsync.
## @param endpoint The API endpoint
## @param data Request body data (will be JSON-encoded)
## @param useSessionToken Whether to include Authorization header
## @return Network response
func putAsync(endpoint: String, data: Dictionary = {}, useSessionToken: bool = false) -> HorizonNetworkResponse:
	return await _sendRequest(endpoint, HTTPClient.METHOD_PUT, data, useSessionToken)


## Make a DELETE request.
## @param endpoint The API endpoint
## @param useSessionToken Whether to include Authorization header
## @return Network response
func deleteAsync(endpoint: String, useSessionToken: bool = false) -> HorizonNetworkResponse:
	return await _sendRequest(endpoint, HTTPClient.METHOD_DELETE, {}, useSessionToken)


## Make a POST request with raw binary data.
## @param endpoint The API endpoint
## @param binaryData Raw bytes to send
## @param useSessionToken Whether to include Authorization header
## @param extraHeaders Additional request headers as "Name: value" lines (e.g. If-Match)
## @return Network response
func postBinaryAsync(endpoint: String, binaryData: PackedByteArray, useSessionToken: bool = false, extraHeaders: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
	return await _sendBinaryRequest(endpoint, binaryData, useSessionToken, extraHeaders)


## Make a GET request expecting binary response.
## @param endpoint The API endpoint
## @param useSessionToken Whether to include Authorization header
## @return Dictionary with "found" bool and "data" PackedByteArray
func getBinaryAsync(endpoint: String, useSessionToken: bool = false) -> Dictionary:
	return await _sendBinaryResponseRequest(endpoint, HTTPClient.METHOD_GET, {}, useSessionToken)


## Make a POST request with a JSON body expecting a binary response.
## Cloud Save load requires application/json input and application/octet-stream output.
## @return Dictionary with "success", "found", "data", "error", "statusCode" and
##         "headers" (response headers as "Name: value" lines, empty without a response)
func postJsonForBinaryAsync(endpoint: String, data: Dictionary, useSessionToken: bool = false) -> Dictionary:
	return await _sendBinaryResponseRequest(endpoint, HTTPClient.METHOD_POST, data, useSessionToken)


## Human-readable HTTP method name for logging and telemetry.
func _methodName(method: int) -> String:
	match method:
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_PUT:
			return "PUT"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		_:
			return "GET"


## Internal request handler with retry logic.
func _sendRequest(endpoint: String, method: int, data: Dictionary, useSessionToken: bool, extraHeaders: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
	if activeHost.is_empty():
		return HorizonNetworkResponse.failure(
			"No active host. Call connect() first.",
			0,
			HorizonErrorCodes.ErrorCode.SDK_NOT_CONNECTED
		)

	# A retry belongs to the original request. Never combine its URL/body with a new
	# project or player session after a sign-out, reconnect or project switch.
	var requestHost: String = activeHost
	var requestGeneration: int = getContextGeneration(useSessionToken)
	var requestKey: String = apiKey
	var requestToken: String = sessionToken if useSessionToken else ""
	var url := requestHost + endpoint
	var headers: PackedStringArray = ["Content-Type: application/json", "X-API-Key: " + requestKey]
	if not requestToken.is_empty(): headers.append("Authorization: Bearer " + requestToken)
	headers.append_array(extraHeaders)
	var bodyJson := ""
	if not data.is_empty() or method == HTTPClient.METHOD_POST or method == HTTPClient.METHOD_PUT:
		bodyJson = _toJsonExcludeEmpty(data)
	var attemptCount := 0
	var maxAttempts := maxRetryAttempts + 1
	# Signup creates a fresh server identity; legacy redemption has no deduplication ID.
	# An uncertain outcome must never trigger a second effect within the transport.
	var route: String = endpoint.get_slice("?", 0)
	var redemption_id: Variant = data.get("idempotencyId")
	if method == HTTPClient.METHOD_POST and (route == "/api/v1/app/user-management/signup" or (route == "/api/v1/app/gift-codes/redeem" and (not redemption_id is String or redemption_id.is_empty()))):
		maxAttempts = 1

	while attemptCount < maxAttempts:
		attemptCount += 1
		request_started.emit(url, _methodName(method))
		if getContextGeneration(useSessionToken) != requestGeneration or activeHost != requestHost or apiKey != requestKey or (useSessionToken and sessionToken != requestToken):
			var changed := HorizonNetworkResponse.failure("Request context changed before retry", 0, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
			changed.serverCode = "SESSION_CHANGED"
			return changed

		var http := HTTPRequest.new()
		add_child(http)
		http.timeout = connectionTimeoutSeconds

		# Send request (bodyJson is empty for body-less methods)
		var error := http.request(url, headers, method, bodyJson)

		if error != OK:
			http.queue_free()
			_logger.error("Request failed to start: %d" % error)
			return HorizonNetworkResponse.failure(
				"Failed to start request",
				0,
				HorizonErrorCodes.ErrorCode.NETWORK_ERROR
			)

		# Wait for completion
		var result: Array = await http.request_completed
		http.queue_free()

		if getContextGeneration(useSessionToken) != requestGeneration:
			var stale: HorizonNetworkResponse = HorizonNetworkResponse.failure("Request context changed while awaiting response",0,HorizonErrorCodes.ErrorCode.NETWORK_ERROR)
			stale.serverCode = "SESSION_CHANGED"
			return stale

		var resultCode: int = result[0]
		var responseCode: int = result[1]
		var responseHeaders: PackedStringArray = result[2]
		var body: PackedByteArray = result[3]

		# Handle network errors
		if resultCode != HTTPRequest.RESULT_SUCCESS:
			if attemptCount < maxAttempts:
				_logger.warning("Request failed (attempt %d/%d). Retrying..." % [attemptCount, maxAttempts])
				await get_tree().create_timer(retryDelaySeconds).timeout
				continue
			return HorizonNetworkResponse.failure(
				"Network error: %d" % resultCode,
				0,
				HorizonErrorCodes.ErrorCode.NETWORK_ERROR
			)

		# Handle rate limiting
		if responseCode == 429:
			var retryAfter: float = _retryAfterSeconds(responseHeaders)
			if not is_finite(retryAfter) or retryAfter <= 0.0:
				retryAfter = maxf(retryDelaySeconds, 1.0) if is_finite(retryDelaySeconds) else 1.0
			rate_limited.emit(retryAfter)
			# A 429 whose body carries a `code` is a feature limit (e.g. RUN_RATE_LIMITED,
			# RUN_CAPACITY_REACHED), not the transient account request limit (empty body).
			# The wait can be an hour, so fail at once and let the game decide.
			var limitBody := body.get_string_from_utf8()
			var limitCode := _parseServerErrorCode(limitBody)
			if not limitCode.is_empty():
				var limitMsg := _parseErrorMessage(limitBody, responseCode)
				_logger.error("Request failed: %s %s - %s [%s, retry after %.0f s]" % [_methodName(method), url, limitMsg, limitCode, retryAfter])
				request_failed.emit(url, limitMsg)
				var limited := HorizonNetworkResponse.failure(limitMsg, responseCode, HorizonErrorCodes.ErrorCode.API_RATE_LIMITED)
				limited.serverCode = limitCode
				limited.headers = responseHeaders
				return limited
			if attemptCount < maxAttempts:
				var wait_seconds: float = _rateLimitDelay(retryAfter)
				_logger.warning("Rate limited. Retrying after %.1f seconds including jitter..." % wait_seconds)
				await get_tree().create_timer(wait_seconds).timeout
				continue
			# Still rate limited after the last attempt: fail with a clear message and keep the 429 status.
			var rateLimitMsg := _rateLimitMessage(retryAfter)
			_logger.error("Request failed: %s %s - %s" % [_methodName(method), url, rateLimitMsg])
			request_failed.emit(url, rateLimitMsg)
			var rateLimited := HorizonNetworkResponse.failure(
				rateLimitMsg,
				responseCode,
				HorizonErrorCodes.ErrorCode.API_RATE_LIMITED
			)
			rateLimited.headers = responseHeaders
			return rateLimited

		# Handle server errors (5xx) - retry
		if responseCode >= 500:
			if attemptCount < maxAttempts:
				_logger.warning("Server error %d (attempt %d/%d). Retrying..." % [responseCode, attemptCount, maxAttempts])
				await get_tree().create_timer(retryDelaySeconds).timeout
				continue

		var bodyText := body.get_string_from_utf8()
		_logger.debug("Response from %s: %s" % [endpoint, bodyText])

		# Handle client errors (4xx)
		if responseCode >= 400:
			var errorMsg := _parseErrorMessage(bodyText, responseCode)
			_logger.error("Request failed: %s %s - %s" % [_methodName(method), url, errorMsg])
			var errorCode := HorizonErrorCodes.fromHttpStatus(responseCode)
			request_failed.emit(url, errorMsg)
			var failed := HorizonNetworkResponse.failure(errorMsg, responseCode, errorCode)
			failed.serverCode = _parseServerErrorCode(bodyText)
			failed.errorBody = bodyText
			failed.headers = responseHeaders
			return failed

		# Success - parse JSON response
		var trimmed := bodyText.strip_edges()
		var parsed: Variant = null
		if trimmed.is_empty():
			parsed = {}
		elif trimmed.begins_with("{") or trimmed.begins_with("[") or trimmed.begins_with("\"") or trimmed == "true" or trimmed == "false" or trimmed == "null" or trimmed.is_valid_float():
			parsed = JSON.parse_string(trimmed)
			if parsed == null:
				_logger.warning("Failed to parse JSON response: %s" % trimmed)
				parsed = {"raw": bodyText}
		else:
			# Plain text response (e.g. "ok")
			parsed = {"success": true, "message": trimmed}

		var response := HorizonNetworkResponse.success(parsed if parsed != null else {}, responseCode)
		response.rawBody = bodyText
		response.headers = responseHeaders
		request_completed.emit(url, response)
		return response

	# Max retries exceeded
	return HorizonNetworkResponse.failure(
		"Max retry attempts (%d) exceeded" % maxAttempts,
		0,
		HorizonErrorCodes.ErrorCode.NETWORK_ERROR
	)


## Send binary POST request.
func _sendBinaryRequest(endpoint: String, binaryData: PackedByteArray, useSessionToken: bool, extraHeaders: PackedStringArray = PackedStringArray()) -> HorizonNetworkResponse:
	if activeHost.is_empty():
		return HorizonNetworkResponse.failure(
			"No active host. Call connect() first.",
			0,
			HorizonErrorCodes.ErrorCode.SDK_NOT_CONNECTED
		)

	var url := activeHost + endpoint
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = connectionTimeoutSeconds

	var headers: PackedStringArray = [
		"Content-Type: application/octet-stream",
		"X-API-Key: " + apiKey
	]

	if useSessionToken and not sessionToken.is_empty():
		headers.append("Authorization: Bearer " + sessionToken)
	headers.append_array(extraHeaders)

	var error := http.request_raw(url, headers, HTTPClient.METHOD_POST, binaryData)
	if error != OK:
		http.queue_free()
		return HorizonNetworkResponse.failure("Failed to start binary request", 0, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)

	var result: Array = await http.request_completed
	http.queue_free()

	var resultCode: int = result[0]
	var responseCode: int = result[1]
	var body: PackedByteArray = result[3]

	if resultCode != HTTPRequest.RESULT_SUCCESS:
		return HorizonNetworkResponse.failure("Network error: %d" % resultCode, 0, HorizonErrorCodes.ErrorCode.NETWORK_ERROR)

	if responseCode >= 400:
		var bodyText := body.get_string_from_utf8()
		var errorMsg := _parseErrorMessage(bodyText, responseCode)
		if responseCode == HorizonErrorCodes.HTTP_RATE_LIMITED:
			errorMsg = _rateLimitMessage(_retryAfterSeconds(result[2]))
		var failed := HorizonNetworkResponse.failure(errorMsg, responseCode, HorizonErrorCodes.fromHttpStatus(responseCode))
		failed.headers = result[2]
		return failed

	var bodyText := body.get_string_from_utf8()
	var parsed := JSON.parse_string(bodyText)
	var response := HorizonNetworkResponse.success(parsed if parsed != null else {}, responseCode)
	response.headers = result[2]
	return response


## Send a request expecting a binary response.
func _sendBinaryResponseRequest(endpoint: String, method: int, data: Dictionary, useSessionToken: bool) -> Dictionary:
	if activeHost.is_empty():
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "No active host"}

	var url := activeHost + endpoint
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = connectionTimeoutSeconds

	var headers: PackedStringArray = [
		"Accept: application/octet-stream",
		"X-API-Key: " + apiKey
	]

	if useSessionToken and not sessionToken.is_empty():
		headers.append("Authorization: Bearer " + sessionToken)

	var bodyJson := ""
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json")
		bodyJson = _toJsonExcludeEmpty(data)

	var error := http.request(url, headers, method, bodyJson)
	if error != OK:
		http.queue_free()
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "Failed to start request"}

	var result: Array = await http.request_completed
	http.queue_free()

	var resultCode: int = result[0]
	var responseCode: int = result[1]
	var responseHeaders: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]

	if resultCode != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "Network error: %d" % resultCode}

	# 204 No Content = not found
	if responseCode == 204:
		return {"success": true, "found": false, "data": PackedByteArray(), "error": "", "statusCode": responseCode, "headers": responseHeaders}

	if responseCode >= 400:
		var errorMsg: String = _rateLimitMessage(_retryAfterSeconds(responseHeaders)) if responseCode == HorizonErrorCodes.HTTP_RATE_LIMITED else "HTTP %d" % responseCode
		return {"success": false, "found": false, "data": PackedByteArray(), "error": errorMsg, "statusCode": responseCode, "headers": responseHeaders}

	return {"success": true, "found": true, "data": body, "error": "", "statusCode": responseCode, "headers": responseHeaders}


## Convert dictionary to JSON, excluding empty string values.
## @param data The dictionary to convert
## @return JSON string
func _toJsonExcludeEmpty(data: Dictionary) -> String:
	var filtered := {}
	for key in data:
		var value = data[key]
		# Exclude null and empty strings, but keep false, 0, and empty arrays/dicts
		if value != null and not (value is String and value.is_empty()):
			filtered[key] = value
	return JSON.stringify(filtered)


## Parse error message from response body.
## @param bodyText Response body text
## @param statusCode HTTP status code
## @return Human-readable error message
func _parseErrorMessage(bodyText: String, statusCode: int) -> String:
	if not bodyText.is_empty():
		var parsed := JSON.parse_string(bodyText)
		if parsed is Dictionary:
			if parsed.has("message"):
				return parsed["message"]
			if parsed.has("error"):
				return parsed["error"]

	return "HTTP %d" % statusCode


## Parse the machine readable `code` field from an error body.
## @param bodyText Response body text
## @return The server code (e.g. "COSMETIC_LOCKED"), or "" when the body has none
func _parseServerErrorCode(bodyText: String) -> String:
	if bodyText.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(bodyText)
	if parsed is Dictionary:
		var code: Variant = parsed.get("code")
		if code is String:
			return code
	return ""


## One existing retry timer; never retry before the server's delay. No global game RNG use.
func _rateLimitDelay(retry_after: float) -> float:
	var base: float = retry_after if is_finite(retry_after) and retry_after > 0.0 else (maxf(retryDelaySeconds, 1.0) if is_finite(retryDelaySeconds) else 1.0)
	return base + base * _retryRandom.randf_range(0.0, 0.2)


## Read the Retry-After header in seconds (0.0 if missing or not numeric).
## @param responseHeaders Response headers from HTTPRequest.request_completed
## @return Seconds to wait before the next request
func _retryAfterSeconds(responseHeaders: PackedStringArray) -> float:
	for header in responseHeaders:
		if header.to_lower().begins_with("retry-after:"):
			return maxf(header.split(":")[1].strip_edges().to_float(), 0.0)
	return 0.0


## Error message for a request that is still rate limited (HTTP 429).
## @param retryAfterSeconds Seconds from the Retry-After header (0 if unknown)
## @return Human-readable error message
func _rateLimitMessage(retryAfterSeconds: float) -> String:
	if retryAfterSeconds > 0.0:
		return "Rate limit exceeded (HTTP 429). Try again in %d seconds." % ceili(retryAfterSeconds)
	return "Rate limit exceeded (HTTP 429). Try again later."


## Get ping results for all hosts.
## @return Dictionary of host -> ping_ms
func getHostPingResults() -> Dictionary:
	return _hostPingResults.duplicate()
