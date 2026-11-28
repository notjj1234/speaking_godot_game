class_name TrainingState
extends RefCounted
## Guided Training bookkeeping. The "completed" flag and the one-time tips live
## in SettingsManager (settings.cfg [tutorial]), not the save file, so they
## survive a new run and aren't tied to a save. The two static flags only
## carry intent across one level load.

const TRAINING_PATH := "res://levels/training/training.tscn"
const HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const CAMP_PATH := "res://levels/endless_horde/camp/camp.tscn"

## The current/next camp visit is the guided tour at the end of Training.
static var tour_mode := false
## The next horde load skips the practice pad and starts at stage 1.
static var direct_start := false


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("SettingsManager")


## Players who already started a horde run (e.g. from before Training
## existed) count as trained, so an update never forces them into it.
static func is_completed() -> bool:
	var sm := _settings()
	if sm == null:
		return false
	if bool(sm.tutorial_completed):
		return true
	if _has_played_horde():
		sm.tutorial_completed = true
		sm.save_settings()
		print("✅ Training: returning player, marked complete")
		return true
	return false


static func _has_played_horde() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var tracker: Node = tree.root.get_node_or_null("ProgressTracker") if tree else null
	if tracker == null or not tracker.has_method("lifetime"):
		return false
	var life: Dictionary = tracker.lifetime()
	return int(life.get("runs", 0)) > 0 or int(life.get("best_stage", 0)) > 0


static func mark_completed() -> void:
	var sm := _settings()
	if sm == null:
		return
	sm.tutorial_completed = true
	sm.save_settings()
	print("✅ Training: marked complete")


static func tip_seen(id: String) -> bool:
	var sm := _settings()
	return sm != null and bool(sm.tutorial_tips_seen.get(id, false))


static func mark_tip_seen(id: String) -> void:
	var sm := _settings()
	if sm == null:
		return
	sm.tutorial_tips_seen[id] = true
	sm.save_settings()


static func consume_direct_start() -> bool:
	var was := direct_start
	direct_start = false
	return was


static func in_tutorial(tree: SceneTree) -> bool:
	if tree == null or tree.current_scene == null:
		return false
	var scene := tree.current_scene
	if String(scene.name) == "Training":
		return true
	return scene is Camp and tour_mode
