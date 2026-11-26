#!/usr/bin/env python3
"""Static audit for the one-press-one-action invariant (docs/ui-input-rules.md).

    python3.13 tools/ui_qa/input_audit.py                # audit this repo, exit 1 on findings
    python3.13 tools/ui_qa/input_audit.py --root DIR     # audit another checkout
    python3.13 tools/ui_qa/input_audit.py --self-test    # on the PRE-FIX tree: expect the known pairs

Hit-rect geometry follows the engine (scene/2d/physics/touch_screen_button.cpp):
  * textured TouchScreenButton  -> top-left at the node origin, texture-sized
  * shape-only TouchScreenButton -> shape CENTRED on the node origin
Rects inside Containers only exist at runtime; tools/ui_qa/ui_overlap_probe.gd
covers those.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from itertools import combinations
from pathlib import Path

DESIGN = (640.0, 480.0)
MIN_TARGET = 44.0

SKIP_DIRS = {"addons", "build", "android", "godot-whisper", "tools", "ios", ".godot", ".git"}

# Historical D-pad allowlist. Movement is now a VirtualJoystickAddon under
# LeftCluster/Joystick (Input.action_press via the addon's _input) — not
# TouchScreenButton nodes, so there is no native-action or TSB-overlap exception.
# Kept empty and mirrored in docs/ui-input-rules.md + ui_overlap_probe.gd.
DPAD_SCENE = "touch_controls/Scene/touch_controls.tscn"
DPAD: set[str] = set()

# Not instanced by anything. Checked: the audit fails if one becomes referenced.
UNUSED_SCENES = {
    "speech_to_text/SpeechToText.tscn",
    "levels/tutorial_items/tutorial_popup.tscn",
    "touch_controls/Scene/pause_exit_button.tscn",
}

# (scene, node) full-screen STOP ColorRects that are modal dimmers. Each one's
# overlay must also push a router layer; a dimmer alone does not block TSBs.
MODAL_DIMMERS = {
    ("gui/pause_menu/pause_menu.tscn", "ColorRect"),
    ("gui/settings/settings.tscn", "Dim"),
    ("gui/bonfire/bonfire.tscn", "Dim"),
    ("gui/game_over/game_over.tscn", "Dim"),
    ("levels/title_screen/title_screen.tscn", "ConfirmDim"),
}

# Scripts allowed to look at raw pointer events.
POINTER_SCRIPTS = {
    "00_globals/ui_input_router.gd": "the single dispatcher",
    "touch_controls/Scripts/touch_controls.gd":
        "voice-only mic retry in _unhandled_input (browser gesture rule); presses no UI",
}

INTERACTIVE = {"Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton",
               "TextureButton", "LinkButton", "HSlider", "VSlider", "LineEdit"}
CONTAINERS = {"Container", "BoxContainer", "VBoxContainer", "HBoxContainer", "GridContainer",
              "CenterContainer", "MarginContainer", "PanelContainer", "HFlowContainer",
              "VFlowContainer", "ScrollContainer"}
# Control types whose default mouse_filter is STOP and that get used as backdrops.
DEFAULT_STOP = {"Control", "ColorRect", "Panel", "PanelContainer"}

Rect = tuple[float, float, float, float]  # x, y, w, h


@dataclass
class Node:
    name: str
    type: str
    parent: str | None
    props: dict[str, str] = field(default_factory=dict)

    @property
    def path(self) -> str:
        if self.parent is None:
            return "."
        return self.name if self.parent == "." else f"{self.parent}/{self.name}"


@dataclass
class Scene:
    rel: str
    nodes: dict[str, Node]
    subs: dict[str, dict[str, str]]
    exts: dict[str, str]


@dataclass(frozen=True)
class Finding:
    check: str
    where: str
    detail: str
    nodes: tuple[str, ...] = ()


def parse_scene(path: Path, rel: str) -> Scene:
    nodes: dict[str, Node] = {}
    subs: dict[str, dict[str, str]] = {}
    exts: dict[str, str] = {}
    target: dict[str, str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            target = None
            kind = line[1:].split(" ", 1)[0].rstrip("]")
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', line))
            if kind == "ext_resource":
                exts[attrs.get("id", "")] = attrs.get("path", "")
            elif kind == "sub_resource":
                target = subs.setdefault(attrs.get("id", ""), {})
            elif kind == "node":
                node = Node(attrs.get("name", ""), attrs.get("type", ""), attrs.get("parent"))
                nodes[node.path] = node
                target = node.props
        elif target is not None and " = " in line:
            key, value = line.split(" = ", 1)
            target[key] = value
    return Scene(rel, nodes, subs, exts)


def vec(value: str | None, default=(0.0, 0.0)) -> tuple[float, float]:
    if not value:
        return default
    nums = re.findall(r"-?\d+(?:\.\d+)?", value.split("(", 1)[-1])
    return (float(nums[0]), float(nums[1])) if len(nums) >= 2 else default


def num(node: Node, key: str, default: float = 0.0) -> float:
    return float(node.props.get(key, default))


def png_size(path: Path) -> tuple[float, float] | None:
    try:
        head = path.read_bytes()[:24]
    except OSError:
        return None
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return float(int.from_bytes(head[16:20], "big")), float(int.from_bytes(head[20:24], "big"))


def control_rect(scene: Scene, path: str) -> Rect | None:
    """Static rect of a Control, or None when only a Container can decide it."""
    node = scene.nodes.get(path)
    if node is None:
        return None
    if node.parent is None:
        return (0.0, 0.0, *DESIGN)
    parent = scene.nodes.get(node.parent)
    if parent is None:
        return None
    if parent.type in CONTAINERS:
        return None
    if parent.parent is None and parent.type != "Control":
        base: Rect | None = (0.0, 0.0, *DESIGN)
    else:
        base = control_rect(scene, node.parent)
    if base is None:
        return None
    bx, by, bw, bh = base
    left = bx + bw * num(node, "anchor_left") + num(node, "offset_left")
    top = by + bh * num(node, "anchor_top") + num(node, "offset_top")
    right = bx + bw * num(node, "anchor_right") + num(node, "offset_right")
    bottom = by + bh * num(node, "anchor_bottom") + num(node, "offset_bottom")
    min_w, min_h = vec(node.props.get("custom_minimum_size"))
    width, height = right - left, bottom - top
    if min_w > width:
        grow = node.props.get("grow_horizontal", "1")
        left -= {"0": min_w - width, "2": (min_w - width) / 2}.get(grow, 0)
        width = min_w
    if min_h > height:
        grow = node.props.get("grow_vertical", "1")
        top -= {"0": min_h - height, "2": (min_h - height) / 2}.get(grow, 0)
        height = min_h
    return (left, top, width, height)


def tsb_rect(scene: Scene, node: Node, root: Path) -> Rect | None:
    parent = scene.nodes.get(node.parent or "")
    if parent is None or parent.type in CONTAINERS:
        return None
    if parent.parent is None and parent.type != "Control":
        base: Rect | None = (0.0, 0.0, *DESIGN)
    else:
        base = control_rect(scene, node.parent)
    if base is None:
        return None
    px, py = vec(node.props.get("position"))
    sx, sy = vec(node.props.get("scale"), (1.0, 1.0))
    x, y = base[0] + px, base[1] + py
    shape_id = re.search(r'SubResource\("([^"]+)"\)', node.props.get("shape", ""))
    if shape_id:
        w, h = vec(scene.subs.get(shape_id.group(1), {}).get("size"), (20.0, 20.0))
        w, h = w * sx, h * sy
        if "texture_normal" not in node.props:
            return (x - w / 2, y - h / 2, w, h)
    tex_id = re.search(r'ExtResource\("([^"]+)"\)', node.props.get("texture_normal", ""))
    if tex_id:
        size = png_size(root / scene.exts.get(tex_id.group(1), "").removeprefix("res://"))
        if size:
            return (x, y, size[0] * sx, size[1] * sy)
    return None


def overlap(a: Rect, b: Rect) -> tuple[float, float] | None:
    w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return (w, h) if w > 0 and h > 0 else None


def iter_files(root: Path, suffix: str):
    for path in sorted(root.rglob(f"*{suffix}")):
        rel = path.relative_to(root)
        if SKIP_DIRS.intersection(rel.parts[:-1]) or rel.parts[0].startswith("zz_"):
            continue
        yield path, rel.as_posix()


def audit_scenes(root: Path) -> tuple[list[Finding], list[str]]:
    findings: list[Finding] = []
    allowed: list[str] = []
    for path, rel in iter_files(root, ".tscn"):
        if rel in UNUSED_SCENES:
            continue
        scene = parse_scene(path, rel)
        tsbs = [n for n in scene.nodes.values() if n.type == "TouchScreenButton"]
        rects = {n.path: tsb_rect(scene, n, root) for n in tsbs}

        for a, b in combinations(tsbs, 2):
            ra, rb = rects[a.path], rects[b.path]
            if not (ra and rb and (hit := overlap(ra, rb))):
                continue
            text = f"{a.name} / {b.name} overlap {hit[0]:g}x{hit[1]:g}"
            if rel == DPAD_SCENE and {a.name, b.name} <= DPAD:
                allowed.append(f"{rel}: {text}")
            else:
                findings.append(Finding("tsb-overlap", rel, text, (a.name, b.name)))

        buttons = {p: control_rect(scene, p) for p, n in scene.nodes.items() if n.type == "Button"}
        for tsb in tsbs:
            for button_path, rb in buttons.items():
                ra = rects[tsb.path]
                if ra and rb and (hit := overlap(ra, rb)):
                    button = scene.nodes[button_path]
                    findings.append(Finding(
                        "tsb-on-button", rel,
                        f"{tsb.name} sits on Button {button.name} ({hit[0]:g}x{hit[1]:g})",
                        (tsb.name, button.name)))

        for node in scene.nodes.values():
            if node.type in INTERACTIVE:
                rect = control_rect(scene, node.path)
                w, h = (rect[2], rect[3]) if rect else vec(node.props.get("custom_minimum_size"))
                if w < MIN_TARGET or h < MIN_TARGET:
                    findings.append(Finding(
                        "small-target", rel, f"{node.name} ({node.type}) is {w:g}x{h:g}", (node.name,)))
            if node.name.startswith("Touch_") or (
                    node.type == "TouchScreenButton" and node.name.startswith("Touch")):
                findings.append(Finding("touch-twin-node", rel, node.name, (node.name,)))
            if node.type == "TouchScreenButton":
                action = node.props.get("action", '""').strip('"')
                if action and not (rel == DPAD_SCENE and node.name in DPAD):
                    findings.append(Finding(
                        "tsb-native-action", rel, f'{node.name} has action="{action}"', (node.name,)))
            full = (num(node, "anchor_right") == 1.0 and num(node, "anchor_bottom") == 1.0
                    and num(node, "anchor_left") == 0.0 and num(node, "anchor_top") == 0.0)
            stop = node.props.get("mouse_filter", "0" if node.type in DEFAULT_STOP else "") == "0"
            if full and stop and not (node.type == "ColorRect" and (rel, node.name) in MODAL_DIMMERS):
                findings.append(Finding(
                    "fullscreen-stop", rel, f"{node.name} ({node.type}) is full-screen STOP", (node.name,)))
    return findings, allowed


def strip_comment(line: str) -> str:
    return re.sub(r"(^|\s)#.*$", "", line)


def handler_name(expr: str) -> str:
    """The handler's identity. Bound arguments are part of it: _set_tab.bind(A)
    and _set_tab.bind(B) are two different actions."""
    expr = expr.strip()
    while expr.count(")") > expr.count("("):
        expr = expr[:-1].rstrip()
    return expr


def audit_scripts(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    scene_text = "".join(p.read_text(encoding="utf-8") for p, _ in iter_files(root, ".tscn"))
    for path, rel in iter_files(root, ".gd"):
        lines = [strip_comment(l) for l in path.read_text(encoding="utf-8").splitlines()]
        # handler -> nodes it is wired to; node -> kinds of wiring
        by_handler: dict[str, set[str]] = defaultdict(set)
        by_node: dict[str, set[str]] = defaultdict(set)

        def wire(node: str, kind: str, expr: str) -> None:
            name = handler_name(expr)
            if name.startswith("func") or name in {"handler", "action", ""}:
                return
            by_handler[name].add(node.strip())
            by_node[node.strip()].add(kind)

        for number, line in enumerate(lines, 1):
            code = line.strip()
            if code.startswith("func "):
                continue
            if m := re.search(r"([\w%$.]+)\.(pressed|toggled|gui_input)\.connect\((.+)\)", code):
                wire(m[1], "gui_input" if m[2] == "gui_input" else "pressed", m[3])
            if m := re.search(r'\bconnect\("(pressed|gui_input)",\s*Callable\(self,\s*"(\w+)"\)', code):
                wire("self", m[1], m[2])
            if m := re.search(r"(?:UiInputRouter\.(?:bind|bind_button)|(?<![\w.])_bind|(?<![\w.])_route)\((.+)\)\s*$", code):
                args = [a.strip() for a in re.split(r",(?![^()]*\))", m[1])]
                if len(args) >= 3 and args[2].startswith("_on"):  # old twin helper: button, touch, handler
                    wire(args[0], "pressed", args[2])
                    wire(args[1], "pressed", args[2])
                elif len(args) >= 2:
                    wire(args[0], "router", args[1])
            if "TouchScreenButton.new()" in code:
                findings.append(Finding("touch-twin-node", f"{rel}:{number}", "creates a TouchScreenButton"))
            if 'emit_signal("pressed")' in code or re.search(r"\.pressed\.emit\(", code):
                findings.append(Finding("synthetic-press", f"{rel}:{number}", code))
            if re.search(r"\bInputEvent(ScreenTouch|MouseButton)\b", code) and rel not in POINTER_SCRIPTS:
                findings.append(Finding("pointer-path", f"{rel}:{number}", code))
            if m := re.search(r"(\w*(?:button|btn|input|_back)\w*)\.custom_minimum_size\s*=\s*Vector2\(([\d.]+),\s*([\d.]+)\)", code):
                w, h = float(m[2]), float(m[3])
                if h < MIN_TARGET or 0 < w < MIN_TARGET:
                    findings.append(Finding("small-target", f"{rel}:{number}", f"{m[1]} is {w:g}x{h:g}", (m[1],)))

        for name, targets in by_handler.items():
            if len(targets) > 1:
                findings.append(Finding(
                    "handler-multi-node", rel, f"{name} wired to {', '.join(sorted(targets))}"))
        for node, kinds in by_node.items():
            if "gui_input" in kinds and kinds & {"pressed", "router"}:
                findings.append(Finding(
                    "pressed-and-gui-input", rel, f"{node} is wired through gui_input and {sorted(kinds - {'gui_input'})}"))

    for unused in UNUSED_SCENES:
        if f'path="res://{unused}"' in scene_text:
            findings.append(Finding("stale-allowlist", unused, "is in UNUSED_SCENES but a scene instances it"))
    return findings


# Pairs the pre-fix tree must report.
SELF_TEST = [
    ("tsb-overlap", "bonfire.tscn", "TouchCrit", "TouchEquip"),
    ("tsb-overlap", "settings.tscn", "TouchDifficulty", "TouchReset"),
    ("tsb-overlap", "bonfire.tscn", "TouchJournal", "TouchContinue"),
    ("tsb-overlap", "bonfire.tscn", "TouchJournal", "TouchTitle"),
    ("tsb-on-button", "touch_controls.tscn", "Interact", "Touch_Interact"),
    ("tsb-on-button", "touch_controls.tscn", "Mic", "Touch_Mic"),
    ("any", "touch_controls.tscn", "Attack", "Interact"),
]


def self_test(findings: list[Finding]) -> int:
    missing = 0
    for index, (check, scene, a, b) in enumerate(SELF_TEST, 1):
        found = [f for f in findings
                 if (check == "any" or f.check == check) and f.where.endswith(scene) and set(f.nodes) == {a, b}]
        if found:
            print(f"  ✅ {index} {found[0].detail}")
        else:
            missing += 1
            print(f"  ❌ {index} {scene} {a} / {b} NOT reported")
            if index == 7:
                print("       Attack is textured, so the engine anchors it top-left: x 132..212 in RightCluster,\n"
                      "       while Interact ends at x 100. They are 32 px apart. See the report, section 3.")
    print(f"self-test: {len(SELF_TEST) - missing}/{len(SELF_TEST)} pairs reported")
    return 1 if missing else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    scene_findings, allowed = audit_scenes(args.root)
    findings = scene_findings + audit_scripts(args.root)

    grouped: dict[str, list[Finding]] = defaultdict(list)
    for f in findings:
        grouped[f.check].append(f)
    for check in sorted(grouped):
        print(f"\n❌ {check} ({len(grouped[check])})")
        for f in grouped[check]:
            print(f"   {f.where}: {f.detail}")
    print(f"\nAllowlisted D-pad diagonals ({len(allowed)}):")
    for line in allowed:
        print(f"   {line}")
    print(f"\n{len(findings)} finding(s)")

    if args.self_test:
        print()
        return self_test(findings)
    # Joystick replaced the D-pad: zero TSB diagonal overlaps are expected.
    if len(allowed) != 0:
        print("❌ expected 0 D-pad diagonal overlaps; leftover arrow TSBs?")
        return 1
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
