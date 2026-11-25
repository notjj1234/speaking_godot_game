# title_screen.gd

extends CanvasLayer

const PLAYGROUND_PATH := "res://levels/playground.tscn"
const ENDLESS_HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const SAVE_FILE_PATH := "user://save.sav"

@onready var tutorial_button: Button = $Control/CenterContainer/VBoxContainer/StartTutorial
@onready var game_button: Button = $Control/CenterContainer/VBoxContainer/StartGame
@onready var load_button: Button = $Control/CenterContainer/VBoxContainer/Load
@onready var journal_button: Button = $Control/CenterContainer/VBoxContainer/Journal
@onready var settings_button: Button = $Control/CenterContainer/VBoxContainer/Settings
@onready var exit_button: Button = $Control/CenterContainer/VBoxContainer/ExitGame
@onready var _settings_node: SettingsNode = null
@onready var load_confirm: Control = %LoadConfirm
@onready var exit_confirm: Control = %ExitConfirm
@onready var location_label: Label = %LocationLabel
@onready var hp_label: Label = %HpLabel
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton
@onready var exit_yes_button: Button = %ExitYesButton
@onready var exit_no_button: Button = %ExitNoButton

var _navigating: bool = false
var _journal_was_open: bool = false
var _show_exit: bool = false
## UiInputRouter layer of whichever confirm card is open, else 0.
var _confirm_layer: int = 0


func _ready() -> void:
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	await SceneTransition.fade_in()

	# Web has no app process to quit; hide Exit on browser builds.
	_show_exit = not OS.has_feature("web")
	if exit_button:
		exit_button.visible = _show_exit
	if exit_confirm:
		exit_confirm.visible = false

	# Base-layer buttons. UiInputRouter dispatches the pointer; `pressed` is keyboard.
	UiInputRouter.bind_button(tutorial_button, _on_tutorial_pressed)
	UiInputRouter.bind_button(game_button, _on_game_pressed)
	UiInputRouter.bind_button(load_button, _on_load_pressed)
	UiInputRouter.bind_button(journal_button, _on_journal_pressed)
	if settings_button:
		UiInputRouter.bind_button(settings_button, _on_settings_pressed)
	if _show_exit and exit_button:
		UiInputRouter.bind_button(exit_button, _on_exit_pressed)

	if exit_yes_button and exit_no_button:
		exit_yes_button.focus_neighbor_right = exit_yes_button.get_path_to(exit_no_button)
		exit_yes_button.focus_next = exit_yes_button.get_path_to(exit_no_button)
		exit_yes_button.focus_neighbor_left = exit_yes_button.get_path_to(exit_no_button)
		exit_yes_button.focus_previous = exit_yes_button.get_path_to(exit_no_button)
		exit_no_button.focus_neighbor_left = exit_no_button.get_path_to(exit_yes_button)
		exit_no_button.focus_previous = exit_no_button.get_path_to(exit_yes_button)
		exit_no_button.focus_neighbor_right = exit_no_button.get_path_to(exit_yes_button)
		exit_no_button.focus_next = exit_no_button.get_path_to(exit_yes_button)

	yes_button.focus_neighbor_right = yes_button.get_path_to(no_button)
	yes_button.focus_next = yes_button.get_path_to(no_button)
	yes_button.focus_neighbor_left = yes_button.get_path_to(no_button)
	yes_button.focus_previous = yes_button.get_path_to(no_button)
	no_button.focus_neighbor_left = no_button.get_path_to(yes_button)
	no_button.focus_previous = no_button.get_path_to(yes_button)
	no_button.focus_neighbor_right = no_button.get_path_to(yes_button)
	no_button.focus_next = no_button.get_path_to(yes_button)

	# Disabled state must be known before building the arrow-key focus ring.
	load_button.disabled = not SaveManager.has_save()
	_setup_menu_focus_neighbors()
	tutorial_button.grab_focus()

	load_confirm.visible = false

	_hide_gameplay_ui()


func _setup_menu_focus_neighbors() -> void:
	# Explicit vertical ring so Settings (and Exit when native) are never skipped.
	# Older code wired Journal → Tutorial and left Settings unreachable by arrows.
	var chain: Array[Control] = []
	for btn in [tutorial_button, game_button, load_button, journal_button, settings_button]:
		if btn == null:
			continue
		# Disabled buttons cannot take focus — link around them.
		if btn is BaseButton and (btn as BaseButton).disabled:
			btn.focus_mode = Control.FOCUS_NONE
			continue
		chain.append(btn)
	if _show_exit and exit_button != null and exit_button.visible:
		chain.append(exit_button)
	elif exit_button != null:
		exit_button.focus_mode = Control.FOCUS_NONE
		exit_button.focus_neighbor_top = NodePath()
		exit_button.focus_neighbor_bottom = NodePath()
		exit_button.focus_next = NodePath()
		exit_button.focus_previous = NodePath()

	var n := chain.size()
	if n == 0:
		return
	var names: PackedStringArray = []
	for i in n:
		var cur := chain[i]
		var prev := chain[(i - 1 + n) % n]
		var next := chain[(i + 1) % n]
		cur.focus_mode = Control.FOCUS_ALL
		cur.focus_neighbor_top = cur.get_path_to(prev)
		cur.focus_previous = cur.get_path_to(prev)
		cur.focus_neighbor_bottom = cur.get_path_to(next)
		cur.focus_next = cur.get_path_to(next)
		# Pin left/right to self so spatial search does not jump off the column.
		cur.focus_neighbor_left = cur.get_path_to(cur)
		cur.focus_neighbor_right = cur.get_path_to(cur)
		names.append(String(cur.name))
	print("✅ TitleScreen focus chain: ", ", ".join(names))


