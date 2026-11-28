extends Node
## Boss stages: detection, roster, phase bands, rewards (HordeCurve) and the
## band override on the stage challenge picker (WordTracker). Run headless on a
## scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_boss_curve.tscn

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_detection()
	_test_roster()
	_test_phases_and_rewards()
	_test_band_override()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_detection() -> void:
	for s in [0, 1, 19, 21]:
		_check("stage %d is not a boss stage" % s, not HordeCurve.is_boss_stage(s))
	for s in [20, 40, 100]:
		_check("stage %d is a boss stage" % s, HordeCurve.is_boss_stage(s))
	var king := HordeCurve.boss_for_stage(20)
	_check("Slime King adds use the minion sheet", str(king.get("add_sheet", "")).ends_with("slime_minion.png"),
			str(king.get("add_sheet", "")))
	_check("Slime King adds chase", king.get("add_chase", false) == true)
	for s in [40, 60, 80]:
		var other := HordeCurve.boss_for_stage(s)
		_check("stage %d boss has no add sheet or chase" % s, not other.has("add_sheet") and not other.has("add_chase"))
	_check("boss quota is 1", HordeCurve.retry_quota(20, false) == 1, str(HordeCurve.retry_quota(20, false)))
	_check("boss short-retry quota is 1", HordeCurve.retry_quota(20, true) == 1)
	_check("stage 19 quota unchanged", HordeCurve.retry_quota(19, false) == HordeCurve.spawn_total(19))


func _test_roster() -> void:
	_check("stage 20 boss kind slime", HordeCurve.kind_for(20, 0) == "slime", HordeCurve.kind_for(20, 0))
	_check("stage 40 boss kind skeleton", HordeCurve.kind_for(40, 3) == "skeleton", HordeCurve.kind_for(40, 3))
	_check("stage 60 boss kind orc", HordeCurve.kind_for(60, 0) == "orc", HordeCurve.kind_for(60, 0))
	_check("stage 80 boss kind bandit", HordeCurve.kind_for(80, 0) == "bandit", HordeCurve.kind_for(80, 0))
	_check("stage 100 repeats slime", HordeCurve.kind_for(100, 0) == "slime", HordeCurve.kind_for(100, 0))
	_check("stage 19 kind unchanged", HordeCurve.kind_for(19, 0) == "beetle", HordeCurve.kind_for(19, 0))
	_check("no boss on stage 19", HordeCurve.boss_for_stage(19).is_empty())
	_check("stage 20 boss is the Slime King", str(HordeCurve.boss_for_stage(20).get("name", "")) == "Slime King")
	for s in [20, 40, 60, 80]:
		_check("stage %d boss matches its arena" % s,
				HordeCurve.BOSSES.find(HordeCurve.boss_for_stage(s)) == HordeCurve.arena_index_for(s))
	for boss in HordeCurve.BOSSES:
		var boss_name := str(boss.get("name", ""))
		var ascii := not boss_name.is_empty()
		for i in boss_name.length():
			if boss_name.unicode_at(i) >= 128:
				ascii = false
		_check("boss name is ASCII: %s" % boss_name, ascii)


func _test_phases_and_rewards() -> void:
	_check("phase 0 band 2", HordeCurve.boss_phase_band(0) == 2)
	_check("phase 1 band 3", HordeCurve.boss_phase_band(1) == 3)
	_check("phase 2 band 3", HordeCurve.boss_phase_band(2) == 3)
	_check("phase 9 clamps to band 3", HordeCurve.boss_phase_band(9) == 3)
	_check("reward stage 20 is 10", HordeCurve.boss_reward_gems(20) == 10, str(HordeCurve.boss_reward_gems(20)))
	_check("reward stage 40 is 15", HordeCurve.boss_reward_gems(40) == 15, str(HordeCurve.boss_reward_gems(40)))
	_check("reward stage 100 is 30", HordeCurve.boss_reward_gems(100) == 30, str(HordeCurve.boss_reward_gems(100)))
	_check("no reward off a boss stage", HordeCurve.boss_reward_gems(19) == 0)
	_check("stage 20 phase bar is 10", HordeCurve.boss_phase_hp(20) == 10, str(HordeCurve.boss_phase_hp(20)))
	_check("phase bar floor is 4", HordeCurve.boss_phase_hp(1) >= 4)


func _bands_of(stage: int, band_override: int, samples: int) -> Array:
	var seen := []
	for i in samples:
		var picked: String = WordTracker.get_speech_challenge_for_stage(stage, band_override)
		var band: int = WordTracker._band_of_phrase(picked)
		if not seen.has(band):
			seen.append(band)
	return seen


func _test_band_override() -> void:
	var saved: Dictionary = ProgressTracker.snapshot()
	ProgressTracker.load_from_save({})
	var bands := _bands_of(20, 2, 10)
	_check("override picks band 2", bands == [2], str(bands))
	ProgressTracker.record_horde_death(20)
	ProgressTracker.record_horde_death(20)
	bands = _bands_of(20, 2, 10)
	_check("warm-up lowers the override to band 1", bands == [1], str(bands))
	bands = _bands_of(20, -1, 10)
	_check("no override under warm-up is band 2 (unchanged)", bands == [2], str(bands))
	ProgressTracker.load_from_save(saved)
