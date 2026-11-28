# vision_area.gd

class_name VisionArea extends Area2D

signal player_entered()
signal player_exited()

const IDLE_COLOR := Color(0.95, 0.84, 0.42, 0.10)
const ALERT_COLOR := Color(0.9, 0.25, 0.2, 0.16)

var _cone: Polygon2D


func _ready() -> void:
	body_entered.connect(_on_body_enter)
	body_exited.connect(_on_body_exit)

	var p = get_parent()
	if p is Enemy:
		p.direction_changed.connect(_on_direction_change)

	_make_cone_indicator()
	player_entered.connect(_on_player_entered)
	player_exited.connect(_on_player_exited)


func _make_cone_indicator() -> void:
	# Visual only: copy the collision cone into a translucent Polygon2D so the
	# player can read the enemy's facing. Slime has no VisionArea at all.
	var collision := find_child("CollisionPolygon2D", false) as CollisionPolygon2D
	if collision == null:
		return
	_cone = Polygon2D.new()
	_cone.polygon = collision.polygon
	_cone.position = collision.position
	_cone.color = IDLE_COLOR
	_cone.z_index = -1  # under the sprite, over the floor
	add_child(_cone)


func hide_cone() -> void:
	if _cone:
		_cone.visible = false


func _on_player_entered() -> void:
	if _cone:
		_cone.color = ALERT_COLOR


func _on_player_exited() -> void:
	if _cone:
		_cone.color = IDLE_COLOR


func _on_body_enter(_b: Node2D) -> void:
	if _b is Player:
		player_entered.emit()
	pass

func _on_body_exit(_b: Node2D) -> void:
	if _b is Player:
		player_exited.emit()
	pass

func _on_direction_change(new_direction: Vector2) -> void:
	match new_direction:
		Vector2.DOWN:
			rotation_degrees = 0
		Vector2.UP:
			rotation_degrees = 180
		Vector2.LEFT:
			rotation_degrees = 90
		Vector2.RIGHT:
			rotation_degrees = -90
		_:
			rotation_degrees = 0
	pass
