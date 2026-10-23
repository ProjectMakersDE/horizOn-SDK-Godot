extends Node
## Explicit UI actions only. Preserve the reviewed revisions/request IDs after a timeout.
var _member_context: Dictionary = {}
var _member_pages: Dictionary = {}
var _member_ticket: int = 0

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
func load_member_page(group_id: String, after_user_id: String = "", limit: Variant = null) -> Dictionary:
	var horizon: Node = _authorized()
	if horizon == null: return _failure("SESSION_REQUIRED")
	var context: Dictionary = _member_scope(horizon)
	if context != _member_context:
		_member_pages.clear()
		_member_context = context
	# Null is the sample default, read from the current authenticated own snapshot.
	# An explicit size is passed unchanged to the SDK API and server policy.
	if limit == null:
		var own: Dictionary = horizon.groups.getCurrentGroups()
		if own.get("userId") != context.user or not own.get("limits") is Dictionary:
			return _failure("CURRENT_LIMITS_REQUIRED")
		limit = own.limits.get("memberPageSize")
	if typeof(limit) != TYPE_INT or limit < 1 or limit >= 2147483647: return _failure("INVALID_PAGE")
	var previous: Dictionary = _member_pages.get(group_id, {})
	var cursor: String = after_user_id
	var restarted: bool = false
	if not cursor.is_empty():
		if previous.is_empty(): return _failure("MEMBER_PAGE_RESTART_REQUIRED")
		if previous.limit != limit:
			cursor = ""
			restarted = true
			_member_pages.erase(group_id)
		elif previous.cursor != cursor: return _failure("MEMBER_PAGE_RESTART_REQUIRED")
	_member_ticket += 1
	var ticket: int = _member_ticket
	var result: Dictionary = await horizon.groups.getMembers(context.user, group_id, cursor, limit)
	if context != _member_scope(horizon) or ticket != _member_ticket: return _failure("STALE_RESPONSE")
	if result.get("success", false):
		if not cursor.is_empty() and result.data.revision != previous.revision:
			_member_pages.erase(group_id)
			return _failure("MEMBER_PAGE_RESTART_REQUIRED")
		_member_pages[group_id] = {"limit": limit, "revision": result.data.revision, "cursor": result.data.nextAfterUserId}
		result.restarted = restarted
	return result

func _member_scope(horizon: Node) -> Dictionary:
	return {"user": horizon.auth.getCurrentUser().userId, "project": horizon._http.apiKey, "session": horizon._http.sessionToken, "host": horizon._http.activeHost, "generation": horizon._http.getContextGeneration()}

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
