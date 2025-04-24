extends Node2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false
	if PlayerManager.player_spawned == false:
		PlayerManager.set_player_position(global_position)
		PlayerManager.player_spawned = true

	# Assign PlayerHud to the player
	var player_hud = get_tree().root.get_node("PlayerHud") as PlayerHudUI  # Cast explicitly to PlayerHudUI
	PlayerManager.player.player_hud = player_hud

	# Add a debug message to confirm player spawn
	print("Player spawned at position: ", global_position)
