## ============================================================
## horizOn SDK - Player Profile Data Model
## ============================================================
## The visible part of a player profile: avatar, frame and up to
## three badges. Used by Horizon.playerProfile and on every
## leaderboard entry. The server stores only IDs; the game maps
## them to its own assets and treats unknown IDs as "not set".
## ============================================================
class_name HorizonPlayerProfileData
extends RefCounted

## Selected avatar ID ("" = not set)
var avatarId: String = ""

## Selected frame ID ("" = not set)
var frameId: String = ""

## Displayed badge IDs (0 to 3, order kept)
var badges: Array[String] = []


## Create a profile from a dictionary.
## Null safe: a missing or null dictionary gives an empty profile,
## null IDs become "" and a missing badge list becomes [].
## @param data Dictionary with avatarId, frameId and badges (may be null)
## @return New profile data
static func fromDict(data: Variant) -> HorizonPlayerProfileData:
	var profile := HorizonPlayerProfileData.new()
	if not (data is Dictionary):
		return profile
	var avatar: Variant = data.get("avatarId")
	var frame: Variant = data.get("frameId")
	var badgeList: Variant = data.get("badges")
	profile.avatarId = avatar if avatar is String else ""
	profile.frameId = frame if frame is String else ""
	if badgeList is Array:
		for badge in badgeList:
			if badge is String and not badge.is_empty():
				profile.badges.append(badge)
	return profile


## Convert to dictionary (same field names as the JSON API).
## @return Dictionary representation
func toDict() -> Dictionary:
	return {
		"avatarId": avatarId,
		"frameId": frameId,
		"badges": badges.duplicate()
	}


## Check whether an avatar is set.
## @return True if avatarId is not empty
func hasAvatar() -> bool:
	return not avatarId.is_empty()


## Check whether a frame is set.
## @return True if frameId is not empty
func hasFrame() -> bool:
	return not frameId.is_empty()
