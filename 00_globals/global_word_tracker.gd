# global_word_tracker.gd

extends Node

signal word_list_updated  

var spoken_words: Dictionary = {}
var last_added_word: String = ""
var last_add_time: int = 0  

var available_words: Array = []  # ✅ List of words from Google Sheets
var available_sentences: Array = []  # ✅ List of sentences from Google Sheets

var speech_challenge_active: bool = false

var next_challenge_type := "word"  # Start with a word

const LOCAL_SENTENCES_PATH := "res://sentence_data/sentences.txt"

func _ready() -> void:
	if not get_tree().root.has_node("WordTracker"):
		get_tree().root.add_child(self)  
	print("✅ WordTracker initialized.")

	# Local fallback first so challenges work even when Sheets URL is a placeholder
	_load_local_fallback()

	# Sheets can overwrite local data if/when the request succeeds
	fetch_words_and_sentences()

	emit_signal("word_list_updated")

# ✅ Fetch words and sentences from Google Sheets
func fetch_words_and_sentences():
	var sheets_manager = get_node("/root/SheetsManager") if get_tree().root.has_node("/root/SheetsManager") else null
	if sheets_manager:
		sheets_manager.words_loaded.connect(_on_words_loaded)
		sheets_manager.sentences_loaded.connect(_on_sentences_loaded)
		sheets_manager.fetch_sentences_and_words()
	else:
		print("❌ [ERROR] SheetsManager not found! Using local sentence fallback.")
		_load_local_fallback()

# Load res://sentence_data/sentences.txt into available_words / available_sentences
func _load_local_fallback() -> void:
	if not FileAccess.file_exists(LOCAL_SENTENCES_PATH):
		print("❌ [ERROR] Local sentences file not found:", LOCAL_SENTENCES_PATH)
		return

	var file := FileAccess.open(LOCAL_SENTENCES_PATH, FileAccess.READ)
	if file == null:
		print("❌ [ERROR] Could not open local sentences file:", LOCAL_SENTENCES_PATH)
		return

	var words: Array = []
	var sentences: Array = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		if line.split(" ").size() > 1:
			sentences.append(line)
		else:
			words.append(line)
	file.close()

	if not words.is_empty():
		available_words = words
	if not sentences.is_empty():
		available_sentences = sentences

	if available_words.is_empty() and available_sentences.is_empty():
		print("⚠️ [WARNING] Local sentences file was empty.")
	else:
		print("✅ [INFO] Loaded local fallback — words:", available_words.size(), "sentences:", available_sentences.size())

# ✅ Store loaded words from Google Sheets
func _on_words_loaded(words: Array):
	if words.is_empty():
		print("⚠️ [WARNING] Sheets returned no words; keeping local fallback.")
		return
	available_words = words
	print("✅ [INFO] Loaded words from Google Sheets:", available_words)

# ✅ Store loaded sentences from Google Sheets
func _on_sentences_loaded(sentences: Array):
	if sentences.is_empty():
		print("⚠️ [WARNING] Sheets returned no sentences; keeping local fallback.")
		return
	available_sentences = sentences
	print("✅ [INFO] Loaded sentences from Google Sheets:", available_sentences)

# ✅ Pick a random word or sentence for speech challenge, alternating between word and sentence
func get_random_speech_challenge() -> String:
	if available_words.is_empty() and available_sentences.is_empty():
		_load_local_fallback()
	if available_words.is_empty() and available_sentences.is_empty():
		print("❌ [ERROR] No words or sentences available for speech challenge.")
		return "No words available."

	var selected_challenge = ""

	# ✅ Enforce alternation but allow fallback if needed
	if next_challenge_type == "word":
		if not available_words.is_empty():
			selected_challenge = available_words[randi() % available_words.size()]
			next_challenge_type = "sentence"  # Switch to sentence next
		else:
			selected_challenge = available_sentences[randi() % available_sentences.size()]
			next_challenge_type = "word"
	elif next_challenge_type == "sentence":
		if not available_sentences.is_empty():
			selected_challenge = available_sentences[randi() % available_sentences.size()]
			next_challenge_type = "word"
		else:
			selected_challenge = available_words[randi() % available_words.size()]
			next_challenge_type = "sentence"

	print("✅ [INFO] Selected challenge:", selected_challenge)
	return selected_challenge

