extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ready_file := OS.get_environment("HEALTH_FIXTURE_READY_FILE")
	var file := FileAccess.open(ready_file, FileAccess.READ)
	if file == null:
		_fail("missing local health fixture")
		return
	var hosts: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	var client := HorizonHttpClient.new()
	root.add_child(client)
	client.initialize(HorizonLogger.new(HorizonLogger.LogLevel.NONE))
	client.connectionTimeoutSeconds = 3

	if not await client._checkHealth(hosts["plain"]):
		_fail("200 OK must pass")
		return
	if not await client._checkHealth(hosts["whitespace"]):
		_fail("trimmed 200 OK must pass")
		return
	if await client._checkHealth(hosts["wrong_status"]):
		_fail("503 OK must fail")
		return
	if await client._checkHealth(hosts["wrong_body"]):
		_fail("200 NOT OK must fail")
		return
	if await client._pingHost(hosts["whitespace"]) < 0:
		_fail("multi-host ping must accept trimmed 200 OK")
		return
	if await client._pingHost(hosts["wrong_body"]) >= 0:
		_fail("multi-host ping must reject wrong body")
		return

	client.apiKey = "local-fixture-key"
	client.hosts = PackedStringArray([hosts["plain"]])
	if not await client.connect_to_server() or client.activeHost != hosts["plain"]:
		_fail("single-host connection must select healthy host")
		return
	client.hosts = PackedStringArray([hosts["wrong_status"], hosts["whitespace"]])
	if not await client.connect_to_server() or client.activeHost != hosts["whitespace"]:
		_fail("multi-host connection must select healthy host")
		return

	print("Godot public-health transport contract passed")
	client.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
