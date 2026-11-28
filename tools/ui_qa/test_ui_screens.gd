extends "res://tools/ui_qa/pointer_driver.gd"
## One press, one effect, on the real screens. Run headless:
##   python3.13 tools/ui_qa/run_headless_tests.py

const TUTORIAL_BANNER := "res://levels/tutorial_items/tutorial_dialog.gd"

var probe: Node
var interacts := 0
var action_downs: Array[String] = []


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventAction and event.pressed:
		action_downs.append(String(event.action))


func centre(item: CanvasItem) -> Vector2:
	return item.get_global_transform_with_canvas() * UiInputRouter.local_rect(item).get_center()


## Click or tap the middle of a node, after letting the 80 ms twin window lapse.
func press(item: CanvasItem, with_finger: bool = false) -> void:
	await get_tree().create_timer(0.12, true).timeout
	if with_finger:
		await tap(centre(item))
	else:
		await click(centre(item))


## Probe the current screen: no unexpected live overlaps, and `panel` fits.
func screen_ok(label: String, panel: Control = null) -> void:
	await frames(4)
	check(label + ": probe finds no unexpected overlap", probe.dump(), 0)
	if panel:
		var rect := panel.get_global_rect()
		var view := panel.get_viewport_rect()
		check(label + ": panel fits the 640x480 viewport %s" % rect, view.grow(0.5).encloses(rect), true)


func _ready() -> void:
	get_window().size = Vector2i(640, 480)
	probe = (load("res://tools/ui_qa/ui_overlap_probe.gd") as GDScript).new()
	add_child(probe)
	PlayerManager.interact_pressed.connect(func(): interacts += 1)
	await frames(10)
	await _settings()
	await _pause_menu()
	await _journal()
	await _game_over()
	await _dialog()
	await _hud()
	await _title()
	await _coming_soon()
	await _tutorial_banner()
	await _overlays_and_loading()
	finish()


func _settings() -> void:
	var s = load("res://gui/settings/settings.tscn").instantiate()
	add_child(s)
	await frames()
	var m := get_node("/root/SettingsManager")
	s.show_settings()
	await screen_ok("settings", s.panel)

	var before := int(m.speech_difficulty)
	await press(s.difficulty_button)
	check("settings: one click steps difficulty once", int(m.speech_difficulty), (before + 1) % 3)
	await press(s.difficulty_button, true)
	check("settings: one finger tap steps difficulty once", int(m.speech_difficulty), (before + 2) % 3)
	check("settings: tapping Difficulty never arms Reset", s.reset_button.text, "Reset")
	await press(s.reset_button)
	check("settings: one click only arms Reset", s.reset_button.text, "Confirm?")
	await press(s.close_button)
	check("settings: Close first disarms Reset", [s.reset_button.text, s.visible], ["Reset", true])

	var muted: bool = m.music_muted
	await press(s.music_mute_button)
	check("settings: one click flips music mute once", m.music_muted, not muted)
	await press(s.music_mute_button)
	check("settings: second click flips it back", m.music_muted, muted)
	var language: String = m.stt_language
	await press(s.language_button)
	check("settings: language advances one step",
			s.LANGUAGES.find(m.stt_language), (s.LANGUAGES.find(language) + 1) % s.LANGUAGES.size())

	before = int(m.speech_difficulty)
	s.difficulty_button.grab_focus()
	await key_accept()
	check("settings: keyboard accept steps difficulty once", int(m.speech_difficulty), (before + 1) % 3)

	await press(s.close_button)
	check("settings: Close hides the screen", s.visible, false)
	check("settings: its layer is popped", UiInputRouter.active_layer(), 0)
	s.queue_free()
	await frames()


