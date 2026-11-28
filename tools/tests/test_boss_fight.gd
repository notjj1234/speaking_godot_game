extends Node2D
## A boss fight through the real speech-challenge path (fake STT transcripts).
## Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_boss_fight.tscn
## Review Focus 1: a non-final phase pass never emits enemy_destroyed.
## Review Focus 2: the phase grace stops a hit from chaining into the next challenge.

const SLIME := "res://enemies/slime/slime.tscn"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")

var passes := 0
var failures := 0
var destroyed := 0
var phase_events: Array = []


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _enemy_children() -> int:
	return get_children().filter(func(c): return c is Enemy and not c.is_queued_for_deletion()).size()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	var saved_provider = STTManager.provider
	STTManager.provider = FakeStt.new()
	var saved_progress: Dictionary = ProgressTracker.snapshot()
	ProgressTracker.load_from_save({})
	WordTracker.horde_stage = 20
	var killer := HurtBox.new()
	killer.damage = 99
	add_child(killer)

	await _test_boss(killer)
	await _test_plain_enemy(killer)
	await _test_boss_art()

	WordTracker.horde_stage = 0
	ProgressTracker.load_from_save(saved_progress)
	STTManager.provider = saved_provider
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


## Each boss draws its own sheet at 2x resolution on a child sprite, so the
## boss is twice the size on screen while every art pixel is one screen pixel,
## like the player (tools/art_build/style_check.py).
func _test_boss_art() -> void:
	var scenes := {"slime": SLIME, "skeleton": "res://enemies/skeleton/skeleton.tscn",
			"orc": "res://enemies/orc/orc.tscn", "bandit": "res://enemies/bandit/bandit.tscn"}
	for stage in [20, 40, 60, 80]:
		var profile := HordeCurve.boss_for_stage(stage)
		var who := str(profile.get("name"))
		var sheet := str(profile.get("sheet", ""))
		_check(who + ": sheet exists", sheet != "" and ResourceLoader.exists(sheet), sheet)
		var boss: Enemy = load(scenes[profile.get("kind")]).instantiate()
		boss.make_boss(profile, 10)
		add_child(boss)
		boss.global_position = Vector2(3000 + stage * 10, 3000)
		await get_tree().physics_frame
		var art := boss.get_node_or_null("Sprite2D/BossSprite") as Sprite2D
		_check(who + ": boss sprite attached", art != null)
		if art == null:
			boss.queue_free()
			continue
		var base := boss.sprite
		_check(who + ": draws its own sheet", art.texture != null and art.texture.resource_path == sheet,
				art.texture.resource_path if art.texture else "none")
		var net := absf(boss.scale.x * base.scale.x * art.scale.x)
		_check(who + ": one art pixel per screen pixel", is_equal_approx(net, 1.0), str(net))
		_check(who + ": same frame layout", art.hframes == base.hframes and art.vframes == base.vframes,
				"%dx%d vs %dx%d" % [art.hframes, art.vframes, base.hframes, base.vframes])
		var base_w := base.texture.get_width() / base.hframes
		var art_w := art.texture.get_width() / art.hframes
		_check(who + ": frames drawn at 2x resolution", art_w == base_w * 2, "%d vs %d" % [art_w, base_w])
		_check(who + ": base art hidden", is_zero_approx(base.self_modulate.a))
		base.frame = 5
		_check(who + ": follows the animation frame", art.frame == 5, str(art.frame))
		boss.queue_free()
	await get_tree().physics_frame


func _pass_challenge() -> void:
	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	await _wait(0.7)


