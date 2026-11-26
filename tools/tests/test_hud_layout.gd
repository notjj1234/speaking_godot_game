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