func _pause_menu() -> void:
	var menu := PauseMenu
	menu.show_pause_menu()
	await screen_ok("pause", menu.get_node("Control/MenuRoot/Center/MenuCard"))

	var m := get_node("/root/SettingsManager")
	m.set_music_muted(false)
	m.set_music_volume(0.5)
	await press(menu.music_quieter_button)
	check("pause: '-' lowers volume by one step", snappedf(m.music_volume, 0.01), 0.4)
	await press(menu.music_mute_button, true)
	check("pause: one tap mutes once", m.music_muted, true)
	await press(menu.music_mute_button)
	check("pause: one click unmutes once", m.music_muted, false)
	menu.music_louder_button.grab_focus()
	await key_accept()
	check("pause: keyboard '+' raises volume one step", snappedf(m.music_volume, 0.01), 0.5)

	# Inventory: one click must use exactly one item.
	var grid: Node = menu.get_node("Control/MenuRoot/Center/MenuCard/Card/Columns/LeftColumn/PanelContainer/GridContainer")
	var slot: Node = null
	if slot == null:
		var data: SlotData = SlotData.new()
		# No shipped item has a use effect, so build one that is consumed on use.
		data.item_data = ItemData.new()
		data.item_data.effects.append(ItemEffect.new())
		data.quantity = 5
		grid.data.slots[0] = data
		grid.data.changed.emit()
		await frames(5)
		slot = grid.get_child(0)
	slot.slot_data.quantity = 5
	await press(slot)
	check("pause: one click uses exactly one inventory item", slot.slot_data.quantity, 4)
	await press(slot, true)
	check("pause: one tap uses exactly one inventory item", slot.slot_data.quantity, 3)

	await press(menu.button_settings)
	var settings = menu._settings_node
	check("pause: Settings opens", settings != null and settings.visible, true)
	await press(menu.get_node("Control/CloseIcon"))
	check("pause: the X under Settings is inert", menu.is_paused, true)
	await press(settings.close_button)
	check("pause: closing Settings returns to pause", [settings.visible, menu.is_paused], [false, true])

	SaveManager.save_game()
	await press(menu.button_load)
	await frames(3)
	var confirm: Control = menu.load_confirm
	check("pause: Load asks first", confirm.visible, true)
	await screen_ok("pause load confirm")
	m.set_music_muted(false)
	await press(menu.music_mute_button)
	check("pause: buttons under the load confirm are inert", m.music_muted, false)
	await press(menu.load_cancel_button)
	check("pause: Cancel closes only the confirm", [confirm.visible, menu.is_paused], [false, true])

	await press(menu.get_node("Control/CloseIcon"))
	check("pause: the X closes the menu", [menu.is_paused, get_tree().paused], [false, false])
	check("pause: its layer is popped", UiInputRouter.active_layer(), 0)


func _journal() -> void:
	PauseMenu.show_pause_menu()
	await frames()
	await press(PauseMenu.journal_button)
	var journal = ProgressTracker._journal
	check("journal: opens from pause", journal != null and journal.visible, true)
	await screen_ok("journal today", journal._panel)

	await press(journal._tab_phrases)
	check("journal: Phrases tab", journal._tab, 1)
	await screen_ok("journal phrases", journal._panel)
	await press(journal._tab_bestiary, true)
	check("journal: Bestiary tab by finger", journal._tab, 2)
	await screen_ok("journal bestiary", journal._panel)
	journal._tab_today.grab_focus()
	await key_accept()
	check("journal: keyboard switches tab", journal._tab, 0)

	await get_tree().create_timer(0.12, true).timeout
	await click(journal._panel.get_global_rect().position + Vector2(8, 8))
	check("journal: a tap on the panel itself keeps it open", journal.visible, true)
	await get_tree().create_timer(0.12, true).timeout
	await click(Vector2(6, 6))
	check("journal: a tap outside closes it", [journal.visible, PauseMenu.is_paused], [false, true])
	await press(PauseMenu.journal_button)
	await press(journal._back)
	check("journal: Back closes only the journal", [journal.visible, PauseMenu.is_paused], [false, true])
	PauseMenu.hide_pause_menu()
	await frames()


func _game_over() -> void:
	# show_defeat() now loads the camp; exercise this fallback screen itself.
	GameOver._open()
	await screen_ok("game over")
	check("game over: owns the top layer", UiInputRouter.active_layer() > 0, true)
	GameOver._navigating = true  # keep the test from changing scene
	await press(GameOver.title_button)
	check("game over: tap leaves it open while already navigating", GameOver.visible, true)
	GameOver.visible = false
	GameOver._close_layer()
	get_tree().paused = false
	GameOver._restore_audio()


func _dialog() -> void:
	DialogSystem.show_dialog("A", null, PackedStringArray(["one", "two", "three", "four"]), Callable(), 1)
	await screen_ok("dialog")
	await press(DialogSystem.dialog_bar)
	check("dialog: one click advances one line", DialogSystem._index, 1)
	await press(DialogSystem.dialog_bar, true)
	check("dialog: one tap advances one line", DialogSystem._index, 2)
	DialogSystem.close()
	check("dialog: its layer is popped", UiInputRouter.active_layer(), 0)
	await frames()


