extends CanvasLayer

class_name SettingsNode

signal closed

var _is_open: bool = false
var _navigating: bool = false
var _language_index: int = 0
var _confirming_reset: bool = false
var _input_layer: int = 0

@onready var panel: PanelContainer = %Panel
@onready var vbox: VBoxContainer = %VBoxContainer
@onready var music_slider: HSlider = %MusicSlider
@onready var music_mute_button: Button = %MusicMuteButton
@onready var sfx_slider: HSlider = %SFXSlider
@onready var sfx_mute_button: Button = %SFXMuteButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var language_button: Button = %LanguageButton
@onready var touch_button: Button = %TouchButton
@onready var difficulty_button: Button = %DifficultyButton
@onready var reset_button: Button = %ResetButton
@onready var close_button: Button = %CloseButton

const LANGUAGES := ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	
	_sync_controls()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


## Pointer presses and keyboard `pressed` for every button on this layer.
func _route_pointer() -> void:
	UiInputRouter.bind_button(music_mute_button, _on_music_mute_pressed, _input_layer)
	UiInputRouter.bind_button(sfx_mute_button, _on_sfx_mute_pressed, _input_layer)
	UiInputRouter.bind_button(fullscreen_button, _on_fullscreen_pressed, _input_layer)
	UiInputRouter.bind_button(language_button, _on_language_pressed, _input_layer)
	UiInputRouter.bind_button(touch_button, _on_touch_pressed, _input_layer)
	UiInputRouter.bind_button(difficulty_button, _on_difficulty_pressed, _input_layer)
	UiInputRouter.bind_button(reset_button, _on_reset_pressed, _input_layer)
	UiInputRouter.bind_button(close_button, _on_close_pressed, _input_layer)


func show_settings() -> void:
	if _is_open or _navigating:
		return
	_is_open = true
	visible = true
	_input_layer = UiInputRouter.push_layer(&"settings", self)
	_route_pointer()
	_sync_controls()
	close_button.grab_focus()


func hide_settings() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	UiInputRouter.pop_layer(_input_layer)
	_input_layer = 0
	closed.emit()


func _sync_controls() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if not settings:
		return
	music_slider.set_value_no_signal(settings.music_volume * 100.0)
	music_mute_button.text = "Unmute" if settings.music_muted else "Mute"
	sfx_slider.set_value_no_signal(settings.sfx_volume * 100.0)
	sfx_mute_button.text = "Unmute" if settings.sfx_muted else "Mute"
	fullscreen_button.text = "On" if settings.fullscreen else "Off"
	
	_language_index = LANGUAGES.find(settings.stt_language)
	if _language_index == -1:
		_language_index = 0
	language_button.text = _language_name(LANGUAGES[_language_index])
	
	touch_button.text = _touch_text(settings.touch_controls_forced)
	
	var diff_names := ["Easy", "Normal", "Hard"]
	difficulty_button.text = diff_names[settings.speech_difficulty]
	
	reset_button.text = "Reset"
	_confirming_reset = false


func _language_name(code: String) -> String:
	match code:
		"en": return "English"
		"es": return "Spanish"
		"fr": return "French"
		"de": return "German"
		"it": return "Italian"
		"pt": return "Portuguese"
		"ja": return "Japanese"
		"ko": return "Korean"
		"zh": return "Chinese"
	return code.to_upper()


func _touch_text(enabled: bool) -> String:
	return "On" if enabled else "Auto"


func _on_music_slider_changed(value: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_volume(value / 100.0)


func _on_sfx_slider_changed(value: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_sfx_volume(value / 100.0)


func _on_music_mute_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_muted(not settings.music_muted)


func _on_sfx_mute_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_sfx_muted(not settings.sfx_muted)


func _on_fullscreen_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_fullscreen(not settings.fullscreen)


func _on_language_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if not settings:
		return
	_language_index = (_language_index + 1) % LANGUAGES.size()
	var new_lang: String = str(LANGUAGES[_language_index])
	settings.set_stt_language(new_lang)
	language_button.text = _language_name(new_lang)


func _on_touch_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_touch_controls_forced(not settings.touch_controls_forced)
		touch_button.text = _touch_text(settings.touch_controls_forced)


func _on_difficulty_pressed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if not settings:
		return
	var new_diff := (int(settings.speech_difficulty) + 1) % 3
	settings.set_speech_difficulty(SettingsManager.SpeechDifficulty.values()[new_diff])
	var diff_names := ["Easy", "Normal", "Hard"]
	difficulty_button.text = diff_names[new_diff]


func _on_reset_pressed() -> void:
	if _confirming_reset:
		var settings = get_node_or_null("/root/SettingsManager")
		if settings:
			settings.reset_progress()
		_confirming_reset = false
		reset_button.text = "Reset"
	else:
		_confirming_reset = true
		reset_button.text = "Confirm?"


func _on_close_pressed() -> void:
	if _confirming_reset:
		_confirming_reset = false
		reset_button.text = "Reset"
		return
	hide_settings()
