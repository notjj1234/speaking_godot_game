extends Node2D
## Speech-challenge exit regressions. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_challenge_exit.tscn
## F01: an out-of-tries challenge must drop every STT/HUD connection, so a
##      later enemy's challenge is not judged (and torn down) by the old one.
## F04: an STT backend that keeps erroring must eventually offer a way through
##      (word tiles for players; typing is developer-only).

const SLIME := "res://enemies/slime/slime.tscn"
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


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _links_to(sig: Signal, target: Object) -> int:
	var n := 0
	for c in sig.get_connections():
		var callable: Callable = c["callable"]
		if callable.get_object() == target:
			n += 1
	return n


func _spawn(at: Vector2) -> Enemy:
	var e: Enemy = load(SLIME).instantiate()
	add_child(e)
	e.global_position = at
	return e


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)
	await _test_fail_path_releases_io(killer)
	await _test_error_streak_offers_typing(killer)
	await _test_typed_test_input(killer)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_fail_path_releases_io(killer: HurtBox) -> void:
	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	var a := _spawn(Vector2(2000, 2000))
	var b := _spawn(Vector2(3000, 3000))
	await get_tree().physics_frame
	a._take_damage(killer)
	_check("challenge owns the mic on every platform (no voice commands)",
			controls.get("_challenge_mic_active") == true)
	for i in 3:
		PlayerHud.fallback_submitted.emit("zzzz wrong")
		await _wait(0.1)
	await _wait(2.5)
	_check("fail path: game resumed", not get_tree().paused)
	_check("fail path: mic handed back to the controls", controls.get("_challenge_mic_active") == false)
	_check("fail path: no HUD fallback link left on enemy",
			_links_to(PlayerHud.fallback_submitted, a) == 0)
	_check("fail path: no speak-button link left on enemy",
			_links_to(PlayerHud.speak_pressed, a) == 0)
	_check("fail path: no STT transcript link left on enemy",
			_links_to(STTManager.listening_completed, a) == 0)
	_check("fail path: no STT error link left on enemy", _links_to(STTManager.error, a) == 0)

	b._take_damage(killer)
	PlayerHud.fallback_submitted.emit("zzzz wrong")
	await _wait(2.0)
	_check("next challenge survives a wrong answer: still paused", get_tree().paused)
	_check("next challenge survives a wrong answer: card visible", PlayerHud.challenge_panel.visible)
	_check("next challenge survives a wrong answer: still active",
			WordTracker.speech_challenge_active)
	_check("next challenge: only its own try was spent",
			b.challenge_tries_left == 2 and a.challenge_tries_left == 0,
			"a=%d b=%d" % [a.challenge_tries_left, b.challenge_tries_left])

	PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)
	var plate: Control = PlayerHud.get("_success_plate")
	_check("success toast shows 'Got it!'", plate != null and plate.visible
			and (plate.get_node_or_null("VBoxContainer/Label") as Label) != null
			and (plate.get_node("VBoxContainer/Label") as Label).text.begins_with("Got it!"))
	await _wait(1.0)
	_check("next challenge passes and resumes", not get_tree().paused)
	_check("full-HP enemy is not killed by another enemy's answer", is_instance_valid(a) and a.hp == a.max_hp)
	if is_instance_valid(a):
		a.queue_free()


func _test_error_streak_offers_typing(killer: HurtBox) -> void:
	var real_provider = STTManager.provider
	var fake := FakeStt.new()
	STTManager.add_child(fake)
	STTManager.provider = fake
	var c := _spawn(Vector2(4000, 4000))
	await get_tree().physics_frame
	c._take_damage(killer)
	_check("available STT: typed box starts hidden", not PlayerHud.challenge_fallback_row.visible)
	STTManager.error.emit(7)
	STTManager.error.emit(7)
	_check("two errors: still voice only", not PlayerHud.challenge_fallback_row.visible)
	STTManager.error.emit(7)
	_check("third error in a row: word tiles offered", PlayerHud.word_tiles_row.visible)
	_check("third error in a row: no typing box for players", not PlayerHud.challenge_fallback_input.is_visible_in_tree())
	_check("listening restarted after each error", fake.listen_calls >= 4,
			"listen_calls=%d" % fake.listen_calls)
	PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)
	await _wait(1.0)
	_check("typed answer after errors passes", not get_tree().paused)
	STTManager.provider = real_provider
	fake.queue_free()


## Developer-only typing aid: with typed_test_input on, every challenge
## offers the typed box from the start, even when STT is available.
func _test_typed_test_input(killer: HurtBox) -> void:
	_check("typed test input: off in headless runs", not PlayerHud.typed_test_input)
	var real_provider = STTManager.provider
	var fake := FakeStt.new()
	STTManager.add_child(fake)
	STTManager.provider = fake
	PlayerHud.typed_test_input = true
	var d := _spawn(Vector2(5000, 5000))
	await get_tree().physics_frame
	d._take_damage(killer)
	_check("typed test input: box shown at challenge start", PlayerHud.challenge_fallback_row.visible)
	_check("typed test input: mic still listens", fake.listen_calls >= 1, "listen_calls=%d" % fake.listen_calls)
	PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)
	await _wait(1.0)
	_check("typed test input: typed answer passes", not get_tree().paused)
	_check("typed test input: box hidden after", not PlayerHud.challenge_fallback_row.visible)
	PlayerHud.typed_test_input = false
	STTManager.provider = real_provider
	fake.queue_free()
