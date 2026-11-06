extends Node

const SAVE_PATH = "user://"

signal game_loaded
signal game_saved

var current_save: Dictionary = {
	scene_path = "",
	player = {
		hp = 1, 
		max_hp = 1, 
		pos_x = 0,
		pos_y = 0
	},
	items = [],
	persistence = [],
	quests = [],
	bonfire = {
		"points": 0,
		"vitality": 0,
		"might": 0,
		"haste": 0,
		"crit": 0,
		"sword_equipped": false
	}
}

var _boot_progress_loaded := false


func _ready() -> void:
	# ProgressTracker is registered after SaveManager; defer until it exists.
	call_deferred("_boot_load_progress_only")


func _boot_load_progress_only() -> void:
	if _boot_progress_loaded:
		return
	_boot_progress_loaded = true
	if not has_save():
		return
	var file := FileAccess.open(SAVE_PATH + "save.sav", FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err := json.parse(file.get_line())
	if err != OK:
		return
	var save_dict = json.get_data()
	if not (save_dict is Dictionary):
		return
	# Do NOT replace current_save or warp the scene. Progress only.
	if save_dict.has("progress") and save_dict.progress is Dictionary:
		var tracker := get_node_or_null("/root/ProgressTracker")
		if tracker and tracker.has_method("load_from_save"):
			tracker.load_from_save(save_dict.progress)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH + "save.sav")


func save_game() -> void:
	update_player_data()
	update_scene_path()
	update_item_data()
	update_bonfire_data()
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("snapshot"):
		current_save["progress"] = tracker.snapshot()
	var file := FileAccess.open(SAVE_PATH + "save.sav", FileAccess.WRITE)
	if file == null:
		print("❌ SaveManager: Failed to open save file for writing")
		return
	var save_json = JSON.stringify(current_save)
	file.store_line(save_json)
	game_saved.emit()


func load_game() -> void:
	if not has_save():
		print("❌ SaveManager: No save file found")
		return
	var file := FileAccess.open(SAVE_PATH + "save.sav", FileAccess.READ)
	if file == null:
		print("❌ SaveManager: Failed to open save file for reading")
		return
	var json := JSON.new()
	json.parse(file.get_line())
	var save_dict : Dictionary = json.get_data() as Dictionary
	current_save = save_dict

	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("load_from_save"):
		var progress: Dictionary = {}
		if current_save.has("progress") and current_save.progress is Dictionary:
			progress = current_save.progress
		tracker.load_from_save(progress)
	
	LevelManager.load_new_level(current_save.scene_path, "", Vector2.ZERO)
	
	await LevelManager.level_load_started
	
	PlayerManager.set_player_position(Vector2(current_save.player.pos_x, current_save.player.pos_y))
	PlayerManager.set_health(current_save.player.hp, current_save.player.max_hp)
	PlayerManager.INVENTORY_DATA.parse_save_data(current_save.items)
	var bonfire_data: Dictionary = {}
	if current_save.has("bonfire") and current_save.bonfire is Dictionary:
		bonfire_data = current_save.bonfire
	PlayerManager.apply_saved_bonfire(bonfire_data)
	
	await LevelManager.level_loaded
	
	game_loaded.emit()

func update_player_data() -> void:
	var p : Player = PlayerManager.player
	current_save.player.hp = p.hp
	current_save.player.max_hp = p.max_hp
	current_save.player.pos_x = p.global_position.x
	current_save.player.pos_y = p.global_position.y

func update_scene_path() -> void:
	var p : String = ""
	for c in get_tree().root.get_children():
		if c is Level:
			p = c.scene_file_path
			break
	# Keep previous scene_path when no Level is current (e.g. title screen).
	if p != "":
		current_save.scene_path = p
	
func update_item_data() -> void:
	current_save.items = PlayerManager.INVENTORY_DATA.get_save_data()


func update_bonfire_data() -> void:
	current_save.bonfire = PlayerManager.bonfire_save_dict()
	
	
func add_persistent_value(value: String) -> void:
	if check_persistent_value(value) == false:
		current_save.persistence.append(value)
	pass

func check_persistent_value(value: String) -> bool:
	var p = current_save.persistence as Array
	return p.has(value)
