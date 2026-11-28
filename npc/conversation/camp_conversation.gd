class_name CampConversation
extends Node
## Runs one camp conversation at a time (NPCs and the fire) as a small step
## machine: ASK what you want -> OFFER a price -> PRACTICE a phrase to close
## the deal. Options always show as lettered chips (A, B, C...). With a working
## mic a tap only opens the Say-it box and the spoken phrase confirms it; with
## no STT (or the mic denied) a tap acts at once and skips practice.

enum Step { IDLE, ASK, OFFER, PRACTICE }

signal line_changed(text: String)
signal purchase_made(offer_id: String, paid: int)
signal action_chosen(action_id: String)
signal ended

const WEB_SCORE_PASS := 75.0
const FALLBACK_AFTER_MISSES := 3
const FAREWELL_HOLD_SEC := 1.2
const RELISTEN_DELAY_SEC := 0.4
const MIC_DENIED := -1
## Same bar as enemy.gd: this many STT errors in a row means the mic is not
## working (e.g. Android permission error 9), so fall back to tap choices.
const STT_ERRORS_BEFORE_TAP := 3
const SAY_MISS_TEXT := "Not quite. Try again."

var _active := false
var _leaving := false
var _step: int = Step.IDLE
var _voice := false
var _npc_id := ""
var _data: Dictionary = {}
var _on_end: Callable = Callable()
var _line := ""
var _offer_id := ""
var _target := ""
var _attempts := 0
var _clarify_index := 0
var _listening := false
var _audio_quieted_by_us := false
var _sfx_was_muted := false
var _fallback_shown := false
var _error_streak := 0
var _token := 0
var _pending_choice := ""
var _say_misses := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camp_conversation")


func _exit_tree() -> void:
	if _active:
		leave()


func start(npc_id: String, portrait: Texture, portrait_hframes: int, on_end: Callable) -> void:
	if _active:
		return
	var data := CampLines.npc(npc_id)
	if data.is_empty():
		print("❌ CampConversation: no lines for '%s'" % npc_id)
		return
	_active = true
	_leaving = false
	_token += 1
	_npc_id = npc_id
	_data = data
	_on_end = on_end
	_offer_id = ""
	_attempts = 0
	_clarify_index = 0
	_fallback_shown = false
	_error_streak = 0
	_pending_choice = ""
	var stt = _stt()
	_voice = stt != null and stt.is_speech_available()
	if stt:
		stt.listening_completed.connect(_on_listening_completed)
		stt.error.connect(_on_stt_error)
	if _is_web():
		_set_web_challenge_mic(true)
	if not DialogSystem.say_cancelled.is_connected(_on_say_cancelled):
		DialogSystem.say_cancelled.connect(_on_say_cancelled)
	DialogSystem.show_conversation(str(data.get("name", npc_id)), portrait, portrait_hframes, _on_dialog_closed)
	print("✅ CampConversation: talking to %s (%s)" % [npc_id, "voice" if _voice else "tap"])
	_step = Step.ASK
	var greet: Array = data.get("greet", ["..."])
	_say(str(greet[randi() % greet.size()]))


func is_active() -> bool:
	return _active


func step() -> int:
	return _step


func current_line() -> String:
	return _line


func voice_mode() -> bool:
	return _voice


## The option tapped in voice mode and waiting to be said, or "".
func pending_choice() -> String:
	return _pending_choice


## The single entry for STT results, the typed fallback and tests.
func submit_transcript(text: String) -> void:
	if not _active:
		return
	_end_listen()
	_error_streak = 0
	var heard := text.strip_edges()
	if heard == "":
		# Never fail or advance on silence: just listen again.
		_listen()
		return
	DialogSystem.set_heard(heard)
	if _pending_choice != "":
		await _handle_pending(heard)
		return
	match _step:
		Step.ASK:
			_handle_ask(heard)
		Step.OFFER:
			_handle_offer(heard)
		Step.PRACTICE:
			_handle_practice(heard)


## Tap-chip entry point. In voice mode a tap only opens (or retargets) the
## Say-it box; the spoken phrase confirms it in _handle_pending.
func choose(choice_id: String) -> void:
	if not _active:
		return
	if _voice:
		_open_say_box(choice_id)
		return
	_act_on(choice_id)


