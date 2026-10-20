"""Coordinate a real town expansion in an exclusive, recoverable output folder.

Planning uses ordinary Python. Blender runs only after the plan passes its
topology/site audit. No canonical plan, source blend or existing output is edited.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
DEFAULT_BASELINE = REPO / "art/living_town"


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")


def validate_output(output, baseline_root):
    output, baseline_root = Path(output).resolve(), Path(baseline_root).resolve(strict=True)
    # Refuse source trees even when the requested final directory does not exist.
    protected = [baseline_root, REPO / "art", REPO / "tools", REPO / "game", REPO / ".git"]
    if any(output == p or output.is_relative_to(p) or p.is_relative_to(output) for p in protected):
        raise ValueError("Output overlaps canonical source: " + str(output))
    if output.exists():
        raise FileExistsError("Use a fresh output directory: " + str(output))
    return output


def generate(*, output, baseline_root=DEFAULT_BASELINE, seed=20261020,
             blender=None, pbr_library=None, plan_only=False, quick=False,
             timeout_seconds=7200, infinigen_asset=None):
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError("Seed must be an unsigned 32-bit integer")
    if not plan_only and (blender is None or not Path(blender).is_file()):
        raise ValueError("Supply an existing Blender executable for scene generation")
    if not plan_only and (pbr_library is None or not Path(pbr_library).is_file()):
        raise ValueError("Supply an existing source-bound PBR library manifest for scene generation")
    if timeout_seconds <= 0:
        raise ValueError("Timeout must be positive")
    output = validate_output(output, baseline_root)
    baseline_root = Path(baseline_root).resolve(strict=True)
    baseline = baseline_root / "living_town_complete.blend"
    if not baseline.is_file():
        raise FileNotFoundError(baseline)
    native_before = sha(baseline)
    from territory import generate as plan_territory
    from preview_territory import render_map
    plan = plan_territory(baseline_root, seed)
    audit = plan["validation"]
    if audit.get("status") != "PASS":
        raise ValueError("Territory audit did not pass: " + json.dumps(audit))
    output.mkdir(parents=True, exist_ok=False)
    plan_path = output / "territory_plan.json"
    write_json(plan_path, plan)
    render_map(plan, baseline_root, output / "territory_map.png")
    receipt = {
        "schema": "living_town.generation_run.v1", "status": "PLANNED",
        "seed": seed, "baseline_sha256": native_before, "plan_sha256": sha(plan_path),
        "source_sha256": {p.name: sha(p) for p in Path(__file__).parent.glob("*.py")},
        "runtime": {"device": "CPU", "threads": 6, "heavy_processes": 1},
        "output": str(output), "blender_executed": False,
    }
    geometry_helpers=[REPO/"tools/asset_refinement"/(name+".py") for name in
                      ("hero_furniture","hero_foliage","hero_pbr")]
    geometry_helpers.extend(baseline_root/"tools"/name for name in
                            ("interior_design.py","reserve_plan.py","terrain_profile.py"))
    receipt["geometry_helper_sha256"]={str(p.relative_to(REPO)).replace("\\","/"):sha(p) for p in geometry_helpers}
    write_json(output / "generation_run.json", receipt)
    if plan_only:
        return receipt
    command = [str(Path(blender).resolve()), "--background", "--threads", "6", "--python-exit-code", "1", "--python",
               str(Path(__file__).with_name("build_expansion_scene.py")), "--",
               "--baseline", str(baseline), "--plan", str(plan_path), "--output", str(output / "scene")]
    if pbr_library:
        command.extend(["--pbr-library", str(Path(pbr_library).resolve(strict=True))])
    if quick:
        command.append("--quick")
    if infinigen_asset:
        command.extend(["--infinigen-asset", str(Path(infinigen_asset).resolve(strict=True))])
    receipt.update(status="GENERATING", blender_executed=True, command=command)
    write_json(output / "generation_run.json", receipt)
    started = time.monotonic()
    environment = dict(os.environ, OMP_NUM_THREADS="6", OPENBLAS_NUM_THREADS="6")
    try:
        with (output / "blender.log").open("w", encoding="utf-8") as log:
            process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                     env=environment, timeout=timeout_seconds, check=False)
        receipt["exit_code"] = process.returncode
        receipt["status"] = "GENERATED_REQUIRES_REVIEW" if process.returncode == 0 else "FAILED"
        if process.returncode == 0 and not (output / "scene/expansion_manifest.json").is_file():
            receipt["status"] = "FAILED_MISSING_MANIFEST"
    except subprocess.TimeoutExpired:
        receipt.update(status="TIMEOUT", exit_code=None)
    finally:
        receipt["elapsed_seconds"] = round(time.monotonic() - started, 3)
        receipt["baseline_after_sha256"] = sha(baseline)
        receipt["baseline_unchanged"] = receipt["baseline_after_sha256"] == native_before
        if not receipt["baseline_unchanged"]:
            receipt["status"] = "FAILED_SOURCE_CHANGED"
        write_json(output / "generation_run.json", receipt)
    if receipt["status"] != "GENERATED_REQUIRES_REVIEW":
        raise RuntimeError("Generation failed; inspect " + str(output / "blender.log"))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline-root", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--seed", type=int, default=20261020)
    parser.add_argument("--blender", type=Path)
    parser.add_argument("--pbr-library", type=Path)
    parser.add_argument("--infinigen-asset", type=Path)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    args = parser.parse_args()
    result = generate(**vars(args))
    print(json.dumps({"status": result["status"], "output": result["output"]}))


if __name__ == "__main__":
    main()
