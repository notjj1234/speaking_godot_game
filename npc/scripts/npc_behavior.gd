@icon("res://npc/icons/npc_behavior.svg")

class_name NPCBehavior extends Node2D

var npc: NPC

func _ready() -> void:
	var p = get_parent()
	if p is NPC:
		npc = p as NPC
		# connect to signal
		npc.do_behavior_enabled.connect(start)


func start() -> void:
	pass
