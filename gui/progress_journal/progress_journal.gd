extends CanvasLayer

const BOLD := preload("res://gui/fonts/Abaddon Bold.ttf")
const LIGHT := preload("res://gui/fonts/Abaddon Light.ttf")
const BUBBLE := preload("res://gui/dialog_system/sprites/text-bubble.png")

const INK := Color(0.35, 0.24, 0.12, 1)
const PARCHMENT := Color(0.82, 0.78, 0.7, 1)
const PAGER_BG := Color(0.93, 0.88, 0.78, 1)
const TITLE_GOLD := Color(1, 0.97, 0.82, 1)
const PANEL_FILL := Color(0.04, 0.16, 0.1, 0.94)
const PANEL_BORDER := Color(0.86, 0.74, 0.32, 1)
const DIM := Color(0.02, 0.08, 0.04, 0.45)
const TEXT_LIGHT := Color(0.98, 0.96, 0.88, 1)

const ROWS_PER_PAGE := 5
const BAR_SEGMENTS := 8
const BAR_CELL := 8

enum Tab { TODAY, PHRASES, BESTIARY }

var _tab: Tab = Tab.TODAY
var _phrases_today_only := true
var _phrase_page := 0

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _tab_today: Button
var _tab_phrases: Button
var _tab_bestiary: Button
var _body: VBoxContainer
var _back: Button
var _touch_back: TouchScreenButton


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	_tab = Tab.TODAY
	_phrases_today_only = true
	_phrase_page = 0
	visible = true
	_refresh()
	if _back:
		_back.grab_focus()


func close() -> void:
	visible = false
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("request_flush"):
		tracker.request_flush()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	_align_touch(_back, _touch_back)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 400)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_FILL
	panel_style.border_color = PANEL_BORDER
	panel_style.set_border_width_all(4)
	panel_style.set_corner_radius_all(2)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_panel.add_child(outer)

	_title = Label.new()
	_title.text = "Journal"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", BOLD)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", TITLE_GOLD)
	outer.add_child(_title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(tabs)

	_tab_today = _make_pager_button("Today")
	_tab_phrases = _make_pager_button("Phrases")
	_tab_bestiary = _make_pager_button("Bestiary")
	_tab_today.pressed.connect(func(): _set_tab(Tab.TODAY))
	_tab_phrases.pressed.connect(func(): _set_tab(Tab.PHRASES))
	_tab_bestiary.pressed.connect(func(): _set_tab(Tab.BESTIARY))
	tabs.add_child(_tab_today)
	tabs.add_child(_tab_phrases)
	tabs.add_child(_tab_bestiary)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	outer.add_child(_body)

	_back = _make_pager_button("Back")
	_back.custom_minimum_size = Vector2(120, 36)
	_back.pressed.connect(close)
	outer.add_child(_back)

	_touch_back = TouchScreenButton.new()
	_touch_back.visible = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 36)
	_touch_back.shape = shape
	_touch_back.shape_visible = false
	_touch_back.pressed.connect(close)
	root.add_child(_touch_back)


func _set_tab(tab: Tab) -> void:
	_tab = tab
	_phrase_page = 0
	_refresh()


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()
	match _tab:
		Tab.TODAY:
			_fill_today()
		Tab.PHRASES:
			_fill_phrases()
		Tab.BESTIARY:
			_fill_bestiary()


func _tracker() -> Node:
	return get_node_or_null("/root/ProgressTracker")


