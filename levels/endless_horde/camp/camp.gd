class_name Camp
extends Level
## Where an Endless Horde death (or a boss victory) lands you: a walkable camp
## with talking NPCs who sell upgrades and food, and a fire that sends you back
## to the fight.

signal _tour_talked

const HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

var _navigating := false
## Gems granted on arrival for a beaten boss; 0 means this visit is a death's.
var victory_gems: int = 0
## Guided Training's camp tour (TrainingState.tour_mode); null on normal visits.
var tour_coach: TrainingCoach
var tour_banner: CoachBanner
var tour_pointer: GuidePointer
var _tour_dialog_open := Callable()
var _tour_dialog_closed := Callable()

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
	if TrainingState.tour_mode:
		_start_tour()
	else:
		_show_tip()
	print("✅ Camp: rested, %d gems to spend" % PlayerManager.bonfire_points)


## At most one reminder per visit: the death tip first, the shop tip later.
func _show_tip() -> void:
	if not is_victory() and CoachTips.show_once(self, "camp_after_death", CoachTips.CAMP_AFTER_DEATH):
		return
	if PlayerManager.bonfire_points >= PlayerManager.upgrade_cost("might"):
		CoachTips.show_once(self, "shop_ready", CoachTips.SHOP_READY)


## The end of Guided Training: talk to someone, buy something, then Fight.
func _start_tour() -> void:
	# First time only, and top-up only: replaying Training can't farm points.
	if not TrainingState.is_completed():
		var gift := PlayerManager.upgrade_cost("might") - PlayerManager.bonfire_points
		if gift > 0:
			PlayerManager.bonfire_points += gift
			Sfx.play(&"purchase")
			PlayerHud.show_notice("A gift: +%d gems to spend!" % gift)
	tour_banner = CoachBanner.new()
	add_child(tour_banner)
	tour_coach = TrainingCoach.new()
	add_child(tour_coach)
	tour_pointer = GuidePointer.new()
	add_child(tour_pointer)
	tour_coach.pointer = tour_pointer
	tour_coach.lessons = [
		{"id": &"talk", "goal": "Talk to someone", "begin": _tour_talk, "point": _nearest_npc,
			"text": "This is camp. Walk up to someone and talk to them. I've put a few points in your pocket.",
			"touch_text": "This is camp. Walk up to someone and tap Talk. I've put a few points in your pocket."},
		{"id": &"buy", "goal": "Buy something", "begin": func(): return conversation.purchase_made,
			"point": _point_buy,
			"text": "Buy something! You seal each deal by saying a phrase - more speaking practice."},
		{"id": &"fire", "goal": "Go to the fire", "point": func(): return get_node_or_null("CampFire"), "text": "When you're ready, go to the fire and choose Fight. Good luck out there!"},
	]
	tour_coach.start(tour_banner)
	# A conversation owns the screen: the coach steps aside until it closes.
	_tour_dialog_open = _on_tour_dialog.bind(true)
	_tour_dialog_closed = _on_tour_dialog.bind(false)
	DialogSystem.opened.connect(_tour_dialog_open)
	DialogSystem.closed.connect(_tour_dialog_closed)
	print("✅ Camp: guided tour started")


const TOUR_NPCS: Array[String] = ["Smith", "Trainer", "Cook"]


func _nearest_npc() -> Node2D:
	var player := PlayerManager.player
	var best: Node2D = null
	for npc_name in TOUR_NPCS:
		var npc := get_node_or_null(npc_name) as Node2D
		if npc == null:
			continue
		if best == null or (player and npc.global_position.distance_to(player.global_position)
				< best.global_position.distance_to(player.global_position)):
			best = npc
	return best


## While talking: a ring on the first choice chip; otherwise the nearest NPC.
func _point_buy():
	if DialogSystem.is_open and DialogSystem.choice_row and DialogSystem.choice_row.visible:
		for chip in DialogSystem.choice_row.get_children():
			if chip is Button and chip != DialogSystem.leave_button and chip.is_visible_in_tree():
				return chip
		return null
	if DialogSystem.is_open:
		return null
	return _nearest_npc()


func _process(_delta: float) -> void:
	if tour_banner and is_instance_valid(tour_banner) and tour_pointer:
		tour_banner.set_avoid(tour_pointer.world_target_rect())


func _on_tour_dialog(open: bool) -> void:
	if tour_banner and is_instance_valid(tour_banner):
		tour_banner.set_suppressed(open)


func _tour_talk() -> Signal:
	conversation.started.connect(_on_tour_conversation)
	return _tour_talked


func _on_tour_conversation(npc_id: String) -> void:
	if npc_id == "fire":
		return
	conversation.started.disconnect(_on_tour_conversation)
	_tour_talked.emit()


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
	Sfx.play(&"victory")
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
			if TrainingState.tour_mode:
				TrainingState.mark_completed()
				TrainingState.tour_mode = false
				TrainingState.direct_start = true
			_leave(HORDE_PATH)
		"title":
			TrainingState.tour_mode = false
			_leave(TITLE_PATH)
		"journal":
			var tracker := get_node_or_null("/root/ProgressTracker")
			if tracker and tracker.has_method("show_journal"):
				tracker.show_journal()


## Leaving the tour camp any way at all (fire, pause -> Main Menu, Load) ends
## the tour. Only the camp that ran it may clear the flag.
func _free_level() -> void:
	if tour_coach != null:
		TrainingState.tour_mode = false
		if _tour_dialog_open.is_valid() and DialogSystem.opened.is_connected(_tour_dialog_open):
			DialogSystem.opened.disconnect(_tour_dialog_open)
		if _tour_dialog_closed.is_valid() and DialogSystem.closed.is_connected(_tour_dialog_closed):
			DialogSystem.closed.disconnect(_tour_dialog_closed)
		if tour_pointer:
			tour_pointer.clear()
	super()


func _leave(level_path: String) -> void:
	if _navigating:
		return
	_navigating = true
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(level_path, "", Vector2.ZERO)
