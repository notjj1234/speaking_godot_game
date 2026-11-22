"""make_audio.py — synthesize distinct hit/death WAVs per enemy (44.1kHz 16-bit mono).

The project shares two slime WAVs across every enemy; the rework gives each
enemy its own hit/death pair so damage feedback is identifiable by ear.
"""
import math
import os
import random
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import rp

SR = 44100


def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        w.writeframes(frames)
    print("wrote", path)


def env(i, n, attack=0.01, decay=None):
    t = i / SR
    a = max(1, int(attack * SR))
    if i < a:
        return i / a
    if decay is not None:
        d = max(1, int(decay * SR))
        return max(0.0, 1.0 - (i - a) / d)
    return max(0.0, 1.0 - (i - a) / (n - a))


def sine(freq, t):
    return math.sin(2 * math.pi * freq * t)


def noise():
    return random.uniform(-1.0, 1.0)


def bandit_hit():
    n = int(0.12 * SR)
    out = []
    for i in range(n):
        t = i / SR
        f = 1400 - 5000 * t
        out.append((sine(f, t) * 0.5 + noise() * 0.25) * env(i, n, 0.004, 0.1))
    return out


def bandit_die():
    n = int(0.35 * SR)
    out = []
    for i in range(n):
        t = i / SR
        f = 900 - 2100 * t
        out.append((sine(f, t) * 0.55 + noise() * 0.2) * env(i, n, 0.005, 0.3))
    return out


def skeleton_hit():
    # dry bone rattle: three noise ticks
    n = int(0.25 * SR)
    out = []
    starts = [0.0, 0.07, 0.15]
    for i in range(n):
        t = i / SR
        v = 0.0
        for s in starts:
            if t >= s:
                k = i - int(s * SR)
                v += noise() * env(k, int(0.06 * SR), 0.002, 0.05)
        v += sine(220 - 300 * t, t) * 0.2 * env(i, n, 0.004, 0.2)
        out.append(v * 0.6)
    return out


def skeleton_die():
    n = int(0.45 * SR)
    out = []
    for i in range(n):
        t = i / SR
        v = noise() * env(i, n, 0.003, 0.28) * 0.5
        v += sine(180 - 260 * t, t) * 0.35 * env(i, n, 0.005, 0.35)
        out.append(v)
    return out


def orc_hit():
    n = int(0.28 * SR)
    out = []
    for i in range(n):
        t = i / SR
        v = sine(95 - 60 * t, t) * 0.8
        v += sine(62, t) * 0.4
        v += noise() * 0.3 * env(i, n, 0.002, 0.08)
        out.append(v * env(i, n, 0.004, 0.24))
    return out


def orc_die():
    n = int(0.5 * SR)
    out = []
    for i in range(n):
        t = i / SR
        v = sine(80 - 90 * t, t) * 0.9
        v += noise() * 0.35 * env(i, n, 0.003, 0.15)
        out.append(v * env(i, n, 0.005, 0.42))
    return out


SOUNDS = {
    "bandit": (bandit_hit, bandit_die),
    "skeleton": (skeleton_hit, skeleton_die),
    "orc": (orc_hit, orc_die),
}


def main():
    random.seed(7)
    for enemy, (hit_fn, die_fn) in SOUNDS.items():
        write_wav(rp(f"enemies/{enemy}/{enemy}_hit.wav"), hit_fn())
        write_wav(rp(f"enemies/{enemy}/{enemy}_die.wav"), die_fn())


if __name__ == "__main__":
    main()
