# speech_matcher.gd
# Unified speech validation with configurable strategies

class_name SpeechMatcher extends RefCounted

enum MatchStrategy:
	STRATEGY_EXACT = 0      # Exact match (case-insensitive, trimmed)
	STRATEGY_SUBSTRING = 1  # Target phrase appears anywhere in recognized text
	STRATEGY_FUZZY = 2      # Token-based fuzzy matching (allow minor variations)
	STRATEGY_PHONETIC = 3   # Phonetic matching for ESL learners (future)

enum Difficulty:
	DIFFICULTY_EASY = 0     # Substring match, case-insensitive
	DIFFICULTY_NORMAL = 1   # Fuzzy token match
	DIFFICULTY_HARD = 2     # Exact match

static var _default_strategy: MatchStrategy = MatchStrategy.STRATEGY_SUBSTRING
static var _default_difficulty: Difficulty = Difficulty.DIFFICULTY_NORMAL

@export var strategy: MatchStrategy = MatchStrategy.STRATEGY_SUBSTRING
@export var difficulty: Difficulty = Difficulty.DIFFICULTY_NORMAL
@export var confidence_threshold: float = 0.6  # Minimum confidence for fuzzy match
@export var ignore_punctuation: bool = true
@export var ignore_case: bool = true

func _init() -> void:
	pass

func match(recognized: String, target: String) -> bool:
	if recognized.is_empty() or target.is_empty():
		return false
	
	var clean_recognized = _normalize(recognized)
	var clean_target = _normalize(target)
	
	if clean_recognized.is_empty() or clean_target.is_empty():
		return false
	
	match strategy:
		MatchStrategy.STRATEGY_EXACT:
			return _exact_match(clean_recognized, clean_target)
		MatchStrategy.STRATEGY_SUBSTRING:
			return _substring_match(clean_recognized, clean_target)
		MatchStrategy.STRATEGY_FUZZY:
			return _fuzzy_match(clean_recognized, clean_target)
		MatchStrategy.STRATEGY_PHONETIC:
			return _phonetic_match(clean_recognized, clean_target)
	
	return false

func match_with_confidence(recognized: String, target: String) -> Dictionary:
	var result = {"matched": false, "confidence": 0.0, "details": ""}
	
	if recognized.is_empty() or target.is_empty():
		result.details = "Empty input"
		return result
	
	var clean_recognized = _normalize(recognized)
	var clean_target = _normalize(target)
	
	if clean_recognized.is_empty() or clean_target.is_empty():
		result.details = "Empty after normalization"
		return result
	
	match strategy:
		MatchStrategy.STRATEGY_EXACT:
			var matched = _exact_match(clean_recognized, clean_target)
			result.matched = matched
			result.confidence = 1.0 if matched else 0.0
			result.details = "Exact match" if matched else "No exact match"
		MatchStrategy.STRATEGY_SUBSTRING:
			var matched = _substring_match(clean_recognized, clean_target)
			result.matched = matched
			result.confidence = 1.0 if matched else 0.0
			result.details = "Substring match" if matched else "Target not in recognized"
		MatchStrategy.STRATEGY_FUZZY:
			var fuzzy_result = _fuzzy_match_detailed(clean_recognized, clean_target)
			result.matched = fuzzy_result.matched
			result.confidence = fuzzy_result.confidence
			result.details = fuzzy_result.details
		MatchStrategy.STRATEGY_PHONETIC:
			var matched = _phonetic_match(clean_recognized, clean_target)
			result.matched = matched
			result.confidence = 1.0 if matched else 0.0
			result.details = "Phonetic match" if matched else "No phonetic match"
	
	return result

func _normalize(text: String) -> String:
	var result = text
	if ignore_case:
		result = result.to_lower()
	if ignore_punctuation:
		result = _strip_punctuation(result)
	return result.strip_edges()

func _strip_punctuation(text: String) -> String:
	var allowed = "abcdefghijklmnopqrstuvwxyz0123456789 "
	var result = ""
	for ch in text:
		if ch in allowed or ch == " ":
			result += ch
	return " ".join(result.split(" ", false))

func _exact_match(recognized: String, target: String) -> bool:
	return recognized == target

