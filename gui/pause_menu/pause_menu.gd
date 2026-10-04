extends CanvasLayer

signal shown
signal hidden

@onready var audio_stream_player: AudioStreamPlayer = $Control/AudioStreamPlayer

@onready var button_save: Button = $Control/HBoxContainer/Button_Save
@onready var button_load: Button = $Control/HBoxContainer/Button_Load
@onready var color_rect: ColorRect = $Control/ColorRect
@onready var touch_save: TouchScreenButton = $Control/HBoxContainer/Touch_Save
@onready var touch_load: TouchScreenButton = $Control/HBoxContainer/Touch_Load

const INK := Color(0.12, 0.08, 0.04, 1)
const BODY_FONT := preload("res://gui/fonts/Abaddon Light.ttf")

@onready var item_description: Label = $Control/ItemDescription
@onready var word_rows: VBoxContainer = $Control/WordPanel/WordColumn/WordRows
@onready var page_label: Label = $Control/WordPanel/WordColumn/Pager/PageLabel
@onready var prev_page_button: Button = $Control/WordPanel/WordColumn/Pager/PrevPageButton
@onready var next_page_button: Button = $Control/WordPanel/WordColumn/Pager/NextPageButton
@onready var music_slider: HSlider = $Control/MusicPanel/MusicSlider
@onready var music_mute_button: Button = $Control/MusicPanel/MusicButtons/MusicMute
@onready var music_quieter_button: Button = $Control/MusicPanel/MusicButtons/MusicQuieter
@onready var music_louder_button: Button = $Control/MusicPanel/MusicButtons/MusicLouder

var is_paused: bool = false
var current_page: int = 0
var words_per_page: int = 5
var _desktop_touch_preview: bool = false

func _ready() -> void:
	hide_pause_menu()

	# Restore Save & Load functionality
	button_save.pressed.connect(_on_save_pressed)
	button_load.pressed.connect(_on_load_pressed)

	# Connect touchscreen buttons for Save & Load (if they exist)
	if touch_save:
		touch_save.pressed.connect(_on_save_pressed)
	if touch_load:
		touch_load.pressed.connect(_on_load_pressed)

	# Debugging: Log when save/load buttons are pressed
	button_save.pressed.connect(func(): print("[DEBUG] Save button pressed."))
	button_load.pressed.connect(func(): print("[DEBUG] Load button pressed."))

	# Enable touchscreen support directly on the buttons
	prev_page_button.pressed.connect(_prev_page)
	prev_page_button.gui_input.connect(_on_touch_gui_input.bind(prev_page_button))
	prev_page_button.mouse_filter = Control.MOUSE_FILTER_STOP

	next_page_button.pressed.connect(_next_page)
	next_page_button.gui_input.connect(_on_touch_gui_input.bind(next_page_button))
	next_page_button.mouse_filter = Control.MOUSE_FILTER_STOP

	music_slider.value_changed.connect(_on_music_slider_changed)
	# Mouse clicks are also delivered as screen touches, and Button.pressed
	# fires again on release. One touch-down handler keeps Mute from flipping twice.
	music_mute_button.gui_input.connect(_on_music_gui_input.bind(_on_music_mute_pressed))
	music_quieter_button.gui_input.connect(_on_music_gui_input.bind(_on_music_quieter_pressed))
	music_louder_button.gui_input.connect(_on_music_gui_input.bind(_on_music_louder_pressed))
	music_mute_button.custom_minimum_size = Vector2(120, 36)
	music_mute_button.clip_text = true
	_sync_music_controls()

	print("[DEBUG] Prev Page Button & Next Page Button Ready for touch input.")

# Handles touchscreen input manually on buttons
func _on_touch_gui_input(event: InputEvent, button: Button) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if button == prev_page_button:
			print("[DEBUG] PrevPageButton tapped!")
			_prev_page()
		elif button == next_page_button:
			print("[DEBUG] NextPageButton tapped!")
			_next_page()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _is_menu_scene() or _game_over_open():
			return
		# Block pause during speech challenge
		if has_node("/root/WordTracker"):
			var word_tracker = get_node("/root/WordTracker")
			if word_tracker.speech_challenge_active:
				get_viewport().set_input_as_handled()
				return
		if not is_paused:
			show_pause_menu()
		else:
			hide_pause_menu()
		get_viewport().set_input_as_handled()


func _game_over_open() -> bool:
	var game_over := get_node_or_null("/root/GameOver")
	if game_over != null and game_over.visible:
		return true
	var bonfire := get_node_or_null("/root/Bonfire")
	return bonfire != null and bonfire.visible


func _is_menu_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var scene_name := String(scene.name)
	return scene_name == "TitleScreen" or scene_name == "ComingSoon"

func show_pause_menu() -> void:
	get_tree().paused = true
	visible = true
	is_paused = true
	shown.emit()
	current_page = 0
	_sync_music_controls()
	update_word_list_display()
	_add_desktop_touch_preview_button()
	_set_mobile_overlays_suppressed(true)

func hide_pause_menu() -> void:
	get_tree().paused = false
	visible = false
	is_paused = false
	hidden.emit()
	_set_mobile_overlays_suppressed(false)


func _set_mobile_overlays_suppressed(suppressed: bool) -> void:
	for n in get_tree().get_nodes_in_group("touch_controls"):
		if n.has_method("set_suppressed_by_pause"):
			n.set_suppressed_by_pause(suppressed)
	for n in get_tree().get_nodes_in_group("pause_button"):
		if n.has_method("set_suppressed_by_pause"):
			n.set_suppressed_by_pause(suppressed)

