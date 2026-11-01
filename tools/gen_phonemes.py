#!/usr/bin/env python3
"""Offline generator for canonical phoneme data used by speech challenges.

Reads the game's shipped word/sentence lists (sentence_data/sentences.txt +
00_globals/global_word_tracker.gd DEFAULT_*) and emits:
  - sentence_data/phonemes.json: { "<challenge text>": "<phones, space-separated>" }
  - sentence_data/phoneme_normalization.json: { "<gruut token>": "<normalized token>" }

Phonemes come from gruut's bundled grapheme->phoneme CRF model (gruut_lang_en).
Offline/dev-time only — this is NOT run at runtime in the browser (runtime path is
the in-browser wav2vec2 scorer from tools/pronunciation_spike via the LQPron facade).

Usage: python3 tools/gen_phonemes.py
"""

import json
import os
import re
import sys

GRUU_T_G2P_MODEL = (
    "/Library/Frameworks/Python.framework/Versions/3.13/lib/python3.13/"
    "site-packages/gruut_lang_en/g2p/model.crf"
)

from gruut import g2p  # noqa: E402

DEFAULT_WORDS = [
    "hello", "water", "apple", "cat", "dog", "school", "friend", "book", "happy", "sorry",
]
DEFAULT_SENTENCES = [
    "I like cats", "My name is Tom", "I can run", "Good morning", "How are you", "I am fine",
]


def _phones(word: str) -> str:
    tagger = getattr(_phones, "_tagger", None)
    if tagger is None:
        import pycrfsuite
        tagger = pycrfsuite.Tagger()
        tagger.open(GRUU_T_G2P_MODEL)
        _phones._tagger = tagger
    g2p_model = getattr(_phones, "_model", None)
    if g2p_model is None:
        g2p_model = g2p.GraphemesToPhonemes(tagger)
        _phones._model = g2p_model
    phonemes = list(g2p_model(word))
    return " ".join(phonemes)


def _normalize(token: str) -> str:
    # Normalize espeak-style / gruut-style IPA token variants to a single canonical form.
    mapping = {
        "ɑ": "a",
        "ɪ": "i",
        "ʊ": "u",
        "ɛ": "e",
        "ɔ": "o",
        "ə": "uh",
        "ɹ": "r",
        "ɾ": "t",
        "ŋ": "n",
    }
    return mapping.get(token, token)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(here)

    sentences_path = os.path.join(project_root, "sentence_data", "sentences.txt")
    phones_by_text: dict = {}
    texts: set = set()

    if os.path.isfile(sentences_path):
        with open(sentences_path, "r", encoding="utf-8") as f:
            for line in f:
                t = line.strip().lower()
                if not t:
                    continue
                if " " in t:
                    phones = " ".join(_phones(w) for w in t.split(" "))
                else:
                    phones = _phones(t)
                phones_by_text[t] = phones
                texts.add(t)
    else:
        print(f"⚠️ sentences file not found: {sentences_path}")

    for w in DEFAULT_WORDS:
        if w not in phones_by_text:
            phones_by_text[w] = _phones(w)
            texts.add(w)
    for s in DEFAULT_SENTENCES:
        if s not in phones_by_text:
            phones_by_text[s] = " ".join(_phones(w) for w in s.split(" "))
            texts.add(s)

    with open(os.path.join(project_root, "sentence_data", "phonemes.json"), "w", encoding="utf-8") as f:
        json.dump(phones_by_text, f, indent=2, sort_keys=True)
        f.write("\n")

    normalization = {
        "ɑ": "a", "ɪ": "i", "ʊ": "u", "ɛ": "e", "ɔ": "o", "ə": "uh",
        "ɹ": "r", "ɾ": "t", "ŋ": "n",
    }
    with open(os.path.join(project_root, "sentence_data", "phoneme_normalization.json"), "w", encoding="utf-8") as f:
        json.dump(normalization, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"✅ Generated sentence_data/phonemes.json with {len(phones_by_text)} entries")
    for t in sorted(phones_by_text):
        print(f"   - {t} -> {phones_by_text[t]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
