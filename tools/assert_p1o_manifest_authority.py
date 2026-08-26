#!/usr/bin/env python3
"""Player-presentation contract for authored CargoManifest authority (P1-o)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def load_meta(root: Path) -> dict:
    return json.loads((root / "rt_meta.json").read_text(encoding="utf-8"))


def changed(valid: Path, corrupt: Path, name: str) -> tuple[int, tuple[int, int, int, int] | None]:
    a = Image.open(valid / name).convert("RGB")
    b = Image.open(corrupt / name).convert("RGB")
    if a.size != b.size:
        raise ValueError(f"{name} size mismatch: {a.size} != {b.size}")
    diff = ImageChops.difference(a, b)
    bbox = diff.getbbox()
    if bbox is None:
        return 0, None
    r, g, blue = diff.split()
    changed_mask = ImageChops.lighter(ImageChops.lighter(r, g), blue)
    count = a.width * a.height - changed_mask.histogram()[0]
    return count, bbox


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: assert_p1o_manifest_authority.py <valid-space-shot> <corrupt-space-shot>")
        return 2
    valid, corrupt = Path(sys.argv[1]), Path(sys.argv[2])
    failures: list[str] = []
    vm, cm = load_meta(valid), load_meta(corrupt)
    shared = ("mode", "journey", "space", "tick", "player_journey", "player_entered", "player_returned")
    for key in shared:
        if vm.get(key) != cm.get(key):
            failures.append(f"fixture drift {key}: {vm.get(key)!r} != {cm.get(key)!r}")
    if (vm.get("cargo_state"), vm.get("cargo_good"), vm.get("cargo_qty"), vm.get("carrier_count")) != ("ready", "柴薪", 4, 1):
        failures.append("valid arm is not ready/柴薪x4/carrier1")
    if (cm.get("cargo_state"), cm.get("cargo_good"), cm.get("cargo_qty"), cm.get("carrier_count")) != ("invalid", "", 0, 0):
        failures.append("corrupt arm leaks trusted cargo fields or carrier")
    if cm.get("corrupt_manifest_field") != "price_per":
        failures.append("corrupt arm provenance is not price_per")
    for name in ("rt_town_before.png", "rt_interior.png"):
        count, bbox = changed(valid, corrupt, name)
        print(f"[P1O-VISUAL] {name} changed={count} bbox={bbox}")
        if count <= 0 or bbox is None:
            failures.append(f"{name} has no valid-vs-corrupt visual tooth")
    if failures:
        for failure in failures:
            print(f"[P1O-VISUAL] FAIL: {failure}")
        return 1
    print("[P1O-VISUAL] PASS: ready becomes invalid, trusted fields/carrier disappear, both player frames react")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
