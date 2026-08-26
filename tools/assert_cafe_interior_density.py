#!/usr/bin/env python3
"""Fail-closed View-only café-density gate for the already-authored café slots.

It compares the real normal and ``--draw-skip interior_furniture`` frames for both
floors.  Furniture must be present on each floor, normal furniture may not paint
outside café's authored inner-cell footprint, and the two floor treatments must
remain visibly distinct.  It intentionally knows no Sim/data state.
"""
import argparse
import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("[CAFEDENSITY] FAIL Pillow is required; refusing to skip")
    sys.exit(1)

VP = (1280.0, 768.0)
T = 48.0
PAD = (120.0, 240.0)
DTOL = 28


def rect():
    """The 8x6 café inner cells [1..6]x[1..4] in its shot-fit frame."""
    zoom = min((VP[0] - PAD[0]) / (8 * T), (VP[1] - PAD[1]) / (6 * T))
    sx = lambda v: (v - 4 * T) * zoom + VP[0] / 2.0
    sy = lambda v: (v - 3 * T) * zoom + VP[1] / 2.0
    return (math.ceil(sx(T)), math.ceil(sy(T)),
            math.floor(sx(7 * T)), math.floor(sy(5 * T)))


# C1's real shot-fit map rectangle for café's authored 8x6 room.  Boundary cells are
# deliberately included: the existing 2F picture slots are wall-mounted at x=0.
FOOTPRINT = (261, 100, 1019, 668)


def load(path):
    if not os.path.isfile(path):
        raise ValueError("missing frame: " + path)
    im = Image.open(path).convert("RGB")
    if im.size != (1280, 768):
        raise ValueError("expected 1280x768 frame: %s is %s" % (path, im.size))
    return im


def changes(normal, bare):
    return [(max(abs(a - b) for a, b in zip(p, q)) > DTOL)
            for p, q in zip(normal.getdata(), bare.getdata())]


def assess(normal, bare):
    changed = changes(normal, bare)
    x0, y0, x1, y1 = FOOTPRINT
    inside = outside = 0
    for y in range(768):
        row = y * 1280
        for x in range(1280):
            if changed[row + x]:
                if x0 <= x < x1 and y0 <= y < y1:
                    inside += 1
                else:
                    outside += 1
    return inside, outside


def check(out_dir):
    one, one_bare = load(os.path.join(out_dir, "vg_int_cafe.png")), load(os.path.join(out_dir, "vg_cafe1f_bare.png"))
    two, two_bare = load(os.path.join(out_dir, "vg_cafe2f.png")), load(os.path.join(out_dir, "vg_cafe2f_bare.png"))
    a_in, a_out = assess(one, one_bare)
    b_in, b_out = assess(two, two_bare)
    r = rect()
    floor_pixels = (r[2] - r[0]) * (r[3] - r[1])
    floor_diff = sum(changes(one, two))
    print("[CAFEDENSITY] footprint=%s density-region=%s 1F inside=%d outside=%d 2F inside=%d outside=%d 1F-v-2F=%d" %
          (FOOTPRINT, r, a_in, a_out, b_in, b_out, floor_diff))
    failures = []
    if a_in < floor_pixels // 25:
        failures.append("1F furniture is too sparse or draw-skip was not applied")
    if b_in < floor_pixels // 25:
        failures.append("2F furniture is too sparse or draw-skip was not applied")
    if a_out or b_out:
        failures.append("furniture pixels escaped the authored inner-cell footprint")
    if floor_diff < floor_pixels // 12:
        failures.append("1F public café and 2F private room are insufficiently distinct")
    if failures:
        print("[CAFEDENSITY] FAIL " + "; ".join(failures))
        return 1
    print("[CAFEDENSITY] PASS existing-slot density and footprint are bounded")
    return 0


def self_test():
    # Synthetic negative control: one furniture pixel outside the footprint must fail closed.
    n = Image.new("RGB", (1280, 768), (20, 20, 20))
    b = n.copy()
    d = ImageDraw.Draw(n)
    x0, y0, _, _ = FOOTPRINT
    d.rectangle((x0 + 10, y0 + 10, x0 + 100, y0 + 100), fill=(220, 180, 80))
    inside, outside = assess(n, b)
    if inside <= 0 or outside != 0:
        print("[CAFEDENSITY] FAIL self-test positive control")
        return 1
    d.point((10, 10), fill=(250, 250, 250))
    _, outside = assess(n, b)
    if outside <= 0:
        print("[CAFEDENSITY] FAIL self-test did not detect escaped fixture")
        return 1
    print("[CAFEDENSITY] PASS self-test rejected intentional out-of-footprint fixture")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", nargs="?")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.out_dir:
        ap.error("out_dir is required unless --self-test")
    try:
        return check(a.out_dir)
    except ValueError as e:
        print("[CAFEDENSITY] FAIL " + str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
