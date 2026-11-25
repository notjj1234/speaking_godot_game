# coming_soon.gd

extends CanvasLayer

const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

@onready var back_button: Button = $Control/CenterContainer/VBoxContainer/BackButton

var _navigating: bool = false


func _ready() -> void:
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	await SceneTransition.fade_in()
	_hide_gameplay_ui()

	UiInputRouter.bind_button(back_button, _on_back_pressed)
	back_button.grab_focus()


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
