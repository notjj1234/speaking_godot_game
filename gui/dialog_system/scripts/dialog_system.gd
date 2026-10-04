@tool
@icon("res://gui/dialog_system/icons/star_bubble.svg")
class_name DialogSystemNode extends CanvasLayer

const FALLBACK_DIALOG_HEIGHT := 96.0
const TALK_FRAME_TIME := 0.15

var is_open: bool = false
var _lines: PackedStringArray = PackedStringArray()
var _index: int = 0
var _on_finished: Callable = Callable()
var _portrait_hframes: int = 1
var _talk_timer: Timer = null
var _pending_portrait: Texture = null
var _fit_token: int = 0

@onready var name_label: Label = $DialogUI/DialogBar/ContentColumn/NameLabel
@onready var content_column: Control = $DialogUI/DialogBar/ContentColumn
@onready var text_panel: Control = $DialogUI/DialogBar/ContentColumn/PanelContainer
@onready var portrait_slot: Control = $DialogUI/DialogBar/PortraitSlot
@onready var portrait_sprite: Sprite2D = $DialogUI/DialogBar/PortraitSlot/PortraitSprite
@onready var text_label: RichTextLabel = $DialogUI/DialogBar/ContentColumn/PanelContainer/RichTextLabel


func _ready() -> void:
	if Engine.is_editor_hint():
		visible = false
		return
	visible = false
	is_open = false
	PlayerManager.dialog_open = false
	_talk_timer = Timer.new()
	_talk_timer.wait_time = TALK_FRAME_TIME
	_talk_timer.one_shot = false
	_talk_timer.timeout.connect(_on_talk_frame)
	add_child(_talk_timer)
	if portrait_slot:
		portrait_slot.visible = false


func show_dialog(speaker: String, portrait: Texture, lines: PackedStringArray, on_finished: Callable = Callable(), portrait_hframes: int = 4) -> void:
	if Engine.is_editor_hint():
		return
	if lines.is_empty():
		lines = PackedStringArray(["..."])
	_lines = lines
	_index = 0
	_on_finished = on_finished
	is_open = true
	PlayerManager.dialog_open = true
	visible = true
	if name_label:
		name_label.text = speaker
	_pending_portrait = portrait
	_portrait_hframes = maxi(portrait_hframes, 1)
	_show_current_line()
	_fit_portrait_to_textbox()


func close() -> void:
	if not is_open:
		return
	is_open = false
	PlayerManager.dialog_open = false
	visible = false
	_stop_talk_anim()
	_pending_portrait = null
	if portrait_slot:
		portrait_slot.visible = false
	var callback := _on_finished
	_on_finished = Callable()
	if callback.is_valid():
		callback.call()


func _fit_portrait_to_textbox() -> void:
	_fit_token += 1
	var token := _fit_token
	# Wait until Control layout finishes so text_panel.size is real.
	await get_tree().process_frame
	if token != _fit_token or not is_open:
		return
	await get_tree().process_frame
	if token != _fit_token or not is_open:
		return
	_apply_portrait_size()


func _apply_portrait_size() -> void:
	if portrait_slot == null or portrait_sprite == null:
		return
	var portrait := _pending_portrait
	if portrait == null:
		portrait_slot.visible = false
		_stop_talk_anim()
		return

	var target_h := FALLBACK_DIALOG_HEIGHT
	if content_column != null and content_column.size.y > 1.0:
		target_h = content_column.size.y
	elif text_panel != null:
		var name_h := 0.0
		if name_label != null:
			name_h = name_label.size.y
		target_h = name_h + text_panel.size.y + 4.0

	# Slot is a square matching name + bubble height.
	portrait_slot.custom_minimum_size = Vector2(target_h, target_h)
	portrait_slot.size = Vector2(target_h, target_h)

	_portrait_hframes = maxi(_portrait_hframes, 1)
	portrait_sprite.texture = portrait
	portrait_sprite.hframes = _portrait_hframes
	portrait_sprite.vframes = 1
	portrait_sprite.frame = 0
	portrait_sprite.centered = true
	portrait_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var frame_w: float = float(portrait.get_width()) / float(_portrait_hframes)
	var frame_h: float = float(portrait.get_height())
	if frame_w > 0.0 and frame_h > 0.0:
		# Stretch independently so the sprite fills the slot with no side gaps.
		portrait_sprite.scale = Vector2(target_h / frame_w, target_h / frame_h)
	else:
		portrait_sprite.scale = Vector2.ONE

	portrait_sprite.position = Vector2(target_h * 0.5, target_h * 0.5)
	portrait_slot.visible = true
	print("✅ Dialog portrait fitted to name+bubble height: ", target_h)

	if _portrait_hframes > 1:
		_talk_timer.start()
	else:
		_stop_talk_anim()


func _on_talk_frame() -> void:
	if not is_open or portrait_sprite == null or _portrait_hframes <= 1:
		return
	portrait_sprite.frame = (portrait_sprite.frame + 1) % _portrait_hframes


func _stop_talk_anim() -> void:
	if _talk_timer:
		_talk_timer.stop()
	if portrait_sprite:
		portrait_sprite.frame = 0


func _show_current_line() -> void:
	if text_label == null:
		return
	if _index >= 0 and _index < _lines.size():
		text_label.text = _lines[_index]
	else:
		text_label.text = ""
	if is_open and _portrait_hframes > 1 and _talk_timer and _talk_timer.is_stopped():
		_talk_timer.start()
		if portrait_sprite:
			portrait_sprite.frame = 0


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		close()
	else:
		_show_current_line()
		_fit_portrait_to_textbox()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_open or not visible:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_advance()
		get_viewport().set_input_as_handled()
