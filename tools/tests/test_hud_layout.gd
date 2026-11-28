extends Node
## HUD cosmetic regressions (F27-F33). Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_hud_layout.tscn

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(640, 480)
	await get_tree().process_frame
	await _commands_panel()
	await _practice_notice()
	await _success_toast()
	_layers_and_draw_order()
	await _one_prompt_at_a_time()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _commands_panel() -> void:
	PlayerHud.hide_voice_commands_list()
	PlayerHud.update_live_transcript("hello there")
	var panel: Control = PlayerHud.get("_voice_commands_panel")
	_check("F27: a stray transcript does not open the commands panel", panel == null or not panel.visible)
	PlayerHud.show_voice_commands_list()
	panel = PlayerHud.get("_voice_commands_panel")
	PlayerHud.update_live_transcript("move left")
	for i in 4:
		await get_tree().process_frame
	var heard: Label = PlayerHud.get("_move_heard_label")
	_check("F27: heard line shows inside an open panel", heard.visible and heard.text == "Heard: move left")
	# Measure the real movement joystick in a landscape-phone touch layout.
	MobileSafeLayout.set_force_touch_ui(true)
	get_window().size = Vector2i(844, 390)
	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	for i in 8:
		await get_tree().process_frame
	controls._apply_safe_layout()
	for i in 4:
		await get_tree().process_frame
	var stick := controls.find_child("Joystick", true, false) as CanvasItem
	var stick_rect := stick.get_global_transform_with_canvas() * UiInputRouter.local_rect(stick)
	var rect := panel.get_global_rect()
	_check("F29: commands panel (with a heard line) clears the joystick",
			not rect.intersects(stick_rect), "panel %s stick %s" % [rect, stick_rect])
	controls.queue_free()
	MobileSafeLayout.set_force_touch_ui(false)
	get_window().size = Vector2i(640, 480)
	await get_tree().process_frame
	PlayerHud.hide_voice_commands_list()
	_check("F27: closing the panel clears the heard line", not heard.visible and heard.text == "")


func _practice_notice() -> void:
	var banner: Control = PlayerHud.voice_only_banner
	banner.visible = true
	PlayerHud.show_practice_notice()
	var notice: Label = PlayerHud.get("_practice_notice_label")
	_check("F28: practice notice sits below the voice banner",
			notice.offset_top >= banner.offset_bottom, "notice %.0f banner %.0f" % [notice.offset_top, banner.offset_bottom])
	await _wait(1.2)
	PlayerHud.show_practice_notice()
	await _wait(0.7)  # the first notice's fade would be half done by now
	_check("F28: a repeat notice is not faded by the old tween", notice.modulate.a > 0.99, str(notice.modulate.a))
	banner.visible = false
	await _wait(1.5)
	PlayerHud.show_notice("Boss beaten! +10 gems")
	_check("boss notice reuses the notice label", notice.text == "Boss beaten! +10 gems" and notice.visible, notice.text)
	PlayerHud.show_practice_notice()
	_check("practice notice keeps its text", notice.text == "Practice — you can't die here!", notice.text)
	await _wait(2.2)


func _success_toast() -> void:
	PlayerHud._show_success_toast(100)
	await _wait(0.5)  # first toast is fading (fade starts at 0.35 s)
	PlayerHud._show_success_toast(100)
	await _wait(0.2)
	var plate: Control = PlayerHud.get("_success_plate")
	_check("F32: a second toast is not faded by the old tween", plate.modulate.a > 0.99, str(plate.modulate.a))
	await _wait(1.0)


func _layers_and_draw_order() -> void:
	_check("F31: version badge sits under the pause menu", VersionOverlay.layer < PauseMenu.layer)
	_check("F31: version badge stays above the HUD", VersionOverlay.layer > PlayerHud.layer)
	var player: Player = PlayerManager.player
	var had_sword := PlayerManager.sword_equipped
	PlayerManager.sword_equipped = true
	var weapon := player.get_node("Sprite2D/WeaponSprite") as Sprite2D
	for dir in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		player.cardinal_direction = dir
		player.refresh_weapon_sprite()
		_check("F30: sword keeps z_index 0 facing %s" % player.anim_direction(), weapon.z_index == 0, str(weapon.z_index))
	PlayerManager.sword_equipped = had_sword
	player.refresh_weapon_sprite()
	var camera := player.find_children("*", "PlayerCamera", true, false)
	_check("F33: player camera keeps refitting while paused",
			not camera.is_empty() and (camera[0] as Node).process_mode == Node.PROCESS_MODE_ALWAYS)


