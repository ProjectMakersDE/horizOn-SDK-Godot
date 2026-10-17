extends RefCounted
## Pass an existing authenticated MarketplaceExample Node with its stable project_id configured.
static func read_one_listing(screen: Node, listing_id: String) -> Dictionary:
	return await screen.read_listing(listing_id)
## Call only from the player's Buy confirmation after displaying the successfully read listing.
static func buy_reviewed_listing(screen: Node, listing_id: String) -> Dictionary:
	var review: Dictionary = screen.review_buy(listing_id)
	return await screen.confirm_reviewed_trade() if review.success else review
# After uncertainty, use screen.retry_pending() / screen.recover_original_operation() with the saved original.
