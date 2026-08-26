#!/usr/bin/env python3
"""Build an isolated game tree with the C3 first-frame daylight fix disabled.

This is a fault injector for the hosted visual canary, not a product migration.
It copies ``game/`` to an empty caller-owned destination, omits the rebuildable
``.godot`` cache, and changes exactly one structurally identified assignment in
``scripts/Main.gd``. The source tree is read twice and must remain byte-exact.

Usage:
    python tools/prepare_visual_canary_negative.py <source-game> <dest-game>

The JSON receipt printed on stdout travels with the two negative framebuffer
artifacts. Existing destinations and ambiguous source seams fail closed; this
script never removes or overwrites a directory.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path


ANCHOR = b"\t_modulate = CanvasModulate.new()"
NEEDLE = b"\t_modulate.color = _daylight(Sim.time_of_day())"
REPLACEMENT = (
    b"\t_modulate.color = Color.WHITE  # P1-y fault injection: disable first-frame daylight"
)
EXPECTED_NEEDLE_COUNT = 4


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fail(message: str) -> int:
    print(f"prepare_visual_canary_negative: {message}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        return fail("usage: <source-game> <dest-game>")

    source = Path(argv[0]).resolve()
    dest = Path(argv[1]).resolve()
    if not source.is_dir():
        return fail(f"source game directory is missing: {source}")
    if dest.exists():
        return fail(f"destination already exists (refusing overwrite): {dest}")
    if source == dest or source in dest.parents or dest in source.parents:
        return fail("source and destination must be disjoint directory trees")

    source_main = source / "scripts" / "Main.gd"
    if not source_main.is_file():
        return fail(f"source seam is missing: {source_main}")
    before = source_main.read_bytes()
    anchor_count = before.count(ANCHOR)
    needle_count = before.count(NEEDLE)
    if anchor_count != 1:
        return fail(f"expected one CanvasModulate construction anchor, found {anchor_count}")
    if needle_count != EXPECTED_NEEDLE_COUNT:
        return fail(f"expected {EXPECTED_NEEDLE_COUNT} daylight assignments, found {needle_count}")
    if REPLACEMENT in before:
        return fail("source already contains the P1-y injected replacement")

    anchor_at = before.index(ANCHOR)
    target_at = before.find(NEEDLE, anchor_at + len(ANCHOR))
    goal_at = before.find(b"\n\t_goals =", target_at)
    if target_at < 0 or goal_at < 0 or target_at > goal_at:
        return fail("could not bind the first-frame daylight assignment to the startup seam")

    shutil.copytree(source, dest, ignore=shutil.ignore_patterns(".godot"))
    dest_main = dest / "scripts" / "Main.gd"
    copied = dest_main.read_bytes()
    if copied != before:
        return fail("copied Main.gd differs from the source before injection")
    after = copied[:target_at] + REPLACEMENT + copied[target_at + len(NEEDLE) :]
    dest_main.write_bytes(after)

    source_after = source_main.read_bytes()
    if source_after != before:
        return fail("source Main.gd changed while preparing the negative tree")
    if after.count(REPLACEMENT) != 1 or after.count(NEEDLE) != EXPECTED_NEEDLE_COUNT - 1:
        return fail("injected tree does not contain the exact one-line mutation")

    receipt = {
        "schema": "p1y-hosted-visual-negative/v1",
        "source_game": str(source),
        "destination_game": str(dest),
        "mutation": "Main.gd startup CanvasModulate assignment: _daylight(...) -> Color.WHITE",
        "expected_detection": ["FAIL A1", "FAIL A2", "DAYNIGHT GATE: FAIL (2)"],
        "source_main_sha256_before": sha256(before),
        "source_main_sha256_after": sha256(source_after),
        "negative_main_sha256": sha256(after),
        "source_unchanged": source_after == before,
        "omitted_rebuildable_paths": [".godot"],
    }
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
