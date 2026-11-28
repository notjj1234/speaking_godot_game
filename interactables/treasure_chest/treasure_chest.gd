@tool
class_name TreasureChest extends Node2D

@export var item_data: ItemData: set = _set_item_data
@export var quantity: int = 1 : set = _set_quantity

var is_open: bool = false

@onready var sprite: Sprite2D = $ItemSprite
@onready var label: Label = $ItemSprite/Label
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var interact_area: Area2D = $Area2D
@onready var is_open_data: PersistentDataHandler = $IsOpen


func _ready() -> void:
	_update_texture()
	_update_label()
	if Engine.is_editor_hint():
		return
	interact_area.area_entered.connect(_on_area_enter)
	interact_area.area_exited.connect(_on_area_exit)
	is_open_data.data_loaded.connect(set_chest_state)
	set_chest_state()
	pass

func set_chest_state() -> void:
	is_open = is_open_data.value
	if is_open:
		animation_player.play("opened")
	else:
		animation_player.play("closed")

func player_interact() -> void:
	if is_open == true:
		return
	is_open = true
	_set_open_prompt(false)
	is_open_data.set_value()
	animation_player.play("open_chest")
	if item_data and quantity > 0:
		PlayerManager.INVENTORY_DATA.add_item(item_data, quantity)
		Sfx.play(&"purchase")
	else:
		printerr("No Items in Chest")
		push_error("No Items in Chest")
	

func _on_area_enter(_a :Area2D) -> void:
	PlayerManager.interact_pressed.connect(player_interact)
	_set_open_prompt(not is_open)

func _on_area_exit(_a: Area2D) -> void:
	PlayerManager.interact_pressed.disconnect(player_interact)
	_set_open_prompt(false)


## Touch: the Interact button reads "Open" while a closed chest is in reach.
var _prompting := false

func _set_open_prompt(on: bool) -> void:
	if on == _prompting:
		return
	_prompting = on
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("set_talk_prompt"):
			node.set_talk_prompt(on, "Open")

func _set_item_data(value: ItemData) -> void:
	item_data = value
	_update_texture()
	
func _set_quantity(value: int) -> void:
	quantity = value
	_update_label()
	
func _update_texture() -> void:
	if item_data and sprite:
		sprite.texture = item_data.texture

func _update_label() -> void:
	if label:
		if quantity < 1:
			label.text = ""
		else:
			label.text = "x" + str(quantity)
