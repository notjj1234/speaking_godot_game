# level.gd

class_name Level extends Node2D

## Early tutorial / menus — no optional mic toggle.
const NO_OPTIONAL_MIC := [
	"TitleScreen",
	"Playground",
	"01",
	"02",
	"ComingSoon",
]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.y_sort_enabled = true
	PlayerManager.set_as_parent(self)
	LevelManager.level_load_started.connect(_free_level)
	if name == "02":
		# Defer so TouchControls has finished _ready (STT signals wired) and the
		# player has been nudged clear of transition walls.
		call_deferred("_set_voice_only", true)
	elif _offers_optional_mic():
		# Final tutorial (03) and onwards: mic is optional; keyboard stays free.
		call_deferred("_set_optional_mic", true)
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("play_for_level"):
		music.play_for_level()


func _free_level() -> void:
	if name == "02":
		_set_voice_only(false)
	elif _offers_optional_mic():
		_set_optional_mic(false)
	PlayerManager.unparent_player(self)
	queue_free()
	pass


func _offers_optional_mic() -> bool:
	return name not in NO_OPTIONAL_MIC


func _set_voice_only(enabled: bool) -> void:
	var hud = get_node_or_null("/root/PlayerHud")
	if hud:
		if enabled and hud.has_method("show_voice_only_banner"):
			hud.show_voice_only_banner()
		elif not enabled and hud.has_method("hide_voice_only_banner"):
			hud.hide_voice_only_banner()
	var started := false
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if enabled and node.has_method("begin_voice_only_mode"):
			node.begin_voice_only_mode()
			started = true
		elif not enabled and node.has_method("end_voice_only_mode"):
			node.end_voice_only_mode()
	# Only lock keyboard after a touch-controls node owns the voice-only session.
	# begin_voice_only_mode clears voice_only itself if the mic cannot start.
	if enabled and not started:
		print("⚠️ No touch controls for voice-only — keeping keyboard enabled.")
		PlayerManager.voice_only = false
	elif not enabled:
		PlayerManager.voice_only = false


func _set_optional_mic(enabled: bool) -> void:
	var hud = get_node_or_null("/root/PlayerHud")
	if hud:
		if enabled and hud.has_method("show_optional_mic_banner"):
			hud.show_optional_mic_banner()
		elif not enabled and hud.has_method("hide_optional_mic_banner"):
			hud.hide_optional_mic_banner()
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if enabled and node.has_method("begin_optional_mic_mode"):
			node.begin_optional_mic_mode()
		elif not enabled and node.has_method("end_optional_mic_mode"):
			node.end_optional_mic_mode()
	# Optional mic never locks the keyboard.
	PlayerManager.voice_only = false