func update_word_list_display() -> void:
	if word_rows == null:
		return
	for child in word_rows.get_children():
		child.queue_free()

	var words: Array = []
	var total_words := 0
	if has_node("/root/WordTracker"):
		var word_tracker = get_node("/root/WordTracker")
		words = word_tracker.get_paginated_word_list(current_page, words_per_page)
		total_words = word_tracker.get_word_count()
	else:
		print("❌ WordTracker singleton not found. Word list will stay empty.")

	if words.is_empty():
		word_rows.add_child(_make_empty_label())
	else:
		for word_data in words:
			word_rows.add_child(_make_word_row(str(word_data)))

	var page_count := 1
	if total_words > 0:
		page_count = int(ceil(float(total_words) / float(words_per_page)))
	if page_label:
		page_label.text = "%d / %d" % [current_page + 1, page_count]
	if prev_page_button:
		prev_page_button.disabled = current_page <= 0 or total_words == 0
	if next_page_button:
		next_page_button.disabled = total_words == 0 or (current_page + 1) * words_per_page >= total_words


func _make_empty_label() -> Label:
	var label := Label.new()
	label.text = "No words yet."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK)
	return label


func _make_word_row(word_data: String) -> HBoxContainer:
	var parts := word_data.rsplit(": ", true, 1)
	var phrase := parts[0] if parts.size() > 0 else word_data
	var count := parts[1] if parts.size() > 1 else ""

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var phrase_label := Label.new()
	phrase_label.text = phrase
	phrase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phrase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phrase_label.add_theme_font_override("font", BODY_FONT)
	phrase_label.add_theme_font_size_override("font_size", 14)
	phrase_label.add_theme_color_override("font_color", INK)
	row.add_child(phrase_label)

	var count_label := Label.new()
	count_label.text = "x " + count
	count_label.custom_minimum_size = Vector2(48, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	count_label.add_theme_font_override("font", BODY_FONT)
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", INK)
	row.add_child(count_label)
	return row

func _prev_page() -> void:
	if current_page > 0:
		print("[DEBUG] Moving to previous page.")
		current_page -= 1
		update_word_list_display()
	else:
		print("[DEBUG] Already on first page. Can't go back.")

func _next_page() -> void:
	if has_node("/root/WordTracker"):
		var word_tracker = get_node("/root/WordTracker")
		var total_words = word_tracker.get_word_count()
		if (current_page + 1) * words_per_page < total_words:
			print("[DEBUG] Moving to next page.")
			current_page += 1
			update_word_list_display()
		else:
			print("[DEBUG] Already on last page. Can't go forward.")

func _on_save_pressed() -> void:
	if not is_paused:
		return
	print("[DEBUG] Save game triggered.")
	SaveManager.save_game()
	hide_pause_menu()

func _on_load_pressed() -> void:
	if not is_paused:
		return
	print("[DEBUG] Load game triggered.")
	SaveManager.load_game()
	await LevelManager.level_load_started
	hide_pause_menu()

func update_item_description(new_text: String) -> void:
	item_description.text = new_text

func play_audio(audio: AudioStream) -> void:
	audio_stream_player.stream = audio
	audio_stream_player.play()


func _music() -> Node:
	return get_node_or_null("/root/MusicManager")


func _sync_music_controls() -> void:
	var music := _music()
	if music == null or music_slider == null:
		return
	music_slider.set_value_no_signal(float(music.volume_linear) * 100.0)
	music_mute_button.text = "Unmute" if music.muted else "Mute"


func _on_music_slider_changed(value: float) -> void:
	var music := _music()
	if music == null:
		return
	music.set_volume_linear(value / 100.0)
	if music.muted and value > 0.0:
		music.set_muted(false)
	_sync_music_controls()


func _add_desktop_touch_preview_button() -> void:
	# Temporary. Desktop browsers hide the D-pad. This shows it so placement can be checked.
	var music_panel := get_node_or_null("Control/MusicPanel")
	if music_panel == null or music_panel.get_node_or_null("DesktopTouchPreview") != null:
		return
	if MobileSafeLayout.wants_touch_ui():
		return
	var button := Button.new()
	button.name = "DesktopTouchPreview"
	button.text = "Show touch controls"
	button.custom_minimum_size = Vector2(0, 36)
	button.gui_input.connect(_on_desktop_preview_input.bind(button))
	music_panel.add_child(button)


func _on_desktop_preview_input(event: InputEvent, button: Button) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	get_viewport().set_input_as_handled()
	_desktop_touch_preview = not _desktop_touch_preview
	MobileSafeLayout.set_force_touch_ui(_desktop_touch_preview)
	button.text = "Hide touch controls" if _desktop_touch_preview else "Show touch controls"
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("apply_touch_ui_enabled"):
			node.apply_touch_ui_enabled()
	for node in get_tree().get_nodes_in_group("pause_button"):
		if node.has_method("apply_touch_ui_enabled"):
			node.apply_touch_ui_enabled()
	print("🖥️ Desktop touch preview: ", "on" if _desktop_touch_preview else "off", ". Close the pause menu to see the buttons. Resize the window to switch portrait and landscape.")


func _on_music_gui_input(event: InputEvent, action: Callable) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	get_viewport().set_input_as_handled()
	action.call()


func _on_music_mute_pressed() -> void:
	var music := _music()
	if music == null:
		return
	music.set_muted(not music.muted)
	_sync_music_controls()


func _on_music_quieter_pressed() -> void:
	var music := _music()
	if music == null:
		return
	music.set_volume_linear(float(music.volume_linear) - 0.1)
	_sync_music_controls()


func _on_music_louder_pressed() -> void:
	var music := _music()
	if music == null:
		return
	music.set_volume_linear(float(music.volume_linear) + 0.1)
	if music.muted:
		music.set_muted(false)
	_sync_music_controls()
