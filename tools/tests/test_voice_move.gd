extends Node2D
## F14 regression: a voice "move" step must collide with walls and freeze while
## the tree is paused (it used to set position directly, 32 times, on a timer
## that ignores pause). Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_voice_move.tscn

const WALL_LAYER := 16  # "Walls": the player's collision mask

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wall_at(x: float, y: float) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = WALL_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 400)
	shape.shape = rect
	wall.add_child(shape)
	wall.global_position = Vector2(x, y)
	add_child(wall)
	return wall


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var player: Player = PlayerManager.player
	PlayerManager.voice_only = false
	player.global_position = Vector2(2000, 2000)
	await get_tree().physics_frame

	var start := player.global_position
	await player.move_with_animation(Vector2.LEFT)
	var moved := start.x - player.global_position.x
	_check("open floor: one step moves about 128 px", absf(moved - 128.0) < 12.0, "moved %.1f" % moved)
	_check("step ends standing still", player.velocity == Vector2.ZERO or player._continuous_move_direction == Vector2.ZERO)

	var wall_x := player.global_position.x + 60.0
	_wall_at(wall_x, player.global_position.y)
	await get_tree().physics_frame
	await player.move_with_animation(Vector2.RIGHT)
	_check("wall: step stops before the wall", player.global_position.x < wall_x - 8.0,
			"x=%.1f wall=%.1f" % [player.global_position.x, wall_x])

	player.global_position = Vector2(3000, 3000)
	await get_tree().physics_frame
	# Not awaited: the step must still be running when the tree pauses.
	player.move_with_animation.call_deferred(Vector2.DOWN)
	for i in 5:
		await get_tree().physics_frame
	get_tree().paused = true
	var frozen_at := player.global_position
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check("paused: the step does not move the player", player.global_position.distance_to(frozen_at) < 0.5,
			"drifted %.1f" % player.global_position.distance_to(frozen_at))
	get_tree().paused = false
	await get_tree().create_timer(2.5, true, false, true).timeout
	_check("step ends after the pause", player._continuous_move_direction == Vector2.ZERO)

	# Training's voice lesson listens for this signal.
	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	await get_tree().process_frame
	var heard: Array[String] = []
	controls.voice_command_executed.connect(func(c: String): heard.append(c))
	controls._execute_command("attack")
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("voice command signal fires", heard == ["attack"], str(heard))
	controls.queue_free()

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