## A conversation or speech card owns the screen: the optional-mic banner,
## the desktop Mic button and the battle card stay out of it.
func _one_prompt_at_a_time() -> void:
	var banner: Control = PlayerHud.voice_only_banner
	PlayerHud.mic_banner_fade_sec = 30.0
	PlayerHud.show_optional_mic_banner()
	_check("mic banner shows in play", banner.visible)

	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	await get_tree().process_frame
	controls._ensure_mic_button_visible()
	var desktop := not bool(controls.get("_touch_ui_enabled"))
	_check("desktop: no lone floating Mic button (the HUD plate is the switch)", not desktop or not controls.right_cluster.is_visible_in_tree())

	DialogSystem.show_conversation("Smith", null, 1, Callable())
	DialogSystem.show_say_box("A", "Hit harder")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("dialog hides the mic banner", not banner.visible)
	_check("dialog hides the desktop Mic button", not desktop or not controls.visible)
	_check("dialog never opens the battle card", not PlayerHud.challenge_panel.visible)
	var bar: Rect2 = DialogSystem.dialog_bar.get_global_rect()
	var box: Rect2 = DialogSystem.say_box.get_global_rect()
	_check("say box clear of the dialog bar", not box.intersects(bar), "box %s bar %s" % [box, bar])
	var portrait: Control = DialogSystem.portrait_slot
	_check("portrait capped", portrait.custom_minimum_size.y <= 112.0, str(portrait.custom_minimum_size))
	DialogSystem.close()
	await get_tree().process_frame
	# Portrait card: a framed square exactly as tall as the text box, beside it.
	var face := ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	DialogSystem.show_conversation("Cook", face, 1, Callable())
	DialogSystem.set_conversation_line("Pull up a log! Something to eat?")
	for i in 4:
		await get_tree().process_frame
	var panel: Rect2 = DialogSystem.text_panel.get_global_rect()
	var card: Rect2 = DialogSystem.portrait_slot.get_global_rect()
	_check("portrait as tall as the text box", DialogSystem.portrait_slot.visible and absf(card.size.y - panel.size.y) <= 2.0,
		"card %s panel %s" % [card, panel])
	_check("portrait top-aligned with the text box", absf(card.position.y - panel.position.y) <= 2.0,
		"card %s panel %s" % [card, panel])
	_check("portrait is square", absf(card.size.x - card.size.y) <= 2.0, str(card))
	_check("portrait sits left of the text box", card.end.x <= panel.position.x, "card %s panel %s" % [card, panel])
	DialogSystem.set_choices([{"id": "a", "label": "A  Apple"}, {"id": "b", "label": "B  Bye"}], func(_id): pass)
	await get_tree().process_frame
	_check("Leave sits with the choices (last chip)", DialogSystem.leave_button.get_parent() == DialogSystem.choice_row
		and DialogSystem.leave_button.get_index() == DialogSystem.choice_row.get_child_count() - 1)
	_check("one-line text box isn't a tall empty box", panel.size.y <= 70.0, str(panel.size))
	var wide: Rect2 = DialogSystem.bar_rect_for(Vector2(1280, 480))
	_check("wide screen: bar capped and centred", wide.size.x <= 600.0 and absf(wide.get_center().x - 640.0) <= 1.0, str(wide))
	var narrow: Rect2 = DialogSystem.bar_rect_for(Vector2(360, 640))
	_check("phone: bar fills the width", absf(narrow.size.x - 336.0) <= 1.0 and absf(narrow.position.x - 12.0) <= 1.0, str(narrow))
	_check("bar keeps a 12 px bottom gutter", absf(narrow.end.y - 628.0) <= 1.0, str(narrow))
	DialogSystem.close()
	await get_tree().process_frame
	_check("mic banner back after the dialog", banner.visible)
	_check("desktop: still no floating Mic button after the dialog", not desktop or not controls.right_cluster.is_visible_in_tree())

	PlayerHud.show_speech_challenge("cat")
	await get_tree().process_frame
	_check("speech card hides the mic banner", not banner.visible)
	PlayerHud.hide_speech_challenge()
	await get_tree().process_frame
	_check("mic banner back after the card", banner.visible)

	PlayerHud.mic_banner_fade_sec = 0.2
	PlayerHud.show_optional_mic_banner()
	await _wait(0.5)
	_check("mic hint fades by itself", not banner.visible)
	PlayerHud.hide_optional_mic_banner()
	controls.queue_free()
