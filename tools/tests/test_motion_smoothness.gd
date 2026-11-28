extends Node
## Walking must look smooth and play the same on any display (60/90/120/144 Hz,
## variable refresh), not just on one machine. Run headless on a scratch copy
## only (renamed config/name):
##   Godot --headless --path <copy> res://tools/tests/test_motion_smoothness.tscn
## * Physics stays at a fixed 60 Hz with physics interpolation on, and no frame
##   cap, so every device draws at its own rate between ticks. (Godot 4.7 has no
##   2D get_global_transform_interpolated and headless draws nothing, so drawn
##   smoothness is measured from Movie Maker frames instead; see the ledger.)
## * The camera adds no offset of its own (the engine interpolates and snaps).
## * Per-frame smoothing (enemy turning, knockback slowdown) gives the same
##   result per second at any frame rate.

const HORDE := "res://levels/endless_horde/endless_horde.tscn"

var passes := 0

## Records engine errors (e.g. get_viewport_rect outside the tree).
class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append(code if rationale == "" else rationale)

var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_check_frame_rate_math()
	_check("physics interpolation is on", ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	_check("physics tick stays 60 Hz", Engine.physics_ticks_per_second == 60, str(Engine.physics_ticks_per_second))
	_check("no frame cap in the project", int(ProjectSettings.get_setting("application/run/max_fps", 0)) == 0)
	# Snapping hero and camera separately made the hero rock +-1 px while followed.
	_check("transform pixel snap is off", not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", true))

	get_tree().current_scene = null
	get_tree().change_scene_to_file(HORDE)
	var horde: Node = null
	for i in 120:
		await get_tree().process_frame
		horde = get_tree().current_scene
		if horde and horde.get("_arena") != null:
			break
	_check("horde scene loads", horde != null and horde.get("_arena") != null)
	if horde == null or horde.get("_arena") == null:
		_finish()
		return
	await _check_camera_offset()
	await _check_camera_off_tree()
	_finish()


## Headless draws at 640x480, where the arena camera is pinned on both axes,
## so test the camera script itself on an unbounded parent.
func _check_camera_offset() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var cam := PlayerCamera.new()
	holder.add_child(cam)
	# Free-follow: no arena bounds, limits far away (nothing pins an axis).
	cam.set("_bounds", [] as Array[Vector2])
	cam.zoom = Vector2.ONE
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	var offsets := {}
	for i in 40:
		holder.global_position = Vector2(100.0 + 1.37 * float(i), 200.0 + 0.83 * float(i))
		await get_tree().process_frame
		offsets[cam.offset] = true
	holder.queue_free()
	_check("camera adds no offset of its own while following", offsets.size() == 1 and offsets.has(Vector2.ZERO),
			str(offsets.keys().slice(0, 6)))


## Bounds can arrive while the player (and its camera) is out of the tree
## during a level change. That must not touch the viewport (engine error) and
## must still apply once the camera is back.
func _check_camera_off_tree() -> void:
	var cam := PlayerCamera.new()
	var bounds: Array[Vector2] = [Vector2(0, 0), Vector2(640, 480)]
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	cam.update_limits(bounds)
	OS.remove_logger(catcher)
	_check("camera takes bounds while out of the tree, no engine error",
			not cam.is_inside_tree() and cam.get("_bounds") == bounds and catcher.errors.is_empty(), str(catcher.errors))
	var holder := Node2D.new()
	add_child(holder)
	holder.add_child(cam)
	await _frames(3)
	_check("camera applies those bounds once back in the tree", cam.limit_right == 640 and cam.limit_bottom == 480,
			"%d %d" % [cam.limit_right, cam.limit_bottom])
	holder.queue_free()


## Per-frame smoothing must not depend on the frame rate.
func _check_frame_rate_math() -> void:
	var headings := {}
	var speeds := {}
	for fps in [30, 60, 120, 144]:
		var dt := 1.0 / float(fps)
		# Chase turn: heading right, target straight down.
		# 1/6 s is a whole number of frames at every rate tested.
		var n: int = fps / 6
		var d := Vector2.RIGHT
		for i in n:
			d = d.lerp(Vector2.DOWN, State.turn_weight(0.25, dt)).normalized()
		headings[fps] = rad_to_deg(d.angle())
		# Knockback slowdown (player stun: decelerate_speed 10).
		var v := 200.0
		for i in n:
			v *= State.decay_factor(10.0, dt)
		speeds[fps] = v
	var h_spread: float = headings.values().max() - headings.values().min()
	_check("chase turn is the same at 30/60/120/144 fps", h_spread <= 2.0, str(headings))
	var s_spread: float = (speeds.values().max() - speeds.values().min()) / speeds[60]
	_check("knockback slowdown is the same at 30/60/120/144 fps", s_spread <= 0.01, str(speeds))
	_check("60 fps turn keeps today's 0.25 per frame", is_equal_approx(State.turn_weight(0.25, 1.0 / 60.0), 0.25))
	_check("60 fps slowdown keeps today's v -= v*k*dt", is_equal_approx(State.decay_factor(10.0, 1.0 / 60.0), 1.0 - 10.0 / 60.0))
	var slow: float = State.decay_factor(10.0, 0.2)
	_check("a long frame never reverses velocity", slow >= 0.0 and slow < 1.0, str(slow))


func _finish() -> void:
	Engine.max_fps = 0
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
