extends CanvasLayer

signal shown
signal hidden

@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

# The pause menu is built from containers so it stays centered and scales with
# the viewport at any browser aspect ratio. Nodes are addressed by unique name
# so the layout can change without touching this script.
@onready var button_save: Button = %Button_Save
@onready var button_load: Button = %Button_Load
@onready var button_main_menu: Button = %Button_MainMenu
@onready var color_rect: ColorRect = $Control/ColorRect
@onready var journal_button: Button = %JournalButton
@onready var close_icon: TouchScreenButton = $Control/CloseIcon
@onready var item_grid: GridContainer = $Control/MenuRoot/Center/MenuCard/Card/Columns/LeftColumn/PanelContainer/GridContainer
@onready var button_settings: Button = %Button_Settings

const INK := Color(0.12, 0.08, 0.04, 1)
const BODY_FONT := preload("res://gui/fonts/Abaddon Light.ttf")
const TITLE_SCENE := "res://levels/title_screen/title_screen.tscn"
const SETTINGS_SCENE := "res://gui/settings/settings.tscn"

var _leaving_to_title: bool = false
var _settings_node: SettingsNode = null
## UiInputRouter layer while the menu is open, 0 while closed.
var input_layer: int = 0
var load_confirm: Control = null
var load_confirm_button: Button = null
var load_cancel_button: Button = null
var _load_confirm_layer: int = 0

@onready var item_description: Label = %ItemDescription
@onready var saved_note: Label = %SavedNote
@onready var word_rows: VBoxContainer = %WordRows
@onready var page_label: Label = %PageLabel
@onready var prev_page_button: Button = %PrevPageButton
@onready var next_page_button: Button = %NextPageButton
@onready var music_slider: HSlider = %MusicSlider
@onready var music_mute_button: Button = %MusicMute
@onready var music_quieter_button: Button = %MusicQuieter
@onready var music_louder_button: Button = %MusicLouder

var is_paused: bool = false
## Bumped by anything that should cancel the delayed close after Save
## (opening Journal/Settings/Load, or closing/reopening the menu).
var _save_close_token: int = 0
var current_page: int = 0
var words_per_page: int = 5

func _ready() -> void:
	hide_pause_menu()

	# Restore Save & Load functionality
	button_save.pressed.connect(_on_save_pressed)
	button_load.pressed.connect(_on_load_pressed)
	button_main_menu.pressed.connect(_on_main_menu_pressed)
	if button_settings:
		button_settings.pressed.connect(_on_settings_pressed)

	# Debugging: Log when save/load buttons are pressed
	button_save.pressed.connect(func(): print("[DEBUG] Save button pressed."))
	button_load.pressed.connect(func(): print("[DEBUG] Load button pressed."))

	music_slider.value_changed.connect(_on_music_slider_changed)
	music_mute_button.custom_minimum_size = Vector2(120, 44)
	music_mute_button.clip_text = true
	_sync_music_controls()


## Pointer presses (and keyboard `pressed`) for everything on this layer.
func _route_pointer() -> void:
	UiInputRouter.bind_button(journal_button, _on_journal_pressed, input_layer)
	UiInputRouter.bind_button(prev_page_button, _prev_page, input_layer)
	UiInputRouter.bind_button(next_page_button, _next_page, input_layer)
	UiInputRouter.bind_button(music_quieter_button, _on_music_quieter_pressed, input_layer)
	UiInputRouter.bind_button(music_mute_button, _on_music_mute_pressed, input_layer)
	UiInputRouter.bind_button(music_louder_button, _on_music_louder_pressed, input_layer)
	UiInputRouter.bind(close_icon, hide_pause_menu, input_layer)
	# Save, Load, Main Menu and Settings are already connected to `pressed`.
	UiInputRouter.bind(button_save, _on_save_pressed, input_layer)
	UiInputRouter.bind(button_load, _on_load_pressed, input_layer)
	UiInputRouter.bind(button_main_menu, _on_main_menu_pressed, input_layer)
	UiInputRouter.bind(button_settings, _on_settings_pressed, input_layer)
	for slot in item_grid.get_children():
		if slot is InventorySlotUI and not slot.is_queued_for_deletion():
			slot.route(input_layer)


func _unhandled_input(event: InputEvent) -> void:
	if load_confirm != null and load_confirm.visible \
			and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		_on_load_cancelled()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if _is_menu_scene() or _game_over_open():
			return
		# Mid-load the level manager unpauses when the fade ends, which would
		# leave this menu up over a running game; a dialog bar would cover it.
		if LevelManager.is_loading or DialogSystem.is_open:
			get_viewport().set_input_as_handled()
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
	return game_over != null and game_over.visible


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
	if input_layer == 0:
		input_layer = UiInputRouter.push_layer(&"pause", self)
	shown.emit()
	_route_pointer()
	current_page = 0
	_sync_music_controls()
	update_word_list_display()

## unpause=false is for closing the menu while a level load owns the pause:
## LevelManager unpauses once the new level has faded in.
func hide_pause_menu(unpause: bool = true) -> void:
	_save_close_token += 1
	_close_load_confirm()
	if _settings_node:
		_settings_node.hide_settings()
	UiInputRouter.pop_layer(input_layer)
	input_layer = 0
	if unpause:
		get_tree().paused = false
	visible = false
	is_paused = false
	if saved_note:
		saved_note.visible = false
	hidden.emit()


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

func _on_journal_pressed() -> void:
	if not is_paused:
		return
	_save_close_token += 1
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("show_journal"):
		tracker.show_journal()


