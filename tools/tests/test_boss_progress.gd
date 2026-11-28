extends Node
## Boss victory bookkeeping in ProgressTracker. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_boss_progress.tscn
## Review Focus 5: no stale resume_stage after a victory; deaths unchanged.
## Review Focus 6: old saves without the boss fields still load.

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
	var saved: Dictionary = ProgressTracker.snapshot()
	var t := ProgressTracker

	t.load_from_save({"version": 1, "horde_run": {"resume_stage": 7}})
	_check("old save: resume kept", t.horde_resume_stage() == 7)
	_check("old save: no boss cleared", t.boss_cleared_stage() == 0)
	_check("old save: no reward pending", t.boss_reward_pending() == 0)

	t.load_from_save({})
	t.record_horde_death(20)
	t.record_horde_death(20)
	_check("two deaths arm warm-up", t.horde_warmup() and t.horde_short_retry())
	t.record_stage_cleared(20)
	t.record_boss_cleared(20)
	_check("victory resumes at 21", t.horde_resume_stage() == 21, str(t.horde_resume_stage()))
	_check("victory clears stuck stage", t.horde_stuck_stage() == 0)
	_check("victory clears short retry", not t.horde_short_retry())
	_check("victory clears warm-up", not t.horde_warmup())
	_check("boss 20 recorded", t.boss_cleared_stage() == 20)
	_check("reward 20 pending", t.boss_reward_pending() == 20)
	_check("first claim returns 20", t.claim_boss_reward() == 20)
	_check("second claim returns 0", t.claim_boss_reward() == 0)

	t.record_boss_cleared(40)
	var snap: Dictionary = t.snapshot()
	t.load_from_save(snap)
	_check("round trip keeps pending reward", t.boss_reward_pending() == 40)
	_check("round trip keeps best boss", t.boss_cleared_stage() == 40)
	t.record_stage_cleared(41)
	_check("clearing the resume stage resets it", t.horde_resume_stage() == 0, str(t.horde_resume_stage()))

	t.record_boss_cleared(0)
	_check("bad stage changes nothing", t.boss_reward_pending() == 40 and t.boss_cleared_stage() == 40)
	t.record_boss_cleared(20)
	_check("best boss never goes down", t.boss_cleared_stage() == 40)

	t.load_from_save({})
	t.record_horde_death(20)
	_check("death on boss stage resumes at 20", t.horde_resume_stage() == 20)
	t.record_stage_cleared(20)
	_check("death then clear resets resume", t.horde_resume_stage() == 0)
	_check("death then clear resets stuck", t.horde_stuck_stage() == 0)

	t.load_from_save(saved)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
