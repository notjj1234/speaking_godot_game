extends Node2D
## Tester-pass fixes, phase 1: things that confuse young players.
## Dev hotkey (Ctrl+`), fair word tiles, the Trainer bubble never covering
## the target, a first-visit greeting, a glowing patch, one consistent mic
## control, and honest hint text.

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


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _test_dev_hotkey()
	_test_lookalikes()
	await _test_bubble_avoids_target()
	await _test_first_greeting()
	await _test_glow()
	await _test_mic_words()
	_test_hint_text()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _key(ctrl: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_QUOTELEFT
	ev.keycode = KEY_QUOTELEFT
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	return ev


func _test_dev_hotkey() -> void:
	SettingsManager.set_dev_mode(false)
	VersionOverlay._input(_key(false))
	_check("` alone does nothing", not SettingsManager.dev_mode)
	VersionOverlay._input(_key(true))
	_check("Ctrl+` turns developer mode on", SettingsManager.dev_mode and PlayerHud.typed_test_input)
	VersionOverlay._input(_key(true))
	_check("Ctrl+` again turns it off", not SettingsManager.dev_mode)


func _test_lookalikes() -> void:
	for target in ["cat", "garden", "I like cats"]:
		var others: Array = WordTracker.lookalike_phrases(target, 2)
		var band: int = WordTracker._band_of_phrase(target)
		_check("look-alikes for '%s': two of them" % target, others.size() == 2, str(others))
		var same := true
		for o in others:
			if absi(WordTracker._band_of_phrase(o) - band) > 1 or str(o).to_lower() == target.to_lower():
				same = false
		_check("look-alikes for '%s': similar length, never the target" % target, same, str(others))
	var before = WordTracker.get("next_challenge_type")
	WordTracker.lookalike_phrases("cat", 2)
	_check("look-alikes have no side effects", WordTracker.get("next_challenge_type") == before)


func _test_bubble_avoids_target() -> void:
	var banner := CoachBanner.new()
	add_child(banner)
	banner.say("A boss!", false, "Beat it")
	await _frames()
	var top := banner.panel_rect()
	_check("no target: bubble at the top", not banner.is_at_bottom() and top.position.y < 240.0, str(top))
	banner.set_avoid(top.grow(-10.0))
	await _frames()
	var moved := banner.panel_rect()
	_check("target under the bubble: it moves to the bottom", banner.is_at_bottom() and not moved.intersects(top.grow(-10.0)),
		"%s vs %s" % [moved, top])
	banner.set_avoid(Rect2())
	await _frames()
	_check("target gone: back to the top", not banner.is_at_bottom())
	banner.queue_free()


func _test_first_greeting() -> void:
	var conv := CampConversation.new()
	add_child(conv)
	var saved = STTManager.provider
	STTManager.provider = FakeStt.new()
	TrainingState.tour_mode = true
	conv.start("smith", null, 1, Callable())
	await _frames()
	_check("first visit: no 'back from the dead'", not conv.current_line().to_lower().contains("dead"), conv.current_line())
	_check("first visit: a welcome line", CampLines.NPCS["smith"]["greet_first"].has(conv.current_line()), conv.current_line())
	conv.leave()
	TrainingState.tour_mode = false
	STTManager.provider = saved
	conv.queue_free()
	await _frames()


func _test_glow() -> void:
	var glow := HordeArenaHelpers.add_glow(self, Vector2(100, 100), Vector2(64, 64))
	await _frames(3)
	_check("glow drawn on the patch", glow != null and glow.is_inside_tree() and glow.visible)
	var a1: float = glow.glow_alpha()
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check("glow pulses", absf(glow.glow_alpha() - a1) > 0.02, "%f -> %f" % [a1, glow.glow_alpha()])
	glow.queue_free()


func _test_mic_words() -> void:
	PlayerHud.set_stt_state(PlayerHudUI.SttState.STT_IDLE)
	_check("plate: 'Mic Off' like the button", PlayerHud.stt_plate_text() == "Mic Off", PlayerHud.stt_plate_text())
	PlayerHud.set_stt_state(PlayerHudUI.SttState.STT_UNAVAILABLE)
	_check("plate: 'No mic'", PlayerHud.stt_plate_text() == "No mic", PlayerHud.stt_plate_text())
	PlayerHud.set_stt_state(PlayerHudUI.SttState.STT_IDLE)

	var saved = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	await _frames()
	controls.set("_touch_ui_enabled", false)
	controls._ensure_mic_button_visible()
	await _frames()
	_check("desktop: no lone floating Mic button", not controls.right_cluster.is_visible_in_tree())
	_check("desktop: the top-right plate is the mic switch", PlayerHud.stt_plate_clickable())
	var before: bool = controls.mic_enabled
	PlayerHud.stt_plate_pressed.emit()
	await _frames()
	_check("desktop: clicking the plate toggles the mic", controls.mic_enabled != before)
	PlayerHud.stt_plate_pressed.emit()
	await _frames()

	controls.set("_touch_ui_enabled", true)
	STTManager.provider = load("res://speech_to_text/unavailable_stt_provider.gd").new()
	controls._ensure_mic_button_visible()
	await _frames()
	_check("no STT: the Mic toggle is hidden", not controls.mic_button.visible)
	STTManager.provider = saved
	controls.queue_free()
	PlayerHud.set_stt_plate_clickable(false)
	await _frames()


func _test_hint_text() -> void:
	var banner := CoachBanner.new()
	banner.say("Read this.", true)
	_check("desktop hint mentions clicking", banner.hint_text() == "Click or press Enter to continue"
		or banner.hint_text() == "Tap to continue", banner.hint_text())
	banner.free()
	var training_src := FileAccess.get_file_as_string("res://levels/training/training.gd")
	_check("HUD lesson: hearts are top middle", training_src.contains("Top middle: your hearts")
		and not training_src.contains("Top left: your hearts"))