func _hud() -> void:
	var hud = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	var pause_button = load("res://touch_controls/Scene/pause_button.tscn").instantiate()
	add_child(hud)
	add_child(pause_button)
	await frames()
	MobileSafeLayout.set_force_touch_ui(true)
	hud.apply_touch_ui_enabled()
	pause_button.apply_touch_ui_enabled()
	PlayerManager.player.visible = true
	PlayerManager.set_process(true)
	PlayerManager.player.set_process(true)
	await screen_ok("gameplay HUD")

	var right: Node = hud.right_cluster
	var left: Node = hud.left_cluster
	var attack: TouchScreenButton = right.get_node("Attack")
	var machine: PlayerStateMachine = PlayerManager.player.state_machine

	# attack: consumed by state_idle / state_walk handle_input(event)
	await get_tree().create_timer(0.8, true).timeout
	action_downs.clear()
	await press(attack, true)
	check("hud: Attack delivers one attack event", action_downs.count("attack"), 1)
	check("hud: the player state machine entered Attack",
			[String(machine.current_state.name), String(machine.prev_state.name)].has("Attack"), true)
	check("hud: attack is released after the finger lifts", Input.is_action_pressed(&"attack"), false)
	await get_tree().create_timer(0.8, true).timeout

	# interact: state_idle emits PlayerManager.interact_pressed
	interacts = 0
	await press(hud.interact_button)
	check("hud: one click on Interact emits interact_pressed once", interacts, 1)
	await press(hud.interact_button, true)
	check("hud: one tap on Interact emits interact_pressed once", interacts, 2)

	action_downs.clear()
	await press(hud.mic_button)
	check("hud: Mic is a label to GUI", [hud.mic_button.mouse_filter, hud.mic_button.focus_mode],
			[Control.MOUSE_FILTER_IGNORE, Control.FOCUS_NONE])
	check("hud: Mic drives no input action", action_downs, [] as Array[String])

	# Joystick: FIXED VirtualJoystickAddon; press NE of centre for an 8-way diagonal.
	var stick: Control = left.get_node("Joystick")
	var stick_ne: Vector2 = centre(stick) + Vector2(50, -50)
	await touch(stick_ne, true, 0)
	check("hud: joystick NE presses up+right",
			[Input.is_action_pressed(&"up"), Input.is_action_pressed(&"right")], [true, true])
	await touch(stick_ne, false, 0)
	check("hud: lifting the joystick releases movement",
			[Input.is_action_pressed(&"up"), Input.is_action_pressed(&"right")], [false, false])

	# Under every overlay the whole cluster is gone and held input is released.
	await touch(centre(attack), true, 0)
	await touch(stick_ne, true, 1)
	PauseMenu.show_pause_menu()
	await frames(4)
	check("hud: opening pause releases held Attack", Input.is_action_pressed(&"attack"), false)
	check("hud: opening pause releases the joystick", Input.is_action_pressed(&"up"), false)
	check("hud: cluster and pause button are suppressed", [hud.visible, pause_button.visible], [false, false])
	await touch(centre(attack), false, 0)
	await touch(stick_ne, false, 1)
	PauseMenu.hide_pause_menu()
	await frames()
	check("hud: cluster returns after pause", [hud.visible, pause_button.visible], [true, true])

	DialogSystem.show_dialog("A", null, PackedStringArray(["one", "two"]), Callable(), 1)
	await frames(4)
	check("hud: dialog suppresses the cluster too", hud.visible, false)
	await touch(stick_ne, true, 0)
	check("hud: the joystick under a dialog is inert", Input.is_action_pressed(&"up"), false)
	await touch(stick_ne, false, 0)
	DialogSystem.close()
	await frames()

	# pause: pause_menu._unhandled_input reads the event
	var pause_visual: TouchScreenButton = pause_button.get_node("Root/TopRight/Pause")
	await press(pause_visual, true)
	check("hud: the pause button opens the pause menu once", PauseMenu.is_paused, true)
	PauseMenu.hide_pause_menu()
	await frames()
	await press(pause_visual)
	check("hud: a desktop click opens it once (no open-then-close)", PauseMenu.is_paused, true)
	PauseMenu.hide_pause_menu()

	MobileSafeLayout.set_force_touch_ui(false)
	hud.queue_free()
	pause_button.queue_free()
	await frames()


