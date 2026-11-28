extends Node2D
## Tutorial flags live in settings.cfg [tutorial], survive a reload, and are
## cleared by Settings → Reset. Plus the shared horde arena helpers.

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	await get_tree().process_frame
	var sm := get_node("/root/SettingsManager")
	sm.tutorial_completed = false
	sm.tutorial_tips_seen = {}

	_check("fresh: not completed", not TrainingState.is_completed())
	TrainingState.mark_completed()
	_check("mark_completed sets flag", TrainingState.is_completed())
	var reloaded: Node = load("res://00_globals/global_settings.gd").new()
	reloaded.load_settings()
	_check("mark_completed persists", reloaded.tutorial_completed == true)
	reloaded.free()

	_check("tip unseen at first", not TrainingState.tip_seen("first_boss"))
	TrainingState.mark_tip_seen("first_boss")
	_check("tip seen round-trip", TrainingState.tip_seen("first_boss"))
	var reloaded2: Node = load("res://00_globals/global_settings.gd").new()
	reloaded2.load_settings()
	_check("tip persists", bool(reloaded2.tutorial_tips_seen.get("first_boss", false)))
	reloaded2.free()

	sm.reset_progress()
	_check("reset clears completed", not TrainingState.is_completed())
	_check("reset clears tips", not TrainingState.tip_seen("first_boss"))

	TrainingState.direct_start = true
	_check("consume_direct_start true once", TrainingState.consume_direct_start())
	_check("consume_direct_start then false", not TrainingState.consume_direct_start())

	_check("not in tutorial here", not TrainingState.in_tutorial(get_tree()))

	# A returning player (from before Training existed) isn't forced into it.
	sm.tutorial_completed = false
	ProgressTracker.load_from_save({})
	_check("brand-new player: not completed", not TrainingState.is_completed())
	ProgressTracker.record_run_started()
	_check("player with runs counts as completed", TrainingState.is_completed())
	_check("veteran flag saved", sm.tutorial_completed == true)
	ProgressTracker.load_from_save({})
	sm.tutorial_completed = false

	var arena: HordeArena = load("res://levels/endless_horde/arenas/arena_01.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	var grass := arena.ground
	var rect := grass.get_used_rect()
	var far := grass.to_global(grass.map_to_local(rect.position)) + Vector2(-5000, -5000)
	var clamped := HordeArenaHelpers.clamp_to_grass(grass, far, 64.0)
	var corner := grass.to_global(grass.map_to_local(rect.position))
	_check("helpers: clamp keeps inside grass", clamped.x >= corner.x + 63.0 and clamped.y >= corner.y + 63.0,
		"%s vs %s" % [clamped, corner])
	var barrier := HordeArenaHelpers.add_top_barrier(self, grass, 16)
	_check("helpers: top barrier added", barrier != null and barrier.name == "TopBarrier"
		and barrier.collision_layer == 16)
	var restore: Array[Dictionary] = []
	var center := grass.to_global(grass.map_to_local(rect.position + rect.size / 2))
	var cell := grass.local_to_map(grass.to_local(center))
	var before := grass.get_cell_atlas_coords(cell)
	HordeArenaHelpers.paint_patch(grass, center, restore)
	_check("helpers: patch painted", restore.size() == 4 and grass.get_cell_atlas_coords(cell) == Vector2i(9, 1))
	HordeArenaHelpers.restore_patch(grass, restore)
	_check("helpers: patch restored", grass.get_cell_atlas_coords(cell) == before and restore.is_empty())

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