func _act_on(choice_id: String) -> void:
	match _step:
		Step.ASK:
			if choice_id == "bye":
				_farewell()
			else:
				_pick_offer(choice_id)
		Step.OFFER:
			if choice_id == "yes" and _voice:
				_enter_practice()
			elif choice_id == "yes":
				_complete_purchase(false, -1.0)
			else:
				_back_to_ask(str(_data.get("anything_else", "")))


func leave() -> void:
	if not _active or _leaving:
		return
	_leaving = true
	_token += 1
	var stt = _stt()
	if stt:
		if _listening:
			stt.stop()
		if stt.listening_completed.is_connected(_on_listening_completed):
			stt.listening_completed.disconnect(_on_listening_completed)
		if stt.error.is_connected(_on_stt_error):
			stt.error.disconnect(_on_stt_error)
	_end_listen()
	_hide_fallback()
	_abandon_scorer_capture()
	_clear_pending()
	if DialogSystem.say_cancelled.is_connected(_on_say_cancelled):
		DialogSystem.say_cancelled.disconnect(_on_say_cancelled)
	if _is_web():
		_set_web_challenge_mic(false)
	_step = Step.IDLE
	_active = false
	if DialogSystem.is_open and DialogSystem.is_conversation():
		DialogSystem.close()
	var callback := _on_end
	_on_end = Callable()
	if callback.is_valid():
		callback.call()
	_leaving = false
	print("✅ CampConversation: left %s" % _npc_id)
	ended.emit()


# --- steps ------------------------------------------------------------------

func _handle_ask(heard: String) -> void:
	var intents := {}
	var offers: Dictionary = _data.get("offers", {})
	for id in offers:
		intents[id] = offers[id].get("phrases", [])
	intents["bye"] = CampLines.BYE
	var talk: Array = _data.get("small_talk", [])
	for i in talk.size():
		intents["talk:%d" % i] = talk[i].get("expect", [])
	var intent := IntentMatcher.best_intent(heard, intents)
	if intent == "bye":
		_farewell()
	elif offers.has(intent):
		_pick_offer(intent)
	elif intent.begins_with("talk:"):
		_say(str(talk[int(intent.substr(5))].get("reply", "")))
	else:
		var clarify: Array = _data.get("clarify", ["Say again?"])
		_say(str(clarify[_clarify_index % clarify.size()]))
		_clarify_index += 1


func _pick_offer(offer_id: String) -> void:
	var offers: Dictionary = _data.get("offers", {})
	if not offers.has(offer_id):
		_say(str(_data.get("anything_else", "")))
		return
	var offer: Dictionary = offers[offer_id]
	if offer.get("action", false):
		print("✅ CampConversation: action %s" % offer_id)
		leave()
		action_chosen.emit(offer_id)
		return
	var refused := CampShop.refusal(offer_id)
	if refused != "":
		var refuse: Dictionary = _data.get("refuse", {})
		var line := str(refuse.get(refused, ""))
		if line == "":
			line = "Can't do that one right now."
		_play_sfx(&"error")
		_back_to_ask(line)
		return
	if offer_id == "sword":
		CampShop.buy("sword", false)
		var done_key := "done" if PlayerManager.sword_equipped else "done_off"
		_back_to_ask(str(offer.get(done_key, offer.get("done", ""))))
		return
	_offer_id = offer_id
	_step = Step.OFFER
	_say(_offer_line())


func _offer_line() -> String:
	var offer: Dictionary = _data["offers"][_offer_id]
	return str(offer.get("offer", "%d gems. Deal?")) % CampShop.price(_offer_id)


func _handle_offer(heard: String) -> void:
	var answer := IntentMatcher.best_intent(heard, {"yes": CampLines.YES, "no": CampLines.NO})
	if answer == "yes":
		if _voice:
			_enter_practice()
		else:
			_complete_purchase(false, -1.0)
	elif answer == "no":
		_back_to_ask(str(_data.get("anything_else", "")))
	else:
		_say(_offer_line())


