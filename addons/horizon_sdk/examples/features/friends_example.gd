extends Node
## Call from explicit UI actions after restoring the original authenticated player.
## A stale Inbox notice is a hint: accept/decline/cancel use the current request UUID.

func refresh_friends() -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var result: Dictionary = await horizon.friends.getFriends(horizon.auth.getCurrentUser().userId)
	if result.success:
		print("Public friend code: %s" % result.data.friendCode)
		for friend: Dictionary in result.data.friends:
			# null means no retained login is known. This is never an online/offline flag.
			print("Friend %s; last known login: %s" % [friend.userId, friend.lastActiveAt])
	return result

func find_exact(query: String) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.friends.findPlayer(horizon.auth.getCurrentUser().userId, query)

## Capture these original arguments when the user confirms the rendered snapshot.
## After timeout/409 call refresh_friends and ask the user to reconcile; never silently
## replace revision/request_id and repeat. The SDK also sends each command only once.
func change_relationship(action: String, target: String, revision: Variant, request_id: String = "") -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var user_id: String = horizon.auth.getCurrentUser().userId
	match action:
		"request": return await horizon.friends.sendRequest(user_id, target, revision)
		"accept": return await horizon.friends.acceptRequest(user_id, target, revision, request_id)
		"decline": return await horizon.friends.declineRequest(user_id, target, revision, request_id)
		"cancel": return await horizon.friends.cancelRequest(user_id, target, revision, request_id)
		"remove": return await horizon.friends.removeFriend(user_id, target, revision)
		"block": return await horizon.friends.blockPlayer(user_id, target, revision)
		"unblock": return await horizon.friends.unblockPlayer(user_id, target, revision)
	return _failure("INVALID_REQUEST")

func _authorized() -> Node:
	var horizon: Node = get_node_or_null("/root/Horizon")
	return horizon if horizon != null and horizon.auth.isSignedIn() else null

func _failure(code: String) -> Dictionary:
	return {"success": false, "data": {}, "errorCode": code, "error": code}
