@tool

class_name PatrolLocation extends Node2D

@export var wait_time: float = 0.0:
	set(v):
		wait_time = v
		_update_wait_time_label()

var target_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	target_position = global_position
	if Engine.is_editor_hint():
		return
	$Sprite2D.queue_free()
	pass

func update_label(_s:String) -> void:
	$Sprite2D/Label.text = _s
	
	pass



func _update_wait_time_label() -> void:
	if Engine.is_editor_hint():
		$Sprite2D/Label2.text = "wait: " + str(snappedf(wait_time, 0.1)) + "s"
	pass
