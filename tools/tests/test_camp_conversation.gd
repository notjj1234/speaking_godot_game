extends Node2D
## CampConversation regressions. Run headless on a scratch copy only (purchases
## write user://save.sav):
##   Godot --headless --path <copy> res://tools/tests/test_camp_conversation.tscn
## Review Focus 1: a late STT result after leaving buys nothing.
## Review Focus 2: silence re-listens and never advances, fails or charges.
## Review Focus 3: a denied mic switches to tap chips that still buy.

const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")
const FakeTts := preload("res://tools/tests/fake_tts_provider.gd")
const APPLE := "res://items/apple.tres"

var passes := 0
var failures := 0
var conv: CampConversation
var fake
var ended_count := 0
var cb_count := 0
var purchases: Array = []
var actions: Array[String] = []


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _links_to(sig: Signal, target: Object) -> int:
	var n := 0
	for c in sig.get_connections():
		var callable: Callable = c["callable"]
		if callable.get_object() == target:
			n += 1
	return n


func _reset_wallet(points: int = 20) -> void:
	PlayerManager.bonfire_points = points
	for stat in ["vitality", "might", "haste", "crit"]:
		PlayerManager._set_rank(stat, 0)
	PlayerManager.INVENTORY_DATA.parse_save_data([])
	purchases.clear()
	actions.clear()


## The practice target is quoted at the end of the practice line: ...: '<target>'
func _target_from_line() -> String:
	var line := conv.current_line()
	var start := line.find(": '")
	if start == -1 or not line.ends_with("'"):
		return ""
	return line.substr(start + 3, line.length() - start - 4)


