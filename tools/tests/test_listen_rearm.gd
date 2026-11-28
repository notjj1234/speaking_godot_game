extends Node2D
## Fight challenge Listen: the mic comes back after the phrase is read aloud;
## if the browser refuses that restart (no user tap), a "Tap Speak" prompt
## appears; and a stuck read-aloud can't hold the mic off for long.

const SLIME := "res://enemies/slime/slime.tscn"
const FakeStt := preload("res://tools/tests/fake_stt_provider.gd")
const FakeTts := preload("res://tools/tests/fake_tts_provider.gd")

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


## TTSManager's watchdog counts wall-clock ms; headless frames run faster
## than real time, so wait on the real clock.
func _wait_real(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	var old_stt = STTManager.provider
	var fake = FakeStt.new()
	STTManager.provider = fake
	var old_tts = TTSManager.provider
	var voice = FakeTts.new()
	TTSManager.provider = voice

	var e: Enemy = load(SLIME).instantiate()
	e.hp = 1
	add_child(e)
	e.global_position = Vector2(2000, 2000)
	var hit := HurtBox.new()
	hit.damage = 1
	add_child(hit)
	e._take_damage(hit)
	await get_tree().process_frame
	_check("challenge up", WordTracker.speech_challenge_active and PlayerHud.challenge_panel.visible)

	var calls_before: int = fake.listen_calls
	PlayerHud._on_listen_pressed()
	_check("phrase read aloud", voice.spoken.size() > 0 and voice.spoken[-1] == PlayerHud.target_sentence)
	voice.finish()
	await _wait_real(800)
	_check("mic re-armed after Listen", fake.listen_calls > calls_before,
		"%d -> %d" % [calls_before, fake.listen_calls])

	PlayerHud.hide_speak_button()
	STTManager.error.emit(-1)
	await get_tree().process_frame
	_check("refused restart offers Speak", PlayerHud.challenge_speak_button.visible)
	_check("prompt says tap Speak", PlayerHud._challenge_status_label != null
		and PlayerHud._challenge_status_label.text.contains("Tap Speak"),
		PlayerHud._challenge_status_label.text if PlayerHud._challenge_status_label else "<none>")

	# A stuck read-aloud of one word may not keep the mic off for 5 s.
	voice.talking = false
	TTSManager.speak("cat")
	_check("short phrase watchdog <= 2.5 s", TTSManager._max_ms <= 2500, str(TTSManager._max_ms))
	TTSManager.stop()

	STTManager.listening_completed.emit(PlayerHud.target_sentence)
	await _wait(1.0)
	get_tree().paused = false
	STTManager.provider = old_stt
	TTSManager.provider = old_tts
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
