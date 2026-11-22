extends CanvasLayer

const HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

## Skill identity: display name, distinctive label color, the spoken keyword
## the player must say to confirm an upgrade, and accepted synonyms.
const SKILLS := {
	"vitality": {"name": "Vitality", "color": Color(0.85, 0.25, 0.25), "say": "vitality", "accept": ["hp"]},
	"might": {"name": "Might", "color": Color(0.95, 0.55, 0.2), "say": "might", "accept": ["attack"]},
	"haste": {"name": "Haste", "color": Color(0.35, 0.75, 0.95), "say": "haste", "accept": ["speed"]},
	"crit": {"name": "Crit", "color": Color(0.98, 0.9, 0.45), "say": "crit", "accept": ["critical"]},
}

var _busy := false
var _navigating := false
var _master_was_muted := false
var _listening_stat := ""

@onready var vitality_label: Label = %VitalityLabel
@onready var might_label: Label = %MightLabel
@onready var haste_label: Label = %HasteLabel
@onready var crit_label: Label = %CritLabel
@onready var points_label: Label = %PointsLabel
@onready var feedback: Label = %Feedback
@onready var vitality_button: Button = %VitalityButton
@onready var might_button: Button = %MightButton
@onready var haste_button: Button = %HasteButton
@onready var crit_button: Button = %CritButton
@onready var equip_button: Button = %EquipButton
@onready var resume_stage_label: Label = %ResumeStageLabel
@onready var continue_button: Button = %ContinueButton
@onready var journal_button: Button = %JournalButton
@onready var title_button: Button = %TitleButton
@onready var avatar_weapon: Sprite2D = %AvatarWeapon
@onready var touch_vitality: TouchScreenButton = %TouchVitality
@onready var touch_might: TouchScreenButton = %TouchMight
@onready var touch_haste: TouchScreenButton = %TouchHaste
@onready var touch_crit: TouchScreenButton = %TouchCrit
@onready var touch_equip: TouchScreenButton = %TouchEquip
@onready var touch_continue: TouchScreenButton = %TouchContinue
@onready var touch_journal: TouchScreenButton = %TouchJournal
@onready var touch_title: TouchScreenButton = %TouchTitle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	_bind(vitality_button, touch_vitality, _on_vitality)
	_bind(might_button, touch_might, _on_might)
	_bind(haste_button, touch_haste, _on_haste)
	_bind(crit_button, touch_crit, _on_crit)
	_bind(equip_button, touch_equip, _on_equip)
	_bind(continue_button, touch_continue, _on_continue)
	_bind(journal_button, touch_journal, _on_journal)
	_bind(title_button, touch_title, _on_title)


func show_rest() -> void:
	if visible:
		return
	_cancel_upgrade_listen()
	_busy = false
	_navigating = false
	_silence_all()
	var pause := get_node_or_null("/root/PauseMenu")
	if pause and pause.visible:
		pause.visible = false
		pause.is_paused = false
	visible = true
	get_tree().paused = true
	set_process(true)
	PlayerManager.convert_gems_to_points()
	PlayerManager.set_health(PlayerManager.horde_max_hp(), PlayerManager.horde_max_hp())
	_refresh()
	_apply_resume_copy()
	SaveManager.save_game()
	continue_button.grab_focus()


func _process(_delta: float) -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	_align(vitality_button, touch_vitality)
	_align(might_button, touch_might)
	_align(haste_button, touch_haste)
	_align(crit_button, touch_crit)
	_align(equip_button, touch_equip)
	_align(continue_button, touch_continue)
	_align(journal_button, touch_journal)
	_align(title_button, touch_title)


func _bind(button: Button, touch: TouchScreenButton, handler: Callable) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(handler)
	touch.pressed.connect(handler)
	touch.visible = true


