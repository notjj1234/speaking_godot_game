# phonetic_matcher.gd
#
# Reduced-coverage English phonetic helpers for speech-challenge acceptance.
# Provides Double Metaphone-style keys, token similarity, and fuzzy transcript
# containment for all platforms (web + Android). Used by the enemy speech
# challenge acceptance logic while a phoneme scorer is unavailable or for words
# without canonical phoneme data.

class_name PhoneticMatcher
extends RefCounted

const FUZZY_MIN_SIMILARITY := 0.72
const _VOWELS := "aeiou"
const _DIGRAPHS := ["th", "sh", "ch", "ck", "gh", "sch"]


static func key(word: String) -> String:
	# Phonetic key: lowercase, vowels stripped, digraph pairs collapsed to the
	# leading consonant, digits stripped. Reduced-coverage Metaphone-like key.
	var w := word.to_lower().strip_edges()
	var out := ""
	var i := 0
	while i < w.length():
		var pair := w.substr(i, 2)
		if i + 1 < w.length() and _DIGRAPHS.has(pair):
			out += pair.substr(0, 1)
			i += 2
			continue
		var ch := w.substr(i, 1)
		if _VOWELS.contains(ch):
			i += 1
			continue
		out += ch
		i += 1
	return out


static func similarity(a: String, b: String) -> float:
	var ja := _tokens(a)
	var jb := _tokens(b)
	var sa := " ".join(ja)
	var sb := " ".join(jb)
	if sa == "" and sb == "":
		return 1.0
	if sa == "" or sb == "":
		return 0.0
	return 1.0 - float(_levenshtein(sa, sb)) / float(maxf(sa.length(), sb.length()))


static func transcript_contains_fuzzy(haystack: String, target: String, min_similarity: float = FUZZY_MIN_SIMILARITY) -> bool:
	var h: PackedStringArray = _tokens(haystack)
	var t: PackedStringArray = _tokens(target)
	if h.is_empty() or t.is_empty():
		return false
	if h.size() < t.size():
		return false
	if " ".join(h) == " ".join(t):
		return true
	var best := 0.0
	for j in range(h.size() - t.size() + 1):
		var sim := 0.0
		for k in range(t.size()):
			sim += _token_similarity(h[j + k], t[k])
		sim = sim / float(t.size())
		if sim > best:
			best = sim
	return best >= min_similarity


static func _tokens(text: String) -> PackedStringArray:
	var t := text.to_lower().strip_edges()
	var parts: PackedStringArray = t.split(" ", false)
	var out: PackedStringArray = PackedStringArray()
	for p in parts:
		var k := p.strip_edges()
		if k != "":
			out.append(k)
	return out


static func _token_similarity(a: String, b: String) -> float:
	if a == b:
		return 1.0
	return 1.0 - float(_levenshtein(a, b)) / float(maxf(a.length(), b.length()))


static func _levenshtein(a: String, b: String) -> int:
	var m := a.length()
	var n := b.length()
	var d: Array[int] = []
	for i in range(n + 1):
		d.append(i)
	for i in range(1, m + 1):
		var prev: int = d[0]
		d[0] = i
		for j in range(1, n + 1):
			var tmp: int = d[j]
			var cost := 1 if a.substr(i - 1, 1) != b.substr(j - 1, 1) else 0
			d[j] = mini(mini(prev + 1, d[j] + 1), d[j - 1] + cost)
			prev = tmp
	return d[n]
