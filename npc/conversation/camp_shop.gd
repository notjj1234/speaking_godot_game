class_name CampShop
extends RefCounted
## Prices, refusals and purchases for everything the camp NPCs sell.
## Gems are PlayerManager.bonfire_points.

const ITEM_PATHS := {"apple": "res://items/apple.tres", "potion": "res://items/potion.tres"}
const ITEM_PRICES := {"apple": 2, "potion": 4}
const CARRY_CAP := 3
const DISCOUNT := 1
const STATS := ["vitality", "might", "haste", "crit"]


static func price(offer_id: String) -> int:
	if offer_id in STATS:
		return PlayerManager.upgrade_cost(offer_id)
	if ITEM_PRICES.has(offer_id):
		return ITEM_PRICES[offer_id]
	return 0


static func discounted_price(offer_id: String) -> int:
	return maxi(price(offer_id) - DISCOUNT, 1)


## Returns "", "maxed", "no_sword", "full" or "broke" (checked in that order).
static func refusal(offer_id: String) -> String:
	if offer_id == "haste" and PlayerManager.haste_rank >= PlayerManager.HASTE_MAX:
		return "maxed"
	if offer_id == "crit" and PlayerManager.crit_rank >= PlayerManager.CRIT_MAX:
		return "maxed"
	if offer_id == "sword" and not PlayerManager.has_sword():
		return "no_sword"
	if ITEM_PATHS.has(offer_id) and PlayerManager.item_count(ITEM_PATHS[offer_id]) >= CARRY_CAP:
		return "full"
	if PlayerManager.bonfire_points < price(offer_id):
		return "broke"
	return ""


static func buy(offer_id: String, discounted: bool) -> bool:
	if offer_id in STATS:
		var err: String = PlayerManager.try_upgrade(offer_id, DISCOUNT if discounted else 0)
		if err != "":
			print("⚠️ CampShop: upgrade %s refused: %s" % [offer_id, err])
		return err == ""
	if ITEM_PATHS.has(offer_id):
		return _buy_item(offer_id, discounted_price(offer_id) if discounted else price(offer_id))
	if offer_id == "sword":
		PlayerManager.toggle_sword()
		return true
	print("❌ CampShop: unknown offer '%s'" % offer_id)
	return false


static func _buy_item(offer_id: String, cost: int) -> bool:
	if PlayerManager.bonfire_points < cost:
		return false
	PlayerManager.bonfire_points -= cost
	var item: ItemData = load(ITEM_PATHS[offer_id])
	if not PlayerManager.INVENTORY_DATA.add_item(item):
		PlayerManager.bonfire_points += cost
		print("⚠️ CampShop: inventory full, refunded %d for %s" % [cost, offer_id])
		return false
	SaveManager.save_game()
	print("✅ CampShop: bought %s for %d" % [offer_id, cost])
	return true
