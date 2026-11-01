# level_transition.gd

@tool
class_name LevelTransition extends Area2D

enum SIDE {LEFT, RIGHT, TOP, BOTTOM}

@export_file( "*.tscn" ) var level # Only open scene files
@export var target_transition_area: String = "LevelTransition"

@export_category("Collision Area Settings")

@export_range(1, 12, 1, "or_greater") var size: int = 2 : 
	set( _v ):
		size = _v
		_update_area()

@export var side: SIDE = SIDE.LEFT : 
	set( _v ):
		side = _v
		_update_area()
		

@export var snap_to_grid: bool = false:
	set(_v):
		_snap_to_grid()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_area()
	if Engine.is_editor_hint():
		return
	
	monitoring = false
	_place_player()
	
	await LevelManager.level_loaded
	await get_tree().process_frame  # Let the scene settle one frame
	
	await get_tree().create_timer(0.3).timeout  # Delay before enabling transition
	monitoring = true
	body_entered.connect(_player_entered)


func _player_entered(_p: Node2D) -> void:
	# Build/Do something with the level manager
	LevelManager.load_new_level(level, target_transition_area, get_offset())

func _place_player() -> void:
	if name != LevelManager.target_transition:
		return

	var spawn_position = global_position + LevelManager.position_offset
	# Vertical gates (top/bottom) sit in narrow corridors. Carrying the previous
	# level's X/Y offset drops the player into wall tiles mid-maze (level 02).
	if side == SIDE.TOP or side == SIDE.BOTTOM:
		spawn_position.x = global_position.x
	elif side == SIDE.LEFT or side == SIDE.RIGHT:
		spawn_position.y = global_position.y
	PlayerManager.set_player_position(spawn_position)

	# Nudge clear of wall tiles. Player collision radius is ~20px; 8px left them
	# overlapping top/bottom borders (especially level 02 voice-only).
	await get_tree().process_frame
	var nudge := Vector2.ZERO
	const CLEARANCE := 28.0

	match side:
		SIDE.LEFT:
			nudge = Vector2(CLEARANCE, 0)
		SIDE.RIGHT:
			nudge = Vector2(-CLEARANCE, 0)
		SIDE.TOP:
			nudge = Vector2(0, CLEARANCE)
		SIDE.BOTTOM:
			nudge = Vector2(0, -CLEARANCE)

	PlayerManager.set_player_position(PlayerManager.player.global_position + nudge)
	await get_tree().process_frame
	_resolve_wall_overlap(nudge)


func _resolve_wall_overlap(inward: Vector2) -> void:
	var player := PlayerManager.player
	if player == null or not is_instance_valid(player):
		return
	if not player.test_move(player.global_transform, Vector2.ZERO):
		return
	# Step further into the level until the capsule is free of solids.
	var step := inward.normalized() * 8.0
	if step == Vector2.ZERO:
		step = Vector2(0, -8)
	for _i in range(12):
		PlayerManager.set_player_position(player.global_position + step)
		await get_tree().process_frame
		if not player.test_move(player.global_transform, Vector2.ZERO):
			print("✅ Transition spawn resolved clear of walls at ", player.global_position)
			return
	push_warning("⚠️ Transition spawn still overlapping solids at %s" % player.global_position)


func get_offset() -> Vector2:
	var offset: Vector2 = Vector2.ZERO
	var player_pos = PlayerManager.player.global_position
	
	if side == SIDE.LEFT or side == SIDE.RIGHT:
		offset.y = player_pos.y - global_position.y
		offset.x = 16
		if side == SIDE.LEFT:
			offset.x *= -1
	else:
		offset.x = player_pos.x - global_position.x
		offset.y = 16
		if side == SIDE.TOP:
			offset.y *= -1
	return offset


func _update_area() -> void:
	if not is_inside_tree():
		return  # Ensure the node tree is ready

	var new_rect: Vector2 = Vector2(32, 32)
	var new_position: Vector2 = Vector2.ZERO

	if side == SIDE.TOP:
		new_rect.x *= size
		new_position.y -= 16
	elif side == SIDE.BOTTOM:
		new_rect.x *= size
		new_position.y += 16
	elif side == SIDE.LEFT:
		new_rect.y *= size
		new_position.x -= 16
	elif side == SIDE.RIGHT:
		new_rect.y *= size
		new_position.x += 16

	if collision_shape == null:
		collision_shape = get_node("CollisionShape2D")
		if collision_shape == null:
			push_error("CollisionShape2D node not found!")
			return

	collision_shape.shape.size = new_rect
	collision_shape.position = new_position

func _snap_to_grid() -> void:
	position.x = round(position.x / 16) * 16  # Round to nearest whole number then x 16
	position.y = round(position.y / 16) * 16
