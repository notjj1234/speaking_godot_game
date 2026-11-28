extends Node
## Generated chiptune music: every track loads and loops, levels pick their
## track, the horde switches per arena and boss, speech challenges duck it and
## boss phases speed it up. Run headless on a scratch copy only (scene loads
## can write user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_music.tscn

const HORDE := "res://levels/endless_horde/endless_horde.tscn"
const CAMP := "res://levels/endless_horde/camp/camp.tscn"
const TITLE := "res://levels/title_screen/title_screen.tscn"
const TUTORIAL := "res://levels/tutorial_area/01.tscn"
const COMING_SOON := "res://levels/coming_soon/coming_soon.tscn"
const OLD_TRACK := "res://audio/music/Bonetrousle.ogg"

var passes := 0
var failures := 0
var music: Node


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _await_scene(path: String, limit: float) -> bool:
	var timer := get_tree().create_timer(limit, true, false, true)
	while timer.time_left > 0.0:
		var scene := get_tree().current_scene
		if scene and scene.scene_file_path == path and not LevelManager.is_loading:
			return true
		await get_tree().process_frame
	return false


func _load(path: String) -> bool:
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(path, "", Vector2.ZERO)
	var ok := await _await_scene(path, 8.0)
	await _wait(0.2)
	return ok


func _track() -> StringName:
	return music.call("current_track")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	get_tree().current_scene = null
	music = get_node_or_null("/root/MusicManager")
	_check("autoload MusicManager exists", music != null)
	if music == null or not music.has_method("play_track"):
		_check("MusicManager has play_track", false)
		_finish()
		return
	_check_files()
	await _check_switching()
	await _check_ducking()
	await _check_intensity()
	await _check_mapping()
	_finish()


func _check_files() -> void:
	var tracks: Dictionary = music.get("TRACKS")
	var ids := tracks.keys()
	ids.sort()
	_check("fourteen tracks", tracks.size() == 14, str(ids))
	for id in [&"title", &"tutorial", &"meadow", &"ruins", &"ashen", &"frozen",
			&"boss_slime", &"boss_bone", &"boss_orc", &"boss_frost", &"camp",
			&"npc_smith", &"npc_trainer", &"npc_cook"]:
		_check("track %s listed" % id, tracks.has(id))
	for id in tracks:
		var stream := load(tracks[id]) as AudioStreamOggVorbis
		_check("%s loads as AudioStreamOggVorbis" % id, stream != null, str(tracks[id]))
		if stream == null:
			continue
		var length := stream.get_length()
		_check("%s is a 20-90 s loop" % id, length >= 20.0 and length <= 90.0, "%.1f s" % length)
		var playing := music.call("_stream_for", id) as AudioStreamOggVorbis
		_check("%s loops when played" % id, playing != null and playing.loop)
	_check("old Undertale track is gone", not FileAccess.file_exists(OLD_TRACK) and not ResourceLoader.exists(OLD_TRACK))
	var src := FileAccess.get_file_as_string("res://audio/music_manager.gd")
	_check("music manager no longer names it", not src.contains("Bonetrousle"))


func _check_switching() -> void:
	music.call("play_track", &"meadow")
	await _wait(1.0)
	var first := music.call("active_player") as AudioStreamPlayer
	_check("play_track starts the track", _track() == &"meadow" and first != null and first.playing, str(_track()))
	var pos := first.get_playback_position()
	music.call("play_track", &"meadow")
	await _wait(0.3)
	var same := music.call("active_player") as AudioStreamPlayer
	_check("same track again does not restart", same == first and same.playing and same.get_playback_position() >= pos,
			"%.2f -> %.2f" % [pos, same.get_playback_position()])
	music.call("play_track", &"ruins")
	_check("new track is current at once", _track() == &"ruins")
	await _wait(1.0)
	var now := music.call("active_player") as AudioStreamPlayer
	var players := music.find_children("*", "AudioStreamPlayer", false, false)
	var audible := players.filter(func(p): return p.playing)
	_check("crossfade ends with only the new player playing", audible.size() == 1 and audible[0] == now and now != first,
			str(audible.size()))
	_check("new player plays the ruins stream", now.stream == music.call("_stream_for", &"ruins"))
	music.call("play_track", &"not_a_track")
	_check("unknown id keeps the current track", _track() == &"ruins" and now.playing)
	music.call("play_track", &"")
	await _wait(1.0)
	_check("empty id fades to silence", _track() == &"" and players.all(func(p): return not p.playing))


func _check_ducking() -> void:
	music.call("play_track", &"camp")
	await _wait(1.0)
	var p := music.call("active_player") as AudioStreamPlayer
	var full := p.volume_db
	music.call("set_ducked", true)
	await _wait(0.6)
	_check("ducking lowers the music about 14 dB", absf((full - p.volume_db) - 14.0) < 0.5, "%.1f -> %.1f" % [full, p.volume_db])
	music.call("set_ducked", false)
	await _wait(0.8)
	_check("unducking restores it", absf(p.volume_db - full) < 0.5, "%.1f" % p.volume_db)
	PlayerHud.show_speech_challenge("hello")
	await _wait(0.6)
	_check("a speech challenge ducks the music", full - p.volume_db > 13.0, "%.1f" % p.volume_db)
	PlayerHud.hide_speech_challenge()
	await _wait(0.8)
	_check("closing the challenge restores it", absf(p.volume_db - full) < 0.5, "%.1f" % p.volume_db)
	music.call("set_ducked", true)
	music.call("stop_for_menu")
	music.call("play_track", &"camp")
	await _wait(1.0)
	p = music.call("active_player") as AudioStreamPlayer
	_check("stop_for_menu clears the duck", absf(p.volume_db - full) < 0.5, "%.1f" % p.volume_db)


