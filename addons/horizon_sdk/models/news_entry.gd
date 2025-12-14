## ============================================================
## horizOn SDK - News Entry Model
## ============================================================
## Data class representing a news article from the server.
## ============================================================
class_name HorizonNewsEntry
extends RefCounted

## Unique identifier for the news entry
var id: String = ""

## Title of the news article
var title: String = ""

## Message/content of the news article
var message: String = ""

## Release date (ISO 8601 format)
var releaseDate: String = ""

## Language code (e.g., "en", "de")
var languageCode: String = ""


## Create a news entry from a dictionary.
## Safely handles null values from server responses.
## @param data Dictionary containing news data
## @return New news entry
static func fromDict(data: Dictionary) -> HorizonNewsEntry:
	var entry := HorizonNewsEntry.new()
	# Safely get string values (handle null)
	var safeStr = func(key: String) -> String:
		var val = data.get(key)
		return val if val is String else ""
	entry.id = safeStr.call("id")
	entry.title = safeStr.call("title")
	entry.message = safeStr.call("message")
	entry.releaseDate = safeStr.call("releaseDate")
	entry.languageCode = safeStr.call("languageCode")
	return entry


## Create an array of news entries from an array of dictionaries.
## @param entries Array of entry dictionaries
## @return Array of HorizonNewsEntry
static func fromArray(entries: Array) -> Array[HorizonNewsEntry]:
	var result: Array[HorizonNewsEntry] = []
	for entry_data in entries:
		if entry_data is Dictionary:
			result.append(fromDict(entry_data))
	return result


## Convert to dictionary.
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"message": message,
		"releaseDate": releaseDate,
		"languageCode": languageCode
	}
