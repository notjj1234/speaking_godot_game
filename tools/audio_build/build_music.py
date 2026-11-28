#!/usr/bin/env python3
"""Composes the game's original 8-bit music into audio/music/<track>.ogg.

A small NES-style sequencer: two pulse waves (lead and harmony), a stepped
triangle bass and noise drums. Melodies are written by hand below; bass,
harmony and drums come from each song's chord chart and a named style, so a
song is one readable block. Stdlib only and deterministic (seeded noise);
encoding uses the ffmpeg on this machine (native vorbis encoder).

    python3 tools/audio_build/build_music.py            # render every track
    python3 tools/audio_build/build_music.py meadow     # render some tracks
    python3 tools/audio_build/build_music.py --check    # verify committed files

Notation, on an eighth-note grid (8 steps a bar in 4/4, 6 in 3/4):
  "G4"  a note    "-"  hold the previous note    "."  rest    "|"  bar line
Chords: one or two per bar ("F C" splits the bar), e.g. "Am | F | G7 | E".
"""
from __future__ import annotations

import array
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "audio", "music")
TAIL_SEC = 2.5  # rendered past the loop end, then folded onto the start
PEAK_LIMIT = 0.85  # about -1.4 dBFS
TARGET_RMS = 0.16
MIN_SNR_DB = 22.0
ENCODE_RATE = 44100
ENCODE_QUALITY = 3

LEAD_VOL = 0.30
HARM_VOL = 0.12
BASS_VOL = 0.42
ECHO_DELAY_BEATS = 0.75
ECHO_FEEDBACK = 0.35
ECHO_LEVEL = 0.45


# ---------------------------------------------------------------- songs

