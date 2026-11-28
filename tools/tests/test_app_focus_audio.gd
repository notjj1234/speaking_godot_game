extends Node2D
## Native apps (Android): Master is muted while the app is in the background
## and restored on return. Music/SFX (the user's own mutes) are never touched.

class FakeTts extends TTSSpeechProvider:
	var stops := 0
	var talking := false
	func is_available() -> bool: return true
	func speak(_text: String) -> bool:
		talking = true
		return true
	func stop() -> void:
		stops += 1
		talking = false
	func is_speaking() -> bool: return talking


var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	await get_tree().process_frame
	var focus := get_node_or_null("/root/AppFocusAudio")
	_check("autoload registered", focus != null)
	if focus == null:
		_finish()
		return
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	var music_was := AudioServer.is_bus_mute(music)
	var sfx_was := AudioServer.is_bus_mute(sfx)

	AudioServer.set_bus_mute(0, false)
	focus.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check("paused mutes Master", AudioServer.is_bus_mute(0))
	focus.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("resumed restores unmuted Master", not AudioServer.is_bus_mute(0))

	AudioServer.set_bus_mute(0, true)
	focus.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	focus.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("already-muted Master stays muted after resume", AudioServer.is_bus_mute(0))

	AudioServer.set_bus_mute(0, false)
	focus.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	focus.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	focus.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("double pause then resume restores original", not AudioServer.is_bus_mute(0))

	focus.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("stray resume changes nothing", not AudioServer.is_bus_mute(0))

	# Read-aloud (DisplayServer TTS) bypasses the Master bus: it must stop too.
	var tts := get_node("/root/TTSManager")
	var old_tts = tts.provider
	var fake := FakeTts.new()
	tts.provider = fake
	tts.speak("hello there")
	fake.stops = 0  # speak() stops any earlier line itself
	focus.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check("paused stops read-aloud", fake.stops >= 1 and not tts._speaking, "stops %d" % fake.stops)
	focus.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	tts.provider = old_tts

	_check("music/sfx buses untouched", AudioServer.is_bus_mute(music) == music_was
		and AudioServer.is_bus_mute(sfx) == sfx_was)
	_finish()


func _finish() -> void:
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
