# global_player_manager.gd

extends Node

# Preload the player
const PLAYER = preload("res://player/player.tscn")
const INVENTORY_DATA : InventoryData = preload("res://gui/pause_menu/inventory/player_inventory.tres")

signal interact_pressed


var player: Player
var player_spawned: bool = false

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