func _check_intensity() -> void:
	music.call("play_track", &"boss_bone")
	await _wait(0.1)
	var p := music.call("active_player") as AudioStreamPlayer
	_check("phase 1 plays at normal speed", is_equal_approx(p.pitch_scale, 1.0), str(p.pitch_scale))
	music.call("set_intensity", 2)
	_check("phase 2 is 1.06x", is_equal_approx(p.pitch_scale, 1.06), str(p.pitch_scale))
	music.call("set_intensity", 3)
	_check("phase 3 is 1.12x", is_equal_approx(p.pitch_scale, 1.12), str(p.pitch_scale))
	music.call("play_track", &"camp")
	await _wait(0.1)
	var q := music.call("active_player") as AudioStreamPlayer
	_check("a new track resets the speed", is_equal_approx(q.pitch_scale, 1.0), str(q.pitch_scale))


func _check_mapping() -> void:
	var saved_progress: Dictionary = ProgressTracker.snapshot()
	ProgressTracker.load_from_save({})
	_check("horde loads", await _load(HORDE))
	var horde := get_tree().current_scene
	_check("horde practice plays meadow", _track() == &"meadow", str(_track()))
	var expect := {21: &"ruins", 41: &"ashen", 61: &"frozen", 20: &"boss_slime", 40: &"boss_bone",
			60: &"boss_orc", 80: &"boss_frost", 81: &"meadow", 101: &"ruins", 100: &"boss_slime"}
	# Arenas (and their music) cycle every 80 stages: 81 is the Meadow again.
	for stage in [21, 41, 61, 20, 40, 60, 80, 81, 101, 100]:
		horde.call("_jump_to_stage", stage)
		await _wait(0.3)
		PlayerManager.set_health(999, 999)
		_check("stage %d plays %s" % [stage, expect[stage]], _track() == expect[stage], str(_track()))
	var boss: Enemy = null
	for c in horde.get_node("HordeEnemies").get_children():
		if c is Enemy and (c as Enemy).is_boss():
			boss = c
	_check("stage 100 has a boss", boss != null)
	if boss:
		boss.call("_advance_boss_phase")
		await get_tree().process_frame
		var p := music.call("active_player") as AudioStreamPlayer
		_check("boss phase 2 speeds the boss track up", is_equal_approx(p.pitch_scale, 1.06), str(p.pitch_scale))
	_check("camp loads", await _load(CAMP))
	_check("camp plays camp", _track() == &"camp", str(_track()))
	await _check_npc_themes()
	_check("title loads", await _load(TITLE))
	_check("title plays title", _track() == &"title", str(_track()))
	_check("tutorial loads", await _load(TUTORIAL))
	_check("tutorial plays tutorial", _track() == &"tutorial", str(_track()))
	_check("coming soon loads", await _load(COMING_SOON))
	var players := music.find_children("*", "AudioStreamPlayer", false, false)
	_check("coming soon is silent", players.all(func(p): return not p.playing))
	ProgressTracker.load_from_save(saved_progress)


## Each camp NPC has a theme while you talk to them; the camp track comes back
## after. Listening for speech lowers the music instead of muting everything.
func _check_npc_themes() -> void:
	var expect := {"smith": &"npc_smith", "trainer": &"npc_trainer", "cook": &"npc_cook"}
	var conv := get_tree().get_first_node_in_group("camp_conversation")
	_check("camp has a conversation", conv != null)
	var found := {}
	for npc in get_tree().current_scene.find_children("*", "NPC", true, false):
		var res = npc.get("npc_resource")
		if res == null or not expect.has(res.conversation_id):
			continue
		var id: String = res.conversation_id
		found[id] = true
		_check("%s resource names its theme" % id, res.get("music_track") == expect[id], str(res.get("music_track")))
		npc.call("player_interact")
		await _wait(0.2)
		_check("talking to the %s plays %s" % [id, expect[id]], _track() == expect[id], str(_track()))
		if conv:
			conv.call("leave")
		await _wait(2.0)
		_check("leaving the %s brings the camp track back" % id, _track() == &"camp", str(_track()))
	_check("all three camp NPCs found", found.size() == 3, str(found.keys()))
	if conv == null or not conv.has_method("_quiet_for_mic"):
		_check("conversation has _quiet_for_mic", false)
		return
	var master := AudioServer.get_bus_index("Master")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var master_before := AudioServer.is_bus_mute(master)
	var sfx_before := AudioServer.is_bus_mute(sfx_bus)
	var p := music.call("active_player") as AudioStreamPlayer
	var full := p.volume_db
	conv.call("_quiet_for_mic")
	await _wait(0.6)
	_check("listening keeps the Master bus on", AudioServer.is_bus_mute(master) == master_before)
	_check("listening mutes game sounds (SFX bus)", AudioServer.is_bus_mute(sfx_bus))
	_check("listening lowers the music, not stops it", p.playing and full - p.volume_db > 13.0,
			"%.1f -> %.1f" % [full, p.volume_db])
	conv.call("_restore_after_mic")
	await _wait(0.8)
	_check("after listening the SFX bus is restored", AudioServer.is_bus_mute(sfx_bus) == sfx_before)
	_check("after listening the music is back up", absf(p.volume_db - full) < 0.5, "%.1f" % p.volume_db)


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
