extends Node
## Explicit UI actions only. Preserve the reviewed revisions/request IDs after a timeout.

func refresh_groups() -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.groups.getGroups(horizon.auth.getCurrentUser().userId)

func inspect_group(group_id: String) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.groups.getGroup(horizon.auth.getCurrentUser().userId, group_id)

## Render each page with its revision. If it changes, ask for an explicit restart.
## This never drains every page or promises one snapshot across multiple HTTP calls.
func load_member_page(group_id: String, after_user_id: String = "") -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.groups.getMembers(horizon.auth.getCurrentUser().userId, group_id, after_user_id, 50)

func load_pending(group_id: String) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.groups.getPending(horizon.auth.getCurrentUser().userId, group_id)

func create_group(player_revision: Variant, name: String, mode: String = "open", data: Variant = {}) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	# Capture player_revision once when confirming. No client-selected group UUID.
	return await horizon.groups.createGroup(horizon.auth.getCurrentUser().userId, player_revision, name, "", mode, data)

func update_group(group_id: String, revision: Variant, name: String, description: String, mode: String, data: Variant) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	return await horizon.groups.updateGroup(horizon.auth.getCurrentUser().userId, group_id, revision, name, description, mode, data)

## A two-player flow calls invite as the leader/officer, then refreshes as the
## recipient and confirms the current invitation UUID before accept-invite.
## Transfer leadership explicitly before the previous leader leaves. On409/full
## Inbox/timeout, display the error and read state; never substitute intent here.
func confirm_action(action: String, group_id: String, revision: Variant, target: String = "", request_id: String = "", role: String = "") -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var user: String = horizon.auth.getCurrentUser().userId
	match action:
		"join": return await horizon.groups.joinGroup(user, group_id, revision)
		"request": return await horizon.groups.requestJoin(user, group_id, revision)
		"invite": return await horizon.groups.invitePlayer(user, group_id, revision, target)
		"accept-invite": return await horizon.groups.acceptInvite(user, group_id, revision, request_id)
		"decline-invite": return await horizon.groups.declineInvite(user, group_id, revision, request_id)
		"cancel-invite": return await horizon.groups.cancelInvite(user, group_id, revision, target, request_id)
		"accept-request": return await horizon.groups.acceptRequest(user, group_id, revision, target, request_id)
		"decline-request": return await horizon.groups.declineRequest(user, group_id, revision, target, request_id)
		"cancel-request": return await horizon.groups.cancelRequest(user, group_id, revision, request_id)
		"leave": return await horizon.groups.leaveGroup(user, group_id, revision)
		"remove": return await horizon.groups.removeMember(user, group_id, revision, target)
		"role": return await horizon.groups.setMemberRole(user, group_id, revision, target, role)
		"transfer": return await horizon.groups.transferLeadership(user, group_id, revision, target)
		"delete": return await horizon.groups.deleteGroup(user, group_id, revision)
	return _failure("INVALID_GROUP_ACTION")

func _authorized() -> Node:
	var horizon: Node = get_node_or_null("/root/Horizon")
	return horizon if horizon != null and horizon.auth.isSignedIn() else null
func _failure(code: String) -> Dictionary:
	return {"success": false, "data": {}, "errorCode": code, "error": code}
