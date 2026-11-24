"""humanoid.py — shared walk/chase pose maths for the 8x3 enemy sheets.

Sheet contract (unchanged; read from enemies/<kind>/<kind>.tscn):
  512x192, 8x3 cells of 64 px, frames
  0-3 down walk, 4-7 up walk, 8-11 side walk,
  12-15 down chase, 16-19 up chase, 20-23 side chase.
  idle/stun/destroy reuse 0 / 4 / 8.
Feet baseline = bbox bottom (exclusive): down 56, up 48, side 50.
The lowest *body* pixel therefore sits on row base-2 (the outline takes base-1).

Every creature builds its own parts; this module only answers "where are the
hips, feet, hands and how much does the body bob on this frame", so walk
cycles move the same way across the cast and always keep one foot planted.
"""
from __future__ import annotations

from pixrig import sheet

BASE = {"down": 56, "up": 48, "side": 50}


def direction_of(i: int) -> str:
    col, row = i % 8, i // 8
    if col < 4:
        return "down" if row == 0 else "up"
    return "side"


def frame_table():
    """(index, direction, phase, chase) for all 24 cells."""
    out = []
    for i in range(24):
        col, row = i % 8, i // 8
        if row == 0:
            d, chase = ("down", False) if col < 4 else ("up", False)
        elif row == 1:
            d, chase = ("side", False) if col < 4 else ("down", True)
        else:
            d, chase = ("up", True) if col < 4 else ("side", True)
        out.append((i, d, col % 4, chase))
    return out


class Pose:
    def __init__(self, direction: str, phase: int, chase: bool):
        self.d = direction
        self.p = phase
        self.chase = chase
        self.g = BASE[direction] - 2          # lowest body row
        self.bob = 1 if phase in (1, 3) else 0
        self.s = (1, 0, -1, 0)[phase]           # +1: left (viewer) leg forward
        self.amp = 2 if chase else 1
        self.lean = 1 if chase else 0

    def y(self, h: float) -> float:
        """Row for a height h above the feet, including the walk bob."""
        return self.g - h - (self.bob if h > 4 else 0)

    # ---- legs -------------------------------------------------------------
    def front_feet(self):
        """Down/up views: (left_raise, right_raise) in px; one foot is always 0."""
        r = 3 if self.chase else 2
        return {0: (0, r), 1: (0, r - 1), 2: (r, 0), 3: (r - 1, 0)}[self.p]

    def side_feet(self):
        """Side view facing right: (near_dx, near_raise, far_dx, far_raise)."""
        st = 6 if self.chase else 4
        return {0: (st, 0, -st, 0), 1: (0, 0, 2, 3), 2: (-st, 0, st, 0), 3: (2, 3, 0, 0)}[self.p]

    def arm_swing(self):
        """Hand y offset for (left, right) arms in front/back views."""
        a = 2 * self.amp if not self.chase else self.amp
        return (-self.s * a, self.s * a)


def build_sheet(draw):
    """draw(pose) -> 64x64 RGBA image; returns the 512x192 sheet."""
    cells = [None] * 24
    for i, d, ph, chase in frame_table():
        cells[i] = draw(Pose(d, ph, chase))
    out = sheet(cells, 8, 64, 64)
    assert out.size == (512, 192)
    return out
