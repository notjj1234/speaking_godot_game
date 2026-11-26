extends Node
## Endless Horde arena regressions. Run headless on a scratch copy only:
##   Godot --headless --path <copy> res://tools/tests/test_horde_arenas.tscn
## Arena per 20 stages (HordeCurve.arena_index_for), swap leaves exactly one
## Arena / TopBarrier and that arena's decor, stage label, camera bounds;
## spawns never land in walls/props or on top of the player; the camera covers
## the screen with the arena and never shakes on an axis pinned to a limit.

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const DECOR := {"Meadow": 14, "Stone Ruins": 25, "Ashen Camp": 15, "Frozen Hollow": 20}
const SAFE_GAP := 72.0

var passes := 0
var failures := 0
var _spawned: Array[Vector2] = []


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
	await _frames(5)
	_check_arena(horde, "Meadow", "practice")
	_check("practice label", (horde.get("_label") as Label).text == "Practice", (horde.get("_label") as Label).text)
	var player := PlayerManager.player as Node2D
	_check("player starts on the spawn point", player.global_position.distance_to(Vector2(320, 240)) < 2.0, str(player.global_position))
	await _check_camera(horde)

	(horde.get_node("HordeEnemies") as Node).child_entered_tree.connect(_on_enemy_added)
	for step in [[21, "Stone Ruins"], [47, "Ashen Camp"], [61, "Frozen Hollow"], [81, "Meadow"], [20, "Meadow"]]:
		PlayerManager.set_health(40, 40)
		_spawned.clear()
		horde.call("_jump_to_stage", step[0])
		await _frames(45)
		_check_arena(horde, step[1], "stage %d" % step[0])
		var label := (horde.get("_label") as Label).text
		_check("stage %d label" % step[0], label == "Stage %d - %s" % [step[0], step[1]], label)
		_check_spawns(horde, step[0])
	_finish()


func _check_arena(horde: Node, want: String, tag: String) -> void:
	var arenas := horde.get_children().filter(func(c): return c is HordeArena)
	_check("%s: exactly one arena" % tag, arenas.size() == 1, str(arenas.size()))
	var arena := horde.get("_arena") as HordeArena
	_check("%s: arena is %s" % [tag, want], arena != null and arena.display_name == want, arena.display_name if arena else "null")
	_check("%s: ground re-pointed" % tag, horde.get("_grass") == arena.ground)
	var barriers := horde.get_children().filter(func(c): return c.name.begins_with("TopBarrier") and not c.is_queued_for_deletion())
	_check("%s: one TopBarrier" % tag, barriers.size() == 1, str(barriers.size()))
	var decor := (horde.get_node("DecorLayer") as Node).get_children().filter(func(c): return not c.is_queued_for_deletion())
	_check("%s: decor moved into DecorLayer (%d)" % [tag, DECOR[want]], decor.size() == DECOR[want], str(decor.size()))
	var bounds: Array = LevelManager.current_tilemap_bounds
	_check("%s: camera bounds are the 640x480 arena" % tag,
			bounds.size() == 2 and bounds[0] == Vector2.ZERO and bounds[1] == Vector2(640, 480), str(bounds))


func _on_enemy_added(node: Node) -> void:
	if node is Enemy:
		# Queued after the level's own unstick pass, so this sees the final spot.
		call_deferred("_record_spawn", node)


func _record_spawn(node: Node) -> void:
	if is_instance_valid(node):
		_spawned.append((node as Node2D).global_position)


func _check_spawns(horde: Node, stage: int) -> void:
	var arena := horde.get("_arena") as HordeArena
	var player := (PlayerManager.player as Node2D).global_position
	var blocked := 0
	var close := 0
	for p in _spawned:
		if arena.is_blocked(p):
			blocked += 1
		if p.distance_to(player) < SAFE_GAP - 1.0:
			close += 1
	_check("stage %d: enemies spawned" % stage, not _spawned.is_empty())
	_check("stage %d: no spawn inside a wall or prop" % stage, blocked == 0, "%d of %d" % [blocked, _spawned.size()])
	_check("stage %d: no spawn on top of the player" % stage, close == 0, "%d of %d" % [close, _spawned.size()])


func _check_camera(horde: Node) -> void:
	var cam := PlayerManager.player.get_node_or_null("Camera2D") as Camera2D
	_check("player camera found", cam != null)
	if cam == null:
		return
	var view := get_viewport().get_visible_rect().size
	var seen := view / cam.zoom
	_check("camera shows no space outside the arena (%s at zoom %.2f)" % [view, cam.zoom.x],
			seen.x <= 641.0 and seen.y <= 481.0, str(seen))
	# Walk along the left wall: the camera is pinned there, so it must not wobble.
	var player := PlayerManager.player as Node2D
	var offsets := {}
	for i in 12:
		player.global_position = Vector2(48.0 + 0.3 * float(i), 240.4)
		await get_tree().process_frame
		offsets[snappedf(cam.offset.x, 0.01)] = true
	_check("no sub-pixel shake while pinned to the wall", offsets.size() == 1 and offsets.has(0.0), str(offsets.keys()))
	player.global_position = Vector2(320, 240)
	await _frames(2)


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
