## ============================================================
## horizOn SDK - Leaderboard Entry Model
## ============================================================
## Data class representing a single leaderboard entry.
## ============================================================
class_name HorizonLeaderboardEntry
extends RefCounted

## Position in the leaderboard (1-indexed)
var position: int = 0

## Username of the player
var username: String = ""

## Score value
var score: int = 0


## Create a leaderboard entry from a dictionary.
## Safely handles null values from server responses.
## @param data Dictionary containing entry data
## @return New leaderboard entry
static func fromDict(data: Dictionary) -> HorizonLeaderboardEntry:
	var entry := HorizonLeaderboardEntry.new()
	var pos = data.get("position")
	var user = data.get("username")
	var sc = data.get("score")
	entry.position = int(pos) if pos != null else 0
	entry.username = user if user is String else ""
	entry.score = int(sc) if sc != null else 0
	return entry


## Create an array of leaderboard entries from an array of dictionaries.
## @param entries Array of entry dictionaries
## @return Array of HorizonLeaderboardEntry
static func fromArray(entries: Array) -> Array[HorizonLeaderboardEntry]:
	var result: Array[HorizonLeaderboardEntry] = []
	for entry_data in entries:
		if entry_data is Dictionary:
			result.append(fromDict(entry_data))
	return result


## Convert to dictionary.
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"position": position,
		"username": username,
		"score": score
	}
