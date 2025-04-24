# level_03_logic.gd

extends Node

@onready var treasure_chest := get_parent().get_node("TreasureChest")
@onready var tutorial_dialog := get_node_or_null("../PlayerHud/TutorialDialog")

func _ready():
	print("📦 Level 03 logic initialized.")
	if treasure_chest:
		treasure_chest.visible = false
	else:
		print("❌ TreasureChest node not found!")

	await wait_until_all_goblins_defeated()
	reveal_chest()

func wait_until_all_goblins_defeated() -> void:
	print("👀 Waiting for goblins to be defeated...")
	while true:
		await get_tree().process_frame
		if not any_goblins_left():
			print("✅ All goblins defeated.")
			break
		await get_tree().create_timer(0.5).timeout

func any_goblins_left() -> bool:
	var goblins_node = get_parent().get_node_or_null("GoblinsContainer")
	if goblins_node == null:
		print("❌ Goblins node not found.")
		return false

	var goblin_count := 0
	for child in goblins_node.get_children():
		if child.name.begins_with("Goblin"):
			if child.is_queued_for_deletion() or child.get_meta("queued_for_removal", false):
				continue
			goblin_count += 1
	print("🟡 Goblins remaining (not queued for deletion):", goblin_count)
	return goblin_count > 0

func reveal_chest():
	if treasure_chest:
		print("🎉 Revealing treasure chest!")
		treasure_chest.visible = true
		if treasure_chest.has_node("AnimationPlayer"):
			print("▶️ Playing 'reveal' animation.")
			treasure_chest.get_node("AnimationPlayer").play("reveal")
		else:
			print("⚠️ No AnimationPlayer found on the treasure chest.")

		if tutorial_dialog:
			tutorial_dialog.show_custom_message("Congrats, you killed the goblin!\nUse the Interact button to open the chest.")
		else:
			print("⚠️ TutorialDialog not found.")
	else:
		print("❌ TreasureChest reference is invalid.")
