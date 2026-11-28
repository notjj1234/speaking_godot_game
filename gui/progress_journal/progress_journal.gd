extends CanvasLayer

const BOLD := preload("res://gui/fonts/Abaddon Bold.ttf")
const LIGHT := preload("res://gui/fonts/Abaddon Light.ttf")
const BUBBLE := preload("res://gui/dialog_system/sprites/text-bubble.png")

const INK := Color(0.35, 0.24, 0.12, 1)
const PAGER_BG := Color(0.93, 0.88, 0.78, 1)
const TITLE_GOLD := Color(1, 0.97, 0.82, 1)
const PANEL_BORDER := Color(0.86, 0.74, 0.32, 1)
const DIM := Color(0.02, 0.08, 0.04, 0.45)
const TEXT_LIGHT := Color(0.98, 0.96, 0.88, 1)

# New UI matching title screen updated style (see title_screen.tscn StyleBoxFlat_primary_focus & StyleBoxFlat_secondary)
const UI_BG_COLOR := Color(0.05, 0.14, 0.09, 1)
const UI_ACCENT_COLOR := Color(0.16, 0.46, 0.24, 1)
const UI_TEXT_COLOR := Color(0.98, 0.96, 0.88, 1)

const TILE_BG := Color(0.09, 0.24, 0.15, 1)
const TILE_BORDER := Color(0.86, 0.74, 0.32, 0.45)
const BAR_TRACK := Color(0.13, 0.3, 0.19, 1)
const TODAY_GREEN := Color(0.62, 0.92, 0.58, 1)

const ROWS_PER_PAGE := 5
const BAR_SEGMENTS := 8
const BAR_CELL := Vector2(18, 7)
# A quiet week should not fill the bars: 1 word is a sliver, not a full column.
const BAR_MIN_SCALE := 5

const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTHS := ["January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"]

const MONSTERS := ["slime", "goblin", "beetle", "orc", "skeleton", "bandit"]
const MONSTER_SHEETS := {
	"slime": preload("res://enemies/slime/Slime.png"),
	"goblin": preload("res://enemies/goblin/goblin.png"),
	"beetle": preload("res://enemies/beetle/Beetle.png"),
	"orc": preload("res://enemies/orc/orc.png"),
	"skeleton": preload("res://enemies/skeleton/skeleton.png"),
	"bandit": preload("res://enemies/bandit/bandit.png"),
}
const MONSTER_FRAME := Rect2(0, 0, 64, 64)

enum Tab { TODAY, PHRASES, BESTIARY }

var _tab: Tab = Tab.TODAY
var _phrases_today_only := false
var _phrase_page := 0

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _tab_today: Button
var _tab_phrases: Button
var _tab_bestiary: Button
var _body: VBoxContainer
var _back: Button
var _root: Control
var _input_layer := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	_tab = Tab.TODAY
	_phrases_today_only = false
	_phrase_page = 0
	visible = true
	if _input_layer == 0:
		_input_layer = UiInputRouter.push_layer(&"journal", self)
	# Tap outside closes. The panel sits above the dimmer and swallows the rest.
	UiInputRouter.bind(_dim, _on_dim_tapped, _input_layer)
	UiInputRouter.bind(_panel, _swallow_tap, _input_layer)
	_route(_tab_today, _set_tab.bind(Tab.TODAY))
	_route(_tab_phrases, _set_tab.bind(Tab.PHRASES))
	_route(_tab_bestiary, _set_tab.bind(Tab.BESTIARY))
	_route(_back, close)
	_refresh()
	if _back:
		_back.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	UiInputRouter.pop_layer(_input_layer)
	_input_layer = 0
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()
	# Defer flush so a save error cannot interrupt teardown.
	call_deferred("_deferred_flush")


## Pointer presses and keyboard `pressed` for one button on this layer.
func _route(button: Button, handler: Callable) -> void:
	UiInputRouter.bind_button(button, handler, _input_layer)


func _on_dim_tapped() -> void:
	close()


