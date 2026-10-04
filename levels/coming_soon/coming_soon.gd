# coming_soon.gd

extends CanvasLayer

const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

@onready var back_button: Button = $Control/CenterContainer/VBoxContainer/BackButton
@onready var touch_back: TouchScreenButton = $Control/TouchBack

var _navigating: bool = false


func _ready() -> void:
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	await SceneTransition.fade_in()
	_hide_gameplay_ui()

	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.pressed.connect(_on_back_pressed)
	touch_back.pressed.connect(_on_back_pressed)

	# Invisible twin stays aligned so desktop mouse clicks still fire.
	touch_back.visible = true
	back_button.grab_focus()
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_align_back_touch_button)
	_align_back_touch_button()
	call_deferred("_align_back_touch_button")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_align_back_touch_button()


func _process(_delta: float) -> void:
	_align_back_touch_button()


func _align_back_touch_button() -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	if back_button == null or touch_back == null:
		return
	var rect := back_button.get_global_rect()
	touch_back.global_position = rect.position + rect.size / 2.0
	if touch_back.shape is RectangleShape2D:
		(touch_back.shape as RectangleShape2D).size = rect.size


func _on_back_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	await SceneTransition.fade_out()
	get_tree().change_scene_to_file(TITLE_PATH)


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
