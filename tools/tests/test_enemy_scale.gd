extends Node2D
## Enemies are drawn at least as big as the hero: humanoids ~1.25x, orcs 1.5x,
## critters 1.15x; bosses stay 2x and their adds come out at critter size.
## AI vision range and the health bar keep their on-screen size.

const SCENES := {
	"bandit": ["res://enemies/bandit/bandit.tscn", 1.25],
	"skeleton": ["res://enemies/skeleton/skeleton.tscn", 1.25],
	"goblin": ["res://enemies/goblin/goblin.tscn", 1.25],
	"orc": ["res://enemies/orc/orc.tscn", 1.5],
	"slime": ["res://enemies/slime/slime.tscn", 1.15],
	"beetle": ["res://enemies/beetle/beetle.tscn", 1.15],
}

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _spawn(path: String) -> Enemy:
	var e: Enemy = load(path).instantiate()
	e.global_position = Vector2(4000, 4000)
	add_child(e)
	return e


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	for kind in SCENES:
		var path: String = SCENES[kind][0]
		var want: float = SCENES[kind][1]
		var e := _spawn(path)
		await get_tree().process_frame
		_check("%s drawn at %.2fx" % [kind, want], _near(e.global_scale.x, want), str(e.global_scale))
		_check("%s health bar stays 1x" % kind, _near(e.health_bar.global_scale.x, 1.0), str(e.health_bar.global_scale))
		var vision := e.get_node_or_null("VisionArea") as Node2D
		if vision:
			_check("%s vision range unchanged" % kind, _near(vision.global_scale.x, 1.0), str(vision.global_scale))
		e.queue_free()

	# Bosses: still 2x; adds land at the slime's own size.
	var boss := load("res://enemies/slime/slime.tscn").instantiate() as Enemy
	boss.make_boss(HordeCurve.BOSSES[0], 4)
	boss.global_position = Vector2(4000, 4000)
	add_child(boss)
	await get_tree().process_frame
	_check("boss stays 2x", _near(boss.global_scale.x, HordeCurve.BOSS_SCALE), str(boss.global_scale))
	_check("boss adds come out at 1.15x", _near(boss.global_scale.x * boss.split_scale, 1.15),
		str(boss.global_scale.x * boss.split_scale))
	boss.queue_free()

	# A beetle's split children: parent scale x split_scale, not scaled twice.
	var beetle := _spawn("res://enemies/beetle/beetle.tscn")
	await get_tree().process_frame
	var before := get_children().size()
	beetle.spawn_split_children()
	await get_tree().process_frame
	var kids: Array = []
	for c in get_children():
		if c is Enemy and c != beetle and not c.is_queued_for_deletion():
			kids.append(c)
	if kids.size() > 0:
		var k: Enemy = kids[0]
		_check("split child = 1.15 x 0.65", _near(k.global_scale.x, 1.15 * 0.65), str(k.global_scale))
	else:
		_check("split children spawned", get_children().size() > before, "no split method")

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
