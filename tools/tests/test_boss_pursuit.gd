extends Node
## Block bosses must hunt the player: never give up, always face them, path
## around props, and throw telegraphed ranged attacks that walls stop.
## Run headless on a scratch copy only (renamed config/name):
##   Godot --headless --path <copy> res://tools/tests/test_boss_pursuit.tscn
## Projectiles are found by group "boss_projectile" and settings by get(), so
## this script parses before the feature exists (RED is a FAIL, not an error).

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const STAGES := {"Slime King": 20, "Bone Captain": 40, "Orc Warlord": 60, "Frost Bandit": 80}
const GROUP := &"boss_projectile"

var passes := 0
var failures := 0
var horde: Node
var player: Player
var arena: HordeArena
## Every projectile seen this boss: id -> {ticks alive, ticks inside a solid}.
var _seen := {}
var _fired_through_prop := 0
var _in_horde_container := 0
var _stuck_in_solid := 0
var _overstayed := 0
var _hits: Array = []
var _launch_min := INF
## Per kind: chase distance bands scaled 1.5x for the 2x bosses (base value x 1.5).
const REACH := {
	"Bone Captain": {"hold_inner": 60.0, "hold_outer": 72.0},
	"Orc Warlord": {"charge_min_range": 84.0, "charge_max_range": 132.0},
	"Frost Bandit": {"orbit_inner": 78.0, "orbit_outer": 96.0, "dart_stop_distance": 33.0},
}
## HordeCurve.BOSS_MAX_HIT: no boss hit takes more than a quarter of the base 20 HP.
const MAX_HIT := 5


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
	player = PlayerManager.player
	# The player stands still and never dies; hits are read off its HitBox.
	player.get_node("StateMachine").process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	player.invulnerable = true
	player.hit_box.damaged.connect(func(hb: HurtBox): _hits.append({"group": hb.is_in_group(GROUP), "damage": hb.damage}))
	for boss_name in STAGES:
		await _boss_suite(boss_name, STAGES[boss_name])
	_finish()


func _boss_suite(boss_name: String, stage: int) -> void:
	horde.call("_jump_to_stage", stage)
	var boss: Enemy = null
	for i in 900:
		await get_tree().physics_frame
		boss = _find_boss()
		if boss:
			break
	_check("%s: spawns" % boss_name, boss != null and boss.boss_name == boss_name, boss.boss_name if boss else "none")
	if boss == null:
		return
	arena = horde.get("_arena") as HordeArena
	await _test_arrival(boss_name, boss)
	_seen.clear()
	_launch_min = INF
	_fired_through_prop = 0
	_in_horde_container = 0
	_stuck_in_solid = 0
	_overstayed = 0
	_hits.clear()
	await get_tree().physics_frame
	await _test_relentless(boss_name, boss)
	await _test_around_prop(boss_name, boss)
	await _test_ranged(boss_name, boss)
	_check("%s: never fires through a prop" % boss_name, _fired_through_prop == 0, str(_fired_through_prop))
	_check("%s: projectiles stay out of HordeEnemies" % boss_name, _in_horde_container == 0, str(_in_horde_container))
	_check("%s: walls and props stop projectiles" % boss_name, _stuck_in_solid == 0, str(_stuck_in_solid))
	_check("%s: projectiles expire within 3 s" % boss_name, _overstayed == 0, str(_overstayed))
	# The edge is LAUNCH_EDGE (18) out from the chest; a tick of travel only adds.
	_check("%s: shots launch from the body edge, not the feet" % boss_name, _launch_min >= 16.0, str(_launch_min))
	await _test_top_hud(boss_name, boss)