SONGS: dict[str, dict] = {
    # Title: a hopeful, heroic march.
    "title": dict(
        bpm=120, beats=4, duty=0.25, harm_duty=0.5,
        bass="march", harm="stab", drums="march",
        chords=["C | G | Am | F | C | G | F G | C",
                "F | G | Em | Am | F | G | Dm G | C"],
        lead=[
            "C5 - - G4 C5 - E5 - | D5 - - B4 G4 - - - | A4 - C5 - E5 - D5 C5 | C5 - A4 - F4 - - - |"
            "E5 - - C5 G5 - - E5 | D5 - G5 - F5 E5 D5 - | C5 - A4 C5 B4 - D5 - | C5 - - - G4 - - -",
            "A5 - - G5 F5 - E5 - | D5 - - E5 F5 - G5 - | E5 - - D5 B4 - G4 - | A4 - B4 - C5 - E5 - |"
            "F5 - E5 - D5 - C5 - | B4 - C5 - D5 - G5 - | F5 - E5 - D5 - B4 - | C5 - - - - - . .",
        ],
        form="AB",
    ),
    # Tutorial: light and friendly, unhurried.
    "tutorial": dict(
        bpm=100, beats=4, duty=0.5, harm_duty=0.125,
        bass="half", harm="arp", drums="light",
        chords=["F | Bb | C | F | Dm | Bb | C | F",
                "Bb | F | Gm | C | Bb | F | Gm C | F"],
        lead=[
            "F4 - A4 - C5 - A4 - | Bb4 - D5 - F5 - D5 - | E5 - D5 - C5 - Bb4 - | A4 - - - F4 - . . |"
            "D5 - F5 - A5 - F5 - | D5 - - C5 Bb4 - D5 - | C5 - E5 - G5 - E5 - | F5 - - - . . . .",
            "D5 - C5 - Bb4 - D5 - | C5 - A4 - F4 - A4 - | Bb4 - A4 - G4 - Bb4 - | A4 - G4 - E4 - C4 - |"
            "F4 - Bb4 - D5 - F5 - | E5 - F5 - C5 - A4 - | Bb4 - G4 - C5 - E5 - | F5 - - - - - . .",
        ],
        form="AB",
    ),
    # Meadow (stages 1-19): bright and bouncy.
    "meadow": dict(
        bpm=132, beats=4, duty=0.25, harm_duty=0.125,
        bass="octave", harm="arp", drums="rock",
        chords=["G | C | G | D | G | C | Am D | G",
                "Em | C | G | D | Em | C | A7 | D",
                "C | D | Bm | Em | C | D | C D | G"],
        lead=[
            "G4 B4 D5 B4 G5 - D5 - | E5 - C5 E5 G5 - E5 - | D5 B4 G4 B4 D5 - G5 - | F#5 - E5 - D5 - A4 - |"
            "B4 - D5 - G5 F#5 G5 A5 | G5 - E5 - C5 - E5 - | C5 - A4 - D5 - F#5 - | G5 - - - G4 - . .",
            "E5 - G5 - B5 - G5 - | A5 - G5 - E5 - C5 - | D5 - G5 - B4 - D5 - | A4 - - B4 C5 - D5 - |"
            "E5 - E5 F#5 G5 - E5 - | C5 - E5 - G5 - E5 - | C#5 - E5 - G5 - E5 - | F#5 - - - D5 - . .",
            "E5 - - - G5 - - - | F#5 - - - A5 - - - | D5 - - - F#5 - - - | G5 - - - E5 - - - |"
            "E5 - G5 - C6 - G5 - | F#5 - A5 - D6 - A5 - | G5 - E5 - F#5 - D5 - | G5 - - - - - . .",
        ],
        form="ABCA",
    ),
    # Stone Ruins (stages 21-39): mysterious D dorian with an echoing lead.
    "ruins": dict(
        bpm=104, beats=4, duty=0.5, harm_duty=0.125, echo=True,
        bass="slow", harm="arp_slow", drums="sparse",
        chords=["Dm | G | Dm | C | Dm | G | F C | Dm",
                "F | C | G | Am | F | Em | G | A",
                "Dm | Dm | C | C | Bb | Bb | A | A"],
        lead=[
            "D5 - - - A4 - - - | B4 - - - D5 - G4 - | F5 - E5 - D5 - - - | E5 - - - C5 - - - |"
            "A5 - - - F5 - D5 - | G5 - - - B4 - D5 - | C5 - A4 - G4 - E4 - | D4 - - - - - . .",
            "A4 - C5 - F5 - - - | E5 - - - G5 - - - | D5 - B4 - G4 - - - | C5 - - - E5 - A4 - |"
            "F5 - - - A5 - - - | G5 - - - E5 - B4 - | D5 - - - B4 - G4 - | C#5 - - - E5 - - -",
            ". . . . A5 - - - | F5 - - - D5 - - - | . . . . G5 - - - | E5 - - - C5 - - - |"
            ". . D5 - F5 - - - | D5 - - - Bb4 - - - | C#5 - - - E5 - - - | A4 - - - - - . .",
        ],
        form="ABCA",
    ),
    # Ashen Camp (stages 41-59): E phrygian over war drums.
    "ashen": dict(
        bpm=144, beats=4, duty=0.25, harm_duty=0.5,
        bass="gallop", harm="power", drums="war",
        chords=["E5 | F5 | E5 | D5 | E5 | F5 | G5 F5 | E5",
                "Am | G | F | E | Am | G | F | E",
                "E5 | E5 | D5 | D5 | C5 | D5 | F5 | E5"],
        lead=[
            "E5 - E5 F5 E5 - B4 - | F5 - - E5 D5 - C5 - | E5 - G5 - F5 E5 D5 E5 | D5 - - - A4 - - - |"
            "B5 - A5 G5 F5 - E5 - | F5 - G5 - A5 - C6 - | B5 - A5 - G5 - F5 - | E5 - - - E4 - . .",
            "A5 - - - E5 - C5 - | D5 - B4 - G4 - B4 - | C5 - A4 - F4 - A4 - | B4 - - - G#4 - E4 - |"
            "C5 - E5 - A5 - G5 - | F5 - D5 - B4 - D5 - | A5 - G5 - F5 - E5 - | E5 - - - B4 - . .",
            "E5 . . . E5 . . . | E5 . E5 . F5 - - . | D5 . . . D5 . . . | D5 . D5 . E5 - - . |"
            "C5 . . . C5 . . . | D5 . . . D5 . . . | F5 - - - G5 - - - | F5 - E5 - - - . .",
        ],
        form="ABCA",
    ),
    # Frozen Hollow (stages 61-79): sparse, icy bells with an echo.
    "frozen": dict(
        bpm=96, beats=4, duty=0.125, harm_duty=0.125, echo=True,
        bass="slow", harm="arp_high", drums="ice",
        chords=["Am | F | C | G | Am | F | Dm | E",
                "F | G | Em | Am | F | G | E | E",
                "Am | Am | F | F | Dm | Dm | E | E"],
        lead=[
            "E5 - - - A5 - - - | C6 - - - B5 - A5 - | G5 - - - E5 - - - | D5 - - - B4 - - - |"
            "C5 - E5 - A5 - - - | A5 - G5 - F5 - - - | F5 - E5 - D5 - - - | E5 - - - G#4 - - -",
            "F5 - - - A5 - C6 - | B5 - - - G5 - D5 - | E5 - - - G5 - B5 - | A5 - - - - - E5 - |"
            "F5 - - - E5 - D5 - | D5 - - - B4 - G4 - | G#4 - B4 - D5 - E5 - | E5 - - - - - . .",
            ". . . . . . . . | E6 - - - - - . . | . . . . . . . . | C6 - - - A5 - . . |"
            ". . . . . . . . | F5 - - - D5 - . . | . . . . . . . . | B5 - - - G#5 - . .",
        ],
        form="ABCA",
    ),
    # Slime King: a comic, menacing bounce.
    "boss_slime": dict(
        bpm=150, beats=4, duty=0.5, harm_duty=0.25,
        bass="bounce", harm="stab", drums="bounce",
        chords=["Cm | Cm | Ab | G | Cm | Cm | Ab | G",
                "Fm | Cm | Fm | G | Ab | Bb | Ab | G"],
        lead=[
            "C5 . G4 . C5 . Eb5 . | D5 . Eb5 . D5 . C5 . | C5 . Ab4 . Eb4 . Ab4 . | B4 - - . G4 . B4 . |"
            "Eb5 . C5 . G5 . Eb5 . | F5 . Eb5 . D5 . Eb5 . | C5 . Eb5 . Ab5 . G5 . | G5 - F5 - D5 - B4 -",
            "Ab5 . F5 . C5 . F5 . | G5 . Eb5 . C5 . Eb5 . | F5 . Ab5 . C6 . Ab5 . | G5 - - - D5 - B4 - |"
            "C6 . Ab5 . Eb5 . C5 . | D5 . F5 . Bb5 . F5 . | Eb5 . C5 . Ab4 . C5 . | B4 . D5 . G5 - - -",
        ],
        form="AB",
    ),
    # Bone Captain: a spooky skeleton march in E harmonic minor.
    "boss_bone": dict(
        bpm=138, beats=4, duty=0.25, harm_duty=0.5,
        bass="march", harm="stab", drums="march",
        chords=["Em | B | Em | B | Am | Em | C B | Em",
                "Am | D#dim | Em | C | Am | B | C | B"],
        lead=[
            "E5 . E5 . B4 . E5 G5 | F#5 . D#5 . B4 . D#5 . | E5 . G5 . B5 . G5 E5 | D#5 - - - B4 - . . |"
            "C6 . B5 . A5 . E5 . | G5 . F#5 . E5 . B4 . | C5 . E5 . D#5 . F#5 . | E5 - - - . . . .",
            "A4 . C5 . E5 . A5 . | F#5 . A5 . D#5 . C5 . | B4 . E5 . G5 . B5 . | C6 - B5 - A5 - G5 - |"
            "A5 . E5 . C5 . E5 . | D#5 . F#5 . B5 . A5 . | G5 . E5 . C5 . G5 . | F#5 - D#5 - B4 - - -",
        ],
        form="AB",
    ),
    # Orc Warlord: heavy, pounding power fifths (F# phrygian dominant).
    "boss_orc": dict(
        bpm=120, beats=4, duty=0.5, harm_duty=0.5,
        bass="pound", harm="power", drums="war",
        chords=["F#5 | G5 | F#5 | E5 | F#5 | G5 | D5 E5 | F#5",
                "D5 | E5 | F#5 | F#5 | D5 | E5 | G5 | F#"],
        lead=[
            "F#4 - - - F#4 - G4 - | G4 - - - A#4 - G4 - | F#4 - A#4 - C#5 - B4 - | A#4 - - - E4 - - - |"
            "C#5 - - - D5 - C#5 - | B4 - D5 - G5 - - - | F#5 - E5 - D5 - C#5 - | F#4 - - - - - . .",
            "D5 - - - A#4 - D5 - | E5 - - - B4 - E5 - | F#5 - E5 - D5 - C#5 - | A#4 - - - F#4 - - - |"
            "D5 - E5 - F#5 - G5 - | E5 - F#5 - G5 - A#5 - | B5 - - - G5 - D5 - | C#5 - A#4 - F#4 - - -",
        ],
        form="AB",
    ),
    # Frost Bandit: fast and sharp, B minor.
    "boss_frost": dict(
        bpm=168, beats=4, duty=0.125, harm_duty=0.25,
        bass="gallop", harm="arp", drums="fast",
        chords=["Bm | G | D | A | Bm | G | Em | F#",
                "G | A | F#m | Bm | G | A | F# | F#",
                "Em | Bm | G | A | Em | Bm | C#dim | F#"],
        lead=[
            "B4 D5 F#5 D5 B5 F#5 D5 F#5 | G5 D5 B4 D5 G5 B5 G5 D5 | F#5 A5 D6 A5 F#5 D5 A4 D5 | E5 C#5 A4 C#5 E5 - - - |"
            "D6 C#6 B5 F#5 D5 F#5 B5 - | B5 A5 G5 D5 B4 D5 G5 - | E5 G5 B5 G5 E5 G5 B5 E6 | C#6 - A#5 - F#5 - - -",
            "B5 - - - A5 - G5 - | A5 - - - E5 - C#5 - | F#5 - - - A5 - C#6 - | B5 - - - - - F#5 - |"
            "G5 - A5 - B5 - D6 - | C#6 - B5 - A5 - E5 - | F#5 - A#5 - C#6 - E6 - | F#6 - - - - - . .",
            "E5 . G5 . B5 . E6 . | D6 . B5 . F#5 . D5 . | G5 . B5 . D6 . B5 . | C#6 . A5 . E5 . C#5 . |"
            "E6 . B5 . G5 . E5 . | F#5 . B5 . D6 . F#6 . | E6 . C#6 . G5 . E5 . | A#5 - C#6 - F#5 - - -",
        ],
        form="ABC",
    ),
    # Camp: a calm campfire waltz with a crackling fire.
    "camp": dict(
        bpm=84, beats=3, duty=0.25, harm_duty=0.125,
        bass="waltz", harm="waltz", drums="fire",
        chords=["Bb | Gm | Eb | F | Bb | Gm | Cm F | Bb",
                "Eb | Bb | Cm | F | Eb | Bb | Cm F | Bb"],
        lead=[
            "D5 - - - F5 - | D5 - Bb4 - G4 - | G4 - - - Bb4 - | A4 - - - - - |"
            "F4 - Bb4 - D5 - | G5 - F5 - D5 - | Eb5 - C5 - A4 - | Bb4 - - - . .",
            "G5 - - - Eb5 - | F5 - - - D5 - | Eb5 - D5 - C5 - | C5 - - - A4 - |"
            "Bb4 - G5 - - - | F5 - D5 - Bb4 - | C5 - Eb5 - D5 C5 | Bb4 - - - - -",
        ],
        form="AB",
    ),
    # Smith (camp NPC): a sturdy forge tune in D mixolydian with anvil strikes.
    "npc_smith": dict(
        bpm=100, beats=4, duty=0.5, harm_duty=0.25,
        bass="march", harm="power", drums="forge",
        chords=["D | C | G | D | D | C | G A | D",
                "G | D | C | D | G | D | C A | D"],
        lead=[
            "D5 - F#5 - A5 - F#5 - | G5 - E5 - C5 - E5 - | D5 - B4 - G4 - B4 - | A4 - - - D5 - - - |"
            "F#5 - A5 - D6 - A5 - | G5 - E5 - G5 - C6 - | B5 - G5 - A5 - C#6 - | D6 - - - A5 - . .",
            "B5 - - A5 G5 - D5 - | F#5 - - E5 D5 - A4 - | E5 - - D5 C5 - G4 - | A4 - D5 - F#5 - A5 - |"
            "G5 - B5 - D6 - B5 - | A5 - F#5 - D5 - F#5 - | E5 - G5 - E5 - C#5 - | D5 - - - - - . .",
        ],
        form="AB",
    ),
    # Trainer (camp NPC): a bugle-call drill march in Bb.
    "npc_trainer": dict(
        bpm=116, beats=4, duty=0.25, harm_duty=0.5,
        bass="march", harm="stab", drums="march",
        chords=["Bb | F | Bb | F | Eb | Bb | F7 | Bb",
                "Gm | Eb | Bb | F | Gm | Eb | F | Bb"],
        lead=[
            "F4 - - Bb4 D5 - Bb4 - | C5 - - A4 F4 - A4 - | D5 - - F5 Bb5 - F5 - | C5 - - - F4 - . . |"
            "G5 - - Eb5 Bb4 - Eb5 - | F5 - D5 - Bb4 - D5 - | C5 - Eb5 - A4 - C5 - | Bb4 - - - . . . .",
            "D5 - G5 - Bb5 - G5 - | Eb5 - G5 - Bb5 - G5 - | F5 - D5 - Bb4 - D5 - | C5 - F5 - A5 - F5 - |"
            "G5 - - D5 Bb4 - D5 - | Eb5 - - Bb4 G4 - Bb4 - | A4 - C5 - F5 - A5 - | Bb5 - - - F5 - . .",
        ],
        form="AB",
    ),
    # Cook (camp NPC): a cheerful kitchen polka in F.
    "npc_cook": dict(
        bpm=132, beats=4, duty=0.25, harm_duty=0.125,
        bass="bounce", harm="stab", drums="bounce",
        chords=["F | C | C7 | F | F | Bb | C | F",
                "Bb | F | C | F | Bb | F | C7 | F"],
        lead=[
            "A4 C5 F5 . A5 . F5 . | G5 . E5 . C5 . E5 . | Bb4 C5 E5 . G5 . E5 . | F5 . A5 . F5 - - . |"
            "C6 . A5 . F5 . A5 . | Bb5 . F5 . D5 . F5 . | E5 F5 G5 . C6 . G5 . | F5 - - . F4 . . .",
            "D5 . F5 . Bb5 . F5 . | C5 . F5 . A5 . F5 . | E5 . G5 . C6 . G5 . | A5 G5 F5 . C5 . . . |"
            "D6 . Bb5 . F5 . D5 . | C6 . A5 . F5 . C5 . | Bb4 . C5 . E5 . G5 . | F5 - - . . . . .",
        ],
        form="AB",
    ),
}


