# enemy_health_bar.gd

class_name EnemyHealthBar
extends Node2D

const BAR_W := 26.0
const BAR_H := 4.0
const BORDER_COLOR := Color(0.86, 0.74, 0.32)  # gold, matches bonfire chrome
const BG_COLOR := Color(0.04, 0.16, 0.1)
const NORMAL_COLOR := Color(0.35, 0.75, 0.35)
const CAUTION_COLOR := Color(0.95, 0.8, 0.25)
const CRITICAL_COLOR := Color(0.85, 0.3, 0.25)
const CAUTION_FRACTION := 0.5
const CRITICAL_FRACTION := 0.2
const NUMBER_FONT := preload("res://gui/fonts/m5x7.ttf")
const NUMBER_SIZE := 12
const OUTLINE_SIZE := 1
const NUMBER_COLOR := Color(1, 1, 1)
const OUTLINE_COLOR := Color(0, 0, 0, 0.9)

var _max_hp := 1
var _hp := 1


func _ready() -> void:
	visible = false


func setup(max_hp: int) -> void:
	_max_hp = maxi(max_hp, 1)
	_hp = _max_hp
	queue_redraw()


func update_bar(hp: int) -> void:
	_hp = clampi(hp, 0, _max_hp)
	visible = true
	queue_redraw()


func hide_bar() -> void:
	visible = false


func get_display_text() -> String:
	return "%d/%d" % [_hp, _max_hp]


func _fraction() -> float:
	return float(_hp) / float(_max_hp)


func _fill_color() -> Color:
	var f := _fraction()
	if f < CRITICAL_FRACTION:
		return CRITICAL_COLOR
	if f < CAUTION_FRACTION:
		return CAUTION_COLOR
	return NORMAL_COLOR


func _draw() -> void:
	# Frame: gold border 1px around a dark-green track.
	draw_rect(Rect2(-1, -1, BAR_W + 2, BAR_H + 2), BORDER_COLOR)
	draw_rect(Rect2(0, 0, BAR_W, BAR_H), BG_COLOR)
	var fill_w := BAR_W * _fraction()
	if fill_w > 0.0:
		draw_rect(Rect2(0, 0, fill_w, BAR_H), _fill_color())

	var text := get_display_text()
	var text_size := NUMBER_FONT.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_SIZE
	)
	# Baseline a few px above the bar; snap to whole pixels for nearest filter.
	var pos := Vector2(
		roundf((BAR_W - text_size.x) * 0.5),
		roundf(-2.0)
	)
	draw_string_outline(
		NUMBER_FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		NUMBER_SIZE, OUTLINE_SIZE, OUTLINE_COLOR
	)
	draw_string(
		NUMBER_FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		NUMBER_SIZE, NUMBER_COLOR
	)