func _test_boss(killer: HurtBox) -> void:
	var boss: Enemy = load(SLIME).instantiate()
	boss.make_boss(HordeCurve.boss_for_stage(20), 10)
	add_child(boss)
	boss.global_position = Vector2(2000, 2000)
	var destroy := boss.get_node("EnemyStateMachine/Destroy")
	var no_drops: Array[DropData] = []
	destroy.set("drops", no_drops)
	boss.enemy_destroyed.connect(func(_h): destroyed += 1)
	boss.boss_phase_changed.connect(func(p, n): phase_events.append([p, n]))
	var chase := boss.get_node("EnemyStateMachine/Chase")
	var chase_before := float(chase.get("chase_speed"))
	var kills_before := int(ProgressTracker.lifetime().kills.get("slime", 0))
	await get_tree().physics_frame

	_check("boss is a boss", boss.is_boss())
	_check("boss at whole-number 2x scale", boss.scale == Vector2(2, 2), str(boss.scale))
	_check("boss bar is the phase hp", boss.max_hp == 10, str(boss.max_hp))
	_check("boss bar reads Phase 1/3", boss.health_bar.get_display_text() == "Phase 1/3",
			boss.health_bar.get_display_text())
	_check("boss art is not tinted", boss.sprite.modulate.is_equal_approx(Color.WHITE), str(boss.sprite.modulate))

	Sfx.reset_counts()
	boss._take_damage(killer)
	_check("phase 1 challenge started", WordTracker.speech_challenge_active and get_tree().paused)
	# The fake provider never starts audio; drive its listening_started like a device would.
	STTManager.listening_started.emit()
	await get_tree().process_frame
	_check("sound: challenge start pings listen", Sfx.count(&"listen") >= 1, str(Sfx.count(&"listen")))
	var pings := Sfx.count(&"listen")
	PlayerHud.set_stt_state(PlayerHudUI.SttState.STT_LISTENING)
	PlayerHud.set_stt_state(PlayerHudUI.SttState.STT_LISTENING)
	_check("sound: still listening adds no ping", Sfx.count(&"listen") == pings, str(Sfx.count(&"listen")))
	# Web restarts the recognizer on silence: stop/start cycles must stay quiet.
	STTManager.listening_stopped.emit()
	STTManager.listening_started.emit()
	_check("sound: silent restart adds no ping", Sfx.count(&"listen") == pings, str(Sfx.count(&"listen")))
	_check("challenge card names the boss phase", PlayerHud.challenge_title_label.visible
			and PlayerHud.challenge_title_label.text == "Slime King - phase 1/3", PlayerHud.challenge_title_label.text)
	_check("phase 1 phrase is band 2", WordTracker._band_of_phrase(PlayerHud.target_sentence) == 2,
			PlayerHud.target_sentence)
	var enemies_before := _enemy_children()
	await _pass_challenge()
	_check("sound: pass plays correct once", Sfx.count(&"correct") == 1, str(Sfx.count(&"correct")))
	_check("phase pass: boss alive", is_instance_valid(boss) and not boss.is_queued_for_deletion())
	_check("phase pass: no enemy_destroyed", destroyed == 0, str(destroyed))
	_check("phase pass: phase advanced", boss.boss_phase == 1, str(boss.boss_phase))
	_check("phase pass: bar refilled", boss.hp == boss.max_hp, "%d/%d" % [boss.hp, boss.max_hp])
	_check("phase pass: bar reads Phase 2/3", boss.health_bar.get_display_text() == "Phase 2/3",
			boss.health_bar.get_display_text())
	_check("phase pass: two pips left", boss.health_bar.phases_left() == 2, str(boss.health_bar.phases_left()))
	_check("phase pass: phase sound", Sfx.count(&"phase") == 1, str(Sfx.count(&"phase")))
	_check("phase pass: centre notice", PlayerHud.last_notice == "Slime King hit! Phase 2/3", PlayerHud.last_notice)
	_check("phase pass: signal (2, 3)", phase_events == [[2, 3]], str(phase_events))
	_check("phase pass: game resumed", not get_tree().paused and not WordTracker.speech_challenge_active)
	_check("phase pass: colour restored after flash", boss.sprite.modulate.is_equal_approx(Color.WHITE),
			str(boss.sprite.modulate))
	_check("phase pass: Slime King spawned 2 adds", _enemy_children() == enemies_before + 2,
			"%d -> %d" % [enemies_before, _enemy_children()])
	_check("phase pass: tune applied", is_equal_approx(float(chase.get("chase_speed")), chase_before * 1.15),
			"%s -> %s" % [chase_before, chase.get("chase_speed")])
	_check("phase pass: kill not recorded yet",
			int(ProgressTracker.lifetime().kills.get("slime", 0)) == kills_before)

	_check("grace: invulnerable", boss.invulnerable)
	boss._take_damage(killer)
	_check("grace: a hit starts no challenge", not WordTracker.speech_challenge_active)
	await _wait(1.0)
	_check("grace: ends", not boss.invulnerable)
	await _check_minions(boss)

	boss._take_damage(killer)
	_check("phase 2 phrase is band 3", WordTracker._band_of_phrase(PlayerHud.target_sentence) == 3,
			PlayerHud.target_sentence)
	for i in 3:
		STTManager.listening_completed.emit("zzzz wrong")
		await _wait(0.1)
	await _wait(2.5)
	_check("sound: misses play wrong", Sfx.count(&"wrong") >= 2, str(Sfx.count(&"wrong")))
	_check("sound: out of tries plays error", Sfx.count(&"error") >= 1, str(Sfx.count(&"error")))
	_check("out of tries: phase kept", boss.boss_phase == 1, str(boss.boss_phase))
	_check("out of tries: current bar refilled", boss.hp == boss.max_hp, "%d/%d" % [boss.hp, boss.max_hp])
	_check("out of tries: not destroyed", destroyed == 0)
	_check("out of tries: game resumed", not get_tree().paused)

	boss._take_damage(killer)
	await _pass_challenge()
	_check("phase 2 pass: phase 3", boss.boss_phase == 2 and phase_events.size() == 2, str(phase_events))
	await _wait(1.3)
	boss._take_damage(killer)
	_check("phase 3 phrase is band 3", WordTracker._band_of_phrase(PlayerHud.target_sentence) == 3,
			PlayerHud.target_sentence)
	await _pass_challenge()
	_check("final pass: enemy_destroyed once", destroyed == 1, str(destroyed))
	_check("final pass: kill recorded once",
			int(ProgressTracker.lifetime().kills.get("slime", 0)) == kills_before + 1)
	await _wait(1.5)
	for child in get_children():
		if child is Enemy:
			child.queue_free()
	await get_tree().process_frame


