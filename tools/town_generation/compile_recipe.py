"""Compile the real town inputs into a deterministic generation recipe.

This is an executable planning prototype, not a town renderer or Infinigen
installer. It never calls a shell, Blender, a model, or an upstream generator.
The recipe explicitly lists the missing full-town refinement adapters.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def sub_seed(seed, namespace, identity):
    """Stable across input ordering and unrelated asset insertions."""
    return int.from_bytes(hashlib.sha256(
        f"{seed}\0{namespace}\0{identity}".encode()).digest()[:4], "big")


def indexed(rows, label):
    result = {}
    for row in rows:
        identity = row["id"]
        if not isinstance(identity, str) or not identity or identity in result:
            raise ValueError(f"Invalid or duplicate {label} id: {identity}")
        result[identity] = row
    return result


def world_xy(building, local):
    angle = math.radians(building["yaw_degrees"])
    c, s = math.cos(angle), math.sin(angle)
    x, y = building["center"]
    return [x + local[0] * c - local[1] * s,
            y + local[0] * s + local[1] * c]


def build_recipe(profile, inputs, hashes):
    seed = profile["seed"]
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed < 2**32:
        raise ValueError("Seed must be an unsigned 32-bit integer")
    if inputs["interiors"]["masterplan_sha256"] != hashes["masterplan"]:
        raise ValueError("Interior plan is bound to another masterplan")
    terrain = inputs["terrain"]
    if terrain["masterplan_sha256"] != hashes["masterplan"] or terrain["landscape_plan_sha256"] != hashes["landscape"]:
        raise ValueError("Terrain plan is bound to another masterplan/landscape")
    buildings = indexed(inputs["masterplan"]["buildings"], "town building")
    interiors = indexed(inputs["interiors"]["buildings"], "interior building")
    pads = indexed(terrain["building_pads"], "building pad")
    if set(buildings) != set(interiors) or set(buildings) != set(pads):
        raise ValueError("Town, interior and pad ids must agree")
    focus = profile["focus_buildings"]
    if len(set(focus)) != len(focus) or not set(focus) <= set(buildings):
        raise ValueError("Focus ids must identify distinct town buildings")
    quality = profile["proposed_quality"]
    town = []
    room_ids, asset_ids = set(), set()
    for identity in sorted(buildings):
        building, interior, pad = buildings[identity], interiors[identity], pads[identity]
        dimensions = [building["width"], building["depth"], interior["floor_height_m"]]
        if not all(math.isfinite(v) and v > 0 for v in dimensions):
            raise ValueError("Building dimensions must be positive finite metres")
        if interior["floors"] != building["floors"] or len(interior["levels"]) != building["floors"]:
            raise ValueError("Building floors and room plan disagree")
        if interior["footprint_m"] != [building["width"], building["depth"]]:
            raise ValueError("Interior footprint and target building disagree")
        level_ids = [row["level"] for row in interior["levels"]]
        if any(type(value) is not int for value in level_ids) or sorted(level_ids) != list(range(building["floors"])):
            raise ValueError("Floor levels must cover each storey exactly once")
        levels = []
        for level in sorted(interior["levels"], key=lambda row: row["level"]):
            rooms = []
            for room in sorted(level["rooms"], key=lambda row: row["id"]):
                if not isinstance(room["id"], str) or not room["id"] or room["id"] in room_ids:
                    raise ValueError("Invalid or duplicate room id")
                room_ids.add(room["id"])
                for asset in room.get("assets", []):
                    if not isinstance(asset["id"], str) or not asset["id"] or asset["id"] in asset_ids:
                        raise ValueError("Invalid or duplicate asset id")
                    asset_ids.add(asset["id"])
                assets = [{"id": asset["id"], "kind": asset["kind"],
                           "seed": sub_seed(seed, "asset", asset["id"]),
                           "target_local_center_m": asset["center_m"],
                           "target_world_xy_m": world_xy(building, asset["center_m"]),
                           "target_dimensions_m": asset["dimensions_m"],
                           "world_yaw_degrees": building["yaw_degrees"] + asset["rotation_degrees"],
                           "fit_and_working_front_validation_required": True}
                          for asset in sorted(room.get("assets", []), key=lambda row: row["id"])]
                rooms.append({"id": room["id"], "purpose": room["purpose"],
                              "bounds_local_m": room["bounds_m"],
                              "door_gaps": room.get("door_gaps", []),
                              "circulation_keepouts": room.get("circulation_keepouts", []),
                              "assets": assets})
            levels.append({"level": level["level"],
                           "finished_floor_world_z_m": pad["pad_base_z_m"] + level["finished_floor_local_z_m"],
                           "rooms": rooms})
        first_floor = next(row for row in levels if row["level"] == 0)["finished_floor_world_z_m"]
        if abs(first_floor - pad["finished_floor_z_m"]) > 1e-6:
            raise ValueError("Ground floor and recorded terrain pad disagree")
        angle = math.radians(building["yaw_degrees"])
        town.append({"id": identity, "kind": building["kind"], "seed": sub_seed(seed, "building", identity),
                     "center_xy_m": building["center"], "yaw_degrees": building["yaw_degrees"],
                     "front_outward_xy": [math.sin(angle), -math.cos(angle)],
                     "pad_base_z_m": pad["pad_base_z_m"], "threshold_xy_m": pad["threshold_xy"],
                     "levels": levels,
                     "facade": {"width_m": dimensions[0], "storey_height_m": dimensions[2],
                                "bake_pixels": quality["focus_facade_bake_pixels"] if identity in focus else quality["other_facade_bake_pixels"],
                                "fine_scan_repeat_m": quality["fine_plaster_repeat_metres"],
                                "opening_and_weather_masks": "DERIVE_FROM_TARGET_GEOMETRY",
                                "whole_vignette_replacement": False}})
    reserve_rows = indexed(inputs["reserve"]["buildings"], "reserve building")
    if set(reserve_rows) & set(buildings):
        raise ValueError("Reserve and town building ids overlap")
    reserve = [{"id": row["id"], "kind": row["kind"], "seed": sub_seed(seed, "building", row["id"]),
                "center_xy_m": row["center"], "yaw_degrees": row["yaw_degrees"],
                "pad_level_m": row["pad_level_m"],
                "finished_floor_world_z_m": row["pad_level_m"] + row["finished_floor_offset_m"],
                "entry_threshold_m": row["entry_threshold_m"], "interior_program": row["program"],
                "interior_detail_adapter": "REQUIRES_RESERVE_AMENITIES_FACTORY_ADAPTER"}
               for row in (reserve_rows[key] for key in sorted(reserve_rows))]
    for row in reserve:
        if len(row["entry_threshold_m"]) != 3 or abs(row["finished_floor_world_z_m"] - row["entry_threshold_m"][2]) > 1e-6:
            raise ValueError("Reserve threshold and its own floor offset disagree")
    stages = [
        ("plan", [], "compiled", "Topography, irregular roads/parcels, stable functional ids and source bindings"),
        ("layout", ["plan"], "adapter_required", "Cheap shells/rooms; evaluate circulation, grades and furniture relations before detail"),
        ("assets", ["layout"], "adapter_required", "Fit detailed factory assets to target dimensions, openings and support/facing relations"),
        ("landscape", ["layout"], "adapter_required", "Terrain-conditioned vegetation, horticulture and reserve trail/bridge contacts"),
        ("materials", ["assets", "landscape"], "adapter_required", "Metric microdetail plus contextual meso/macro variation, baked portable PBR"),
        ("review_slice", ["materials"], "adapter_required", "Matched concept/street/interior/terrain views and actual GLB consumer check"),
        ("town_chunks", ["review_slice"], "adapter_required", "Scale accepted factories with stable sub-seeds, cached chunks and shared meshes"),
        ("delivery", ["town_chunks"], "adapter_required", "Native/GLB, explicit collision/navigation products, consumer tests and narrated walkthrough")]
    return {"schema": "living_town.generation_recipe.v1", "status": "COMPILED_NOT_GENERATED",
            "seed": seed, "style": profile["style"], "input_sha256": hashes,
            "upstream_references": profile["upstream_references"], "runtime": profile["runtime"],
            "proposed_quality": quality, "first_integration_slice_ids": focus,
            "baseline_role": "Reusable starting geometry/program; user authorizes replacement and replanning after comparison",
            "historical_landscape_source_bindings": inputs["landscape"].get("source_bindings", {}),
            "historical_binding_policy": "Baseline siting evidence, not a blanket current-source equality requirement",
            "town": town, "reserve": reserve,
            "counts": {"town_buildings": len(town), "reserve_buildings": len(reserve),
                       "town_floors": sum(len(b["levels"]) for b in town),
                       "town_rooms": sum(len(l["rooms"]) for b in town for l in b["levels"]),
                       "town_furnishings": sum(len(r["assets"]) for b in town for l in b["levels"] for r in l["rooms"])},
            "stages": [{"id": name, "depends_on": deps, "implementation": state, "purpose": purpose,
                        "seed": sub_seed(seed, "stage", name)} for name, deps, state, purpose in stages],
            "missing_integration": ["Parameterized full-town architecture/material/furniture/foliage adapters",
                                    "Explicit output-root/seed APIs; existing reserve builder writes fixed authoring paths",
                                    "Topography-aware replanning and concept-matched first slice",
                                    "Chunked instance-preserving export, LOD/collision/navigation and performance proof"],
            "blender_executed": False, "infinigen_executed": False, "inference_executed": False}


def compile_recipe(root, profile_path, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if output.exists():
        raise FileExistsError(output)
    profile_path = Path(profile_path).resolve(strict=True)
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    if profile.get("schema") != "living_town.generation_profile.v1":
        raise ValueError("Unknown generation profile")
    inputs, hashes, source_paths = {}, {}, {}
    for role, name in profile["inputs"].items():
        path = (root / name).resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError("Input escapes repository")
        inputs[role] = json.loads(path.read_text(encoding="utf-8"))
        hashes[role], source_paths[role] = sha(path), name
    bound_modules = {}
    for name in profile["source_modules"]:
        path = (root / name).resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError("Source module escapes repository")
        bound_modules[name] = sha(path)
    for name, wanted in inputs["reserve"]["source_bindings"].items():
        path = (root / "art/living_town" / name).resolve(strict=True)
        if not path.is_relative_to(root) or sha(path) != wanted:
            raise ValueError("Reserve source binding differs: " + name)
    recipe = build_recipe(profile, inputs, hashes)
    recipe.update({"profile_sha256": sha(profile_path), "compiler_sha256": sha(Path(__file__)),
                   "input_paths": source_paths, "source_module_sha256": bound_modules})
    encoded = (json.dumps(recipe, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    output.mkdir(parents=True, exist_ok=False)
    (output / "generation_recipe.json").write_bytes(encoded)
    return recipe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO)
    parser.add_argument("--profile", type=Path, default=Path(__file__).with_name("breton_summer.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    recipe = compile_recipe(args.root, args.profile, args.output)
    print(json.dumps({"status": recipe["status"], "counts": recipe["counts"],
                      "output": str(args.output / "generation_recipe.json")}))


if __name__ == "__main__":
    main()