func _swallow_tap() -> void:
	pass


func _deferred_flush() -> void:
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("request_flush"):
		tracker.request_flush()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 400)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UI_BG_COLOR
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
	_tab_phrases = _make_pager_button("My Words")
	_tab_bestiary = _make_pager_button("Monsters")
	tabs.add_child(_tab_today)
	tabs.add_child(_tab_phrases)
	tabs.add_child(_tab_bestiary)
	# Close shares the tab row (a 44 px row of its own would not fit 480 px),
	# set apart by a gap and a dark outline so it doesn't read as a 4th tab.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	tabs.add_child(gap)
	_back = _make_pager_button("Close")
	_style_close_button(_back)
	tabs.add_child(_back)

	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	outer.add_child(_body)



func _set_tab(tab: Tab) -> void:
	_tab = tab
	_phrase_page = 0
	_refresh()


func _set_scope(today_only: bool) -> void:
	_phrases_today_only = today_only
	_phrase_page = 0
	_refresh()


func _turn_page(step: int) -> void:
	_phrase_page = maxi(_phrase_page + step, 0)
	_refresh()


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()
	_apply_button_style(_tab_today, _tab == Tab.TODAY)
	_apply_button_style(_tab_phrases, _tab == Tab.PHRASES)
	_apply_button_style(_tab_bestiary, _tab == Tab.BESTIARY)
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
	var today_key: String = tracker.today_key() if tracker else ""
	var day: Dictionary = tracker.day_stats(today_key) if tracker else {}
	var life: Dictionary = tracker.lifetime() if tracker else {}
	var streak_n: int = tracker.streak() if tracker else 0
	var words := int(day.get("words_spoken", 0))
	var sentences := int(day.get("sentences_spoken", 0))
	var best := int(life.get("best_stage", 0))

	_body.add_child(_text(_cheer_line(words, sentences), BOLD, 14, TITLE_GOLD, true))
	_body.add_child(_text(_friendly_date(today_key), LIGHT, 12, UI_TEXT_COLOR, true))

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(_stat_tile(words, "words said"))
	tiles.add_child(_stat_tile(sentences, "sentences said"))
	tiles.add_child(_stat_tile(int(day.get("stages_cleared", 0)), "stages won"))
	tiles.add_child(_stat_tile(streak_n, "days in a row"))
	_body.add_child(tiles)

	var best_text: String = "Highest stage ever: %d" % best if best > 0 else "Highest stage ever: none yet"
	_body.add_child(_text(best_text, LIGHT, 14, UI_TEXT_COLOR, true))

	var days: Array = tracker.recent_days(7) if tracker else []
	_body.add_child(_week_chart(days))


func _cheer_line(words: int, sentences: int) -> String:
	if words + sentences == 0:
		return "Beat a monster by speaking to start today!"
	var parts: Array[String] = []
	if words > 0:
		parts.append(_count_noun(words, "word"))
	if sentences > 0:
		parts.append(_count_noun(sentences, "sentence"))
	return "You said %s today. Great job!" % " and ".join(parts)


func _count_noun(n: int, noun: String) -> String:
	return "%d %s" % [n, noun if n == 1 else noun + "s"]


## "2026-11-26" -> "Thursday 26 November". Falls back to the key if it does not parse.
func _friendly_date(day_key: String) -> String:
	var parts := day_key.split("-")
	if parts.size() != 3:
		return day_key
	var d := Time.get_datetime_dict_from_datetime_string(day_key, true)
	var month := int(d.get("month", 0))
	if month < 1 or month > 12:
		return day_key
	return "%s %d %s" % [WEEKDAYS[int(d.get("weekday", 0)) % 7], int(d.get("day", 0)), MONTHS[month - 1]]


func _weekday_letter(day_key: String) -> String:
	var d := Time.get_datetime_dict_from_datetime_string(day_key, true)
	return str(WEEKDAYS[int(d.get("weekday", 0)) % 7]).left(1)


