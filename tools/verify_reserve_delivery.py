"""Verify the curated reserve source/asset delivery without running an engine.

Workspace preflight: --repo <checkout> [--assets <export-directory>].
Portable proof: --delivery <extracted-folder> OR --archive <delivery.zip>.
All paths, receipts, final images and embedded GLB dependencies are checked;
this does not substitute for the separately recorded actual visual review.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tempfile
import unittest
import zipfile


SOURCE = "art/living_town/"
ASSETS = "game_assets_reserve/"
CONSUMER = SOURCE + "integration/reserve_godot/"
EVIDENCE = SOURCE + "evidence/"
RELEASE_TAG = "town-reserve-2026-10-12"
MAX_GAME_TRIANGLES = 5_000_000
FILE_MANIFEST = "FILE_MANIFEST.json"
SCHEMA = "living_town.reserve_delivery_verification.v1"
BINDINGS = {
    "masterplan_sha256": "masterplan.json",
    "terrain_plan_sha256": "terrain_plan.json",
    "terrain_profile_sha256": "tools/terrain_profile.py",
    "interior_plan_sha256": "interior_plan.json",
    "interior_module_sha256": "tools/interior_design.py",
    "landscape_plan_sha256": "landscape_plan.json",
    "landscape_details_sha256": "tools/landscape_details.py",
    "reserve_plan_sha256": "reserve_plan.json",
    "reserve_plan_module_sha256": "tools/reserve_plan.py",
    "reserve_environment_module_sha256": "tools/reserve_environment.py",
    "reserve_amenities_module_sha256": "tools/reserve_amenities.py",
}
FREEZE_FILES = (
    "living_town_complete.blend", "living_town_building_study.blend",
    "masterplan.json", "terrain_plan.json", "landscape_plan.json", "interior_plan.json",
    "reserve_plan.json", "tools/build_living_town.py", "tools/terrain_profile.py",
    "tools/interior_design.py", "tools/refine_environment.py", "tools/landscape_details.py",
    "tools/reserve_plan.py", "tools/reserve_environment.py", "tools/reserve_amenities.py",
    "tools/generate_reserve_materials.py", "textures/natural_rock_material.json",
    "textures/natural_rock_basecolor.png", "textures/natural_rock_roughness.png",
    "textures/natural_rock_normal.png",
)
SOURCE_TOOLS = (
    "build_reserve.py", "audit_native_scene.py", "audit_reserve_scene.py",
    "diagnose_roof_contact.py", "export_game_assets.py", "verify_reserve_exports.py",
    "freeze_source.py", "generate_materials.py", "render_reserve.py",
)
REQUIRED_EVIDENCE = (
    "final_source_freeze.json", "native_scene_audit.json", "reserve_native_audit.json",
    "interior_planning_audit.json", "planning_revision_geometry_audit.json",
    "reserve_export_verification.json", "reserve_renders.json", "reserve_visual_review.json",
    "reserve_stair_land_negative_control.json",
)
RENDER_IDS = (
    "01_reserve_overview", "02_reserve_topography", "03_visitor_hub", "04_trailer_park",
    "05_cafe_composition", "06_home_composition", "07_trailer_family_interior",
    "08_trailer_twin_interior", "09_convenience_interior", "10_souvenir_interior",
    "11_bathhouse_interior", "12_public_toilets", "13_lunch_car",
    "14_ravine_bridge", "15_stone_stairs",
)
CAPTURE_IDS = ("01_reserve_overview", "02_trailer_park", "03_trailer_local_cutaway", "04_woodland_bridge")
FIXED_FILES = (
    "LICENSE", "docs/RESERVE_EDITION.md", "tools/package_reserve_delivery.py", "game/data/town3d/projection.json",
    "tools/verify_reserve_delivery.py", SOURCE + "town_manifest.json",
    SOURCE + "source_snapshot/map.json",
    SOURCE + "textures/material_manifest.json", SOURCE + "textures/water_normal.png",
    SOURCE + "external_assets/fonts/PROVENANCE.json",
    SOURCE + "external_assets/polyhaven/PROVENANCE.json",
) + tuple(SOURCE + p for p in FREEZE_FILES) + tuple(SOURCE + "tools/" + p for p in SOURCE_TOOLS) + tuple(EVIDENCE + p for p in REQUIRED_EVIDENCE) + tuple(CONSUMER + p for p in ("project.godot", "Main.tscn", "smoke.gd", "run_consumer.py", "README.md", "evidence/logical_report.json", "evidence/render_report.json", "evidence/runner_report.json"))


class DeliveryError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise DeliveryError(message)


def relative_name(value):
    require(isinstance(value, str) and value and "\\" not in value, "Use a nonempty POSIX relative path")
    require(not value.startswith("/") and ":" not in value and "\x00" not in value, "Absolute or unsafe path: " + value)
    parts = PurePosixPath(value).parts
    require(all(p not in (".", "..", "") for p in parts) and "/".join(parts) == value, "Noncanonical path: " + value)
    require(not any(p.rstrip(" .") != p for p in parts), "Windows-ambiguous path: " + value)
    require(not any(re.fullmatch(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?", p) for p in parts), "Reserved Windows path: " + value)
    return value


def hash_stream(handle):
    digest = hashlib.sha256()
    for block in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def valid_hash(value):
    return isinstance(value, str) and re.fullmatch("[0-9a-f]{64}", value) is not None


class Reader:
    """One canonical package namespace, mapped to workspace, directory or ZIP."""
    def __init__(self, directory=None, archive=None, repo=None, assets=None, consumer_evidence=None):
        self.directory = Path(directory).resolve() if directory else None
        self.repo = Path(repo).resolve() if repo else None
        self.assets = Path(assets).resolve() if assets else (self.repo / SOURCE / "game_assets_reserve" if self.repo else None)
        self.consumer_evidence = Path(consumer_evidence).resolve() if consumer_evidence else None
        self.zip = zipfile.ZipFile(archive, "r") if archive else None
        self.cache = {}
        if self.zip:
            entries = self.zip.infolist()
            names = [relative_name(i.filename) for i in entries if not i.is_dir()]
            require(len(names) == len(set(n.casefold() for n in names)), "Duplicate/case-colliding ZIP members")
            for item in entries:
                require(not item.is_dir(), "Unexpected ZIP directory entry")
                require(not item.flag_bits & 1, "Encrypted ZIP entry")
                require((item.external_attr >> 16) & 0o170000 != 0o120000, "ZIP symlink entry")
            self.zip_names = set(names)

    def close(self):
        if self.zip:
            self.zip.close()

    def path(self, name):
        name = relative_name(name)
        if self.directory:
            base, path = self.directory, self.directory / name
        elif name.startswith(ASSETS):
            base, path = self.assets, self.assets / name[len(ASSETS):]
        elif self.consumer_evidence and name.startswith(CONSUMER + "evidence/"):
            base, path = self.consumer_evidence, self.consumer_evidence / name[len(CONSUMER + "evidence/"):]
        else:
            base, path = self.repo, self.repo / name
        require(path.resolve().is_relative_to(base.resolve()), "Path escapes root: " + name)
        cursor = path
        while cursor != base.parent:
            require(not cursor.is_symlink(), "Symlink not permitted: " + name)
            if cursor == base:
                break
            cursor = cursor.parent
        require(path.is_file(), "Missing required file: " + str(path))
        return path

    def open(self, name):
        relative_name(name)
        if self.zip:
            require(name in self.zip_names, "Missing ZIP member: " + name)
            return self.zip.open(name, "r")
        return self.path(name).open("rb")

    def size(self, name):
        return self.zip.getinfo(name).file_size if self.zip else self.path(name).stat().st_size

    def record(self, name):
        if name not in self.cache:
            with self.open(name) as handle:
                digest = hash_stream(handle)
            self.cache[name] = {"path": name, "bytes": self.size(name), "sha256": digest}
        return self.cache[name]

    def json(self, name):
        require(self.size(name) < 64 * 1024 * 1024, "Oversized JSON: " + name)
        with self.open(name) as handle:
            return json.load(io.TextIOWrapper(handle, encoding="utf-8-sig"))


def same_receipt(reader, name, receipt):
    require(isinstance(receipt, dict), "Missing receipt for " + name)
    actual = reader.record(name)
    require(receipt.get("sha256") == actual["sha256"], "SHA256 mismatch: " + name)
    require(receipt.get("bytes") == actual["bytes"] and actual["bytes"] > 0, "Byte count mismatch: " + name)
    return actual


def pass_checks(report, schema=None, boolean=False):
    require(isinstance(report, dict) and report.get("status") == "PASS", "Report is not PASS")
    if schema:
        require(report.get("schema") == schema, "Unexpected report schema")
    checks = report.get("checks")
    require(isinstance(checks, list) and checks, "No recorded checks")
    names = []
    for item in checks:
        require(item.get("passed") is True if boolean else item.get("status") == "PASS", "Failed recorded check: " + str(item))
        names.append(item.get("name" if boolean else "id"))
    require(all(isinstance(n, str) and n for n in names) and len(names) == len(set(names)), "Duplicate/missing check names")
    if boolean:
        require(report.get("failure_count") == 0 and report.get("check_count") == len(checks), "Consumer check totals disagree")


def png_size(reader, name):
    with reader.open(name) as handle:
        head = handle.read(24)
    require(len(head) == 24 and head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR", "Invalid PNG header: " + name)
    result = list(struct.unpack(">II", head[16:24]))
    require(min(result) > 0, "Empty PNG: " + name)
    return result


def glb_json(reader, name):
    with reader.open(name) as handle:
        header = handle.read(20)
        require(len(header) == 20, "Short GLB: " + name)
        magic, version, size, length, kind = struct.unpack("<4sIIII", header)
        require(magic == b"glTF" and version == 2 and size == reader.size(name), "Invalid GLB2 header/length: " + name)
        require(kind == 0x4e4f534a and 0 < length < min(size, 64 * 1024 * 1024), "Invalid GLB JSON chunk")
        doc = json.loads(handle.read(length).decode("utf-8"))
    require(doc.get("asset", {}).get("version") == "2.0", "Invalid glTF version")
    require(not doc.get("extensionsRequired"), "Required extension reduces engine-neutral portability: " + name)
    for group in ("buffers", "images"):
        for item in doc.get(group, []):
            require("uri" not in item or item["uri"].startswith("data:"), "External GLB resource: " + name)
    for material in doc.get("materials", []):
        require("pbrMetallicRoughness" in material, "Missing core PBR material: " + name)
    return doc


def export_records(manifest):
    records = [manifest.get("town_game"), manifest.get("camera_rig")]
    if manifest.get("town_high_detail") is not None:
        records.append(manifest["town_high_detail"])
    records += [b.get("standalone") for b in manifest.get("buildings", [])]
    records += [b.get("standalone") for b in manifest.get("reserve_buildings", [])]
    require(all(isinstance(r, dict) and r.get("file") for r in records), "Optimized whole town, camera rig and every prefab are required")
    paths = [relative_name(r["file"]) for r in records]
    require(len(paths) == len(set(p.casefold() for p in paths)), "Duplicate export filenames")
    require(all(p.endswith(".glb") for p in paths), "Unexpected export file type")
    return records


def payload_names(reader):
    """Curated allowlist, never a recursive copy of a workspace directory."""
    names = set(FIXED_FILES)
    manifest = reader.json(ASSETS + "export_manifest.json")
    names.add(ASSETS + "export_manifest.json")
    names.update(ASSETS + r["file"] for r in export_records(manifest))
    materials = reader.json(SOURCE + "textures/material_manifest.json")
    for material in materials["materials"].values():
        for slot in ("basecolor", "roughness", "normal"):
            names.add(SOURCE + "textures/" + relative_name(material[slot]))
    for folder in ("fonts", "polyhaven"):
        provenance = reader.json(SOURCE + "external_assets/" + folder + "/PROVENANCE.json")
        records = provenance.get("files", [provenance])
        for record in records:
            names.add(SOURCE + "external_assets/" + folder + "/" + relative_name(record["file"]))
    names.update(SOURCE + "renders/reserve_v6/" + ident + ".png" for ident in RENDER_IDS)
    names.update(CONSUMER + "evidence/captures/" + ident + ".png" for ident in CAPTURE_IDS)
    names.update(CONSUMER + "evidence/" + stage + "." + stream + ".log" for stage in ("parser", "logical", "render") for stream in ("stdout", "stderr"))
    require(len(names) == len(set(n.casefold() for n in names)), "Case-colliding payload names")
    return sorted(relative_name(n) for n in names)


def validate(reader, packaged=False):
    report = {"schema": SCHEMA, "generated_utc": datetime.now(timezone.utc).isoformat(), "status": "FAIL", "checks": [],
              "scope": "Current reserve asset/source receipts and actual reviewed PNG bindings; no engine execution, collision/playability or listening claim."}
    state = {}

    def check(name, callback):
        try:
            detail = callback()
            report["checks"].append({"id": name, "status": "PASS", "detail": detail})
        except (OSError, ValueError, KeyError, TypeError, AssertionError, zipfile.BadZipFile) as exc:
            report["checks"].append({"id": name, "status": "FAIL", "error": str(exc)})

    def need(*keys):
        require(all(key in state for key in keys), "Required earlier evidence did not validate: " + ", ".join(key for key in keys if key not in state))

    def sources():
        freeze = reader.json(EVIDENCE + "final_source_freeze.json")
        require(freeze.get("schema") == "living_town.source_freeze.v6", "Reserve delivery requires a current V6 freeze; urban V5 is not sufficient")
        require(set(freeze.get("files", {})) == set(FREEZE_FILES), "Unexpected/missing freeze file set")
        for name, digest in freeze["files"].items():
            require(valid_hash(digest) and reader.record(SOURCE + name)["sha256"] == digest, "Stale frozen source: " + name)
        bindings = {key: reader.record(SOURCE + name)["sha256"] for key, name in BINDINGS.items()}
        town = reader.json(SOURCE + "town_manifest.json")
        for key, digest in bindings.items():
            require(town.get(key) == digest, "Stale native manifest binding: " + key)
        require(town.get("reserve_amenities", {}).get("building_count") == 21, "Expected 21 reserve amenities")
        require(town["reserve_amenities"].get("room_count", 0) > 0 and town["reserve_amenities"].get("furnishing_count", 0) > 0, "Empty reserve inventory")
        require(freeze.get("reserve_environment") == town.get("reserve_environment"), "Freeze/native reserve environment differs")
        require(freeze.get("reserve_amenity_inventory") == {key: town["reserve_amenities"][key] for key in ("building_count", "room_count", "furnishing_count", "kinds")}, "Freeze/native reserve amenity inventory differs")
        state.update(freeze=freeze, town=town, bindings=bindings, native_sha=freeze["files"]["living_town_complete.blend"])
        report["source_blend_sha256"] = state["native_sha"]
        report["source_freeze_sha256"] = reader.record(EVIDENCE + "final_source_freeze.json")["sha256"]
        return {"frozen_files": len(freeze["files"]), "source_bindings": bindings}
    check("current_v6_native_and_source_freeze", sources)

    def audits():
        need("native_sha", "freeze", "bindings")
        for filename, schema in (("native_scene_audit.json", "living_town.native_audit.v3"), ("reserve_native_audit.json", "living_town.reserve_native_audit.v1")):
            audit = reader.json(EVIDENCE + filename)
            pass_checks(audit, schema)
            require(audit.get("source_blend_sha256") == state["native_sha"], "Stale native audit: " + filename)
            source_bindings = audit.get("source_bindings", audit)
            for key, digest in state["bindings"].items():
                if filename == "native_scene_audit.json" and key.startswith("reserve_"):
                    continue
                if filename == "reserve_native_audit.json" and key == "landscape_details_sha256":
                    continue  # Core native audit binds this urban landscape module.
                require(source_bindings.get(key) == digest, "Stale audit binding: " + key)
            if filename.startswith("reserve_"):
                require(audit.get("audit_module_sha256") == reader.record(SOURCE + "tools/audit_reserve_scene.py")["sha256"], "Reserve audit module changed")
                require(audit.get("primitive_recipe_module_sha256") == reader.record(SOURCE + "tools/build_living_town.py")["sha256"], "Reserve primitive recipe changed")
                require(state["freeze"].get("reserve_native_audit_sha256") == reader.record(EVIDENCE + filename)["sha256"], "Freeze does not bind reserve audit")
                require(state["freeze"].get("reserve_native_checks") == len(audit["checks"]), "Reserve audit count differs from freeze")
                projection = reader.json("game/data/town3d/projection.json")
                fixture_ids = {b["model_asset_id"] for b in projection.get("interaction_bindings", {}).values() if b.get("model_asset_id")}
                require(len(fixture_ids) == 47, "Reference projection does not retain 47 unique game-bound fixtures")
                fixture_checks = [c for c in audit["checks"] if c["id"] == "frozen_47_game_bound_fixture_ids_exist_in_actual_meshes"]
                require(len(fixture_checks) == 1, "Native projection/fixture check is missing")
                fixture = fixture_checks[0].get("detail", {})
                require(fixture.get("projection_sha256") == reader.record("game/data/town3d/projection.json")["sha256"], "Reference projection changed since native fixture audit")
                require(fixture.get("unique_fixture_ids") == 47 and set(fixture.get("fixture_ids", [])) == fixture_ids and fixture.get("missing") == [], "Native reference-fixture coverage differs")
            else:
                require(state["freeze"].get("native_checks") == len(audit["checks"]), "Native audit count differs from freeze")
                contacts = [c for c in audit["checks"] if c["id"] == "all57_chimney_bases_intersect_actual_roof_surfaces"]
                require(len(contacts) == 1, "Actual chimney contact check is absent")
                detail = contacts[0].get("detail", {})
                require(detail.get("status") == "PASS" and detail.get("chimney_count") == 57 and detail.get("sample_count") == 513 and not detail.get("failures"), "Actual 57/513 chimney contact proof differs")
        interior = reader.json(EVIDENCE + "interior_planning_audit.json")
        require(interior.get("status") == "PASS", "Interior planning audit failed")
        for key in ("interior_plan_sha256", "interior_module_sha256"):
            require(interior.get(key) == state["bindings"][key], "Stale interior planning audit")
        geometry = reader.json(EVIDENCE + "planning_revision_geometry_audit.json")
        pass_checks(geometry)
        require(geometry.get("masterplan_sha256") == state["bindings"]["masterplan_sha256"], "Stale planning geometry audit")
        return "Both saved-native audits and the planning prerequisites bind current source bytes."
    check("current_native_and_planning_audits", audits)

    def stair_negative_control():
        need("native_sha")
        name = EVIDENCE + "reserve_stair_land_negative_control.json"
        control = reader.json(name)
        require(control.get("schema") == "living_town.reserve_stair_land_negative_control.v1" and control.get("status") == "PASS", "Stair negative-control receipt is not PASS")
        module_sha = reader.record(SOURCE + "tools/audit_reserve_scene.py")["sha256"]
        require(control.get("audit_module", {}).get("sha256") == module_sha, "Stair negative control used a different audit module")
        gate_id = "actual_stair_land_occlusion_and_walking_head_clearance_absent"
        observed = control.get("gate", {})
        require(observed.get("id") == gate_id and observed.get("observed_status") == "FAIL" and observed.get("failure_count") == 1950, "Historical stair control must record the measured FAIL/1950 rejection")
        bad_native = control.get("known_bad_native", {})
        require(valid_hash(bad_native.get("sha256")) and bad_native["sha256"] != state["native_sha"], "Historical bad native must be distinct from the delivered native")
        require(bad_native.get("included_in_final_delivery") is False and bad_native.get("exact_bytes_independently_verified_when_receipt_created") is True, "Historical bad native identity or exclusion is unproven")
        current = reader.json(EVIDENCE + "reserve_native_audit.json")
        require(current.get("status") == "PASS" and current.get("source_blend_sha256") == state["native_sha"], "Current stair audit is stale or failed")
        final_gates = [c for c in current.get("checks", []) if c.get("id") == gate_id]
        require(len(final_gates) == 1 and final_gates[0].get("status") == "PASS" and final_gates[0].get("detail", {}).get("failure_count") == 0, "Delivered native must separately pass the same actual stair gate")
        return {"historical_observed_status": "FAIL", "historical_failure_count": 1950,
                "current_gate_status": "PASS", "known_bad_native_included": False,
                "negative_receipt_sha256": reader.record(name)["sha256"], "audit_module_sha256": module_sha}
    check("current_stair_gate_and_historical_negative_control", stair_negative_control)

    def assets():
        need("native_sha", "bindings", "town")
        manifest = reader.json(ASSETS + "export_manifest.json")
        require(manifest.get("schema") == "living_town.game_assets.v1" and manifest.get("status") == "PASS" and manifest.get("evidence_label") == "final", "Export is not a final PASS")
        require(manifest.get("source_blend_sha256") == state["native_sha"], "Export native source is stale")
        require(manifest.get("source_manifest_sha256") == reader.record(SOURCE + "town_manifest.json")["sha256"], "Export native manifest is stale")
        require(manifest.get("exporter_sha256") == reader.record(SOURCE + "tools/export_game_assets.py")["sha256"], "Exporter script changed")
        for key, digest in state["bindings"].items():
            if key == "terrain_profile_sha256":
                continue  # Export schema binds the terrain plan; the native audits also bind its generator.
            require(manifest.get("source_" + key) == digest, "Stale export source binding: " + key)
        require(manifest.get("building_count") == 49 and len(manifest.get("buildings", [])) == 49, "Core prefab inventory is not 49")
        require(manifest.get("reserve_building_count") == 21 and len(manifest.get("reserve_buildings", [])) == 21, "Reserve prefab inventory is not 21")
        require(manifest.get("reserve_amenities") == state["town"]["reserve_amenities"], "Native/export reserve inventory differs")
        require(manifest.get("reserve_environment") == state["town"]["reserve_environment"], "Native/export environment differs")
        require(set(manifest.get("portable_binding_fields", [])) == set(BINDINGS) - {"terrain_plan_sha256", "terrain_profile_sha256"}, "Portable binding field contract is incomplete")
        require(manifest.get("camera_rig", {}).get("camera_count") == state["freeze"].get("cameras") and state["freeze"].get("cameras", 0) > 0, "Camera rig count differs from frozen native")
        records = export_records(manifest)
        for record in records:
            name = ASSETS + record["file"]
            same_receipt(reader, name, record)
            glb_json(reader, name)
        optimized = manifest["town_game"]
        doc = glb_json(reader, ASSETS + optimized["file"])
        roots = [n for n in doc.get("nodes", []) if n.get("name") == "LivingTown"]
        require(len(roots) == 1 and roots[0].get("extras", {}).get("source_blend_sha256") == state["native_sha"], "GLB root source differs")
        for key in manifest.get("portable_binding_fields", []):
            require(key in state["bindings"] and roots[0]["extras"].get(key) == state["bindings"][key], "GLB source binding differs: " + key)
        reserve_ids = [n.get("extras", {}).get("reserve_building_id") for n in doc.get("nodes", []) if n.get("extras", {}).get("reserve_role") == "building"]
        require(len(reserve_ids) == 21 and set(reserve_ids) == {b["id"] for b in manifest["reserve_buildings"]}, "Actual GLB reserve building roots differ")
        require(manifest.get("optimization", {}).get("game_budget_passed") is True, "Optimized town exceeds the declared measured budget")
        require(isinstance(optimized.get("triangles"), int) and 0 < optimized["triangles"] <= manifest["optimization"].get("game_triangle_budget", 0) <= MAX_GAME_TRIANGLES, "Optimized triangle cost/budget is invalid or exceeds the accepted 5M expanded-triangle ceiling")
        proof = reader.json(EVIDENCE + "reserve_export_verification.json")
        pass_checks(proof, "living_town.reserve_export_verification.v1")
        require(proof.get("source_blend_sha256") == state["native_sha"] and proof.get("export_manifest_sha256") == reader.record(ASSETS + "export_manifest.json")["sha256"], "Independent export verification is stale")
        require(proof.get("source_manifest_sha256") == reader.record(SOURCE + "town_manifest.json")["sha256"], "Independent export native manifest is stale")
        require(set(proof.get("source_bindings", {})) == set(BINDINGS) - {"terrain_profile_sha256"}, "Independent export verification lacks its complete source binding set")
        for key, digest in proof.get("source_bindings", {}).items():
            require(key in state["bindings"] and digest == state["bindings"][key], "Independent export source binding differs")
        state.update(manifest=manifest, asset_records=records)
        report["export_manifest_sha256"] = reader.record(ASSETS + "export_manifest.json")["sha256"]
        report["optimized_glb"] = reader.record(ASSETS + optimized["file"])
        return {"glbs": len(records), "core_prefabs": 49, "reserve_prefabs": 21, "game_triangles": optimized.get("triangles"), "high_detail_triangles": (manifest.get("town_high_detail") or {}).get("triangles")}
    check("current_self_contained_exports_and_independent_verification", assets)

    def native_images():
        need("native_sha", "bindings")
        renders = reader.json(EVIDENCE + "reserve_renders.json")
        require(isinstance(renders, list) and len(renders) == 15 and {r["id"] for r in renders} == set(RENDER_IDS), "Exactly 15 final reserve render records are required")
        images = []
        for row in renders:
            expected = "renders/reserve_v6/" + row["id"] + ".png"
            require(row.get("image") == expected, "Nonfinal or misplaced render record")
            require(row.get("source_blend_sha256") == state["native_sha"], "Stale final render source: " + row["id"])
            for key in ("reserve_plan_sha256", "interior_plan_sha256"):
                require(row.get(key) == state["bindings"][key], "Stale render source binding")
            name = SOURCE + expected
            require(reader.record(name)["sha256"] == row.get("sha256"), "Render image hash differs: " + name)
            require(png_size(reader, name) == row.get("resolution"), "Render PNG dimensions differ")
            require(isinstance(row.get("samples"), int) and row["samples"] >= 32, "Preview-quality native render")
            images.append(name)
        state["native_images"] = images
        return {"current_final_images": len(images)}
    check("fifteen_current_final_native_renders", native_images)

    def consumers():
        need("native_sha", "manifest", "bindings", "town")
        summaries = {}
        for filename, capture in (("logical_report.json", False), ("render_report.json", True)):
            data = reader.json(CONSUMER + "evidence/" + filename)
            pass_checks(data, "living_town.reserve_consumer.v1", boolean=True)
            require(data.get("source_blend_sha256") == state["native_sha"], "Stale consumer native source")
            inputs = data.get("inputs", {})
            require(inputs.get("capture_requested") is capture, "Wrong consumer run mode")
            for name, item in ((ASSETS + "export_manifest.json", "export_manifest"), (SOURCE + "town_manifest.json", "native_manifest"), (CONSUMER + "smoke.gd", "consumer_script"), (ASSETS + state["manifest"]["town_game"]["file"], "glb")):
                same_receipt(reader, name, inputs.get(item))
            for key in state["manifest"].get("portable_binding_fields", []):
                require(data.get("source_" + key) == state["bindings"][key], "Stale consumer planning binding")
            inventory = state["town"]["reserve_amenities"]
            require(data.get("reserve_inventory") == {"buildings": inventory["building_count"], "rooms": inventory["room_count"], "furnishings": inventory["furnishing_count"]}, "Consumer inventory differs from native")
            names = {c["name"] for c in data["checks"]}
            require({"reserve_furnishing_ids_match_native", "all_actual_room_floor_tops_match_finished_floor_datum", "full_glb_creates_node3d_scene"}.issubset(names), "Missing reserve-specific consumer checks")
            if capture:
                require(data.get("display_server") not in (None, "headless"), "Renderer captures came from a headless-only run")
                shots = data.get("images", [])
                require(len(shots) == 4 and {r["name"] for r in shots} == set(CAPTURE_IDS), "Exactly four current reserve capture views required")
                image_names = []
                for shot in shots:
                    name = CONSUMER + "evidence/captures/" + shot["name"] + ".png"
                    require(str(shot.get("path", "")).replace("\\", "/").rsplit("/", 1)[-1] == shot["name"] + ".png", "Capture receipt filename differs")
                    same_receipt(reader, name, shot)
                    png_size(reader, name)
                    image_names.append(name)
                state["consumer_images"] = image_names
            summaries[filename] = len(data["checks"])
        runner = reader.json(CONSUMER + "evidence/runner_report.json")
        require(runner.get("schema") == "living_town.reserve_consumer_runner.v1" and runner.get("status") == "PASS", "Consumer supervisor did not PASS")
        for name, key in ((CONSUMER + "smoke.gd", "consumer"), (CONSUMER + "project.godot", "project"), (ASSETS + "export_manifest.json", "export_manifest"), (SOURCE + "town_manifest.json", "native_manifest"), (CONSUMER + "evidence/logical_report.json", "logical_report"), (CONSUMER + "evidence/render_report.json", "render_report")):
            same_receipt(reader, name, runner.get(key))
        stages = runner.get("stages", [])
        require([s.get("name") for s in stages] == ["parser", "logical", "render"], "Consumer did not execute the expected serial stages")
        for stage in stages:
            require(stage.get("exit_code") == 0 and stage.get("fatal_or_script_messages") == [], "Consumer stage failed")
            for stream in ("stdout", "stderr"):
                # Empty clean stderr is valid; still bind its zero-byte receipt.
                name = CONSUMER + "evidence/" + stage["name"] + "." + stream + ".log"
                actual = reader.record(name)
                require(stage.get(stream, {}).get("sha256") == actual["sha256"] and stage[stream].get("bytes") == actual["bytes"], "Stage log receipt differs")
        return summaries
    check("current_isolated_godot_logical_and_actual_renderer_receipts", consumers)

    def image_review():
        need("native_sha", "native_images", "consumer_images")
        review = reader.json(EVIDENCE + "reserve_visual_review.json")
        require(review.get("status") == "PASS" and review.get("visually_reviewed") is True, "Actual visual review is missing or pending")
        require(review.get("reviewer_kind") in ("agent", "human") and review.get("source_blend_sha256") == state["native_sha"], "Visual review source/reviewer differs")
        require(review.get("export_manifest_sha256") == reader.record(ASSETS + "export_manifest.json")["sha256"], "Visual review export manifest is stale")
        expected = set(state["native_images"] + state["consumer_images"])
        seen = set()
        for item in review.get("images", []):
            value = item.get("path", item.get("image", ""))
            candidates = [name for name in expected if value.replace("\\", "/").endswith(name) or value == name.removeprefix(SOURCE)]
            require(len(candidates) == 1, "Unrecognized/ambiguous reviewed image: " + value)
            name = candidates[0]
            require(name not in seen and item.get("sha256") == reader.record(name)["sha256"], "Duplicate or stale reviewed image: " + name)
            require(bool(item.get("observations")), "Image review lacks actual observations: " + name)
            require(item.get("status", "PASS") == "PASS", "Image review has a concrete blocker")
            seen.add(name)
        require(seen == expected, "Visual review must cover all 15 native images and four consumer captures")
        return {"reviewed_images": len(seen), "reviewer_kind": review["reviewer_kind"], "review_sha256": reader.record(EVIDENCE + "reserve_visual_review.json")["sha256"]}
    check("separate_actual_review_of_all_nineteen_final_images", image_review)

    def dependencies():
        mats = reader.json(SOURCE + "textures/material_manifest.json")
        require(len(mats.get("materials", {})) == 9, "Expected nine procedural PBR texture families")
        for material in mats["materials"].values():
            for slot in ("basecolor", "roughness", "normal"):
                png_size(reader, SOURCE + "textures/" + relative_name(material[slot]))
        png_size(reader, SOURCE + "textures/water_normal.png")
        rock = reader.json(SOURCE + "textures/natural_rock_material.json")
        require(rock.get("schema") == "living_town.natural_rock_material.v1" and rock.get("tile_size_metres") == 4.0 and rock.get("edge_checks") == "PASS", "Natural-rock material metadata is invalid")
        require(rock.get("generator_sha256") == reader.record(SOURCE + "tools/generate_reserve_materials.py")["sha256"], "Natural-rock generator changed")
        require(rock.get("helper_sha256") == reader.record(SOURCE + "tools/generate_materials.py")["sha256"], "Natural-rock noise/normal helper changed")
        for slot, resolution in (("basecolor", [1024, 1024]), ("roughness", [512, 512]), ("normal", [512, 512])):
            name = SOURCE + "textures/natural_rock_" + slot + ".png"
            same_receipt(reader, name, rock.get("maps", {}).get(slot))
            require(png_size(reader, name) == resolution, "Natural-rock map dimensions differ")
        for folder in ("fonts", "polyhaven"):
            provenance = reader.json(SOURCE + "external_assets/" + folder + "/PROVENANCE.json")
            require(bool(provenance.get("license")), "Dependency license missing")
            for row in provenance.get("files", [provenance]):
                same_receipt(reader, SOURCE + "external_assets/" + folder + "/" + relative_name(row["file"]), row)
        payload = payload_names(reader)
        for name in payload:
            reader.record(name)
        state["payload"] = payload
        return {"payload_files": len(payload), "payload_bytes": sum(reader.record(n)["bytes"] for n in payload), "raw_film_or_old_media_included": False}
    check("curated_rebuild_sources_materials_licenses_and_provenance", dependencies)

    if packaged:
        def package_inventory():
            need("payload", "native_sha")
            inventory = reader.json(FILE_MANIFEST)
            require(inventory.get("schema") == "living_town.reserve_package.v1" and inventory.get("release_tag") == RELEASE_TAG, "Wrong package manifest/release")
            require(inventory.get("source_blend_sha256") == state["native_sha"] and inventory.get("export_manifest_sha256") == report["export_manifest_sha256"], "Package source binding differs")
            require(inventory.get("source_freeze_sha256") == report["source_freeze_sha256"], "Package source freeze binding differs")
            rows = inventory.get("files", [])
            names = [relative_name(r["path"]) for r in rows]
            expected = set(state["payload"]) | {"START_HERE.md"}
            require(len(names) == len(set(n.casefold() for n in names)) and set(names) == expected, "Package manifest is not the curated allowlist")
            for row in rows:
                actual = reader.record(row["path"])
                require(row.get("sha256") == actual["sha256"] and row.get("bytes") == actual["bytes"], "Packaged file receipt differs: " + row["path"])
            require(inventory.get("file_count") == len(rows) and inventory.get("payload_bytes") == sum(r["bytes"] for r in rows), "Package inventory totals disagree")
            actual_names = reader.zip_names if reader.zip else {p.relative_to(reader.directory).as_posix() for p in reader.directory.rglob("*") if p.is_file()}
            require(actual_names == expected | {FILE_MANIFEST}, "Unexpected or missing package/ZIP members")
            report["file_manifest"] = reader.record(FILE_MANIFEST)
            return {"payload_files": len(rows), "every_zip_member_stream_verified": reader.zip is not None}
        check("complete_package_inventory_and_streamed_checksums", package_inventory)
    report["passed"] = sum(c["status"] == "PASS" for c in report["checks"])
    report["failed"] = len(report["checks"]) - report["passed"]
    report["status"] = "PASS" if not report["failed"] else "FAIL"
    return report


def _synthetic_fixture(directory, high_detail=True, square_topomap=False, extra_audit_check=False):
    """Tiny receipt fixture for contract tests, never used as delivery evidence."""
    base = Path(directory)
    def put(name, content):
        path = base / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else json.dumps(content).encode())
    def receipt(name):
        return Reader(directory=base).record(name)
    for name in FIXED_FILES:
        put(name, b"synthetic fixture, not an actual model or audit")
    put("game/data/town3d/projection.json", {"interaction_bindings": {"functional_" + str(i): {"model_asset_id": "fixture_" + str(i)} for i in range(47)}})
    # PNG header is enough for header tests; the independent visual-review
    # contract is tested as a receipt, without claiming the fixture is rendered.
    png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 8, 6)
    materials = {"material_" + str(i): {slot: str(i) + "_" + slot + ".png" for slot in ("basecolor", "roughness", "normal")} for i in range(9)}
    for material in materials.values():
        for name in material.values():
            put(SOURCE + "textures/" + name, png)
    put(SOURCE + "textures/water_normal.png", png)
    put(SOURCE + "textures/material_manifest.json", {"materials": materials})
    rock_maps = {}
    for slot, size in (("basecolor", 1024), ("roughness", 512), ("normal", 512)):
        name = SOURCE + "textures/natural_rock_" + slot + ".png"
        put(name, b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", size, size))
        rock_maps[slot] = dict(receipt(name), file=Path(name).name)
    put(SOURCE + "textures/natural_rock_material.json", {"schema": "living_town.natural_rock_material.v1", "tile_size_metres": 4.0, "edge_checks": "PASS",
        "generator_sha256": receipt(SOURCE + "tools/generate_reserve_materials.py")["sha256"], "helper_sha256": receipt(SOURCE + "tools/generate_materials.py")["sha256"], "maps": rock_maps})
    for folder, filename in (("fonts", "font.ttf"), ("polyhaven", "sky.hdr")):
        name = SOURCE + "external_assets/" + folder + "/" + filename
        put(name, b"synthetic dependency")
        put(SOURCE + "external_assets/" + folder + "/PROVENANCE.json", {"license": "synthetic", "files": [dict(receipt(name), file=filename)]})
    bindings = {key: receipt(SOURCE + name)["sha256"] for key, name in BINDINGS.items()}
    native_sha = receipt(SOURCE + "living_town_complete.blend")["sha256"]
    inventory = {"building_count": 21, "room_count": 92, "furnishing_count": 158, "kinds": {"trailer": 12, "service": 9}}
    town = {**bindings, "reserve_amenities": inventory, "reserve_environment": {"tree_instances": 3500}}
    put(SOURCE + "town_manifest.json", town)
    core_checks = [{"id": "all57_chimney_bases_intersect_actual_roof_surfaces", "status": "PASS", "detail": {"status": "PASS", "chimney_count": 57, "sample_count": 513, "failures": []}}]
    core = {"schema": "living_town.native_audit.v3", "status": "PASS", "source_blend_sha256": native_sha, **bindings, "checks": core_checks}
    put(EVIDENCE + "native_scene_audit.json", core)
    reserve = {"schema": "living_town.reserve_native_audit.v1", "status": "PASS", "source_blend_sha256": native_sha, "source_bindings": bindings,
               "audit_module_sha256": receipt(SOURCE + "tools/audit_reserve_scene.py")["sha256"],
               "primitive_recipe_module_sha256": receipt(SOURCE + "tools/build_living_town.py")["sha256"], "checks": [{"id": "fixture_contract", "status": "PASS"},
               {"id": "frozen_47_game_bound_fixture_ids_exist_in_actual_meshes", "status": "PASS", "detail": {"projection_sha256": receipt("game/data/town3d/projection.json")["sha256"],
                "unique_fixture_ids": 47, "fixture_ids": ["fixture_" + str(i) for i in range(47)], "missing": []}},
                {"id": "actual_stair_land_occlusion_and_walking_head_clearance_absent", "status": "PASS", "detail": {"failure_count": 0}}]}
    if extra_audit_check:
        reserve["checks"].append({"id": "additional_actual_triangle_winding_fixture", "status": "PASS"})
    put(EVIDENCE + "reserve_native_audit.json", reserve)
    put(EVIDENCE + "reserve_stair_land_negative_control.json", {
        "schema": "living_town.reserve_stair_land_negative_control.v1", "status": "PASS",
        "audit_module": {"sha256": receipt(SOURCE + "tools/audit_reserve_scene.py")["sha256"]},
        "known_bad_native": {"sha256": hashlib.sha256(b"different known-bad synthetic native").hexdigest(),
                             "included_in_final_delivery": False, "exact_bytes_independently_verified_when_receipt_created": True},
        "gate": {"id": "actual_stair_land_occlusion_and_walking_head_clearance_absent", "observed_status": "FAIL", "failure_count": 1950}})
    freeze = {"schema": "living_town.source_freeze.v6", "files": {name: receipt(SOURCE + name)["sha256"] for name in FREEZE_FILES},
              "reserve_environment": town["reserve_environment"], "reserve_amenity_inventory": inventory, "native_checks": 1, "reserve_native_checks": len(reserve["checks"]),
              "reserve_native_audit_sha256": receipt(EVIDENCE + "reserve_native_audit.json")["sha256"], "cameras": 14}
    put(EVIDENCE + "final_source_freeze.json", freeze)
    put(EVIDENCE + "interior_planning_audit.json", {"status": "PASS", "interior_plan_sha256": bindings["interior_plan_sha256"], "interior_module_sha256": bindings["interior_module_sha256"]})
    put(EVIDENCE + "planning_revision_geometry_audit.json", {"status": "PASS", "masterplan_sha256": bindings["masterplan_sha256"], "checks": [{"id": "fixture_contract", "status": "PASS"}]})
    portable = sorted(set(BINDINGS) - {"terrain_plan_sha256", "terrain_profile_sha256"})
    reserve_ids = ["Reserve_" + str(i) for i in range(21)]
    doc = {"asset": {"version": "2.0"}, "nodes": [{"name": "LivingTown", "extras": {"source_blend_sha256": native_sha, **{key: bindings[key] for key in portable}}}] + [
        {"extras": {"reserve_role": "building", "reserve_building_id": ident}} for ident in reserve_ids], "materials": [{"pbrMetallicRoughness": {}}]}
    text = json.dumps(doc).encode();text += b" " * (-len(text) % 4)
    blob = struct.pack("<4sIIII", b"glTF", 2, 20 + len(text), len(text), 0x4e4f534a) + text
    def asset(filename):
        put(ASSETS + filename, blob)
        return dict(receipt(ASSETS + filename), file=filename, triangles=100)
    manifest = {"schema": "living_town.game_assets.v1", "status": "PASS", "evidence_label": "final", "source_blend_sha256": native_sha,
                "source_manifest_sha256": receipt(SOURCE + "town_manifest.json")["sha256"], "exporter_sha256": receipt(SOURCE + "tools/export_game_assets.py")["sha256"],
                **{"source_" + key: digest for key, digest in bindings.items()}, "portable_binding_fields": portable,
                "building_count": 49, "buildings": [{"id": "Core_" + str(i), "standalone": asset("buildings/Core_" + str(i) + ".glb")} for i in range(49)],
                "reserve_building_count": 21, "reserve_buildings": [{"id": ident, "standalone": asset("reserve/" + ident + ".glb")} for ident in reserve_ids],
                "reserve_amenities": inventory, "reserve_environment": town["reserve_environment"], "town_game": asset("living_town_game.glb"),
                "town_high_detail": asset("living_town.glb") if high_detail else None, "camera_rig": dict(asset("cameras.glb"), camera_count=14),
                "optimization": {"game_budget_passed": True, "game_triangle_budget": 1000}}
    put(ASSETS + "export_manifest.json", manifest)
    put(EVIDENCE + "reserve_export_verification.json", {"schema": "living_town.reserve_export_verification.v1", "status": "PASS", "checks": [{"id": "fixture_contract", "status": "PASS"}],
        "source_blend_sha256": native_sha, "export_manifest_sha256": receipt(ASSETS + "export_manifest.json")["sha256"], "source_manifest_sha256": manifest["source_manifest_sha256"],
        "source_bindings": {key: digest for key, digest in bindings.items() if key != "terrain_profile_sha256"}})
    images, renders = [], []
    for ident in RENDER_IDS:
        square = square_topomap and ident == "02_reserve_topography"
        content = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 8, 8) if square else png
        name = SOURCE + "renders/reserve_v6/" + ident + ".png";put(name, content)
        images.append(dict(receipt(name), observations="Synthetic receipt test only"))
        renders.append({"id": ident, "image": name.removeprefix(SOURCE), "source_blend_sha256": native_sha, "reserve_plan_sha256": bindings["reserve_plan_sha256"],
                        "interior_plan_sha256": bindings["interior_plan_sha256"], "resolution": [8, 8] if square else [8, 6], "samples": 32, "sha256": receipt(name)["sha256"]})
    put(EVIDENCE + "reserve_renders.json", renders)
    checks = [{"name": name, "passed": True} for name in ("reserve_furnishing_ids_match_native", "all_actual_room_floor_tops_match_finished_floor_datum", "full_glb_creates_node3d_scene")]
    for filename, capture in (("logical_report.json", False), ("render_report.json", True)):
        data = {"schema": "living_town.reserve_consumer.v1", "status": "PASS", "failure_count": 0, "check_count": len(checks), "checks": checks,
                "source_blend_sha256": native_sha, **{"source_" + key: bindings[key] for key in portable},
                "reserve_inventory": {"buildings": 21, "rooms": 92, "furnishings": 158}, "display_server": "fixture" if capture else "headless",
                "inputs": {"export_manifest": receipt(ASSETS + "export_manifest.json"), "native_manifest": receipt(SOURCE + "town_manifest.json"),
                           "consumer_script": receipt(CONSUMER + "smoke.gd"), "glb": receipt(ASSETS + "living_town_game.glb"), "capture_requested": capture}}
        if capture:
            data["images"] = []
            for ident in CAPTURE_IDS:
                name = CONSUMER + "evidence/captures/" + ident + ".png";put(name, png)
                data["images"].append(dict(receipt(name), name=ident))
                images.append(dict(receipt(name), observations="Synthetic receipt test only"))
        put(CONSUMER + "evidence/" + filename, data)
    stages = []
    for name in ("parser", "logical", "render"):
        row = {"name": name, "exit_code": 0, "fatal_or_script_messages": []}
        for stream in ("stdout", "stderr"):
            logname = CONSUMER + "evidence/" + name + "." + stream + ".log"
            put(logname, b"fixture" if stream == "stdout" else b"")
            row[stream] = receipt(logname)
        stages.append(row)
    put(CONSUMER + "evidence/runner_report.json", {"schema": "living_town.reserve_consumer_runner.v1", "status": "PASS", "stages": stages,
        "consumer": receipt(CONSUMER + "smoke.gd"), "project": receipt(CONSUMER + "project.godot"), "export_manifest": receipt(ASSETS + "export_manifest.json"),
        "native_manifest": receipt(SOURCE + "town_manifest.json"), "logical_report": receipt(CONSUMER + "evidence/logical_report.json"), "render_report": receipt(CONSUMER + "evidence/render_report.json")})
    put(EVIDENCE + "reserve_visual_review.json", {"status": "PASS", "visually_reviewed": True, "reviewer_kind": "agent", "source_blend_sha256": native_sha,
                                               "export_manifest_sha256": receipt(ASSETS + "export_manifest.json")["sha256"], "images": images})
    put("START_HERE.md", b"Synthetic fixture; not a delivery")
    names = payload_names(Reader(directory=base)) + ["START_HERE.md"]
    rows = [receipt(name) for name in names]
    put(FILE_MANIFEST, {"schema": "living_town.reserve_package.v1", "release_tag": RELEASE_TAG, "source_blend_sha256": native_sha,
                        "source_freeze_sha256": receipt(EVIDENCE + "final_source_freeze.json")["sha256"],
                        "export_manifest_sha256": receipt(ASSETS + "export_manifest.json")["sha256"], "files": rows,
                        "file_count": len(rows), "payload_bytes": sum(r["bytes"] for r in rows)})


def self_test():
    class PureChecks(unittest.TestCase):
        def test_relative_paths(self):
            self.assertEqual(relative_name("reserve/a.glb"), "reserve/a.glb")
            for name in ("../a", "a/../b", "/a", "D:/a", "a\\b", "a//b", "a/./b", "CON.txt", "a. /b"):
                with self.assertRaises(DeliveryError):
                    relative_name(name)

        def test_stream_and_receipts(self):
            with tempfile.TemporaryDirectory() as tmp:
                Path(tmp, "a.txt").write_bytes(b"reserve")
                reader = Reader(directory=tmp)
                record = reader.record("a.txt")
                self.assertEqual(record["sha256"], hashlib.sha256(b"reserve").hexdigest())
                same_receipt(reader, "a.txt", record)
                with self.assertRaises(DeliveryError):
                    same_receipt(reader, "a.txt", dict(record, bytes=8))
                with self.assertRaises(DeliveryError):
                    reader.path("missing")

        def test_pass_check_requires_actual_positive_counts(self):
            pass_checks({"status": "PASS", "checks": [{"name": "x", "passed": True}], "check_count": 1, "failure_count": 0}, boolean=True)
            for report in ({"status": "PASS", "checks": []}, {"status": "PASS", "checks": [{"id": "x", "status": "FAIL"}]}):
                with self.assertRaises(DeliveryError):
                    pass_checks(report)

        def test_glb_portability(self):
            def blob(uri=None):
                doc = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0}], "materials": [{"pbrMetallicRoughness": {}}]}
                if uri:
                    doc["buffers"][0]["uri"] = uri
                data = json.dumps(doc).encode()
                data += b" " * (-len(data) % 4)
                return struct.pack("<4sIIII", b"glTF", 2, 20 + len(data), len(data), 0x4e4f534a) + data
            with tempfile.TemporaryDirectory() as tmp:
                Path(tmp, "good.glb").write_bytes(blob())
                Path(tmp, "external.glb").write_bytes(blob("../private.bin"))
                reader = Reader(directory=tmp)
                glb_json(reader, "good.glb")
                with self.assertRaises(DeliveryError):
                    glb_json(reader, "external.glb")

        def test_stale_v5_fails_closed(self):
            with tempfile.TemporaryDirectory() as tmp:
                target = Path(tmp) / EVIDENCE / "final_source_freeze.json"
                target.parent.mkdir(parents=True)
                target.write_text('{"schema":"living_town.source_freeze.v5"}')
                result = validate(Reader(directory=tmp))
                self.assertEqual(result["status"], "FAIL")
                self.assertIn("V6", result["checks"][0]["error"])

        def test_zip_stream_and_unsafe_members(self):
            for member, expected in (("a.txt", True), ("../escape.txt", False), ("D:/absolute.txt", False)):
                memory = io.BytesIO()
                with zipfile.ZipFile(memory, "w", compression=zipfile.ZIP_STORED) as writer:
                    writer.writestr(member, b"small synthetic fixture")
                memory.seek(0)
                if expected:
                    reader = Reader(archive=memory)
                    self.assertEqual(reader.record("a.txt")["bytes"], 23)
                    reader.close()
                else:
                    with self.assertRaises(DeliveryError):
                        Reader(archive=memory)

        def test_complete_curated_receipt_contract_and_stale_image(self):
            with tempfile.TemporaryDirectory() as tmp:
                _synthetic_fixture(tmp)
                result = validate(Reader(directory=tmp), packaged=True)
                self.assertEqual(result["status"], "PASS", result)
                image = Path(tmp) / SOURCE / "renders/reserve_v6/01_reserve_overview.png"
                image.write_bytes(image.read_bytes() + b"changed")
                broken = validate(Reader(directory=tmp), packaged=True)
                self.assertEqual(broken["status"], "FAIL")
                failures = [c["id"] for c in broken["checks"] if c["status"] == "FAIL"]
                self.assertIn("fifteen_current_final_native_renders", failures)
                self.assertIn("complete_package_inventory_and_streamed_checksums", failures)

        def test_complete_zip_receipts_and_unlisted_payload(self):
            with tempfile.TemporaryDirectory() as tmp:
                _synthetic_fixture(tmp)
                memory = io.BytesIO()
                with zipfile.ZipFile(memory, "w", compression=zipfile.ZIP_STORED) as writer:
                    for path in sorted(Path(tmp).rglob("*")):
                        if path.is_file():
                            writer.write(path, path.relative_to(tmp).as_posix())
                memory.seek(0)
                reader = Reader(archive=memory)
                result = validate(reader, packaged=True)
                reader.close()
                self.assertEqual(result["status"], "PASS", result)
                memory.seek(0)
                with zipfile.ZipFile(memory, "a", compression=zipfile.ZIP_STORED) as writer:
                    writer.writestr("unlisted_history.txt", b"must reject unexpected payload")
                memory.seek(0)
                reader = Reader(archive=memory)
                result = validate(reader, packaged=True)
                reader.close()
                self.assertEqual(result["status"], "FAIL")
                self.assertIn("Unexpected", result["checks"][-1]["error"])

        def test_game_only_delivery_is_complete(self):
            with tempfile.TemporaryDirectory() as tmp:
                _synthetic_fixture(tmp, high_detail=False)
                result = validate(Reader(directory=tmp), packaged=True)
                self.assertEqual(result["status"], "PASS", result)
                assets = next(c for c in result["checks"] if c["id"] == "current_self_contained_exports_and_independent_verification")
                self.assertEqual(assets["detail"]["glbs"], 72)
                self.assertIsNone(assets["detail"]["high_detail_triangles"])

        def test_added_native_checks_and_square_topography_are_record_driven(self):
            with tempfile.TemporaryDirectory() as tmp:
                _synthetic_fixture(tmp, high_detail=False, square_topomap=True, extra_audit_check=True)
                result = validate(Reader(directory=tmp), packaged=True)
                self.assertEqual(result["status"], "PASS", result)

        def test_historical_stair_negative_control_is_bound_and_separate(self):
            with tempfile.TemporaryDirectory() as tmp:
                _synthetic_fixture(tmp, high_detail=False)
                result = validate(Reader(directory=tmp), packaged=True)
                self.assertEqual(result["status"], "PASS", result)
                control = next(c for c in result["checks"] if c["id"] == "current_stair_gate_and_historical_negative_control")
                self.assertEqual(control["detail"]["historical_failure_count"], 1950)
                self.assertEqual(control["detail"]["current_gate_status"], "PASS")
                self.assertIn(EVIDENCE + "reserve_stair_land_negative_control.json", payload_names(Reader(directory=tmp)))

        def test_stair_control_rejects_stale_module_or_misleading_rejection(self):
            for mutation in ("stale_module", "observed_pass", "wrong_count", "same_native", "missing"):
                with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as tmp:
                    _synthetic_fixture(tmp, high_detail=False)
                    path = Path(tmp) / EVIDENCE / "reserve_stair_land_negative_control.json"
                    row = json.loads(path.read_text())
                    if mutation == "missing":
                        path.unlink()
                    else:
                        if mutation == "stale_module":
                            row["audit_module"]["sha256"] = "a" * 64
                        elif mutation == "observed_pass":
                            row["gate"]["observed_status"] = "PASS"
                        elif mutation == "wrong_count":
                            row["gate"]["failure_count"] = 0
                        else:
                            row["known_bad_native"]["sha256"] = Reader(directory=tmp).record(SOURCE + "living_town_complete.blend")["sha256"]
                        path.write_text(json.dumps(row))
                    result = validate(Reader(directory=tmp))
                    control = next(c for c in result["checks"] if c["id"] == "current_stair_gate_and_historical_negative_control")
                    self.assertEqual(control["status"], "FAIL", result)

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PureChecks))
    return result.wasSuccessful()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--repo", type=Path)
    group.add_argument("--delivery", type=Path)
    group.add_argument("--archive", type=Path)
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--consumer-evidence", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    opt = parser.parse_args()
    if opt.self_test:
        raise SystemExit(0 if self_test() else 1)
    require(opt.repo or opt.delivery or opt.archive, "Choose --repo, --delivery or --archive")
    reader = Reader(directory=opt.delivery, archive=opt.archive, repo=opt.repo, assets=opt.assets, consumer_evidence=opt.consumer_evidence)
    try:
        result = validate(reader, packaged=bool(opt.delivery or opt.archive))
    finally:
        reader.close()
    if opt.report:
        opt.report.parent.mkdir(parents=True, exist_ok=True)
        opt.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
