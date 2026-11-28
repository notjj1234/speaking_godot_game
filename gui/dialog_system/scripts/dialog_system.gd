@tool
@icon("res://gui/dialog_system/icons/star_bubble.svg")
class_name DialogSystemNode extends CanvasLayer

## The Say-it box's Cancel was pressed: the tapped option is dropped.
signal say_cancelled

const FALLBACK_DIALOG_HEIGHT := 96.0
const TALK_FRAME_TIME := 0.15
## Same parchment as the battle challenge card (player_hud.tscn StyleBoxFlat_challenge).
const SAY_BG := Color(0.98, 0.96, 0.9, 1)
const SAY_INK := Color(0.2, 0.14, 0.05, 1)
const SAY_MISS := Color(0.55, 0.16, 0.08, 1)
const SAY_GAP_ABOVE_BAR := 8.0

var is_open: bool = false
var _lines: PackedStringArray = PackedStringArray()
var _index: int = 0
var _on_finished: Callable = Callable()
var _portrait_hframes: int = 1
var _talk_timer: Timer = null
var _pending_portrait: Texture = null
var _fit_token: int = 0
var _input_layer: int = 0
var _conversation_mode: bool = false
var _on_choice: Callable = Callable()

## Conversation-mode controls, built in code under ContentColumn.
var heard_label: Label = null
var listening_label: Label = null
var choice_row: HFlowContainer = null
var leave_button: Button = null
## Say-it box: opens when an option is tapped in voice mode, shows what to say.
var say_box: PanelContainer = null
var say_title_label: Label = null
var say_phrase_label: Label = null
var say_status_label: Label = null
var say_feedback_label: Label = null
var say_cancel_button: Button = null
var _say_center: CenterContainer = null
var _say_phrase := ""
var _say_listening := false
## The listen ping plays once per prompt (new line, box opened, a miss), not on
## the silent re-listens web STT does on its own.
var _listen_armed := false

@onready var name_label: Label = $DialogUI/DialogBar/ContentColumn/NameLabel
@onready var dialog_bar: Control = $DialogUI/DialogBar
@onready var content_column: Control = $DialogUI/DialogBar/ContentColumn
@onready var text_panel: Control = $DialogUI/DialogBar/ContentColumn/PanelContainer
@onready var portrait_slot: Control = $DialogUI/DialogBar/PortraitSlot
@onready var portrait_sprite: Sprite2D = $DialogUI/DialogBar/PortraitSlot/PortraitSprite
@onready var text_label: RichTextLabel = $DialogUI/DialogBar/ContentColumn/PanelContainer/RichTextLabel
@onready var continue_hint: Label = $DialogUI/DialogBar/ContentColumn/ContinueHint


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
	_build_conversation_controls()


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
	# Reading dialog shouldn't be a combat hazard: freeze enemies for the
	# duration. Player movement is already gated by dialog_open.
	_set_enemies_frozen(true)
	visible = true
	if _input_layer == 0:
		_input_layer = UiInputRouter.push_layer(&"dialog", self)
		UiInputRouter.bind(dialog_bar, _advance, _input_layer)
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
	_set_enemies_frozen(false)
	visible = false
	UiInputRouter.pop_layer(_input_layer)
	_input_layer = 0
	_clear_conversation()
	_stop_talk_anim()
	_pending_portrait = null
	if portrait_slot:
		portrait_slot.visible = false
	var callback := _on_finished
	_on_finished = Callable()
	if callback.is_valid():
		callback.call()


