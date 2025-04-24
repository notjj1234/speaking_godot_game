class_name Plant extends Node2D

@onready var hit_box: HitBox = $HitBox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$HitBox.damaged.connect(take_damage)
	pass # Replace with function body.


func take_damage(_damage: HurtBox) -> void:
	queue_free()
	pass
