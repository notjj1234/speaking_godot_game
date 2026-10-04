extends CanvasLayer

const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

var _navigating := false
var _master_was_muted := false

@onready var title_button: Button = $Control/CenterContainer/VBoxContainer/TitleButton
@onready var touch_title: TouchScreenButton = $Control/TouchTitle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	title_button.mouse_filter = Control.MOUSE_FILTER_STOP
	title_button.pressed.connect(_on_title_pressed)
	touch_title.pressed.connect(_on_title_pressed)
	touch_title.visible = true


func show_defeat() -> void:
	var bonfire := get_node_or_null("/root/Bonfire")
	if bonfire and bonfire.has_method("show_rest"):
		bonfire.show_rest()
		return
	if visible:
		return
	_navigating = false
	_silence_all()
	var pause := get_node_or_null("/root/PauseMenu")
	if pause and pause.visible:
		pause.visible = false
		pause.is_paused = false
	visible = true
	get_tree().paused = true
	set_process(true)
	title_button.grab_focus()
	_align_title_button()


func _process(_delta: float) -> void:
	_align_title_button()


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


func _align_title_button() -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	if title_button == null or touch_title == null:
		return
	var rect := title_button.get_global_rect()
	touch_title.global_position = rect.position + rect.size / 2.0
	if touch_title.shape is RectangleShape2D:
		(touch_title.shape as RectangleShape2D).size = rect.size


func _on_title_pressed() -> void:
	if _navigating:
		return
	_navigating = true
	_restore_audio()
	visible = false
	set_process(false)
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TITLE_PATH, "", Vector2.ZERO)
