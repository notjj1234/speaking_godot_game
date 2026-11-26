extends Node
## Save/load regressions. Run headless on a scratch copy only: it writes
## user://save.sav (a renamed scratch project has its own user:// dir).
##   Godot --headless --path <copy> res://tools/tests/test_save_load.tscn
## F17: a corrupt or scene-less save must not start a load.
## F11/F16: Reset progress empties the inventory and leaves nothing loadable.
## F10: loading after a Main Menu trip keeps the saved position.
## F12: pause-menu Load keeps the tree paused until the new level is in.

const SAVE_FILE := "user://save.sav"
const PLAYGROUND := "res://levels/playground.tscn"
const SWORD := "res://items/sword.tres"
## Open floor near the playground PlayerSpawn (288, 207), away from colliders
## that would nudge the player; far enough from the spawn to tell them apart.
const PLAYGROUND_SPAWN := Vector2(288, 207)
const SAVED_POS := Vector2(328, 237)

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _write_save(text: String) -> void:
	var f := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	f.store_line(text)
	f.close()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Awaits `sig`, giving up after `limit` seconds. Returns true if it fired.
func _await_signal(sig: Signal, limit: float) -> bool:
	var state := {"fired": false}
	var mark := func(_a = null, _b = null) -> void: state["fired"] = true
	sig.connect(mark, CONNECT_ONE_SHOT)
	var timer := get_tree().create_timer(limit, true, false, true)
	while not state["fired"] and timer.time_left > 0.0:
		await get_tree().process_frame
	if sig.is_connected(mark):
		sig.disconnect(mark)
	return state["fired"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	# Survive change_scene_to_file: the old current scene is freed, so step off it.
	get_tree().current_scene = null
	await _test_rejects_bad_saves()
	await _test_reset_clears_inventory()
	await _test_load_keeps_position()
	await _test_pause_menu_load_stays_paused()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_rejects_bad_saves() -> void:
	# level_load_started only fires after the fade-out, so wait well past it.
	_write_save("{not json")
	SaveManager.load_game()
	_check("corrupt save: tree not paused", not get_tree().paused)
	var started := await _await_signal(LevelManager.level_load_started, 2.0)
	_check("corrupt save: no load started", not started)
	_write_save(JSON.stringify({"scene_path": "", "player": {"hp": 1, "max_hp": 1, "pos_x": 0, "pos_y": 0}}))
	SaveManager.load_game()
	_check("scene-less save: tree not paused", not get_tree().paused)
	started = await _await_signal(LevelManager.level_load_started, 2.0)
	_check("scene-less save: no load started", not started)


func _test_reset_clears_inventory() -> void:
	PlayerManager.INVENTORY_DATA.add_item(load(SWORD))
	_check("setup: sword in inventory", PlayerManager.has_sword())
	SettingsManager.reset_progress()
	var empty := true
	for s in PlayerManager.INVENTORY_DATA.slots:
		if s != null:
			empty = false
	_check("reset empties the inventory", empty)
	_check("reset leaves no loadable scene",
			str(SaveManager.current_save.get("scene_path", "x")).is_empty())


func _test_load_keeps_position() -> void:
	_write_save(JSON.stringify({
		"scene_path": PLAYGROUND,
		"player": {"hp": 4, "max_hp": 6, "pos_x": SAVED_POS.x, "pos_y": SAVED_POS.y},
		"items": [], "persistence": [], "quests": [],
	}))
	PlayerManager.player_spawned = false  # what Main Menu leaves behind
	SaveManager.load_game()
	var loaded := await _await_signal(SaveManager.game_loaded, 10.0)
	_check("save loads", loaded)
	await _frames(5)
	var pos := PlayerManager.player.global_position
	_check("loaded position is the saved one", pos.distance_to(SAVED_POS) < 1.0, str(pos))
	_check("player not sent back to PlayerSpawn", pos.distance_to(PLAYGROUND_SPAWN) > 10.0, str(pos))
	_check("loaded HP is the saved one", PlayerManager.player.hp == 4, str(PlayerManager.player.hp))


func _test_pause_menu_load_stays_paused() -> void:
	PauseMenu.show_pause_menu()
	PauseMenu._do_load_game()
	var started := await _await_signal(LevelManager.level_load_started, 10.0)
	_check("pause-menu load starts", started)
	await _frames(2)
	_check("pause menu closed for the load", not PauseMenu.visible)
	_check("tree stays paused during the load", get_tree().paused)
	await _await_signal(LevelManager.level_loaded, 10.0)
	_check("tree unpaused once the level is in", not get_tree().paused)