func _test_plain_enemy(killer: HurtBox) -> void:
	var plain: Enemy = load(SLIME).instantiate()
	add_child(plain)
	plain.global_position = Vector2(3000, 3000)
	var count := {"n": 0}
	plain.enemy_destroyed.connect(func(_h): count["n"] += 1)
	await get_tree().physics_frame
	_check("plain enemy is not a boss", not plain.is_boss())
	plain._take_damage(killer)
	_check("plain enemy: no challenge title", not PlayerHud.challenge_title_label.visible)
	_check("plain enemy: bar shows hp", not plain.health_bar.get_display_text().begins_with("Phase"))
	await _pass_challenge()
	_check("plain enemy destroyed on first pass", count["n"] == 1, str(count["n"]))


## Slime King adds: their own royal sheet, and they chase the player.
func _check_minions(boss: Enemy) -> void:
	var adds := get_children().filter(func(c): return c is Enemy and c != boss and not c.is_queued_for_deletion())
	_check("minions: two adds", adds.size() == 2, str(adds.size()))
	if adds.is_empty():
		return
	var add: Enemy = adds[0]
	var tex := add.sprite.texture
	_check("minions: royal sheet", tex != null and tex.resource_path.ends_with("slime_minion.png"),
			tex.resource_path if tex else "none")
	_check("minions: same frame layout", add.sprite.hframes == 16 and add.sprite.vframes == 2)
	_check("minions: net scale 1.0", is_equal_approx(add.scale.x, 1.0), str(add.scale))
	PlayerManager.set_as_parent(self)
	var target: Node2D = PlayerManager.player
	target.global_position = add.global_position + Vector2(200, 0)
	await _wait(0.3)
	_check("minions: chasing", add.state_machine.current_state is EnemyStateChase,
			str(add.state_machine.current_state))
	var before := add.global_position.distance_to(target.global_position)
	await _wait(1.0)
	var after := add.global_position.distance_to(target.global_position)
	_check("minions: close in on the player", after < before - 10.0, "%.1f -> %.1f" % [before, after])
	var stun := add.get_node("EnemyStateMachine/Stun")
	add.state_machine.change_state(stun)
	await _wait(1.5)
	_check("minions: back to chase after a stun", add.state_machine.current_state is EnemyStateChase,
			str(add.state_machine.current_state))
	PlayerManager.unparent_player(self)
