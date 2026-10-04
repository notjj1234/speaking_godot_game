# global_player_manager.gd

extends Node

# Preload the player
const PLAYER = preload("res://player/player.tscn")
const INVENTORY_DATA : InventoryData = preload("res://gui/pause_menu/inventory/player_inventory.tres")

const GEM_PATH := "res://items/gem.tres"
const SWORD_PATH := "res://items/sword.tres"
const HORDE_BASE_HP := 20
const NORMAL_HP := 6
const BASE_WALK_SPEED := 100.0
const BASE_ATTACK_DAMAGE := 1
const HASTE_MAX := 5
const CRIT_MAX := 5

signal interact_pressed


var player: Player
var player_spawned: bool = false
var dialog_open: bool = false
var voice_only: bool = false

var bonfire_points: int = 0
var vitality_rank: int = 0
var might_rank: int = 0
var haste_rank: int = 0
var crit_rank: int = 0
var sword_equipped: bool = false
var last_attack_was_crit: bool = false

func _ready() -> void:
	add_player_instance()
	await get_tree().create_timer(0.2).timeout
	player_spawned = true

func add_player_instance() -> void:
	player = PLAYER.instantiate()
	add_child(player)

func set_health(hp: int, max_hp: int) -> void:
	player.max_hp = max_hp
	player.hp = hp
	player.update_hp( 0 )
	

func set_player_position(_new_pos: Vector2) -> void:
	player.global_position = _new_pos

func set_as_parent(_p: Node2D) -> void:
	if player.get_parent():
		player.get_parent().remove_child(player)
	_p.add_child(player)
	pass
	

func unparent_player(_p: Node2D) -> void:
	_p.remove_child(player)


func horde_max_hp() -> int:
	return HORDE_BASE_HP + 2 * vitality_rank


func bonfire_save_dict() -> Dictionary:
	return {
		"points": bonfire_points,
		"vitality": vitality_rank,
		"might": might_rank,
		"haste": haste_rank,
		"crit": crit_rank,
		"sword_equipped": sword_equipped,
	}


func apply_saved_bonfire(data: Dictionary) -> void:
	bonfire_points = int(data.get("points", 0))
	vitality_rank = maxi(int(data.get("vitality", 0)), 0)
	might_rank = maxi(int(data.get("might", 0)), 0)
	haste_rank = clampi(int(data.get("haste", 0)), 0, HASTE_MAX)
	crit_rank = clampi(int(data.get("crit", 0)), 0, CRIT_MAX)
	sword_equipped = bool(data.get("sword_equipped", false))
	if sword_equipped and not has_sword():
		sword_equipped = false
	apply_combat_modifiers()


func attack_damage() -> int:
	return BASE_ATTACK_DAMAGE + might_rank


func crit_chance() -> float:
	# Rank 0 still crits, so practice swings can show one. Each rank adds 10%.
	return clampf(0.25 + 0.10 * float(crit_rank), 0.0, 0.75)


func roll_attack_damage() -> int:
	var damage := attack_damage()
	last_attack_was_crit = randf() < crit_chance()
	if last_attack_was_crit:
		return damage * 2
	return damage


func apply_combat_modifiers() -> void:
	if player == null:
		return
	var hurt: HurtBox = player.get_node_or_null("Sprite2D/AttackHurtBox")
	if hurt:
		hurt.damage = BASE_ATTACK_DAMAGE + might_rank
	var walk := player.get_node_or_null("StateMachine/Walk")
	if walk:
		walk.set("move_speed", BASE_WALK_SPEED * (1.0 + 0.08 * float(haste_rank)))
	if player.has_method("refresh_weapon_sprite"):
		player.refresh_weapon_sprite()


func revive_for_horde() -> void:
	if player == null:
		return
	player.invulnerable = false
	if player.hit_box:
		player.hit_box.monitoring = true
	set_health(horde_max_hp(), horde_max_hp())
	apply_combat_modifiers()


func convert_gems_to_points() -> void:
	var gem_slots: Array[SlotData] = []
	for slot in INVENTORY_DATA.slots:
		if slot == null or slot.item_data == null:
			continue
		if slot.item_data.resource_path != GEM_PATH:
			continue
		gem_slots.append(slot)
	var gained := 0
	for slot in gem_slots:
		gained += slot.quantity
		slot.quantity = 0
	bonfire_points += gained


func upgrade_cost(stat: String) -> int:
	return 2 + _rank_for(stat)


func try_upgrade(stat: String) -> String:
	var rank := _rank_for(stat)
	if stat == "haste" and rank >= HASTE_MAX:
		return "Speed is maxed"
	if stat == "crit" and rank >= CRIT_MAX:
		return "Crit is maxed"
	var cost := 2 + rank
	if bonfire_points < cost:
		return "Not enough gems"
	bonfire_points -= cost
	_set_rank(stat, rank + 1)
	if stat == "vitality":
		set_health(horde_max_hp(), horde_max_hp())
	apply_combat_modifiers()
	SaveManager.save_game()
	return ""


func has_sword() -> bool:
	for slot in INVENTORY_DATA.slots:
		if slot == null or slot.item_data == null:
			continue
		if slot.item_data.resource_path == SWORD_PATH or slot.item_data.equip_id == "sword":
			return true
	return false


func toggle_sword() -> void:
	if not has_sword():
		sword_equipped = false
		apply_combat_modifiers()
		return
	sword_equipped = not sword_equipped
	apply_combat_modifiers()
	SaveManager.save_game()


func _rank_for(stat: String) -> int:
	match stat:
		"vitality":
			return vitality_rank
		"might":
			return might_rank
		"haste":
			return haste_rank
		"crit":
			return crit_rank
	return 0


func _set_rank(stat: String, value: int) -> void:
	match stat:
		"vitality":
			vitality_rank = value
		"might":
			might_rank = value
		"haste":
			haste_rank = value
		"crit":
			crit_rank = value
