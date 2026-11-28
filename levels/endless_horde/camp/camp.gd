class_name Camp
extends Level
## Where an Endless Horde death (or a boss victory) lands you: a walkable camp
## with talking NPCs who sell upgrades and food, and a fire that sends you back
## to the fight.

const HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

var _navigating := false
## Gems granted on arrival for a beaten boss; 0 means this visit is a death's.
var victory_gems: int = 0

@onready var conversation: CampConversation = $CampConversation


func _ready() -> void:
	_prepare_ground()
	super()
	PlayerManager.revive_for_horde()
	_claim_boss_reward()
	PlayerManager.convert_gems_to_points()
	# One save persists the claimed (zeroed) reward and the points together.
	SaveManager.save_game()
	conversation.action_chosen.connect(_on_fire_action)
	print("✅ Camp: rested, %d gems to spend" % PlayerManager.bonfire_points)


func music_track() -> StringName:
	return &"camp"


func is_victory() -> bool:
	return victory_gems > 0


func _claim_boss_reward() -> void:
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker == null or not tracker.has_method("claim_boss_reward"):
		return
	var stage := int(tracker.claim_boss_reward())
	if stage <= 0:
		return
	victory_gems = HordeCurve.boss_reward_gems(stage)
	PlayerManager.bonfire_points += victory_gems
	PlayerHud.show_notice("Boss beaten! +%d gems" % victory_gems)
	print("✅ Camp: boss on stage %d beaten, +%d gems" % [stage, victory_gems])


## The camp reuses the Ashen Camp arena as its ground. Its props sort with the
## player, and its decorative fire gives way to the interactive CampFire.
func _prepare_ground() -> void:
	var decor := get_node_or_null("CampGround/Decor") as Node2D
	if decor == null:
		return
	decor.y_sort_enabled = true
	for child in decor.get_children():
		if String(child.name).begins_with("campfire"):
			child.visible = false


func _on_fire_action(action_id: String) -> void:
	match action_id:
		"fight":
			_leave(HORDE_PATH)
		"title":
			_leave(TITLE_PATH)
		"journal":
			var tracker := get_node_or_null("/root/ProgressTracker")
			if tracker and tracker.has_method("show_journal"):
				tracker.show_journal()


func _leave(level_path: String) -> void:
	if _navigating:
		return
	_navigating = true
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(level_path, "", Vector2.ZERO)
