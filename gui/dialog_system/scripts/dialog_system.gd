@tool
@icon("res://gui/dialog_system/icons/star_bubble.svg")
class_name DialogSystemNode extends CanvasLayer

## The Say-it box's Cancel was pressed: the tapped option is dropped.
signal say_cancelled
## Any dialog (lines or conversation) opened / closed: other overlays step aside.
signal opened
signal closed
## Say-it box tools (the camp's own; the HUD battle card never opens here).
signal say_listen_pressed
signal say_speak_pressed
signal say_typed_submitted(text: String)
## A pick-the-word tile in the Say-it box was tapped (players' no-keyboard help).
signal say_tile_picked(text: String)

const FALLBACK_DIALOG_HEIGHT := 96.0
const TALK_FRAME_TIME := 0.15
## Same parchment as the battle challenge card (player_hud.tscn StyleBoxFlat_challenge).
const SAY_BG := Color(0.98, 0.96, 0.9, 1)
const SAY_INK := Color(0.2, 0.14, 0.05, 1)
const SAY_MISS := Color(0.55, 0.16, 0.08, 1)
const SAY_GAP_ABOVE_BAR := 8.0
## The portrait card is a square as tall as the text box, within these bounds.
const PORTRAIT_MIN := 64.0
const PORTRAIT_MAX := 112.0
const PORTRAIT_GAP := 8.0
## The bar is a centred column: full width on phones, capped on wide screens.
const BAR_MAX_W := 600.0
const BAR_MARGIN := 12.0
## Choice / tool chips: parchment with an ink border.
const CHIP_HOVER := Color(0.93, 0.89, 0.8, 1)
const CHIP_PRESSED := Color(0.85, 0.79, 0.66, 1)
const TOAST_GOOD := Color(0.1, 0.42, 0.16, 1)
const TOAST_HOLD_SEC := 1.6

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
var say_listen_button: Button = null
var say_speak_button: Button = null
var say_tools_row: HBoxContainer = null
var say_typed_row: HBoxContainer = null
var say_typed_input: LineEdit = null
var say_submit_button: Button = null
var say_tiles_row: HFlowContainer = null
var _say_center: CenterContainer = null
var _toast: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _say_phrase := ""
var _say_listening := false
## The listen ping plays once per prompt (new line, box opened, a miss), not on
## the silent re-listens web STT does on its own.
var _listen_armed := false

@onready var name_label: Label = $DialogUI/DialogBar/NameRow/NameLabel
@onready var dialog_bar: Control = $DialogUI/DialogBar
@onready var content_column: Control = $DialogUI/DialogBar/Footer/ContentColumn
@onready var text_panel: Control = $DialogUI/DialogBar/Row/PanelContainer
@onready var portrait_slot: Control = $DialogUI/DialogBar/Row/PortraitSlot
@onready var portrait_sprite: Sprite2D = $DialogUI/DialogBar/Row/PortraitSlot/PortraitSprite
@onready var text_label: RichTextLabel = $DialogUI/DialogBar/Row/PanelContainer/RichTextLabel
@onready var continue_hint: Label = $DialogUI/DialogBar/Footer/ContentColumn/ContinueHint
@onready var name_indent: Control = $DialogUI/DialogBar/NameRow/NameIndent
@onready var footer_indent: Control = $DialogUI/DialogBar/Footer/FooterIndent


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
		portrait_slot.add_theme_stylebox_override("panel", parchment_style(3, 6, 2))
	_set_indent(0.0)
	_build_conversation_controls()
	get_viewport().size_changed.connect(_layout_bar)
	_layout_bar()


