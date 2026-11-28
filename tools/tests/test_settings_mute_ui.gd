extends Node2D
## Mute must look muted: "Unmute" text, a red tint and a dimmed slider, in
## both Settings and the pause menu. Moving a slider above 0 unmutes.

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var sm := get_node("/root/SettingsManager")
	var music_was: bool = sm.music_muted
	var sfx_was: bool = sm.sfx_muted
	sm.set_music_muted(false)
	sm.set_sfx_muted(false)

	var settings: SettingsNode = load("res://gui/settings/settings.tscn").instantiate()
	add_child(settings)
	await get_tree().process_frame

	settings._on_music_mute_pressed()
	_check("settings: music mute → Unmute", settings.music_mute_button.text == "Unmute",
		settings.music_mute_button.text)
	_check("settings: music slider dimmed", is_equal_approx(settings.music_slider.modulate.a, 0.45),
		str(settings.music_slider.modulate.a))
	_check("settings: music button tinted", settings.music_mute_button.modulate == MuteLook.MUTED_TINT,
		str(settings.music_mute_button.modulate))

	settings._on_sfx_mute_pressed()
	_check("settings: sfx mute → Unmute", settings.sfx_mute_button.text == "Unmute",
		settings.sfx_mute_button.text)
	_check("settings: sfx slider dimmed", is_equal_approx(settings.sfx_slider.modulate.a, 0.45))

	settings.music_slider.value = 50.0
	_check("settings: slider above 0 unmutes music", sm.music_muted == false)
	_check("settings: unmuted look restored", settings.music_mute_button.text == "Mute"
		and is_equal_approx(settings.music_slider.modulate.a, 1.0)
		and settings.music_mute_button.modulate == Color.WHITE)
	settings.sfx_slider.value = 50.0
	_check("settings: slider above 0 unmutes sfx", sm.sfx_muted == false
		and settings.sfx_mute_button.text == "Mute")

	var pause := get_node("/root/PauseMenu")
	sm.set_music_muted(false)
	pause._on_music_mute_pressed()
	_check("pause: mute → Unmute", pause.music_mute_button.text == "Unmute", pause.music_mute_button.text)
	_check("pause: slider dimmed", is_equal_approx(pause.music_slider.modulate.a, 0.45))
	pause._on_music_mute_pressed()
	_check("pause: unmute restores", pause.music_mute_button.text == "Mute"
		and is_equal_approx(pause.music_slider.modulate.a, 1.0))

	var fresh: Node = load("res://00_globals/global_settings.gd").new()
	_check("fresh default not muted", fresh.music_muted == false)
	fresh.free()

	sm.set_music_muted(music_was)
	sm.set_sfx_muted(sfx_was)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
