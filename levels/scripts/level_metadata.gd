# level_metadata.gd
# Metadata resource for levels to define touch/voice control behavior

class_name LevelMetadata extends Resource

@export var level_name: String = ""
@export var disable_movement_arrows: bool = false
@export var disable_mic_button: bool = false
@export var disable_interact_button: bool = false
@export var disable_attack_button: bool = false
@export var force_voice_only: bool = false
@export var struggle_unlock_count: int = 3
@export var custom_voice_commands: Array[String] = []

func _init() -> void:
	pass

static func get_for_level(level_node: Node) -> LevelMetadata:
	if level_node == null:
		return null
	
	# Check for LevelMetadata resource on the level root
	if level_node.has_meta("level_metadata"):
		return level_node.get_meta("level_metadata")
	
	# Check for child node with LevelMetadata
	for child in level_node.get_children():
		if child is LevelMetadata:
			return child
		if child.has_meta("level_metadata"):
			return child.get_meta("level_metadata")
	
	return null

static func apply_to_touch_controls(touch_controls: Node, metadata: LevelMetadata) -> void:
	if metadata == null or touch_controls == null:
		return
	
	if metadata.disable_movement_arrows and touch_controls.has_method("_disable_arrow_buttons"):
		touch_controls._disable_arrow_buttons()
	
	if metadata.disable_mic_button and touch_controls.has_method("_disable_mic_button"):
		touch_controls._disable_mic_button()
	
	if metadata.disable_interact_button and touch_controls.has_method("_disable_interact_button"):
		touch_controls._disable_interact_button()
	
	if metadata.disable_attack_button and touch_controls.has_method("_disable_attack_button"):
		touch_controls._disable_attack_button()
	
	if metadata.force_voice_only and touch_controls.has_method("begin_voice_only_mode"):
		touch_controls.begin_voice_only_mode()
	
	if metadata.struggle_unlock_count > 0 and touch_controls.has_method("set_struggle_unlock_count"):
		touch_controls.set_struggle_unlock_count(metadata.struggle_unlock_count)
	
	if metadata.custom_voice_commands.size() > 0 and touch_controls.has_method("set_custom_voice_commands"):
		touch_controls.set_custom_voice_commands(metadata.custom_voice_commands)