extends "res://tools/ui_qa/pointer_driver.gd"
## Generated UI sounds: every cue loads, Sfx counts plays, and one router press
## gives exactly one click. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_sfx.tscn

var ui := CanvasLayer.new()
var hits := 0


func _hit() -> void:
	hits += 1


func _ready() -> void:
	get_window().size = Vector2i(640, 480)
	await frames(5)
	var sfx := get_node_or_null("/root/Sfx")
	check("autoload Sfx exists", sfx != null, true)
	if sfx == null:
		finish()
		return
	check("SFX bus exists", AudioServer.get_bus_index("SFX") != -1, true)
	for cue in sfx.CUES:
		var path := "res://audio/sfx/%s.wav" % cue
		var stream := load(path) as AudioStreamWAV
		check("%s loads as AudioStreamWAV" % cue, stream != null, true)
		if stream:
			var limit := 1.2 if cue == "victory" else 0.6
			check("%s is short" % cue, stream.get_length() < limit and stream.get_length() > 0.0, true)

	sfx.reset_counts()
	sfx.play(&"correct")
	check("play sets last_cue", sfx.last_cue, &"correct")
	check("play counts", sfx.count(&"correct"), 1)
	sfx.play(&"nope")
	check("unknown cue leaves last_cue", sfx.last_cue, &"correct")
	check("unknown cue not counted", sfx.count(&"nope"), 0)

	add_child(ui)
	var button := Button.new()
	button.position = Vector2(40, 40)
	button.size = Vector2(160, 80)
	ui.add_child(button)
	UiInputRouter.bind_button(button, _hit)
	await frames()
	sfx.reset_counts()
	await click(Vector2(100, 80))
	check("router press runs the handler once", hits, 1)
	check("router press plays one click", sfx.count(&"click"), 1)
	finish()
