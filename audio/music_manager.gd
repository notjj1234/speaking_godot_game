extends Node

const TRACK_PATH := "res://audio/music/Bonetrousle.ogg"
const BUS_NAME := "Music"

var _player: AudioStreamPlayer
var _track: AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_music_bus()
	_track = load(TRACK_PATH)
	if _track is AudioStreamOggVorbis:
		_track.loop = true
	_player = AudioStreamPlayer.new()
	_player.name = "LevelMusic"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = BUS_NAME
	_player.stream = _track
	add_child(_player)
	
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.settings_changed.connect(_on_settings_changed)
		_on_settings_changed()


func _on_settings_changed() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if not settings:
		return
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, settings.music_muted)
	if settings.music_muted or settings.music_volume <= 0.001:
		AudioServer.set_bus_volume_db(index, -80.0)
	else:
		AudioServer.set_bus_volume_db(index, linear_to_db(settings.music_volume))


func play_for_level() -> void:
	if _player == null or _track == null:
		return
	if _player.stream != _track:
		_player.stream = _track
	if not _player.playing:
		_player.play()
		print("✅ Level music started")


func stop_for_menu() -> void:
	if _player and _player.playing:
		_player.stop()
		print("✅ Level music stopped")


func set_volume_linear(value: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_volume(value)


func set_muted(is_muted: bool) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_muted(is_muted)


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, "Master")