## Parchment card style shared by the portrait frame, chips and the Say-it box.
static func parchment_style(border: int, radius: int, margin: int, bg: Color = SAY_BG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = SAY_INK
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


## Where the bar goes on a view of this size: bottom-centred, BAR_MARGIN from
## the edges, at most BAR_MAX_W wide.
func bar_rect_for(view: Vector2) -> Rect2:
	var w := minf(view.x - BAR_MARGIN * 2.0, BAR_MAX_W)
	var h := dialog_bar.get_combined_minimum_size().y if dialog_bar else 0.0
	return Rect2(Vector2((view.x - w) * 0.5, view.y - BAR_MARGIN - h), Vector2(w, h))


func _layout_bar() -> void:
	if dialog_bar == null or not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var r := bar_rect_for(view)
	dialog_bar.offset_left = r.position.x
	dialog_bar.offset_right = -(view.x - r.end.x)
	dialog_bar.offset_bottom = -BAR_MARGIN
	dialog_bar.offset_top = -BAR_MARGIN - 1.0
	_place_say_box()


## A short result line over the dialog bar ("Bought! -2 gems" / "Need 4 gems
## - you have 2"): pops in when good, shakes when not, fades by itself.
func show_toast(text: String, good: bool) -> void:
	if _toast == null:
		_build_toast()
	if _toast == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", TOAST_GOOD if good else SAY_MISS)
	if _toast_tween:
		_toast_tween.kill()
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast.reset_size()
	var bar := dialog_bar.get_global_rect() if dialog_bar else Rect2(0, 400, 640, 0)
	_toast.position = Vector2(bar.get_center().x - _toast.size.x * 0.5, bar.position.y - _toast.size.y - 6.0)
	_toast.pivot_offset = _toast.size * 0.5
	var x := _toast.position.x
	_toast_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if good:
		_toast.scale = Vector2(0.7, 0.7)
		_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_toast.scale = Vector2.ONE
		for dx in [-6.0, 6.0, -4.0, 4.0, 0.0]:
			_toast_tween.tween_property(_toast, "position:x", x + dx, 0.05)
	_toast_tween.tween_interval(TOAST_HOLD_SEC)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func(): _toast.visible = false)


func toast_text() -> String:
	return _toast_label.text if _toast and _toast.visible else ""


