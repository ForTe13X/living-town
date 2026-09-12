#!/usr/bin/env python3
"""P1-i visual contract for the playable East Ocean warehouse.

The normal and ``--draw-skip warehouse_status`` journeys use the same pinned
seed/tick/player fixture.  The only allowed pixel difference is the live stock
and CargoManifest board.  Journey metadata separately proves that the real
player agent entered and returned through the portal.
"""

from __future__ import annotations

import argparse
import json
import os

from assert_daynight import _png_rgb_rows


MIN_CHANGED = 8_000
MAX_CHANGED = 100_000


def _rgb(row: bytearray, bpp: int, x: int) -> tuple[int, int, int]:
    i = x * bpp
    return row[i], row[i + 1], row[i + 2]


def _load_meta(directory: str) -> dict:
    with open(os.path.join(directory, "rt_meta.json"), encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("status_on_dir")
    parser.add_argument("status_off_dir")
    parser.add_argument("--tol", type=int, default=0)
    args = parser.parse_args()

    on_meta = _load_meta(args.status_on_dir)
    off_meta = _load_meta(args.status_off_dir)
    failures: list[str] = []
    for name, meta in (("on", on_meta), ("off", off_meta)):
        if meta.get("space") != "port_warehouse":
            failures.append(f"{name} fixture did not enter port_warehouse")
        if meta.get("player_entered") is not True or meta.get("player_returned") is not True:
            failures.append(f"{name} fixture did not prove player portal roundtrip")
        interior = meta.get("interior", {})
        if interior.get("space") != "port_warehouse" or interior.get("floor") != "1f":
            failures.append(f"{name} interior metadata is not port_warehouse/1f")
        observatory = meta.get("observatory", {})
        if observatory.get("console_cell") != [6, 1] or observatory.get("mode") != "read_only":
            failures.append(f"{name} did not use the authored read-only observatory console")
        if (observatory.get("sim_noop") is not True
                or observatory.get("action_bar_hidden") is not True
                or observatory.get("chat_hidden") is not True
                or observatory.get("location_truthful") is not True):
            failures.append(f"{name} observatory mutated Sim or exposed stale/social player UI")
        feedback = observatory.get("log_bbcode", "")
        if "观测台｜" not in feedback or "（只读）" not in feedback:
            failures.append(f"{name} interior frame lacks the real console interaction receipt")
    if failures:
        print("[P1I-WAREHOUSE] FAIL: " + "; ".join(failures))
        return 1

    on_path = os.path.join(args.status_on_dir, "rt_interior.png")
    off_path = os.path.join(args.status_off_dir, "rt_interior.png")
    aw, ah, abpp, arows = _png_rgb_rows(on_path)
    bw, bh, bbpp, brows = _png_rgb_rows(off_path)
    if (aw, ah) != (bw, bh):
        print(f"[P1I-WAREHOUSE] FAIL: frame size mismatch {(aw, ah)} != {(bw, bh)}")
        return 1

    # P1-v observatory panel is authored at cells x=3.18..5.90, y=.62..3.17.  Transform
    # that world box through SpaceShot's measured map rect rather than pinning
    # screen pixels, with a small margin for shadow and glyph antialiasing.
    rect = on_meta["interior"]["map_rect_design"]
    sx, sy = rect[2] / 9.0, rect[3] / 6.0
    crop = (
        max(0, int(rect[0] + 3.08 * sx)),
        max(0, int(rect[1] + 0.50 * sy)),
        min(aw, int(rect[0] + 6.02 * sx + 0.999)),
        min(ah, int(rect[1] + 3.30 * sy + 0.999)),
    )
    changed = outside = 0
    xs: list[int] = []
    ys: list[int] = []
    for y in range(ah):
        for x in range(aw):
            left = _rgb(arows[y], abpp, x)
            right = _rgb(brows[y], bbpp, x)
            if max(abs(left[i] - right[i]) for i in range(3)) <= args.tol:
                continue
            changed += 1
            xs.append(x)
            ys.append(y)
            if not (crop[0] <= x < crop[2] and crop[1] <= y < crop[3]):
                outside += 1

    if not xs:
        failures.append("status ON/OFF interiors are identical")
        bbox = None
    else:
        bbox = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    if not (MIN_CHANGED <= changed <= MAX_CHANGED):
        failures.append(f"changed pixels {changed} outside [{MIN_CHANGED},{MAX_CHANGED}]")
    if outside:
        failures.append(f"{outside} changed pixels outside board crop {crop}")
    if failures:
        print("[P1I-WAREHOUSE] FAIL: " + "; ".join(failures))
        return 1

    print(
        f"[P1I-WAREHOUSE] PASS: player roundtrip=true size={aw}x{ah} "
        f"changed={changed} bbox={bbox} crop={crop} tol={args.tol}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