func _fill_phrases() -> void:
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

	var scope := HBoxContainer.new()
	scope.alignment = BoxContainer.ALIGNMENT_CENTER
	scope.add_theme_constant_override("separation", 8)
	var today_btn := _make_pager_button("Just today")
	var all_btn := _make_pager_button("All time")
	today_btn.custom_minimum_size.x = 120
	all_btn.custom_minimum_size.x = 120
	_apply_button_style(today_btn, _phrases_today_only)
	_apply_button_style(all_btn, not _phrases_today_only)
	_route(today_btn, _set_scope.bind(true))
	_route(all_btn, _set_scope.bind(false))
	scope.add_child(today_btn)
	scope.add_child(all_btn)
	_body.add_child(scope)

	var heading := "Words you said today" if _phrases_today_only else "Words you have said"
	_body.add_child(_text(heading, BOLD, 14, TITLE_GOLD, true))

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
		rows.add_child(_text("No words yet. Beat a monster by speaking!", LIGHT, 14, INK, true))
		return

	var start := _phrase_page * ROWS_PER_PAGE
	var end := mini(start + ROWS_PER_PAGE, keys.size())
	for i in range(start, end):
		var count := 0
		if map[keys[i]] is Dictionary:
			count = int(map[keys[i]].get("count", 0))
		rows.add_child(_phrase_row(str(keys[i]), count))

	var page_count := int(ceil(float(keys.size()) / float(ROWS_PER_PAGE)))
	if page_count <= 1:
		return
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 8)
	var prev := _make_pager_button("<")
	var next := _make_pager_button(">")
	var page_label := _text("Page %d of %d" % [_phrase_page + 1, page_count], LIGHT, 14, TEXT_LIGHT, true)
	page_label.custom_minimum_size.x = 96
	prev.disabled = _phrase_page <= 0
	next.disabled = (_phrase_page + 1) * ROWS_PER_PAGE >= keys.size()
	_route(prev, _turn_page.bind(-1))
	_route(next, _turn_page.bind(1))
	pager.add_child(prev)
	pager.add_child(page_label)
	pager.add_child(next)
	_body.add_child(pager)