func _substring_match(recognized: String, target: String) -> bool:
	return target in recognized

func _fuzzy_match(recognized: String, target: String) -> bool:
	var result = _fuzzy_match_detailed(recognized, target)
	return result.matched

func _fuzzy_match_detailed(recognized: String, target: String) -> Dictionary:
	var rec_tokens = recognized.split(" ", false)
	var tgt_tokens = target.split(" ", false)
	
	if tgt_tokens.is_empty():
		return {"matched": false, "confidence": 0.0, "details": "Empty target"}
	
	if tgt_tokens.size() > rec_tokens.size():
		return {"matched": false, "confidence": 0.0, "details": "Target longer than recognized"}
	
	var best_confidence = 0.0
	var best_match = false
	var best_details = ""
	
	for i in range(rec_tokens.size() - tgt_tokens.size() + 1):
		var matches = 0
		for j in range(tgt_tokens.size()):
			if i + j < rec_tokens.size() and _tokens_similar(rec_tokens[i + j], tgt_tokens[j]):
				matches += 1
		
		var confidence = float(matches) / float(tgt_tokens.size())
		if confidence > best_confidence:
			best_confidence = confidence
			best_match = confidence >= confidence_threshold
			best_details = "Matched %d/%d tokens (%.0f%%)" % [matches, tgt_tokens.size(), confidence * 100]
	
	return {"matched": best_match, "confidence": best_confidence, "details": best_details}

func _tokens_similar(a: String, b: String) -> bool:
	if a == b:
		return true
	
	if a.length() == 0 or b.length() == 0:
		return false
	
	var max_len = max(a.length(), b.length())
	var dist = _levenshtein_distance(a, b)
	var similarity = 1.0 - float(dist) / float(max_len)
	
	return similarity >= 0.8

func _levenshtein_distance(a: String, b: String) -> int:
	var len_a = a.length()
	var len_b = b.length()
	
	if len_a == 0:
		return len_b
	if len_b == 0:
		return len_a
	
	var matrix = []
	for i in range(len_a + 1):
		matrix.append([])
		for j in range(len_b + 1):
			matrix[i].append(0)
	
	for i in range(len_a + 1):
		matrix[i][0] = i
	for j in range(len_b + 1):
		matrix[0][j] = j
	
	for i in range(1, len_a + 1):
		for j in range(1, len_b + 1):
			var cost = 0 if a[i - 1] == b[j - 1] else 1
			matrix[i][j] = min(
				matrix[i - 1][j] + 1,
				matrix[i][j - 1] + 1,
				matrix[i - 1][j - 1] + cost
			)
	
	return matrix[len_a][len_b]

func _phonetic_match(recognized: String, target: String) -> bool:
	var rec_phonetic = _to_phonetic(recognized)
	var tgt_phonetic = _to_phonetic(target)
	return _fuzzy_match(rec_phonetic, tgt_phonetic)

func _to_phonetic(text: String) -> String:
	var result = ""
	for ch in text:
		match ch:
			'c', 'k', 'q': result += 'k'
			'ph', 'f': result += 'f'
			'th': result += 't'
			'gh': result += 'g'
			'sh', 'ch': result += 's'
			'v', 'w': result += 'v'
			_ : result += ch
	return result

static func create_from_difficulty(diff: Difficulty) -> SpeechMatcher:
	var matcher = SpeechMatcher.new()
	match diff:
		Difficulty.DIFFICULTY_EASY:
			matcher.strategy = MatchStrategy.STRATEGY_SUBSTRING
			matcher.confidence_threshold = 0.5
		Difficulty.DIFFICULTY_NORMAL:
			matcher.strategy = MatchStrategy.STRATEGY_FUZZY
			matcher.confidence_threshold = 0.6
		Difficulty.DIFFICULTY_HARD:
			matcher.strategy = MatchStrategy.STRATEGY_EXACT
			matcher.confidence_threshold = 1.0
	return matcher

static func get_default_strategy() -> MatchStrategy:
	return _default_strategy

static func set_default_strategy(s: MatchStrategy) -> void:
	_default_strategy = s

static func get_default_difficulty() -> Difficulty:
	return _default_difficulty

static func set_default_difficulty(d: Difficulty) -> void:
	_default_difficulty = d