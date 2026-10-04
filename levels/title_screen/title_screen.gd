# title_screen.gd

extends CanvasLayer

const PLAYGROUND_PATH := "res://levels/playground.tscn"
const COMING_SOON_PATH := "res://levels/coming_soon/coming_soon.tscn"
const ENDLESS_HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"

@onready var tutorial_button: Button = $Control/CenterContainer/VBoxContainer/StartTutorial
@onready var game_button: Button = $Control/CenterContainer/VBoxContainer/StartGame
@onready var horde_button: Button = $Control/CenterContainer/VBoxContainer/EndlessHorde
@onready var touch_tutorial_button: TouchScreenButton = $Control/TouchStartTutorial
@onready var touch_game_button: TouchScreenButton = $Control/TouchStartGame
@onready var touch_horde_button: TouchScreenButton = $Control/TouchEndlessHorde

var _navigating: bool = false


func _ready() -> void:
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	await SceneTransition.fade_in()

	tutorial_button.mouse_filter = Control.MOUSE_FILTER_STOP
	game_button.mouse_filter = Control.MOUSE_FILTER_STOP
	horde_button.mouse_filter = Control.MOUSE_FILTER_STOP

	tutorial_button.pressed.connect(_on_tutorial_pressed)
	game_button.pressed.connect(_on_game_pressed)
	horde_button.pressed.connect(_on_horde_pressed)
	touch_tutorial_button.pressed.connect(_on_tutorial_pressed)
	touch_game_button.pressed.connect(_on_game_pressed)
	touch_horde_button.pressed.connect(_on_horde_pressed)

	# Twins stay visible (no texture) so desktop mouse clicks still land:
	# emulate_touch_from_mouse is on and emulate_mouse_from_touch is off.
	touch_tutorial_button.visible = true
	touch_game_button.visible = true
	touch_horde_button.visible = true

	tutorial_button.focus_neighbor_bottom = tutorial_button.get_path_to(game_button)
	tutorial_button.focus_next = tutorial_button.get_path_to(game_button)
	tutorial_button.focus_neighbor_top = tutorial_button.get_path_to(horde_button)
	tutorial_button.focus_previous = tutorial_button.get_path_to(horde_button)
	game_button.focus_neighbor_top = game_button.get_path_to(tutorial_button)
	game_button.focus_previous = game_button.get_path_to(tutorial_button)
	game_button.focus_neighbor_bottom = game_button.get_path_to(horde_button)
	game_button.focus_next = game_button.get_path_to(horde_button)
	horde_button.focus_neighbor_top = horde_button.get_path_to(game_button)
	horde_button.focus_previous = horde_button.get_path_to(game_button)
	horde_button.focus_neighbor_bottom = horde_button.get_path_to(tutorial_button)
	horde_button.focus_next = horde_button.get_path_to(tutorial_button)
	tutorial_button.grab_focus()

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


func _align_menu_touch_buttons() -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	_align_touch_button(tutorial_button, touch_tutorial_button)
	_align_touch_button(game_button, touch_game_button)
	_align_touch_button(horde_button, touch_horde_button)


func _align_touch_button(button: Control, touch: TouchScreenButton) -> void:
	if button == null or touch == null:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _on_tutorial_pressed() -> void:
	if _navigating:
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


func _on_horde_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	print("Starting Endless Horde...")
	_prime_web_mic()
	_restore_game_ui()
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(ENDLESS_HORDE_PATH, "", Vector2.ZERO)


func _on_game_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	print("Starting Main Game...")
	_prime_web_mic()
	# Keep HUD/player hidden — Coming Soon is still a menu
	await SceneTransition.fade_out()
	get_tree().change_scene_to_file(COMING_SOON_PATH)


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
