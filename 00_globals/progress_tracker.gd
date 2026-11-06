extends Node

const VERSION := 1
const MAX_LIFETIME_PHRASES := 120
const MAX_DAY_PHRASES := 40
const MAX_DAY_KEYS := 14
const FLUSH_INTERVAL_SEC := 5.0

var _data: Dictionary = {}
var _dirty := false
var _flush_timer := 0.0
var _journal: CanvasLayer = null


func _ready() -> void:
	_data = _empty_progress()
	set_process(true)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_flush_timer += delta
	if _flush_timer >= FLUSH_INTERVAL_SEC:
		request_flush()


func load_from_save(progress: Dictionary) -> void:
	_data = _empty_progress()
	if progress.is_empty():
		_dirty = false
		return
	# Preserve unknown keys for future fields.
	for key in progress.keys():
		_data[key] = progress[key]
	_data["version"] = VERSION
	_data["lifetime"] = _merge_lifetime(_data.get("lifetime", {}))
	if not (_data.get("phrases") is Dictionary):
		_data["phrases"] = {}
	if not (_data.get("days") is Dictionary):
		_data["days"] = {}
	if not (_data.get("day_order") is Array):
		_data["day_order"] = []
	_data["horde_run"] = _merge_horde_run(_data.get("horde_run", {}))
	_dirty = false


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func request_flush() -> void:
	if not _dirty:
		_flush_timer = 0.0
		return
	_flush_timer = 0.0
	_dirty = false
	if SaveManager:
		SaveManager.save_game()


func mark_dirty() -> void:
	_dirty = true


func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func streak() -> int:
	var order: Array = _data.get("day_order", [])
	if order.is_empty():
		return 0
	var today := today_key()
	var start_key := today
	if not _day_is_active(today):
		var yest := _offset_day(today, -1)
		if _day_is_active(yest):
			start_key = yest
		else:
			return 0
	var count := 0
	var cursor := start_key
	while _day_is_active(cursor):
		count += 1
		cursor = _offset_day(cursor, -1)
	return count


func recent_days(n: int) -> Array:
	## Returns up to n date keys, oldest first, padded with empty trailing calendar days if needed.
	var result: Array = []
	var today := today_key()
	for i in range(n - 1, -1, -1):
		result.append(_offset_day(today, -i))
	return result


func day_stats(day_key: String) -> Dictionary:
	var days: Dictionary = _data.get("days", {})
	if days.has(day_key) and days[day_key] is Dictionary:
		return days[day_key]
	return _empty_day()


func lifetime() -> Dictionary:
	return _data.get("lifetime", _empty_lifetime())


func phrases_map(today_only: bool) -> Dictionary:
	if today_only:
		var day := day_stats(today_key())
		var p = day.get("phrases", {})
		return p if p is Dictionary else {}
	var all_p = _data.get("phrases", {})
	return all_p if all_p is Dictionary else {}


func record_phrase(phrase: String) -> void:
	phrase = phrase.strip_edges().to_lower()
	if phrase.is_empty():
		return
	var kind := "sentence" if phrase.split(" ", false).size() > 1 else "word"
	var day := today_key()
	var life: Dictionary = _data["lifetime"]
	if kind == "sentence":
		life["sentences_spoken"] = int(life.get("sentences_spoken", 0)) + 1
	else:
		life["words_spoken"] = int(life.get("words_spoken", 0)) + 1

	_bump_phrase_map(_data["phrases"], phrase, kind, day, true)
	_ensure_day(day)
	var day_dict: Dictionary = _data["days"][day]
	if kind == "sentence":
		day_dict["sentences_spoken"] = int(day_dict.get("sentences_spoken", 0)) + 1
	else:
		day_dict["words_spoken"] = int(day_dict.get("words_spoken", 0)) + 1
	if not (day_dict.get("phrases") is Dictionary):
		day_dict["phrases"] = {}
	_bump_phrase_map(day_dict["phrases"], phrase, kind, day, false)
	_enforce_phrase_cap(_data["phrases"], MAX_LIFETIME_PHRASES, true)
	_enforce_phrase_cap(day_dict["phrases"], MAX_DAY_PHRASES, false, day_dict)
	_trim_days()
	mark_dirty()


