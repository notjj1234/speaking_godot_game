extends Node2D
## Tester-pass fixes, phase 2: menus. Settings tells the truth (fullscreen,
## difficulty explained, Touch Controls actually applies), the journal's Close
## doesn't look like a tab, and the title hides Load with no save.

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
	await _test_settings()
	await _test_journal_close()
	await _test_title_load()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_settings() -> void:
	var s: SettingsNode = load("res://gui/settings/settings.tscn").instantiate()
	add_child(s)
	await _frames()
	s.show_settings()
	await _frames()
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	_check("fullscreen row shows the real window mode", s.fullscreen_button.text == ("On" if full else "Off"), s.fullscreen_button.text)
	_check("difficulty is explained", s.difficulty_hint != null and s.difficulty_hint.text != "", str(s.difficulty_hint))
	var before: String = s.difficulty_hint.text
	s._on_difficulty_pressed()
	_check("difficulty hint follows the choice", s.difficulty_hint.text != before, s.difficulty_hint.text)
	s._on_difficulty_pressed()
	s._on_difficulty_pressed()
	var reset_box := s.reset_button.get_theme_stylebox("normal") as StyleBoxFlat
	_check("reset is a red button", reset_box != null and reset_box.bg_color.r > 0.5 and reset_box.bg_color.g < 0.35)

	var controls: Node = load("res://touch_controls/Scene/touch_controls.tscn").instantiate()
	add_child(controls)
	await _frames()
	SettingsManager.set_touch_controls_forced(true)
	await _frames()
	_check("Touch Controls: On really shows them", MobileSafeLayout.wants_touch_ui() and controls.get("_touch_ui_enabled") == true)
	SettingsManager.set_touch_controls_forced(false)
	await _frames()
	_check("Touch Controls: Auto goes back to detection", not MobileSafeLayout.wants_touch_ui())
	controls.queue_free()
	s.queue_free()
	await _frames()


func _test_journal_close() -> void:
	ProgressTracker.show_journal()
	await _frames()
	var j = ProgressTracker.get("_journal")
	_check("journal: Close, not Back", j != null and j._back.text == "Close", j._back.text if j else "")
	var tab_box := j._tab_today.get_theme_stylebox("normal") as StyleBoxFlat
	var close_box := j._back.get_theme_stylebox("normal") as StyleBoxFlat
	_check("journal: Close looks different from the tabs", close_box.bg_color != tab_box.bg_color
		and close_box.bg_color != (j._tab_phrases.get_theme_stylebox("normal") as StyleBoxFlat).bg_color)
	ProgressTracker.hide_journal()
	await _frames()


func _test_title_load() -> void:
	if FileAccess.file_exists("user://save.sav"):
		DirAccess.remove_absolute("user://save.sav")
	var title: Node = load("res://levels/title_screen/title_screen.tscn").instantiate()
	add_child(title)
	await get_tree().create_timer(1.5, true, false, true).timeout  # title fades in first
	_check("title: no save, no Load button", not title.load_button.visible)
	_check("title: real arena behind the menu", title.find_child("TitleArena", true, false) != null)
	title.apply_menu_size(true)
	_check("title: portrait phones get big buttons", title.tutorial_button.custom_minimum_size.y >= 56.0)
	title.apply_menu_size(false)
	title.queue_free()
	await _frames()
