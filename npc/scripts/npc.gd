@tool
@icon("res://npc/icons/npc.svg")

class_name NPC extends CharacterBody2D

signal do_behavior_enabled

var state: String = "idle"
var direction: Vector2 = Vector2.DOWN
var direction_name: String = "down"
var do_behavior: bool = true
var _player_in_range: bool = false
## Track that was playing before this NPC's theme took over.
var _music_before: StringName = &""

@export var npc_resource: NPCResource: set = _set_npc_resource

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation: AnimationPlayer = $AnimationPlayer
@onready var interact_area: Area2D = $InteractArea
@onready var prompt_label: Label = $PromptLabel

func _ready() -> void:
	setup_npc()
	if Engine.is_editor_hint():
		return
	if interact_area:
		interact_area.area_entered.connect(_on_area_enter)
		interact_area.area_exited.connect(_on_area_exit)
	if prompt_label:
		prompt_label.visible = false
	do_behavior_enabled.emit()
	pass
	
func _physics_process(_delta: float) -> void:
	if not do_behavior:
		velocity = Vector2.ZERO
	move_and_slide()


func update_animation()-> void:
	animation.play(state + "_" + direction_name)


func update_direction(target_position: Vector2) -> void:
	direction = global_position.direction_to(target_position)
	update_direction_name()
	if direction_name == "side" and direction.x < 0:
		sprite.flip_h = true
	else:
		sprite.flip_h = false
	

func update_direction_name() -> void:
	var threshold: float = 0.45
	if direction.y < -threshold:
		direction_name = "up"
	elif direction.y > threshold:
		direction_name = "down"
	elif direction.x > threshold || direction.x <-threshold:
		direction_name = "side"
	
	pass


func setup_npc() -> void:
	if npc_resource:
		if sprite:
			sprite.texture = npc_resource.sprite
	pass


func _set_npc_resource(_npc: NPCResource) -> void:
	npc_resource = _npc
	setup_npc()


func _on_area_enter(_a: Area2D) -> void:
	_player_in_range = true
	if not PlayerManager.interact_pressed.is_connected(player_interact):
		PlayerManager.interact_pressed.connect(player_interact)
	_set_prompt_visible(true)
	_set_talk_button(true)


func _on_area_exit(_a: Area2D) -> void:
	_player_in_range = false
	if PlayerManager.interact_pressed.is_connected(player_interact):
		PlayerManager.interact_pressed.disconnect(player_interact)
	_set_prompt_visible(false)
	_set_talk_button(false)


func player_interact() -> void:
	if PlayerManager.dialog_open:
		return
	if npc_resource and npc_resource.conversation_id != "":
		var conv := get_tree().get_first_node_in_group("camp_conversation")
		if conv:
			_begin_talk()
			conv.start(npc_resource.conversation_id, npc_resource.portrait, npc_resource.portrait_hframes, _end_talk)
			return
	var dialog := get_node_or_null("/root/DialogSystem")
	if dialog == null or not dialog.has_method("show_dialog"):
		return
	var lines := PackedStringArray()
	var speaker := "Someone"
	var portrait: Texture = null
	var portrait_hframes := 4
	if npc_resource:
		speaker = npc_resource.npc_name
		portrait = npc_resource.portrait
		portrait_hframes = npc_resource.portrait_hframes
		lines = npc_resource.dialog_lines
	if lines.is_empty():
		lines = PackedStringArray(["..."])
	_begin_talk()
	dialog.show_dialog(speaker, portrait, lines, _end_talk, portrait_hframes)


func _begin_talk() -> void:
	_play_theme()
	do_behavior = false
	velocity = Vector2.ZERO
	state = "idle"
	if PlayerManager.player:
		update_direction(PlayerManager.player.global_position)
	update_animation()
	_set_prompt_visible(false)
	_set_talk_button(false)


func _end_talk() -> void:
	_restore_music()
	do_behavior = true
	do_behavior_enabled.emit()
	_set_prompt_visible(_player_in_range)
	if _player_in_range:
		_set_talk_button(true)


## The NPC's own theme while you talk; the level's track comes back after.
func _play_theme() -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music == null or npc_resource == null or npc_resource.music_track == &"":
		return
	_music_before = music.current_track()
	music.play_track(npc_resource.music_track)


func _restore_music() -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music and _music_before != &"":
		music.play_track(_music_before)
	_music_before = &""


func _set_prompt_visible(show_prompt: bool) -> void:
	if prompt_label:
		prompt_label.visible = show_prompt and not PlayerManager.dialog_open


func _set_talk_button(active: bool) -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("set_talk_prompt"):
			node.set_talk_prompt(active)