func _process(_delta: float) -> void:
	_sync_journal_overlay()


## Escape closes the open confirm card. The journal handles its own Escape.
func _unhandled_input(event: InputEvent) -> void:
	if _is_journal_open():
		return
	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause"):
		return
	if exit_confirm != null and exit_confirm.visible:
		_on_exit_no_pressed()
		get_viewport().set_input_as_handled()
		return
	if load_confirm.visible:
		_on_load_no_pressed()
		get_viewport().set_input_as_handled()


func _any_confirm_open() -> bool:
	return (load_confirm != null and load_confirm.visible) \
			or (exit_confirm != null and exit_confirm.visible)


func _is_journal_open() -> bool:
	var tracker := get_node_or_null("/root/ProgressTracker")
	return tracker != null and tracker.has_method("is_journal_open") and bool(tracker.is_journal_open())


func _sync_journal_overlay() -> void:
	var journal_open := _is_journal_open()
	if _journal_was_open and not journal_open:
		if not _navigating and not _any_confirm_open() and tutorial_button:
			tutorial_button.grab_focus()
	_journal_was_open = journal_open


func _on_tutorial_pressed() -> void:
	if _navigating or _any_confirm_open() or _is_journal_open():
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
	if _navigating or _any_confirm_open() or _is_journal_open():
		return
	_navigating = true
	print("✅ Starting Endless Horde...")
	_prime_web_mic()
	_restore_game_ui()
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(ENDLESS_HORDE_PATH, "", Vector2.ZERO)


func _on_load_pressed() -> void:
	if load_button.disabled or _navigating or _any_confirm_open() or _is_journal_open():
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
	_hide_confirm(load_confirm)
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
	_show_confirm(load_confirm, &"title_load_confirm", yes_button, _on_load_yes_pressed,
			no_button, _on_load_no_pressed)
	yes_button.grab_focus()


func _close_load_confirm() -> void:
	_hide_confirm(load_confirm)
	load_button.grab_focus()
	print("✅ Load confirm closed")


## A confirm card is a modal layer: the menu under it stops receiving presses.
func _show_confirm(card: Control, layer_name: StringName, yes: Button, on_yes: Callable,
		no: Button, on_no: Callable) -> void:
	card.visible = true
	_confirm_layer = UiInputRouter.push_layer(layer_name, self)
	UiInputRouter.bind_button(yes, on_yes, _confirm_layer)
	UiInputRouter.bind_button(no, on_no, _confirm_layer)


func _hide_confirm(card: Control) -> void:
	card.visible = false
	UiInputRouter.pop_layer(_confirm_layer)
	_confirm_layer = 0


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
	if _navigating or _any_confirm_open() or _is_journal_open():
		return
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker == null or not tracker.has_method("show_journal"):
		return
	tracker.show_journal()
	_journal_was_open = _is_journal_open()


func _on_settings_pressed() -> void:
	if _navigating or _any_confirm_open() or _is_journal_open():
		return
	if _settings_node == null:
		var packed := load("res://gui/settings/settings.tscn") as PackedScene
		if packed == null:
			print("❌ TitleScreen: settings scene missing")
			return
		_settings_node = packed.instantiate() as SettingsNode
		if _settings_node == null:
			print("❌ TitleScreen: settings scene root is not a SettingsNode")
			return
		add_child(_settings_node)
	_settings_node.show_settings()


func _on_exit_pressed() -> void:
	if not _show_exit or _navigating or _any_confirm_open() or _is_journal_open():
		return
	_show_exit_confirm()


func _show_exit_confirm() -> void:
	if exit_confirm == null:
		return
	_show_confirm(exit_confirm, &"title_exit_confirm", exit_yes_button, _on_exit_yes_pressed,
			exit_no_button, _on_exit_no_pressed)
	exit_yes_button.grab_focus()
	print("✅ Exit confirm opened")


func _on_exit_yes_pressed() -> void:
	if not _show_exit or _navigating:
		return
	if exit_confirm == null or not exit_confirm.visible:
		return
	print("✅ Exiting game...")
	get_tree().quit()


func _on_exit_no_pressed() -> void:
	if _navigating or exit_confirm == null or not exit_confirm.visible:
		return
	_close_exit_confirm()


func _close_exit_confirm() -> void:
	_hide_confirm(exit_confirm)
	if exit_button and _show_exit:
		exit_button.grab_focus()
	elif tutorial_button:
		tutorial_button.grab_focus()
	print("✅ Exit confirm closed")


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