## Arrival: far from the player, a still entrance, no cone, fair numbers.
func _test_arrival(boss_name: String, boss: Enemy) -> void:
	var gap := boss.global_position.distance_to(player.global_position)
	_check("%s: spawns at least 200 px from the player" % boss_name, gap >= 200.0, "%.0f" % gap)
	var at := boss.global_position
	var moved := false
	for i in 45:
		await get_tree().physics_frame
		if boss.global_position.distance_to(at) > 0.5:
			moved = true
	_check("%s: holds still for its entrance" % boss_name, not moved)
	# From its far spawn it must find its way to a standing player promptly.
	var spawn := boss.global_position
	var reached := false
	for i in 360:
		await get_tree().physics_frame
		if boss.global_position.distance_to(player.global_position) <= 90.0:
			reached = true
			break
	_check("%s: reaches the player from its spawn within 6 s" % boss_name, reached,
			"spawn %s, now %s, player %s" % [spawn.round(), boss.global_position.round(), player.global_position.round()])
	var vision := boss.get_node_or_null("VisionArea")
	var cone_shown := false
	if vision:
		for c in vision.get_children():
			if c is Polygon2D and (c as Polygon2D).visible:
				cone_shown = true
	_check("%s: no vision cone drawn" % boss_name, not cone_shown)
	var chase := boss.state_machine.get_node("Chase")
	var want: Dictionary = REACH.get(boss_name, {})
	for prop in want:
		_check("%s: %s scaled for its size" % [boss_name, prop], is_equal_approx(float(chase.get(prop)), want[prop]),
				"%s vs %s" % [chase.get(prop), want[prop]])
	var biggest := 0
	for hb: HurtBox in boss.find_children("*", "HurtBox"):
		biggest = maxi(biggest, hb.damage)
	_check("%s: no hit over %d damage" % [boss_name, MAX_HIT], biggest <= MAX_HIT and biggest > 0, str(biggest))
	if boss_name == "Orc Warlord":
		var want_speed := 22.0 * HordeCurve.speed_multiplier(STAGES[boss_name])
		_check("Orc Warlord: stalk speed scales with the stage", is_equal_approx(float(chase.get("stalk_speed")), want_speed),
				"%s vs %s" % [chase.get("stalk_speed"), want_speed])


## The wave label (and mic banner) fade while the player or boss is under them.
func _test_top_hud(boss_name: String, boss: Enemy) -> void:
	var label := horde.get("_label") as Label
	var bottom := arena.nearest_open(Vector2(320, 420))
	_place(player, arena.nearest_open(Vector2(320, 300)))
	_place(boss, bottom)
	for i in 30:
		await get_tree().physics_frame
	_check("%s: top label solid when nothing is under it" % boss_name, label.modulate.a >= 0.95, str(label.modulate.a))
	_place(player, bottom)
	_place(boss, Vector2(320, 64))
	var faded := false
	for i in 12:
		await get_tree().physics_frame
		if label.modulate.a < 0.6:
			faded = true
	_check("%s: top label fades over the boss" % boss_name, faded, str(label.modulate.a))


## 1 + 2: from behind (outside the cone) the boss keeps chasing and faces the player.
func _test_relentless(boss_name: String, boss: Enemy) -> void:
	var start := arena.spawn_point()
	_place(boss, start)
	var behind := -boss.cardinal_direction if boss.cardinal_direction != Vector2.ZERO else Vector2.LEFT
	_place(player, arena.nearest_open(start + behind * 150.0))
	await get_tree().physics_frame
	var d0 := boss.global_position.distance_to(player.global_position)
	var closest := d0
	var gave_up := 0
	var facing_ok := 0
	var facing_n := 0
	# 6 s: a boss teleported mid-charge first finishes that charge and staggers.
	for i in 360:
		await get_tree().physics_frame
		_track(boss)
		closest = minf(closest, boss.global_position.distance_to(player.global_position))
		var st := boss.state_machine.current_state
		if st is EnemyStateIdle or st is EnemyStateWander:
			gave_up += 1
		if i < 30 or _charging(boss):
			continue
		var to := player.global_position - boss.global_position
		if absf(absf(to.x) - absf(to.y)) < 0.2 * to.length() or to.length() < 8.0:
			continue
		facing_n += 1
		var axis := Vector2(signf(to.x), 0) if absf(to.x) > absf(to.y) else Vector2(0, signf(to.y))
		if boss.cardinal_direction == axis:
			facing_ok += 1
	_check("%s: never gives up the chase" % boss_name, gave_up == 0, "%d idle/wander ticks" % gave_up)
	# Closest approach, not the final gap: a charger overshoots and comes back.
	_check("%s: closes in from behind" % boss_name, closest < d0 - 30.0, "%.0f -> closest %.0f" % [d0, closest])
	_check("%s: faces the player" % boss_name, facing_n > 0 and float(facing_ok) / float(facing_n) >= 0.9,
			"%d/%d" % [facing_ok, facing_n])


