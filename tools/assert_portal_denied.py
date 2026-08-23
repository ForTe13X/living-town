#!/usr/bin/env python3
"""Assert the P1-p real-tap denied presentation receipt."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assert_daynight import _png_rgb_rows


def main():
    if len(sys.argv) != 2:
        return 2
    root = sys.argv[1]
    with open(os.path.join(root, "rt_meta.json"), encoding="utf-8") as f:
        meta = json.load(f)
    before = _png_rgb_rows(os.path.join(root, "rt_town_before.png"))
    denied = _png_rgb_rows(os.path.join(root, "rt_denied.png"))
    fails = 0
    for ok, label in [
        (before[:3] == denied[:3] and before[0:2] == (1280, 768), "1280x768 same-size frames"),
        (meta.get("journey") == "denied" and meta.get("denied_portal") == "p_port_warehouse_door",
         "real warehouse portal denial arm identified"),
        (meta.get("player_before") == meta.get("player_after"), "player authoritative address unchanged"),
        (meta.get("probe_before") == meta.get("probe_after"), "Probe plane/camera unchanged"),
        (meta.get("cargo_state") == meta.get("cargo_after", {}).get("state")
         and meta.get("cargo_good") == meta.get("cargo_after", {}).get("good")
         and meta.get("cargo_qty") == meta.get("cargo_after", {}).get("qty"), "cargo presentation authority unchanged"),
        ("私人区域" in meta.get("denial_log_bbcode", "")
         and "未获通行许可" in meta.get("denial_log_bbcode", ""), "specific visible denial copy emitted"),
    ]:
        print("  %s %s" % ("PASS" if ok else "FAIL", label))
        if not ok:
            fails += 1
    w, h, bpp, rows0 = before
    rows1 = denied[3]
    changed = 0
    outside = 0
    bbox = [w, h, -1, -1]
    for y in range(h):
        for x in range(w):
            i = x * bpp
            if rows0[y][i:i + 3] != rows1[y][i:i + 3]:
                changed += 1
                bbox = [min(bbox[0], x), min(bbox[1], y), max(bbox[2], x), max(bbox[3], y)]
                if not (x < 590 and y >= 414):
                    outside += 1
    visual_ok = changed > 80 and outside == 0
    print("  %s denial feedback changed=%d bbox=%s outside_feedback=%d" %
          ("PASS" if visual_ok else "FAIL", changed, bbox, outside))
    fails += 0 if visual_ok else 1
    print("=== PORTAL DENIED PRESENTATION: %s ===" % ("PASS" if fails == 0 else "FAIL"))
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
