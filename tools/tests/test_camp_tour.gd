extends Node2D
## Camp tour at the end of Training: a top-up gift (never stacks), talk → buy
## → fire, and Fight marks Training complete and starts the horde at stage 1.

const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

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


func _await_lesson(coach: TrainingCoach, id: StringName, timeout: float) -> bool:
	var timer := get_tree().create_timer(timeout, true, false, true)
	while timer.time_left > 0.0:
		if coach.current_id() == id:
			return true
		await get_tree().process_frame
	return coach.current_id() == id


func _load_camp(tour: bool, points: int) -> Node:
	TrainingState.tour_mode = tour
	PlayerManager.bonfire_points = points
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.CAMP_PATH, "", Vector2.ZERO)
	await _await_scene("Camp", 8.0)
	for i in 3:
		await get_tree().process_frame
	return get_tree().current_scene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	var saved_provider: SttProvider = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	SettingsManager.tutorial_completed = false
	var cost := PlayerManager.upgrade_cost("might")

	var camp: Node = await _load_camp(false, 1)
	_check("normal camp: no coach", camp.get("tour_coach") == null)
	_check("normal camp: points unchanged", PlayerManager.bonfire_points == 1,
		str(PlayerManager.bonfire_points))

	# Leaving the tour any way but the fire must still end it (Review #2).
	camp = await _load_camp(true, 5)
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.HORDE_PATH, "", Vector2.ZERO)
	await _await_scene("EndlessHorde", 8.0)
	_check("tour flag cleared when leaving the camp", not TrainingState.tour_mode)

	# A completed player replaying Training gets no gift (Review #1).
	SettingsManager.tutorial_completed = true
	camp = await _load_camp(true, 0)
	_check("no gift once completed", PlayerManager.bonfire_points == 0, str(PlayerManager.bonfire_points))
	SettingsManager.tutorial_completed = false

	camp = await _load_camp(true, 10)
	_check("tour gift doesn't stack", PlayerManager.bonfire_points == 10, str(PlayerManager.bonfire_points))

	Sfx.reset_counts()
	camp = await _load_camp(true, 0)
	_check("tour gift tops up", PlayerManager.bonfire_points == cost,
		"%d vs %d" % [PlayerManager.bonfire_points, cost])
	_check("tour gift plays the purchase sound", Sfx.count(&"purchase") == 1, str(Sfx.count(&"purchase")))
	_check("tour gift says so", PlayerHud._practice_notice_label != null and PlayerHud._practice_notice_label.text.contains("gift"))
	var coach: TrainingCoach = camp.get("tour_coach")
	_check("tour coach exists", coach != null)
	if coach == null:
		_finish(saved_provider, fake)
		return
	_check("coach starts at talk", await _await_lesson(coach, &"talk", 2.0), str(coach.current_id()))
	_check("in tutorial during tour", TrainingState.in_tutorial(get_tree()))
	var who = coach.current_point_target()
	_check("talk: arrow points at an NPC", who is Node2D and str(who.name) in ["Smith", "Trainer", "Cook"], str(who))
	var conv: CampConversation = camp.conversation
	conv.start("fire", null, 1, Callable())
	await get_tree().process_frame
	_check("talking to the fire isn't talking to someone", coach.current_id() == &"talk")
	conv.leave()
	await get_tree().create_timer(0.3, true, false, true).timeout
	conv.start("smith", null, 1, Callable())
	_check("talk completes on an NPC", await _await_lesson(coach, &"buy", 2.0), str(coach.current_id()))
	await get_tree().process_frame
	_check("coach hidden while talking", not camp.tour_banner.visible)
	_check("tour goal on the pill", camp.tour_banner.current_goal() == "Buy something", camp.tour_banner.current_goal())
	var chip = coach.current_point_target()
	_check("buy: ring on a choice chip while talking", chip is Button and chip.get_parent() == DialogSystem.choice_row,
		str(chip))
	_check("buy: the ring is drawn over the dialog", camp.tour_pointer.current_kind() == &"ui",
		str(camp.tour_pointer.current_kind()))
	conv.leave()
	await get_tree().process_frame
	_check("coach back after talking", camp.tour_banner.visible)
	conv.purchase_made.emit("might", 2)
	_check("buy completes after purchase", await _await_lesson(coach, &"fire", 2.0), str(coach.current_id()))
	_check("fire: arrow points at the campfire", coach.current_point_target() == camp.get_node("CampFire"),
		str(coach.current_point_target()))

	var runs_before := int(ProgressTracker.lifetime().get("runs", 0))
	camp._on_fire_action("fight")
	_check("fight marks tutorial complete", TrainingState.is_completed())
	_check("tour flag cleared", not TrainingState.tour_mode)
	_check("horde loaded", await _await_scene("EndlessHorde", 8.0), _scene_name())
	var stage := -1
	var timer := get_tree().create_timer(3.0, true, false, true)
	var horde := get_tree().current_scene
	while timer.time_left > 0.0:
		await get_tree().physics_frame
		stage = int(horde.get("_stage"))
		if stage == 1:
			break
	_check("horde starts directly at stage 1", stage == 1 and horde.get("_practice") == false,
		"stage %d practice %s" % [stage, str(horde.get("_practice"))])
	_check("a run was started", int(ProgressTracker.lifetime().get("runs", 0)) == runs_before + 1)
	_check("direct start consumed", not TrainingState.direct_start)
	_finish(saved_provider, fake)


func _finish(saved_provider: SttProvider, fake) -> void:
	TrainingState.tour_mode = false
	get_tree().paused = false
	STTManager.provider = saved_provider
	fake.free()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