## 3: a prop between boss and player; the boss must come around it.
func _test_around_prop(boss_name: String, boss: Enemy) -> void:
	var setup := _prop_setup()
	_check("%s: found a prop to hide behind" % boss_name, not setup.is_empty())
	if setup.is_empty():
		return
	var rect: Rect2 = setup["rect"]
	_place(boss, setup["boss"])
	_place(player, setup["player"])
	var got_round := false
	for i in 480:
		await get_tree().physics_frame
		_track(boss)
		var a := boss.global_position
		var b := player.global_position
		if a.distance_to(b) <= 90.0 and not _segment_hits(a, b, rect.grow(2.0)):
			got_round = true
			break
	_check("%s: paths around a prop" % boss_name, got_round,
			"stuck at %s, player %s, prop %s" % [boss.global_position.round(), player.global_position.round(), rect])


## 4, 7, 9: fires with a wind-up hold, freezes when paused, phase clears and grows the volley.
func _test_ranged(boss_name: String, boss: Enemy) -> void:
	# Start clean: shots from the prop test must not count as this volley.
	for i in 240:
		if _live(boss).is_empty():
			break
		await get_tree().physics_frame
		_track(boss)
	var start := arena.spawn_point()
	_place(boss, start)
	var spot := start
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var p: Vector2 = start + dir * 120.0
		if not arena.is_blocked(p) and not _segment_solid(start, p):
			spot = p
			break
	_place(player, spot)
	var fired := false
	var held_ticks := 0
	var held_moved := 0
	var prev := boss.global_position
	var was_held := false
	for i in 420:
		await get_tree().physics_frame
		_track(boss)
		# The hold is set after the body moved this tick; it binds from the next.
		var held: bool = boss.get("attack_hold") == true
		if held:
			held_ticks += 1
			if was_held and boss.global_position.distance_to(prev) > 0.01:
				held_moved += 1
		was_held = held
		_keep_apart(boss)
		prev = boss.global_position
		if not _live(boss).is_empty():
			fired = true
			break
	_check("%s: ranged attack fires" % boss_name, fired)
	_check("%s: holds still during the wind-up" % boss_name, held_ticks > 0 and held_moved == 0,
			"%d held, %d moved" % [held_ticks, held_moved])
	if not fired:
		return
	# Paused (a speech challenge): nothing moves and nothing new fires.
	var before := _live(boss)
	var pos := before.map(func(p): return p.global_position)
	get_tree().paused = true
	await get_tree().create_timer(0.5, true, false, true).timeout
	var after := _live(boss)
	var frozen := after.size() == before.size()
	for i in mini(after.size(), before.size()):
		frozen = frozen and after[i] == before[i] and after[i].global_position == pos[i]
	get_tree().paused = false
	_check("%s: projectiles freeze while paused" % boss_name, frozen, "%d -> %d" % [before.size(), after.size()])
	# Let some shots land so the hit check has data.
	for i in 90:
		await get_tree().physics_frame
		_track(boss)
	var touch := int((boss.get_node("HurtBox") as HurtBox).damage)
	var proj_hits := _hits.filter(func(h): return h["group"])
	_check("%s: a projectile hits for the boss's touch damage" % boss_name,
			not proj_hits.is_empty() and proj_hits.all(func(h): return h["damage"] == touch),
			"%s vs %d" % [str(proj_hits), touch])
	# Phase pass: in-flight shots are cleared and the next volley grows.
	var ranged: Dictionary = HordeCurve.boss_for_stage(STAGES[boss_name]).get("ranged", {})
	var want := int(ranged.get("count", 0)) + int(ranged.get("count_step", 0)) * (boss.boss_phase + 1)
	for i in 300:
		if not _live(boss).is_empty():
			break
		await get_tree().physics_frame
		_track(boss)
	boss.call("_advance_boss_phase")
	await get_tree().physics_frame
	_check("%s: phase change clears projectiles" % boss_name, _live(boss).is_empty(), str(_live(boss).size()))
	_place(boss, start)
	_place(player, spot)
	var volley := 0
	for i in 480:
		await get_tree().physics_frame
		_track(boss)
		_keep_apart(boss)
		var n := _live(boss).size()
		if n > 0:
			volley = n
			break
	_check("%s: next phase volley has %d shots" % [boss_name, want], want > 0 and volley == want, str(volley))


