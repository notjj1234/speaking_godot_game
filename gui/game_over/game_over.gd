extends CanvasLayer

const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

var _navigating := false
var _master_was_muted := false
var _input_layer := 0

@onready var title_button: Button = $Control/CenterContainer/VBoxContainer/TitleButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func show_defeat() -> void:
	var bonfire := get_node_or_null("/root/Bonfire")
	if bonfire and bonfire.has_method("show_rest"):
		bonfire.show_rest()
		return
	_open()


func _open() -> void:
	if visible:
		return
	_navigating = false
	_silence_all()
	var pause := get_node_or_null("/root/PauseMenu")
	if pause and pause.is_paused:
		pause.hide_pause_menu()
	visible = true
	get_tree().paused = true
	_input_layer = UiInputRouter.push_layer(&"game_over", self)
	UiInputRouter.bind_button(title_button, _on_title_pressed, _input_layer)
	title_button.grab_focus()


func _close_layer() -> void:
	UiInputRouter.pop_layer(_input_layer)
	_input_layer = 0


func _silence_all() -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	_master_was_muted = AudioServer.is_bus_mute(index)
	AudioServer.set_bus_mute(index, true)


func _restore_audio() -> void:
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	AudioServer.set_bus_mute(index, _master_was_muted)


func _on_title_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	_restore_audio()
	visible = false
	_close_layer()
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TITLE_PATH, "", Vector2.ZERO)
