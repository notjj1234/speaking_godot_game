extends Node2D
## Camp level regressions. Run headless on a scratch copy only (the camp saves
## to user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_camp_scene.tscn

const CAMP := "res://levels/endless_horde/camp/camp.tscn"
const GEM := "res://items/gem.tres"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _find_npcs(root: Node) -> Array[NPC]:
	var out: Array[NPC] = []
	for node in root.find_children("*", "NPC", true, false):
		var npc := node as NPC
		if npc and npc.npc_resource and npc.npc_resource.conversation_id != "":
			out.append(npc)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var saved_provider: SttProvider = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	var saved_inv: Array = PlayerManager.INVENTORY_DATA.get_save_data()
	var saved_points := PlayerManager.bonfire_points

	PlayerManager.INVENTORY_DATA.parse_save_data([])
	PlayerManager.bonfire_points = 0
	PlayerManager.INVENTORY_DATA.add_item(load(GEM), 5)
	PlayerManager.set_health(3, PlayerManager.horde_max_hp())
	PlayerManager.player.make_invulnerable(30.0)

	var packed := load(CAMP) as PackedScene
	_check("camp scene loads", packed != null)
	if packed == null:
		_finish(saved_provider, fake, saved_inv, saved_points)
		return
	var camp := packed.instantiate()
	add_child(camp)
	await get_tree().process_frame

	_check("camp root is Camp", camp.name == "Camp" and camp is Level, camp.name)
	_check("gems became points", PlayerManager.bonfire_points == 5, "points %d" % PlayerManager.bonfire_points)
	_check("gem stack emptied", PlayerManager.item_count(GEM) == 0, "gems %d" % PlayerManager.item_count(GEM))
	_check("full heal", PlayerManager.player.hp == PlayerManager.horde_max_hp(),
		"hp %d/%d" % [PlayerManager.player.hp, PlayerManager.horde_max_hp()])
	await _wait(1.4)
	_check("death invulnerability cleared", not PlayerManager.player.invulnerable)

	var npcs := _find_npcs(camp)
	_check("three talking NPCs", npcs.size() == 3, "found %d" % npcs.size())
	_check("one conversation controller", get_tree().get_nodes_in_group("camp_conversation").size() == 1)
	var conv: CampConversation = get_tree().get_first_node_in_group("camp_conversation")
	var smith: NPC = null
	for npc in npcs:
		if npc.npc_resource.conversation_id == "smith":
			smith = npc
	_check("smith present", smith != null)
	if smith and conv:
		smith.player_interact()
		await get_tree().process_frame
		_check("smith opens a conversation", DialogSystem.is_conversation())
		_check("smith stops wandering while talking", not smith.do_behavior)
		conv.leave()
		await get_tree().process_frame
		_check("smith wanders again after leaving", smith.do_behavior)
	_check("fire present", camp.find_child("CampFire", true, false) != null)

	camp.queue_free()
	await get_tree().process_frame
	_finish(saved_provider, fake, saved_inv, saved_points)


func _finish(saved_provider: SttProvider, fake, saved_inv: Array, saved_points: int) -> void:
	STTManager.provider = saved_provider
	fake.free()
	PlayerManager.INVENTORY_DATA.parse_save_data(saved_inv)
	PlayerManager.bonfire_points = saved_points
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
