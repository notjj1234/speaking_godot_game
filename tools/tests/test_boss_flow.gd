extends Node
## Boss stage -> victory camp -> fight on, end to end. Run headless on a scratch
## copy only (it writes user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_boss_flow.tscn
## Review Focus 3: a victory twice (or during a load) starts one camp load.
## Review Focus 4: the reward is granted once across camp re-entry and load_game.

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const GEM := "res://items/gem.tres"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

var passes := 0
var failures := 0
var load_starts := 0
var phase_labels: Array = []


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## Polls until the current scene is `scene_name` and no load is running.
func _await_scene(scene_name: String, limit: float) -> bool:
	var timer := get_tree().create_timer(limit, true, false, true)
	while timer.time_left > 0.0:
		if _scene_name() == scene_name and not LevelManager.is_loading:
			return true
		await get_tree().process_frame
	return false


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return String(scene.name) if scene else "<none>"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	# Survive change_scene_to_file: the old current scene is freed, so step off it.
	get_tree().current_scene = null
	var saved_provider: SttProvider = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	var saved_progress: Dictionary = ProgressTracker.snapshot()
	var saved_points := PlayerManager.bonfire_points
	ProgressTracker.load_from_save({})
	PlayerManager.bonfire_points = 0
	var gems_before := PlayerManager.item_count(GEM)
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)

	PlayerManager.player_spawned = false
	LevelManager.load_new_level(HORDE, "", Vector2.ZERO)
	_check("horde loaded", await _await_scene("EndlessHorde", 6.0), _scene_name())
	for i in 3:
		await get_tree().process_frame
	var horde := get_tree().current_scene
	horde.call("_jump_to_stage", 20)
	for i in 60:
		await get_tree().physics_frame
	PlayerManager.set_health(999, 999)
	var label := horde.get("_label") as Label
	_check("stage 20 label names the boss", label.text == "Stage 20 - Slime King", label.text)
	var enemies := (horde.get_node("HordeEnemies") as Node).get_children().filter(func(c): return c is Enemy)
	_check("one boss spawned", enemies.size() == 1 and (enemies[0] as Enemy).is_boss(), str(enemies.size()))
	if enemies.size() == 1:
		(enemies[0] as Enemy).boss_phase_changed.connect(func(_p, _n): phase_labels.append(label.text))

	LevelManager.level_load_started.connect(func(): load_starts += 1)
	Sfx.reset_counts()
	_check("every enemy defeated by speaking", await _defeat_all(horde, killer))
	# A load already in flight when the victory pause ends must not drop the camp trip.
	LevelManager.is_loading = true
	await _wait(HordeCurve.BOSS_CLEAR_PAUSE + 0.5)
	_check("busy loader -> camp trip waits", load_starts == 0 and _scene_name() == "EndlessHorde",
			"loads %d scene %s" % [load_starts, _scene_name()])
	LevelManager.is_loading = false
	_check("victory sound once", Sfx.count(&"victory") == 1, str(Sfx.count(&"victory")))
	_check("phase label shows 2/3", phase_labels.size() >= 1 and phase_labels[0] == "Slime King 2/3", str(phase_labels))
	_check("victory lands in the camp", await _await_scene("Camp", 10.0), _scene_name())
	_check("victory: one load", load_starts == 1, "loads %d" % load_starts)
	_check("victory: not the death route", not GameOver.get("_camp_requested") and not GameOver.visible)
	_check("victory: no death recorded", ProgressTracker.horde_stuck_stage() == 0)
	_check("victory: resume at 21", ProgressTracker.horde_resume_stage() == 21, str(ProgressTracker.horde_resume_stage()))
	_check("victory: boss 20 recorded", ProgressTracker.boss_cleared_stage() == 20)
	_check("victory: reward claimed", ProgressTracker.boss_reward_pending() == 0)
	var camp := get_tree().current_scene
	_check("camp knows it was a victory", camp.call("is_victory") and int(camp.get("victory_gems")) == 10,
			str(camp.get("victory_gems")))
	var expected := 10 + gems_before
	_check("victory: +10 gems", PlayerManager.bonfire_points == expected,
			"points %d want %d" % [PlayerManager.bonfire_points, expected])

	SaveManager.load_game()
	await _wait(0.5)
	_check("reload lands in the camp", await _await_scene("Camp", 10.0), _scene_name())
	_check("reload: no second reward", PlayerManager.bonfire_points == expected, "points %d" % PlayerManager.bonfire_points)
	_check("reload: not a victory visit", not get_tree().current_scene.call("is_victory"))

	var conv: CampConversation = get_tree().get_first_node_in_group("camp_conversation")
	_check("camp has a conversation", conv != null)
	if conv:
		conv.start("fire", null, 1, Callable())
		conv.submit_transcript("fight on")
		_check("fight on returns to the horde", await _await_scene("EndlessHorde", 10.0), _scene_name())
		horde = get_tree().current_scene
		var stage := -1
		var timer := get_tree().create_timer(3.0, true, false, true)
		while timer.time_left > 0.0:
			await get_tree().physics_frame
			stage = int(horde.get("_stage"))
			if stage == 21:
				break
		_check("fight on resumes at stage 21", stage == 21, "stage %d" % stage)
		var arena := horde.get("_arena") as HordeArena
		_check("stage 21 is Stone Ruins", arena != null and arena.display_name == "Stone Ruins")

		load_starts = 0
		horde.call("_go_to_camp")
		horde.call("_go_to_camp")
		_check("camp re-entry loads", await _await_scene("Camp", 10.0), _scene_name())
		_check("go to camp twice -> one load", load_starts == 1, "loads %d" % load_starts)
		_check("re-entry: no second reward", PlayerManager.bonfire_points == expected,
				"points %d" % PlayerManager.bonfire_points)

	ProgressTracker.load_from_save(saved_progress)
	PlayerManager.bonfire_points = saved_points
	STTManager.provider = saved_provider
	fake.free()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


## Speaks every enemy (boss phases and adds) to death. Drops are cleared so the
## gem count only reflects the boss reward.
func _defeat_all(horde: Node, killer: HurtBox) -> bool:
	var holder := horde.get_node("HordeEnemies")
	var timer := get_tree().create_timer(40.0, true, false, true)
	while timer.time_left > 0.0:
		if not is_instance_valid(holder):
			return true
		var targets := holder.get_children().filter(
				func(c): return c is Enemy and not c.is_queued_for_deletion() and not c.dying)
		if targets.is_empty():
			return true
		var enemy := targets[0] as Enemy
		if enemy.invulnerable or get_tree().paused or WordTracker.speech_challenge_active:
			await get_tree().process_frame
			continue
		var destroy := enemy.get_node_or_null("EnemyStateMachine/Destroy")
		if destroy:
			var no_drops: Array[DropData] = []
			destroy.set("drops", no_drops)
		enemy._take_damage(killer)
		if WordTracker.speech_challenge_active:
			STTManager.listening_completed.emit(PlayerHud.target_sentence)
			await _wait(0.7)
		else:
			await get_tree().process_frame
	return false
