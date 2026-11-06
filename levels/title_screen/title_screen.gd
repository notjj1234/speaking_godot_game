# title_screen.gd

extends CanvasLayer

const PLAYGROUND_PATH := "res://levels/playground.tscn"
const ENDLESS_HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const SAVE_FILE_PATH := "user://save.sav"

@onready var tutorial_button: Button = $Control/CenterContainer/VBoxContainer/StartTutorial
@onready var game_button: Button = $Control/CenterContainer/VBoxContainer/StartGame
@onready var load_button: Button = $Control/CenterContainer/VBoxContainer/Load
@onready var journal_button: Button = $Control/CenterContainer/VBoxContainer/Journal
@onready var touch_tutorial_button: TouchScreenButton = $Control/TouchStartTutorial
@onready var touch_game_button: TouchScreenButton = $Control/TouchStartGame
@onready var touch_load_button: TouchScreenButton = $Control/TouchLoad
@onready var touch_journal_button: TouchScreenButton = $Control/TouchJournal
@onready var load_confirm: Control = %LoadConfirm
@onready var location_label: Label = %LocationLabel
@onready var hp_label: Label = %HpLabel
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton
@onready var touch_load_yes: TouchScreenButton = %TouchLoadYes
@onready var touch_load_no: TouchScreenButton = %TouchLoadNo

var _navigating: bool = false
## No sits on top of the centered Load button. The same click that dismisses
## Continue? must not reopen it, so menu twins stay hidden until pointer-up.
var _suppress_load_open: bool = false
var _hold_menu_until_release: bool = false


func _ready() -> void:
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	await SceneTransition.fade_in()

	tutorial_button.mouse_filter = Control.MOUSE_FILTER_STOP
	game_button.mouse_filter = Control.MOUSE_FILTER_STOP
	load_button.mouse_filter = Control.MOUSE_FILTER_STOP
	journal_button.mouse_filter = Control.MOUSE_FILTER_STOP
	yes_button.mouse_filter = Control.MOUSE_FILTER_STOP
	no_button.mouse_filter = Control.MOUSE_FILTER_STOP

	tutorial_button.pressed.connect(_on_tutorial_pressed)
	game_button.pressed.connect(_on_game_pressed)
	load_button.pressed.connect(_on_load_pressed)
	journal_button.pressed.connect(_on_journal_pressed)
	yes_button.pressed.connect(_on_load_yes_pressed)
	no_button.pressed.connect(_on_load_no_pressed)
	touch_tutorial_button.pressed.connect(_on_tutorial_pressed)
	touch_game_button.pressed.connect(_on_game_pressed)
	touch_load_button.pressed.connect(_on_load_pressed)
	touch_journal_button.pressed.connect(_on_journal_pressed)
	# Confirm Yes/No: do not rely on TouchScreenButton twins. With
	# emulate_touch_from_mouse, misaligned twins make No a dead click.
	# _input hit-tests the real button rects instead (see below).
	touch_load_yes.visible = false
	touch_load_no.visible = false

	# Twins stay visible (no texture) so desktop mouse clicks still land:
	# emulate_touch_from_mouse is on and emulate_mouse_from_touch is off.
	touch_tutorial_button.visible = true
	touch_game_button.visible = true
	touch_load_button.visible = true
	touch_journal_button.visible = true

	tutorial_button.focus_neighbor_bottom = tutorial_button.get_path_to(game_button)
	tutorial_button.focus_next = tutorial_button.get_path_to(game_button)
	tutorial_button.focus_neighbor_top = tutorial_button.get_path_to(journal_button)
	tutorial_button.focus_previous = tutorial_button.get_path_to(journal_button)
	game_button.focus_neighbor_top = game_button.get_path_to(tutorial_button)
	game_button.focus_previous = game_button.get_path_to(tutorial_button)
	game_button.focus_neighbor_bottom = game_button.get_path_to(load_button)
	game_button.focus_next = game_button.get_path_to(load_button)
	load_button.focus_neighbor_top = load_button.get_path_to(game_button)
	load_button.focus_previous = load_button.get_path_to(game_button)
	load_button.focus_neighbor_bottom = load_button.get_path_to(journal_button)
	load_button.focus_next = load_button.get_path_to(journal_button)
	journal_button.focus_neighbor_top = journal_button.get_path_to(load_button)
	journal_button.focus_previous = journal_button.get_path_to(load_button)
	journal_button.focus_neighbor_bottom = journal_button.get_path_to(tutorial_button)
	journal_button.focus_next = journal_button.get_path_to(tutorial_button)

	yes_button.focus_neighbor_right = yes_button.get_path_to(no_button)
	yes_button.focus_next = yes_button.get_path_to(no_button)
	yes_button.focus_neighbor_left = yes_button.get_path_to(no_button)
	yes_button.focus_previous = yes_button.get_path_to(no_button)
	no_button.focus_neighbor_left = no_button.get_path_to(yes_button)
	no_button.focus_previous = no_button.get_path_to(yes_button)
	no_button.focus_neighbor_right = no_button.get_path_to(yes_button)
	no_button.focus_next = no_button.get_path_to(yes_button)

	tutorial_button.grab_focus()

	load_button.disabled = not SaveManager.has_save()
	load_confirm.visible = false
	touch_load_yes.visible = false
	touch_load_no.visible = false

	_hide_gameplay_ui()
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_align_menu_touch_buttons)
	_align_menu_touch_buttons()
	call_deferred("_align_menu_touch_buttons")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_align_menu_touch_buttons()


