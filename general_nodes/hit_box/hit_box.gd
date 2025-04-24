# hit_box.gd

class_name HitBox extends Area2D

signal damaged (hurt_box: HurtBox)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func take_damage(hurt_box: HurtBox) -> void:
	if hurt_box is HurtBox:
		damaged.emit(hurt_box)