## Opens the dialog for a spoken back-and-forth: lines are pushed with
## set_conversation_line, taps go to choice chips, and Leave / Esc call close(),
## which runs `on_leave`.
func show_conversation(speaker: String, portrait: Texture, portrait_hframes: int, on_leave: Callable) -> void:
	if Engine.is_editor_hint():
		return
	if is_open:
		close()
	_lines = PackedStringArray([""])
	_index = 0
	_on_finished = on_leave
	_conversation_mode = true
	is_open = true
	PlayerManager.dialog_open = true
	_set_enemies_frozen(true)
	visible = true
	_input_layer = UiInputRouter.push_layer(&"dialog", self)
	if leave_button:
		leave_button.visible = true
		UiInputRouter.bind_button(leave_button, close, _input_layer)
	if say_cancel_button:
		UiInputRouter.bind_button(say_cancel_button, _on_say_cancel, _input_layer)
	if continue_hint:
		continue_hint.visible = false
	if name_label:
		name_label.text = speaker
	_pending_portrait = portrait
	_portrait_hframes = maxi(portrait_hframes, 1)
	_show_current_line()
	_fit_portrait_to_textbox()


func is_conversation() -> bool:
	return _conversation_mode


func set_conversation_line(text: String) -> void:
	if not _conversation_mode:
		return
	_lines = PackedStringArray([text])
	_index = 0
	_show_current_line()
	_arm_listen_ping()


func set_heard(text: String) -> void:
	if heard_label == null:
		return
	heard_label.text = 'Heard: "%s"' % text if text != "" else ""
	heard_label.visible = text != ""
	_refresh_say_status()


func set_listening(on: bool) -> void:
	_say_listening = on and _conversation_mode
	if _say_listening and _listen_armed:
		_play_listen_ping()
	if listening_label:
		listening_label.visible = on and _conversation_mode
	_refresh_say_status()


## Opens (or retargets) the Say-it box for a tapped option.
func show_say_box(letter: String, phrase: String) -> void:
	if say_box == null or not _conversation_mode:
		return
	_say_phrase = phrase
	say_title_label.text = "%s - say it:" % letter
	say_phrase_label.text = phrase
	set_say_feedback("")
	_place_say_box()
	_say_center.visible = true
	_refresh_say_status()
	_arm_listen_ping()


func hide_say_box() -> void:
	_say_phrase = ""
	if _say_center:
		_say_center.visible = false


func is_say_box_open() -> bool:
	return _say_center != null and _say_center.visible


func say_phrase() -> String:
	return _say_phrase


func set_say_feedback(text: String) -> void:
	if say_feedback_label == null:
		return
	say_feedback_label.text = text
	say_feedback_label.visible = text != ""
	if text != "":
		_arm_listen_ping()


func _arm_listen_ping() -> void:
	_listen_armed = true
	if _say_listening:
		_play_listen_ping()


func _play_listen_ping() -> void:
	_listen_armed = false
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(&"listen")


func _on_say_cancel() -> void:
	hide_say_box()
	say_cancelled.emit()


func _refresh_say_status() -> void:
	if say_status_label == null:
		return
	if heard_label and heard_label.visible:
		say_status_label.text = heard_label.text
	elif _say_listening:
		say_status_label.text = "Listening..."
	else:
		say_status_label.text = ""
	say_status_label.visible = say_status_label.text != ""


## Keeps the card centred in the space above the dialog bar.
func _place_say_box() -> void:
	if _say_center == null or dialog_bar == null:
		return
	var view_h := get_viewport().get_visible_rect().size.y
	_say_center.offset_bottom = -maxf(view_h - dialog_bar.global_position.y + SAY_GAP_ABOVE_BAR, 0.0)


## choices: Array of {"id": String, "label": String}. Empty hides the row.
func set_choices(choices: Array, on_choice: Callable) -> void:
	if choice_row == null:
		return
	_clear_choice_buttons()
	_on_choice = on_choice
	for choice in choices:
		var id := str(choice.get("id", ""))
		var btn := _make_button(str(choice.get("label", id)))
		choice_row.add_child(btn)
		if _input_layer != 0:
			UiInputRouter.bind_button(btn, _pick_choice.bind(id), _input_layer)
	choice_row.visible = not choices.is_empty() and _conversation_mode


