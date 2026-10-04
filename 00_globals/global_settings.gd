# global_settings.gd
# Global settings singleton for game configuration

class_name SettingsManager extends Node

enum SpeechDifficulty {
	DIFFICULTY_EASY = 0,
	DIFFICULTY_NORMAL = 1,
	DIFFICULTY_HARD = 2
}

signal settings_changed

var music_volume: float = 0.8
var music_muted: bool = false
var sfx_volume: float = 0.8
var sfx_muted: bool = false
var fullscreen: bool = true
var stt_language: String = "en"
var touch_controls_forced: bool = false
var speech_difficulty: SpeechDifficulty = SpeechDifficulty.DIFFICULTY_NORMAL
var ui_scale: float = 1.0
var reduce_motion: bool = false
var color_blind_mode: bool = false

const SETTINGS_PATH = "user://settings.cfg"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()


func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] No settings file found, using defaults")
		return
	
	music_volume = config.get_value("audio", "music_volume", 0.8)
	music_muted = config.get_value("audio", "music_muted", false)
	sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
	sfx_muted = config.get_value("audio", "sfx_muted", false)
	fullscreen = config.get_value("video", "fullscreen", true)
	stt_language = config.get_value("speech", "stt_language", "en")
	touch_controls_forced = config.get_value("input", "touch_controls_forced", false)
	speech_difficulty = SpeechDifficulty(config.get_value("speech", "speech_difficulty", 1))
	ui_scale = config.get_value("accessibility", "ui_scale", 1.0)
	reduce_motion = config.get_value("accessibility", "reduce_motion", false)
	color_blind_mode = config.get_value("accessibility", "color_blind_mode", false)


func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "music_muted", music_muted)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("speech", "stt_language", stt_language)
	config.set_value("input", "touch_controls_forced", touch_controls_forced)
	config.set_value("speech", "speech_difficulty", int(speech_difficulty))
	config.set_value("accessibility", "ui_scale", ui_scale)
	config.set_value("accessibility", "reduce_motion", reduce_motion)
	config.set_value("accessibility", "color_blind_mode", color_blind_mode)
	
	var err = config.save(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] Failed to save settings: ", err)


func apply_settings() -> void:
	# Apply audio settings
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_muted)
	
	# Apply video settings
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	
	# Apply STT language
	var stt = get_node_or_null("/root/STTManager")
	if stt and stt.has_method("set_language"):
		stt.set_language(stt_language)
	
	# Apply accessibility
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		if hud.has_method("set_ui_scale"):
			hud.set_ui_scale(ui_scale)
		if hud.has_method("set_reduce_motion"):
			hud.set_reduce_motion(reduce_motion)


func set_music_volume(volume: float) -> void:
	music_volume = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	settings_changed.emit()


func set_music_muted(muted: bool) -> void:
	music_muted = muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), music_muted)
	settings_changed.emit()


func set_sfx_volume(volume: float) -> void:
	sfx_volume = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))
	settings_changed.emit()


func set_sfx_muted(muted: bool) -> void:
	sfx_muted = muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), sfx_muted)
	settings_changed.emit()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	settings_changed.emit()


func set_stt_language(lang: String) -> void:
	stt_language = lang
	var stt = get_node_or_null("/root/STTManager")
	if stt and stt.has_method("set_language"):
		stt.set_language(lang)
	settings_changed.emit()


func set_touch_controls_forced(enabled: bool) -> void:
	touch_controls_forced = enabled
	var touch = get_node_or_null("/root/TouchControls")
	if touch and touch.has_method("apply_touch_ui_enabled"):
		touch.apply_touch_ui_enabled()
	settings_changed.emit()


func set_speech_difficulty(diff: SpeechDifficulty) -> void:
	speech_difficulty = diff
	settings_changed.emit()


func get_speech_difficulty() -> SpeechDifficulty:
	return speech_difficulty


func set_ui_scale(scale: float) -> void:
	ui_scale = clampf(scale, 0.5, 2.0)
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		if hud.has_method("set_ui_scale"):
			hud.set_ui_scale(ui_scale)
	settings_changed.emit()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	if has_node("/root/PlayerHud"):
		var hud = get_node("/root/PlayerHud")
		if hud.has_method("set_reduce_motion"):
			hud.set_reduce_motion(reduce_motion)
	settings_changed.emit()


func set_color_blind_mode(enabled: bool) -> void:
	color_blind_mode = enabled
	settings_changed.emit()


func reset_progress() -> void:
	# Reset all progression data
	var save = get_node_or_null("/root/SaveManager")
	if save and save.has_method("reset_save"):
		save.reset_save()
	
	var player_mgr = get_node_or_null("/root/PlayerManager")
	if player_mgr:
		player_mgr.bonfire_points = 0
		player_mgr.vitality_rank = 0
		player_mgr.might_rank = 0
		player_mgr.haste_rank = 0
		player_mgr.crit_rank = 0
		player_mgr.sword_equipped = false
		if player_mgr.has_method("apply_combat_modifiers"):
			player_mgr.apply_combat_modifiers()
	
	var word_tracker = get_node_or_null("/root/WordTracker")
	if word_tracker and word_tracker.has_method("clear_word_list"):
		word_tracker.clear_word_list()
	
	print("[SettingsManager] Progress reset")
	settings_changed.emit()