func _build_toast() -> void:
	var ui := get_node_or_null("DialogUI") as Control
	if ui == null:
		return
	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := parchment_style(3, 8, 8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 4
	_toast.add_theme_stylebox_override("panel", style)
	_toast_label = _make_say_label(16, SAY_INK)
	_toast.add_child(_toast_label)
	_toast.visible = false
	ui.add_child(_toast)


## Name, choices and status line start where the text box starts.
func _set_indent(width: float) -> void:
	if name_indent:
		name_indent.custom_minimum_size.x = width
	if footer_indent:
		footer_indent.custom_minimum_size.x = width


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
	opened.emit()
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
	_layout_bar()
	_fit_portrait_to_textbox()


func close() -> void:
	if not is_open:
		return
	is_open = false
	PlayerManager.dialog_open = false
	closed.emit()
	_set_enemies_frozen(false)
	visible = false
	UiInputRouter.pop_layer(_input_layer)
	_input_layer = 0
	_clear_conversation()
	_stop_talk_anim()
	_pending_portrait = null
	if portrait_slot:
		portrait_slot.visible = false
	_set_indent(0.0)
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
	opened.emit()
	_set_enemies_frozen(true)
	visible = true
	_input_layer = UiInputRouter.push_layer(&"dialog", self)
	if leave_button:
		leave_button.visible = true
		UiInputRouter.bind_button(leave_button, close, _input_layer)
		_dock_leave()
		if choice_row:
			choice_row.visible = true
	if say_cancel_button:
		UiInputRouter.bind_button(say_cancel_button, _on_say_cancel, _input_layer)
	if say_listen_button:
		UiInputRouter.bind_button(say_listen_button, _on_say_listen, _input_layer)
	if say_speak_button:
		UiInputRouter.bind_button(say_speak_button, _on_say_speak, _input_layer)
	if say_submit_button:
		UiInputRouter.bind_button(say_submit_button, _on_say_submit, _input_layer)
	if continue_hint:
		continue_hint.visible = false
	if name_label:
		name_label.text = speaker
	_pending_portrait = portrait
	_portrait_hframes = maxi(portrait_hframes, 1)
	_show_current_line()
	_layout_bar()
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
	say_title_label.text = ("%s - say it:" % letter) if letter != "" else "Say it:"
	say_phrase_label.text = phrase
	set_say_feedback("")
	_place_say_box()
	_say_center.visible = true
	_refresh_say_status()
	_arm_listen_ping()


func hide_say_box() -> void:
	_say_phrase = ""
	clear_say_tools()
	if _say_center:
		_say_center.visible = false


## Which helpers the open Say-it box offers: Listen (read the phrase aloud),
## Speak (start the mic again with a tap) and a typing row.
func set_say_tools(listen: bool, speak: bool, typed: bool) -> void:
	if say_tools_row == null:
		return
	say_listen_button.visible = listen
	say_speak_button.visible = speak
	say_tools_row.visible = listen or speak
	var was_typed := say_typed_row.visible
	say_typed_row.visible = typed
	if typed and not was_typed:
		say_typed_input.text = ""
	if not typed and say_typed_input.has_focus():
		say_typed_input.release_focus()


func clear_say_tools() -> void:
	set_say_tools(false, false, false)
	set_say_tiles([])


## Pick-the-word tiles under the phrase; an empty list hides them.
func set_say_tiles(options: Array) -> void:
	if say_tiles_row == null:
		return
	for child in say_tiles_row.get_children():
		UiInputRouter.unbind(child)
		say_tiles_row.remove_child(child)
		child.queue_free()
	for text in options:
		var btn := _make_button(str(text))
		say_tiles_row.add_child(btn)
		if _input_layer != 0:
			UiInputRouter.bind_button(btn, _on_say_tile.bind(str(text)), _input_layer)
	say_tiles_row.visible = not options.is_empty()


func say_tile_texts() -> Array:
	var out: Array = []
	if say_tiles_row:
		for child in say_tiles_row.get_children():
			if not child.is_queued_for_deletion():
				out.append((child as Button).text)
	return out


func say_tile_button(text: String) -> Button:
	if say_tiles_row:
		for child in say_tiles_row.get_children():
			if not child.is_queued_for_deletion() and (child as Button).text == text:
				return child
	return null


func _on_say_tile(text: String) -> void:
	if is_say_box_open():
		say_tile_picked.emit(text)


func _on_say_listen() -> void:
	if is_say_box_open():
		say_listen_pressed.emit()


func _on_say_speak() -> void:
	if is_say_box_open():
		say_speak_pressed.emit()


func _on_say_submit() -> void:
	if not is_say_box_open() or say_typed_input == null:
		return
	var text := say_typed_input.text.strip_edges()
	if text == "":
		return
	say_typed_input.text = ""
	say_typed_submitted.emit(text)


func _on_say_text_submitted(_text: String) -> void:
	_on_say_submit()


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
	_dock_leave()
	choice_row.visible = _conversation_mode


func _pick_choice(id: String) -> void:
	if _on_choice.is_valid():
		_on_choice.call(id)


func _clear_choice_buttons() -> void:
	if choice_row == null:
		return
	for child in choice_row.get_children():
		if child == leave_button:
			continue
		UiInputRouter.unbind(child)
		choice_row.remove_child(child)
		child.queue_free()
	choice_row.visible = false


## Leave rides at the end of the choice chips, not alone in a corner.
func _dock_leave() -> void:
	if leave_button == null or choice_row == null:
		return
	if leave_button.get_parent() != choice_row:
		leave_button.reparent(choice_row, false)
	choice_row.move_child(leave_button, choice_row.get_child_count() - 1)


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
	leave_button = _make_button("Leave", true)
	leave_button.name = "LeaveButton"
	choice_row.add_child(leave_button)
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
	var style := parchment_style(3, 8, 10)
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

	say_tools_row = HBoxContainer.new()
	say_tools_row.name = "SayTools"
	say_tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	say_tools_row.add_theme_constant_override("separation", 8)
	say_tools_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(say_tools_row)
	say_listen_button = _make_button("Listen")
	say_listen_button.name = "SayListenButton"
	say_tools_row.add_child(say_listen_button)
	say_speak_button = _make_button("Speak")
	say_speak_button.name = "SaySpeakButton"
	say_tools_row.add_child(say_speak_button)

	# Typing box: native GUI inside the dialog layer's own card (see
	# docs/ui-input-rules.md). Submit is router-bound like every button.
	say_typed_row = HBoxContainer.new()
	say_typed_row.name = "SayTyped"
	say_typed_row.add_theme_constant_override("separation", 6)
	say_typed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(say_typed_row)
	say_typed_input = LineEdit.new()
	say_typed_input.name = "SayTypedInput"
	say_typed_input.placeholder_text = "Type it, press Enter (dev)"
	say_typed_input.custom_minimum_size = Vector2(150, 44)
	say_typed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if text_label:
		say_typed_input.add_theme_font_override("font", text_label.get_theme_font("normal_font"))
	say_typed_input.add_theme_font_size_override("font_size", 14)
	say_typed_input.text_submitted.connect(_on_say_text_submitted)
	say_typed_row.add_child(say_typed_input)
	say_submit_button = _make_button("Submit")
	say_submit_button.name = "SaySubmitButton"
	say_typed_row.add_child(say_submit_button)

	say_tiles_row = HFlowContainer.new()
	say_tiles_row.name = "SayTiles"
	say_tiles_row.alignment = FlowContainer.ALIGNMENT_CENTER
	say_tiles_row.add_theme_constant_override("h_separation", 6)
	say_tiles_row.add_theme_constant_override("v_separation", 4)
	say_tiles_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	say_tiles_row.visible = false
	column.add_child(say_tiles_row)

	say_cancel_button = _make_button("Cancel", true)
	say_cancel_button.name = "SayCancelButton"
	say_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(say_cancel_button)
	clear_say_tools()


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


## Parchment chip; `quiet` is the outlined, lighter look for Leave / Cancel.
func _make_button(text: String, quiet: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	if text_label:
		btn.add_theme_font_override("font", text_label.get_theme_font("normal_font"))
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(64, 44)
	var normal := parchment_style(2, 6, 8, Color(SAY_BG, 0.8) if quiet else SAY_BG)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	if quiet:
		normal.border_color = Color(SAY_INK, 0.55)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = CHIP_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = CHIP_PRESSED
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(key, SAY_INK)
	btn.add_theme_color_override("font_disabled_color", Color(SAY_INK, 0.45))
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
		_set_indent(0.0)
		_stop_talk_anim()
		return

	var target_h := FALLBACK_DIALOG_HEIGHT
	if text_panel != null and text_panel.size.y > 1.0:
		target_h = text_panel.size.y

	# The card is a square as tall as the text box beside it; capped so a long
	# line can't blow the portrait up over the play area.
	target_h = clampf(target_h, PORTRAIT_MIN, PORTRAIT_MAX)
	portrait_slot.custom_minimum_size = Vector2(target_h, target_h)
	portrait_slot.size = Vector2(target_h, target_h)
	_set_indent(target_h + PORTRAIT_GAP)
	var inner := target_h - 8.0  # inside the frame's border

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
		var fitted := minf(inner / frame_w, inner / frame_h)
		portrait_sprite.scale = Vector2(fitted, fitted)
	else:
		portrait_sprite.scale = Vector2.ONE

	portrait_sprite.position = Vector2(target_h * 0.5, target_h * 0.5)
	portrait_slot.visible = true
	print("✅ Dialog portrait fitted to the text box height: ", target_h)

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