func _align(button: Button, touch: TouchScreenButton) -> void:
	if button == null or touch == null:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _refresh() -> void:
	points_label.text = "Gems: %d" % PlayerManager.bonfire_points
	_set_row(vitality_label, vitality_button, "vitality")
	_set_row(might_label, might_button, "might")
	_set_row(haste_label, haste_button, "haste")
	_set_row(crit_label, crit_button, "crit")
	var owned := PlayerManager.has_sword()
	equip_button.disabled = not owned
	if PlayerManager.sword_equipped:
		equip_button.text = "Unequip sword"
	else:
		equip_button.text = "Equip sword"
	avatar_weapon.visible = PlayerManager.sword_equipped


func _set_row(label: Label, button: Button, stat: String) -> void:
	var info: Dictionary = SKILLS[stat]
	var rank := int(PlayerManager.get("%s_rank" % stat))
	var capped := (stat == "haste" and rank >= PlayerManager.HASTE_MAX) \
			or (stat == "crit" and rank >= PlayerManager.CRIT_MAX)
	label.add_theme_color_override("font_color", info["color"])
	var title: String = info["name"]
	if stat == "crit":
		title = "%s  %d%%" % [info["name"], int(round(PlayerManager.crit_chance() * 100.0))]
	if capped:
		label.text = "%s  rank %d  maxed" % [title, rank]
		button.disabled = true
		button.text = "Max"
		return
	# ASCII only: the bonfire pixel font has no glyphs for → — …
	label.text = "%s  rank %d -> %d  (%d gems)  - say \"%s\"" \
			% [title, rank, rank + 1, PlayerManager.upgrade_cost(stat), info["say"]]
	button.disabled = false
	button.text = "Upgrade"


func _on_vitality() -> void:
	_request_upgrade("vitality")


func _on_might() -> void:
	_request_upgrade("might")


func _on_haste() -> void:
	_request_upgrade("haste")


func _on_crit() -> void:
	_request_upgrade("crit")


func _stat_controls(stat: String) -> Array:
	match stat:
		"vitality":
			return [vitality_button, touch_vitality]
		"might":
			return [might_button, touch_might]
		"haste":
			return [haste_button, touch_haste]
		_:
			return [crit_button, touch_crit]


func _say_word(stat: String) -> String:
	return SKILLS[stat]["say"]


func _request_upgrade(stat: String) -> void:
	if _busy or _navigating:
		return
	if _listening_stat != "":
		# Pressing the listening row again cancels the confirmation.
		if _listening_stat == stat:
			_cancel_upgrade_listen("Cancelled.")
		return
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		# Windows / no mic provider: don't lock the player out of upgrades.
		_spend(stat)
		if feedback.text == "Upgraded.":
			feedback.text = "Upgraded. (voice unavailable)"
		return
	_listening_stat = stat
	var controls := _stat_controls(stat)
	(controls[0] as Button).text = "Listening... say \"%s\"" % _say_word(stat)
	for other in SKILLS.keys():
		if other == stat:
			continue
		# No disabled state on TouchScreenButton twins — the handler guard in
		# _request_upgrade already ignores presses on other rows while listening.
		(_stat_controls(other)[0] as Button).disabled = true
	var tts = get_node_or_null("/root/TTSManager")
	if tts and tts.has_method("is_available") and tts.is_available():
		tts.speak("Say \"%s\"" % _say_word(stat))
	_connect_listen_signals()
	if _is_web():
		_begin_web_challenge_mic()
		if stt.has_method("begin_challenge_listen"):
			stt.begin_challenge_listen()
		else:
			stt.listen()
	else:
		stt.listen()


func _cancel_upgrade_listen(note := "") -> void:
	if _listening_stat == "":
		return
	var stat := _listening_stat
	_listening_stat = ""
	var stt = _stt_manager()
	if stt:
		stt.stop()
	_disconnect_listen_signals()
	if _is_web():
		_end_web_challenge_mic()
	# _refresh restores the other rows' enabled state and button text.
	_refresh()
	if note != "":
		feedback.text = note


func _spend(stat: String) -> void:
	if _busy or _navigating:
		return
	_busy = true
	var message := PlayerManager.try_upgrade(stat)
	feedback.text = "Upgraded." if message == "" else message
	_refresh()
	_busy = false


