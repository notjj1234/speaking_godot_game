class_name InventoryUI extends Control

const INVENTORY_SLOT = preload("res://gui/pause_menu/inventory/inventory_slot.tscn")

var focus_index: int = 0

@export var data: InventoryData

@onready var pause_menu: CanvasLayer = $"../../.."

func _ready() -> void:
	PauseMenu.shown.connect(update_inventory)
	PauseMenu.hidden.connect(clear_inventory)
	clear_inventory()
	data.changed.connect(on_inventory_changed)

func clear_inventory() -> void:
	for c in get_children():
		c.queue_free()

func update_inventory(i: int = 0) -> void:
	for s in data.slots:
		var new_slot = INVENTORY_SLOT.instantiate()
		add_child(new_slot)
		new_slot.slot_data = s

		# Ensure touch and focus events work for each slot
		new_slot.focus_entered.connect(item_focused)

	await get_tree().process_frame
	get_child(i).grab_focus()

func item_focused() -> void:
	for i in range(get_child_count()):
		if get_child(i).has_focus():
			focus_index = i
			return

func on_inventory_changed() -> void:
	var i = focus_index
	clear_inventory()
	update_inventory(i)
