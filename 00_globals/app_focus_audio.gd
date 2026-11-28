extends Node
## Native apps (Android/iOS/desktop app-pause events): mutes the Master bus
## and stops read-aloud while the app is in the background, and restores
## Master on return. Only Master is touched, so the player's own Music/SFX
## mute settings stay as they were.
## The mic is released separately by STTManager._notification. Web is handled
## by the focus guard in export/web_shell.html (the game loop is frozen there).

var _muted_by_us := false
var _master_was_muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if OS.has_feature("web"):
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_on_paused()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_on_resumed()


func _on_paused() -> void:
	if _muted_by_us:
		return
	_master_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	# Read-aloud goes through the OS speech engine, not the Master bus.
	var tts := get_node_or_null("/root/TTSManager")
	if tts and tts.has_method("stop"):
		tts.stop()
	_muted_by_us = true
	print("⚠️ AppFocusAudio: app paused, Master muted")


func _on_resumed() -> void:
	if not _muted_by_us:
		return
	AudioServer.set_bus_mute(0, _master_was_muted)
	_muted_by_us = false
	print("✅ AppFocusAudio: app resumed, Master restored")
