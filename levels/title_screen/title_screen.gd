# title_screen.gd

extends Control

@onready var tutorial_button := $CenterContainer/VBoxContainer/StartTutorial
@onready var game_button := $CenterContainer/VBoxContainer/StartGame
@onready var touch_tutorial_button := $TouchStartTutorial  # now top-level

func _ready():
	tutorial_button.text = "Start Tutorial"
	game_button.text = "Start Game"

	tutorial_button.mouse_filter = Control.MOUSE_FILTER_STOP
	game_button.mouse_filter = Control.MOUSE_FILTER_STOP

	tutorial_button.pressed.connect(_on_tutorial_pressed)
	game_button.pressed.connect(_on_game_pressed)
	touch_tutorial_button.pressed.connect(_on_tutorial_pressed)

	touch_tutorial_button.visible = true

	# Hide persistent gameplay elements
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		hud.visible = false
		hud.set_process(false)
		hud.set_physics_process(false)

	if has_node("/root/PlayerManager"):
		var player_mgr = get_node("/root/PlayerManager")
		player_mgr.set_process(false)
		player_mgr.set_physics_process(false)
		if player_mgr.has_node("Player"):
			var player = player_mgr.get_node("Player")
			player.visible = false
			player.set_process(false)
			player.set_physics_process(false)

func _process(_delta):
	# Dynamically align invisible Touch button to visible one
	if tutorial_button and touch_tutorial_button:
		var rect = tutorial_button.get_global_rect()
		touch_tutorial_button.global_position = rect.position + rect.size / 2.0
		touch_tutorial_button.shape.extents = rect.size / 2.0

func _on_tutorial_pressed():
	print("▶️ Starting Tutorial...")
	_restore_game_ui()

	# 🛠️ Set transition name manually for initial scene
	LevelManager.target_transition = "PlaygroundTo01"
	LevelManager.position_offset = Vector2.ZERO  # Start at exact spawn

	get_tree().change_scene_to_file("res://Levels/playground.tscn")


func _on_game_pressed():
	print("▶️ Starting Main Game...")
	_restore_game_ui()
	get_tree().change_scene_to_file("res://Levels/ComingSoon.tscn")

func _restore_game_ui():
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		hud.visible = true
		hud.set_process(true)
		hud.set_physics_process(true)

	if has_node("/root/PlayerManager"):
		var player_mgr = get_node("/root/PlayerManager")
		player_mgr.set_process(true)
		player_mgr.set_physics_process(true)
		if player_mgr.has_node("Player"):
			var player = player_mgr.get_node("Player")
			player.visible = true
			player.set_process(true)
			player.set_physics_process(true)
