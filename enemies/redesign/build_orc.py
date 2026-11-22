"""build_orc.py — Orc sheet: siege-engine brute, cleaver + pauldron + topknot.

Structural edits on the Goblin base: oversized Goblin head replaced by a small
head with a topknot, torso rebuilt as a wide trapezoid with huge forearms, iron
pauldron on one shoulder, Goblin club replaced by a heavy cleaver (dragged in
walk, shouldered in the up view), loincloth replaced by a jagged war-skirt,
ochre war paint, thick legs. Full ramp rebuild: charcoal-olive / iron / ochre.
Edit discipline: erase old anatomy to transparent FIRST, then stamp new shapes.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import (Cell, load_cells, compose_sheet, direction_of, phase_of, rp,
                    G_OUTLINE, G_SKIN_L, G_SKIN_M, G_SKIN_H, G_BLACK, G_CLOTH,
                    G_LEATHER, G_GRAY, G_WHITE, G_STEEL, G_YELLOW)
from qa import report, montage, goblin_baselines

OUT = rp("enemies/orc/orc.png")

# Palette — charcoal-olive skin / iron / ochre war paint / rust skirt. Not goblin green.
OUTLINE = (30, 26, 18, 255)
SKIN_H = (134, 138, 96, 255)
SKIN_M = (106, 110, 74, 255)
SKIN_D = (78, 82, 56, 255)
IRON_M = (110, 114, 120, 255)
IRON_D = (67, 71, 77, 255)
IRON_L = (154, 160, 168, 255)
OCHRE = (201, 138, 46, 255)
SKIRT_M = (96, 54, 34, 255)
SKIRT_D = (74, 40, 28, 255)
HAIR = (26, 22, 16, 255)
EYE = (255, 236, 200, 255)

REMAP = {
    G_OUTLINE: OUTLINE, G_SKIN_H: SKIN_H, G_SKIN_L: SKIN_M, G_SKIN_M: SKIN_D,
    G_BLACK: OUTLINE, G_CLOTH: SKIRT_D, G_LEATHER: SKIRT_M, G_GRAY: IRON_D,
    G_WHITE: IRON_L, G_STEEL: IRON_M, G_YELLOW: EYE,
}
STEELS = {IRON_M, IRON_D, IRON_L}


def erase_rect(cell, x0, y0, x1, y1):
    cell.erase(Cell.m_rect(x0, y0, x1, y1))


def erase_colors(cell, x0, y0, x1, y1, colors):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if cell.get(x, y) in colors:
                cell.set(x, y, (0, 0, 0, 0))


def sway(phase):
    return [0, 1, 1, 0][phase]


def lag(phase):
    return [0, -1, 0, 1][phase]


def pauldron(cell, x0, y0, flip=False):
    """Iron pauldron block with rivets, draped over one shoulder."""
    pts = [(x0, y0), (x0 + 7, y0 - 1), (x0 + 8, y0 + 4), (x0 + 7, y0 + 8),
           (x0 + 1, y0 + 7), (x0 - 1, y0 + 3)]
    if flip:
        pts = [(x0 - (p[0] - x0), p[1]) for p in pts]
    cell.stamp(Cell.m_poly(pts), IRON_M, OUTLINE)
    inner = [(x0 + 1, y0 + 1), (x0 + 6, y0 + 1), (x0 + 6, y0 + 5), (x0 + 1, y0 + 5)]
    if flip:
        inner = [(x0 - (p[0] - x0), p[1]) for p in inner]
    cell.stamp(Cell.m_poly(inner), IRON_D)
    cell.stamp(Cell.m_disc(x0 + 2, y0 + 2, 0), IRON_L)
    cell.stamp(Cell.m_disc(x0 + 5, y0 + 2, 0), IRON_L)


def small_head_down(cell, cx, cy):
    """Small orc head: heavy jaw, angry pale eyes, ochre brow paint."""
    cell.stamp(Cell.m_ellipse(cx, cy, 7, 6), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(cx - 1, cy - 2, 4, 2), SKIN_H)
    cell.stamp(Cell.m_rect(cx - 5, cy + 1, cx + 5, cy + 3), SKIN_D)      # heavy jaw
    cell.stamp(Cell.m_rect(cx - 4, cy - 2, cx + 4, cy - 1), OCHRE)       # war paint brow
    cell.stamp(Cell.m_rect(cx - 4, cy, cx - 2, cy + 1), EYE)
    cell.stamp(Cell.m_rect(cx + 2, cy, cx + 4, cy + 1), EYE)
    cell.stamp(Cell.m_rect(cx - 3, cy, cx - 3, cy), OUTLINE)
    cell.stamp(Cell.m_rect(cx + 3, cy, cx + 3, cy), OUTLINE)


def topknot_down(cell, cx, ytop):
    cell.stamp(Cell.m_rect(cx - 1, ytop, cx + 1, ytop + 3), HAIR, OUTLINE)
    cell.stamp(Cell.m_disc(cx, ytop - 1, 1), HAIR)


def build_down(cell, phase):
    s = sway(phase)
    lg = lag(phase)
    # erase ears, old head, old club, old arms, old legs
    erase_rect(cell, 17, 18, 23, 31)
    erase_rect(cell, 39, 18, 46, 31)
    erase_rect(cell, 17, 33, 28, 58)
    erase_rect(cell, 19, 32, 27, 48)
    erase_rect(cell, 35, 32, 45, 48)
    erase_rect(cell, 24, 45, 39, 57)
    cell.erase(Cell.m_ellipse(31, 25, 10, 9))
    # trapezoid torso: wide shoulders, narrower waist
    cell.stamp(Cell.m_rect(23, 33, 40, 39), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_rect(25, 39, 38, 45), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_rect(25, 34, 38, 36), SKIN_H)
    cell.stamp(Cell.m_rect(23, 33, 24, 44), SKIN_D)
    cell.stamp(Cell.m_rect(39, 33, 40, 44), SKIN_D)
    cell.stamp(Cell.m_rect(28, 37, 35, 38), OCHRE)     # war paint slash on chest
    # jagged war-skirt
    skirt = Cell.m_poly([(24, 44), (39, 44), (39, 50), (36, 48), (34, 51),
                         (32, 48), (30, 51), (28, 48), (26, 50), (24, 49)])
    cell.stamp(skirt, SKIRT_M, OUTLINE)
    cell.stamp(Cell.m_poly([(26, 45), (37, 45), (37, 47), (26, 47)]), SKIRT_D)
    # huge forearms
    cell.stamp(Cell.m_line(26, 36, 23, 45, 4), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_disc(23, 46, 3), SKIN_D, OUTLINE)
    cell.stamp(Cell.m_line(37, 36, 40, 43, 4), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_disc(40, 44, 3), SKIN_D, OUTLINE)
    cell.stamp(Cell.m_rect(39, 40, 42, 42), OCHRE)     # paint on the forearm
    # iron pauldron on the image-right shoulder
    pauldron(cell, 37, 30 + s)
    # cleaver in the left fist, blade dragging
    cell.stamp(Cell.m_rect(21, 45, 24, 49), SKIRT_D)          # grip
    cell.stamp(Cell.m_rect(18 + lg, 49, 28 + lg, 56), IRON_M, OUTLINE)
    cell.stamp(Cell.m_rect(19 + lg, 55, 28 + lg, 56), IRON_L)  # ground edge
    cell.stamp(Cell.m_rect(19 + lg, 49, 28 + lg, 50), IRON_D)
    # thick legs
    cell.stamp(Cell.m_rect(26, 50, 31, 55), SKIN_D, OUTLINE)
    cell.stamp(Cell.m_rect(33, 50, 38, 55), SKIN_D, OUTLINE)
    # small head + topknot
    small_head_down(cell, 31, 24)
    topknot_down(cell, 31, 17)


def build_up(cell, phase):
    s = sway(phase)
    # erase ears, old head, old club, legs
    erase_rect(cell, 17, 16, 23, 30)
    erase_rect(cell, 39, 16, 46, 30)
    erase_rect(cell, 38, 13, 48, 50)
    erase_rect(cell, 24, 42, 39, 57)
    cell.erase(Cell.m_ellipse(31, 23, 10, 8))
    # hulking back
    cell.stamp(Cell.m_rect(24, 30, 39, 44), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_rect(26, 31, 37, 34), SKIN_H)
    cell.stamp(Cell.m_rect(30, 35, 33, 43), SKIN_D)        # spine shade
    cell.stamp(Cell.m_rect(27, 37, 36, 38), OCHRE)         # war paint on the back
    # jagged war-skirt hem
    skirt = Cell.m_poly([(24, 42), (39, 42), (39, 48), (36, 46), (34, 49),
                         (32, 46), (30, 49), (28, 46), (26, 48), (24, 47)])
    cell.stamp(skirt, SKIRT_M, OUTLINE)
    # huge arms
    cell.stamp(Cell.m_rect(21, 31, 25, 44), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_rect(38, 31, 42, 44), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_rect(21, 31, 22, 44), SKIN_D)
    cell.stamp(Cell.m_rect(41, 31, 42, 44), SKIN_D)
    # iron pauldron from behind
    pauldron(cell, 37, 29 + s)
    # cleaver shouldered: handle up-right, big blade at the top
    cell.stamp(Cell.m_line(39, 34, 44, 22, 2), SKIRT_D)
    cell.stamp(Cell.m_rect(40, 15, 48, 23), IRON_M, OUTLINE)
    cell.stamp(Cell.m_rect(40, 15, 48, 16), IRON_L)
    cell.stamp(Cell.m_rect(47, 15, 48, 23), IRON_D)
    # thick legs (up-view baseline 48)
    cell.stamp(Cell.m_rect(26, 44, 31, 47), SKIN_D, OUTLINE)
    cell.stamp(Cell.m_rect(33, 44, 38, 47), SKIN_D, OUTLINE)
    # small head from behind + topknot
    cell.stamp(Cell.m_ellipse(31, 22, 7, 5), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(30, 20, 4, 2), SKIN_H)
    topknot_down(cell, 31, 15)


def build_side(cell, phase):
    s = sway(phase)
    lg = lag(phase)
    # erase Goblin weapon, old head incl. nose, legs
    erase_colors(cell, 34, 29, 53, 42, STEELS)
    erase_colors(cell, 20, 33, 34, 39, STEELS)
    cell.erase(Cell.m_ellipse(27, 24, 8, 8))
    erase_rect(cell, 22, 40, 38, 51)
    # hunched trapezoid torso
    cell.stamp(Cell.m_poly([(21, 29), (35, 29), (33, 42), (23, 42)]), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_poly([(24, 30), (33, 30), (32, 33), (25, 33)]), SKIN_H)
    cell.stamp(Cell.m_rect(21, 34, 23, 41), SKIN_D)
    cell.stamp(Cell.m_line(26, 34, 31, 37, 1), OCHRE)      # war paint slash
    # jagged war-skirt
    skirt = Cell.m_poly([(22, 41), (34, 41), (34, 47), (31, 45), (29, 48),
                         (27, 45), (25, 47), (22, 46)])
    cell.stamp(skirt, SKIRT_M, OUTLINE)
    # back arm column + huge front arm
    cell.stamp(Cell.m_rect(21, 32, 24, 42), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_line(32, 33, 37, 41, 4), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_disc(38, 42, 3), SKIN_D, OUTLINE)
    # iron pauldron riding the front shoulder
    pauldron(cell, 31, 27 + s)
    # cleaver dragged low in front
    cell.stamp(Cell.m_line(39, 43, 41, 46, 2), SKIRT_D)
    cell.stamp(Cell.m_rect(38 + lg, 45, 46 + lg, 49), IRON_M, OUTLINE)
    cell.stamp(Cell.m_rect(38 + lg, 48, 46 + lg, 49), IRON_L)
    cell.stamp(Cell.m_rect(38 + lg, 45, 46 + lg, 46), IRON_D)
    # thick legs
    cell.stamp(Cell.m_rect(24, 45, 29, 48), SKIN_D, OUTLINE)
    cell.stamp(Cell.m_rect(31, 45, 36, 48), SKIN_D, OUTLINE)
    # small head in profile + topknot
    cell.stamp(Cell.m_ellipse(25, 22, 6, 5), SKIN_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(24, 20, 3, 2), SKIN_H)
    cell.stamp(Cell.m_rect(28, 24, 31, 26), SKIN_D)        # jaw jut
    cell.stamp(Cell.m_rect(27, 20, 30, 21), OCHRE)         # brow paint
    cell.stamp(Cell.m_rect(27, 22, 28, 23), EYE)
    cell.stamp(Cell.m_rect(27, 22, 27, 22), OUTLINE)
    cell.stamp(Cell.m_rect(24, 15, 26, 18), HAIR, OUTLINE)


BUILDERS = {"down": build_down, "up": build_up, "side": build_side}


def main():
    cells = [Cell(c) for c in load_cells("enemies/goblin/goblin.png")]
    for i, cell in enumerate(cells):
        cell.remap(REMAP)
        BUILDERS[direction_of(i)](cell, phase_of(i))
    sheet = compose_sheet([c.img for c in cells])
    sheet.save(OUT)
    report(sheet, "orc", goblin_baselines())
    montage(sheet, "orc", "/tmp/qa_orc.png")


if __name__ == "__main__":
    main()
