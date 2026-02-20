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
var apiKey: String = ""
var hosts: PackedStringArray = []
var activeHost: String = ""
var sessionToken: String = ""
var connectionTimeoutSeconds: int = 10
var maxRetryAttempts: int = 3
var retryDelaySeconds: float = 1.0

## State
var _status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var _hostPingResults: Dictionary = {}
var _logger: HorizonLogger
var _pendingRequests: int = 0


## Initialize the HTTP client.
## @param logger Logger instance for debug output
func initialize(logger: HorizonLogger) -> void:
	_logger = logger
	_logger.info("HTTP Client initialized")


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
	var pingUrl := host + "/actuator/health"
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
		if bodyText.contains('"status":"UP"'):
			return float(Time.get_ticks_msec() - startTime)

	return -1.0


## Check if a host is healthy (single request, no timing).
## @param host The host URL to check
## @return True if the host reports healthy
func _checkHealth(host: String) -> bool:
	var healthUrl := host + "/actuator/health"
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
		if bodyText.contains('"status":"UP"'):
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
## @return Network response
func postAsync(endpoint: String, data: Dictionary = {}, useSessionToken: bool = false) -> HorizonNetworkResponse:
	return await _sendRequest(endpoint, HTTPClient.METHOD_POST, data, useSessionToken)


## Make a POST request with raw binary data.
## @param endpoint The API endpoint
## @param binaryData Raw bytes to send
## @param useSessionToken Whether to include Authorization header
## @return Network response
func postBinaryAsync(endpoint: String, binaryData: PackedByteArray, useSessionToken: bool = false) -> HorizonNetworkResponse:
	return await _sendBinaryRequest(endpoint, binaryData, useSessionToken)


## Make a GET request expecting binary response.
## @param endpoint The API endpoint
## @param useSessionToken Whether to include Authorization header
## @return Dictionary with "found" bool and "data" PackedByteArray
func getBinaryAsync(endpoint: String, useSessionToken: bool = false) -> Dictionary:
	return await _sendBinaryGetRequest(endpoint, useSessionToken)


## Internal request handler with retry logic.
func _sendRequest(endpoint: String, method: int, data: Dictionary, useSessionToken: bool) -> HorizonNetworkResponse:
	if activeHost.is_empty():
		return HorizonNetworkResponse.failure(
			"No active host. Call connect() first.",
			0,
			HorizonErrorCodes.ErrorCode.SDK_NOT_CONNECTED
		)

	var url := activeHost + endpoint
	var attemptCount := 0
	var maxAttempts := maxRetryAttempts + 1

	while attemptCount < maxAttempts:
		attemptCount += 1
		request_started.emit(url, "POST" if method == HTTPClient.METHOD_POST else "GET")

		var http := HTTPRequest.new()
		add_child(http)
		http.timeout = connectionTimeoutSeconds

		# Build headers
		var headers: PackedStringArray = [
			"Content-Type: application/json",
			"X-API-Key: " + apiKey
		]

		if useSessionToken and not sessionToken.is_empty():
			headers.append("Authorization: Bearer " + sessionToken)

		# Build body
		var bodyJson := ""
		if not data.is_empty() or method == HTTPClient.METHOD_POST:
			bodyJson = _toJsonExcludeEmpty(data)
			_logger.debug("Request JSON: %s" % bodyJson)

		# Send request
		var error: int
		if method == HTTPClient.METHOD_POST:
			error = http.request(url, headers, HTTPClient.METHOD_POST, bodyJson)
		else:
			error = http.request(url, headers, HTTPClient.METHOD_GET)

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
			var retryAfter := retryDelaySeconds
			for header in responseHeaders:
				if header.to_lower().begins_with("retry-after:"):
					retryAfter = float(header.split(":")[1].strip_edges())
					break
			rate_limited.emit(retryAfter)
			_logger.warning("Rate limited. Retrying after %.1f seconds..." % retryAfter)
			await get_tree().create_timer(retryAfter).timeout
			continue

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
			_logger.error("Request failed: %s %s - %s" % ["POST" if method == HTTPClient.METHOD_POST else "GET", url, errorMsg])
			var errorCode := HorizonErrorCodes.fromHttpStatus(responseCode)
			request_failed.emit(url, errorMsg)
			return HorizonNetworkResponse.failure(errorMsg, responseCode, errorCode)

		# Success - parse JSON response
		var parsed := JSON.parse_string(bodyText)
		if parsed == null and not bodyText.is_empty():
			# Try to handle plain text responses
			if bodyText.strip_edges() == "ok" or bodyText.strip_edges() == '"ok"':
				parsed = {"success": true, "message": "ok"}
			else:
				_logger.warning("Failed to parse JSON response: %s" % bodyText)
				parsed = {"raw": bodyText}

		var response := HorizonNetworkResponse.success(parsed if parsed != null else {}, responseCode)
		request_completed.emit(url, response)
		return response

	# Max retries exceeded
	return HorizonNetworkResponse.failure(
		"Max retry attempts (%d) exceeded" % maxAttempts,
		0,
		HorizonErrorCodes.ErrorCode.NETWORK_ERROR
	)


## Send binary POST request.
func _sendBinaryRequest(endpoint: String, binaryData: PackedByteArray, useSessionToken: bool) -> HorizonNetworkResponse:
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
		return HorizonNetworkResponse.failure(errorMsg, responseCode, HorizonErrorCodes.fromHttpStatus(responseCode))

	var bodyText := body.get_string_from_utf8()
	var parsed := JSON.parse_string(bodyText)
	return HorizonNetworkResponse.success(parsed if parsed != null else {}, responseCode)


## Send binary GET request.
func _sendBinaryGetRequest(endpoint: String, useSessionToken: bool) -> Dictionary:
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

	var error := http.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		http.queue_free()
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "Failed to start request"}

	var result: Array = await http.request_completed
	http.queue_free()

	var resultCode: int = result[0]
	var responseCode: int = result[1]
	var body: PackedByteArray = result[3]

	if resultCode != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "Network error: %d" % resultCode}

	# 204 No Content = not found
	if responseCode == 204:
		return {"success": true, "found": false, "data": PackedByteArray(), "error": ""}

	if responseCode >= 400:
		return {"success": false, "found": false, "data": PackedByteArray(), "error": "HTTP %d" % responseCode}

	return {"success": true, "found": true, "data": body, "error": ""}


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


## Get ping results for all hosts.
## @return Dictionary of host -> ping_ms
func getHostPingResults() -> Dictionary:
	return _hostPingResults.duplicate()