## Per tick: watch every projectile for the global rules.
func _track(boss: Enemy) -> void:
	for child in (horde.get("_enemies") as Node).get_children():
		if child.is_in_group(GROUP):
			_in_horde_container += 1
	for p in get_tree().get_nodes_in_group(GROUP):
		var node := p as Node2D
		if node == null or node.is_queued_for_deletion():
			continue
		var id := node.get_instance_id()
		if not _seen.has(id):
			_seen[id] = {"ticks": 0, "solid": 0}
			if is_instance_valid(boss):
				var chest := boss.global_position + Vector2(0, -BossRangedAttack.LAUNCH_HEIGHT)
				_launch_min = minf(_launch_min, node.global_position.distance_to(chest))
			if is_instance_valid(boss) and _segment_solid(boss.global_position, player.global_position):
				_fired_through_prop += 1
		var rec: Dictionary = _seen[id]
		if _inside_solid(node.global_position):
			rec["solid"] += 1
			if rec["solid"] == 3:
				_stuck_in_solid += 1
		# Counted in physics ticks (this runs once per unpaused tick); 3 s = 180.
		rec["ticks"] += 1
		if rec["ticks"] > 190 and not rec.get("late", false):
			rec["late"] = true
			_overstayed += 1


## Stands in for knockback and kiting (the player here is frozen): when the
## boss hugs the player, step the player 120 px away with a clear line.
func _keep_apart(boss: Enemy) -> void:
	if boss.attack_hold or boss.global_position.distance_to(player.global_position) > 36.0:
		return
	var away := boss.global_position.direction_to(player.global_position)
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	for k in 8:
		var p := boss.global_position + away.rotated(TAU * float(k) / 8.0) * 120.0
		if _roomy(p, 12.0) and not _segment_solid(boss.global_position, p):
			_place(player, p)
			return


func _live(boss: Enemy) -> Array:
	return get_tree().get_nodes_in_group(GROUP).filter(
			func(p): return is_instance_valid(p) and not p.is_queued_for_deletion() and boss.is_ancestor_of(p))


func _charging(boss: Enemy) -> bool:
	var st := boss.state_machine.current_state
	return st is EnemyStateChaseOrc and int(st.get("_phase")) == EnemyStateChaseOrc.Phase.CHARGE


func _find_boss() -> Enemy:
	for child in (horde.get("_enemies") as Node).get_children():
		if child is Enemy and child.is_boss() and not child.is_queued_for_deletion():
			return child
	return null


func _place(node: Node2D, pos: Vector2) -> void:
	node.global_position = pos
	node.reset_physics_interpolation()
	if node is CharacterBody2D:
		(node as CharacterBody2D).velocity = Vector2.ZERO
	# Arena swaps revive the player, which clears invulnerability.
	if node == player:
		player.invulnerable = true


## A prop with open ground on both sides along x or y, boss 70 px off one side,
## player 50 px off the other, the straight line through the prop.
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
			var b: Vector2 = t[0]
			var p: Vector2 = t[1]
			if _roomy(b, 26.0) and _roomy(p, 12.0) and _segment_hits(b, p, rect):
				return {"rect": rect, "boss": b, "player": p}
	return {}


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


## True if a wall or prop collision shape lies on the segment.
func _segment_solid(a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / 4.0))
	for i in n + 1:
		if _inside_solid(a.lerp(b, float(i) / float(maxi(n, 1)))):
			return true
	return false


## A point inside a real wall or prop collision shape (Walls layer).
func _inside_solid(p: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 16
	return not arena.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
