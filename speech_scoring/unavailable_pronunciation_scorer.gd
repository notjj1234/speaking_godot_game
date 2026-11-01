# unavailable_pronunciation_scorer.gd
#
# Scorer used when the real scoring backend is not available on the current
# platform (non-web, spike not approved yet). Always reports failure so callers
# fall back to transcript-level acceptance.

class_name UnavailablePronunciationScorer
extends PronunciationScorer


func is_available() -> bool:
	return false


func begin_capture() -> void:
	pass


func abandon_capture() -> void:
	pass


# Inherits end_capture_and_score from PronunciationScorer (reports failure via
# capture_finished + on_done) — no override needed.
