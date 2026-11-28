class_name CoachBanner
extends CanvasLayer
## The Trainer's speech bubble for Guided Training and one-time tips. A new
## lesson shows the full bubble briefly, then it shrinks to a small pill in
## the top-left corner with the lesson's goal, so the play area stays clear.
## Tap the pill (or press H / coach_toggle) to read the full text again.
## Tap-to-continue lessons stay open until continued. It never blocks
## gameplay input: only the bubble/pill themselves are tappable.

signal continue_pressed

const TRAINER := preload("res://npc/00_npcs/camp_trainer.tres")
const PORTRAIT_SIZE := 64.0
const BUBBLE_WIDTH := 480.0
const BUBBLE_FONT := 17
const PILL_PORTRAIT := 36.0
const PILL_MARGIN := 8.0
const PILL_TOP := 4.0
## Ends at y 50: clear of the HUD mic-banner line (y 52).
const PILL_HEIGHT := 46.0
const PILL_MIN_WIDTH := 150.0
const PILL_MAX_WIDTH := 300.0
const PILL_FONT := 16
const BADGE_SIZE := 24.0
const HINT_COLOR := Color(0.35, 0.22, 0.08, 1)
const GAMEPLAY_ACTIONS: Array[StringName] = [&"up", &"down", &"left", &"right", &"attack", &"interact"]

## Seconds a non-tap lesson stays open before shrinking to the pill.
var collapse_sec := 4.0

var _panel: PanelContainer
var _label: Label
var _hint: Label
var _portrait: TextureRect
var _pill: PanelContainer
var _pill_label: Label
var _badge: PanelContainer
var _pill_tween: Tween
var _popped_goal := ""
## How many times a new goal has popped the pill (tests read this).
var pill_pops := 0
## The open bubble moves to the bottom while its top spot would cover this
## screen rect (the current lesson's target and its arrow).
var _avoid := Rect2()
var _at_bottom := false
const BOTTOM_MARGIN := 12.0
var _text := ""
var _goal := ""
var _tap := false
var _collapsed := false
var _suppressed := false
var _shown := false
var _flash_token := 0
var _collapse_token := 0
## Flash tips stay open (they hide themselves instead of shrinking).
var _pinned := false