func _fill_today() -> void:
	var tracker := _tracker()
	var today_key := tracker.today_key() if tracker else ""
	var day: Dictionary = tracker.day_stats(today_key) if tracker else {}
	var life: Dictionary = tracker.lifetime() if tracker else {}
	var streak_n := tracker.streak() if tracker else 0

	_body.add_child(_line("Today", today_key))
	_body.add_child(_line("Stages cleared", str(int(day.get("stages_cleared", 0)))))
	_body.add_child(_line("Best stage", str(int(life.get("best_stage", 0)))))
	_body.add_child(_line("Words", str(int(day.get("words_spoken", 0)))))
	_body.add_child(_line("Sentences", str(int(day.get("sentences_spoken", 0)))))
	_body.add_child(_line("Streak", str(streak_n)))

	var days: Array = tracker.recent_days(7) if tracker else []
	_body.add_child(_chart_row("Stages", days, "stages_cleared"))
	_body.add_child(_chart_row("Words", days, "words_spoken"))


func _fill_phrases() -> void:
	var switch := HBoxContainer.new()
	switch.add_theme_constant_override("separation", 8)
	switch.alignment = BoxContainer.ALIGNMENT_CENTER
	var today_btn := _make_pager_button("Today")
	var all_btn := _make_pager_button("All")
	today_btn.disabled = _phrases_today_only
	all_btn.disabled = not _phrases_today_only
	today_btn.pressed.connect(func():
		_phrases_today_only = true
		_phrase_page = 0
		_refresh()
	)
	all_btn.pressed.connect(func():
		_phrases_today_only = false
		_phrase_page = 0
		_refresh()
	)
	switch.add_child(today_btn)
	switch.add_child(all_btn)
	_body.add_child(switch)

	var tracker := _tracker()
	var map: Dictionary = tracker.phrases_map(_phrases_today_only) if tracker else {}
	var keys: Array = map.keys()
	keys.sort_custom(func(a, b):
		var ca := int(map[a].get("count", 0)) if map[a] is Dictionary else 0
		var cb := int(map[b].get("count", 0)) if map[b] is Dictionary else 0
		if ca != cb:
			return ca > cb
		return str(a) < str(b)
	)

	var bubble := PanelContainer.new()
	var style := StyleBoxTexture.new()
	style.texture = BUBBLE
	style.texture_margin_left = 16
	style.texture_margin_top = 16
	style.texture_margin_right = 16
	style.texture_margin_bottom = 16
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(bubble)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	bubble.add_child(rows)

	if keys.is_empty():
		var empty := Label.new()
		empty.text = "No words yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_override("font", LIGHT)
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", INK)
		rows.add_child(empty)
	else:
		var start := _phrase_page * ROWS_PER_PAGE
		var end := mini(start + ROWS_PER_PAGE, keys.size())
		for i in range(start, end):
			var phrase := str(keys[i])
			var count := 0
			if map[keys[i]] is Dictionary:
				count = int(map[keys[i]].get("count", 0))
			var row := Label.new()
			row.text = "%s    %d" % [phrase, count]
			row.add_theme_font_override("font", LIGHT)
			row.add_theme_font_size_override("font_size", 14)
			row.add_theme_color_override("font_color", INK)
			rows.add_child(row)

	var page_count := 1
	if keys.size() > 0:
		page_count = int(ceil(float(keys.size()) / float(ROWS_PER_PAGE)))
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 8)
	var prev := _make_pager_button("<")
	var next := _make_pager_button(">")
	var page_label := Label.new()
	page_label.text = "%d / %d" % [_phrase_page + 1, page_count]
	page_label.add_theme_font_override("font", LIGHT)
	page_label.add_theme_font_size_override("font_size", 14)
	page_label.add_theme_color_override("font_color", TEXT_LIGHT)
	prev.disabled = _phrase_page <= 0 or keys.is_empty()
	next.disabled = keys.is_empty() or (_phrase_page + 1) * ROWS_PER_PAGE >= keys.size()
	prev.pressed.connect(func():
		_phrase_page = maxi(_phrase_page - 1, 0)
		_refresh()
	)
	next.pressed.connect(func():
		_phrase_page += 1
		_refresh()
	)
	pager.add_child(prev)
	pager.add_child(page_label)
	pager.add_child(next)
	_body.add_child(pager)


