extends Node2D
## Tester-pass fixes, phase 3: touch buttons and phone layout. The attack
## button is a sword, Interact only shows when there's something to use, the
## hearts are bigger, and a portrait phone's map fills the space above the
## controls instead of leaving a big empty band.

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
	await _test_touch_buttons()
	_test_hearts()
	_test_portrait_layout()
	await _test_robustness()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_touch_buttons() -> void:
	MobileSafeLayout.set_force_touch_ui(true)
	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	await _frames(3)
	var tex: Texture2D = controls.attack_button.texture_normal
	_check("attack button shows a sword", tex != null and tex.resource_path.ends_with("AttackSword.png"),
		tex.resource_path if tex else "")
	_check("Interact hidden with nothing nearby", not controls.interact_button.visible)
	controls.set_talk_prompt(true, "Open")
	_check("near a chest: 'Open' shows", controls.interact_button.visible and controls.interact_button.text == "Open",
		controls.interact_button.text)
	controls.set_talk_prompt(false)
	_check("walked away: hidden again", not controls.interact_button.visible)
	controls.set_talk_prompt(true)
	_check("near an NPC: 'Talk'", controls.interact_button.visible and controls.interact_button.text == "Talk")
	controls.set_talk_prompt(false)
	controls.queue_free()
	MobileSafeLayout.set_force_touch_ui(false)
	await _frames()


func _test_hearts() -> void:
	var row := PlayerHud.get_node("Control/HFlowContainer") as Control
	_check("hearts drawn bigger", row.scale.x >= 1.25, str(row.scale))
	_check("LIFE label drawn bigger", PlayerHud.life_sprite.scale.x >= 1.25, str(PlayerHud.life_sprite.scale))
	var vis := Rect2(0, 0, 640, 480)
	var hearts_rect: Rect2 = MobileSafeLayout._hud_rects(vis)[0]
	_check("HUD keep-out rect covers the bigger hearts", hearts_rect.size.x >= 130.0 * row.scale.x, str(hearts_rect))


func _test_portrait_layout() -> void:
	var vis := Rect2(0, 0, 640, 1280)
	var h: float = MobileSafeLayout.portrait_arena_height(vis, 1.0)
	_check("portrait: the map gets more than the old 480 px", h > 600.0, str(h))
	var band := vis.size.y - MobileSafeLayout.PORTRAIT_ARENA_TOP - h
	_check("portrait: the controls still have their band", band >= MobileSafeLayout.LEFT_CLUSTER_SIZE.y, str(band))
	var z: float = PlayerCamera.portrait_zoom(Vector2(640, 1280), Vector2(640, 480), h)
	_check("portrait: camera zooms so the map fills that height", z > 1.2 and z <= PlayerCamera.MAX_COVER_ZOOM, str(z))


## Phase 4: a beaten enemy's "0/3" bar goes away, a freed body can't spam
## errors in the horde HUD check, and the journal never outlives a level.
func _test_robustness() -> void:
	var e: Enemy = load("res://enemies/slime/slime.tscn").instantiate()
	e.hp = 1
	add_child(e)
	e.global_position = Vector2(3000, 3000)
	await get_tree().physics_frame
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)
	e._take_damage(killer)
	await _frames()
	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	await get_tree().create_timer(0.8, true, false, true).timeout
	_check("beaten enemy: health bar hidden while it dies", not is_instance_valid(e) or not e.health_bar.visible)
	get_tree().paused = false

	var hw: Node2D = load("res://levels/endless_horde/horde_waves.gd").new()
	var gone := Node2D.new()
	gone.free()
	var under = hw._under_hud(gone, [] as Array[Rect2])
	_check("horde HUD check: a freed body is just 'not under'", under is bool and under == false, str(under))
	hw.free()

	ProgressTracker.show_journal()
	await _frames()
	LevelManager.level_load_started.emit()
	await _frames()
	_check("journal closes when a level loads", not ProgressTracker.is_journal_open())
