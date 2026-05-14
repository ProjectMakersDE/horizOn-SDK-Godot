## ============================================================
## horizOn SDK - News Minimal Example
## ============================================================
## What it does: connects, then loads the latest news entries and
## prints their titles and release dates.
## App key: imported via Project > Tools > horizOn: Import Config.
## Start path: attach this script to a Node and run the scene, or
## run it via the shared examples runner (features_runner.tscn).
## Expected output: a count of news entries followed by one line
## per entry, or a clear error line on failure.
## ============================================================
extends Node


func _ready() -> void:
	var horizon := get_node_or_null("/root/Horizon")
	if horizon == null:
		push_error("Horizon autoload not found. Enable the horizOn SDK plugin.")
		return

	# Error handling via signals.
	horizon.news.news_load_failed.connect(func(error: String):
		push_error("News load failed: %s" % error))

	var connected: bool = await horizon.connect_to_server()
	if not connected:
		push_error("Could not connect to any horizOn server.")
		return

	# News does not require sign-in.
	# loadNews(limit, language_code, use_cache) returns an empty array on failure.
	var entries: Array[HorizonNewsEntry] = await horizon.news.loadNews(10, "", false)
	if entries.is_empty():
		print("No news entries available.")
		return

	print("Loaded %d news entries:" % entries.size())
	for entry in entries:
		print("  [%s] %s" % [entry.releaseDate, entry.title])