func _fill_bestiary() -> void:
	var tracker := _tracker()
	var life: Dictionary = tracker.lifetime() if tracker else {}
	var day: Dictionary = tracker.day_stats(tracker.today_key()) if tracker else {}
	var life_kills: Dictionary = life.get("kills", {}) if life.get("kills") is Dictionary else {}
	var day_kills: Dictionary = day.get("kills", {}) if day.get("kills") is Dictionary else {}
	for kind in ["slime", "goblin", "beetle"]:
		var title := kind.capitalize()
		_body.add_child(_line("%s lifetime" % title, str(int(life_kills.get(kind, 0)))))
		_body.add_child(_line("%s today" % title, str(int(day_kills.get(kind, 0)))))


func _line(label: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = label
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_override("font", LIGHT)
	left.add_theme_font_size_override("font_size", 14)
	left.add_theme_color_override("font_color", TEXT_LIGHT)
	var right := Label.new()
	right.text = value
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_override("font", BOLD)
	right.add_theme_font_size_override("font_size", 14)
	right.add_theme_color_override("font_color", TITLE_GOLD)
	row.add_child(left)
	row.add_child(right)
	return row


func _chart_row(title: String, days: Array, field: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_override("font", BOLD)
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", TITLE_GOLD)
	box.add_child(title_label)

	var tracker := _tracker()
	var values: Array[int] = []
	var max_v := 1
	for day_key in days:
		var stats: Dictionary = tracker.day_stats(str(day_key)) if tracker else {}
		var v := int(stats.get(field, 0))
		values.append(v)
		max_v = maxi(max_v, v)

	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 6)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	var labels := HBoxContainer.new()
	labels.add_theme_constant_override("separation", 6)
	labels.alignment = BoxContainer.ALIGNMENT_CENTER

	for i in values.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.custom_minimum_size = Vector2(BAR_CELL, BAR_CELL * BAR_SEGMENTS)
		var filled := int(round(float(values[i]) / float(max_v) * float(BAR_SEGMENTS)))
		filled = clampi(filled, 0, BAR_SEGMENTS)
		var empty_n := BAR_SEGMENTS - filled
		for _e in empty_n:
			var empty_cell := ColorRect.new()
			empty_cell.custom_minimum_size = Vector2(BAR_CELL, BAR_CELL)
			empty_cell.color = PARCHMENT
			col.add_child(empty_cell)
		for _f in filled:
			var fill_cell := ColorRect.new()
			fill_cell.custom_minimum_size = Vector2(BAR_CELL, BAR_CELL)
			fill_cell.color = INK
			col.add_child(fill_cell)
		bars.add_child(col)

		var day_key := str(days[i]) if i < days.size() else ""
		var day_num := "?"
		if day_key.length() >= 10:
			day_num = str(int(day_key.substr(8, 2)))
		var day_label := Label.new()
		day_label.text = day_num
		day_label.custom_minimum_size = Vector2(BAR_CELL + 4, 0)
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day_label.add_theme_font_override("font", LIGHT)
		day_label.add_theme_font_size_override("font_size", 10)
		day_label.add_theme_color_override("font_color", TEXT_LIGHT)
		labels.add_child(day_label)

	box.add_child(bars)
	box.add_child(labels)
	return box


func _make_pager_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(88, 32)
	btn.add_theme_font_override("font", LIGHT)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", INK)
	btn.add_theme_color_override("font_disabled_color", Color(0.12, 0.08, 0.04, 0.35))
	var normal := StyleBoxFlat.new()
	normal.bg_color = PAGER_BG
	normal.border_color = INK
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 2
	normal.content_margin_bottom = 2
	var off := normal.duplicate()
	off.bg_color = Color(0.82, 0.78, 0.7, 0.6)
	off.border_color = Color(0.35, 0.24, 0.12, 0.35)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_stylebox_override("disabled", off)
	return btn


func _align_touch(button: Control, touch: TouchScreenButton) -> void:
	if button == null or touch == null:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size
