extends RefCounted
## Pass an existing authenticated ItemGiftsExample Node with its stable project_id configured.
static func read_one_gift(screen: Node, gift_id: String) -> Dictionary:
	return await screen.read_gift(gift_id)
## Call only from the player's Send confirmation, after read_config/read_inventory succeeded and the
## recipient profile, item and fee were shown.
static func send_reviewed_gift(screen: Node, recipient_id: String, instance_id: String) -> Dictionary:
	var review: Dictionary = screen.review_send(recipient_id, instance_id)
	return await screen.confirm_reviewed_send() if review.success else review
## Call only from the recipient's Decline confirmation after read_one_gift.
static func decline_reviewed_gift(screen: Node, gift_id: String) -> Dictionary:
	var review: Dictionary = screen.review_decline(gift_id)
	return await screen.confirm_reviewed_decline() if review.success else review
# After uncertainty, use screen.retry_pending() / screen.recover_original_operation() with the saved original.
