extends CanvasLayer

const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"
const CAMP_PATH := "res://levels/endless_horde/camp/camp.tscn"

var _navigating := false
var _camp_requested := false
var _master_was_muted := false
var _input_layer := 0

@onready var title_button: Button = $Control/CenterContainer/VBoxContainer/TitleButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## An Endless Horde death: rest at the camp. Falls back to this screen only if
## the camp scene is missing from the build.
func show_defeat() -> void:
	if LevelManager.is_loading or _camp_requested:
		return
	if not ResourceLoader.exists(CAMP_PATH):
		print("❌ GameOver: camp scene missing, showing game over")
		_open()
		return
	_camp_requested = true
	PlayerManager.player_spawned = false
	LevelManager.level_loaded.connect(_on_camp_loaded, CONNECT_ONE_SHOT)
	LevelManager.load_new_level(CAMP_PATH, "", Vector2.ZERO)


func _on_camp_loaded() -> void:
	_camp_requested = false


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
