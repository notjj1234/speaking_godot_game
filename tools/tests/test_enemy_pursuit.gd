extends Node
## Ordinary horde enemies: they path around walls and props while chasing, and
## when they lose sight they walk to where they last saw the player and look
## around before going back to wandering. Run headless on a scratch copy only:
##   Godot --headless --path <copy> res://tools/tests/test_enemy_pursuit.tscn

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const KINDS := {
	"goblin": "res://enemies/goblin/goblin.tscn",
	"skeleton": "res://enemies/skeleton/skeleton.tscn",
	"orc": "res://enemies/orc/orc.tscn",
	"bandit": "res://enemies/bandit/bandit.tscn",
	"beetle": "res://enemies/beetle/beetle.tscn",
}

var passes := 0
var failures := 0
var horde: Node
var player: Player
var arena: HordeArena
var holder: Node2D


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	get_tree().change_scene_to_file(HORDE)
	for i in 120:
		await get_tree().process_frame
		horde = get_tree().current_scene
		if horde and horde.get("_arena") != null:
			break
	_check("horde scene loads", horde != null and horde.get("_arena") != null)
	if horde == null or horde.get("_arena") == null:
		_finish()
		return
	# Stone Ruins: the arena with the most walls and props.
	horde.call("_jump_to_stage", 21)
	for i in 30:
		await get_tree().physics_frame
	horde.call("_clear_horde")
	horde.set("_stage_active", false)
	arena = horde.get("_arena")
	player = PlayerManager.player
	player.get_node("StateMachine").process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	player.invulnerable = true
	holder = Node2D.new()
	holder.y_sort_enabled = true
	horde.add_child(holder)
	for kind in KINDS:
		await _test_around_prop(kind)
	for kind in ["goblin", "skeleton", "orc"]:
		await _test_search(kind)
	await _test_search_spots_player("goblin")
	_finish()


func _spawn(kind: String, pos: Vector2) -> Enemy:
	var e := (load(KINDS[kind]) as PackedScene).instantiate() as Enemy
	holder.add_child(e)
	_place(e, pos)
	await get_tree().physics_frame
	return e


func _chase(e: Enemy) -> EnemyStateChase:
	return e.get_node_or_null("EnemyStateMachine/Chase") as EnemyStateChase


## Chasing: never stuck on the prop between it and the player.
func _test_around_prop(kind: String) -> void:
	var setup := _prop_setup()
	_check("%s: found a prop" % kind, not setup.is_empty())
	if setup.is_empty():
		return
	var rect: Rect2 = setup["rect"]
	_place(player, setup["player"])
	var e: Enemy = await _spawn(kind, setup["enemy"])
	var chase := _chase(e)
	_check("%s: has a Chase state" % kind, chase != null)
	if chase == null:
		e.queue_free()
		return
	# The random "chaos" hesitation shares is_bouncing; switch it off so the
	# check below sees wall bounces only.
	e.chaos_pauses_enabled = false
	e.state_machine.change_state(chase)
	var got_round := false
	var bounced := false
	for i in 480:
		chase.set("_can_see_player", true)  # pathing only, not the vision cone
		if e.state_machine.current_state != chase and not (e.state_machine.current_state is EnemyStateStun):
			e.state_machine.change_state(chase)
		await get_tree().physics_frame
		bounced = bounced or e.is_bouncing
		var a := e.global_position
		var b := player.global_position
		if a.distance_to(b) <= 90.0 and not _segment_hits(a, b, rect.grow(2.0)):
			got_round = true
			break
	_check("%s: paths around a prop while chasing" % kind, got_round,
			"stuck at %s, player %s, prop %s" % [e.global_position.round(), player.global_position.round(), rect])
	_check("%s: no random wall bounce while chasing" % kind, not bounced)
	e.queue_free()
	await get_tree().physics_frame