func _phrase_row(phrase: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := _text(phrase, BOLD, 14, INK, false)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.clip_text = true
	left.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var right := _text("said %s" % ("1 time" if count == 1 else "%d times" % count), LIGHT, 14, INK, false)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	row.add_child(right)
	return row


func _fill_bestiary() -> void:
	var tracker := _tracker()
	var life: Dictionary = tracker.lifetime() if tracker else {}
	var day: Dictionary = tracker.day_stats(tracker.today_key()) if tracker else {}
	var life_kills: Dictionary = life.get("kills", {}) if life.get("kills") is Dictionary else {}
	var day_kills: Dictionary = day.get("kills", {}) if day.get("kills") is Dictionary else {}

	_body.add_child(_text("Monsters you have beaten", BOLD, 14, TITLE_GOLD, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for kind in MONSTERS:
		grid.add_child(_monster_card(kind, int(life_kills.get(kind, 0)), int(day_kills.get(kind, 0))))
	_body.add_child(grid)


func _monster_card(kind: String, total: int, today: int) -> PanelContainer:
	var card := _tile_panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	var atlas := AtlasTexture.new()
	atlas.atlas = MONSTER_SHEETS[kind]
	atlas.region = MONSTER_FRAME
	var pic := TextureRect.new()
	pic.texture = atlas
	pic.custom_minimum_size = Vector2(48, 48)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Unmet monsters show as a dark shape, something to discover.
	if total == 0:
		pic.modulate = Color(0, 0, 0, 0.55)
	row.add_child(pic)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(_text(kind.capitalize(), BOLD, 14, TITLE_GOLD, false))
	if total == 0:
		info.add_child(_text("Not beaten yet", LIGHT, 12, UI_TEXT_COLOR, false))
	else:
		info.add_child(_text("%d beaten" % total, LIGHT, 14, UI_TEXT_COLOR, false))
		if today > 0:
			info.add_child(_text("+%d today" % today, LIGHT, 12, TODAY_GREEN, false))
	row.add_child(info)
	return card


func _text(value: String, font: Font, size: int, color: Color, centered: bool) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _tile_panel() -> PanelContainer:
	var tile := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = TILE_BG
	style.border_color = TILE_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", style)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tile


func _stat_tile(number: int, caption: String) -> PanelContainer:
	var tile := _tile_panel()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(_text(str(number), BOLD, 20, TITLE_GOLD, true))
	box.add_child(_text(caption, LIGHT, 12, UI_TEXT_COLOR, true))
	tile.add_child(box)
	return tile


## Words + sentences per day, oldest first. Each day is one column (count, bar,
## weekday) so a label can never drift away from its bar.
func _week_chart(days: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_text("Your speaking this week", BOLD, 12, TITLE_GOLD, false))

	var tracker := _tracker()
	var values: Array[int] = []
	var bar_top := BAR_MIN_SCALE
	for day_key in days:
		var stats: Dictionary = tracker.day_stats(str(day_key)) if tracker else {}
		var v := int(stats.get("words_spoken", 0)) + int(stats.get("sentences_spoken", 0))
		values.append(v)
		bar_top = maxi(bar_top, v)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	var week_total := 0
	for i in values.size():
		week_total += values[i]
		var is_today := i == values.size() - 1
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.custom_minimum_size.x = 40

		col.add_child(_text(str(values[i]), BOLD, 12, TITLE_GOLD if values[i] > 0 else UI_TEXT_COLOR, true))

		var bar := VBoxContainer.new()
		bar.add_theme_constant_override("separation", 1)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var filled := 0
		if values[i] > 0:
			filled = clampi(int(ceil(float(values[i]) / float(bar_top) * float(BAR_SEGMENTS))), 1, BAR_SEGMENTS)
		for s in BAR_SEGMENTS:
			var cell := ColorRect.new()
			cell.custom_minimum_size = BAR_CELL
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.color = TITLE_GOLD if s >= BAR_SEGMENTS - filled else BAR_TRACK
			bar.add_child(cell)
		col.add_child(bar)

		var day_name := "Today" if is_today else _weekday_letter(str(days[i]))
		col.add_child(_text(day_name, BOLD if is_today else LIGHT, 12,
				TITLE_GOLD if is_today else UI_TEXT_COLOR, true))
		columns.add_child(col)
	box.add_child(columns)

	if week_total == 0:
		box.add_child(_text("Say words in battle to fill this up!", LIGHT, 12, UI_TEXT_COLOR, true))
	return box


func _make_pager_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(88, 44)
	btn.add_theme_font_override("font", LIGHT)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_disabled_color", Color(0.12, 0.08, 0.04, 0.35))
	var off := _button_box(Color(0.82, 0.78, 0.7, 0.6), Color(0.35, 0.24, 0.12, 0.35))
	btn.add_theme_stylebox_override("disabled", off)
	_apply_button_style(btn, false)
	return btn


## Selected buttons (open tab, chosen scope) are filled green with light text.
## Every font colour state is set: Godot's default focus colour is near-white,
## which made a focused button's label vanish on the parchment fill.
func _apply_button_style(btn: Button, selected: bool) -> void:
	var box := _button_box(UI_ACCENT_COLOR, PANEL_BORDER) if selected else _button_box(PAGER_BG, INK)
	var ink := TEXT_LIGHT if selected else INK
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ink)


## Close: dark fill, light text, thicker light outline; a visible focus ring.
func _style_close_button(btn: Button) -> void:
	var box := _button_box(Color(0.12, 0.08, 0.04, 0.9), TEXT_LIGHT)
	box.set_border_width_all(2)
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = UI_ACCENT_COLOR
	focus.set_border_width_all(3)
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, box)
	btn.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, TEXT_LIGHT)


func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box
