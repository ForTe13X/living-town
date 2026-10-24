"""Hash-bound whole-town coverage inventory; never equates a PASS label with proof.

This is an offline, standard-library auditor. It reads authored plans, generated
records and existing audit receipts, not Blender geometry. Native results retain
their original scope. In particular, a room zone is not an asserted closed room,
and aggregate geometry checks do not establish visual quality or engine behavior.

Run from any directory::

    python tools/town_upgrade/building_inventory.py --output build/town_upgrade/audit_notes

Exit 0 means structurally consistent inputs; it does not mean visual acceptance.
Exit 1 means inventory discrepancies. Overall coverage stays INCOMPLETE while
required per-building/per-floor proof is absent.
"""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path


SCHEMA = "living_town.whole_town_inventory.v1"
REPO = Path(__file__).resolve().parents[2]
FLOOR_CHECKLIST = (
    "native_floor_slab_and_owner", "native_room_and_fixture_ownership",
    "native_partition_apertures", "native_furniture_pose_and_clearance",
    "native_exterior_windows", "visual_interior",
)
BUILDING_CHECKLIST = ("native_entrance", "visual_exterior")
CIRCULATION_NAMES = {"hall", "stairwell", "lower_landing", "upper_landing"}


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def planning_record(buildings):
    """Exact adapter representation used by audit_prepared_plans, without imports."""
    rows = [{**b, "floors": b["floors"] if isinstance(b["floors"], int)
             else b.get("floor_count", len(b["levels"]))} for b in buildings]
    return {"buildings": rows, "floor_count": sum(b["floors"] for b in rows),
            "room_count": sum(len(f["rooms"]) for b in rows for f in b["levels"])}


def semantic_plan_sha256(buildings):
    # This is the documented serialization in interior_design.audit_plan, not
    # the raw interiors.json hash. Both hashes are retained in the report.
    return hashlib.sha256(json.dumps(planning_record(buildings), indent=2).encode("utf-8")).hexdigest()


def index_records(records, label, issues):
    result = {}
    for record in records:
        ident = record.get("id")
        if not ident:
            issues.append({"kind": "missing_id", "source": label})
        elif ident in result:
            issues.append({"kind": "duplicate_id", "source": label, "id": ident})
        else:
            result[ident] = record
    return result


def compare_ids(expected, actual, label, issues):
    missing, extra = sorted(set(expected)-set(actual)), sorted(set(actual)-set(expected))
    if missing or extra:
        issues.append({"kind": "id_set_mismatch", "source": label,
                       "missing": missing, "unexpected": extra})
    return not missing and not extra


def floor_rows(building):
    # Native manifests duplicate the same floors under floors and levels.
    # Prefer levels and count each floor exactly once.
    return building.get("levels", building.get("floors", []))


def normalize_reserve(record):
    """Reserve plan has programs; exact room geometry lives in its build manifest."""
    result = deepcopy(record)
    levels = sorted({r.get("floor_index", 0) for r in record.get("rooms", [])})
    result["floors"] = len(levels)
    result["levels"] = []
    for level in levels:
        rooms = []
        for room in record["rooms"]:
            if room.get("floor_index", 0) != level:
                continue
            room = deepcopy(room)
            room["assets"] = [a for a in record.get("assets", []) if a.get("room_id") == room["id"]]
            rooms.append(room)
        result["levels"].append({"level": level, "rooms": rooms,
                                 "partitions": record.get("partitions", []),
                                 "finished_floor_local_z_m": record.get("finished_floor_local_z_m")})
    return result


