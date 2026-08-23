#!/usr/bin/env python3
"""Pixel contract for the P1-c East Ocean CargoManifest carrier projection.

Input A is the normal seed-3/day-3-noon town frame. Input B is the exact same
fixture rendered with ``--draw-skip carrier``.  A valid delivery must make a
substantial, localized difference inside the authored East Ocean berth and no
difference elsewhere.  The gate intentionally stores no PNG golden.
"""

from __future__ import annotations

import argparse
import sys

from assert_daynight import _png_rgb_rows


REFERENCE_SIZE = (1280, 768)
REFERENCE_CROP = (930, 180, 1000, 245)  # tolerant box around berth [60, 8]
MIN_CHANGED = 100
MAX_CHANGED = 3000


def _scaled_crop(width: int, height: int) -> tuple[int, int, int, int]:
    sx = width / REFERENCE_SIZE[0]
    sy = height / REFERENCE_SIZE[1]
    x0, y0, x1, y1 = REFERENCE_CROP
    return (
        int(x0 * sx),
        int(y0 * sy),
        int(x1 * sx + 0.999),
        int(y1 * sy + 0.999),
    )


def _rgb(row: bytearray, bpp: int, x: int) -> tuple[int, int, int]:
    i = x * bpp
    return row[i], row[i + 1], row[i + 2]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("carrier_on")
    parser.add_argument("carrier_off")
    parser.add_argument("--tol", type=int, default=0)
    args = parser.parse_args()

    try:
        aw, ah, abpp, arows = _png_rgb_rows(args.carrier_on)
        bw, bh, bbpp, brows = _png_rgb_rows(args.carrier_off)
    except (OSError, ValueError) as exc:
        print(f"[CARRIER] FAIL: {exc}")
        return 1
    if (aw, ah) != (bw, bh):
        print(f"[CARRIER] FAIL: frame size mismatch {(aw, ah)} != {(bw, bh)}")
        return 1

    crop = _scaled_crop(aw, ah)
    changed = 0
    outside = 0
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

    if changed == 0:
        print("[CARRIER] FAIL: carrier ON and OFF frames are identical")
        return 1
    bbox = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
    failures: list[str] = []
    if not (MIN_CHANGED <= changed <= MAX_CHANGED):
        failures.append(f"changed pixels {changed} outside [{MIN_CHANGED},{MAX_CHANGED}]")
    if outside:
        failures.append(f"{outside} changed pixels outside East Ocean crop {crop}")
    if not (crop[0] <= bbox[0] < bbox[2] <= crop[2] and crop[1] <= bbox[1] < bbox[3] <= crop[3]):
        failures.append(f"diff bbox {bbox} escapes East Ocean crop {crop}")
    if failures:
        print("[CARRIER] FAIL: " + "; ".join(failures))
        return 1

    print(f"[CARRIER] PASS: size={aw}x{ah} changed={changed} bbox={bbox} crop={crop} tol={args.tol}")
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    raise SystemExit(main())
