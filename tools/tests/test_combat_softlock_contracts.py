#!/usr/bin/env python3
"""Regression contracts for horde combat softlocks (no Godot binary required).

1) Challenge feedback timers must tick while the tree is paused, or
   speech_challenge_active never clears and every enemy ignores damage.
2) Fatal horde death must not start stun i-frames that later re-enable the
   hitbox after bonfire revive (delayed damage from the killing blow).
3) Revive must bump/cancel stale i-frame coroutines and grant spawn grace.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
failures = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global failures
    if cond:
        print(f"✅ {name}")
    else:
        failures += 1
        suffix = f" — {detail}" if detail else ""
        print(f"❌ {name}{suffix}")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def main() -> int:
    hud = read("gui/player_hud/player_hud.gd")
    enemy = read("enemies/scripts/enemy.gd")
    player = read("player/Scripts/player.gd")
    manager = read("00_globals/global_player_manager.gd")

    # Feedback hide must use a pause-immune SceneTreeTimer (2nd arg true).
    hide_fn = re.search(
        r"func _hide_feedback_after_delay\(.*?\n(?:.*\n)*?(?=\nfunc |\Z)",
        hud,
    )
    check(
        "player_hud feedback timer ignores pause",
        bool(hide_fn) and "create_timer(FEEDBACK_DURATION, true)" in hide_fn.group(0),
        "expected create_timer(FEEDBACK_DURATION, true)",
    )

    wait_fn = re.search(
        r"func _wait_feedback_and_resume\(.*?\n(?:.*\n)*?(?=\nfunc |\Z)",
        enemy,
    )
    check(
        "enemy feedback wait timer ignores pause",
        bool(wait_fn) and "create_timer(PlayerHudUI.FEEDBACK_DURATION, true)" in wait_fn.group(0),
        "expected create_timer(..., true)",
    )

    take = re.search(
        r"func _take_damage\(.*?\n(?:.*\n)*?(?=\nfunc |\Z)",
        player,
    )
    take_body = take.group(0) if take else ""
    # Fatal EndlessHorde branch should not emit player_damaged (avoids stun i-frames).
    # Isolate the block between the EndlessHorde check and the playground else.
    horde_match = re.search(
        r'if scene != null and scene\.name == "EndlessHorde":(.*?)(?:^\telse:)',
        take_body,
        re.S | re.M,
    )
    fatal = horde_match.group(1) if horde_match else ""
    check(
        "horde death does not emit player_damaged",
        bool(horde_match) and "player_damaged.emit" not in fatal,
        "fatal horde path still emits player_damaged" if fatal else "EndlessHorde death block missing",
    )
    check(
        "player has cancel_invulnerability helper",
        "func cancel_invulnerability" in player,
    )
    check(
        "make_invulnerable uses token guard",
        "_invuln_token" in player and "if token != _invuln_token" in player,
    )
    check(
        "revive cancels stale i-frames and grants spawn grace",
        "cancel_invulnerability" in manager
        and "make_invulnerable" in manager
        and "speech_challenge_active" in manager,
    )
    check(
        "horde death clears speech_challenge_active",
        "speech_challenge_active" in fatal,
    )
    stun = read("enemies/scripts/states/enemy_state_stun.gd")
    check(
        "enemy stun has max-duration escape",
        "STUN_MAX_SEC" in stun and "_stun_elapsed" in stun,
    )

    if failures:
        print(f"\n{failures} contract(s) failed")
        return 1
    print("\nAll combat softlock contracts passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
