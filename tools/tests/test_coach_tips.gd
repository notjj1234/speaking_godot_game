extends Node2D
## One-time coach tips: each shows once ever, never during Training, one per
## camp visit, and the first boss / new arena tips fire from the horde.

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return String(scene.name) if scene else "<none>"


func _await_scene(scene_name: String, timeout: float) -> bool:
	var timer := get_tree().create_timer(timeout, true, false, true)
	while timer.time_left > 0.0:
		if _scene_name() == scene_name and not LevelManager.is_loading:
			return true
		await get_tree().process_frame
	return false


func _banner_in(node: Node) -> CoachBanner:
	for child in node.get_children():
		if child is CoachBanner:
			return child
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	SettingsManager.tutorial_tips_seen = {}
	TrainingState.tour_mode = false

	var host := Node.new()
	add_child(host)
	_check("shows once: first call", CoachTips.show_once(host, "unit_tip", "Hello"))
	var banner := _banner_in(host)
	_check("shows once: banner up", banner != null and banner.visible and banner.current_text() == "Hello")
	_check("shows once: second call refused", not CoachTips.show_once(host, "unit_tip", "Hello"))
	_check("tip marked seen", TrainingState.tip_seen("unit_tip"))

	# A death visit to camp shows the death tip, not the shop tip.
	PlayerManager.bonfire_points = 50
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.CAMP_PATH, "", Vector2.ZERO)
	await _await_scene("Camp", 8.0)
	await get_tree().process_frame
	_check("camp shows death tip on a death visit", TrainingState.tip_seen("camp_after_death"))
	_check("one tip per visit", not TrainingState.tip_seen("shop_ready"))
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.CAMP_PATH, "", Vector2.ZERO)
	await _await_scene("Camp", 8.0)
	await get_tree().process_frame
	_check("next visit shows the shop tip", TrainingState.tip_seen("shop_ready"))

	SettingsManager.tutorial_tips_seen = {}
	TrainingState.tour_mode = true
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.CAMP_PATH, "", Vector2.ZERO)
	await _await_scene("Camp", 8.0)
	await get_tree().process_frame
	_check("no tip on tour visit", SettingsManager.tutorial_tips_seen.is_empty(),
		str(SettingsManager.tutorial_tips_seen))
	_check("silent during tutorial", not CoachTips.show_once(get_tree().current_scene, "x", "y"))
	TrainingState.tour_mode = false

	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.HORDE_PATH, "", Vector2.ZERO)
	await _await_scene("EndlessHorde", 8.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	var horde := get_tree().current_scene
	await horde._begin_stage(20)
	_check("boss tip on stage 20", TrainingState.tip_seen("first_boss"))
	_check("no new-arena tip in arena 1", not TrainingState.tip_seen("new_arena"))
	horde._clear_horde()
	await horde._begin_stage(21)
	_check("new-arena tip on stage 21", TrainingState.tip_seen("new_arena"))

	get_tree().paused = false
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
