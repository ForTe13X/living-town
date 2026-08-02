from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

from PIL import Image


FIXTURE_SHA256 = "90ddd379d67b3e251ac0113a548706c95f840ae6c5aea0ee50a587a2ab3e8198"
LAB_COMMIT = "1a195e06f1dd6b6aef2668906d6a816b8799e67b"
LAB_PATH = "artifacts/integration/s16_compositor_projection.json"
BANNER = "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE"
FIXTURE_RELATIVE = "game/narrative_lab/s16/fixtures/s16_compositor_projection.json"
SCREENSHOTS = {
    "compositor_1024x768.png": (1024, 768),
    "compositor_1280x768.png": (1280, 768),
    "compositor_2688x1216.png": (2688, 1216),
}
SOURCE_PATHS = (
    FIXTURE_RELATIVE,
    "game/narrative_lab/s16/.gitattributes",
    "game/narrative_lab/s16/fixtures/source_receipt.json",
    "game/narrative_lab/s16/scripts/S16Compositor.gd",
    "game/narrative_lab/s16/tests/s16_compositor_test.gd",
    "game/narrative_lab/s16/scenes/s16_compositor_test.tscn",
    "analysis/narrative_visual/s16/render_s16_review.ps1",
    "analysis/narrative_visual/s16/.gitattributes",
    "analysis/narrative_visual/s16/verify_s16_artifacts.py",
    "analysis/narrative_visual/s16/test_s16_compositor.py",
)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def banner_pixels(image: Image.Image) -> int:
    rgb = image.convert("RGB")
    maximum = 0
    for y in range(46, min(56, rgb.height)):
        count = sum(
            1
            for x in range(rgb.width)
            if (lambda p: p[0] >= 180 and 80 <= p[1] <= 180 and p[2] <= 130)(
                rgb.getpixel((x, y))
            )
        )
        maximum = max(maximum, count)
    return maximum


def fixture_bytes_valid(value: bytes) -> bool:
    return sha256_bytes(value) == FIXTURE_SHA256