def validate_levels(expected, generated, expected_floors, label, issues):
    prior_issue_count = len(issues)
    expected_levels = floor_rows(expected)
    observed_levels = floor_rows(generated)
    if not isinstance(expected_levels, list) or not isinstance(observed_levels, list):
        issues.append({"kind": "missing_floor_definition", "source": label})
        return False
    levels = [f.get("level") for f in expected_levels]
    observed = [f.get("level") for f in observed_levels]
    valid = True
    required = list(range(expected_floors))
    if sorted(levels) != required or sorted(observed) != required:
        issues.append({"kind": "floor_coverage_mismatch", "source": label,
                       "expected_levels": required, "planned": levels, "generated": observed})
        valid = False
    emap, gmap = {f.get("level"): f for f in expected_levels}, {f.get("level"): f for f in observed_levels}
    for level, floor in emap.items():
        other = gmap.get(level, {})
        for key in ("partitions", "finished_floor_local_z_m", "slab_voids", "stair_to_next_level"):
            if floor.get(key) != other.get(key):
                issues.append({"kind": "floor_geometry_record_mismatch", "source": f"{label}:L{level}", "field": key})
                valid = False
        rooms = index_records(floor.get("rooms", []), f"{label}:L{level}:planned_rooms", issues)
        generated_rooms = index_records(other.get("rooms", []), f"{label}:L{level}:generated_rooms", issues)
        valid &= compare_ids(rooms, generated_rooms, f"{label}:L{level}:rooms", issues)
        for room_id, room in rooms.items():
            observed_room = generated_rooms.get(room_id, {})
            for key in ("purpose", "bounds_m", "door_gaps", "nonrectangular_exclusions_m"):
                if room.get(key) != observed_room.get(key):
                    issues.append({"kind": "room_program_or_geometry_mismatch", "source": room_id, "field": key})
                    valid = False
            assets = index_records(room.get("assets", []), room_id+":planned_assets", issues)
            generated_assets = index_records(observed_room.get("assets", []), room_id+":generated_assets", issues)
            valid &= compare_ids(assets, generated_assets, room_id+":assets", issues)
            for asset_id, asset in assets.items():
                for key in ("kind", "center_m", "dimensions_m", "rotation_degrees", "footprint_m", "integrated_fixtures"):
                    if asset.get(key) != generated_assets.get(asset_id, {}).get(key):
                        issues.append({"kind": "fixture_pose_or_program_mismatch", "source": asset_id, "field": key})
                        valid = False
    return valid and len(issues) == prior_issue_count


def bound_receipt(receipt, required, *, checks=()):
    """All requested bindings/checks must match; a top-level PASS alone is inert."""
    reasons = []
    if receipt.get("status") != "PASS":
        reasons.append("receipt status is not PASS")
    for dotted, value in required.items():
        actual = receipt
        for key in dotted.split("."):
            actual = actual.get(key) if isinstance(actual, dict) else None
        if value is None or actual != value:
            reasons.append(f"binding mismatch: {dotted}")
    table = {c.get("id"): c for c in receipt.get("checks", [])}
    for ident in checks:
        if table.get(ident, {}).get("status") != "PASS":
            reasons.append("missing or failed check: "+ident)
    return {"accepted": not reasons, "reasons": reasons,
            "binding_fields": required, "required_checks": list(checks)}


def coverage(status="missing", evidence=None, scope=None):
    return {"status": status, "evidence": evidence, "scope": scope}


def aggregate_coverage(accepted, check_id, evidence, scope):
    return coverage("verified" if accepted else "missing", evidence+"#"+check_id, scope)


def room_inventory(room, geometry, plan_checks):
    purpose = room.get("purpose", "")
    circulation = room.get("name", "").lower() in CIRCULATION_NAMES or "circulation" in purpose.lower()
    return {"id": room["id"], "name": room.get("name"), "purpose": purpose,
            "zone_type": "circulation_zone" if circulation else "authored_room_zone",
            "enclosure": "not_asserted_by_inventory",
            "bounds_m": room.get("bounds_m"), "finish": room.get("finish"),
            "nonrectangular_exclusions_m": room.get("nonrectangular_exclusions_m", []),
            "geometry_status": geometry["status"],
            "plan_checks": plan_checks.get(room["id"], []),
            "door_access_references": room.get("door_gaps", []),
            "circulation_keepouts_m": room.get("circulation_keepouts", []),
            "furniture_clearances_m": room.get("furniture_clearances_m", []),
            "furnishings": [{k: a[k] for k in (
                "id", "kind", "center_m", "dimensions_m", "rotation_degrees", "footprint_m",
                "integrated_fixtures", "integrated_seating", "detail_source", "object_names") if k in a}
                for a in room.get("assets", [])],
            "omitted_optional_assets": room.get("omitted_optional_assets", [])}


