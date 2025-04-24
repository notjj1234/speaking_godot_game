class_name InventorySlotUI extends Button

var slot_data: SlotData : set = set_slot_data

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label
@onready var selection_rect: ColorRect = $SelectionRect if has_node("SelectionRect") else null

func _ready() -> void:
	texture_rect.texture = null
	label.text = ""

	# Connect Button signals to methods
	connect("focus_entered", Callable(self, "_on_item_focused"))
	connect("focus_exited", Callable(self, "_on_item_unfocused"))
	connect("pressed", Callable(self, "_on_item_pressed"))

	# Ensure GUI input is handled for touch interactions
	connect("gui_input", Callable(self, "_on_gui_input"))

func set_slot_data(value: SlotData) -> void:
	slot_data = value
	if slot_data == null:
		texture_rect.texture = null
		label.text = ""
		return

	texture_rect.texture = slot_data.item_data.texture
	label.text = str(slot_data.quantity)

func _on_item_focused() -> void:
	# Check if selection_rect exists before trying to modify it
	if selection_rect:
		selection_rect.visible = true

	if slot_data != null and slot_data.item_data != null:
		PauseMenu.update_item_description(slot_data.item_data.description)

func _on_item_unfocused() -> void:
	# Check if selection_rect exists before trying to modify it
	if selection_rect:
		selection_rect.visible = false

	PauseMenu.update_item_description("")

func _on_item_pressed() -> void:
	if slot_data:
		if slot_data.item_data:
			var was_used = slot_data.item_data.use()
			if was_used == false:
				return
			slot_data.quantity -= 1
			label.text = str(slot_data.quantity)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		grab_focus()
		_on_item_focused()
		_on_item_pressed()
	elif event is InputEventMouseButton and event.pressed:
		grab_focus()
		_on_item_focused()
		_on_item_pressed()
