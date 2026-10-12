"""Stage the frozen, portable town for the existing Godot game.

Run with normal Python, not Blender. The source art package is read-only. The
game receives one optimized GLB, provenance, and a small semantic node catalog;
the high-detail scene and 49 duplicate prefab textures are deliberately omitted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import time


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".staging")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def copy_verified(source: Path, destination: Path, expected: str | None = None) -> dict:
    source_hash = sha256(source)
    if expected and source_hash != expected:
        raise ValueError(f"Frozen source mismatch: {source.name}: {source_hash} != {expected}")
    # A repeat invocation keeps identical output bytes and avoids an extra 200MB write.
    if not destination.exists() or sha256(destination) != source_hash:
        temporary = destination.with_suffix(destination.suffix + ".staging")
        with source.open("rb") as incoming, temporary.open("wb") as outgoing:
            shutil.copyfileobj(incoming, outgoing, 4 * 1024 * 1024)
            outgoing.flush()
            os.fsync(outgoing.fileno())
        os.replace(temporary, destination)
    with destination.open("rb+") as stream:
        os.fsync(stream.fileno())
    result_hash = sha256(destination)
    if result_hash != source_hash:
        raise ValueError(f"Staged file mismatch: {destination}")
    return {"file": destination.name, "bytes": destination.stat().st_size, "sha256": result_hash}


def read_glb_json(path: Path) -> dict:
    with path.open("rb") as stream:
        magic, version, total = struct.unpack("<4sII", stream.read(12))
        length, kind = struct.unpack("<II", stream.read(8))
        if magic != b"glTF" or version != 2 or total != path.stat().st_size or kind != 0x4E4F534A:
            raise ValueError("Invalid GLB 2.0 header")
        return json.loads(stream.read(length))


def make_catalog(document: dict, manifest: dict, plan: dict, interiors: dict) -> dict:
    nodes = document["nodes"]
    names = [node.get("name", "") for node in nodes]
    if len(set(names)) != len(names) or not all(names):
        raise ValueError("Stable node-name catalog requires unique, named GLB nodes")
    records = []
    for node in nodes:
        record = {"name": node["name"], "extras": node.get("extras", {})}
        if "mesh" in node:
            primitives = document["meshes"][node["mesh"]]["primitives"]
            record["vertex_color"] = any("COLOR_0" in part.get("attributes", {}) for part in primitives)
        records.append(record)
    interior_buildings = {item["id"]: item for item in interiors["buildings"]}
    doors = []
    source_objects = {node.get("extras", {}).get("source_object", "") for node in nodes}
    for building in plan["buildings"]:
        ident = building["id"]
        if not any(name.startswith(ident + "_Front_") for name in source_objects):
            continue  # Open market hall has no ordinary closed entrance leaf.
        entrance = interior_buildings[ident]["entrance_local_m"]
        doors.append({"building_id": ident, "center_x_m": float(entrance[0]),
                      "front_z_m": float(building["depth"]) / 2,
                      "body_width_m": .96, "body_height_m": 2.24,
                      "open_degrees": -105.0,
                      "source_prefix": ident + "_Front_",
                      "material_suffixes": ["Sage", "BluePaint", "Burgundy", "Glass", "Brass"],
                      "scope": "Runtime visual leaf only; portal permissions remain Sim-owned"})
    material_rules = []
    for material in document.get("materials", []):
        material_rules.append({"name": material.get("name", ""),
                               "alpha_mode": material.get("alphaMode", "OPAQUE"),
                               "base_color_factor": material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])})
    root = next(node for node in nodes if node["name"] == "LivingTown")
    return {"schema": "living_town.runtime_node_catalog.v1",
            "source_glb_sha256": manifest["town"]["sha256"],
            "source_blend_sha256": manifest["source_blend_sha256"],
            "portable_root_extras": root.get("extras", {}),
            "coordinate_system": manifest["coordinate_system"],
            "extras_bounds_coordinate_system": "Literal Blender-local XY metres; Godot local X=x, Z=-y",
            "inventory": manifest["interior_inventory"],
            "nodes": records, "material_rules": material_rules, "front_doors": doors}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    started = time.monotonic()
    root = args.root.resolve()
    art = root / "art/living_town"
    destination = root / "game/assets/town3d"
    destination.mkdir(parents=True, exist_ok=True)
    manifest_path = art / "game_assets/export_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "PASS" or manifest.get("units") != "metres":
        raise ValueError("Only a passing metric export may be staged")
    files = []
    source_glb = art / "game_assets/living_town_game.glb"
    files.append(copy_verified(source_glb, destination / source_glb.name, manifest["town"]["sha256"]))
    files.append(copy_verified(manifest_path, destination / manifest_path.name))
    metadata = ["masterplan", "terrain_plan", "interior_plan", "landscape_plan"]
    loaded = {}
    for name in metadata:
        source = art / (name + ".json")
        files.append(copy_verified(source, destination / source.name, manifest.get("source_" + name + "_sha256")))
        loaded[name] = json.loads(source.read_text(encoding="utf-8"))
    catalog = make_catalog(read_glb_json(source_glb), manifest, loaded["masterplan"], loaded["interior_plan"])
    write_json(destination / "node_catalog.json", catalog)
    files.append({"file": "node_catalog.json", "bytes": (destination / "node_catalog.json").stat().st_size,
                  "sha256": sha256(destination / "node_catalog.json")})
    stage = {"schema": "living_town.game_stage.v1", "status": "PASS",
             "source_blend_sha256": manifest["source_blend_sha256"],
             "source_export_manifest_sha256": sha256(manifest_path),
             "source_glb_sha256": manifest["town"]["sha256"],
             "source_bindings": {key: value for key, value in manifest.items()
                                 if key.startswith("source_") and key.endswith("_sha256")},
             "files": files, "node_count": len(catalog["nodes"]),
             "front_door_specs": len(catalog["front_doors"]),
             "inventory": manifest["interior_inventory"],
             "elapsed_seconds": round(time.monotonic() - started, 3),
             "notes": ["One optimized whole-town GLB; no duplicate high-detail scene or 49 prefabs",
                       "Frozen delivery unchanged; all staged bytes SHA256-verified and fsynced",
                       "Runtime visual geometry is not simulation, collision, or navigation authority",
                       "Metadata retains original Blender-local XY bounds; transform once at the adapter boundary"]}
    write_json(destination / "stage_manifest.json", stage)
    print(json.dumps({key: stage[key] for key in ["status", "source_blend_sha256", "source_glb_sha256", "node_count", "front_door_specs", "elapsed_seconds"]}))


if __name__ == "__main__":
    main()
