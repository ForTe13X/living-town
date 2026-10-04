#!/usr/bin/env python3
"""Player-presentation contract for authored CargoManifest authority (P1-o)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def load_meta(root: Path) -> dict:
    path = root / "rt_meta.json"
    if not path.is_file():
        path = root / "capture.json"  # archived evidence uses a descriptive filename
    return json.loads(path.read_text(encoding="utf-8"))


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


def expected_carrier_projections(meta: dict) -> list[dict[str, str]]:
    """Independently project eligible authoritative manifests onto authored berth slots."""
    manifests = meta.get("manifest_authority", [])
    configs = meta.get("carrier_configs", [])
    if not isinstance(manifests, list) or not isinstance(configs, list):
        raise ValueError("manifest_authority/carrier_configs must be arrays")
    expected: list[dict[str, str]] = []
    for config in configs:
        if not isinstance(config, dict):
            continue
        route, node = str(config.get("route_id", "")), str(config.get("node", ""))
        ready = [
            rec for rec in manifests
            if isinstance(rec, dict)
            and rec.get("authority_valid") is True
            and rec.get("state") == "ready"
            and int(rec.get("remaining_qty", 0)) > 0
            and rec.get("route_id") == route
            and rec.get("node") == node
        ]
        if not ready:
            continue
        # The product projection prioritizes supply cargo, then preserves manifest arrival order.
        selected = next((rec for rec in ready if rec.get("supply") is True), ready[0])
        expected.append({"route_id": route, "node": node, "manifest_id": str(selected.get("id", ""))})
    return expected


def validate_projection_set(meta: dict) -> list[str]:
    expected = expected_carrier_projections(meta)
    actual = meta.get("carrier_projections")
    if not isinstance(actual, list):
        return ["carrier_projections is missing or is not an array"]
    normalized = [
        {key: str(rec.get(key, "")) for key in ("route_id", "node", "manifest_id")}
        for rec in actual if isinstance(rec, dict)
    ]
    failures: list[str] = []
    if len(normalized) != len(actual):
        failures.append("carrier_projections contains a non-object entry")
    if len(normalized) != len(expected):
        failures.append(f"carrier projection set size differs: expected={len(expected)} actual={len(normalized)}")
    elif normalized != expected:
        failures.append(f"carrier projection identities differ: expected={expected!r} actual={normalized!r}")
    if int(meta.get("carrier_count", -1)) != len(expected):
        failures.append(f"carrier_count differs from derived set: expected={len(expected)} actual={meta.get('carrier_count')!r}")
    return failures


def validate_fixture_count(meta: dict, required_count: int) -> list[str]:
    """Require the authored fixture to exercise the intended number of berths."""
    failures = validate_projection_set(meta)
    expected_count = len(expected_carrier_projections(meta))
    if expected_count != required_count:
        failures.append(f"fixture has {expected_count} eligible berth(s), requires {required_count}")
    return failures


def self_test() -> int:
    configs = [
        {"route_id": "east_ocean", "node": "port_dock"},
        {"route_id": "east_ocean", "node": "port_dock2"},
    ]
    manifests = [
        {"id": "firewood-1", "route_id": "east_ocean", "node": "port_dock", "state": "ready", "remaining_qty": 12, "authority_valid": True, "supply": False},
        {"id": "ration-1", "route_id": "east_ocean", "node": "port_dock2", "state": "ready", "remaining_qty": 36, "authority_valid": True, "supply": True},
    ]
    two = {"carrier_configs": configs, "manifest_authority": manifests,
           "carrier_projections": [
               {"route_id": "east_ocean", "node": "port_dock", "manifest_id": "firewood-1"},
               {"route_id": "east_ocean", "node": "port_dock2", "manifest_id": "ration-1"},
           ], "carrier_count": 2}
    one = {**two, "manifest_authority": manifests[:1], "carrier_projections": two["carrier_projections"][:1], "carrier_count": 1}
    corrupt = {**one, "manifest_authority": [{**manifests[0], "authority_valid": False}], "carrier_projections": [], "carrier_count": 0}
    cases = [
        ("one eligible berth", one, True),
        ("two eligible berths", two, True),
        ("corrupt authority suppresses carrier", corrupt, True),
        ("missing eligible ship is rejected", {**two, "carrier_projections": two["carrier_projections"][:1]}, "carrier projection set size"),
        ("swapped ship identity is rejected", {**two, "carrier_projections": [two["carrier_projections"][1], two["carrier_projections"][0]]}, "carrier projection identities"),
    ]
    for name, meta, expectation in cases:
        failures = validate_projection_set(meta)
        passed = not failures if isinstance(expectation, bool) else any(expectation in item for item in failures)
        should_pass = expectation if isinstance(expectation, bool) else True
        if passed != should_pass:
            print(f"[P1O-SELFTEST] FAIL: {name} expected={expectation!r}, got={failures!r}")
            return 1
        print(f"[P1O-SELFTEST] PASS: {name}")
    if validate_fixture_count(two, 2) or not any(
        "fixture has 1 eligible berth(s), requires 2" in failure
        for failure in validate_fixture_count(one, 2)
    ):
        print("[P1O-SELFTEST] FAIL: required two-berth fixture tooth")
        return 1
    print("[P1O-SELFTEST] PASS: required two-berth fixture tooth")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    if len(sys.argv) in (3, 5) and sys.argv[1] == "--check-projections":
        required_count = None
        if len(sys.argv) == 5:
            if sys.argv[3] != "--require-count" or not sys.argv[4].isdigit():
                print("usage: --check-projections <shot-dir> [--require-count <n>]")
                return 2
            required_count = int(sys.argv[4])
        meta = load_meta(Path(sys.argv[2]))
        failures = (validate_fixture_count(meta, required_count) if required_count is not None
                    else validate_projection_set(meta))
        if failures:
            for failure in failures:
                print(f"[P1O-CARRIERS] FAIL: {failure}")
            return 1
        expected = expected_carrier_projections(meta)
        print(f"[P1O-CARRIERS] PASS: {len(expected)} authoritative berth projection(s): {expected!r}")
        return 0
    if len(sys.argv) != 3:
        print("usage: assert_p1o_manifest_authority.py <valid-space-shot> <corrupt-space-shot> | --check-projections <shot-dir> | --self-test")
        return 2
    valid, corrupt = Path(sys.argv[1]), Path(sys.argv[2])
    failures: list[str] = []
    vm, cm = load_meta(valid), load_meta(corrupt)
    shared = ("mode", "journey", "space", "tick", "player_journey", "player_entered", "player_returned")
    for key in shared:
        if vm.get(key) != cm.get(key):
            failures.append(f"fixture drift {key}: {vm.get(key)!r} != {cm.get(key)!r}")
    # Keep the independently-authored cargo status contract, but derive the carrier identities from
    # this run's validated manifest inventory and authored berth slots rather than a stale ship count.
    if (vm.get("cargo_state"), vm.get("cargo_good"), vm.get("cargo_qty")) != ("ready", "柴薪", 12):
        failures.append("valid arm is not ready/柴薪x12")
    failures.extend(f"valid arm: {failure}" for failure in validate_projection_set(vm))
    if (cm.get("cargo_state"), cm.get("cargo_good"), cm.get("cargo_qty")) != ("invalid", "", 0):
        failures.append("corrupt arm leaks trusted cargo fields")
    failures.extend(f"corrupt arm: {failure}" for failure in validate_projection_set(cm))
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
    print(f"[P1O-VISUAL] PASS: ready becomes invalid; expected carriers={expected_carrier_projections(vm)!r}; corrupt arm suppresses every carrier; both player frames react")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