def partition_openings(floor):
    return [{"partition_index": i, "axis": p.get("axis"),
             "coordinate_m": p.get("coordinate_m"), "span_m": p.get("span_m"), **opening}
            for i, p in enumerate(floor.get("partitions", [])) for opening in p.get("openings", [])]


def build_inventory(documents, hashes, evidence_paths=None):
    """Public pure function, usable with small negative-control fixture documents."""
    evidence_paths = evidence_paths or {}
    issues, evaluations, buildings = [], {}, []
    master, interior, manifest = (documents.get(k, {}) for k in ("masterplan", "interior_plan", "town_manifest"))
    reserve, expansion, generated = (documents.get(k, {}) for k in ("reserve_plan", "territory_plan", "expansion_interiors"))
    expansion_manifest = documents.get("expansion_manifest", {})
    core_ids = index_records(master.get("buildings", []), "masterplan", issues)
    core_plans = index_records(interior.get("buildings", []), "interior_plan", issues)
    core_built = index_records(manifest.get("buildings", []), "town_manifest.buildings", issues)
    core_generated = index_records(manifest.get("interiors", []), "town_manifest.interiors", issues)
    reserve_ids = index_records(reserve.get("buildings", []), "reserve_plan", issues)
    amenities = manifest.get("reserve_amenities", {})
    reserve_generated = index_records([normalize_reserve(b) for b in amenities.get("buildings", [])], "reserve_amenities", issues)
    expansion_ids = index_records(expansion.get("buildings", []), "territory_plan", issues)
    expansion_built = index_records(expansion_manifest.get("buildings", []), "expansion_manifest", issues)
    expansion_generated = index_records(generated.get("buildings", []), "expansion_interiors", issues)
    for expected, actual, label in (
        (core_ids, core_plans, "urban_plan"), (core_ids, core_built, "urban_shell_manifest"),
        (core_ids, core_generated, "urban_interior_manifest"),
        (reserve_ids, reserve_generated, "reserve_interior_manifest"),
        (expansion_ids, expansion_built, "expansion_shell_manifest"),
        (expansion_ids, expansion_generated, "expansion_interior_manifest"),
    ):
        compare_ids(expected, actual, label, issues)
    all_ids = [*core_ids, *reserve_ids, *expansion_ids]
    duplicates = [k for k, v in Counter(all_ids).items() if v > 1]
    if duplicates:
        issues.append({"kind": "cross_group_duplicate_ids", "ids": duplicates})

    core_audit = documents.get("core_native_audit", {})
    reserve_audit = documents.get("reserve_native_audit", {})
    expansion_audit = documents.get("expansion_native_audit", {})
    core_required = {"source_blend_sha256": hashes.get("baseline_native"),
                     "masterplan_sha256": hashes.get("masterplan"),
                     "interior_plan_sha256": hashes.get("interior_plan"),
                     "interior_module_sha256": hashes.get("interior_module")}
    evaluations["urban_native"] = bound_receipt(core_audit, core_required)
    reserve_required = {"source_blend_sha256": hashes.get("baseline_native")}
    # Source bindings are schema-defined; require every recorded input, not
    # only the selected reserve_plan binding.
    binding_aliases = {"masterplan_sha256": "masterplan", "terrain_plan_sha256": "terrain_plan",
                      "landscape_plan_sha256": "landscape_plan", "terrain_profile_sha256": "terrain_profile",
                      "interior_plan_sha256": "interior_plan", "interior_module_sha256": "interior_module",
                      "reserve_plan_sha256": "reserve_plan", "reserve_plan_module_sha256": "reserve_plan_module",
                      "reserve_environment_module_sha256": "reserve_environment_module",
                      "reserve_amenities_module_sha256": "reserve_amenities_module"}
    for field, alias in binding_aliases.items():
        reserve_required["source_bindings."+field] = hashes.get(alias)
    evaluations["reserve_native"] = bound_receipt(reserve_audit, reserve_required)
    evaluations["expansion_native"] = bound_receipt(expansion_audit, {"native_sha256": hashes.get("expansion_native")})
    expansion_manifest_bound = (expansion_manifest.get("plan", {}).get("sha256") == hashes.get("territory_plan")
                                and expansion_manifest.get("native", {}).get("sha256") == hashes.get("expansion_native"))
    evaluations["expansion_native"]["accepted"] &= expansion_manifest_bound
    if not expansion_manifest_bound:
        evaluations["expansion_native"]["reasons"].append("manifest plan/native binding mismatch")

    plan_audits = {"urban": documents.get("core_plan_audit", {}),
                   "expansion": documents.get("expansion_actual_interior_audit", {}).get("navigation_privacy", {})}
    expected_plan_hashes = {"urban": hashes.get("interior_plan"),
                            "expansion": semantic_plan_sha256(list(expansion_generated.values())) if expansion_generated else None}
    plan_checks = {"urban": {}, "reserve": {}, "expansion": {}}
    for group, audit in plan_audits.items():
        bound = bound_receipt(audit, {"interior_plan_sha256": expected_plan_hashes[group],
                                      "interior_module_sha256": hashes.get("interior_module")})
        evaluations[group+"_plan"] = bound
        if bound["accepted"]:
            for key in ("essential_fixture_coverage", "privacy_enclosure_checks",
                        "sleeping_room_exterior_boundary_checks", "nonrectangular_room_checks"):
                for check in audit.get(key, []):
                    if check.get("pass"):
                        plan_checks[group].setdefault(check["room"], []).append(key)
            for key in ("functional_clearances", "furniture_density"):
                for check in audit.get("furniture_composition", {}).get(key, []):
                    if check.get("pass"):
                        plan_checks[group].setdefault(check["room"], []).append(key)
    visual = documents.get("old_visual_review", {})
    evaluations["old_visual_review"] = bound_receipt(visual, {
        "source_blend_sha256": hashes.get("baseline_native"),
        "source_interior_plan_sha256": hashes.get("interior_plan"),
        "source_interior_module_sha256": hashes.get("interior_module")})
    evaluations["old_visual_review"]["scope"] = "Selected historic images only; never all-building/all-floor coverage."

    def native_check(group, check_id, count_key=None, count=None):
        audit = core_audit if group == "urban" else reserve_audit
        evaluation = evaluations["urban_native" if group == "urban" else "reserve_native"]
        check = next((c for c in audit.get("checks", []) if c.get("id") == check_id), {})
        detail = check.get("detail", {})
        accepted = evaluation["accepted"] and check.get("status") == "PASS"
        if count_key:
            accepted &= detail.get(count_key) == count
        if any(detail.get(k) for k in ("errors", "failures", "failure_count", "room_errors", "asset_errors", "level_errors", "cover_errors")):
            accepted = False
        return aggregate_coverage(accepted, check_id, evidence_paths.get(group+"_native", group+"_native_audit"),
                                  "Hash-bound exhaustive aggregate check, not an individual image review.")

    core_counts = {"floors": sum(b["floors"] for b in core_ids.values()),
                   "rooms": sum(len(f["rooms"]) for b in core_plans.values() for f in floor_rows(b)),
                   "assets": sum(len(r.get("assets", [])) for b in core_plans.values() for f in floor_rows(b) for r in f["rooms"])}
    reserve_counts = {"rooms": sum(len(b.get("rooms", [])) for b in amenities.get("buildings", [])),
                      "assets": sum(len(b.get("assets", [])) for b in amenities.get("buildings", []))}
    geometries = {
        "urban": {
            "native_floor_slab_and_owner": native_check("urban", "all89_native_floor_levels_and_cover_ownership", "levels", core_counts["floors"]),
            "native_room_and_fixture_ownership": native_check("urban", "native_room_and_reusable_furniture_ownership", "room_zones", core_counts["rooms"]),
            "native_partition_apertures": native_check("urban", "native_partition_apertures_are_geometric"),
            "native_furniture_pose_and_clearance": native_check("reserve", "core_757_actual_furniture_mesh_poses_match_refined_plan", "assemblies", core_counts["assets"]),
        },
        "reserve": {
            "native_floor_slab_and_owner": native_check("reserve", "21_reserve_amenities_actual_ownership_floors_and_entry_steps", "buildings", len(reserve_ids)),
            "native_room_and_fixture_ownership": native_check("reserve", "21_reserve_amenities_actual_ownership_floors_and_entry_steps", "rooms", reserve_counts["rooms"]),
            "native_partition_apertures": native_check("reserve", "reserve_actual_partitions_and_entrance_holes"),
            "native_furniture_pose_and_clearance": native_check("reserve", "reserve_furnishing_actual_world_mesh_poses", "assemblies", reserve_counts["assets"]),
        },
        "expansion": {},
    }
    # Mesh-pose equality and sampled body clearance are separate requirements.
    for group, check_id in (("urban", "core_actual_furniture_front_and_door_body_clearance"),
                            ("reserve", "reserve_actual_fixture_approaches_and_entry_body_clearance")):
        clearance = native_check("reserve", check_id)
        geometries[group]["native_furniture_pose_and_clearance"]["clearance_evidence"] = clearance
        if clearance["status"] != "verified":
            geometries[group]["native_furniture_pose_and_clearance"]["status"] = "missing"

    for group, ids, plans, generated_rows, shell_rows in (
        ("urban", core_ids, core_plans, core_generated, core_built),
        ("reserve", reserve_ids, reserve_generated, reserve_generated, reserve_generated),
        ("expansion", expansion_ids, expansion_generated, expansion_generated, expansion_built),
    ):
        for ident, source in ids.items():
            plan, built = plans.get(ident, {}), generated_rows.get(ident, {})
            expected_floors = source.get("floors", 1)
            valid = validate_levels(plan, built, expected_floors, ident, issues)
            shell = shell_rows.get(ident, {})
            shell_floors = shell.get("floor_count", shell.get("floors", expected_floors))
            if isinstance(shell_floors, list):
                shell_floors = len(shell_floors)
            if shell_floors != expected_floors:
                issues.append({"kind": "shell_floor_count_mismatch", "id": ident,
                               "expected": expected_floors, "actual": shell_floors})
                valid = False
            native = deepcopy(geometries[group]) if valid else {}
            floors = []
            level_map = {f.get("level"): f for f in floor_rows(plan)}
            for level in range(expected_floors):
                floor = level_map.get(level, {})
                evidence = {key: deepcopy(native.get(key, coverage())) for key in FLOOR_CHECKLIST}
                rooms = [room_inventory(r, evidence["native_room_and_fixture_ownership"], plan_checks[group])
                         for r in floor.get("rooms", [])]
                floors.append({"level": level, "status": "missing", "expectation_present": bool(floor),
                               "finished_floor_local_z_m": floor.get("finished_floor_local_z_m"),
                               "rooms": rooms, "room_zone_count": len(rooms),
                               "furnishing_count": sum(len(r["furnishings"]) for r in rooms),
                               "partitions": floor.get("partitions", []),
                               "authored_partition_openings": partition_openings(floor),
                               "slab_voids": floor.get("slab_voids", []),
                               "stair_to_next_level": floor.get("stair_to_next_level"),
                               "coverage": evidence,
                               "missing_proof": [k for k, v in evidence.items() if v["status"] != "verified"]})
            entry = coverage()
            if group == "reserve" and valid:
                entry = native_check("reserve", "reserve_actual_partitions_and_entrance_holes", "entrances", len(reserve_ids))
            elif group == "expansion" and valid:
                sweep = expansion_audit.get("actual_doorway_sweeps", {})
                pads = {p["id"] for p in expansion_audit.get("pad_contacts", [])}
                accepted = (evaluations["expansion_native"]["accepted"] and ident in pads
                            and sweep.get("buildings") == len(expansion_ids)
                            and not sweep.get("blocked") and sweep.get("width_m", 0) >= .5)
                entry = aggregate_coverage(accepted, "actual_doorway_sweeps", evidence_paths.get("expansion_native", "expansion_native_audit"),
                                           "Half-metre entrance centreline at three heights; not full room clearance.")
            window_count = shell.get("window_aperture_count")
            buildings.append({"id": ident, "group": group, "kind": source.get("kind"),
                              "district": source.get("district"), "center_m": source.get("center_m", source.get("center")),
                              "footprint_m": [source.get("width"), source.get("depth")],
                              "yaw_degrees": source.get("yaw_degrees"), "source_program": source.get("program"),
                              "status": "missing", "expected_floor_count": expected_floors,
                              "generated_inventory_status": "verified" if valid and ident in shell_rows else "missing",
                              "expectation_authority": "canonical_interior_plan" if group == "urban" else
                                  "generated_manifest_only_room_geometry" if group == "reserve" else "expansion_final_generated_interiors",
                              "native_sha256": hashes.get("expansion_native" if group == "expansion" else "baseline_native"),
                              "windows": {"declared_aperture_count": window_count,
                                          "count_status": "declared" if window_count is not None else "missing",
                                          "native_aperture_status": "missing", "per_floor_ledger_status": "missing",
                                          "limit": "Counts never establish actual holes/daylight; old core and reserve recipes lack an exported aperture ledger."},
                              "entrance": {"expected_primary_entrances": 1,
                                           "width_m": shell.get("door_aperture_width_m", shell.get("entry_width_m")),
                                           "state": shell.get("front_door_state"), "evidence": entry},
                              "coverage": {"native_entrance": entry, "visual_exterior": coverage()},
                              "floors": floors})

    totals = Counter()
    groups = {}
    for group in ("urban", "reserve", "expansion"):
        rows = [b for b in buildings if b["group"] == group]
        groups[group] = {"buildings": len(rows), "floors": sum(len(b["floors"]) for b in rows),
                         "room_zones": sum(f["room_zone_count"] for b in rows for f in b["floors"]),
                         "furnishings": sum(f["furnishing_count"] for b in rows for f in b["floors"])}
        totals.update(groups[group])
    coverage_summary = {key: {status: sum(f["coverage"][key]["status"] == status
                                         for b in buildings for f in b["floors"])
                              for status in ("verified", "missing")} for key in FLOOR_CHECKLIST}
    return {"schema": SCHEMA, "status": "INCOMPLETE", "inventory_status": "FAIL" if issues else "PASS",
            "authority": "Offline expectation and evidence coverage inventory; no native scene or engine executed.",
            "input_sha256": hashes, "summary": dict(totals), "groups": groups,
            "floor_coverage_summary": coverage_summary, "evidence_evaluations": evaluations,
            "inventory_issues": issues, "buildings": buildings,
            "limits": ["Source/build records are declarations, not reopened geometry proof.",
                       "Verified native scopes are inherited only from exact-hash exhaustive receipts and preserve their finite-sampling limits.",
                       "Plan room zones include open circulation; enclosure is not inferred from rectangles or names.",
                       "No per-building/per-floor current visual review is supplied by the historic sample-image review.",
                       "This does not test game navigation, material appearance, performance, or character assets."]}


