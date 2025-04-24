# tutorial_level.gd

extends "res://Levels/Scripts/level.gd"

@onready var player_hud = $PlayerHud

func _ready() -> void:
	super._ready()
	_show_tutorial_popup()

func _show_tutorial_popup() -> void:
	var popup_scene = preload("res://Levels/TutorialItems/tutorial_popup.tscn")
	var popup = popup_scene.instantiate()
	popup.position = player_hud.position + Vector2(0, 80)  # Example offset
	add_child(popup)
	popup.set_text("Welcome! Use the arrow keys or joystick to move.")  # You can customize this!