def build_report(root: Path, lab_root: Path) -> dict[str, Any]:
    root = root.resolve()
    lab_root = lab_root.resolve()
    media = root / "analysis" / "narrative_visual" / "s16"
    issues: list[dict[str, str]] = []

    def issue(code: str, path: str, detail: str) -> None:
        issues.append({"code": code, "path": path, "detail": detail})

    fixture = root / FIXTURE_RELATIVE
    fixture_bytes = fixture.read_bytes() if fixture.is_file() else b""
    if not fixture_bytes_valid(fixture_bytes):
        issue("FIXTURE_HASH_MISMATCH", FIXTURE_RELATIVE, sha256_bytes(fixture_bytes))
    try:
        lab_bytes = subprocess.check_output(
            ["git", "show", f"{LAB_COMMIT}:{LAB_PATH}"], cwd=lab_root
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        lab_bytes = b""
        issue("LAB_SOURCE_UNREADABLE", LAB_PATH, type(exc).__name__)
    if lab_bytes != fixture_bytes:
        issue("FIXTURE_SOURCE_BYTES_MISMATCH", FIXTURE_RELATIVE, LAB_PATH)

    compositor_path = root / "game/narrative_lab/s16/scripts/S16Compositor.gd"
    compositor_source = (
        compositor_path.read_text(encoding="utf-8") if compositor_path.is_file() else ""
    )
    if BANNER not in compositor_source:
        issue("BANNER_SOURCE_MISSING", str(compositor_path.relative_to(root)), BANNER)
    if compositor_source.count("func _dispatch(") != 1:
        issue("DISPATCHER_COUNT_INVALID", str(compositor_path.relative_to(root)), "expected one")
    if "InputEventMouseButton" in compositor_source:
        issue("RAW_MOUSE_HANDLER_FORBIDDEN", str(compositor_path.relative_to(root)), "found")
    for forbidden in ("FileAccess.WRITE", "store_string(", "store_var("):
        if forbidden in compositor_source:
            issue("COMPOSITOR_WRITEBACK_API_FORBIDDEN", str(compositor_path.relative_to(root)), forbidden)

    audit_path = media / "audit.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8")) if audit_path.is_file() else {}
    expected_audit = {
        "result": "PASS_WITH_BLOCKERS",
        "production_gate": False,
        "banner": BANNER,
        "mode": "READ_ONLY_COMMITTED_TRACE",
        "simulation": "NOT_SIM",
    }
    for key, expected in expected_audit.items():
        if audit.get(key) != expected:
            issue("AUDIT_FIELD_INVALID", f"audit.{key}", repr(audit.get(key)))
    metrics = audit.get("metrics", {})
    for key, expected in {
        "frames": 13,
        "snapshot_fields": 10,
        "dispatcher_actions": 5,
        "responsive_layouts": 3,
    }.items():
        if metrics.get(key) != expected:
            issue("AUDIT_METRIC_INVALID", f"audit.metrics.{key}", repr(metrics.get(key)))
    checks = audit.get("checks", {})
    for key in (
        "fixture_hash_bound",
        "handoff_half_mutation_rejected",
        "replay_fingerprints_stable",
        "source_trace_unchanged",
        "fixture_bytes_unchanged",
        "component_boundary_exact_ten_fields",
        "transition_sidecar_whitelisted",
        "button_uses_dispatcher",
        "keyboard_uses_dispatcher",
        "screen_touch_single_dispatch",
        "responsive_targets_at_least_44px",
    ):
        if checks.get(key) is not True:
            issue("AUDIT_CHECK_FAILED", f"audit.checks.{key}", repr(checks.get(key)))
    if len(audit.get("blockers", [])) != 3:
        issue("AUDIT_BLOCKER_COUNT_INVALID", "audit.blockers", str(len(audit.get("blockers", []))))

    media_receipts: dict[str, Any] = {}
    for name, expected_size in SCREENSHOTS.items():
        path = media / name
        if not path.is_file():
            issue("SCREENSHOT_MISSING", name, "missing")
            continue
        with Image.open(path) as image:
            size = image.size
            accent_pixels = banner_pixels(image)
        if size != expected_size:
            issue("SCREENSHOT_SIZE_INVALID", name, repr(size))
        if accent_pixels < int(expected_size[0] * 0.90):
            issue("SCREENSHOT_BANNER_MISSING", name, str(accent_pixels))
        observed_sha = sha256(path)
        audit_sha = audit.get("screenshots", {}).get(name, {}).get("sha256")
        if observed_sha != audit_sha:
            issue("SCREENSHOT_AUDIT_HASH_MISMATCH", name, str(audit_sha))
        media_receipts[name] = {
            "size": list(size),
            "sha256": observed_sha,
            "banner_accent_pixels": accent_pixels,
            "media_kind": "component_layout_review_not_sim_not_gameplay",
        }

    source_hashes: dict[str, str] = {}
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            issue("SOURCE_FILE_MISSING", relative, "missing")
        else:
            source_hashes[relative] = sha256(path)

    issues.sort(key=lambda item: (item["code"], item["path"], item["detail"]))
    return {
        "schema": "living-town-s16-main-media-gate/v1",
        "verdict": "PASS" if not issues else "FAIL",
        "production_gate": False,
        "banner": BANNER,
        "fixture_source_receipt": {
            "lab_commit": LAB_COMMIT,
            "lab_path": LAB_PATH,
            "sha256": FIXTURE_SHA256,
            "exact_bytes_verified": bool(fixture_bytes) and fixture_bytes == lab_bytes,
        },
        "media": media_receipts,
        "source_sha256": source_hashes,
        "mutation_cases": [
            {"id": "fixture_byte_tamper", "detected": not fixture_bytes_valid(fixture_bytes + b"x")},
            {"id": "handoff_half_commit", "detected": checks.get("handoff_half_mutation_rejected") is True},
            {"id": "banner_erasure", "detected": banner_pixels(Image.new("RGB", (1024, 768), "black")) == 0},
        ],
        "issues": issues,
    }


def render_report(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lab-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = build_report(args.root, args.lab_root)
    rendered = render_report(report)
    if args.output:
        output = args.output if args.output.is_absolute() else args.root / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(rendered)
    print(rendered.decode(), end="")
    return 0 if report["verdict"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
