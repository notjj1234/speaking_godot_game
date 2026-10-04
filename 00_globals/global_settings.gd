extends Node

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_DEFAULTS := {"volume": 0.7, "muted": false}
const SFX_DEFAULTS := {"volume": 0.7, "muted": false}
const DISPLAY_DEFAULTS := {"fullscreen": false}
const STT_DEFAULTS := {"language": "en"}
const INPUT_DEFAULTS := {"touch_controls": false}

var music_volume: float = MUSIC_DEFAULTS.volume
var music_muted: bool = MUSIC_DEFAULTS.muted
var sfx_volume: float = SFX_DEFAULTS.volume
var sfx_muted: bool = SFX_DEFAULTS.muted
var fullscreen: bool = DISPLAY_DEFAULTS.fullscreen
var stt_language: String = STT_DEFAULTS.language
var touch_controls_forced: bool = INPUT_DEFAULTS.touch_controls

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_migrate_legacy_music_settings()
	_apply_all()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(config.get_value("music", "volume", MUSIC_DEFAULTS.volume)), 0.0, 1.0)
	music_muted = bool(config.get_value("music", "muted", MUSIC_DEFAULTS.muted))
	sfx_volume = clampf(float(config.get_value("sfx", "volume", SFX_DEFAULTS.volume)), 0.0, 1.0)
	sfx_muted = bool(config.get_value("sfx", "muted", SFX_DEFAULTS.muted))
	fullscreen = bool(config.get_value("display", "fullscreen", DISPLAY_DEFAULTS.fullscreen))
	stt_language = str(config.get_value("stt", "language", STT_DEFAULTS.language))
	touch_controls_forced = bool(config.get_value("input", "touch_controls", INPUT_DEFAULTS.touch_controls))

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("music", "volume", music_volume)
	config.set_value("music", "muted", music_muted)
	config.set_value("sfx", "volume", sfx_volume)
	config.set_value("sfx", "muted", sfx_muted)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("stt", "language", stt_language)
	config.set_value("input", "touch_controls", touch_controls_forced)
	config.save(SETTINGS_PATH)

func _migrate_legacy_music_settings() -> void:
	var legacy_path := "user://music_settings.cfg"
	if not FileAccess.file_exists(legacy_path):
		return
	var config := ConfigFile.new()
	if config.load(legacy_path) != OK:
		return
	if config.has_section_key("music", "volume"):
		music_volume = clampf(float(config.get_value("music", "volume", MUSIC_DEFAULTS.volume)), 0.0, 1.0)
	if config.has_section_key("music", "muted"):
		music_muted = bool(config.get_value("music", "muted", MUSIC_DEFAULTS.muted))
	_save_settings()

func _apply_all() -> void:
	_apply_music()
	_apply_sfx()
	_apply_display()
	_apply_stt()
	_apply_input()

func _apply_music() -> void:
	var mm = get_node_or_null("/root/MusicManager")
	if mm:
		mm.set_volume_linear(music_volume)
		mm.set_muted(music_muted)

func _apply_sfx() -> void:
	if sfx_muted or sfx_volume <= 0.001:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), true)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -80.0)
	else:
		AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), false)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))

func _apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_stt() -> void:
	var stt = get_node_or_null("/root/STTManager")
	if stt and stt.has_method("set_language"):
		stt.set_language(stt_language)

func _apply_input() -> void:
	if has_node("/root/TouchControls"):
		var tc = get_node("/root/TouchControls")
		if tc.has_method("set_force_touch_ui"):
			tc.set_force_touch_ui(touch_controls_forced)

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_music()
	_save_settings()
	settings_changed.emit()

func set_music_muted(muted: bool) -> void:
	music_muted = muted
	_apply_music()
	_save_settings()
	settings_changed.emit()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_sfx()
	_save_settings()
	settings_changed.emit()

func set_sfx_muted(muted: bool) -> void:
	sfx_muted = muted
	_apply_sfx()
	_save_settings()
	settings_changed.emit()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()
	_save_settings()
	settings_changed.emit()

func set_stt_language(lang: String) -> void:
	stt_language = lang.strip_edges()
	_apply_stt()
	_save_settings()
	settings_changed.emit()

func set_touch_controls_forced(enabled: bool) -> void:
	touch_controls_forced = enabled
	_apply_input()
	_save_settings()
	settings_changed.emit()

func reset_progress() -> void:
	var save_path := "user://save.sav"
	if FileAccess.file_exists(save_path):
		FileAccess.remove(save_path)
	var persistence_path := "user://settings.cfg"
	if FileAccess.file_exists(persistence_path):
		var config := ConfigFile.new()
		config.load(persistence_path)
		config.erase_section("music")
		config.erase_section("sfx")
		config.erase_section("display")
		config.erase_section("stt")
		config.erase_section("input")
		config.save(persistence_path)
	_load_settings()
	_apply_all()
	settings_changed.emit()