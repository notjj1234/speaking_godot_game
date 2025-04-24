class_name HeartGUI extends Control

@onready var sprite: Sprite2D = $Sprite2D


var value: int = 2 : # Based on the heart frames, 1 is half hearts, 2 is full hearts
	set(_value):
		value = _value
		update_sprite()



func update_sprite() -> void:
	sprite.frame = value
