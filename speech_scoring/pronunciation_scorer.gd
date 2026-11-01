# pronunciation_scorer.gd
#
# Base interface for speech pronunciation scoring. Mirrors the SttProvider
# pattern in speech_to_text/ so callers (Enemy speech challenges) depend on an
# interface, not the platform backend. Score results arrive via the
# capture_finished signal: { "score": int, "phones": String, "ms": int, "ok": bool }.

class_name PronunciationScorer
extends Node

signal capture_started
signal capture_finished(score: int, phones: String, ms: int, ok: bool)

var last_result: Dictionary = {"score": -1, "phones": "", "ms": -1, "ok": false}


func is_available() -> bool:
	return false


func begin_capture() -> void:
	pass


func abandon_capture() -> void:
	pass


func end_capture_and_score(target_phonemes: String, on_done: Callable) -> void:
	# No scoring backend available (or capture not recording): report failure.
	last_result = {"score": -1, "phones": "", "ms": -1, "ok": false}
	capture_finished.emit(-1, "", -1, false)
	on_done.call(last_result)