func _process(_delta: float) -> void:
	_align_menu_touch_buttons()


func _input(event: InputEvent) -> void:
	if _pointer_released(event):
		if _hold_menu_until_release:
			_hold_menu_until_release = false
			_suppress_load_open = false
			if not _navigating and not load_confirm.visible:
				_unlock_load()
				_show_menu_twins()
		return
	if not load_confirm.visible or _navigating:
		return
	# emulate_touch_from_mouse turns clicks into ScreenTouch; GUI Buttons never
	# see them. Hit-test Yes/No by their laid-out rects so both sides work.
	var tap_pos := _pointer_press_pos(event)
	if tap_pos == Vector2.INF:
		return
	if no_button.get_global_rect().has_point(tap_pos):
		_on_load_no_pressed()
		get_viewport().set_input_as_handled()
	elif yes_button.get_global_rect().has_point(tap_pos):
		_on_load_yes_pressed()
		get_viewport().set_input_as_handled()


func _pointer_press_pos(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch and event.pressed:
		return event.position
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		return event.position
	return Vector2.INF


func _pointer_released(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and not event.pressed:
		return true
	if event is InputEventMouseButton \
			and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not load_confirm.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_load_no_pressed()
		get_viewport().set_input_as_handled()


func _align_menu_touch_buttons() -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	# While Continue? is open, or until the dismissing click releases, do not
	# move TouchLoad back onto Load — that same click would reopen the card.
	if load_confirm.visible or _hold_menu_until_release:
		return
	_align_touch_button(tutorial_button, touch_tutorial_button)
	_align_touch_button(game_button, touch_game_button)
	_align_touch_button(load_button, touch_load_button)
	_align_touch_button(journal_button, touch_journal_button)


func _align_touch_button(button: Control, touch: TouchScreenButton) -> void:
	if button == null or touch == null:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _on_tutorial_pressed() -> void:
	if _navigating or load_confirm.visible:
		return
	_navigating = true
	print("Starting Tutorial...")
	_prime_web_mic()
	_restore_game_ui()
	# Spawn at PlayerSpawn (center of playground), not PlaygroundTo01 (top edge —
	# that transition would immediately pull the player into tutorial area 01).
	# Empty target + player_spawned=false lets player_spawn.gd place the player.
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(PLAYGROUND_PATH, "", Vector2.ZERO)


func _on_game_pressed() -> void:
	if _navigating or load_confirm.visible:
		return
	_navigating = true
	print("✅ Starting Endless Horde...")
	_prime_web_mic()
	_restore_game_ui()
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(ENDLESS_HORDE_PATH, "", Vector2.ZERO)


func _on_load_pressed() -> void:
	if load_button.disabled or _navigating or load_confirm.visible or _suppress_load_open or _hold_menu_until_release:
		return
	if not SaveManager.has_save():
		return
	var data := _read_save_dict()
	var scene_path := str(data.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		print("❌ Load: save has empty scene_path")
		return
	_show_load_confirm(data)


func _on_load_yes_pressed() -> void:
	if _navigating or not load_confirm.visible:
		return
	if not SaveManager.has_save():
		_close_load_confirm()
		return
	var scene_path := _read_save_scene_path()
	if scene_path.is_empty():
		print("❌ Load: save has empty scene_path")
		_close_load_confirm()
		return
	_navigating = true
	_suppress_load_open = true
	_set_load_confirm_visible(false)
	print("✅ Loading saved game...")
	_prime_web_mic()
	_restore_game_ui()
	# Do not touch player_spawned — mirrors pause-menu Load so PlayerSpawn
	# does not overwrite the restored save position.
	SaveManager.load_game()
	await LevelManager.level_load_started


func _on_load_no_pressed() -> void:
	if _navigating or not load_confirm.visible:
		return
	_close_load_confirm()


func _show_load_confirm(data: Dictionary) -> void:
	location_label.text = _format_location_line(data)
	hp_label.text = _format_hp_line(data)
	_lock_load()
	_set_load_confirm_visible(true)
	yes_button.grab_focus()


func _close_load_confirm() -> void:
	# Keep Load disabled and its touch target off-screen until this click ends.
	_lock_load()
	_suppress_load_open = true
	_hold_menu_until_release = true
	_set_load_confirm_visible(false)
	# Pointer-up may never arrive on web. Keep Load dead through this click,
	# then turn it back on.
	_release_load_lock.call_deferred()
	print("✅ Load confirm closed")


func _lock_load() -> void:
	load_button.disabled = true
	load_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_load_button.visible = false
	touch_load_button.position = Vector2(-4000, -4000)
	if touch_load_button.shape is RectangleShape2D:
		(touch_load_button.shape as RectangleShape2D).size = Vector2.ZERO


func _set_load_confirm_visible(open: bool) -> void:
	if load_confirm:
		load_confirm.visible = open
	# While the card is up (or until twins restore), menu twins must stay off.
	touch_tutorial_button.visible = false
	touch_game_button.visible = false
	touch_load_button.visible = false
	touch_journal_button.visible = false
	touch_load_yes.visible = false
	touch_load_no.visible = false


func _release_load_lock() -> void:
	# One frame is enough to finish the No click; 0.4s felt like Load was broken.
	await get_tree().process_frame
	if _navigating or (load_confirm != null and load_confirm.visible):
		return
	_hold_menu_until_release = false
	_suppress_load_open = false
	_unlock_load()
	_show_menu_twins()


func _unlock_load() -> void:
	load_button.disabled = not SaveManager.has_save()
	load_button.mouse_filter = Control.MOUSE_FILTER_STOP


func _show_menu_twins() -> void:
	touch_tutorial_button.visible = true
	touch_game_button.visible = true
	touch_load_button.visible = true
	touch_journal_button.visible = true
	touch_load_yes.visible = false
	touch_load_no.visible = false
	_align_menu_touch_buttons()


func _format_location_line(data: Dictionary) -> String:
	var scene_path := str(data.get("scene_path", "")).strip_edges()
	var place := _friendly_place_name(scene_path)
	var stage := _stage_from_save(data)
	if stage > 0:
		return "%s  —  Stage %d" % [place, stage]
	return place


func _format_hp_line(data: Dictionary) -> String:
	var player = data.get("player", {})
	if not (player is Dictionary):
		return "HP  ?  /  ?"
	var hp := int(player.get("hp", 0))
	var max_hp := int(player.get("max_hp", 0))
	return "HP  %d  /  %d" % [hp, max_hp]


func _friendly_place_name(scene_path: String) -> String:
	var path := scene_path.to_lower()
	if "endless_horde" in path:
		return "Endless Horde"
	if "playground" in path:
		return "Tutorial"
	if scene_path.is_empty():
		return "Unknown lands"
	var file := scene_path.get_file().get_basename().replace("_", " ")
	if file.is_empty():
		return "Unknown lands"
	return file.capitalize()


func _stage_from_save(data: Dictionary) -> int:
	var progress = data.get("progress", {})
	if not (progress is Dictionary):
		return 0
	var horde_run = progress.get("horde_run", {})
	if horde_run is Dictionary:
		var resume := int(horde_run.get("resume_stage", 0))
		if resume > 0:
			return resume
	var lifetime = progress.get("lifetime", {})
	if lifetime is Dictionary:
		return int(lifetime.get("best_stage", 0))
	return 0


func _read_save_scene_path() -> String:
	return str(_read_save_dict().get("scene_path", "")).strip_edges()


func _read_save_dict() -> Dictionary:
	# Peek only — does not restore HP/inventory. SaveManager.load_game() loads.
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_line())
	if err != OK:
		return {}
	var data = json.get_data()
	if not (data is Dictionary):
		return {}
	return data


func _on_journal_pressed() -> void:
	if _navigating or load_confirm.visible:
		return
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("show_journal"):
		tracker.show_journal()


func _prime_web_mic() -> void:
	if not OS.has_feature("web"):
		return
	var stt = get_node_or_null("/root/STTManager")
	if stt and stt.has_method("prime_web_permission"):
		stt.prime_web_permission()


func _set_player_camera_enabled(enabled: bool) -> void:
	var player = PlayerManager.player
	if player == null:
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.enabled = enabled


func _hide_gameplay_ui() -> void:
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		hud.visible = false
		hud.set_process(false)
		hud.set_physics_process(false)

	PlayerManager.set_process(false)
	PlayerManager.set_physics_process(false)
	if PlayerManager.player:
		PlayerManager.player.visible = false
		PlayerManager.player.set_process(false)
		PlayerManager.player.set_physics_process(false)

	_set_player_camera_enabled(false)


func _restore_game_ui() -> void:
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		hud.visible = true
		hud.set_process(true)
		hud.set_physics_process(true)

	PlayerManager.set_process(true)
	PlayerManager.set_physics_process(true)
	if PlayerManager.player:
		PlayerManager.player.visible = true
		PlayerManager.player.set_process(true)
		PlayerManager.player.set_physics_process(true)

	_set_player_camera_enabled(true)