func _init() -> void:
	layer = 5  # above the HUD (2), below the PauseMenu (10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _bubble_style(12.0, 8.0))
	root.add_child(_panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_panel.add_child(row)

	_portrait = _make_portrait(PORTRAIT_SIZE)
	row.add_child(_portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	_label = _make_label(BUBBLE_FONT, TutorialDialog.INK)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_label)

	_hint = _make_label(13, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.visible = false
	column.add_child(_hint)

	# The pill: portrait + one-line goal, top-left, clear of the hearts (top
	# centre), the mic/version badges (top right) and the y 52 HUD banner.
	_pill = PanelContainer.new()
	_pill.name = "Pill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override("panel", _bubble_style(8.0, 4.0))
	_pill.visible = false
	root.add_child(_pill)
	var pill_row := HBoxContainer.new()
	pill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_row.add_theme_constant_override("separation", 8)
	_pill.add_child(pill_row)
	pill_row.add_child(_make_portrait(PILL_PORTRAIT))
	_pill_label = _make_label(PILL_FONT, TutorialDialog.INK)
	_pill_label.clip_text = true
	_pill_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill_row.add_child(_pill_label)
	# Round "?" badge: tap the pill for the full text.
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = TutorialDialog.INK
	badge_style.set_corner_radius_all(int(BADGE_SIZE * 0.5))
	_badge.add_theme_stylebox_override("panel", badge_style)
	var q := _make_label(PILL_FONT, Color(0.98, 0.94, 0.84, 1))
	q.text = "?"
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(q)
	pill_row.add_child(_badge)
	_layout()


func _bubble_style(margin_x: float, margin_y: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = TutorialDialog.BUBBLE
	style.content_margin_left = margin_x
	style.content_margin_top = margin_y
	style.content_margin_right = margin_x + 2.0
	style.content_margin_bottom = margin_y
	style.texture_margin_left = 16.0
	style.texture_margin_top = 16.0
	style.texture_margin_right = 16.0
	style.texture_margin_bottom = 16.0
	return style


func _make_portrait(size_px: float) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(size_px, size_px)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _trainer_portrait()
	return portrait


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", TutorialDialog.BODY_FONT)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _trainer_portrait() -> Texture2D:
	var sheet: Texture2D = TRAINER.portrait
	if sheet == null:
		return null
	var frames := maxi(int(TRAINER.portrait_hframes), 1)
	if frames == 1:
		return sheet
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var w := sheet.get_width() / frames
	atlas.region = Rect2(0, 0, w, sheet.get_height())
	return atlas


## The open bubble: BUBBLE_WIDTH wide, never wider than the view minus 24.
func bubble_width_for(view: Vector2) -> float:
	return minf(BUBBLE_WIDTH, view.x - 24.0)


## On portrait phones the pause button owns the top-left corner: the pill
## goes just under it.
func pill_top_for(portrait: bool, pause_rect: Rect2) -> float:
	if portrait and pause_rect.size.y > 0.0:
		return pause_rect.end.y + 6.0
	return PILL_TOP


## Where the open bubble sits normally (top centre), for the avoid check.
func top_rect_for(view: Vector2) -> Rect2:
	var w := bubble_width_for(view)
	return Rect2((view.x - w) * 0.5, TutorialDialog.TOP_MARGIN, w, TutorialDialog.BANNER_HEIGHT)


## Keep the open bubble off `rect` (screen coords); an empty rect clears it.
func set_avoid(rect: Rect2) -> void:
	if rect == _avoid:
		return
	_avoid = rect
	var was := _at_bottom
	_layout()
	if was != _at_bottom:
		_panel.reset_size()


func is_at_bottom() -> bool:
	return _at_bottom


func hint_text() -> String:
	return _hint.text


## Above the touch controls on touch screens, else a small gap.
func _bottom_margin(view: Vector2) -> float:
	if not is_inside_tree() or not MobileSafeLayout.wants_touch_ui():
		return BOTTOM_MARGIN
	var placed: Dictionary = MobileSafeLayout.layout_touch_controls(get_viewport())
	var top := view.y
	for key in ["left", "right"]:
		if placed.has(key):
			top = minf(top, (placed[key] as Rect2).position.y)
	return maxf(BOTTOM_MARGIN, view.y - top + 8.0)


func pill_font_size() -> int:
	return _pill_label.get_theme_font_size("font_size")


func _layout() -> void:
	var view := Vector2(640, 480)
	var portrait := false
	var pause_rect := Rect2()
	if is_inside_tree():
		var vp := get_viewport()
		view = vp.get_visible_rect().size
		portrait = MobileSafeLayout.is_portrait(vp) and MobileSafeLayout.wants_touch_ui()
		if portrait:
			pause_rect = MobileSafeLayout.layout_touch_controls(vp).get("pause", Rect2())
	var width := bubble_width_for(view)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_at_bottom = _avoid.has_area() and top_rect_for(view).intersects(_avoid)
	if _at_bottom:
		var bottom := _bottom_margin(view)
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_panel.offset_bottom = -bottom
		_panel.offset_top = -bottom - TutorialDialog.BANNER_HEIGHT
	else:
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 0.0
		_panel.grow_vertical = Control.GROW_DIRECTION_END
		_panel.offset_top = TutorialDialog.TOP_MARGIN
		_panel.offset_bottom = TutorialDialog.TOP_MARGIN + TutorialDialog.BANNER_HEIGHT
	_pill.anchor_left = 0.0
	_pill.anchor_right = 0.0
	_pill.anchor_top = 0.0
	_pill.anchor_bottom = 0.0
	var top := pill_top_for(portrait, pause_rect)
	_pill.offset_left = PILL_MARGIN
	_pill.offset_top = top
	_pill.offset_right = PILL_MARGIN + _pill_width()
	_pill.offset_bottom = top + PILL_HEIGHT


## Fits the goal text: portrait + text + badge, within the min / max width.
func _pill_width() -> float:
	var font := _pill_label.get_theme_font("font")
	var text_w := 120.0
	if font:
		text_w = font.get_string_size(_pill_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_FONT).x
	var w := 8.0 + PILL_PORTRAIT + 8.0 + text_w + 8.0 + BADGE_SIZE + 12.0
	var max_w := PILL_MAX_WIDTH
	if is_inside_tree():
		var vis := get_viewport().get_visible_rect()
		var hearts: Rect2 = MobileSafeLayout._hud_rects(vis)[0]
		max_w = minf(max_w, hearts.position.x - PILL_MARGIN - 6.0)
	return clampf(w, minf(PILL_MIN_WIDTH, max_w), max_w)


## A new goal on the pill pops in and glows twice so the change is noticed.
func _pop_pill() -> void:
	if _goal == _popped_goal:
		return
	_popped_goal = _goal
	pill_pops += 1
	if _pill_tween:
		_pill_tween.kill()
	if not is_inside_tree():
		return
	_pill.pivot_offset = Vector2(0.0, PILL_HEIGHT * 0.5)
	_pill.scale = Vector2(0.85, 0.85)
	_pill.modulate = Color.WHITE
	_pill_tween = create_tween()
	_pill_tween.tween_property(_pill, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 2:
		_pill_tween.tween_property(_pill, "modulate", Color(1.35, 1.25, 0.9), 0.18)
		_pill_tween.tween_property(_pill, "modulate", Color.WHITE, 0.22)


## Shows `text` expanded. With tap_to_continue, a tap on the bubble or
## ui_accept emits continue_pressed (once per say) and it stays open; else it
## shrinks to the pill (showing `goal`) after collapse_sec or on first play.
func say(text: String, tap_to_continue: bool = false, goal: String = "") -> void:
	_flash_token += 1
	_text = text
	_label.text = text
	_goal = goal
	_pinned = false
	_pill_label.text = goal if goal != "" else _first_words(text)
	_layout()
	_shown = true
	_set_tap(tap_to_continue)
	expand()


## A non-blocking tip that hides itself after `seconds` (never shrinks).
func flash(text: String, seconds: float = 5.0) -> void:
	say(text, false)
	_pinned = true
	_collapse_token += 1  # tips don't shrink to a pill
	var token := _flash_token
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _flash_token and is_instance_valid(self):
		clear()


func clear() -> void:
	_flash_token += 1
	_collapse_token += 1
	_shown = false
	_set_tap(false)
	_refresh()


func expand() -> void:
	_collapsed = false
	_refresh()
	if not _tap:
		_collapse_later()


func collapse() -> void:
	if _tap or _pinned or not _shown:
		return
	_collapse_token += 1
	_collapsed = true
	_refresh()
	_pop_pill()


func toggle() -> void:
	if _collapsed:
		expand()
	else:
		collapse()


func is_collapsed() -> bool:
	return _collapsed


## A dialog or speech challenge owns the screen: hide everything, then come
## back in the same state.
func set_suppressed(on: bool) -> void:
	if on == _suppressed:
		return
	_suppressed = on
	_refresh()


func current_text() -> String:
	return _text


func current_goal() -> String:
	return _goal


func pill_text() -> String:
	return _pill_label.text


func pill_rect() -> Rect2:
	return _pill.get_global_rect()


## Whichever part is on screen (for keeping it clear of other UI).
func panel_rect() -> Rect2:
	return _pill.get_global_rect() if _collapsed else _panel.get_global_rect()


func _refresh() -> void:
	visible = _shown and not _suppressed
	_panel.visible = not _collapsed
	_pill.visible = _collapsed
	_sync_router()


func _collapse_later() -> void:
	_collapse_token += 1
	var token := _collapse_token
	if not is_inside_tree():
		return
	await get_tree().create_timer(collapse_sec, false).timeout
	if is_instance_valid(self) and token == _collapse_token and not _collapsed:
		collapse()


func _process(_delta: float) -> void:
	if _collapsed or _tap or _pinned or not _shown or _suppressed or get_tree().paused:
		return
	for action in GAMEPLAY_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			collapse()
			return


func _first_words(text: String) -> String:
	var words := text.split(" ", false)
	return " ".join(words.slice(0, mini(words.size(), 4)))


func _set_tap(enabled: bool) -> void:
	_tap = enabled
	_hint.visible = enabled
	_hint.text = "Tap to continue" if MobileSafeLayout.wants_touch_ui() else "Click or press Enter to continue"
	if enabled:
		_collapsed = false
	_sync_router()


## Base-layer taps: the open bubble continues (tap lessons), the pill expands.
func _sync_router() -> void:
	if not is_inside_tree():
		return
	var router := get_node_or_null("/root/UiInputRouter")
	if router == null:
		return
	var live := visible
	if live and _tap and not _collapsed:
		router.bind(_panel, _on_tap)
	else:
		router.unbind(_panel)
	if live and _collapsed:
		router.bind(_pill, _on_pill_tap)
	else:
		router.unbind(_pill)


func _on_tap() -> void:
	if not _tap or not visible:
		return
	_set_tap(false)
	continue_pressed.emit()


func _on_pill_tap() -> void:
	if visible and _collapsed:
		expand()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# A menu on top (pause, settings) owns the keyboard.
	if get_tree().paused:
		return
	var router := get_node_or_null("/root/UiInputRouter")
	if router and router.active_layer() != 0:
		return
	if InputMap.has_action(&"coach_toggle") and event.is_action_pressed(&"coach_toggle") and not _tap:
		get_viewport().set_input_as_handled()
		toggle()
		return
	if _tap and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_tap()


func _enter_tree() -> void:
	call_deferred("_sync_router")
	call_deferred("_layout")
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp and vp.size_changed.is_connected(_layout):
		vp.size_changed.disconnect(_layout)
	var router := get_node_or_null("/root/UiInputRouter")
	if router:
		if _panel:
			router.unbind(_panel)
		if _pill:
			router.unbind(_pill)
