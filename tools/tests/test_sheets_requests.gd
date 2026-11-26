extends Node
## F18 regression: with the placeholder Apps Script URL every Sheets request
## fails to start, and request_completed never fires, so the HTTPRequest node
## must be freed on that path too. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_sheets_requests.tscn

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _http_children() -> int:
	var n := 0
	for c in SheetsManager.get_children():
		if c is HTTPRequest and not c.is_queued_for_deletion():
			n += 1
	return n


func _ready() -> void:
	for i in 5:
		await get_tree().process_frame
	_check("boot fetches leave no HTTPRequest behind", _http_children() == 0,
			"%d left" % _http_children())
	for word in ["apple", "water", "book"]:
		WordTracker.add_spoken_word(word)
	for i in 3:
		await get_tree().process_frame
	_check("failed word saves leave no HTTPRequest behind", _http_children() == 0,
			"%d left" % _http_children())
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
