extends Node
## Resource integrity: every ext_resource uid in game scenes must resolve (via
## ResourceUID, not string compare — equivalent uid spellings decode to the same
## id) to the file its path points at. A uid that resolves elsewhere loads the
## wrong file; an unknown one only loads by silent path fallback.
## Run headless on a scratch copy (after --import):
##   Godot --headless --path <copy> res://tools/tests/test_resource_uids.tscn

const SKIP_DIRS := ["res://.godot", "res://addons", "res://legacy", "res://godot-whisper",
		"res://build", "res://android", "res://tools", "res://graphify-out"]
## Unreferenced by any game scene (see the bug audit): its script uid names
## tutorial_popup.gd while its path says tutorial_dialog.gd. Not shipped.
const DORMANT := [
	"res://levels/tutorial_items/tutorial_popup.tscn",
]

var passes := 0
var failures := 0


func _scenes(dir: String, out: Array) -> void:
	for skip in SKIP_DIRS:
		if dir.begins_with(skip):
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_scenes(dir.path_join(sub), out)


func _ready() -> void:
	var files: Array = []
	_scenes("res://", files)
	var line_re := RegEx.create_from_string('\\[ext_resource[^\\]]*\\buid="(uid://[^"]+)"[^\\]]*\\bpath="([^"]+)"')
	var checked := 0
	for file in files:
		if DORMANT.has(file):
			continue
		var text := FileAccess.get_file_as_string(file)
		for m in line_re.search_all(text):
			checked += 1
			var uid := m.get_string(1)
			var path := m.get_string(2)
			var id := ResourceUID.text_to_id(uid)
			var ok := id != ResourceUID.INVALID_ID and ResourceUID.has_id(id) \
					and ResourceUID.get_id_path(id) == path
			if not ok:
				failures += 1
				var actual := ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else "<unknown uid>"
				print("FAIL %s: %s for %s resolves to %s" % [file, uid, path, actual])
	passes = checked - failures
	print("PASS %d ext_resource uids match their paths" % passes)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
