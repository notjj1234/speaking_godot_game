"""build_bandit.py — Bandit sheet: hooded human opportunist, stiletto + buckler.

Structural edits on the Goblin base: ears removed everywhere, Goblin club replaced
by a slim stiletto (reverse grip) + round buckler on the off arm, hood + face wrap
replace the bare head, scarf tail flutters per frame, shoulders narrowed, leather
jack replaces bare torso/loincloth, boots replace bare feet. Full ramp rebuild.

Edit discipline: erase the old anatomy to transparent FIRST, then stamp new
shapes — never layer new gear over remapped Goblin pixels.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import (Cell, load_cells, compose_sheet, direction_of, phase_of, rp,
                    G_OUTLINE, G_SKIN_L, G_SKIN_M, G_SKIN_H, G_BLACK, G_CLOTH,
                    G_LEATHER, G_GRAY, G_WHITE, G_STEEL, G_YELLOW)
from qa import report, montage, goblin_baselines

OUT = rp("enemies/bandit/bandit.png")

# Palette — oxblood / umber leather / cold steel / bone wrap. No green.
OUTLINE = (42, 28, 20, 255)
HOOD_D = (92, 35, 38, 255)
HOOD_M = (126, 50, 54, 255)
HOOD_H = (156, 74, 74, 255)
WRAP_L = (216, 201, 168, 255)
WRAP_M = (188, 168, 132, 255)
LEATHER_D = (84, 55, 30, 255)
LEATHER_M = (122, 82, 48, 255)
LEATHER_H = (156, 112, 64, 255)
STEEL_D = (95, 112, 124, 255)
STEEL_M = (159, 176, 189, 255)
STEEL_L = (207, 216, 222, 255)
BOOT = (46, 32, 22, 255)
BLACK = (0, 0, 0, 255)

REMAP = {
    G_OUTLINE: OUTLINE, G_SKIN_H: WRAP_L, G_SKIN_L: LEATHER_H, G_SKIN_M: LEATHER_M,
    G_BLACK: BLACK, G_CLOTH: HOOD_D, G_LEATHER: LEATHER_D, G_GRAY: STEEL_D,
    G_WHITE: STEEL_L, G_STEEL: STEEL_M, G_YELLOW: BLACK,
}
STEELS = {STEEL_D, STEEL_M, STEEL_L}


def erase_rect(cell, x0, y0, x1, y1):
    cell.erase(Cell.m_rect(x0, y0, x1, y1))


def erase_colors(cell, x0, y0, x1, y1, colors):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if cell.get(x, y) in colors:
                cell.set(x, y, (0, 0, 0, 0))


def flutter(phase):
    return [0, 1, 2, 1][phase]


def boots_down(cell):
    erase_rect(cell, 24, 50, 31, 57)
    erase_rect(cell, 32, 50, 39, 57)
    cell.stamp(Cell.m_rect(25, 50, 30, 55), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(33, 50, 38, 55), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(25, 50, 30, 50), LEATHER_H)
    cell.stamp(Cell.m_rect(33, 50, 38, 50), LEATHER_H)


def boots_up(cell):
    erase_rect(cell, 24, 42, 31, 49)
    erase_rect(cell, 32, 42, 39, 49)
    cell.stamp(Cell.m_rect(25, 42, 30, 47), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(33, 42, 38, 47), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(25, 42, 30, 42), LEATHER_H)
    cell.stamp(Cell.m_rect(33, 42, 38, 42), LEATHER_H)


def boots_side(cell):
    erase_rect(cell, 23, 43, 31, 51)
    erase_rect(cell, 31, 43, 38, 51)
    cell.stamp(Cell.m_rect(24, 44, 30, 49), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(32, 44, 37, 49), BOOT, OUTLINE)
    cell.stamp(Cell.m_rect(24, 44, 30, 44), LEATHER_H)
    cell.stamp(Cell.m_rect(32, 44, 37, 44), LEATHER_H)


def buckler(cell, cx, cy):
    cell.stamp_ramp([
        (Cell.m_disc(cx, cy, 5), STEEL_D, OUTLINE),
        (Cell.m_disc(cx, cy, 3), STEEL_M, None),
        (Cell.m_disc(cx, cy, 1), STEEL_L, None),
    ])


def build_down(cell, phase):
    f = flutter(phase)
    # erase ears, old head, old club, and top of torso (rebuilt narrower)
    erase_rect(cell, 17, 18, 23, 31)
    erase_rect(cell, 39, 18, 46, 31)
    erase_rect(cell, 17, 33, 28, 58)
    cell.erase(Cell.m_ellipse(31, 25, 10, 9))
    erase_rect(cell, 24, 33, 38, 38)
    # leather jack (narrow shoulders)
    cell.stamp(Cell.m_rect(26, 34, 36, 42), LEATHER_M, OUTLINE)
    cell.stamp(Cell.m_rect(27, 34, 35, 36), LEATHER_H)
    cell.stamp(Cell.m_rect(28, 37, 30, 42), LEATHER_D)   # strap
    cell.stamp(Cell.m_rect(26, 41, 36, 42), LEATHER_D)   # belt
    # hood
    cell.stamp(Cell.m_ellipse(31, 22, 10, 8), HOOD_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(29, 19, 5, 3), HOOD_H)
    cell.stamp(Cell.m_rect(25, 24, 37, 25), HOOD_D)      # overhang shadow
    # face wrap + eye slit
    cell.stamp(Cell.m_rect(25, 26, 37, 31), WRAP_L, OUTLINE)
    cell.stamp(Cell.m_rect(26, 27, 36, 28), WRAP_M)
    cell.stamp(Cell.m_rect(27, 29, 35, 29), BLACK)
    # scarf neck band + fluttering tail (trails to image-right, stays above baseline)
    cell.stamp(Cell.m_rect(26, 32, 36, 33), HOOD_D, OUTLINE)
    tail = Cell.m_poly([(37, 32), (44 + f, 36), (47 + f, 43), (43 + f, 47),
                        (40, 43), (38, 37)])
    cell.stamp(tail, HOOD_M, OUTLINE)
    cell.stamp(Cell.m_poly([(38, 34), (43 + f, 37), (45 + f, 42), (41, 41)]), HOOD_H)
    # buckler on off (image-right) arm
    buckler(cell, 40, 41)
    # stiletto, reverse grip in image-left hand (drawn last: bright, in front)
    cell.stamp(Cell.m_rect(22, 39, 25, 42), WRAP_M, OUTLINE)  # hand
    cell.stamp(Cell.m_rect(21, 42, 26, 43), STEEL_D)          # crossguard
    cell.stamp(Cell.m_rect(23, 43, 24, 45), LEATHER_D)        # grip
    cell.stamp(Cell.m_line(25, 45, 28, 54, 2), STEEL_M)       # blade, out-forward
    cell.stamp(Cell.m_line(26, 46, 28, 53, 1), STEEL_L)
    boots_down(cell)


def build_up(cell, phase):
    f = flutter(phase)
    # erase ears, old head, old club, torso top
    erase_rect(cell, 17, 16, 23, 30)
    erase_rect(cell, 39, 16, 46, 30)
    erase_rect(cell, 38, 13, 48, 50)
    cell.erase(Cell.m_ellipse(31, 23, 10, 8))
    erase_rect(cell, 24, 30, 38, 33)
    # torso (leather jack)
    cell.stamp(Cell.m_rect(26, 32, 36, 42), LEATHER_M, OUTLINE)
    cell.stamp(Cell.m_rect(27, 32, 35, 34), LEATHER_H)
    cell.stamp(Cell.m_rect(26, 41, 36, 42), LEATHER_D)
    # hood back
    cell.stamp(Cell.m_ellipse(31, 21, 10, 8), HOOD_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(29, 18, 5, 3), HOOD_H)
    # scarf under hood + tail trailing to image-left (stays above baseline)
    cell.stamp(Cell.m_rect(26, 29, 36, 31), HOOD_D, OUTLINE)
    tail = Cell.m_poly([(26, 30), (19 - f, 34), (16 - f, 41), (20 - f, 46),
                        (25, 42), (27, 35)])
    cell.stamp(tail, HOOD_M, OUTLINE)
    cell.stamp(Cell.m_poly([(25, 32), (20 - f, 35), (18 - f, 40), (23, 38)]), HOOD_H)
    # buckler slung on the back
    cell.stamp_ramp([
        (Cell.m_disc(31, 37, 6), LEATHER_D, OUTLINE),
        (Cell.m_disc(31, 37, 4), STEEL_D, None),
        (Cell.m_disc(31, 37, 2), STEEL_M, None),
        (Cell.m_disc(30, 36, 1), STEEL_L, None),
    ])
    # stiletto tucked at hip (blade down)
    cell.stamp(Cell.m_line(39, 40, 40, 49, 2), STEEL_D)
    cell.stamp(Cell.m_rect(37, 39, 42, 40), STEEL_D)
    boots_up(cell)


def build_side(cell, phase):
    f = flutter(phase)
    # erase Goblin weapon (keep hands/body), old head incl. nose
    erase_colors(cell, 34, 29, 53, 42, STEELS)
    erase_colors(cell, 20, 33, 34, 39, STEELS)
    cell.erase(Cell.m_ellipse(27, 24, 8, 8))
    # narrow torso: leather jack
    cell.stamp(Cell.m_rect(23, 31, 33, 42), LEATHER_M, OUTLINE)
    cell.stamp(Cell.m_rect(24, 31, 32, 33), LEATHER_H)
    cell.stamp(Cell.m_rect(23, 41, 33, 42), LEATHER_D)
    # hood (profile; opening at the face)
    cell.stamp(Cell.m_ellipse(25, 23, 8, 8), HOOD_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(23, 20, 4, 3), HOOD_H)
    erase_rect(cell, 29, 22, 34, 29)                      # face opening
    cell.stamp(Cell.m_rect(28, 22, 33, 23), HOOD_D)       # overhang shadow
    # face wrap band + eye slit
    cell.stamp(Cell.m_rect(28, 24, 33, 29), WRAP_L, OUTLINE)
    cell.stamp(Cell.m_rect(29, 25, 32, 26), WRAP_M)
    cell.stamp(Cell.m_rect(29, 27, 32, 27), BLACK)
    # scarf neck + tail trailing behind (image-left, stays above baseline)
    cell.stamp(Cell.m_rect(22, 29, 27, 32), HOOD_D, OUTLINE)
    tail = Cell.m_poly([(22, 30), (14 - f, 34), (12 - f, 41), (16 - f, 46),
                        (20, 41), (22, 34)])
    cell.stamp(tail, HOOD_M, OUTLINE)
    cell.stamp(Cell.m_poly([(21, 32), (15 - f, 35), (14 - f, 40), (18, 38)]), HOOD_H)
    # buckler on the front arm
    buckler(cell, 27, 38)
    # stiletto reverse grip, blade forward
    cell.stamp(Cell.m_rect(32, 35, 35, 38), WRAP_M, OUTLINE)  # hand
    cell.stamp(Cell.m_rect(31, 38, 36, 39), STEEL_D)          # crossguard
    cell.stamp(Cell.m_line(35, 37, 46, 40, 2), STEEL_M)
    cell.stamp(Cell.m_line(36, 37, 45, 39, 1), STEEL_L)
    boots_side(cell)


BUILDERS = {"down": build_down, "up": build_up, "side": build_side}


def main():
    cells = [Cell(c) for c in load_cells("enemies/goblin/goblin.png")]
    for i, cell in enumerate(cells):
        cell.remap(REMAP)
        BUILDERS[direction_of(i)](cell, phase_of(i))
    sheet = compose_sheet([c.img for c in cells])
    sheet.save(OUT)
    report(sheet, "bandit", goblin_baselines())
    montage(sheet, "bandit", "/tmp/qa_bandit.png")


if __name__ == "__main__":
    main()