func record_kill(kind: String) -> void:
	kind = kind.to_lower()
	if kind not in ["slime", "goblin", "beetle", "other"]:
		kind = "other"
	var life: Dictionary = _data["lifetime"]
	var kills: Dictionary = life.get("kills", {})
	if not (kills is Dictionary):
		kills = {"slime": 0, "goblin": 0, "beetle": 0, "other": 0}
	kills[kind] = int(kills.get(kind, 0)) + 1
	life["kills"] = kills

	var day := today_key()
	_ensure_day(day)
	var day_dict: Dictionary = _data["days"][day]
	var day_kills: Dictionary = day_dict.get("kills", {})
	if not (day_kills is Dictionary):
		day_kills = {"slime": 0, "goblin": 0, "beetle": 0, "other": 0}
	day_kills[kind] = int(day_kills.get(kind, 0)) + 1
	day_dict["kills"] = day_kills
	_trim_days()
	mark_dirty()


func record_run_started() -> void:
	var life: Dictionary = _data["lifetime"]
	life["runs"] = int(life.get("runs", 0)) + 1
	var day := today_key()
	_ensure_day(day)
	var day_dict: Dictionary = _data["days"][day]
	day_dict["runs"] = int(day_dict.get("runs", 0)) + 1
	_trim_days()
	mark_dirty()
	request_flush()


func record_stage_reached(stage: int) -> void:
	stage = maxi(stage, 0)
	var life: Dictionary = _data["lifetime"]
	life["best_stage"] = maxi(int(life.get("best_stage", 0)), stage)
	var day := today_key()
	_ensure_day(day)
	var day_dict: Dictionary = _data["days"][day]
	day_dict["best_stage"] = maxi(int(day_dict.get("best_stage", 0)), stage)
	_trim_days()
	mark_dirty()


func record_stage_cleared(stage: int) -> void:
	stage = maxi(stage, 0)
	var life: Dictionary = _data["lifetime"]
	life["stages_cleared"] = int(life.get("stages_cleared", 0)) + 1
	life["best_stage"] = maxi(int(life.get("best_stage", 0)), stage)
	var day := today_key()
	_ensure_day(day)
	var day_dict: Dictionary = _data["days"][day]
	day_dict["stages_cleared"] = int(day_dict.get("stages_cleared", 0)) + 1
	day_dict["best_stage"] = maxi(int(day_dict.get("best_stage", 0)), stage)
	_trim_days()
	note_stage_cleared(stage)
	mark_dirty()
	request_flush()


func record_horde_death(stage: int) -> void:
	stage = maxi(stage, 1)
	var run := _horde_run()
	if int(run.get("stuck_stage", 0)) != stage:
		run["stuck_stage"] = stage
		run["deaths_on_stage"] = 1
	else:
		run["deaths_on_stage"] = int(run.get("deaths_on_stage", 0)) + 1
	run["resume_stage"] = stage
	run["short_retry"] = true
	run["warmup"] = int(run["deaths_on_stage"]) >= 3
	_data["horde_run"] = run
	mark_dirty()


func note_stage_cleared(stage: int) -> void:
	var run := _horde_run()
	if int(run.get("stuck_stage", 0)) != stage:
		return
	run["resume_stage"] = 0
	run["stuck_stage"] = 0
	run["deaths_on_stage"] = 0
	run["short_retry"] = false
	run["warmup"] = false
	_data["horde_run"] = run


func horde_resume_stage() -> int:
	return int(_horde_run().get("resume_stage", 0))


func horde_stuck_stage() -> int:
	return int(_horde_run().get("stuck_stage", 0))


func horde_short_retry() -> bool:
	return bool(_horde_run().get("short_retry", false))


func horde_warmup() -> bool:
	return bool(_horde_run().get("warmup", false))


func show_journal() -> void:
	if _journal == null:
		var packed := load("res://gui/progress_journal/progress_journal.tscn") as PackedScene
		if packed == null:
			print("❌ ProgressTracker: journal scene missing")
			return
		_journal = packed.instantiate()
		add_child(_journal)
	if _journal.has_method("open"):
		_journal.open()
	else:
		_journal.visible = true


func hide_journal() -> void:
	if _journal == null:
		return
	if _journal.has_method("close"):
		_journal.close()
	else:
		_journal.visible = false
	request_flush()


func is_journal_open() -> bool:
	return _journal != null and _journal.visible


# --- internals ---

func _empty_progress() -> Dictionary:
	return {
		"version": VERSION,
		"lifetime": _empty_lifetime(),
		"phrases": {},
		"days": {},
		"day_order": [],
		"horde_run": _empty_horde_run(),
	}


func _empty_horde_run() -> Dictionary:
	return {
		"resume_stage": 0,
		"stuck_stage": 0,
		"deaths_on_stage": 0,
		"short_retry": false,
		"warmup": false,
	}