## TTSManager's watchdog counts wall-clock ms; headless frames run faster
## than real time, so wait on the real clock.
func _wait_real(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _start(npc_id: String) -> void:
	conv.start(npc_id, null, 1, func(): cb_count += 1)
	await _frames()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var saved_provider: SttProvider = STTManager.provider
	fake = FakeStt.new()
	STTManager.provider = fake
	var saved_inv: Array = PlayerManager.INVENTORY_DATA.get_save_data()
	var saved := [PlayerManager.bonfire_points, PlayerManager.vitality_rank, PlayerManager.might_rank,
		PlayerManager.haste_rank, PlayerManager.crit_rank]
	var master := AudioServer.get_bus_index("Master")
	var master_muted := AudioServer.is_bus_mute(master)

	conv = CampConversation.new()
	add_child(conv)
	conv.ended.connect(func(): ended_count += 1)
	conv.purchase_made.connect(func(id: String, paid: int): purchases.append([id, paid]))
	conv.action_chosen.connect(func(id: String): actions.append(id))
	await _frames()

	await _test_voice_first_try()
	await _test_voice_second_try()
	await _test_clarify_and_small_talk()
	await _test_cook_cap()
	await _test_fire_action()
	await _test_silence()
	await _test_mic_denied()
	await _test_error_streak()
	await _test_late_result()
	await _test_tap_then_say()
	await _test_say_retarget()
	await _test_say_cancel()
	await _test_say_leave()
	await _test_say_error_streak()
	await _test_purchase_sounds()
	await _test_typed_test_input()
	await _test_say_tiles()
	await _test_listen_rearms_mic()
	await _test_stat_chips()
	await _test_leave(master, master_muted)

	STTManager.provider = saved_provider
	fake.free()
	PlayerManager.INVENTORY_DATA.parse_save_data(saved_inv)
	PlayerManager.bonfire_points = saved[0]
	PlayerManager.vitality_rank = saved[1]
	PlayerManager.might_rank = saved[2]
	PlayerManager.haste_rank = saved[3]
	PlayerManager.crit_rank = saved[4]
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _test_voice_first_try() -> void:
	_reset_wallet()
	await _start("smith")
	_check("smith: voice mode", conv.voice_mode())
	_check("smith: in ASK", conv.step() == CampConversation.Step.ASK)
	conv.submit_transcript("I wanna hit harder")
	_check("smith: hit harder -> OFFER", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	conv.submit_transcript("yeah")
	_check("smith: yeah -> PRACTICE", conv.step() == CampConversation.Step.PRACTICE, "step %d" % conv.step())
	var target := _target_from_line()
	_check("smith: practice target quoted", target != "", "line '%s'" % conv.current_line())
	conv.submit_transcript(target)
	await _frames()
	_check("smith: might bought", PlayerManager.might_rank == 1, "rank %d" % PlayerManager.might_rank)
	_check("smith: first try discounted", PlayerManager.bonfire_points == 19, "points %d" % PlayerManager.bonfire_points)
	_check("smith: purchase_made(might, 1)", purchases == [["might", 1]], str(purchases))
	_check("smith: back to ASK", conv.step() == CampConversation.Step.ASK)
	conv.leave()


func _test_voice_second_try() -> void:
	_reset_wallet()
	await _start("trainer")
	conv.submit_transcript("make me tougher")
	conv.submit_transcript("yes")
	var target := _target_from_line()
	conv.submit_transcript("zebra quantum xylophone")
	await _frames()
	_check("trainer: miss stays in PRACTICE", conv.step() == CampConversation.Step.PRACTICE)
	_check("trainer: miss charges nothing", PlayerManager.bonfire_points == 20)
	conv.submit_transcript(target)
	await _frames()
	_check("trainer: vitality bought", PlayerManager.vitality_rank == 1)
	_check("trainer: second try full price", PlayerManager.bonfire_points == 18, "points %d" % PlayerManager.bonfire_points)
	conv.leave()


func _test_clarify_and_small_talk() -> void:
	_reset_wallet()
	await _start("smith")
	conv.submit_transcript("purple monkey")
	var clarify: Array = CampLines.npc("smith")["clarify"]
	_check("clarify: stays in ASK", conv.step() == CampConversation.Step.ASK)
	_check("clarify: says a clarify line", conv.current_line() in clarify, "line '%s'" % conv.current_line())
	_check("clarify: no gems change", PlayerManager.bonfire_points == 20)
	conv.submit_transcript("good morning")
	var reply: String = CampLines.npc("smith")["small_talk"][0]["reply"]
	_check("small talk: reply", conv.current_line() == reply, "line '%s'" % conv.current_line())
	_check("small talk: stays in ASK", conv.step() == CampConversation.Step.ASK)
	conv.leave()


func _test_cook_cap() -> void:
	_reset_wallet()
	PlayerManager.INVENTORY_DATA.add_item(load(APPLE), 3)
	await _start("cook")
	conv.submit_transcript("can I get an apple")
	var full: String = CampLines.npc("cook")["refuse"]["full"]
	_check("cook: full pack refusal", conv.current_line().begins_with(full), "line '%s'" % conv.current_line())
	_check("cook: stays in ASK", conv.step() == CampConversation.Step.ASK)
	conv.leave()


func _test_fire_action() -> void:
	_reset_wallet()
	await _start("fire")
	conv.submit_transcript("fight on")
	_check("fire: action_chosen(fight)", actions.size() == 1 and actions[0] == "fight", str(actions))
	_check("fire: conversation ended", not conv.is_active())


func _test_silence() -> void:
	_reset_wallet()
	await _start("smith")
	var line := conv.current_line()
	var calls: int = fake.listen_calls
	conv.submit_transcript("   ")
	_check("silence ASK: step kept", conv.step() == CampConversation.Step.ASK)
	_check("silence ASK: line kept", conv.current_line() == line)
	_check("silence ASK: listens again", fake.listen_calls > calls)
	conv.submit_transcript("stronger")
	calls = fake.listen_calls
	conv.submit_transcript("")
	_check("silence OFFER: step kept", conv.step() == CampConversation.Step.OFFER)
	_check("silence OFFER: listens again", fake.listen_calls > calls)
	conv.submit_transcript("yes")
	calls = fake.listen_calls
	conv.submit_transcript(" \n ")
	await _frames()
	_check("silence PRACTICE: step kept", conv.step() == CampConversation.Step.PRACTICE)
	_check("silence PRACTICE: nothing charged", PlayerManager.bonfire_points == 20)
	_check("silence PRACTICE: listens again", fake.listen_calls > calls)
	conv.submit_transcript(_target_from_line())
	await _frames()
	_check("silence PRACTICE: next real try is still first-try", PlayerManager.bonfire_points == 19,
		"points %d" % PlayerManager.bonfire_points)
	conv.leave()


func _test_mic_denied() -> void:
	_reset_wallet()
	await _start("smith")
	STTManager.error.emit(-1)
	await _frames()
	_check("denied: tap mode", not conv.voice_mode())
	_check("denied: chips visible", DialogSystem.choice_row.visible)
	conv.choose("might")
	_check("denied: chip -> OFFER", conv.step() == CampConversation.Step.OFFER)
	_check("denied: a tap acts at once, no say box", not DialogSystem.is_say_box_open())
	conv.choose("yes")
	await _frames()
	_check("denied: might bought", PlayerManager.might_rank == 1)
	_check("denied: full price", PlayerManager.bonfire_points == 18, "points %d" % PlayerManager.bonfire_points)
	_check("denied: back to ASK", conv.step() == CampConversation.Step.ASK)
	conv.leave()


## Final review: a backend that keeps erroring with a non -1 code (e.g. Android
## ERROR_INSUFFICIENT_PERMISSIONS = 9) must not trap the player re-listening.
func _test_error_streak() -> void:
	_reset_wallet()
	await _start("smith")
	STTManager.error.emit(7)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("one error: still voice", conv.voice_mode())
	conv.submit_transcript("hello")
	STTManager.error.emit(9)
	await get_tree().create_timer(0.6, true, false, true).timeout
	STTManager.error.emit(9)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("a result resets the streak", conv.voice_mode())
	STTManager.error.emit(9)
	await _frames()
	_check("three errors in a row: tap mode", not conv.voice_mode())
	_check("three errors in a row: chips visible", DialogSystem.choice_row.visible)
	conv.leave()


func _test_late_result() -> void:
	_reset_wallet()
	await _start("smith")
	conv.submit_transcript("hit harder")
	conv.leave()
	STTManager.listening_completed.emit("yes")
	await _frames()
	_check("late result: nothing bought", PlayerManager.might_rank == 0 and PlayerManager.bonfire_points == 20)
	_check("late result: dialog stays closed", not DialogSystem.is_open)
	_check("late result: STT unwired", _links_to(STTManager.listening_completed, conv) == 0)
	_check("late result: errors unwired", _links_to(STTManager.error, conv) == 0)


func _test_leave(master: int, master_muted: bool) -> void:
	_reset_wallet()
	cb_count = 0
	ended_count = 0
	await _start("trainer")
	conv.leave()
	conv.leave()
	_check("leave: on_end once", cb_count == 1, "count %d" % cb_count)
	_check("leave: ended once", ended_count == 1, "count %d" % ended_count)
	_check("leave: player unfrozen", not PlayerManager.dialog_open)
	_check("leave: dialog closed", not DialogSystem.is_open)
	_check("leave: Master mute restored", AudioServer.is_bus_mute(master) == master_muted)


## Shop chips are plain words a first grader gets ("Hit harder - 2 gems"),
## the phrase to say is the same plain words, and the stats behind them hold.
func _test_stat_chips() -> void:
	_reset_wallet()
	var ranks := [PlayerManager.vitality_rank, PlayerManager.might_rank, PlayerManager.crit_rank]
	var hp0 := PlayerManager.horde_max_hp()
	var dmg0 := PlayerManager.attack_damage()
	var crit0 := PlayerManager.crit_chance()
	PlayerManager.vitality_rank += 1
	PlayerManager.might_rank += 1
	PlayerManager.crit_rank += 1
	_check("stats: a vitality rank is +2 HP", PlayerManager.horde_max_hp() - hp0 == 2)
	_check("stats: a might rank is +1 DMG", PlayerManager.attack_damage() - dmg0 == 1)
	_check("stats: a crit rank is +10% CRIT", is_equal_approx(PlayerManager.crit_chance() - crit0, 0.10))
	PlayerManager.vitality_rank = ranks[0]
	PlayerManager.might_rank = ranks[1]
	PlayerManager.crit_rank = ranks[2]
	await _start("smith")
	var chips := _chip_texts()
	_check("shop: smith chip A is 'Hit harder - N gems'", chips.size() > 2
		and str(chips[0]) == "A  Hit harder - %d gems" % CampShop.price("might"), str(chips))
	_check("shop: smith chip B is 'Lucky hits - N gems'", chips.size() > 2
		and str(chips[1]) == "B  Lucky hits - %d gems" % CampShop.price("crit"), str(chips))
	var sword_label := "C  Put sword away" if PlayerManager.sword_equipped else "C  Use sword"
	_check("shop: the sword chip says what it does", chips.size() > 2 and str(chips[2]) == sword_label, str(chips))
	for c in chips:
		_check("shop: no jargon in '%s'" % c, not (str(c).contains("DMG") or str(c).contains("CRIT")
			or str(c).contains("SPEED") or str(c).contains("HP")))
	conv.choose("might")
	_check("stats: the phrase to say stays plain", DialogSystem.say_phrase() == "Hit harder", DialogSystem.say_phrase())
	conv.leave()
	await _start("smith")
	conv.submit_transcript("lucky hits")
	_check("shop: crit offer names the price", conv.current_line().contains(str(CampShop.price("crit")) + " gems"),
		conv.current_line())
	conv.leave()
	await _start("trainer")
	chips = _chip_texts()
	_check("shop: trainer chip A is 'More hearts'", chips.size() > 1 and str(chips[0]).begins_with("A  More hearts - "), str(chips))
	_check("shop: trainer chip B is 'Run faster'", chips.size() > 1 and str(chips[1]).begins_with("B  Run faster - "), str(chips))
	conv.submit_transcript("run faster")
	_check("shop: speed offer names the price", conv.current_line().contains(str(CampShop.price("haste")) + " gems"),
		conv.current_line())
	conv.leave()
	await _start("cook")
	chips = _chip_texts()
	_check("shop: cook says what food does", chips.size() > 1 and str(chips[0]).begins_with("A  Apple (small heal) - ")
		and str(chips[1]).begins_with("B  Potion (big heal) - "), str(chips))
	conv.leave()


func _chip_texts() -> Array:
	return DialogSystem.choice_row.get_children().filter(func(c): return c is Button and c != DialogSystem.leave_button and not c.is_queued_for_deletion()).map(func(b): return b.text)


## Tap a lettered option, then say it: the tap only opens the Say-it box, the
## spoken phrase confirms it.
func _test_tap_then_say() -> void:
	_reset_wallet()
	await _start("smith")
	var chips := _chip_texts()
	_check("say: voice mode shows chips", DialogSystem.choice_row.visible)
	_check("say: first chip lettered A", chips.size() > 0 and str(chips[0]).begins_with("A  "), str(chips))
	_check("say: bye chip is D", chips.size() == 4 and chips[3] == "D  Bye", str(chips))
	Sfx.reset_counts()
	conv.submit_transcript("")
	conv.submit_transcript("   ")
	_check("say: silent relistens stay quiet", Sfx.count(&"listen") == 0, str(Sfx.count(&"listen")))
	conv.choose("might")
	_check("say: box opening pings listen", Sfx.count(&"listen") == 1, str(Sfx.count(&"listen")))
	_check("say: tap keeps ASK", conv.step() == CampConversation.Step.ASK, "step %d" % conv.step())
	_check("say: tap sets pending", conv.pending_choice() == "might", conv.pending_choice())
	_check("say: box open", DialogSystem.is_say_box_open())
	_check("say: phrase is the label", DialogSystem.say_phrase() == "Hit harder", DialogSystem.say_phrase())
	conv.submit_transcript("banana")
	_check("say miss: box stays", DialogSystem.is_say_box_open())
	_check("say miss: feedback", DialogSystem.say_feedback_label.text == "Not quite. Try again.",
		DialogSystem.say_feedback_label.text)
	_check("say miss: wrong sound", Sfx.count(&"wrong") == 1, str(Sfx.count(&"wrong")))
	_check("say miss: still ASK", conv.step() == CampConversation.Step.ASK)
	conv.submit_transcript("hit harder")
	_check("say match: OFFER", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	_check("say match: box closed", not DialogSystem.is_say_box_open())
	_check("say match: accept sound", Sfx.count(&"accept") == 1, str(Sfx.count(&"accept")))
	_check("say match: pending cleared", conv.pending_choice() == "")
	chips = _chip_texts()
	_check("say: offer chips lettered", chips == ["A  Yes", "B  No"], str(chips))
	conv.choose("yes")
	_check("say: yes tap opens box", DialogSystem.is_say_box_open() and DialogSystem.say_phrase() == "Yes")
	conv.submit_transcript("yes")
	_check("say: yes said -> PRACTICE", conv.step() == CampConversation.Step.PRACTICE, "step %d" % conv.step())
	conv.leave()


## Review Focus 1: tapping B while A's box is open retargets the box to B.
func _test_say_retarget() -> void:
	_reset_wallet()
	await _start("smith")
	conv.choose("might")
	conv.choose("crit")
	_check("retarget: box shows Lucky hits", DialogSystem.say_phrase() == "Lucky hits", DialogSystem.say_phrase())
	conv.submit_transcript("hit harder")
	_check("retarget: old phrase does not act", conv.step() == CampConversation.Step.ASK, "step %d" % conv.step())
	_check("retarget: box still open", DialogSystem.is_say_box_open())
	conv.leave()


## Review Focus 3: after Cancel, speech is free speech again.
func _test_say_cancel() -> void:
	_reset_wallet()
	await _start("smith")
	conv.choose("crit")
	DialogSystem._on_say_cancel()
	_check("cancel: box closed", not DialogSystem.is_say_box_open())
	_check("cancel: pending cleared", conv.pending_choice() == "")
	_check("cancel: dialog still open", DialogSystem.is_open and conv.is_active())
	conv.submit_transcript("crit")
	_check("cancel: free speech still works", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	conv.leave()


## Review Focus 2: leaving with the box open leaves nothing pending.
func _test_say_leave() -> void:
	_reset_wallet()
	await _start("smith")
	conv.choose("might")
	conv.leave()
	_check("leave: box closed", not DialogSystem.is_say_box_open())
	await _start("smith")
	_check("leave: nothing pending on restart", conv.pending_choice() == "" and not DialogSystem.is_say_box_open())
	conv.leave()


## Review Focus 4: the mic giving up mid-box hides it and chips act on tap.
func _test_say_error_streak() -> void:
	_reset_wallet()
	await _start("smith")
	conv.choose("might")
	Sfx.reset_counts()
	for i in 3:
		STTManager.error.emit(9)
		await get_tree().create_timer(0.6, true, false, true).timeout
	_check("mic gives up: tap mode", not conv.voice_mode())
	_check("mic gives up: box hidden", not DialogSystem.is_say_box_open())
	_check("mic gives up: chips visible", DialogSystem.choice_row.visible)
	_check("mic gives up: error sound", Sfx.count(&"error") >= 1)
	conv.choose("crit")
	_check("mic gives up: tap acts", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	conv.leave()


func _test_purchase_sounds() -> void:
	_reset_wallet()
	await _start("smith")
	Sfx.reset_counts()
	conv.submit_transcript("hit harder")
	conv.submit_transcript("yes")
	var target := _target_from_line()
	conv.submit_transcript("zebra quantum")
	_check("practice miss: wrong sound", Sfx.count(&"wrong") == 1, str(Sfx.count(&"wrong")))
	var sfx_bus := AudioServer.get_bus_index("SFX")
	await get_tree().create_timer(1.2, true, false, true).timeout  # the miss cue's lift ends
	_check("mic listening mutes game sounds", sfx_bus == -1 or AudioServer.is_bus_mute(sfx_bus))
	conv.submit_transcript(target)
	_check("purchase: sound", Sfx.count(&"purchase") == 1, str(Sfx.count(&"purchase")))
	_check("purchase: sound is audible while the mic listens", sfx_bus == -1 or not AudioServer.is_bus_mute(sfx_bus))
	_check("purchase: a 'Bought' toast", DialogSystem.toast_text().begins_with("Bought"), DialogSystem.toast_text())
	await get_tree().create_timer(1.2, true, false, true).timeout
	_check("game sounds muted again after the cue", sfx_bus == -1 or AudioServer.is_bus_mute(sfx_bus) == conv.is_listening())
	conv.leave()
	_reset_wallet(0)
	await _start("smith")
	Sfx.reset_counts()
	conv.submit_transcript("hit harder")
	_check("broke: error sound", Sfx.count(&"error") == 1, str(Sfx.count(&"error")))
	_check("broke: error sound is audible", sfx_bus == -1 or not AudioServer.is_bus_mute(sfx_bus))
	_check("broke: says how many gems are needed", DialogSystem.toast_text().begins_with("Need"), DialogSystem.toast_text())
	conv.leave()


## Players have no keyboard: after three misses the Say-it box offers
## pick-the-word tiles (no typing), and a tile answers by touch. A tile
## confirms a choice; in practice it buys at full price (no first-try discount).
func _test_say_tiles() -> void:
	_reset_wallet()
	await _start("smith")
	conv.choose(conv._choices()[0]["id"])
	await _frames()
	for i in CampConversation.FALLBACK_AFTER_MISSES:
		conv.submit_transcript("zebra quantum")
	await _frames()
	var tiles: Array = DialogSystem.say_tile_texts()
	_check("say box: tiles after three misses", tiles.size() == 3 and tiles.has(DialogSystem.say_phrase()), str(tiles))
	_check("say box: no typing for players", not DialogSystem.say_typed_row.visible)
	conv.leave()
	await _frames()

	_reset_wallet()
	await _start("smith")
	conv.submit_transcript("hit harder")
	conv.submit_transcript("yes")
	var target := _target_from_line()
	for i in CampConversation.FALLBACK_AFTER_MISSES:
		conv.submit_transcript("zebra quantum")
	await _frames(3)
	var full := CampShop.price("might")
	var btn: Button = DialogSystem.say_tile_button(target)
	_check("practice: the phrase is a tile", btn != null, str(DialogSystem.say_tile_texts()))
	if btn:
		var at := btn.get_global_rect().get_center()
		for pressed in [true, false]:
			var ev := InputEventScreenTouch.new()
			ev.position = at
			ev.pressed = pressed
			UiInputRouter._input(ev)
			await get_tree().process_frame
		await _frames()
	_check("practice: a tile tap buys", PlayerManager.might_rank == 1, "rank %d" % PlayerManager.might_rank)
	_check("practice: tile buys at full price", PlayerManager.bonfire_points == 20 - full,
		"points %d, price %d" % [PlayerManager.bonfire_points, full])
	conv.leave()


## Developer-only typing aid: the Say-it box and practice phrase offer
## typing from the start when typed_test_input is on, inside the camp's own
## Say-it box. The HUD battle card must never open in a camp conversation.
func _test_typed_test_input() -> void:
	_reset_wallet()
	_check("typed: off in headless runs", not PlayerHud.typed_test_input)
	PlayerHud.typed_test_input = true
	await _start("smith")
	conv.choose("might")
	_check("typed: say box offers typing", DialogSystem.say_typed_row.visible)
	_check("typed: battle card stays shut", not PlayerHud.challenge_panel.visible)
	conv.choose("crit")
	_check("typed: retarget keeps typing", DialogSystem.say_typed_row.visible
		and DialogSystem.say_phrase() == "Lucky hits", DialogSystem.say_phrase())
	DialogSystem.say_typed_submitted.emit("lucky hits")
	await _frames()
	_check("typed: typed label -> OFFER", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	_check("typed: box gone after match", not DialogSystem.is_say_box_open())
	conv.choose("yes")
	DialogSystem.say_typed_submitted.emit("yes")
	await _frames()
	_check("typed: yes -> PRACTICE", conv.step() == CampConversation.Step.PRACTICE, "step %d" % conv.step())
	var target := _target_from_line()
	_check("typed: practice offers typing", DialogSystem.is_say_box_open() and DialogSystem.say_typed_row.visible)
	_check("typed: practice box shows the phrase", target != "" and DialogSystem.say_phrase() == target,
		"'%s' vs '%s'" % [DialogSystem.say_phrase(), target])
	_check("typed: practice battle card stays shut", not PlayerHud.challenge_panel.visible)
	DialogSystem.say_typed_submitted.emit(target)
	await _frames()
	_check("typed: practice typed -> bought", PlayerManager.crit_rank == 1, "rank %d" % PlayerManager.crit_rank)
	_check("typed: box gone after purchase", not DialogSystem.is_say_box_open())
	conv.leave()
	PlayerHud.typed_test_input = false


## Listen reads the phrase aloud with the mic off, then the camp listens
## again by itself (it used to stay deaf until you typed).
func _test_listen_rearms_mic() -> void:
	_reset_wallet()
	var tts := get_node("/root/TTSManager")
	var old_tts = tts.provider
	var voice = FakeTts.new()
	tts.provider = voice
	await _start("smith")
	conv.choose("might")
	_check("listen: say box offers Listen", DialogSystem.say_listen_button.visible)
	var calls_before: int = fake.listen_calls
	DialogSystem.say_listen_pressed.emit()
	await _frames()
	_check("listen: phrase read aloud", voice.spoken.size() > 0 and voice.spoken[-1] == "Hit harder", str(voice.spoken))
	_check("listen: mic off while it speaks", not conv._listening)
	voice.finish()
	await _wait_real(800)
	_check("listen: mic back on after speaking", conv._listening and fake.listen_calls > calls_before,
		"listening %s calls %d -> %d" % [conv._listening, calls_before, fake.listen_calls])
	STTManager.listening_completed.emit("hit harder")
	await _frames()
	_check("listen: spoken answer still heard", conv.step() == CampConversation.Step.OFFER, "step %d" % conv.step())
	# A Listen left over from an earlier box must not restart the mic later.
	conv.choose("yes")
	STTManager.listening_completed.emit("yes")
	await _frames()
	DialogSystem.say_listen_pressed.emit()
	await _frames()
	conv.leave()
	var calls_at_leave: int = fake.listen_calls
	voice.finish()
	await _wait_real(800)
	_check("listen: stale finish after leaving does nothing", fake.listen_calls == calls_at_leave
		and not conv._listening)
	tts.provider = old_tts
