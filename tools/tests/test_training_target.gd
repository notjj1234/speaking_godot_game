extends Node2D
## Training targets: a slime that stands still and can't hurt you, but keeps
## real HP, so knocking it down starts the normal speech challenge.

const SLIME := "res://enemies/slime/slime.tscn"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	var stt := get_node("/root/STTManager")
	var old_provider = stt.provider
	stt.provider = FakeStt.new()
	PlayerManager.player.global_position = Vector2(1200, 1000)

	var e: Enemy = load(SLIME).instantiate()
	e.hp = 2
	add_child(e)
	e.global_position = Vector2(1000, 1000)
	e.make_training_target()
	var start := e.global_position
	await _wait(0.5)
	_check("target does not move", e.global_position.distance_to(start) < 1.0,
		"moved %.1f" % e.global_position.distance_to(start))
	var hurt := e.get_node("HurtBox")
	_check("target hurtbox harmless", int(hurt.damage) == 0 and not hurt.monitoring)
	_check("not a practice dummy", not e.practice_dummy)

	var destroyed := [false]
	e.enemy_destroyed.connect(func(_hb): destroyed[0] = true)
	var hit := HurtBox.new()
	hit.damage = 1
	add_child(hit)
	e._take_damage(hit)
	await _wait(0.6)
	_check("one hit leaves it standing", e.hp == 1 and not get_node("/root/WordTracker").speech_challenge_active)
	e._take_damage(hit)
	await _wait(0.3)
	var wt := get_node("/root/WordTracker")
	_check("second hit starts a challenge", wt.speech_challenge_active)
	var challenge: String = PlayerHud.target_sentence
	stt.listening_completed.emit(challenge)
	await _wait(1.5)
	_check("correct answer destroys it", destroyed[0], "challenge='%s'" % challenge)

	get_tree().paused = false
	stt.provider = old_provider
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