def read_inputs(baseline, expansion):
    scene = expansion / "scene"
    paths = {
        "masterplan": baseline/"masterplan.json", "interior_plan": baseline/"interior_plan.json",
        "town_manifest": baseline/"town_manifest.json", "reserve_plan": baseline/"reserve_plan.json",
        "territory_plan": expansion/"territory_plan.json", "expansion_interiors": scene/"interiors.json",
        "expansion_manifest": scene/"expansion_manifest.json", "baseline_native": baseline/"living_town_complete.blend",
        "expansion_native": scene/"expanded_town.blend", "terrain_plan": baseline/"terrain_plan.json",
        "landscape_plan": baseline/"landscape_plan.json", "terrain_profile": baseline/"tools/terrain_profile.py",
        "interior_module": baseline/"tools/interior_design.py", "reserve_plan_module": baseline/"tools/reserve_plan.py",
        "reserve_environment_module": baseline/"tools/reserve_environment.py",
        "reserve_amenities_module": baseline/"tools/reserve_amenities.py",
        "core_native_audit": baseline/"evidence/native_scene_audit.json",
        "reserve_native_audit": baseline/"evidence/reserve_native_audit.json",
        "core_plan_audit": baseline/"evidence/interior_planning_audit.json",
        "old_visual_review": baseline/"evidence/final_interior_render_review.json",
        "expansion_native_audit": scene/"native_review.json",
        "expansion_actual_interior_audit": scene/"actual_interior_audit.json",
        "expansion_builder": REPO/"tools/town_generation/build_expansion_scene.py",
        "expansion_architecture": REPO/"tools/town_generation/architecture_details.py",
        "expansion_adapter": REPO/"tools/town_generation/interior_adapter.py",
        "core_builder": baseline/"tools/build_living_town.py",
    }
    hashes, documents, bindings = {}, {}, {}
    for alias, path in paths.items():
        if not path.is_file():
            raise FileNotFoundError(f"Required inventory input {alias}: {path}")
        hashes[alias] = sha256(path)
        bindings[alias] = {"path": str(path.resolve()), "sha256": hashes[alias], "bytes": path.stat().st_size}
        if path.suffix == ".json":
            documents[alias] = json.loads(path.read_text(encoding="utf-8-sig"))
    evidence_paths = {"urban_native": str(paths["core_native_audit"].resolve()),
                      "reserve_native": str(paths["reserve_native_audit"].resolve()),
                      "expansion_native": str(paths["expansion_native_audit"].resolve())}
    return documents, hashes, bindings, evidence_paths