# ---------------------------------------------------------------- theory

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_QUALITY = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10),
    "maj7": (0, 4, 7, 11), "dim": (0, 3, 6), "5": (0, 7), "sus4": (0, 5, 7),
}


def _pitch_class(name: str) -> tuple[int, str]:
    pc = _PC[name[0]]
    rest = name[1:]
    if rest[:1] == "#":
        pc, rest = pc + 1, rest[1:]
    elif rest[:1] == "b":
        pc, rest = pc - 1, rest[1:]
    return pc % 12, rest


def note_midi(token: str) -> int:
    accidental = {"#": 1, "b": -1}.get(token[1:2], 0)
    octave = token[2:] if accidental else token[1:]
    return 12 * (int(octave) + 1) + _PC[token[0]] + accidental


def chord(name: str) -> tuple[int, tuple[int, ...]]:
    pc, quality = _pitch_class(name)
    if quality not in _QUALITY:
        raise ValueError(f"unknown chord quality in {name!r}")
    return pc, _QUALITY[quality]


def midi_freq(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# ---------------------------------------------------------------- parsing

def parse_line(text: str, steps_per_bar: int, bars: int, what: str) -> list[str]:
    bar_texts = [b.split() for b in text.split("|")]
    bar_texts = [b for b in bar_texts if b]
    if len(bar_texts) != bars:
        raise ValueError(f"{what}: {len(bar_texts)} bars, expected {bars}")
    for i, b in enumerate(bar_texts):
        if len(b) != steps_per_bar:
            raise ValueError(f"{what} bar {i + 1}: {len(b)} steps, expected {steps_per_bar}")
    return [t for b in bar_texts for t in b]


def melody_notes(tokens: list[str], offset: int) -> list[tuple[int, int, int]]:
    """(start_step, length_steps, midi) from note/hold/rest tokens."""
    notes: list[list[int]] = []
    for i, t in enumerate(tokens):
        if t == "-":
            if notes and notes[-1][0] + notes[-1][1] == offset + i:
                notes[-1][1] += 1
        elif t != ".":
            notes.append([offset + i, 1, note_midi(t)])
    return [tuple(n) for n in notes]  # type: ignore[misc]


def chord_steps(chart: str, steps_per_bar: int) -> list[tuple[int, tuple[int, ...]]]:
    """One (root_pc, intervals) per step."""
    out = []
    for bar in [b.split() for b in chart.split("|") if b.split()]:
        n = len(bar)
        for s in range(steps_per_bar):
            out.append(chord(bar[min(n - 1, s * n // steps_per_bar)]))
    return out


# ---------------------------------------------------------------- accompaniment

def _bass_root(pc: int, low: int = 40) -> int:
    m = 36 + pc
    return m + 12 if m < low else m


def bass_notes(style: str, chords: list, spb: int) -> list[tuple[int, int, int, float]]:
    """(start, length, midi, gate) for the triangle."""
    out = []
    for bar in range(len(chords) // spb):
        s0 = bar * spb
        pc, iv = chords[s0]
        r = _bass_root(pc)
        fifth = r + 7
        if style == "waltz":
            out.append((s0, 2, r, 0.9))
            continue
        half = chords[s0 + spb // 2]
        r2 = _bass_root(half[0])
        if style == "march":
            out += [(s0, 2, r, 0.7), (s0 + 2, 2, fifth, 0.7), (s0 + 4, 2, r2, 0.7), (s0 + 6, 2, r2 + 7, 0.7)]
        elif style == "octave":
            for k in range(8):
                root = r if k < 4 else r2
                out.append((s0 + k, 1, root + (12 if k % 2 else 0), 0.8))
        elif style in ("gallop", "pound"):
            low = -12 if style == "pound" else 0
            for k in range(8):
                root = (r if k < 4 else r2) + low
                note = root + 7 if (style == "gallop" and k == 7) else root
                out.append((s0 + k, 1, note, 0.75))
        elif style == "slow":
            out += [(s0, 4, r, 0.95), (s0 + 4, 4, r2 + (7 if r2 == r else 0), 0.95)]
        elif style == "half":
            out += [(s0, 2, r, 0.85), (s0 + 4, 2, r2 + 7 if r2 == r else r2, 0.85)]
        elif style == "bounce":
            out += [(s0, 1, r, 0.5), (s0 + 2, 1, r + 12, 0.5), (s0 + 4, 1, r2, 0.5), (s0 + 6, 1, r2 + 7, 0.5)]
        else:
            raise ValueError(f"unknown bass style {style}")
    return out


def harm_notes(style: str, chords: list, spb: int) -> list[tuple[int, int, int, float, float]]:
    """(start, length, midi, gate, volume) for the second pulse."""
    out = []
    n = len(chords)
    for s in range(n):
        pc, iv = chords[s]
        tones = [60 + pc + i for i in iv]
        if len(tones) == 2:  # power chord: root, fifth, octave
            tones.append(tones[0] + 12)
        beat_step = s % spb
        if style == "arp":
            out.append((s, 1, tones[s % len(tones)], 0.8, 1.0))
        elif style == "arp_high":
            cyc = tones + [t + 12 for t in tones]
            out.append((s, 1, cyc[s % len(cyc)] + 12, 0.6, 0.8))
        elif style == "arp_slow":
            if s % 2 == 0:
                out.append((s, 2, tones[(s // 2) % len(tones)], 0.9, 1.0))
        elif style == "stab":
            if beat_step % 2 == 1:
                for t in tones[1:3]:
                    out.append((s, 1, t, 0.45, 0.8))
        elif style == "power":
            if beat_step % 2 == 0:
                root = 48 + pc
                out += [(s, 1, root, 0.6, 0.9), (s, 1, root + 7, 0.6, 0.9)]
        elif style == "waltz":
            if beat_step in (2, 4):
                for t in tones[:3]:
                    out.append((s, 2, t, 0.7, 0.6))
        else:
            raise ValueError(f"unknown harmony style {style}")
    return out


DRUMS = {
    "rock": ["kh", "h", "sh", "h", "kh", "kh", "sh", "h"],
    "march": ["k", "h", "s", "h", "k", "s", "s", "h"],
    "light": ["k", ".", "h", ".", "s", ".", "h", "."],
    "sparse": ["k", ".", ".", ".", "r", ".", ".", "h"],
    "ice": ["k", ".", "h", ".", ".", ".", "h", "."],
    "war": ["kt", "h", "s", "k", "kt", "t", "s", "t"],
    "fast": ["kH", "H", "sH", "kH", "kH", "H", "sH", "H"],
    "bounce": ["k", "h", "s", "k", "k", "h", "s", "h"],
    "fire": ["k", ".", "h", ".", "h", "."],
    "forge": ["km", ".", "h", ".", "s", "m", "h", "."],
}
FILLS = {
    "rock": ["kh", "h", "sh", "h", "s", "s", "t", "t"],
    "march": ["k", "s", "s", "s", "sH", "sH", "s", "s"],
    "war": ["kt", "t", "t", "t", "s", "s", "t", "t"],
    "fast": ["kH", "H", "sH", "kH", "s", "s", "s", "s"],
    "bounce": ["k", "h", "s", "k", "t", "t", "s", "s"],
    "forge": ["km", "m", "s", "m", "km", ".", "m", "m"],
}
DRUM_VOL = {"light": 0.6, "sparse": 0.6, "ice": 0.45, "fire": 0.4}


# ---------------------------------------------------------------- synthesis

def _blep(t: float, dt: float) -> float:
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def render_pulse(buf, start: int, length: int, freq: float, duty: float, vol: float,
                 vibrato: bool, decay: float) -> None:
    attack = int(0.003 * RATE)
    release = int(0.025 * RATE)
    vib_start = int(0.18 * RATE)
    total = length + release
    ph = 0.0
    two_pi_vib = 2.0 * math.pi * 5.5 / RATE
    end = min(len(buf), start + total)
    for i in range(end - start):
        f = freq
        if vibrato and i > vib_start:
            f = freq * (1.0 + 0.004 * math.sin(two_pi_vib * (i - vib_start)))
        dt = f / RATE
        v = 1.0 if ph < duty else -1.0
        v += _blep(ph, dt)
        v -= _blep((ph - duty) % 1.0, dt)
        ph += dt
        if ph >= 1.0:
            ph -= 1.0
        if i < attack:
            env = i / attack
        else:
            env = 0.65 + 0.35 * math.exp(-decay * (i - attack) / RATE)
        if i >= length:
            env *= 1.0 - (i - length) / release
        buf[start + i] += v * vol * env


def render_triangle(buf, start: int, length: int, freq: float, vol: float) -> None:
    release = int(0.012 * RATE)
    total = length + release
    ph = 0.0
    dt = freq / RATE
    end = min(len(buf), start + total)
    for i in range(end - start):
        tri = 4.0 * abs(ph - 0.5) - 1.0
        v = round(tri * 7.5) / 7.5  # NES-style 16-step triangle
        ph += dt
        if ph >= 1.0:
            ph -= 1.0
        env = 1.0 if i < length else 1.0 - (i - length) / release
        if i < 40:
            env *= i / 40.0
        buf[start + i] += v * vol * env


def _sweep(buf, start: int, dur: float, f0: float, f1: float, vol: float, decay: float) -> None:
    n = int(dur * RATE)
    ph = 0.0
    for i in range(min(n, len(buf) - start)):
        k = i / n
        f = f0 * (f1 / f0) ** k
        ph += f / RATE
        tri = 4.0 * abs((ph % 1.0) - 0.5) - 1.0
        buf[start + i] += tri * vol * math.exp(-decay * k) * min(1.0, i / 30.0)


def _noise(buf, start: int, dur: float, vol: float, decay: float, hold: int, rng: random.Random,
           highpass: bool) -> None:
    n = int(dur * RATE)
    v = 0.0
    prev = 0.0
    for i in range(min(n, len(buf) - start)):
        if i % hold == 0:
            v = rng.random() * 2.0 - 1.0
        s = v - prev if highpass else v
        prev = v
        buf[start + i] += s * vol * math.exp(-decay * i / n) * min(1.0, i / 20.0)


def render_drum(buf, start: int, hit: str, vol: float, rng: random.Random) -> None:
    if hit == "k":
        _sweep(buf, start, 0.11, 170.0, 45.0, 0.95 * vol, 4.0)
    elif hit == "s":
        _noise(buf, start, 0.13, 0.40 * vol, 4.5, 1, rng, False)
        _sweep(buf, start, 0.06, 220.0, 170.0, 0.35 * vol, 5.0)
    elif hit == "h":
        _noise(buf, start, 0.035, 0.22 * vol, 5.0, 1, rng, True)
    elif hit == "t":
        _sweep(buf, start, 0.16, 210.0, 95.0, 0.75 * vol, 3.0)
    elif hit == "r":
        _noise(buf, start, 0.025, 0.25 * vol, 5.0, 2, rng, True)
        _sweep(buf, start, 0.03, 820.0, 760.0, 0.18 * vol, 5.0)
    elif hit == "m":  # anvil: two bright, inharmonic tones ringing out
        _sweep(buf, start, 0.22, 1180.0, 1170.0, 0.16 * vol, 4.0)
        _sweep(buf, start, 0.18, 1735.0, 1720.0, 0.10 * vol, 5.0)
        _noise(buf, start, 0.02, 0.15 * vol, 5.0, 1, rng, True)
    elif hit == "c":  # fire crackle
        _noise(buf, start, 0.012, 0.18 * vol, 6.0, 3, rng, True)


# ---------------------------------------------------------------- render

def song_frames(song: dict) -> tuple[int, int, float]:
    """(steps per bar, total bars, seconds per step)."""
    spb = song["beats"] * 2
    bars = 8 * len(song["form"])
    return spb, bars, 30.0 / song["bpm"]


def render_song(name: str, song: dict) -> tuple[array.array, array.array]:
    spb, bars, step_sec = song_frames(song)
    phrase_bars = 8
    total_steps = bars * spb
    n = int(round(total_steps * step_sec * RATE))
    size = n + int(TAIL_SEC * RATE)
    rng = random.Random(sum(map(ord, name)) * 31 + 7)

    def at(step: float) -> int:
        return int(round(step * step_sec * RATE))

    chords_all: list = []
    lead: list[tuple[int, int, int]] = []
    for p, label in enumerate(song["form"]):
        idx = ord(label) - ord("A")
        offset = p * phrase_bars * spb
        chords_all += chord_steps(song["chords"][idx], spb)
        tokens = parse_line(song["lead"][idx], spb, phrase_bars, f"{name} lead {label}")
        lead += melody_notes(tokens, offset)
    if len(chords_all) != total_steps:
        raise ValueError(f"{name}: chord chart covers {len(chords_all)} steps, expected {total_steps}")

    lead_buf = array.array("f", bytes(4 * size))
    harm_buf = array.array("f", bytes(4 * size))
    bass_buf = array.array("f", bytes(4 * size))
    drum_buf = array.array("f", bytes(4 * size))

    for start, length, m in lead:
        dur = at(start + length) - at(start)
        render_pulse(lead_buf, at(start), int(dur * 0.92), midi_freq(m), song["duty"], LEAD_VOL,
                     True, 3.0)
    for start, length, m, gate, vol in harm_notes(song["harm"], chords_all, spb):
        dur = at(start + length) - at(start)
        render_pulse(harm_buf, at(start), int(dur * gate), midi_freq(m), song["harm_duty"],
                     HARM_VOL * vol, False, 6.0)
    for start, length, m, gate in bass_notes(song["bass"], chords_all, spb):
        dur = at(start + length) - at(start)
        render_triangle(bass_buf, at(start), int(dur * gate), midi_freq(m), BASS_VOL)

    style = song["drums"]
    pattern = DRUMS[style]
    fill = FILLS.get(style)
    dvol = DRUM_VOL.get(style, 1.0)
    for bar in range(bars):
        hits = fill if (fill and bar % 8 == 7) else pattern
        for k, cell in enumerate(hits):
            s = bar * spb + k
            for hit in cell:
                if hit == "H":  # two sixteenth hats
                    render_drum(drum_buf, at(s), "h", dvol, rng)
                    render_drum(drum_buf, at(s + 0.5), "h", dvol, rng)
                elif hit != ".":
                    render_drum(drum_buf, at(s), hit, dvol, rng)
        if style == "fire":
            for _ in range(5):
                render_drum(drum_buf, at(bar * spb + rng.random() * spb), "c", dvol, rng)

    echo_buf = None
    if song.get("echo"):
        d = int(ECHO_DELAY_BEATS * 2 * step_sec * RATE)
        echo_buf = array.array("f", bytes(4 * size))
        for i in range(d, size):
            echo_buf[i] = ECHO_LEVEL * lead_buf[i - d] + ECHO_FEEDBACK * echo_buf[i - d]

    # Pan: lead a little left, harmony right, echo opposite the lead.
    left = array.array("f", bytes(4 * size))
    right = array.array("f", bytes(4 * size))
    for i in range(size):
        c = bass_buf[i] + drum_buf[i]
        lv = lead_buf[i]
        hv = harm_buf[i]
        e = echo_buf[i] if echo_buf is not None else 0.0
        left[i] = c + 0.62 * lv + 0.42 * hv + 0.38 * e
        right[i] = c + 0.42 * lv + 0.62 * hv + 0.62 * e
    # Seamless loop: what rings past the end plays over the start.
    for i in range(n, size):
        left[i - n] += left[i]
        right[i - n] += right[i]
    left = left[:n]
    right = right[:n]

    peak = max(max(map(abs, left)), max(map(abs, right)), 1e-9)
    rms = math.sqrt(sum(v * v for v in left) / n)
    gain = min(TARGET_RMS / max(rms, 1e-9), PEAK_LIMIT / peak)
    for i in range(n):
        left[i] *= gain
        right[i] *= gain
    return left, right


def _pcm(left: array.array, right: array.array) -> bytes:
    out = array.array("h", bytes(4 * len(left)))
    for i in range(len(left)):
        out[2 * i] = int(max(-1.0, min(1.0, left[i])) * 32767)
        out[2 * i + 1] = int(max(-1.0, min(1.0, right[i])) * 32767)
    return out.tobytes()


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg") or ("/opt/homebrew/bin/ffmpeg" if os.path.exists("/opt/homebrew/bin/ffmpeg") else "")
    if not exe:
        sys.exit("❌ ffmpeg not found: install it (brew install ffmpeg) to encode the music")
    return exe


def decode(path: str) -> array.array:
    raw = subprocess.run([_ffmpeg(), "-v", "error", "-i", path, "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-"],
                         check=True, capture_output=True).stdout
    return array.array("h", raw)


def build(name: str) -> None:
    song = SONGS[name]
    left, right = render_song(name, song)
    pcm = _pcm(left, right)
    out = os.path.join(OUT_DIR, f"{name}.ogg")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, f"{name}.wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm)
        # Encoded at 44.1 kHz: at 22.05 kHz this encoder low-passes the pulse
        # waves dull (about 20 dB SNR at any bitrate); 44.1 kHz q3 gives 25 dB
        # at a smaller size than 22.05 kHz q6.
        subprocess.run([_ffmpeg(), "-v", "error", "-y", "-i", wav_path, "-ar", str(ENCODE_RATE), "-c:a", "vorbis",
                        "-strict", "-2", "-q:a", str(ENCODE_QUALITY), out], check=True)
    src = array.array("h", pcm)
    got = decode(out)
    m = min(len(src), len(got))
    sig = sum(float(v) * v for v in src[:m]) or 1.0
    err = sum((float(a) - b) ** 2 for a, b in zip(src[:m], got[:m])) or 1e-9
    snr = 10.0 * math.log10(sig / err)
    print(f"✅ {name}: {len(left) / RATE:.1f} s, {os.path.getsize(out) // 1024} KB, SNR {snr:.1f} dB")
    if snr < MIN_SNR_DB:
        print(f"⚠️ {name}: encoded quality below {MIN_SNR_DB} dB")


def check() -> int:
    bad = 0
    for name, song in SONGS.items():
        path = os.path.join(OUT_DIR, f"{name}.ogg")
        if not os.path.exists(path):
            print(f"❌ {name}: {path} missing")
            bad += 1
            continue
        spb, bars, step_sec = song_frames(song)
        expect = bars * spb * step_sec
        pcm = decode(path)
        frames = len(pcm) // 2
        secs = frames / RATE
        peak = max(abs(v) for v in pcm) / 32768.0
        steps = sorted(abs(pcm[i + 2] - pcm[i]) for i in range(0, len(pcm) - 2, 2))
        p99 = steps[int(len(steps) * 0.99)]
        seam = max(abs(pcm[0] - pcm[-2]), abs(pcm[1] - pcm[-1]))
        problems = []
        if abs(secs - expect) > 0.05:
            problems.append(f"length {secs:.3f} s, expected {expect:.3f} s")
        if peak > 10 ** (-1.0 / 20.0):
            problems.append(f"peak {20 * math.log10(peak):.2f} dBFS above -1 dBFS")
        if seam > p99:
            problems.append(f"loop seam step {seam} above the song's 99th percentile {p99}")
        if problems:
            bad += 1
            print(f"❌ {name}: " + "; ".join(problems))
        else:
            print(f"✅ {name}: {secs:.2f} s, peak {20 * math.log10(max(peak, 1e-9)):.1f} dBFS, seam {seam} <= {p99}")
    return bad


def main(argv: list[str]) -> int:
    if "--check" in argv:
        return 1 if check() else 0
    names = [a for a in argv if not a.startswith("-")] or list(SONGS)
    for n in names:
        if n not in SONGS:
            print(f"❌ unknown track {n}; known: {', '.join(SONGS)}")
            return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in names:
        build(n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
