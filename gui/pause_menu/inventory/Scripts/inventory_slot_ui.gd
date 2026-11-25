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
	# A slot created while the pause menu is open joins its input layer.
	if PauseMenu.input_layer != 0:
		route(PauseMenu.input_layer)

func route(layer: int) -> void:
	UiInputRouter.bind(self, _on_item_tapped, layer)

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

func _on_item_tapped() -> void:
	grab_focus()
	_on_item_pressed()
