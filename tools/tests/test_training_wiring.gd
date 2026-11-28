extends Node2D
## Title → Training routing, pause-menu "Skip tutorial", and saves made inside
## Training never resume it.

const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")
const TITLE := "res://levels/title_screen/title_screen.tscn"

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


func _go_title() -> Node:
	LevelManager.load_new_level(TITLE, "", Vector2.ZERO)
	await _await_scene("TitleScreen", 8.0)
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
	var title: Node = await _go_title()
	title._on_game_pressed()
	_check("new player: Main Game → Training", await _await_scene("Training", 8.0), _scene_name())

	PauseMenu.show_pause_menu()
	await get_tree().process_frame
	_check("skip button shown in training", PauseMenu.button_skip_tutorial.visible)
	_check("save hidden in training", not PauseMenu.button_save.visible)
	PauseMenu.hide_pause_menu()

	SaveManager.save_game()
	_check("save in training points at horde", SaveManager.current_save.scene_path == TrainingState.HORDE_PATH,
		str(SaveManager.current_save.scene_path))

	# Knock a target down so a challenge is up, then skip (Review Focus 1).
	var training := get_tree().current_scene
	await get_tree().create_timer(0.5, true, false, true).timeout
	var target: Enemy = training.spawn_target(Vector2(60, 0), 1)
	var hit := HurtBox.new()
	hit.damage = 1
	add_child(hit)
	target._take_damage(hit)
	await get_tree().process_frame
	_check("challenge up before skip", WordTracker.speech_challenge_active and get_tree().paused)
	PauseMenu._on_skip_tutorial_pressed()
	_check("skip mid-challenge loads the horde", await _await_scene("EndlessHorde", 8.0), _scene_name())
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check("skip: game running", not get_tree().paused)
	_check("skip: challenge cleared", not WordTracker.speech_challenge_active)
	_check("skip: challenge card hidden", not PlayerHud.challenge_panel.visible)
	_check("skip marks completed", TrainingState.is_completed())
	_check("skip starts at stage 1", int(get_tree().current_scene.get("_stage")) == 1,
		str(get_tree().current_scene.get("_stage")))

	PauseMenu.show_pause_menu()
	await get_tree().process_frame
	_check("skip button hidden in the horde", not PauseMenu.button_skip_tutorial.visible)
	_check("save shown in the horde", PauseMenu.button_save.visible)
	PauseMenu.hide_pause_menu()

	title = await _go_title()
	title._on_game_pressed()
	_check("completed: Main Game → horde", await _await_scene("EndlessHorde", 8.0), _scene_name())

	title = await _go_title()
	_check("title names a training save", title._friendly_place_name(TrainingState.TRAINING_PATH) == "Training")
	title._on_tutorial_pressed()
	_check("Tutorial button → Training even when completed", await _await_scene("Training", 8.0), _scene_name())

	get_tree().paused = false
	STTManager.provider = saved_provider
	fake.free()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