func _title() -> void:
	# The title only offers Load for a save that names a scene.
	var save := FileAccess.open("user://save.sav", FileAccess.WRITE)
	save.store_line(JSON.stringify({"scene_path": "res://levels/playground.tscn",
			"player": {"hp": 6, "max_hp": 6}}))
	save.close()
	var title = load("res://levels/title_screen/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().create_timer(1.5, true).timeout
	get_tree().paused = false
	await screen_ok("title")

	await press(title.load_button)
	check("title: Load opens the confirm", title.load_confirm.visible, true)
	await screen_ok("title load confirm")
	await press(title.settings_button)
	check("title: a menu button under LoadConfirm is inert",
			[title._settings_node, title.load_confirm.visible], [null, true])
	await press(title.no_button)
	check("title: No closes it without reopening", title.load_confirm.visible, false)
	await press(title.load_button, true)
	check("title: Load works again right away", title.load_confirm.visible, true)
	title.no_button.grab_focus()
	await key_accept()
	check("title: keyboard No closes it", title.load_confirm.visible, false)

	await press(title.journal_button)
	check("title: Journal opens", ProgressTracker.is_journal_open(), true)
	await press(ProgressTracker._journal._back)
	check("title: Back closes it", ProgressTracker.is_journal_open(), false)

	await press(title.settings_button)
	check("title: Settings opens", title._settings_node != null and title._settings_node.visible, true)
	await press(title.load_button)
	check("title: Load under Settings is inert", title.load_confirm.visible, false)
	await press(title._settings_node.close_button)

	if title.exit_button.visible:
		await press(title.exit_button)
		check("title: Exit asks first", title.exit_confirm.visible, true)
		await screen_ok("title exit confirm")
		await press(title.exit_no_button)
		check("title: Exit No closes it", title.exit_confirm.visible, false)

	title.tutorial_button.grab_focus()
	await _ui_key(KEY_DOWN)
	check("title: arrow keys still walk the focus ring",
			get_viewport().gui_get_focus_owner() == title.game_button, true)

	title.queue_free()
	await frames()
	check("title: no layer outlives the screen", UiInputRouter.active_layer(), 0)


func _ui_key(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames()


func _coming_soon() -> void:
	var screen = load("res://levels/coming_soon/coming_soon.tscn").instantiate()
	add_child(screen)
	await get_tree().create_timer(1.5, true).timeout
	await screen_ok("coming soon")
	screen._navigating = true  # keep the test from changing scene
	var activations: Array = []
	var spy := func(item: Object): activations.append(item)
	UiInputRouter.activated.connect(spy)
	await press(screen.back_button)
	check("coming soon: one click is one activation", activations.size(), 1)
	UiInputRouter.activated.disconnect(spy)
	screen.queue_free()
	await frames()


func _tutorial_banner() -> void:
	var banner := Control.new()
	var background := Panel.new()
	background.name = "DialogBackground"
	var label := Label.new()
	label.name = "DialogLabel"
	background.add_child(label)
	banner.add_child(background)
	banner.set_script(load(TUTORIAL_BANNER))
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(banner)
	await frames(4)
	banner.messages = ["one", "two", "three"]
	banner.show_message(0)
	await frames()
	await press(banner)
	check("tutorial banner: one click advances one message", banner.current_index, 1)
	layer.queue_free()
	await frames()


## The pause key as the keyboard and the touch pause button deliver it.
func _press_pause() -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"pause"
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames()


func _overlays_and_loading() -> void:
	check("pause: drawn above the HUD and the dialog bar",
			PauseMenu.layer > PlayerHud.layer and PauseMenu.layer > DialogSystem.layer, true)

	DialogSystem.show_dialog("A", null, PackedStringArray(["one"]), Callable(), 1)
	await frames()
	await _press_pause()
	check("pause: does not open over a dialog", PauseMenu.is_paused, false)
	DialogSystem.close()
	if PauseMenu.is_paused:
		PauseMenu.hide_pause_menu()
	await frames()

	LevelManager.is_loading = true
	await _press_pause()
	check("pause: does not open during a level load", PauseMenu.is_paused, false)
	LevelManager.is_loading = false
	if PauseMenu.is_paused:
		PauseMenu.hide_pause_menu()

	PauseMenu.show_pause_menu()
	await frames()
	PauseMenu._on_save_pressed()
	await press(PauseMenu.journal_button)
	await get_tree().create_timer(1.0, true).timeout
	check("pause: Save then Journal stays paused", [PauseMenu.is_paused, get_tree().paused], [true, true])
	ProgressTracker.hide_journal()
	PauseMenu.hide_pause_menu()
	await frames()

	# Tutorial levels host their bubble on a plain layer, not a second HUD.
	for path in ["res://levels/playground.tscn", "res://levels/tutorial_area/01.tscn",
			"res://levels/tutorial_area/02.tscn", "res://levels/tutorial_area/03.tscn"]:
		var state := (load(path) as PackedScene).get_state()
		var hud_copy := false
		for i in state.get_node_count():
			if state.get_node_name(i) == &"PlayerHud" and state.get_node_instance(i) != null:
				hud_copy = true
		check("%s: no second PlayerHud instance" % path.get_file(), hud_copy, false)
