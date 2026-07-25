# title_screen.gd

extends CanvasLayer

const PLAYGROUND_PATH := "res://levels/playground.tscn"
const COMING_SOON_PATH := "res://levels/coming_soon/coming_soon.tscn"

@onready var tutorial_button: Button = $Control/CenterContainer/VBoxContainer/StartTutorial
@onready var game_button: Button = $Control/CenterContainer/VBoxContainer/StartGame
@onready var touch_tutorial_button: TouchScreenButton = $Control/TouchStartTutorial
@onready var touch_game_button: TouchScreenButton = $Control/TouchStartGame

var _navigating: bool = false


func _ready() -> void:
	await SceneTransition.fade_in()

	tutorial_button.mouse_filter = Control.MOUSE_FILTER_STOP
	game_button.mouse_filter = Control.MOUSE_FILTER_STOP

	tutorial_button.pressed.connect(_on_tutorial_pressed)
	game_button.pressed.connect(_on_game_pressed)
	touch_tutorial_button.pressed.connect(_on_tutorial_pressed)
	touch_game_button.pressed.connect(_on_game_pressed)

	_hide_gameplay_ui()


func _process(_delta: float) -> void:
	_align_touch_button(tutorial_button, touch_tutorial_button)
	_align_touch_button(game_button, touch_game_button)


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
	_restore_game_ui()
	# Fire-and-forget: LevelManager (autoload) owns the coroutine across the scene swap
	LevelManager.load_new_level(PLAYGROUND_PATH, "PlaygroundTo01", Vector2.ZERO)


func _on_game_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	print("Starting Main Game...")
	# Keep HUD/player hidden — Coming Soon is still a menu
	await SceneTransition.fade_out()
	get_tree().change_scene_to_file(COMING_SOON_PATH)


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
