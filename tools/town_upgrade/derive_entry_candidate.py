"""Assemble a V14-bound entry derivative without changing either input.

No Blender import or subprocess. Actual entry/native audit receipts must already
exist. This file checks/copies evidence; it does not establish art or runtime
acceptance, recompute Blender geometry, or relax the original furniture baseline.
"""
from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
ASSEMBLER = "tools/town_upgrade/derive_entry_candidate.py"
ENTRY = "tools/town_upgrade/entry_details.py"
BASE_MANIFEST_SHA256 = "bfc4c1a15b1ab6722e7c02e35790809fb0cb1981a9ca3d8f5111614ef1494bbb"
EXCLUDED = {"upgrade_manifest.json", "whole_town_native_geometry.json", "portable_curve_meshing.json",
            "portable_mesh_preparation.json", "portable_export_receipt.json", "actual_portable_audit.json",
            "missing_tangent_diagnosis.json"}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path, data):
    path = Path(path)
    need(not path.exists(), "Refusing existing output: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False, allow_nan=False)
        stream.write("\n")
    temporary.replace(path)


def member(root, relative):
    relative = Path(relative)
    need(not relative.is_absolute() and ".." not in relative.parts, "Unsafe member path: " + str(relative))
    path = root / relative
    need(path.resolve().is_relative_to(root.resolve()), "Member escapes root: " + str(relative))
    return path


def snapshot(folder):
    folder = Path(folder)
    need(folder.is_dir(), "Missing input folder: " + str(folder))
    records = {}
    for path in sorted(folder.rglob("*")):
        need(not path.is_symlink() and not (hasattr(path, "is_junction") and path.is_junction()),
             "Linked input member: " + str(path))
        if path.is_file():
            records[path.relative_to(folder).as_posix()] = {"sha256": sha(path), "bytes": path.stat().st_size}
    payload = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return {"path": str(folder), "files": records, "sha256": hashlib.sha256(payload).hexdigest()}


def checked_copy(source, destination, expected):
    need(not destination.exists(), "Refusing existing copied member: " + str(destination))
    need(sha(source) == expected, "Source changed before copying: " + str(source))
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    need(sha(source) == sha(destination) == expected, "Copy/source mismatch: " + str(source))


def factory_contract(repo):
    values = {}
    for node in ast.parse((repo / ENTRY).read_text(encoding="utf-8-sig")).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in {"NATIVE_SHA256", "RECORD_HASHES", "SOURCE_HASHES"}:
                    values[target.id] = ast.literal_eval(node.value)
    need(set(values) == {"NATIVE_SHA256", "RECORD_HASHES", "SOURCE_HASHES"}, "Missing literal entry factory contract")
    return values


def preflight(folder, repo=ROOT):
    """Mirror the existing exporter's file checks; inspect no Blender state."""
    folder, repo = Path(folder).resolve(), Path(repo).resolve()
    need(not (folder / "entry_candidate_REJECTED.json").exists(), "Rejected derivative is not exportable")
    manifest = read(folder / "upgrade_manifest.json")
    audit = read(folder / "whole_town_native_geometry.json")
    native = member(folder, manifest["native"]["path"])
    native_sha = sha(native)
    need(manifest["native_geometry_status"] == audit["status"] == "PASS", "Native audit did not pass")
    need(native_sha == manifest["source_blend_sha256"] == manifest["native"]["sha256"] == audit["saved_native_sha256"],
         "Saved derivative native identity mismatch")
    need(sha(folder / "whole_town_native_geometry.json") == manifest["native_geometry_receipt_sha256"], "Audit binding changed")
    need(sha(folder / "whole_town_buildings.json") == audit["building_records_sha256"], "Building records changed")
    need(manifest["buildings"] == read(folder / "whole_town_buildings.json")["buildings"], "Inline building metadata changed")
    need(manifest["interiors"]["buildings"] == read(folder / "whole_town_interiors.json")["buildings"], "Inline interior metadata changed")
    need(not manifest["assets"] and not (folder / "chunks").exists() and "export_recipe" not in manifest,
         "Derivative inherited previous portable export state")
    for relative, binding in manifest["recipe_bindings"].items():
        need(sha(member(repo, relative)) == binding["sha256"], "Active recipe changed: " + relative)
    lineage = manifest["native_derivation"]
    for key in ("base_manifest", "base_folder_snapshot", "raw_pilot_audit", "entry_detail_changes", "entry_native_derivation", "assembly_receipt"):
        row = lineage[key]
        need(sha(member(folder, row["path"])) == row["sha256"], "Derivation receipt changed: " + key)
    historical = read(member(folder, lineage["base_manifest"]["path"]))
    base_inventory = read(member(folder, lineage["base_folder_snapshot"]["path"]))
    excluded = EXCLUDED | {historical["native"]["path"]}
    for relative, record in base_inventory["files"].items():
        if relative.split("/")[0] == "chunks" or relative in excluded:
            continue
        retained = member(folder, relative)
        need(retained.is_file() and retained.stat().st_size == record["bytes"] and sha(retained) == record["sha256"],
             "Retained original source member changed: " + relative)
    for relative, binding in historical["recipe_bindings"].items():
        need(manifest["recipe_bindings"].get(relative) == binding, "Historical recipe hash was substituted: " + relative)
        need(sha(member(folder, "provenance/base_generation/sources/" + relative)) == binding["sha256"],
             "Historical recipe snapshot changed: " + relative)
    need(lineage["art_review"] == lineage["runtime_review"] == "PENDING" and not lineage["whole_town_concept_acceptance"],
         "Assembly cannot grant art or runtime acceptance")
    return {"status": "PREFLIGHT_PASS_REQUIRES_PORTABLE_ART_AND_RUNTIME_REVIEW", "manifest_sha256": sha(folder / "upgrade_manifest.json"),
            "native_sha256": native_sha, "geometry_recomputed": False, "engine_executed": False}


def derive(base_manifest, pilot, output, repo=ROOT, *, expected_base_manifest_sha256=BASE_MANIFEST_SHA256):
    """The production CLI uses the explicit frozen V14 manifest pin.

    The keyword override exists for tiny file-contract fixtures; it does not
    replace the entry factory's native/source/record and component constraints.
    """
    repo, base_manifest, pilot, output = (Path(p).resolve() for p in (repo, base_manifest, pilot, output))
    base = base_manifest.parent
    need(base_manifest.name == "upgrade_manifest.json", "Expected the complete base upgrade manifest")
    need(not output.exists(), "Use a new derivative output directory")
    need(all(not output.is_relative_to(p) and not p.is_relative_to(output) for p in (base, pilot)), "Output overlaps immutable inputs")
    # Capture the complete inputs before reading/validating individual receipts,
    # so a change during validation cannot become the new accepted baseline.
    base_snapshot, pilot_snapshot = snapshot(base), snapshot(pilot)
    need(sha(base_manifest) == expected_base_manifest_sha256, "Frozen V14 manifest changed")
    original = read(base_manifest)
    for row in original.get("assets", []):
        relative = Path(row["path"]).as_posix()
        member(base, relative)
        need(base_snapshot["files"].get(relative, {}).get("sha256") == row["sha256"], "Historical export bytes differ from base manifest: " + relative)
    contract = factory_contract(repo)
    base_native = member(base, original["native"]["path"])
    need(sha(base_native) == original["source_blend_sha256"] == original["native"]["sha256"] == contract["NATIVE_SHA256"], "Entry base native differs")
    need(original["schema"] == "living_town.whole_town_upgrade.v1", "Unexpected base schema")
    source_hashes = {**{k: v["sha256"] for k, v in original["recipe_bindings"].items()}, **contract["SOURCE_HASHES"]}
    for relative, value in original["recipe_bindings"].items():
        need(source_hashes[relative] == value["sha256"], "Factory conflicts with original recipe: " + relative)
    source_hashes.update({ENTRY: sha(repo / ENTRY), ASSEMBLER: sha(repo / ASSEMBLER)})
    for relative, expected in source_hashes.items():
        need(sha(member(repo, relative)) == expected, "Source recipe changed: " + relative)
    for relative, expected in contract["RECORD_HASHES"].items():
        need(sha(member(base, relative)) == expected, "Entry source records differ: " + relative)
    furniture_count = len(read(base / "source_furniture_geometry.json")["objects"])
    need(furniture_count == 6739, "Original protected interior furniture count differs")
    old_audit = read(base / "whole_town_native_geometry.json")
    need(sha(base / "whole_town_native_geometry.json") == original["native_geometry_receipt_sha256"], "Original audit changed")
    need(old_audit["status"] == "PASS" and old_audit["saved_native_sha256"] == contract["NATIVE_SHA256"], "Original saved-native audit differs")
    need(sha(base / "whole_town_buildings.json") == old_audit["building_records_sha256"], "Original building records changed")
    need(original["buildings"] == read(base / "whole_town_buildings.json")["buildings"], "Base inline buildings differ")
    need(original["interiors"]["buildings"] == read(base / "whole_town_interiors.json")["buildings"], "Base inline interiors differ")
    changes = read(pilot / "entry_detail_changes.json")
    derivation = read(pilot / "entry_native_derivation.json")
    raw_audit = read(pilot / "whole_town_native_geometry_audit.json")
    need(changes["schema"] == "living_town.source_bound_entry_details.v1" and
         changes["status"] == "APPLIED_SCOPED_GEOMETRY_VERIFIED_REQUIRES_ART_AND_RUNTIME_REVIEW", "Entry receipt is not a successful scoped application")
    need(changes["source_native"]["sha256"] == derivation["source"]["sha256"] == contract["NATIVE_SHA256"], "Derivative source-native binding differs")
    need(Path(changes["source_native"]["path"]).resolve() == base_native.resolve(), "Entry source path differs from complete base")
    need(changes["tool_sha256"] == source_hashes[ENTRY], "Entry factory changed after actual pilot")
    need(changes["record_bindings"] == contract["RECORD_HASHES"], "Entry record contract differs")
    for relative, expected in contract["SOURCE_HASHES"].items():
        need(changes["source_bindings"][relative]["sha256"] == expected, "Pilot factory source differs: " + relative)
    preserve = changes["preservation_contract"]
    need(preserve["original_target_fingerprints_unchanged"] is False and preserve["protected_interior_furniture_count"] == 6739,
         "Target revisions or original furniture scope misrepresented")
    need(preserve["verified_source_component_count"] == 195 and preserve["changed_component_count"] == 195 and len(changes["components"]) == 195,
         "Authorized exterior component budget differs")
    for row in changes["components"]:
        need(str(row["source_object"]).startswith(("Civic_Square_and_Summer_Life_", "Reserve_Trailside_Rest_and_Wayfinding_")),
             "Entry component is outside authorized exterior assemblies")
        for key in ("original_geometry_uv_sha256", "new_geometry_uv_sha256", "new_expected_world_points_sha256"):
            value = row[key]
            need(isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value), "Missing target fingerprint: " + key)
        need(row["original_geometry_uv_sha256"] != row["new_geometry_uv_sha256"], "Changed target retained its original fingerprint")
    need(changes["text"]["object"] == "Reserve_Bathhouse_SignText", "Unexpected font correction target")
    for key in ("untargeted_mixed_geometry_uv", "all_non_target_meshes", "all_materials", "all_non_target_object_transforms_and_ids", "original_protected_interior_baseline"):
        need(preserve[key] == "PASS", "Entry preservation failed: " + key)
    need(not changes["whole_town_concept_acceptance"], "Entry receipt cannot approve the whole town")
    need(derivation["schema"] == "living_town.entry_native_derivation.v1" and
         derivation["status"] == "NATIVE_CANDIDATE_SAVED_REQUIRES_ART_AND_RUNTIME_REVIEW", "Saved derivative is not a candidate")
    need(derivation["entry_receipt_sha256"] == sha(pilot / "entry_detail_changes.json") and
         derivation["native_audit_sha256"] == sha(pilot / "whole_town_native_geometry_audit.json"), "Actual pilot receipt hashes differ")
    need(raw_audit["status"] == raw_audit["source_furniture_geometry_status"] == "PASS" and not raw_audit["failures"], "Actual derivative audit failed")
    need(raw_audit["tool_sha256"] == source_hashes["tools/town_upgrade/building_native_audit.py"], "Derivative audit source changed")
    need(Path(raw_audit["loaded_native_path"]).resolve() == base_native, "Raw audit lost its actual loaded-source identity")
    need(raw_audit["counts"] == old_audit["counts"], "Derivative changed audited architectural inventory")
    need(derivation["native_geometry_audit"] == derivation["protected_interior_furniture"] == "PASS", "Pilot audit summary differs")
    need(not derivation["rendered_review"] and not derivation["runtime_review"] and not derivation["portable_export"], "Unexpected pilot review/export claims")
    candidate = Path(derivation["candidate"]["path"]).resolve()
    need(candidate.is_relative_to(pilot) and candidate.is_file(), "Saved candidate is outside the actual pilot")
    need(sha(candidate) == derivation["candidate"]["sha256"], "Saved pilot candidate changed")
    need(derivation["candidate"]["sha256"] != contract["NATIVE_SHA256"], "Entry derivative still names the unchanged base native")
    reserved = {"entry_detail_changes.json", "entry_native_derivation.json", "whole_town_native_geometry_audit.json",
                "entry_candidate_assembly.json", "entry_candidate_preflight.json", "entry_candidate_REJECTED.json"}
    need(not any(k in reserved or k.startswith("provenance/") for k in base_snapshot["files"]),
         "Base contains reserved derivative evidence names")
    created = False
    try:
        output.mkdir(parents=True, exist_ok=False); created = True
        excluded = EXCLUDED | {original["native"]["path"]}
        for relative, record in base_snapshot["files"].items():
            if relative.split("/")[0] == "chunks" or relative in excluded:
                continue
            need(not relative.startswith("provenance/"), "Reserved derivative provenance already exists in base")
            checked_copy(member(base, relative), member(output, relative), record["sha256"])
        provenance = "provenance/base_generation/"
        checked_copy(base_manifest, member(output, provenance + "upgrade_manifest.json"), expected_base_manifest_sha256)
        write(member(output, provenance + "complete_folder_snapshot.json"), base_snapshot)
        for relative, expected in source_hashes.items():
            prefix = provenance + "sources/" if relative in original["recipe_bindings"] else "provenance/derivation_sources/"
            checked_copy(member(repo, relative), member(output, prefix + relative), expected)
        for name in ("entry_detail_changes.json", "entry_native_derivation.json", "whole_town_native_geometry_audit.json"):
            checked_copy(pilot / name, output / name, sha(pilot / name))
        checked_copy(candidate, output / "refined_whole_town.blend", derivation["candidate"]["sha256"])
        enriched = copy.deepcopy(raw_audit)
        enriched.update(saved_native_sha256=sha(output / "refined_whole_town.blend"), saved_native_path=str(output / "refined_whole_town.blend"),
                        building_records_sha256=sha(output / "whole_town_buildings.json"),
                        raw_pilot_audit_sha256=sha(output / "whole_town_native_geometry_audit.json"),
                        entry_native_derivation_sha256=sha(output / "entry_native_derivation.json"))
        write(output / "whole_town_native_geometry.json", enriched)
        assembly = {"schema": "living_town.entry_candidate_assembly.v1", "status": "ASSEMBLED_REQUIRES_PREFLIGHT_AND_REVIEW",
                    "base_folder_snapshot_sha256": base_snapshot["sha256"], "pilot_folder_snapshot": pilot_snapshot,
                    "excluded_historical_export_members": sorted(k for k in base_snapshot["files"] if k.split('/')[0] == 'chunks' or k in excluded),
                    "geometry_recomputed": False, "engine_executed": False, "source_furniture_baseline_rewritten": False}
        write(output / "entry_candidate_assembly.json", assembly)
        def bound(name):
            return {"path": name, "sha256": sha(member(output, name))}
        final = copy.deepcopy(original)
        final.update(status="DERIVED_REQUIRES_VISUAL_AND_GAMEPLAY_REVIEW", source_blend_sha256=sha(output / "refined_whole_town.blend"),
                     native={"path": "refined_whole_town.blend", "sha256": sha(output / "refined_whole_town.blend"), "bytes": (output / "refined_whole_town.blend").stat().st_size},
                     base_generation_input=copy.deepcopy(original["input"]), input=copy.deepcopy(changes["source_native"]),
                     native_geometry_status="PASS", native_geometry_receipt_sha256=sha(output / "whole_town_native_geometry.json"), assets=[])
        final.pop("export_recipe", None)
        final["recipe_bindings"] = copy.deepcopy(original["recipe_bindings"])
        for relative, expected in source_hashes.items():
            final["recipe_bindings"].setdefault(relative, {"sha256": expected})
        final["native_derivation"] = {"schema": "living_town.source_bound_native_derivation.v1",
            "base_manifest": bound(provenance + "upgrade_manifest.json"), "base_folder_snapshot": bound(provenance + "complete_folder_snapshot.json"),
            "raw_pilot_audit": bound("whole_town_native_geometry_audit.json"), "entry_detail_changes": bound("entry_detail_changes.json"),
            "entry_native_derivation": bound("entry_native_derivation.json"), "assembly_receipt": bound("entry_candidate_assembly.json"),
            "original_target_fingerprints_unchanged": False, "changed_exterior_components": 195, "protected_original_interior_objects": 6739,
            "base_engine_metadata_inherited": True, "derivative_engine_version": "NOT_RECORDED_BY_CURRENT_PILOT_RECEIPT",
            "art_review": "PENDING", "runtime_review": "PENDING", "whole_town_concept_acceptance": False}
        write(output / "upgrade_manifest.json", final)
        report = preflight(output, repo)
        need(snapshot(base) == base_snapshot and snapshot(pilot) == pilot_snapshot, "Immutable input folder changed during assembly")
        for relative, expected in source_hashes.items():
            need(sha(member(repo, relative)) == expected, "Recipe changed during assembly: " + relative)
        write(output / "entry_candidate_preflight.json", report)
        return report
    except BaseException as exc:
        if created:
            # Existing exporter gates native_geometry_status. A partially written
            # manifest must fail that gate even if a caller ignores the label.
            manifest_path = output / "upgrade_manifest.json"
            if manifest_path.is_file():
                rejected = read(manifest_path)
                rejected.update(status="REJECTED_ASSEMBLY_DO_NOT_EXPORT", native_geometry_status="REJECTED_ASSEMBLY", assembly_rejection=str(exc))
                write(output / "upgrade_manifest_REJECTED.json", rejected)
                (output / "upgrade_manifest_REJECTED.json").replace(manifest_path)
            write(output / "entry_candidate_REJECTED.json", {"status": "REJECTED_NOT_FOR_EXPORT", "error": str(exc), "engine_executed": False})
        raise


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--base-manifest", type=Path, required=True)
    p.add_argument("--pilot", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--repo", type=Path, default=ROOT)
    args = p.parse_args(argv)
    try:
        print(json.dumps(derive(args.base_manifest, args.pilot, args.output, args.repo)))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(json.dumps({"status": "REJECTED_NOT_FOR_EXPORT", "error": str(error), "engine_executed": False}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
