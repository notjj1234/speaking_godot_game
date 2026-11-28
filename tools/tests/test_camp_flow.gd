extends Node
## Horde death -> camp -> fight on, end to end. Run headless on a scratch copy
## only (it writes user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_camp_flow.tscn
## Review Focus 5: show_defeat twice (or during a load) starts one camp load.

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

var passes := 0
var failures := 0
var load_starts := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


## Awaits `sig`, giving up after `limit` seconds. Returns true if it fired.
func _await_signal(sig: Signal, limit: float) -> bool:
	var state := {"fired": false}
	var mark := func(_a = null, _b = null) -> void: state["fired"] = true
	sig.connect(mark, CONNECT_ONE_SHOT)
	var timer := get_tree().create_timer(limit, true, false, true)
	while not state["fired"] and timer.time_left > 0.0:
		await get_tree().process_frame
	if sig.is_connected(mark):
		sig.disconnect(mark)
	return state["fired"]


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
	ProgressTracker.record_horde_death(3)
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(HORDE, "", Vector2.ZERO)
	_check("horde loaded", await _await_scene("EndlessHorde", 6.0), _scene_name())
	# Let the load's trailing level_loaded emission pass before counting.
	for i in 3:
		await get_tree().process_frame

	LevelManager.level_load_started.connect(func(): load_starts += 1)
	GameOver.show_defeat()
	GameOver.show_defeat()
	var loaded := await _await_signal(LevelManager.level_loaded, 5.0)
	_check("defeat loads a level", loaded)
	_check("defeat twice -> one load", load_starts == 1, "loads %d" % load_starts)
	_check("defeat lands in the camp", _scene_name() == "Camp", _scene_name())
	_check("game over screen stays hidden", not GameOver.visible)

	var conv: CampConversation = get_tree().get_first_node_in_group("camp_conversation")
	_check("camp has a conversation", conv != null)
	if conv:
		conv.start("fire", null, 1, Callable())
		conv.submit_transcript("fight on")
		loaded = await _await_signal(LevelManager.level_loaded, 5.0)
		_check("fight on loads a level", loaded)
		_check("fight on returns to the horde", _scene_name() == "EndlessHorde", _scene_name())
		var stage := -1
		var timer := get_tree().create_timer(2.0, true, false, true)
		while timer.time_left > 0.0:
			await get_tree().physics_frame
			var scene := get_tree().current_scene
			stage = int(scene.get("_stage")) if scene else -1
			if stage == 3:
				break
		_check("horde resumes at the saved stage", stage == 3, "stage %d" % stage)

	STTManager.provider = saved_provider
	fake.free()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
