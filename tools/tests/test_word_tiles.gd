extends Node2D
## Players have no keyboard: when the mic can't help, the word card offers
## pick-the-word tiles (tap the right words), never a typing box. Typing is a
## developer-only aid behind SettingsManager.dev_mode. Card buttons and tiles
## must answer real touches (UiInputRouter), not just mouse clicks.

const SLIME := "res://enemies/slime/slime.tscn"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")


class NoStt extends SttProvider:
	func is_available() -> bool:
		return false


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


func _spawn(at: Vector2) -> Enemy:
	var e: Enemy = load(SLIME).instantiate()
	add_child(e)
	e.global_position = at
	return e


func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = at
		ev.pressed = pressed
		UiInputRouter._input(ev)
		await get_tree().process_frame


func _typing_visible() -> bool:
	return PlayerHud.challenge_fallback_input.is_visible_in_tree()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)
	await _test_dev_mode_switch()
	await _test_no_stt_offers_tiles(killer)
	await _test_wrong_then_right_tile(killer)
	await _test_tiles_after_a_while(killer)
	await _test_dev_typing(killer)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_dev_mode_switch() -> void:
	SettingsManager.set_dev_mode(false)
	_check("players: no typing", not PlayerHud.typed_test_input)
	SettingsManager.set_dev_mode(true)
	_check("dev mode: typing on", PlayerHud.typed_test_input)
	SettingsManager.set_dev_mode(false)
	for i in 5:
		VersionOverlay.badge_tapped()
	_check("five taps on the version badge: dev mode on", SettingsManager.dev_mode and PlayerHud.typed_test_input)
	for i in 5:
		VersionOverlay.badge_tapped()
	_check("five more taps: off again", not SettingsManager.dev_mode and not PlayerHud.typed_test_input)
	_check("dev flag from the URL: ?dev=1", SettingsManager.dev_flag_from_query("?dev=1") == 1)
	_check("dev flag from the URL: ?dev=0", SettingsManager.dev_flag_from_query("?x=2&dev=0") == 0)
	_check("dev flag from the URL: absent", SettingsManager.dev_flag_from_query("?x=2") == -1)


func _test_no_stt_offers_tiles(killer: HurtBox) -> void:
	var real = STTManager.provider
	STTManager.provider = NoStt.new()
	var e := _spawn(Vector2(2000, 2000))
	await get_tree().physics_frame
	e._take_damage(killer)
	await get_tree().process_frame
	_check("no mic: word tiles offered", PlayerHud.word_tiles_row.is_visible_in_tree())
	_check("no mic: no typing box for players", not _typing_visible())
	var texts: Array = PlayerHud.word_tile_texts()
	_check("three tiles", texts.size() == 3, str(texts))
	_check("one tile is the target", texts.has(PlayerHud.target_sentence), "%s / %s" % [texts, PlayerHud.target_sentence])
	var unique := {}
	for t in texts:
		unique[str(t).to_lower()] = true
	_check("tiles are all different", unique.size() == texts.size(), str(texts))
	var journal_before := WordTracker.get_word_count()
	var right: Control = PlayerHud.word_tile_button(PlayerHud.target_sentence)
	await _tap(right)
	await _wait(1.0)
	_check("tapping the right tile wins (by touch)", not get_tree().paused and not WordTracker.speech_challenge_active)
	_check("a tile pick isn't logged as spoken", WordTracker.get_word_count() == journal_before)
	_check("tiles gone after", not PlayerHud.word_tiles_row.is_visible_in_tree())
	STTManager.provider = real


func _test_wrong_then_right_tile(killer: HurtBox) -> void:
	var real = STTManager.provider
	STTManager.provider = NoStt.new()
	var e := _spawn(Vector2(3000, 3000))
	await get_tree().physics_frame
	e._take_damage(killer)
	await get_tree().process_frame
	var wrong := ""
	for t in PlayerHud.word_tile_texts():
		if t != PlayerHud.target_sentence:
			wrong = t
	await _tap(PlayerHud.word_tile_button(wrong))
	await _wait(0.3)
	_check("wrong tile costs a try", e.challenge_tries_left == Enemy.MAX_CHALLENGE_TRIES - 1, str(e.challenge_tries_left))
	_check("still in the challenge", get_tree().paused and PlayerHud.challenge_panel.visible)
	_check("tiles still offered", PlayerHud.word_tiles_row.is_visible_in_tree()
		and PlayerHud.word_tile_texts().has(PlayerHud.target_sentence))
	await _tap(PlayerHud.word_tile_button(PlayerHud.target_sentence))
	await _wait(1.0)
	_check("right tile after a miss wins", not get_tree().paused)
	STTManager.provider = real


## Voice first: with a working mic the tiles wait, then show up if nothing
## lands for a while. Speak on the card answers a real touch.
func _test_tiles_after_a_while(killer: HurtBox) -> void:
	var real = STTManager.provider
	var fake := FakeStt.new()
	STTManager.add_child(fake)
	STTManager.provider = fake
	var e := _spawn(Vector2(4000, 4000))
	e.tiles_after_sec = 0.5
	await get_tree().physics_frame
	e._take_damage(killer)
	await get_tree().process_frame
	_check("mic works: no tiles at first", not PlayerHud.word_tiles_row.is_visible_in_tree())
	await _wait(0.8)
	_check("nothing heard for a while: tiles offered", PlayerHud.word_tiles_row.is_visible_in_tree())
	_check("still no typing for players", not _typing_visible())
	PlayerHud.show_speak_button()
	await get_tree().process_frame  # lay out the newly shown button
	var spoke := [0]
	var on_speak := func(): spoke[0] += 1
	PlayerHud.speak_pressed.connect(on_speak)
	await _tap(PlayerHud.challenge_speak_button)
	_check("Speak answers a real touch, once", spoke[0] == 1, str(spoke[0]))
	PlayerHud.speak_pressed.disconnect(on_speak)
	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	await _wait(1.0)
	_check("speaking still wins", not get_tree().paused)
	STTManager.provider = real
	fake.queue_free()


func _test_dev_typing(killer: HurtBox) -> void:
	var real = STTManager.provider
	STTManager.provider = NoStt.new()
	SettingsManager.set_dev_mode(true)
	var e := _spawn(Vector2(5000, 5000))
	await get_tree().physics_frame
	e._take_damage(killer)
	await get_tree().process_frame
	_check("dev mode: typing box shown", _typing_visible())
	PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)
	await _wait(1.0)
	_check("dev mode: typed answer passes", not get_tree().paused)
	SettingsManager.set_dev_mode(false)
	STTManager.provider = real