func _merge_horde_run(raw) -> Dictionary:
	var base := _empty_horde_run()
	if not (raw is Dictionary):
		return base
	for key in base.keys():
		if raw.has(key):
			base[key] = raw[key]
	return base


func _horde_run() -> Dictionary:
	var run = _data.get("horde_run", {})
	if not (run is Dictionary):
		run = _empty_horde_run()
		_data["horde_run"] = run
	else:
		# Fill missing fields without dropping extras.
		var merged := _merge_horde_run(run)
		for key in run.keys():
			if not merged.has(key):
				merged[key] = run[key]
		_data["horde_run"] = merged
		run = merged
	return run


func _empty_lifetime() -> Dictionary:
	return {
		"runs": 0,
		"stages_cleared": 0,
		"best_stage": 0,
		"words_spoken": 0,
		"sentences_spoken": 0,
		"kills": {"slime": 0, "goblin": 0, "beetle": 0, "other": 0},
		"collapsed_words": 0,
		"collapsed_sentences": 0,
	}


func _empty_day() -> Dictionary:
	return {
		"runs": 0,
		"stages_cleared": 0,
		"best_stage": 0,
		"words_spoken": 0,
		"sentences_spoken": 0,
		"kills": {"slime": 0, "goblin": 0, "beetle": 0, "other": 0},
		"phrases": {},
	}


func _merge_lifetime(raw) -> Dictionary:
	var base := _empty_lifetime()
	if not (raw is Dictionary):
		return base
	for key in base.keys():
		if raw.has(key):
			base[key] = raw[key]
	if not (base.get("kills") is Dictionary):
		base["kills"] = {"slime": 0, "goblin": 0, "beetle": 0, "other": 0}
	return base


func _ensure_day(day: String) -> void:
	var days: Dictionary = _data["days"]
	if not days.has(day) or not (days[day] is Dictionary):
		days[day] = _empty_day()
	var order: Array = _data["day_order"]
	if not order.has(day):
		order.append(day)
	_data["day_order"] = order


func _day_is_active(day: String) -> bool:
	var days: Dictionary = _data.get("days", {})
	if not days.has(day) or not (days[day] is Dictionary):
		return false
	var d: Dictionary = days[day]
	return int(d.get("words_spoken", 0)) + int(d.get("sentences_spoken", 0)) + int(d.get("stages_cleared", 0)) > 0


func _offset_day(day_key: String, offset: int) -> String:
	# Parse YYYY-MM-DD and shift by offset days using unix time at noon UTC.
	var parts := day_key.split("-")
	if parts.size() != 3:
		return day_key
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 12,
		"minute": 0,
		"second": 0,
	})
	unix += offset * 86400
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


func _bump_phrase_map(map: Dictionary, phrase: String, kind: String, day: String, _lifetime: bool) -> void:
	var entry: Dictionary
	if map.has(phrase) and map[phrase] is Dictionary:
		entry = map[phrase]
		entry["count"] = int(entry.get("count", 0)) + 1
		entry["kind"] = kind
		entry["last_day"] = day
	else:
		entry = {"count": 1, "kind": kind, "last_day": day}
	map[phrase] = entry


func _enforce_phrase_cap(map: Dictionary, cap: int, is_lifetime: bool, day_dict: Dictionary = {}) -> void:
	while map.size() > cap:
		var drop_key := ""
		var drop_count := 0x7fffffff
		var drop_day := "9999-99-99"
		for key in map.keys():
			var entry = map[key]
			if not (entry is Dictionary):
				continue
			var c := int(entry.get("count", 0))
			var ld := str(entry.get("last_day", "9999-99-99"))
			if c < drop_count or (c == drop_count and ld < drop_day):
				drop_count = c
				drop_day = ld
				drop_key = str(key)
		if drop_key.is_empty():
			break
		var removed = map[drop_key]
		map.erase(drop_key)
		var kind := "word"
		var count := 0
		if removed is Dictionary:
			kind = str(removed.get("kind", "word"))
			count = int(removed.get("count", 0))
		if is_lifetime:
			var life: Dictionary = _data["lifetime"]
			if kind == "sentence":
				life["collapsed_sentences"] = int(life.get("collapsed_sentences", 0)) + count
			else:
				life["collapsed_words"] = int(life.get("collapsed_words", 0)) + count
		elif not day_dict.is_empty():
			# Day collapse: utterance totals already counted; nothing else required.
			pass


func _trim_days() -> void:
	var order: Array = _data["day_order"]
	var days: Dictionary = _data["days"]
	while order.size() > MAX_DAY_KEYS:
		var oldest = order[0]
		order.remove_at(0)
		days.erase(oldest)
	_data["day_order"] = order
