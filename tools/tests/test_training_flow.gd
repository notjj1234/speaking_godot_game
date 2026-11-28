extends Node2D
## Guided Training: lessons advance only on their own conditions, the speech
## lesson uses the real challenge flow, you can't die, the voice lesson never
## blocks without STT, and the last lesson opens the camp tour.

const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")
const NoStt := preload("res://speech_to_text/unavailable_stt_provider.gd")

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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


var _hit: HurtBox


func _knock_down(target: Enemy) -> void:
	# Kept alive: the enemy hands this box to enemy_destroyed on success, like
	# the player's sword hurtbox in real play.
	if _hit == null:
		_hit = HurtBox.new()
		_hit.damage = 1
		add_child(_hit)
	var hit := _hit
	var guard := 0
	while is_instance_valid(target) and not WordTracker.speech_challenge_active and guard < 20:
		target._take_damage(hit)
		target.invulnerable = false
		guard += 1
		await _frames(2)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	var saved_provider: SttProvider = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	TrainingState.tour_mode = false
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.TRAINING_PATH, "", Vector2.ZERO)
	_check("training loaded", await _await_scene("Training", 8.0), _scene_name())
	var scene := get_tree().current_scene
	var coach: TrainingCoach = scene.coach
	_check("lesson 1 is why", await _await_lesson(coach, &"why", 3.0), str(coach.current_id()))
	await _frames(5)
	_check("why waits for tap", coach.current_id() == &"why")
	_check("reading lesson: no guide arrow", scene.pointer.current_kind() == &"")
	scene.banner.continue_pressed.emit()

	_check("move lesson", await _await_lesson(coach, &"move", 2.0), str(coach.current_id()))
	var player: Player = PlayerManager.player
	player.invulnerable = false
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)
	player._take_damage(killer)
	await _frames(2)
	_check("death refills in training", player.hp == player.max_hp and _scene_name() == "Training",
		"hp %d/%d" % [player.hp, player.max_hp])
	await _wait(0.3)
	_check("move: waits for the patch", coach.current_id() == &"move")
	_check("move: arrow points at the patch", scene.pointer.current_kind() in [&"world", &"edge"]
		and scene.point_target() == scene.marker, str(scene.point_target()))
	PlayerManager.set_player_position(scene.marker.global_position)
	_check("move completes on reaching the patch", await _await_lesson(coach, &"attack", 2.0),
		str(coach.current_id()))

	var target: Enemy = scene.current_target
	_check("attack: a harmless target", target != null and target.move_speed == 0.0)
	await _frames(2)
	_check("attack: arrow points at the slime", scene.point_target() == target, str(scene.point_target()))
	await _knock_down(target)
	_check("attack→speak on knock-down", await _await_lesson(coach, &"speak", 2.0), str(coach.current_id()))
	await _frames(3)
	_check("coach steps aside during the challenge", not scene.banner.visible)
	_check("lesson goal on the pill", scene.banner.current_goal() == "Say the words", scene.banner.current_goal())
	STTManager.listening_completed.emit("zzzz wrong words")
	await _wait(1.0)
	_check("speak waits for the right words", coach.current_id() == &"speak")
	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	_check("right words → fallbacks", await _await_lesson(coach, &"fallbacks", 3.0), str(coach.current_id()))
	var back_timer := get_tree().create_timer(2.0, true, false, true)
	while back_timer.time_left > 0.0 and not scene.banner.visible:
		await get_tree().process_frame
	_check("coach back after the challenge", scene.banner.visible,
		"challenge %s paused %s" % [WordTracker.speech_challenge_active, get_tree().paused])

	await _wait(0.5)
	target = scene.current_target
	_check("fallbacks: a second target", is_instance_valid(target) and target.hp == 2,
		"hp %s" % (str(target.hp) if is_instance_valid(target) else "<freed>"))
	await _knock_down(target)
	await _frames(3)
	_check("fallbacks: challenge up", WordTracker.speech_challenge_active and get_tree().paused)
	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	_check("answer finishes fallbacks", await _await_lesson(coach, &"out_of_tries", 3.0),
		str(coach.current_id()))
	scene.banner.continue_pressed.emit()

	_check("voice lesson", await _await_lesson(coach, &"voice", 2.0), str(coach.current_id()))
	await _wait(0.5)
	_check("voice waits for a command", coach.current_id() == &"voice")
	var controls := get_tree().get_first_node_in_group("touch_controls")
	controls.voice_command_executed.emit("attack")
	_check("voice completes on a command", await _await_lesson(coach, &"gems", 2.0), str(coach.current_id()))

	await _wait(0.3)
	_check("gems: a target to beat", is_instance_valid(scene.current_target))
	coach.complete()
	_check("wave lesson", await _await_lesson(coach, &"wave", 2.0))
	await _wait(2.0)
	_check("wave: enemies arrive", scene.enemy_count() > 0, str(scene.enemy_count()))
	var before: int = scene.enemy_count()
	get_tree().paused = true
	await _wait(3.0)
	_check("wave: no spawns while paused", scene.enemy_count() == before,
		"%d -> %d" % [before, scene.enemy_count()])
	get_tree().paused = false
	coach.complete()
	_check("boss lesson", await _await_lesson(coach, &"boss", 2.0))
	await _wait(0.5)
	var boss: Enemy = scene.current_target
	_check("boss lesson shows phases", is_instance_valid(boss) and boss.is_boss() and boss.boss_phases == 3)
	_check("boss: arrow points at the boss", scene.point_target() == boss, str(scene.point_target()))
	_check("boss music", MusicManager.current_track() == &"boss_slime", str(MusicManager.current_track()))
	coach.complete()
	_check("hud lesson", await _await_lesson(coach, &"hud", 2.0))
	await _frames(2)
	_check("hud: ring around the hearts", scene.point_target() == PlayerHud.get_node("Control/HFlowContainer"),
		str(scene.point_target()))

	# Review Focus 4: without STT the voice lesson must not block.
	STTManager.provider = NoStt.new()
	var skipped := [false]
	var done: Signal = scene.begin_voice()
	done.connect(func(): skipped[0] = true, CONNECT_ONE_SHOT)
	await _wait(3.5)
	_check("voice lesson auto-skips without STT", skipped[0])
	STTManager.provider = fake
	# Mic denied while the speech API exists (web/Android): error(-1) skips.
	var denied := [false]
	done = scene.begin_voice()
	done.connect(func(): denied[0] = true, CONNECT_ONE_SHOT)
	STTManager.error.emit(-1)
	await _wait(3.5)
	_check("voice lesson skips when the mic is denied", denied[0])
	_check("hud still waiting", coach.current_id() == &"hud")
	# Any other silent failure: it becomes tap-to-continue after a while.
	# (This tap also finishes the HUD tap lesson, which is next anyway.)
	var tapped := [false]
	scene.voice_tap_skip_sec = 0.3
	done = scene.begin_voice()
	done.connect(func(): tapped[0] = true, CONNECT_ONE_SHOT)
	await _wait(0.6)
	_check("voice tap hint shown", scene.banner.current_text().begins_with("No command heard yet"),
		scene.banner.current_text())
	scene.banner.continue_pressed.emit()
	await _frames(2)
	_check("voice lesson offers tap-to-continue later", tapped[0])

	_check("last lesson loads the camp", await _await_scene("Camp", 8.0), _scene_name())
	_check("camp is the tour", TrainingState.tour_mode)

	TrainingState.tour_mode = false
	get_tree().paused = false
	STTManager.provider = saved_provider
	fake.free()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