## Losing sight: go to the last-seen spot, look around, then give up.
func _test_search(kind: String) -> void:
	var spot := _open_spot(Vector2.ZERO)
	var last_seen := spot + Vector2(70, 0)
	_place(player, last_seen)
	var e: Enemy = await _spawn(kind, spot)
	var chase := _chase(e)
	e.state_machine.change_state(chase)
	chase.set("_can_see_player", true)
	for i in 10:
		await get_tree().physics_frame
	# The player vanishes far away, out of any cone.
	var far := _far_spot(spot, 280.0)
	_place(player, far)
	chase.set("_can_see_player", false)
	var searched := false
	var reached := false
	var looks := {}
	var gave_up := false
	for i in 600:
		await get_tree().physics_frame
		var st := e.state_machine.current_state
		if st is EnemyStateSearch:
			searched = true
			if e.global_position.distance_to(last_seen) <= 16.0:
				reached = true
			if reached:
				looks[e.cardinal_direction] = true
		elif searched and (st is EnemyStateIdle or st is EnemyStateWander):
			gave_up = true
			break
		elif not searched and (st is EnemyStateIdle or st is EnemyStateWander):
			break
	_check("%s: losing sight starts a search, not idle" % kind, searched)
	_check("%s: search walks to the last-seen spot" % kind, reached, "at %s, spot %s" % [e.global_position.round(), last_seen.round()])
	_check("%s: search looks around there" % kind, looks.size() >= 3, str(looks.keys()))
	_check("%s: then goes back to idle/wander" % kind, gave_up)
	e.queue_free()
	await get_tree().physics_frame


## Searching: seeing the player again goes straight back to chasing.
func _test_search_spots_player(kind: String) -> void:
	var spot := _open_spot(Vector2(0, 40))
	_place(player, _far_spot(spot, 280.0))
	var e: Enemy = await _spawn(kind, spot)
	var search := e.call("_ensure_search") as EnemyStateSearch
	_check("%s: has a Search state" % kind, search != null)
	if search == null:
		e.queue_free()
		return
	search.last_seen = spot + Vector2(30, 0)
	e.state_machine.change_state(search)
	for i in 20:
		await get_tree().physics_frame
	_place(player, e.global_position + e.cardinal_direction * 30.0)
	var chased := false
	for i in 60:
		await get_tree().physics_frame
		if e.state_machine.current_state is EnemyStateChase:
			chased = true
			break
	_check("%s: spotting the player while searching resumes the chase" % kind, chased,
			str(e.state_machine.current_state.name))
	e.queue_free()


func _place(node: Node2D, pos: Vector2) -> void:
	node.global_position = pos
	node.reset_physics_interpolation()
	if node is CharacterBody2D:
		(node as CharacterBody2D).velocity = Vector2.ZERO
	if node == player:
		player.invulnerable = true


## A prop with open ground on both sides: enemy 70 px off one side, player 50 px off the other.
func _prop_setup() -> Dictionary:
	var rects: Array = arena.get("_blocker_rects")
	for rect: Rect2 in rects:
		var c := rect.get_center()
		var tries := [
			[Vector2(rect.position.x - 70.0, c.y), Vector2(rect.end.x + 50.0, c.y)],
			[Vector2(rect.end.x + 70.0, c.y), Vector2(rect.position.x - 50.0, c.y)],
			[Vector2(c.x, rect.position.y - 70.0), Vector2(c.x, rect.end.y + 50.0)],
			[Vector2(c.x, rect.end.y + 70.0), Vector2(c.x, rect.position.y - 50.0)],
		]
		for t in tries:
			if _roomy(t[0], 16.0) and _roomy(t[1], 12.0) and _segment_hits(t[0], t[1], rect):
				return {"rect": rect, "enemy": t[0], "player": t[1]}
	return {}


## An open spot with 100 px of clear ground to its right.
func _open_spot(offset: Vector2) -> Vector2:
	var c := arena.spawn_point() + offset
	for r in range(0, 400, 16):
		for k in 16:
			var p := c + Vector2.from_angle(TAU * k / 16.0) * r
			if _roomy(p, 16.0) and _roomy(p + Vector2(70, 0), 16.0) and arena.line_clear(p, p + Vector2(100, 0), 10.0):
				return p
	return c


func _far_spot(from: Vector2, dist: float) -> Vector2:
	for k in 16:
		var p := from + Vector2.from_angle(TAU * k / 16.0) * dist
		if _roomy(p, 12.0):
			return p
	return from + Vector2(0, dist)


func _roomy(p: Vector2, r: float) -> bool:
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if arena.is_blocked(p + o):
			return false
	return true


func _segment_hits(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var n := int(ceil(a.distance_to(b) / 2.0))
	for i in n + 1:
		if rect.has_point(a.lerp(b, float(i) / float(maxi(n, 1)))):
			return true
	return false


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
