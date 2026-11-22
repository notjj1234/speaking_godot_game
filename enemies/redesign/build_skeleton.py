"""build_skeleton.py — Skeleton sheet: dead spearman, kettle helm + round shield.

Structural edits on the Goblin base: bare head replaced by a skull in a rusty
kettle helm, body thinned to bone limbs, Goblin club replaced by a tall spear,
round shield on the arm (back in the up view), loincloth replaced by a ragged
crimson tabard. Full ramp rebuild: bone ivory / cold blue-grey / rust / crimson.
Edit discipline: erase old anatomy to transparent FIRST, then stamp new shapes.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import (Cell, load_cells, compose_sheet, direction_of, phase_of, rp,
                    G_OUTLINE, G_SKIN_L, G_SKIN_M, G_SKIN_H, G_BLACK, G_CLOTH,
                    G_LEATHER, G_GRAY, G_WHITE, G_STEEL, G_YELLOW)
from qa import report, montage, goblin_baselines

OUT = rp("enemies/skeleton/skeleton.png")

# Palette — bone ivory / cold blue-grey / rust / faded crimson. No green, no flesh.
OUTLINE = (35, 44, 56, 255)
BONE_L = (232, 226, 207, 255)
BONE_M = (201, 194, 168, 255)
BONE_D = (150, 143, 120, 255)
BLACK = (0, 0, 0, 255)
HELM_M = (126, 139, 153, 255)
HELM_D = (76, 88, 102, 255)
RUST = (138, 74, 44, 255)
TABARD_M = (140, 58, 58, 255)
TABARD_D = (92, 38, 38, 255)
WOOD_D = (84, 64, 40, 255)
WOOD_M = (122, 96, 62, 255)
TIP_L = (198, 208, 216, 255)

REMAP = {
    G_OUTLINE: OUTLINE, G_SKIN_H: BONE_L, G_SKIN_L: BONE_M, G_SKIN_M: BONE_D,
    G_BLACK: BLACK, G_CLOTH: TABARD_D, G_LEATHER: TABARD_M, G_GRAY: WOOD_D,
    G_WHITE: TIP_L, G_STEEL: HELM_M, G_YELLOW: BLACK,
}
STEELS = {TIP_L, HELM_M, HELM_D}


def erase_rect(cell, x0, y0, x1, y1):
    cell.erase(Cell.m_rect(x0, y0, x1, y1))


def erase_colors(cell, x0, y0, x1, y1, colors):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if cell.get(x, y) in colors:
                cell.set(x, y, (0, 0, 0, 0))


def jitter(phase):
    # marionette unevenness on the head mass
    return [0, 1, 0, 1][phase]


def skull(cell, cx, cy, back=False):
    """Skull: bone dome with dark sockets (front) or bare dome (back)."""
    cell.stamp(Cell.m_ellipse(cx, cy, 7, 6), BONE_L, OUTLINE)
    cell.stamp(Cell.m_ellipse(cx - 1, cy - 2, 4, 2), BONE_M)
    if not back:
        cell.stamp(Cell.m_disc(cx - 3, cy, 1), BLACK)
        cell.stamp(Cell.m_disc(cx + 3, cy, 1), BLACK)
        cell.stamp(Cell.m_rect(cx - 3, cy + 2, cx + 3, cy + 3), BONE_D)   # jaw
        cell.stamp(Cell.m_rect(cx, cy + 1, cx, cy + 2), BLACK)           # nasal
    else:
        cell.stamp(Cell.m_rect(cx - 3, cy + 2, cx + 3, cy + 3), BONE_D)


def kettle_helm(cell, cx, ybrim, back=False):
    """Rusty kettle helm: brim line + dome, sitting on the skull."""
    cell.stamp(Cell.m_rect(cx - 9, ybrim, cx + 9, ybrim + 1), RUST, OUTLINE)
    cell.stamp(Cell.m_ellipse(cx, ybrim - 1, 6, 3), HELM_M, OUTLINE)
    cell.stamp(Cell.m_ellipse(cx - 1, ybrim - 2, 3, 1), HELM_D)


def shield(cell, cx, cy, r=6):
    """Round shield: iron rim, wood face, metal boss."""
    cell.stamp_ramp([
        (Cell.m_disc(cx, cy, r), HELM_D, OUTLINE),
        (Cell.m_disc(cx, cy, r - 1), WOOD_M, None),
        (Cell.m_disc(cx, cy, r - 3), WOOD_D, None),
        (Cell.m_disc(cx, cy, 1), HELM_M, None),
    ])


def build_down(cell, phase):
    j = jitter(phase)
    # erase ears, old head, old club, both arms (rebuilt as bone), torso sides
    erase_rect(cell, 17, 18, 23, 31)
    erase_rect(cell, 39, 18, 46, 31)
    erase_rect(cell, 17, 33, 28, 58)
    erase_rect(cell, 19, 32, 27, 48)
    erase_rect(cell, 35, 32, 45, 48)
    cell.erase(Cell.m_ellipse(31, 25, 10, 9))
    erase_rect(cell, 24, 32, 27, 46)
    erase_rect(cell, 36, 32, 39, 46)
    erase_rect(cell, 24, 47, 39, 57)
    # ribcage (narrow bone torso)
    cell.stamp(Cell.m_rect(28, 33, 35, 40), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(29, 34, 34, 35), BONE_L)
    cell.stamp(Cell.m_rect(29, 36, 34, 36), BONE_D)   # rib line
    cell.stamp(Cell.m_rect(29, 38, 34, 38), BONE_D)   # rib line
    # ragged tabard (stays within the ribcage width)
    tab = Cell.m_poly([(28, 39), (35, 39), (35, 45), (33, 43), (32, 46), (30, 43), (28, 46)])
    cell.stamp(tab, TABARD_M, OUTLINE)
    cell.stamp(Cell.m_poly([(29, 40), (34, 40), (34, 42), (29, 42)]), TABARD_D)
    # thin bone arms
    cell.stamp(Cell.m_line(28, 34, 25, 42, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_disc(25, 42, 1), BONE_L)
    cell.stamp(Cell.m_line(35, 34, 38, 41, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_disc(38, 41, 1), BONE_L)
    # shield on the left arm
    shield(cell, 23, 41, 6)
    # spear held upright beside the right shoulder (bare 1px shaft)
    cell.stamp(Cell.m_line(40, 22, 40, 46, 1), WOOD_D)
    cell.stamp(Cell.m_poly([(38, 15), (42, 15), (40, 22)]), TIP_L, OUTLINE)
    cell.stamp(Cell.m_disc(39, 43, 1), BONE_L)        # hand on shaft
    # thin shins + separate bone feet
    cell.stamp(Cell.m_line(29, 46, 29, 54, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_line(34, 46, 34, 54, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(26, 54, 29, 55), BONE_D, OUTLINE)
    cell.stamp(Cell.m_rect(33, 54, 36, 55), BONE_D, OUTLINE)
    # skull + kettle helm (jittered for marionette feel)
    skull(cell, 31, 24 + j)
    kettle_helm(cell, 31, 18 + j)


def build_up(cell, phase):
    j = jitter(phase)
    # erase ears, old head, old club, torso sides, legs
    erase_rect(cell, 17, 16, 23, 30)
    erase_rect(cell, 39, 16, 46, 30)
    erase_rect(cell, 38, 13, 48, 50)
    cell.erase(Cell.m_ellipse(31, 23, 10, 8))
    erase_rect(cell, 24, 30, 27, 46)
    erase_rect(cell, 36, 30, 39, 46)
    erase_rect(cell, 24, 44, 39, 57)
    # spine hint above the shield
    cell.stamp(Cell.m_rect(30, 31, 32, 33), BONE_D, OUTLINE)
    # ragged tabard hem below the shield
    tab = Cell.m_poly([(27, 42), (36, 42), (36, 47), (34, 45), (32, 48), (30, 45), (28, 47), (27, 46)])
    cell.stamp(tab, TABARD_M, OUTLINE)
    # thin bone arms at the sides
    cell.stamp(Cell.m_line(27, 32, 24, 40, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_line(35, 32, 38, 40, 2), BONE_M, OUTLINE)
    # shield slung on the back (the big read in this direction)
    shield(cell, 31, 37, 7)
    # spear angled up beside the body (bare 1px shaft)
    cell.stamp(Cell.m_line(40, 20, 43, 44, 1), WOOD_D)
    cell.stamp(Cell.m_poly([(38, 13), (42, 13), (40, 20)]), TIP_L, OUTLINE)
    # thin shins + separate bone feet (up-view baseline 48)
    cell.stamp(Cell.m_line(29, 40, 29, 46, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_line(34, 40, 34, 46, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(26, 46, 29, 47), BONE_D, OUTLINE)
    cell.stamp(Cell.m_rect(33, 46, 36, 47), BONE_D, OUTLINE)
    # back of skull + helm
    skull(cell, 31, 22 + j, back=True)
    kettle_helm(cell, 31, 16 + j, back=True)


def build_side(cell, phase):
    j = jitter(phase)
    # erase Goblin weapon, old head incl. nose, legs
    erase_colors(cell, 34, 29, 53, 42, STEELS)
    erase_colors(cell, 20, 33, 34, 39, STEELS)
    cell.erase(Cell.m_ellipse(27, 24, 8, 8))
    erase_rect(cell, 22, 40, 37, 51)
    # thin torso: ribs + tabard tail behind the shield
    cell.stamp(Cell.m_rect(24, 31, 31, 39), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(25, 32, 30, 33), BONE_L)
    cell.stamp(Cell.m_rect(25, 35, 30, 35), BONE_D)
    cell.stamp(Cell.m_rect(25, 37, 30, 37), BONE_D)
    tab = Cell.m_poly([(23, 38), (31, 38), (31, 46), (29, 44), (27, 47), (25, 44), (23, 46)])
    cell.stamp(tab, TABARD_M, OUTLINE)
    # thin bone arm reaching to the spear
    cell.stamp(Cell.m_line(30, 34, 34, 39, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_disc(34, 39, 1), BONE_L)
    # round shield on the near arm (the read in this direction)
    shield(cell, 24, 41, 6)
    # spear held upright, tip high (bare 1px shaft)
    cell.stamp(Cell.m_line(37, 16, 37, 44, 1), WOOD_D)
    cell.stamp(Cell.m_poly([(35, 9), (39, 9), (37, 16)]), TIP_L, OUTLINE)
    # thin shins + separate bone feet
    cell.stamp(Cell.m_line(28, 44, 28, 46, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(25, 46, 28, 47), BONE_D, OUTLINE)
    cell.stamp(Cell.m_line(32, 44, 32, 45, 2), BONE_M, OUTLINE)
    cell.stamp(Cell.m_rect(31, 45, 34, 46), BONE_D, OUTLINE)
    # skull in profile + kettle helm
    skull(cell, 26, 23 + j)
    erase_rect(cell, 29, 26, 31, 27)  # profile: trim far socket for a one-eyed read
    cell.stamp(Cell.m_disc(28, 23 + j, 1), BLACK)
    kettle_helm(cell, 26, 17 + j)


BUILDERS = {"down": build_down, "up": build_up, "side": build_side}


def main():
    cells = [Cell(c) for c in load_cells("enemies/goblin/goblin.png")]
    for i, cell in enumerate(cells):
        cell.remap(REMAP)
        BUILDERS[direction_of(i)](cell, phase_of(i))
    sheet = compose_sheet([c.img for c in cells])
    sheet.save(OUT)
    report(sheet, "skeleton", goblin_baselines())
    montage(sheet, "skeleton", "/tmp/qa_skeleton.png")


if __name__ == "__main__":
    main()
