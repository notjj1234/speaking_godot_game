extends Node

## Plays the generated 8-bit tracks (tools/audio_build/build_music.py). Levels
## ask for a track by id; a new id crossfades, the same id keeps playing (so
## walking between tutorial rooms never restarts the song). Speech challenges
## duck the music so it stays out of the mic and the read-aloud voice; boss
## phases raise its speed and key a step, NES style.

const BUS_NAME := "Music"
const TRACKS := {
	&"title": "res://audio/music/title.ogg",
	&"tutorial": "res://audio/music/tutorial.ogg",
	&"meadow": "res://audio/music/meadow.ogg",
	&"ruins": "res://audio/music/ruins.ogg",
	&"ashen": "res://audio/music/ashen.ogg",
	&"frozen": "res://audio/music/frozen.ogg",
	&"boss_slime": "res://audio/music/boss_slime.ogg",
	&"boss_bone": "res://audio/music/boss_bone.ogg",
	&"boss_orc": "res://audio/music/boss_orc.ogg",
	&"boss_frost": "res://audio/music/boss_frost.ogg",
	&"camp": "res://audio/music/camp.ogg",
	&"npc_smith": "res://audio/music/npc_smith.ogg",
	&"npc_trainer": "res://audio/music/npc_trainer.ogg",
	&"npc_cook": "res://audio/music/npc_cook.ogg",
}
const FADE_SEC := 0.6
const SILENT_DB := -60.0
const DUCK_DB := -14.0
const DUCK_IN_SEC := 0.25
const DUCK_OUT_SEC := 0.5
## pitch_scale per boss phase (1, 2, 3): +1 and +2 semitones, faster too.
const INTENSITY := [1.0, 1.06, 1.12]

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _track: StringName = &""
var _streams: Dictionary = {}
## Per-player crossfade level and the shared duck offset, both in dB.
var _fade_db: Array[float] = [SILENT_DB, SILENT_DB]
var _duck_db: float = 0.0
var _fade_tween: Tween
var _duck_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_music_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = BUS_NAME
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)

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


## Crossfades to `id`; &"" fades to silence. The same id keeps playing.
func play_track(id: StringName) -> void:
	if _players.is_empty():
		return
	if id == _track and (id == &"" or _players[_active].playing):
		return
	var stream: AudioStream = null
	if id != &"":
		stream = _stream_for(id)
		if stream == null:
			print("⚠️ Music: unknown track ", id)
			return
	_track = id
	var old := _active
	if stream != null:
		_active = 1 - _active
		var p := _players[_active]
		p.stream = stream
		p.pitch_scale = INTENSITY[0]
		_fade_db[_active] = SILENT_DB
		_apply_volume(_active)
		p.play()
	_crossfade(old, stream != null)
	print("✅ Music: ", id if id != &"" else &"(silence)")


## Immediate stop (menus); also clears any duck.
func stop_for_menu() -> void:
	_kill(_fade_tween)
	_kill(_duck_tween)
	_duck_db = 0.0
	for i in _players.size():
		_players[i].stop()
		_fade_db[i] = SILENT_DB
		_apply_volume(i)
	if _track != &"":
		print("✅ Music stopped")
	_track = &""


func set_ducked(on: bool) -> void:
	_kill(_duck_tween)
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck_db, DUCK_DB if on else 0.0, DUCK_IN_SEC if on else DUCK_OUT_SEC)


## Boss phase 1-3 (Enemy.boss_phase_changed is 1-based).
func set_intensity(phase: int) -> void:
	if _players.is_empty():
		return
	_players[_active].pitch_scale = INTENSITY[clampi(phase, 1, INTENSITY.size()) - 1]


func current_track() -> StringName:
	return _track


func active_player() -> AudioStreamPlayer:
	return _players[_active] if not _players.is_empty() else null


func set_volume_linear(value: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_volume(value)


func set_muted(is_muted: bool) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_music_muted(is_muted)


func _stream_for(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	if not TRACKS.has(id):
		return null
	var stream := load(TRACKS[id]) as AudioStream
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	if stream == null:
		print("❌ Music: could not load ", TRACKS[id])
	_streams[id] = stream
	return stream


func _crossfade(old: int, fade_in_new: bool) -> void:
	_kill(_fade_tween)
	_fade_tween = create_tween().set_parallel(true)
	if old != _active or not fade_in_new:
		_fade_tween.tween_method(_set_fade.bind(old), _fade_db[old], SILENT_DB, FADE_SEC)
	if fade_in_new:
		_fade_tween.tween_method(_set_fade.bind(_active), _fade_db[_active], 0.0, FADE_SEC)
	var faded := old if (old != _active or not fade_in_new) else -1
	_fade_tween.chain().tween_callback(func():
		if faded >= 0 and (faded != _active or _track == &""):
			_players[faded].stop())


func _set_fade(db: float, index: int) -> void:
	_fade_db[index] = db
	_apply_volume(index)


func _set_duck(db: float) -> void:
	_duck_db = db
	for i in _players.size():
		_apply_volume(i)


func _apply_volume(index: int) -> void:
	_players[index].volume_db = maxf(SILENT_DB, _fade_db[index] + _duck_db)


func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()


func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, "Master")
