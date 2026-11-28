extends Node
## Plays the generated UI sounds (tools/audio_build/build_sfx.py) on the SFX bus.
## Call Sfx.play(&"correct") etc.; a small pool lets cues overlap.

const CUES: PackedStringArray = ["click", "accept", "correct", "wrong", "error", "listen", "purchase", "phase", "victory"]
const BUS_NAME := "SFX"
const POOL_SIZE := 6

var last_cue: StringName = &""
var _streams: Dictionary = {}
var _counts: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue in CUES:
		var path := "res://audio/sfx/%s.wav" % cue
		if ResourceLoader.exists(path):
			_streams[StringName(cue)] = load(path)
		else:
			print("⚠️ Sfx: missing %s" % path)
	var bus := BUS_NAME if AudioServer.get_bus_index(BUS_NAME) != -1 else "Master"
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = bus
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool.append(player)


func play(cue: StringName) -> void:
	var stream: AudioStream = _streams.get(cue)
	if stream == null:
		print("⚠️ Sfx: unknown cue %s" % cue)
		return
	last_cue = cue
	_counts[cue] = int(_counts.get(cue, 0)) + 1
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.play()


func count(cue: StringName) -> int:
	return int(_counts.get(cue, 0))


func reset_counts() -> void:
	_counts.clear()
	last_cue = &""
