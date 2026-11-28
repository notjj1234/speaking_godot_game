# test_enemy_health_bar.gd
#
# Headless API checks for EnemyHealthBar crisp-number path.
# Run when a Godot binary is available:
#   Godot --headless --path <project> -s res://tools/tests/test_enemy_health_bar.gd

extends SceneTree

var failures := 0


func _fail(name: String) -> void:
	failures += 1
	print("❌ ", name)


func _check(name: String, cond: bool) -> void:
	if cond:
		print("✅ ", name)
	else:
		_fail(name)


func _init() -> void:
	var bar := EnemyHealthBar.new()
	root.add_child(bar)
	bar.setup(3)
	_check("setup shows max/max", bar.get_display_text() == "3/3")
	bar.update_bar(1)
	_check("update_bar shows current/max", bar.get_display_text() == "1/3")
	_check("visible after update", bar.visible == true)
	bar.hide_bar()
	_check("hide_bar hides", bar.visible == false)
	_check(
		"font is m5x7",
		str(EnemyHealthBar.NUMBER_FONT.resource_path).ends_with("m5x7.ttf")
	)
	bar.update_bar(0)
	_check("zero hp still formats", bar.get_display_text() == "0/3")
	_check("no phases by default", bar.phases_left() == 0)
	bar.set_phases(3, 3)
	_check("boss bar names phase 1/3", bar.get_display_text() == "Phase 1/3")
	_check("three pips left", bar.phases_left() == 3)
	bar.set_phases(2, 3)
	_check("after a pass: phase 2/3", bar.get_display_text() == "Phase 2/3")
	_check("two pips left", bar.phases_left() == 2)
	quit(0 if failures == 0 else 1)