func _enter_practice() -> void:
	_step = Step.PRACTICE
	_attempts = 0
	var stage := 1
	var tracker := get_node_or_null("/root/ProgressTracker")
	if tracker and tracker.has_method("horde_resume_stage"):
		stage = maxi(int(tracker.horde_resume_stage()), 1)
	_target = WordTracker.get_speech_challenge_for_stage(stage)
	_say(str(_data.get("practice_intro", "Say: '%s'")) % _target)
	_offer_typed_test_input()


func _handle_practice(heard: String) -> void:
	_attempts += 1
	var token := _token
	var score := -1.0
	var passed := IntentMatcher.contains_phrase(heard, _target)
	if not passed and _is_web():
		score = await _score_web_attempt()
		if token != _token or not _active or _step != Step.PRACTICE:
			return
		passed = score >= WEB_SCORE_PASS
	if passed:
		_hide_fallback()
		_play_sfx(&"correct")
		_complete_purchase(_attempts == 1, score)
		return
	_play_sfx(&"wrong")
	_say(str(_data.get("retry", "Again.")))
	if _is_web() and _attempts >= FALLBACK_AFTER_MISSES:
		_show_fallback()


func _complete_purchase(first_try: bool, score: float) -> void:
	var offer_id := _offer_id
	var paid := CampShop.discounted_price(offer_id) if first_try else CampShop.price(offer_id)
	if not CampShop.buy(offer_id, first_try):
		var refuse: Dictionary = _data.get("refuse", {})
		var why := str(refuse.get(CampShop.refusal(offer_id), ""))
		_play_sfx(&"error")
		_back_to_ask(why if why != "" else "Hm. Your pack has no room for that.")
		return
	_play_sfx(&"purchase")
	purchase_made.emit(offer_id, paid)
	var praise := str(_data.get("praise_first" if first_try else "praise", ""))
	if score >= 0.0:
		praise += " (score %d/100)" % int(round(score))
	var done := str(_data["offers"][offer_id].get("done", ""))
	_back_to_ask(("%s %s" % [praise, done]).strip_edges())


func _back_to_ask(line: String) -> void:
	_clear_pending()
	_step = Step.ASK
	_offer_id = ""
	_target = ""
	var tail := str(_data.get("anything_else", ""))
	if line == "" or line == tail:
		_say(tail)
	else:
		_say("%s %s" % [line, tail])


func _farewell() -> void:
	_step = Step.IDLE
	_say(str(_data.get("farewell", "Bye.")))
	var token := _token
	await get_tree().create_timer(FAREWELL_HOLD_SEC, true, false, true).timeout
	if token == _token and _active:
		leave()


func _say(text: String) -> void:
	_line = text
	DialogSystem.set_conversation_line(text)
	line_changed.emit(text)
	if _step == Step.IDLE or _step == Step.PRACTICE:
		# Practice has nothing to pick: the phrase to say is in the line.
		DialogSystem.set_choices([], Callable())
	else:
		DialogSystem.set_choices(_choices(), choose)
	if _step != Step.IDLE and _voice:
		_listen()


## Each choice: {"id", "label" (lettered, shown on the chip), "say" (the phrase
## to speak after tapping it)}.
func _choices() -> Array:
	var raw: Array = []
	if _step == Step.OFFER:
		raw.append({"id": "yes", "label": "Yes", "say": "Yes"})
		raw.append({"id": "no", "label": "No", "say": "No"})
	else:
		var offers: Dictionary = _data.get("offers", {})
		for id in offers:
			var offer: Dictionary = offers[id]
			var label := str(offer.get("label", id))
			var say := str(offer.get("say", label))
			if not offer.get("action", false) and id != "sword":
				label = "%s (%d)" % [label, CampShop.price(id)]
			raw.append({"id": id, "label": label, "say": say})
		var bye := str(_data.get("bye_label", "Bye"))
		raw.append({"id": "bye", "label": bye, "say": bye})
	for i in raw.size():
		raw[i]["letter"] = _letter(i)
		raw[i]["label"] = "%s  %s" % [_letter(i), raw[i]["label"]]
	return raw


static func _letter(index: int) -> String:
	return String.chr(65 + index)


# --- tap then say -----------------------------------------------------------

