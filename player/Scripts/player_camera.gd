# PlayerCamera.gd

class_name PlayerCamera extends Camera2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	LevelManager.tilemap_bounds_changed.connect(update_limits)
	update_limits(LevelManager.current_tilemap_bounds)


func _process(_delta: float) -> void:
	# Keep the view on whole pixels while the parent CharacterBody2D moves subpixel.
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return
	var parent_pos := parent_node.global_position
	offset = parent_pos.round() - parent_pos


func update_limits(bounds: Array[Vector2]) -> void:
	if bounds == []:
		return

	limit_left = int(bounds[0].x)
	limit_top = int(bounds[0].y)
	limit_right = int(bounds[1].x)
	limit_bottom = int(bounds[1].y)
