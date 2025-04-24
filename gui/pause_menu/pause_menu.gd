extends CanvasLayer

signal shown
signal hidden

@onready var audio_stream_player: AudioStreamPlayer = $Control/AudioStreamPlayer

@onready var button_save: Button = $Control/HBoxContainer/Button_Save
@onready var button_load: Button = $Control/HBoxContainer/Button_Load
@onready var color_rect: ColorRect = $Control/ColorRect
@onready var touch_save: TouchScreenButton = $Control/HBoxContainer/Touch_Save
@onready var touch_load: TouchScreenButton = $Control/HBoxContainer/Touch_Load

@onready var item_description: Label = $Control/ItemDescription
@onready var word_list_display: RichTextLabel = $Control/VBoxContainer/WordListDisplay
@onready var prev_page_button: Button = $Control/VBoxContainer/HBoxContainer/PrevPageButton
@onready var next_page_button: Button = $Control/VBoxContainer/HBoxContainer/NextPageButton

var is_paused: bool = false
var current_page: int = 0
var words_per_page: int = 2

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
		if not is_paused:
			show_pause_menu()
		else:
			hide_pause_menu()
		get_viewport().set_input_as_handled()

func show_pause_menu() -> void:
	get_tree().paused = true
	visible = true
	is_paused = true
	shown.emit()
	current_page = 0  # Reset to first page when opened
	update_word_list_display()

func hide_pause_menu() -> void:
	get_tree().paused = false
	visible = false
	is_paused = false
	hidden.emit()

func update_word_list_display() -> void:
	print("update_word_list_display() triggered")
	
	if has_node("/root/WordTracker"):
		var word_tracker = get_node("/root/WordTracker")
		var words = word_tracker.get_paginated_word_list(current_page, words_per_page)

		if has_node("Control/VBoxContainer/WordListDisplay"):
			word_list_display = get_node("Control/VBoxContainer/WordListDisplay")
			print("Found WordListDisplay node!")  # Debug log

			word_list_display.clear()
			if words.size() > 0:
				for word_data in words:
					word_list_display.append_text(word_data + "\n")
			else:
				word_list_display.append_text("No words recorded.")

		else:
			print("Error: WordListDisplay node not found in scene!")
	else:
		print("Error: WordTracker singleton not found! Word list will not be updated.")

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