func _on_save_pressed() -> void:
	if not is_paused:
		return
	print("[DEBUG] Save game triggered.")
	SaveManager.save_game()
	if saved_note:
		saved_note.visible = true
	_save_close_token += 1
	var token := _save_close_token
	await get_tree().create_timer(0.8, true).timeout
	if is_paused and token == _save_close_token:
		hide_pause_menu()

func _on_load_pressed() -> void:
	if not is_paused:
		return
	if not SaveManager.has_save():
		print("[DEBUG] Load pressed but no save exists.")
		return
	_save_close_token += 1
	# Confirm first: unlike the title screen (which asks before loading), a
	# mis-tap here would silently discard the current run.
	_open_load_confirm()


func _open_load_confirm() -> void:
	if load_confirm == null:
		_build_load_confirm()
	if load_confirm.visible:
		return
	load_confirm.visible = true
	_load_confirm_layer = UiInputRouter.push_layer(&"pause_load_confirm", self)
	UiInputRouter.bind_button(load_confirm_button, _on_load_confirmed, _load_confirm_layer)
	UiInputRouter.bind_button(load_cancel_button, _on_load_cancelled, _load_confirm_layer)
	load_cancel_button.grab_focus()


func _close_load_confirm() -> void:
	if load_confirm == null or not load_confirm.visible:
		return
	load_confirm.visible = false
	UiInputRouter.pop_layer(_load_confirm_layer)
	_load_confirm_layer = 0


func _on_load_confirmed() -> void:
	_close_load_confirm()
	_do_load_game()


func _on_load_cancelled() -> void:
	_close_load_confirm()
	button_load.grab_focus()


func _build_load_confirm() -> void:
	load_confirm = Control.new()
	load_confirm.name = "LoadConfirm"
	load_confirm.visible = false
	load_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(load_confirm)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	load_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_confirm.add_child(center)

	var panel := PanelContainer.new()
	var card: PanelContainer = $Control/MenuRoot/Center/MenuCard
	var card_style := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if card_style:
		card_style.bg_color.a = 1.0
		panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	for text in ["Load saved game?", "Progress since your last save will be lost."]:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", BODY_FONT)
		label.add_theme_font_size_override("font_size", 16)
		column.add_child(label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	load_confirm_button = _make_confirm_button("Load")
	load_cancel_button = _make_confirm_button("Cancel")
	row.add_child(load_confirm_button)
	row.add_child(load_cancel_button)
	var load_path := load_confirm_button.get_path_to(load_cancel_button)
	var cancel_path := load_cancel_button.get_path_to(load_confirm_button)
	for property in ["focus_neighbor_left", "focus_neighbor_right", "focus_neighbor_top",
			"focus_neighbor_bottom", "focus_next", "focus_previous"]:
		load_confirm_button.set(property, load_path)
		load_cancel_button.set(property, cancel_path)


func _make_confirm_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 44)
	button.add_theme_font_override("font", BODY_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	for style in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style, button_save.get_theme_stylebox(style))
	return button


func _do_load_game() -> void:
	print("[DEBUG] Load game triggered.")
	SaveManager.load_game()
	await LevelManager.level_load_started
	hide_pause_menu(false)


func _on_settings_pressed() -> void:
	if not is_paused:
		return
	_save_close_token += 1
	var settings := _ensure_settings()
	if settings:
		settings.show_settings()


func _ensure_settings() -> SettingsNode:
	if _settings_node == null:
		var packed := load(SETTINGS_SCENE) as PackedScene
		if packed == null:
			print("❌ PauseMenu: settings scene missing at ", SETTINGS_SCENE)
			return null
		_settings_node = packed.instantiate() as SettingsNode
		if _settings_node == null:
			print("❌ PauseMenu: settings scene root is not a SettingsNode")
			return null
		add_child(_settings_node)
	return _settings_node


func _on_main_menu_pressed() -> void:
	if not is_paused or _leaving_to_title:
		return
	_leaving_to_title = true
	print("🏠 Returning to main menu.")
	# Drop transient UI state so the next visit starts clean.
	current_page = 0
	item_description.text = ""
	# Music is stopped before the fade so the menu does not fade in over level music.
	var music := get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	PlayerManager.player_spawned = false
	hide_pause_menu()
	# A dialog left open would keep its input layer over the title menu.
	if DialogSystem.is_open:
		DialogSystem.close()
	await LevelManager.load_new_level(TITLE_SCENE, "", Vector2.ZERO)
	_leaving_to_title = false

func update_item_description(new_text: String) -> void:
	item_description.text = new_text

func play_audio(audio: AudioStream) -> void:
	audio_stream_player.stream = audio
	audio_stream_player.play()


func _settings() -> Node:
	return get_node_or_null("/root/SettingsManager")


func _sync_music_controls() -> void:
	var settings := _settings()
	if settings == null or music_slider == null:
		return
	music_slider.set_value_no_signal(float(settings.music_volume) * 100.0)
	music_mute_button.text = "Unmute" if settings.music_muted else "Mute"


func _on_music_slider_changed(value: float) -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_music_volume(value / 100.0)
	if settings.music_muted and value > 0.0:
		settings.set_music_muted(false)
	_sync_music_controls()


func _on_music_mute_pressed() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_music_muted(not settings.music_muted)
	_sync_music_controls()


func _on_music_quieter_pressed() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_music_volume(float(settings.music_volume) - 0.1)
	_sync_music_controls()


func _on_music_louder_pressed() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set_music_volume(float(settings.music_volume) + 0.1)
	if settings.music_muted:
		settings.set_music_muted(false)
	_sync_music_controls()