def markdown_report(report):
    total = report["summary"]
    lines = ["# Whole-town building and interior coverage", "",
             f"Coverage: **{report['status']}**. Input inventory: **{report['inventory_status']}**.", "",
             f"{total['buildings']} buildings; {total['floors']} floors; {total['room_zones']} authored room zones; "
             f"{total['furnishings']} furnishing assemblies. All counts are enumerated, not estimated.", "",
             "| Group | Buildings | Floors | Room zones | Furnishings |", "|---|---:|---:|---:|---:|"]
    for group, count in report["groups"].items():
        lines.append(f"| {group} | {count['buildings']} | {count['floors']} | {count['room_zones']} | {count['furnishings']} |")
    lines += ["", "## Evidence boundaries", ""] + ["- "+x for x in report["limits"]]
    lines += ["", "| Floor requirement | Verified scope | Missing |", "|---|---:|---:|"]
    for key, counts in report["floor_coverage_summary"].items():
        lines.append(f"| {key} | {counts['verified']} | {counts['missing']} |")
    lines += ["", "## Binding failures and stale receipts", ""]
    for name, evaluation in report["evidence_evaluations"].items():
        if not evaluation["accepted"]:
            lines.append(f"- {name}: "+"; ".join(evaluation["reasons"]))
    lines += ["", "## Source discrepancies", ""]
    lines.extend(["- "+json.dumps(issue, ensure_ascii=False) for issue in report["inventory_issues"]] or ["No ID/floor/fixture inventory discrepancy found."])
    lines += ["", "## Upgrade application", "",
              "Retain canonical IDs, exact poses, pad datums, programs, room geometry and circulation constraints as the baseline contract. "
              "Adapt the expansion facade/material pipeline to these records before replacing the visible old shell. The old shell has "
              "party-wall ownership, market-hall arcades, mansards, cross-gables and offset doors: a blanket call to the generic expansion shell "
              "would discard those features and may place windows into party walls. Preserve each typology and door location.", "",
              "Reuse architecture_details.add_facade_details through an API adapter for original material names, local -Y frontage, "
              "pad datum and door offset. Parameterize its currently centered 1.04 m door and 0.38 m floor assumptions before core reuse. "
              "Use the expansion scan/PBR texture pipeline at metre-scale UVs and export baked texture maps; keep upper covers, front covers, "
              "roofs and semantic owner IDs. Preserve tested interiors; detailed furniture replacements must first reserve their real footprint, "
              "then rerun composition/navigation/privacy and compare generated meshes, as focus_furniture_refinements does.", "",
              "Reserve trailers and food trucks use a different one-floor mobile shell, entry width and floor datum. Keep its manifest "
              "room/asset IDs and chassis; material/detail upgrades need the reserve-specific facade adapter. Its room program currently "
              "has no independent authored room-plan file, so its generated room expectations should be frozen before rebuilding.", "",
              "Rebuild and reopen the final combined scene; emit per-floor room/asset/aperture ledgers and actual geometry checks. "
              "Produce exterior and cutaway/interior views for every listed building and floor. Native geometry PASS cannot replace "
              "visual review of walls, furnishing composition, lighting, texture scale or coherent settlement density.", "",
              "## Per-building and per-floor proof checklist", "",
              "Every floor below also needs its authored room zones, furnishing IDs, partition openings, stair/void records and finishes "
              "from building_inventory.json. A zone does not imply a closed room. Windows need an explicit per-floor native aperture ledger.", ""]
    for building in report["buildings"]:
        lines += [f"### {building['id']} ({building['group']}, {building['kind']})", "",
                  f"- [ ] Exterior visual acceptance; entrance evidence: {building['coverage']['native_entrance']['status']}.",
                  f"- [ ] Native window ledger: declared total {building['windows']['declared_aperture_count']}; verify actual apertures and room daylight."]
        for floor in building["floors"]:
            lines.append(f"- [ ] L{floor['level']:02d}: {floor['room_zone_count']} zones, {floor['furnishing_count']} furnishings; missing: "+", ".join(floor["missing_proof"])+".")
        lines.append("")
    return "\n".join(lines)+"\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-root", type=Path, default=REPO/"art/living_town")
    parser.add_argument("--expansion-run", type=Path, default=REPO/"build/town_generation/territory_v6")
    parser.add_argument("--output", type=Path, default=REPO/"build/town_upgrade/audit_notes")
    args = parser.parse_args(argv)
    documents, hashes, bindings, evidence_paths = read_inputs(args.baseline_root, args.expansion_run)
    report = build_inventory(documents, hashes, evidence_paths)
    report["input_bindings"] = bindings
    report["tool_binding"] = {"path": str(Path(__file__).resolve()), "sha256": sha256(__file__)}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/"building_inventory.json").write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    (args.output/"building_inventory_summary.md").write_text(markdown_report(report), encoding="utf-8")
    print(json.dumps({"inventory_status": report["inventory_status"], "coverage": report["status"],
                      "summary": report["summary"], "issues": len(report["inventory_issues"]), "output": str(args.output.resolve())}))
    return int(report["inventory_status"] != "PASS")


if __name__ == "__main__":
    raise SystemExit(main())
