# phonetic_matcher_test.gd
#
# Quick runnable test for PhoneticMatcher (speech_scoring). Extend extends
# SceneTree so it can run standalone from the editor ("Run Current Scene") or
# via `godot --headless` when a binary becomes available. Prints ✅ on pass,
# ❌ + nonzero exit on fail. Uses verified expected values (computed via
# Python cross-check): sim("hello","helo")=0.8, sim("tomato","potato")=0.6667,
# sim("water","woter")=0.8, sim("hello","water")=0.0, sim("watter","water")=0.8333.

extends SceneTree

const PH := "res://speech_scoring/phonetic_matcher.gd"

var failures := 0


func _fail(name: String, got, want: float) -> void:
	failures += 1
	print("❌ ", name, " — got ", got, " want ", want)


func _check(name: String, cond: bool) -> void:
	if cond:
		print("✅ ", name)
	else:
		_fail(name, false, true)


func _init() -> void:
	var m: PhoneticMatcher = load(PH).new()
	_check("similarity(hello,helo)==0.8", absf(m.similarity("hello", "helo") - 0.8) < 0.001)
	_check("similarity(tomato,potato)<1.0 and >0.4 and symmetric", (m.similarity("tomato", "potato") > 0.4) and (m.similarity("potato", "tomato") > 0.4) and (m.similarity("tomato", "potato") < 1.0))
	_check("similarity(hello,water)==0.0", absf(m.similarity("hello", "water") - 0.0) < 0.001)
	_check("similarity(empty,empty)==1.0", m.similarity("", "") == 1.0)
	_check("similarity(abc,empty)==0.0", m.similarity("abc", "") == 0.0)
	_check("key(water)==key(woter)", m.key("water") == m.key("woter"))
	_check("key(water)!=key(hello)", m.key("water") != m.key("hello"))
	_check("key(hello)!=key(helo)", m.key("hello") != m.key("helo"))
	_check("transcript_contains_fuzzy(hello world,hello world)==true", m.transcript_contains_fuzzy("hello world", "hello world"))
	_check("transcript_contains_fuzzy(this is a book on the table,a book)==true", m.transcript_contains_fuzzy("this is a book on the table", "a book"))
	_check("transcript_contains_fuzzy(watter,water,0.5)==true", m.transcript_contains_fuzzy("watter", "water", 0.5))
	_check("transcript_contains_fuzzy(this is a red small dog,a dot)==false", not m.transcript_contains_fuzzy("this is a red small dog", "a dot"))
	_check("transcript_contains_fuzzy(Hello  World ,hello world)==true", m.transcript_contains_fuzzy("Hello  World ", "hello world"))

	quit(0 if failures == 0 else 1)
