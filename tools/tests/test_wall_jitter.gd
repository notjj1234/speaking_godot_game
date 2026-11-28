extends Node
## Walking into walls and props must never make the player body rock back and
## forth (the camera follows the body, so a rocking body shakes the screen).
## Run headless on a scratch copy only (renamed config/name):
##   Godot --headless --path <copy> res://tools/tests/test_wall_jitter.tscn
## For every arena: from each open spot near a collider, hold each of 8
## directions for STEPS physics steps with the real player body and its real
## move_and_slide, and flag any axis that reverses direction twice or more.

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
## One non-boss stage per arena (HordeCurve.arena_index_for).
const STAGES := {"Meadow": 1, "Stone Ruins": 21, "Ashen Camp": 41, "Frozen Hollow": 61}
const GRID := 6.0
const STEPS := 30
## A step smaller than this is settling, not movement.
const MOVE_EPS := 0.25
const MAX_FLIPS := 1
const NEAR := 16.0

var passes := 0
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
	get_tree().current_scene = null
	get_tree().change_scene_to_file(HORDE)
	var horde: Node = null
	for i in 120:
		await get_tree().process_frame
		horde = get_tree().current_scene
		if horde and horde.get("_arena") != null:
			break
	_check("horde scene loads with an arena", horde != null and horde.get("_arena") != null)
	if horde == null or horde.get("_arena") == null:
		_finish()
		return
	var player := PlayerManager.player as CharacterBody2D
	var speed := float((player.get_node("StateMachine/Walk") as Node).get("move_speed"))
	for arena_name in STAGES:
		var stage: int = STAGES[arena_name]
		if stage > 1:
			horde.process_mode = Node.PROCESS_MODE_INHERIT
			horde.call("_jump_to_stage", stage)
			await _frames(45)
		var arena := horde.get("_arena") as HordeArena
		_check("%s: arena loaded" % arena_name, arena != null and arena.display_name == arena_name,
				arena.display_name if arena else "null")
		horde.process_mode = Node.PROCESS_MODE_DISABLED
		horde.call("_clear_horde")
		await get_tree().physics_frame
		_probe(arena_name, player, speed)
	_finish()


func _probe(arena_name: String, player: CharacterBody2D, speed: float) -> void:
	# Not process_mode DISABLED: that removes the body from physics, so
	# move_and_slide would silently stay put. Only stop its own driving.
	var machine := player.get_node("StateMachine") as Node
	var saved_mode := machine.process_mode
	var saved_pos := player.global_position
	var saved_player_mode := player.process_mode
	# The player lives under the (disabled) horde level; keep it in physics.
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	machine.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	var space := player.get_world_2d().direct_space_state
	var fits := _circle_query(player, 10.5)
	var near := _circle_query(player, 10.0 + NEAR)
	var dirs: Array[Vector2] = []
	for i in 8:
		dirs.append(Vector2.RIGHT.rotated(TAU * float(i) / 8.0))
	# The probe only means something if the body really collides here.
	player.global_position = Vector2(320, 60)
	for i in 40:
		player.velocity = Vector2.UP * speed
		player.move_and_slide()
	var stopped_at := player.global_position
	_check("%s: the top wall stops the probe body" % arena_name,
			stopped_at.y > 25.0 and stopped_at.y < 45.0, str(stopped_at))
	var cases := 0
	var bad: Array[String] = []
	var y := 16.0
	while y < 470.0:
		var x := 16.0
		while x < 630.0:
			var at := Vector2(x, y)
			fits.transform = Transform2D(0.0, at)
			near.transform = Transform2D(0.0, at)
			if space.intersect_shape(fits, 1).is_empty() and not space.intersect_shape(near, 1).is_empty():
				for d in dirs:
					cases += 1
					var why := _rocks(player, at, d * speed)
					if why != "":
						bad.append("%s dir %s: %s" % [at, d.snapped(Vector2(0.01, 0.01)), why])
			x += GRID
		y += GRID
	player.velocity = Vector2.ZERO
	player.global_position = saved_pos
	machine.process_mode = saved_mode
	player.process_mode = saved_player_mode
	player.set_physics_process(true)
	_check("%s: probed spots near colliders" % arena_name, cases > 100, str(cases))
	_check("%s: no rocking against walls or props" % arena_name, bad.is_empty(),
			"%d of %d cases, e.g. %s" % [bad.size(), cases, "; ".join(bad.slice(0, 6))])


func _circle_query(player: CharacterBody2D, radius: float) -> PhysicsShapeQueryParameters2D:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.collision_mask = player.collision_mask
	q.exclude = [player.get_rid()]
	return q


## Holds one direction; returns why the body rocked, or "" if it did not.
func _rocks(player: CharacterBody2D, start: Vector2, vel: Vector2) -> String:
	player.global_position = start
	var prev := start
	var last_sign := Vector2.ZERO
	var flips := Vector2.ZERO
	for i in STEPS:
		player.velocity = vel
		player.move_and_slide()
		var step := player.global_position - prev
		prev = player.global_position
		for axis in 2:
			if absf(step[axis]) < MOVE_EPS:
				continue
			var s := signf(step[axis])
			if last_sign[axis] != 0.0 and s != last_sign[axis]:
				flips[axis] += 1.0
			last_sign[axis] = s
	if flips.x > MAX_FLIPS or flips.y > MAX_FLIPS:
		return "flips x%d y%d, ends %s" % [flips.x, flips.y, prev.snapped(Vector2(0.01, 0.01))]
	return ""


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