func _pick_choice(id: String) -> void:
	if _on_choice.is_valid():
		_on_choice.call(id)


func _clear_choice_buttons() -> void:
	if choice_row == null:
		return
	for child in choice_row.get_children():
		UiInputRouter.unbind(child)
		choice_row.remove_child(child)
		child.queue_free()
	choice_row.visible = false


func _clear_conversation() -> void:
	hide_say_box()
	_say_listening = false
	_listen_armed = false
	_conversation_mode = false
	_on_choice = Callable()
	_clear_choice_buttons()
	set_heard("")
	if listening_label:
		listening_label.visible = false
	if leave_button:
		leave_button.visible = false
	if continue_hint:
		continue_hint.visible = true


func _build_conversation_controls() -> void:
	if content_column == null:
		return
	choice_row = HFlowContainer.new()
	choice_row.name = "ChoiceRow"
	choice_row.add_theme_constant_override("h_separation", 6)
	choice_row.add_theme_constant_override("v_separation", 4)
	choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_row.visible = false
	content_column.add_child(choice_row)

	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.add_theme_constant_override("separation", 8)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_column.add_child(status_row)

	listening_label = _make_status_label("Listening...")
	listening_label.name = "ListeningLabel"
	status_row.add_child(listening_label)
	heard_label = _make_status_label("")
	heard_label.name = "HeardLabel"
	heard_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heard_label.clip_text = true
	heard_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(heard_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(spacer)
	leave_button = _make_button("Leave")
	leave_button.name = "LeaveButton"
	status_row.add_child(leave_button)
	_build_say_box()
	_clear_conversation()


func _build_say_box() -> void:
	var ui := get_node_or_null("DialogUI") as Control
	if ui == null:
		return
	_say_center = CenterContainer.new()
	_say_center.name = "SayCenter"
	_say_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_say_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_center.visible = false
	ui.add_child(_say_center)

	say_box = PanelContainer.new()
	say_box.name = "SayBox"
	say_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	say_box.custom_minimum_size = Vector2(260, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = SAY_BG
	style.border_color = SAY_INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	say_box.add_theme_stylebox_override("panel", style)
	_say_center.add_child(say_box)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	say_box.add_child(column)
	say_title_label = _make_say_label(14, SAY_INK)
	column.add_child(say_title_label)
	say_phrase_label = _make_say_label(24, SAY_INK)
	column.add_child(say_phrase_label)
	say_status_label = _make_say_label(12, SAY_INK)
	column.add_child(say_status_label)
	say_feedback_label = _make_say_label(12, SAY_MISS)
	column.add_child(say_feedback_label)
	say_cancel_button = _make_button("Cancel")
	say_cancel_button.name = "SayCancelButton"
	say_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(say_cancel_button)


func _make_say_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text_label:
		label.add_theme_font_override("font", text_label.get_theme_font("normal_font"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_status_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text_label:
		label.add_theme_font_override("font", text_label.get_theme_font("normal_font"))
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.93, 0.88, 0.78, 1))
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 1))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	if text_label:
		btn.add_theme_font_override("font", text_label.get_theme_font("normal_font"))
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(64, 44)
	return btn


func _set_enemies_frozen(frozen: bool) -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if frozen:
			# Remember the mode so close() can restore non-default setups.
			enemy.set_meta("lq_prev_process_mode", enemy.process_mode)
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			enemy.process_mode = int(enemy.get_meta("lq_prev_process_mode", Node.PROCESS_MODE_INHERIT))


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
		# One scale keeps the pixel portrait from stretching to fill the slot.
		var fitted := minf(target_h / frame_w, target_h / frame_h)
		portrait_sprite.scale = Vector2(fitted, fitted)
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


## Keyboard only. Taps on the dialog bar arrive through UiInputRouter.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_open or not visible:
		return
	if _conversation_mode:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_advance()
		get_viewport().set_input_as_handled()
