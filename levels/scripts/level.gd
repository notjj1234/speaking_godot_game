# level.gd

class_name Level extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.y_sort_enabled = true
	PlayerManager.set_as_parent(self)
	LevelManager.level_load_started.connect(_free_level)
	if name == "02":
		_set_voice_only(true)
	var music = get_node_or_null("/root/MusicManager")
	if music and music.has_method("play_for_level"):
		music.play_for_level()


func _free_level() -> void:
	if name == "02":
		_set_voice_only(false)
	PlayerManager.unparent_player(self)
	queue_free()
	pass


func _set_voice_only(enabled: bool) -> void:
	PlayerManager.voice_only = enabled
	var hud = get_node_or_null("/root/PlayerHud")
	if hud:
		if enabled and hud.has_method("show_voice_only_banner"):
			hud.show_voice_only_banner()
		elif not enabled and hud.has_method("hide_voice_only_banner"):
			hud.hide_voice_only_banner()
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if enabled and node.has_method("begin_voice_only_mode"):
			node.begin_voice_only_mode()
		elif not enabled and node.has_method("end_voice_only_mode"):
			node.end_voice_only_mode()