func _on_listen_completed(result: String) -> void:
	var stat := _listening_stat
	if stat == "":
		return
	if _transcript_matches_skill(_normalize(result), stat):
		_cancel_upgrade_listen()
		_spend(stat)
	else:
		feedback.text = "Say \"%s\" to confirm" % _say_word(stat)
		var stt = _stt_manager()
		if stt and stt.is_speech_available():
			stt.listen()


func _on_listen_error(error_code) -> void:
	if _listening_stat == "":
		return
	print("⚠️ Bonfire listen error: ", error_code)
	if error_code is String:
		error_code = int(error_code) if error_code.is_valid_int() else -1
	if error_code == -1:
		# Mic permission / start failure — parked listening helps nobody.
		_cancel_upgrade_listen("Voice unavailable. Tap Upgrade to try again.")
		return
	# Recoverable errors (e.g. no-match on Android): keep the confirmation alive.
	var stt = _stt_manager()
	if stt and stt.is_speech_available():
		stt.listen()


func _transcript_matches_skill(recognized: String, stat: String) -> bool:
	var words: Array = [_say_word(stat)]
	words.append_array(SKILLS[stat]["accept"])
	for w in words:
		var word: String = w
		if word != "" and word in recognized:
			return true
	for w in words:
		var word: String = w
		if PhoneticMatcher.transcript_contains_fuzzy(recognized, word, 0.72):
			return true
	return false


func _normalize(text: String) -> String:
	var cleaned := ""
	for i in text.length():
		var ch := text.substr(i, 1).to_lower()
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			cleaned += ch
		elif ch == " " or ch == "\t" or ch == "\n":
			cleaned += " "
	return " ".join(cleaned.split(" ", false))


func _connect_listen_signals() -> void:
	var stt = _stt_manager()
	if stt == null:
		return
	_disconnect_listen_signals()
	stt.listening_completed.connect(_on_listen_completed)
	stt.error.connect(_on_listen_error)


func _disconnect_listen_signals() -> void:
	var stt = _stt_manager()
	if stt == null:
		return
	if stt.listening_completed.is_connected(_on_listen_completed):
		stt.listening_completed.disconnect(_on_listen_completed)
	if stt.error.is_connected(_on_listen_error):
		stt.error.disconnect(_on_listen_error)


func _stt_manager():
	return get_node_or_null("/root/STTManager")


func _is_web() -> bool:
	return OS.has_feature("web")


func _begin_web_challenge_mic() -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("begin_challenge_mic"):
			node.begin_challenge_mic()


func _end_web_challenge_mic() -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("end_challenge_mic"):
			node.end_challenge_mic()


func _on_equip() -> void:
	if _busy or _navigating:
		return
	if not PlayerManager.has_sword():
		feedback.text = "No sword yet."
		return
	_busy = true
	PlayerManager.toggle_sword()
	feedback.text = "Sword equipped." if PlayerManager.sword_equipped else "Sword unequipped."
	_refresh()
	_busy = false


func _apply_resume_copy() -> void:
	var resume := 0
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("horde_resume_stage"):
		resume = int(tracker.horde_resume_stage())
	if resume > 0:
		resume_stage_label.text = "You reached Stage %d" % resume
		continue_button.text = "Continue Stage %d" % resume
	else:
		resume_stage_label.text = ""
		continue_button.text = "Continue"


func _on_continue() -> void:
	_leave(HORDE_PATH)


func _on_journal() -> void:
	if _busy or _navigating:
		return
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("show_journal"):
		tracker.show_journal()


func _on_title() -> void:
	_leave(TITLE_PATH)


func _leave(level_path: String) -> void:
	if _busy or _navigating:
		return
	_cancel_upgrade_listen()
	_navigating = true
	_busy = true
	_restore_audio()
	visible = false
	set_process(false)
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(level_path, "", Vector2.ZERO)


func _silence_all() -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	_master_was_muted = AudioServer.is_bus_mute(index)
	AudioServer.set_bus_mute(index, true)


func _restore_audio() -> void:
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	AudioServer.set_bus_mute(index, _master_was_muted)
