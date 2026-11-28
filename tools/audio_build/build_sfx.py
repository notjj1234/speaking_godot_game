#!/usr/bin/env python3
"""Synthesises the game's retro UI sounds into audio/sfx/<cue>.wav.

Stdlib only, deterministic (fixed noise seed), so the files can be rebuilt and
tuned here instead of hand-editing audio. 22050 Hz, 16-bit mono.

    python3 tools/audio_build/build_sfx.py
"""
from __future__ import annotations

import math
import os
import random
import struct
import wave

RATE = 22050
PEAK = 0.7  # about -3 dBFS
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "audio", "sfx")
_rng = random.Random(7)


def _note(name: str) -> float:
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def _envelope(i: int, n: int, attack: float, decay: float) -> float:
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    # Exponential decay toward the end, plus a 3 ms fade so nothing clicks.
    d = math.exp(-decay * t / max(n / RATE, 1e-6))
    tail = min(1.0, (n - i) / (0.003 * RATE))
    return a * d * tail


def tone(freq: float, dur: float, shape: str = "square", vol: float = 0.5,
         decay: float = 3.0, slide: float = 0.0) -> list[float]:
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq + slide * (i / n)
        phase = (phase + f / RATE) % 1.0
        if shape == "square":
            s = 1.0 if phase < 0.5 else -1.0
        elif shape == "triangle":
            s = 4.0 * abs(phase - 0.5) - 1.0
        else:
            s = math.sin(2 * math.pi * phase)
        out.append(s * vol * _envelope(i, n, 0.004, decay))
    return out


def noise(dur: float, vol: float = 0.4, decay: float = 5.0) -> list[float]:
    n = int(dur * RATE)
    return [(_rng.random() * 2 - 1) * vol * _envelope(i, n, 0.002, decay) for i in range(n)]


def rest(dur: float) -> list[float]:
    return [0.0] * int(dur * RATE)


def seq(*parts: list[float]) -> list[float]:
    out: list[float] = []
    for p in parts:
        out += p
    return out


def mix(*parts: list[float]) -> list[float]:
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


CUES = {
    "click": lambda: tone(1200, 0.025, "square", 0.35, decay=6),
    "accept": lambda: seq(tone(660, 0.07, "square", 0.4), tone(990, 0.12, "square", 0.4)),
    "correct": lambda: seq(tone(_note("C6"), 0.07, "square", 0.35), tone(_note("E6"), 0.07, "square", 0.35),
                           tone(_note("G6"), 0.18, "square", 0.35)),
    "wrong": lambda: seq(tone(330, 0.12, "square", 0.4, decay=1.5), tone(220, 0.2, "square", 0.4, decay=2)),
    "error": lambda: seq(mix(tone(110, 0.12, "square", 0.45, decay=1), noise(0.12, 0.15)), rest(0.05),
                         mix(tone(110, 0.16, "square", 0.45, decay=1.5), noise(0.16, 0.15))),
    "listen": lambda: tone(1600, 0.09, "triangle", 0.3, decay=4),
    "purchase": lambda: seq(tone(_note("B5"), 0.06, "square", 0.35), tone(_note("E6"), 0.3, "triangle", 0.45, decay=3)),
    "phase": lambda: seq(noise(0.08, 0.6, decay=6),
                         mix(tone(_note("C5"), 0.32, "square", 0.25, slide=60),
                             tone(_note("G5"), 0.32, "square", 0.2, slide=90))),
    "victory": lambda: seq(tone(_note("G5"), 0.1, "square", 0.35), tone(_note("C6"), 0.1, "square", 0.35),
                           tone(_note("E6"), 0.1, "square", 0.35),
                           mix(tone(_note("G6"), 0.45, "square", 0.3, decay=2),
                               tone(_note("C6"), 0.45, "triangle", 0.3, decay=2))),
}


## Quiet cues for frequent events, so a click never competes with a result.
LEVEL = {"click": 0.45, "listen": 0.4}


def write(name: str, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = PEAK * LEVEL.get(name, 1.0) / peak
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))
    print("✅ %s (%.2fs)" % (os.path.relpath(path, ROOT), len(samples) / RATE))


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    for cue, build in CUES.items():
        write(cue, build())
