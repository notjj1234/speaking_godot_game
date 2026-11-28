extends Node2D
## IntentMatcher regressions. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_intent_matcher.tscn

const I := {
	"might": ["hit harder", "stronger", "attack", "might"],
	"vitality": ["tougher", "more health", "hp", "vitality"],
	"bye": ["bye", "nothing", "no thanks"],
}

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
	_expect_intent("hit_harder", "I wanna hit harder", "might")
	_expect_intent("tougher", "make me tougher please", "vitality")
	_expect_intent("nothing_is_bye", "nothing thanks", "bye")
	_expect_intent("hp_not_in_happy", "I am happy", "")
	_expect_intent("empty", "", "")
	_expect_intent("fuzzy_stronga", "make me stronga", "might")
	_check("contains_ignores_case_and_punct", IntentMatcher.contains_phrase("Good  Morning!", "good morning"))
	_check("contains_rejects_other_phrase", not IntentMatcher.contains_phrase("i can run", "i can swim"))
	var n := IntentMatcher.normalize("Hello, World!!")
	_check("normalize", n == "hello world", "got '%s'" % n)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _expect_intent(name: String, transcript: String, want: String) -> void:
	var got := IntentMatcher.best_intent(transcript, I)
	_check(name, got == want, "got '%s', want '%s'" % [got, want])