# ✅ Add spoken word or sentence
func add_spoken_word(word: String) -> bool:
	word = word.strip_edges().to_lower()
	var current_time = Time.get_ticks_msec()  

	# ✅ Fix: Prevent duplicate words within 3 seconds
	if word == last_added_word and current_time - last_add_time < 3000:
		print("❌ Duplicate word detected too soon, ignoring:", word)
		return false  

	last_added_word = word  
	last_add_time = current_time  

	print("✅ Adding word to list:", word)

	# ✅ Fix: Properly update count in the dictionary
	spoken_words[word] = spoken_words.get(word, 0) + 1

	print("✅ Updated word list:", spoken_words)

	emit_signal("word_list_updated")  
	print("✅ Emitted word_list_updated signal")

	# ✅ Fix: Differentiate between word and sentence before saving
	if word.split(" ").size() > 1:  # ✅ Correctly check multi-word sentences
		save_sentence_to_google_sheets(word, spoken_words[word])
	else:
		save_word_to_google_sheets(word, spoken_words[word])

	return true  

func get_word_list() -> String:
	if spoken_words.is_empty():
		return "No words recorded."

	var word_list = ""
	for word in spoken_words.keys():
		word_list += word + ": " + str(spoken_words[word]) + "\n"
	return word_list

func clear_word_list() -> void:
	spoken_words.clear()
	last_added_word = ""
	last_add_time = 0
	emit_signal("word_list_updated")
	print("✅ Word list cleared.")

# ✅ Save word to Google Sheets with device ID and name
func save_word_to_google_sheets(word: String, count: int):
	var sheets_manager = get_node("/root/SheetsManager") if get_tree().root.has_node("/root/SheetsManager") else null
	if sheets_manager and sheets_manager.has_method("save_word_entry"):
		print("📤 [DEBUG] Sending word to Google Sheets: Word =", word, "| Count =", count)
		print("📤 [DEBUG] Device ID =", get_device_id(), "| Device Name =", get_device_name())
		sheets_manager.save_word_entry(word, count, get_device_id(), get_device_name())
	else:
		print("❌ [ERROR] SheetsManager not found or missing method: save_word_entry")

# ✅ Save sentence to Google Sheets with device ID and name
func save_sentence_to_google_sheets(sentence: String, count: int):
	var sheets_manager = get_node("/root/SheetsManager") if get_tree().root.has_node("/root/SheetsManager") else null
	if sheets_manager and sheets_manager.has_method("save_sentence_entry"):
		print("📤 [DEBUG] Sending sentence to Google Sheets:", sentence, "| Count:", count)
		sheets_manager.save_sentence_entry(sentence, count, get_device_id(), get_device_name())
	else:
		print("❌ [ERROR] SheetsManager not found or missing method: save_sentence_entry")

func get_word_count() -> int:
	""" Returns the total number of unique words recorded. """
	return spoken_words.size()

func get_paginated_word_list(page: int, words_per_page: int) -> Array:
	if spoken_words.is_empty():
		return []  

	var word_keys = spoken_words.keys()
	word_keys.sort()

	# ✅ Fix: Ensure sorting always works properly
	word_keys.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0 if a is String and b is String else false)

	var start_index = page * words_per_page
	var end_index = min(start_index + words_per_page, word_keys.size())

	var result = []
	for i in range(start_index, end_index):
		var word = word_keys[i]
		result.append(word + ": " + str(spoken_words[word]))

	print("✅ Paginated words:", result)  # Debugging output
	return result

func get_device_id() -> String:
	return OS.get_unique_id()

# ✅ Get the device name in a flexible way (fixed OS.execute parameters)
func get_device_name() -> String:
	var result = []
	
	# ✅ 1. Try fetching user-defined device name (net.hostname)
	OS.execute("getprop", ["net.hostname"], result)
	if result.size() > 0 and result[0] != "":
		return result[0].strip_edges()

	# ✅ 2. Try getting manufacturer + model name
	var manufacturer_result = []
	var model_result = []

	OS.execute("getprop", ["ro.product.manufacturer"], manufacturer_result)
	OS.execute("getprop", ["ro.product.model"], model_result)

	var manufacturer = manufacturer_result[0] if manufacturer_result.size() > 0 else ""
	var model = model_result[0] if model_result.size() > 0 else ""

	if manufacturer != "" and model != "":
		return manufacturer.strip_edges() + " " + model.strip_edges()
	elif model != "":
		return model.strip_edges()

	return "Unknown Device"
