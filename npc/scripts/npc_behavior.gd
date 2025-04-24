@icon("res://npc/icons/npc_behavior.svg")

class_name NPCBehavior extends Node

var npc: NPC

func _ready() -> void:
	var p = get_parent()
	if p is NPC:
		npc = p as NPC
		# connec to signal
