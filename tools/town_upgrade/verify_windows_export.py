"""Bind a completed, actual Main Windows launch to its exact portable binaries.

This tool runs no engine and fabricates no screenshots. The coordinator first
launches the exported LivingTown.exe with --town-runtime-proof <absolute.json>,
waits for its normal shutdown, and supplies that process exit code here.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import town_runtime_assets as runtime


def verify(root: Path, export_dir: Path, runtime_proof: Path, exit_code: int, log: Path | None = None) -> dict:
    root = root.resolve()
    observed = runtime.read(runtime_proof)
    if observed.get("schema") != "living_town.normal_entry_runtime.v2":
        raise ValueError("Expected actual Main normal-entry runtime proof v2")
    if exit_code != 0 or observed.get("status") != "PASS" or observed.get("actual_gpu") is not True or observed.get("normal_product_entry") is not True or observed.get("entry_scene") != "res://scenes/Main.tscn":
        raise ValueError("The exported game did not complete a successful actual GPU Main launch")
    checks = []

    def checked(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details})
        if not passed:
            raise ValueError(name + ": " + str(details))

    hashes = {rel: runtime.sha(root / rel) for rel in runtime.runtime_records(root)}
    profile = runtime.read(root / runtime.PROFILE)
    for filename in profile["file_hashes"]:
        rel = "game/data/town3d/" + runtime.safe_relative(filename)
        hashes[rel] = runtime.sha(root / rel)
    for rel in profile.get("presentation_source_hashes", {}):
        hashes[runtime.safe_relative(rel)] = runtime.sha(root / rel)
    for rel in (runtime.PROFILE, runtime.PROJECTION, runtime.UPGRADE_LOGICAL,
                runtime.UPGRADE_CAPTURE, runtime.UPGRADE_REVIEW, "game/scripts/town_walkthrough.gd"):
        hashes[rel] = runtime.sha(root / rel)
    capture = runtime.read(root / runtime.UPGRADE_CAPTURE)
    for item in capture.get("captures", []):
        rel = "docs/town_bridge/captures/" + Path(item["file"]).name
        hashes[rel] = runtime.sha(root / rel)
    source = runtime.validate_upgrade_evidence(root, hashes)
    checked("fresh_full_source_gameplay_and_image_review", True, source)
    for field, value in (("profile_sha256", source["profile_sha256"]),
                         ("projection_sha256", source["projection_sha256"]),
                         ("stage_manifest_sha256", hashes[runtime.STAGE]),
                         ("characters_manifest_sha256", source["characters_manifest_sha256"]),
                         ("source_asset_set_sha256", source["source_asset_set_sha256"]),
                         ("source_blend_sha256", source["source_blend_sha256"])):
        checked("actual_export_matches_" + field, observed.get(field) == value, observed.get(field))
    model = observed.get("view", {}).get("model", {})
    actors = observed.get("view", {})
    checked("all151_buildings_loaded_in_actual_export", model.get("loaded") is True and model.get("building_count") == source["building_count"] == 151, model.get("building_count"))
    checked("all_visible_residents_are_refined_mesh_characters", actors.get("mesh_actor_count", 0) == actors.get("actor_count", -1) and actors.get("actor_count", 0) >= 12, actors.get("mesh_actor_count"))
    checked("actual_framebuffer_was_drawn", observed.get("engine_frames_drawn", 0) > 5, observed.get("engine_frames_drawn"))

    binaries = []
    for name, magic, field in (("LivingTown.exe", b"MZ", "executable_sha256"),
                               ("LivingTown.pck", b"GDPC", "pack_sha256")):
        path = export_dir / name
        if not path.is_file() or path.is_symlink():
            raise ValueError("Missing regular portable binary: " + str(path))
        with path.open("rb") as stream:
            checked("actual_binary_header_" + name, stream.read(len(magic)) == magic)
        digest = runtime.sha(path)
        checked("runtime_launched_exact_" + name, observed.get(field) == digest, observed.get(field))
        binaries.append({"file": name, "bytes": path.stat().st_size, "sha256": digest})
    checked("runtime_executable_is_the_portable_export", Path(observed.get("executable", "")).resolve() == (export_dir / "LivingTown.exe").resolve(), observed.get("executable"))

    screenshots = []
    for item in observed.get("screenshots", []):
        path = Path(item["file"])
        if not path.is_absolute() or not path.is_file():
            raise ValueError("Runtime screenshot is missing: " + str(path))
        checked("actual_native_framebuffer_hash", runtime.sha(path) == item.get("sha256"))
        with path.open("rb") as stream:
            header = stream.read(24)
        checked("actual_native_png_framebuffer", len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR")
        width, height = struct.unpack(">II", header[16:24])
        checked("native_framebuffer_dimensions", width >= 960 and height >= 600 and width == item.get("width") and height == item.get("height"), [width, height])
        screenshots.append(dict(item))
    checked("actual_native_screenshot_present", bool(screenshots))
    if log:
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        checked("no_runtime_script_or_fatal_errors", not any(marker in text for marker in ("SCRIPT ERROR:", "Parse Error:", "Fatal error", "TOWN NORMAL ENTRY PROOF FAIL")))
    return {
        "schema": "living_town.upgrade.windows_export.v1", "status": "PASS", "failure_count": 0,
        "created_utc": datetime.now(timezone.utc).isoformat(), "checks": checks,
        **{field: observed[field] for field in ("profile_sha256", "projection_sha256", "stage_manifest_sha256", "characters_manifest_sha256", "source_asset_set_sha256", "source_blend_sha256")},
        "binaries": binaries, "screenshots": screenshots,
        "boot": {"entry_scene": "Main", "normal_product_entry": True, "actual_gpu": True, "exit_code": exit_code,
                 "engine_frames_drawn": observed["engine_frames_drawn"], "engine_version": observed.get("engine_version")},
        "runtime_proof": {"file": str(runtime_proof.resolve()), "sha256": runtime.sha(runtime_proof)},
        "source_runtime_evidence": {"logical_report_sha256": hashes[runtime.UPGRADE_LOGICAL], "visual_report_sha256": hashes[runtime.UPGRADE_CAPTURE],
                                    "logical_checks": source["logical_check_count"], "visual_checks": source["visual_check_count"]},
        "source_verification": "Exact executable/PCK rendered normal Main; complete interactions are independently proven by the bound actual Main/LifeMode walkthrough.",
        "limitations": ["The normal-entry binary smoke run is separate from the full source gameplay interaction recording.",
                        "The supplied process exit code must come from the coordinator's supervised actual executable launch."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--export-dir", type=Path)
    parser.add_argument("--runtime-proof", type=Path, required=True)
    parser.add_argument("--exit-code", type=int, required=True)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output or root / "docs/town_bridge/windows_export_verification.json"
    report = verify(root, (args.export_dir or root / "build/town_bridge/windows").resolve(), args.runtime_proof, args.exit_code, args.log)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "checks": len(report["checks"]), "output": str(output)}))


if __name__ == "__main__":
    main()
