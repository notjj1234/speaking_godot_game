extends Node2D
## CampShop / consumable regressions. Run headless on a scratch copy only (it
## writes user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_camp_shop.tscn
## Review Focus 4: a full inventory refunds the gems instead of eating them.

const APPLE := "res://items/apple.tres"
const POTION := "res://items/potion.tres"

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var inv := PlayerManager.INVENTORY_DATA
	var saved_inv: Array = inv.get_save_data()
	var saved := [PlayerManager.bonfire_points, PlayerManager.vitality_rank, PlayerManager.might_rank,
		PlayerManager.haste_rank, PlayerManager.crit_rank]
	var saved_hp := [PlayerManager.player.hp, PlayerManager.player.max_hp]

	inv.parse_save_data([])
	PlayerManager.bonfire_points = 20
	for stat in ["vitality", "might", "haste", "crit"]:
		PlayerManager._set_rank(stat, 0)

	_test_upgrade_prices()
	_test_apple_cap()
	_test_refusals()
	_test_full_inventory_refunds()
	_test_heals()

	inv.parse_save_data(saved_inv)
	PlayerManager.bonfire_points = saved[0]
	PlayerManager.vitality_rank = saved[1]
	PlayerManager.might_rank = saved[2]
	PlayerManager.haste_rank = saved[3]
	PlayerManager.crit_rank = saved[4]
	PlayerManager.set_health(saved_hp[0], saved_hp[1])
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_upgrade_prices() -> void:
	_check("might price", CampShop.price("might") == 2, "got %d" % CampShop.price("might"))
	_check("might discounted", CampShop.discounted_price("might") == 1)
	var ok := CampShop.buy("might", true)
	_check("discounted buy succeeds", ok)
	_check("discounted buy ranks up", PlayerManager.might_rank == 1, "rank %d" % PlayerManager.might_rank)
	_check("discounted buy pays 1", PlayerManager.bonfire_points == 19, "points %d" % PlayerManager.bonfire_points)
	_check("price follows rank", CampShop.price("might") == 3)


func _test_apple_cap() -> void:
	for i in 3:
		CampShop.buy("apple", false)
	_check("three apples held", PlayerManager.item_count(APPLE) == 3, "count %d" % PlayerManager.item_count(APPLE))
	_check("three apples paid", PlayerManager.bonfire_points == 13, "points %d" % PlayerManager.bonfire_points)
	_check("apple refused at cap", CampShop.refusal("apple") == "full", "got '%s'" % CampShop.refusal("apple"))
	PlayerManager.INVENTORY_DATA.add_item(load(APPLE))
	_check("drops ignore the cap", PlayerManager.item_count(APPLE) == 4)
	_check("potion price", CampShop.price("potion") == 4)


func _test_refusals() -> void:
	PlayerManager.haste_rank = 5
	_check("haste maxed", CampShop.refusal("haste") == "maxed", "got '%s'" % CampShop.refusal("haste"))
	PlayerManager.haste_rank = 0
	var keep := PlayerManager.bonfire_points
	PlayerManager.bonfire_points = 1
	_check("vitality broke", CampShop.refusal("vitality") == "broke", "got '%s'" % CampShop.refusal("vitality"))
	_check("pricier stat broke too", CampShop.refusal("might") == "broke")
	PlayerManager.bonfire_points = keep
	_check("no refusal when affordable", CampShop.refusal("crit") == "")


func _test_full_inventory_refunds() -> void:
	var inv := PlayerManager.INVENTORY_DATA
	inv.parse_save_data([])
	for i in inv.slots.size():
		var dummy := ItemData.new()
		dummy.name = "Dummy %d" % i
		inv.add_item(dummy)
	PlayerManager.bonfire_points = 10
	var before := CampShop.refusal("potion")
	var ok := CampShop.buy("potion", false)
	_check("full inventory: buy fails", not ok)
	_check("full inventory: gems refunded", PlayerManager.bonfire_points == 10, "points %d" % PlayerManager.bonfire_points)
	_check("full inventory: refusal unchanged", CampShop.refusal("potion") == before)
	inv.parse_save_data([])


func _test_heals() -> void:
	PlayerManager.set_health(10, 20)
	var used: bool = load(APPLE).use()
	_check("apple use consumes", used)
	_check("apple heals 4", PlayerManager.player.hp == 14, "hp %d" % PlayerManager.player.hp)
	PlayerManager.set_health(5, 20)
	load(POTION).use()
	_check("potion heals 10", PlayerManager.player.hp == 15, "hp %d" % PlayerManager.player.hp)