func _open_say_box(choice_id: String) -> void:
	for choice in _choices():
		if choice["id"] == choice_id:
			_pending_choice = choice_id
			_say_misses = 0
			_target = str(choice["say"])
			_abandon_scorer_capture()
			DialogSystem.show_say_box(str(choice["letter"]), str(choice["say"]))
			_offer_typed_test_input()
			if not _listening:
				_listen()
			return
	print("⚠️ CampConversation: unknown choice '%s'" % choice_id)


## Phrases that confirm a tapped option: its own label plus the words the
## free-speech matcher already knows for it.
func _phrases_for(choice_id: String) -> Array:
	var out: Array = []
	for choice in _choices():
		if choice["id"] == choice_id:
			out.append(str(choice["say"]))
	match choice_id:
		"yes":
			out.append_array(CampLines.YES)
		"no":
			out.append_array(CampLines.NO)
		"bye":
			out.append_array(CampLines.BYE)
		_:
			var offers: Dictionary = _data.get("offers", {})
			if offers.has(choice_id):
				out.append_array(offers[choice_id].get("phrases", []))
	return out


func _handle_pending(heard: String) -> void:
	var choice_id := _pending_choice
	var token := _token
	var matched := false
	for phrase in _phrases_for(choice_id):
		if IntentMatcher.contains_phrase(heard, str(phrase)):
			matched = true
			break
	if not matched and _is_web():
		var score := await _score_web_attempt()
		if token != _token or not _active or _pending_choice != choice_id:
			return
		matched = score >= WEB_SCORE_PASS
	if matched:
		_play_sfx(&"accept")
		_clear_pending()
		_act_on(choice_id)
		return
	_say_misses += 1
	_play_sfx(&"wrong")
	DialogSystem.set_say_feedback(SAY_MISS_TEXT)
	if _is_web() and _say_misses >= FALLBACK_AFTER_MISSES:
		_show_fallback()
	_listen()


func _clear_pending() -> void:
	if _pending_choice == "" and not DialogSystem.is_say_box_open():
		return
	_pending_choice = ""
	_say_misses = 0
	if _step != Step.PRACTICE:
		_target = ""
	_hide_fallback()
	_abandon_scorer_capture()
	DialogSystem.hide_say_box()


func _on_say_cancelled() -> void:
	if not _active:
		return
	_pending_choice = ""
	_say_misses = 0
	if _step != Step.PRACTICE:
		_target = ""
	_hide_fallback()
	_abandon_scorer_capture()


func _play_sfx(cue: StringName) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(cue)


# --- speech -----------------------------------------------------------------

func _listen() -> void:
	if not _active or not _voice or _step == Step.IDLE:
		return
	var stt = _stt()
	if stt == null:
		return
	_quiet_for_mic()
	_listening = true
	DialogSystem.set_listening(true)
	if _step == Step.PRACTICE or _pending_choice != "":
		_begin_scorer_capture()
	if _is_web():
		stt.begin_challenge_listen()
	else:
		stt.listen()


func _end_listen() -> void:
	_listening = false
	_restore_after_mic()
	DialogSystem.set_listening(false)


func _on_listening_completed(result: String) -> void:
	submit_transcript(result)


func _on_stt_error(code) -> void:
	if not _active:
		return
	_end_listen()
	if str(code) == str(MIC_DENIED):
		print("⚠️ CampConversation: mic denied, switching to tap choices")
		_switch_to_tap()
		return
	_error_streak += 1
	if _error_streak >= STT_ERRORS_BEFORE_TAP:
		print("⚠️ CampConversation: %d STT errors in a row, switching to tap choices" % _error_streak)
		_switch_to_tap()
		return
	var token := _token
	await get_tree().create_timer(RELISTEN_DELAY_SEC, true, false, true).timeout
	if token == _token and _active and not _listening:
		_listen()


func _switch_to_tap() -> void:
	_voice = false
	_play_sfx(&"error")
	_clear_pending()
	_hide_fallback()
	_abandon_scorer_capture()
	if _step == Step.PRACTICE:
		_step = Step.OFFER
		_say(_offer_line())
	elif _step != Step.IDLE:
		DialogSystem.set_choices(_choices(), choose)


func _on_dialog_closed() -> void:
	leave()


