class_name CampFire
extends Node2D
## The camp's fire: walk up and press E / Talk to rest, then say (or tap)
## Fight on, Journal or Title. The choices run through the camp's
## CampConversation ("fire" lines); Camp handles the chosen action.

const PORTRAIT := preload("res://levels/endless_horde/camp/camp_fire_portrait.tres")

var _player_in_range := false
var _flicker: Tween = null

@onready var interact_area: Area2D = $InteractArea
@onready var prompt_label: Label = $PromptLabel
@onready var flame: Sprite2D = $Flame


func _ready() -> void:
	interact_area.area_entered.connect(_on_area_enter)
	interact_area.area_exited.connect(_on_area_exit)
	prompt_label.visible = false
	_start_flicker()


func _exit_tree() -> void:
	if PlayerManager.interact_pressed.is_connected(player_interact):
		PlayerManager.interact_pressed.disconnect(player_interact)


func player_interact() -> void:
	if PlayerManager.dialog_open:
		return
	var conv := get_tree().get_first_node_in_group("camp_conversation")
	if conv == null:
		print("⚠️ CampFire: no camp conversation in this scene")
		return
	_set_prompt(false)
	conv.start("fire", PORTRAIT, 1, _on_talk_end)


func _on_talk_end() -> void:
	_set_prompt(_player_in_range)


func _on_area_enter(_a: Area2D) -> void:
	_player_in_range = true
	if not PlayerManager.interact_pressed.is_connected(player_interact):
		PlayerManager.interact_pressed.connect(player_interact)
	_set_prompt(true)


func _on_area_exit(_a: Area2D) -> void:
	_player_in_range = false
	if PlayerManager.interact_pressed.is_connected(player_interact):
		PlayerManager.interact_pressed.disconnect(player_interact)
	_set_prompt(false)


func _set_prompt(active: bool) -> void:
	prompt_label.visible = active and not PlayerManager.dialog_open
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("set_talk_prompt"):
			node.set_talk_prompt(active)


func _start_flicker() -> void:
	_flicker = create_tween().set_loops()
	_flicker.tween_property(flame, "modulate", Color(1.15, 0.95, 0.8, 1), 0.18)
	_flicker.parallel().tween_property(flame, "scale", Vector2(1.04, 1.06), 0.18)
	_flicker.tween_property(flame, "modulate", Color(1, 1, 1, 1), 0.22)
	_flicker.parallel().tween_property(flame, "scale", Vector2.ONE, 0.22)
