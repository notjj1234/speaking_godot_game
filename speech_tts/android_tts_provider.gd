# android_tts_provider.gd
#
# Android TTS backend built on DisplayServer.tts_* — no plugin, AAR, or extra
# dependency. Reports unavailable when the device exposes no voices, which is
# the brief's definition of "no TTS on this device".

class_name AndroidTTSProvider
extends TTSSpeechProvider

const TTS_RATE := 0.95
const TTS_VOLUME := 100

var _speaking := false
var _voice_id := ""
var _utterance_id := 0


func _ready() -> void:
	if OS.get_name() != "Android":
		return
	# DisplayServer utterance callbacks are global state; only this provider
	# registers them, so the manager must not.
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended)
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_canceled)


func is_available() -> bool:
	if OS.get_name() != "Android":
		return false
	# Never cache: the voice list can be empty for a moment after boot or
	# right after a TTS engine is installed.
	return DisplayServer.tts_get_voices().size() > 0


func speak(text: String) -> bool:
	var cleaned := text.strip_edges()
	if cleaned.is_empty() or not is_available():
		return false

	DisplayServer.tts_stop()
	_voice_id = _pick_voice()
	_utterance_id += 1
	DisplayServer.tts_speak(cleaned, _voice_id, TTS_VOLUME, 1.0, TTS_RATE, _utterance_id, true)
	_speaking = true
	speech_started.emit()
	return true


func stop() -> void:
	if OS.get_name() != "Android":
		return
	DisplayServer.tts_stop()
	_finish()


func is_speaking() -> bool:
	if not _speaking:
		return false
	return DisplayServer.tts_is_speaking()


func _pick_voice() -> String:
	# Prefer a clear American English system voice over the first "en" hit
	# (which can be a quiet / novelty pack on some devices).
	var best_id := ""
	var best_score := -9999
	for voice in DisplayServer.tts_get_voices():
		var language := String(voice.get("language", "")).to_lower().replace("_", "-")
		var name := String(voice.get("name", "")).to_lower()
		var id := String(voice.get("id", ""))
		var score := 0
		if language == "en-us" or language.begins_with("en-us"):
			score += 100
		elif language.begins_with("en"):
			score += 30
		else:
			continue
		if "us" in name or "america" in name or "english (united states)" in name:
			score += 40
		if "whisper" in name or "compact" in name or "novelty" in name:
			score -= 200
		if "uk" in name or "gb" in name or "british" in name:
			score -= 60
		if score > best_score:
			best_score = score
			best_id = id
	if best_id != "":
		return best_id

	var english := DisplayServer.tts_get_voices_for_language("en")
	if english.size() > 0:
		return english[0]
	var voices := DisplayServer.tts_get_voices()
	if voices.size() > 0:
		print("⚠️ AndroidTTSProvider: no English voice, using default.")
		return String(voices[0].get("id", ""))
	return ""


func _on_utterance_ended(id: int) -> void:
	if id != _utterance_id:
		return
	_finish()


func _on_utterance_canceled(id: int) -> void:
	if id != _utterance_id:
		return
	_finish()


func _finish() -> void:
	if not _speaking:
		return
	_speaking = false
	speech_finished.emit()