func _on_speak_pressed() -> void:
	if _active and _voice and not _listening:
		_listen()


func _show_fallback() -> void:
	var hud := get_node_or_null("/root/PlayerHud")
	if hud == null or _fallback_shown:
		return
	_fallback_shown = true
	hud.show_speech_challenge(_target)
	hud.show_typed_fallback()
	hud.show_speak_button()
	if not hud.fallback_submitted.is_connected(submit_transcript):
		hud.fallback_submitted.connect(submit_transcript)
	if not hud.speak_pressed.is_connected(_on_speak_pressed):
		hud.speak_pressed.connect(_on_speak_pressed)


## TEMPORARY (desktop testing): see PlayerHud.typed_test_input. Re-shows the
## box so a retargeted Say-it box types against the new phrase.
func _offer_typed_test_input() -> void:
	var hud := get_node_or_null("/root/PlayerHud")
	if hud == null or not hud.typed_test_input:
		return
	_hide_fallback()
	_show_fallback()


func _hide_fallback() -> void:
	if not _fallback_shown:
		return
	_fallback_shown = false
	var hud := get_node_or_null("/root/PlayerHud")
	if hud == null:
		return
	if hud.fallback_submitted.is_connected(submit_transcript):
		hud.fallback_submitted.disconnect(submit_transcript)
	if hud.speak_pressed.is_connected(_on_speak_pressed):
		hud.speak_pressed.disconnect(_on_speak_pressed)
	hud.hide_speech_challenge()


# --- web phoneme scoring (pattern from enemy.gd) -----------------------------

func _scorer():
	if not _is_web():
		return null
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null:
		return null
	return pm.get_scorer()


func _begin_scorer_capture() -> void:
	var scorer = _scorer()
	if scorer == null or not scorer.is_available() or _target == "":
		return
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null or pm.phonemes_for(_target).is_empty():
		return
	if not scorer.is_capturing():
		scorer.begin_capture()


func _abandon_scorer_capture() -> void:
	var scorer = _scorer()
	if scorer != null and scorer.is_capturing():
		scorer.abandon_capture()


## Returns the 0-100 phoneme score of the clip just captured, or -1.
func _score_web_attempt() -> float:
	var scorer = _scorer()
	if scorer == null or not scorer.is_available() or not scorer.is_capturing():
		return -1.0
	var pm := get_node_or_null("/root/PronunciationManager")
	var phonemes: String = pm.phonemes_for(_target) if pm else ""
	if phonemes.is_empty():
		scorer.abandon_capture()
		return -1.0
	var done := {"ok": false}
	var on_done := func(_r: Dictionary) -> void:
		done["ok"] = true
	scorer.end_capture_and_score(phonemes, on_done)
	if not done["ok"]:
		# Bound the wait so a lost JS callback cannot hang the conversation.
		var timer := get_tree().create_timer(6.0, true, false, true)
		while not done["ok"] and timer.time_left > 0.0:
			await get_tree().process_frame
	return float(scorer.last_result.get("score", -1))


# --- helpers ----------------------------------------------------------------

## While the mic listens: game sounds (SFX bus) off, the music only lowered,
## as in speech challenges, so the NPC's theme keeps playing under the mic.
func _quiet_for_mic() -> void:
	if _audio_quieted_by_us:
		return
	_audio_quieted_by_us = true
	var index := AudioServer.get_bus_index("SFX")
	if index != -1:
		_sfx_was_muted = AudioServer.is_bus_mute(index)
		AudioServer.set_bus_mute(index, true)
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.set_ducked(true)


func _restore_after_mic() -> void:
	if not _audio_quieted_by_us:
		return
	_audio_quieted_by_us = false
	var index := AudioServer.get_bus_index("SFX")
	if index != -1:
		AudioServer.set_bus_mute(index, _sfx_was_muted)
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.set_ducked(false)


func _set_web_challenge_mic(on: bool) -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if on and node.has_method("begin_challenge_mic"):
			node.begin_challenge_mic()
		elif not on and node.has_method("end_challenge_mic"):
			node.end_challenge_mic()


func _stt():
	return get_node_or_null("/root/STTManager")


func _is_web() -> bool:
	return OS.has_feature("web")
