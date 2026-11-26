extends Node2D
## F02 regression: in forced voice-only mode (tutorial level 02), a refused or
## unstartable mic (STT error -1) must unlock the keyboard instead of looping
## "tap to retry" forever. Recoverable errors must keep voice-only armed.
## Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_voice_only_fail_open.tscn

const TOUCH_CONTROLS := "res://touch_controls/Scene/touch_controls.tscn"

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


## Puts the controls in the state begin_voice_only_mode leaves when STT exists.
func _arm_voice_only(controls: Node) -> void:
	controls.set("_voice_only_mode", true)
	controls.set("mic_enabled", true)
	PlayerManager.voice_only = true


func _ready() -> void:
	var controls: Node = load(TOUCH_CONTROLS).instantiate()
	add_child(controls)
	await get_tree().process_frame

	_arm_voice_only(controls)
	controls._on_mic_error(7, "no-match")
	_check("recoverable error keeps voice-only", controls.get("_voice_only_mode") == true)
	_check("recoverable error keeps keyboard locked", PlayerManager.voice_only)

	controls._on_mic_error(-1, "not-allowed")
	_check("refused mic leaves voice-only mode", controls.get("_voice_only_mode") == false)
	_check("refused mic unlocks the keyboard", not PlayerManager.voice_only)
	_check("refused mic turns the mic off", controls.get("mic_enabled") == false)

	PlayerManager.voice_only = false
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
