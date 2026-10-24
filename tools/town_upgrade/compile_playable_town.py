"""Stage an upgraded metric town and compile its REAL Main/LifeMode topology.

This is an overlay adapter, not a simulation or an inspection application. It
keeps existing action definitions, resident identities and portal access rules.
Inputs are immutable native export metadata; no Blender/Godot process is run.

The upgrade manifest declares ``source_blend_sha256``, ``assets`` (relative path,
sha256, baseline), ``buildings`` and ``interiors`` (inline {buildings:[...]} or a
JSON path). Building/interior records use the existing metric planner schema.
``removed_baseline_object_names`` is applied by exact source identity.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import re
import struct
from collections import Counter, defaultdict, deque
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools import build_town_profile as geometry
from tools.stage_town_assets import copy_verified, read_glb_json, sha256, write_json


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def resolve(parent, value):
    path = Path(value)
    return path.resolve() if path.is_absolute() else (parent / path).resolve()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def floor_count(plan):
    return len(plan["levels"])


def normalized_building(row):
    row = copy.deepcopy(row)
    row["center"] = list(row.get("center", row.get("center_m", [])))[:2]
    require(len(row["center"]) == 2, "Missing metric centre: " + row["id"])
    row.setdefault("pad_level_m", float(row.get("center_m", [0, 0, 0])[2]) if len(row.get("center_m", [])) > 2 else 0.)
    row.setdefault("yaw_degrees", 0.)
    row.setdefault("finished_floor_offset_m", .38)
    if "width" not in row:
        row["width"], row["depth"] = row.get("footprint_m", row.get("size_m", [0, 0]))
    require(row["width"] > 0 and row["depth"] > 0, "Missing metric footprint: " + row["id"])
    angle = math.radians(row["yaw_degrees"])
    if row.get("group"):
        # The full-native ledger includes the actual180degree front-face flip
        # of north-facing core houses. Recompute from that final native pose;
        # stale masterplan front vectors must not point to the back facade.
        row["front_outward"] = [math.sin(angle), -math.cos(angle)]
        row["front_threshold"] = list(geometry.local_to_world(row, float(row.get("door_local_x", 0)), -row["depth"]/2))
    else:
        row.setdefault("front_outward", [math.sin(angle), -math.cos(angle)])
        entry = row.get("entry_local", [0, -row["depth"] / 2])
        row.setdefault("front_threshold", list(geometry.local_to_world(row, *entry)))
    return row


def model_inputs(manifest_path, expansion_dir):
    manifest_path = manifest_path.resolve()
    data = read(manifest_path)
    parent = manifest_path.parent
    art = ROOT / "art/living_town"
    territory = read(expansion_dir / "territory_plan.json")
    reserve = read(art / "reserve_plan.json")
    master = read(art / "masterplan.json")
    native = {b["id"]: b for b in read(art / "town_manifest.json")["buildings"]}
    all_buildings = {b["id"]: copy.deepcopy(b) for b in master["buildings"] + reserve["buildings"] + territory["buildings"]}
    for bid, b in all_buildings.items():
        if bid in native:
            b.setdefault("pad_level_m", native[bid]["center_m"][2])
    for b in data.get("buildings", []):
        all_buildings.setdefault(b["id"], {}).update(b)
    all_buildings = {bid: normalized_building(b) for bid, b in all_buildings.items()}
    plans = {p["id"]: p for p in read(art / "interior_plan.json")["buildings"]}
    amenity_module = load_module("town_upgrade_reserve_amenities", art / "tools/reserve_amenities.py")
    for amenity in amenity_module.plan_reserve(reserve):
        rooms = copy.deepcopy(amenity["rooms"])
        for room in rooms:
            room["assets"] = [copy.deepcopy(a) for a in amenity["assets"] if a["room_id"] == room["id"]]
        plans[amenity["id"]] = {"id": amenity["id"], "kind": amenity["kind"], "footprint_m": [amenity["width"], amenity["depth"]],
            "floors": 1, "floor_height_m": amenity["wall_height_m"], "clear_bounds_m": amenity["clear_bounds_m"], "core": None,
            "entrance_local_m": amenity["entry_local"], "levels": [{"level": 0, "finished_floor_local_z_m": amenity["finished_floor_local_z_m"], "rooms": rooms, "partitions": amenity["partitions"]}]}
    plans.update({p["id"]: p for p in read(expansion_dir / "scene/interiors.json")["buildings"]})
    interiors = data.get("interiors", data.get("interiors_path"))
    if isinstance(interiors, str):
        interiors = read(resolve(parent, interiors))
    if isinstance(interiors, dict):
        plans.update({p["id"]: p for p in interiors["buildings"]})
    for name in data.get("interior_sources", []):
        plans.update({p["id"]: p for p in read(resolve(parent, name))["buildings"]})
    missing = sorted(set(all_buildings) - set(plans))
    require(not missing, "Every building needs authored rooms/partitions/assets. Missing interior plans: " + ", ".join(missing))
    require(set(plans) == set(all_buildings), "Interior/building ID sets differ")
    require(bool(data.get("source_blend_sha256")), "Final native manifest needs source_blend_sha256")
    for bid, plan in plans.items():
        require(bool(plan.get("levels")), "No authored levels: " + bid)
        plan["floors"] = len(plan["levels"])
        all_buildings[bid]["floors"] = len(plan["levels"])
    return data, all_buildings, plans, territory, reserve


def asset_records(plan, building):
    """Stable lookups, so consumers never parse an ID ending in _L04 as level4."""
    rooms, assets = {}, {}
    for level in plan["levels"]:
        index = level["level"]
        for room in level["rooms"]:
            rooms[room["id"]] = (building, index)
            for asset in room["assets"]:
                assets[asset["id"]] = (building, index, room["id"])
    return rooms, assets


_STRUCTURAL_STEMS = {
    "partition_with_openings": r"Partitions",
    "interior_joinery": r"Joinery",
    "open_interior_door": r"DoorLeaf_[0-9]+_[0-9]+",
    "stair_and_gallery_guard": r"ShaftGuard",
    "functional_stair": r"Stairs",
}


def structural_floor_metadata(name, extras, building, plan, height_bounds=None):
    """Recover collection-only floor membership from the native recipe grammar.

    Only six known interior roles qualify. The complete owner prefix is removed
    first, so a parcel ID ending in L04 cannot masquerade as a fourth floor.
    Unknown upper envelopes retain their existing cutaway policy.
    """
    role = extras.get("interior_role", "")
    if role != "floor_slab" and role not in _STRUCTURAL_STEMS:
        return {}
    prefix = re.escape(building["id"])
    pattern = prefix + (r"_Floor([1-9][0-9]*)_.+" if role == "floor_slab"
                        else r"_L([0-9]{2})_" + _STRUCTURAL_STEMS[role] + r"_.+")
    match = re.fullmatch(pattern, name)
    require(match is not None, "Unknown authored interior structure name: " + name)
    index = int(match[1]) - (1 if role == "floor_slab" else 0)
    levels = {int(level["level"]): level for level in plan["levels"]}
    require(index in levels, "Interior structure names an unauthored floor: " + name)
    require(role != "floor_slab" or index > 0, "Ground slab is not an upper interior slab: " + name)
    end_index = index
    if role == "functional_stair":
        end_index += 1
        require(end_index in levels and levels[index].get("stair_to_next_level"),
                "Interior stair has no authored next-floor flight: " + name)
    result = {"model_floor_index": index, "model_floor_index_source": "native_interior_structure_grammar.v1"}
    if role == "functional_stair":
        # A flight belongs to its departure floor, and remains visible from its
        # arrival floor. Assigning it to the arrival floor hides stairs on 1f.
        result.update(model_floor_end_index=end_index, model_floor_association="departure_floor")
    if height_bounds is not None:
        low, high = height_bounds
        ff = float(building["pad_level_m"]) + float(levels[index]["finished_floor_local_z_m"])
        if role == "floor_slab":
            valid = ff - .22 <= low <= high <= ff + .08 and high >= ff - .08
        else:
            ceiling = (float(building["pad_level_m"]) + float(levels[end_index]["finished_floor_local_z_m"]) + 1.05
                       if role == "functional_stair" else
                       float(building["pad_level_m"]) + float(levels[index + 1]["finished_floor_local_z_m"]) + .15
                       if index + 1 in levels else ff + float(plan.get("floor_height_m", 2.85)) + .15)
            valid = ff - .12 <= low <= high <= ceiling
        require(valid, "Interior structure floor disagrees with transformed GLB bounds: " + name + " " + str(height_bounds))
        result["model_floor_height_bounds_m"] = [round(low, 6), round(high, 6)]
        result["model_floor_bounds_verified"] = True
    return result


def _glb_node_matrix(document, index, parents, matrix_cache):
    if index in matrix_cache:
        return matrix_cache[index]
    node = document["nodes"][index]
    if "matrix" in node:
        values = node["matrix"]  # glTF stores matrices column first.
        local = tuple(tuple(float(values[c * 4 + r]) for c in range(4)) for r in range(4))
    else:
        x, y, z, w = node.get("rotation", [0, 0, 0, 1])
        rotation = ((1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)),
                    (2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)),
                    (2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)))
        scale = node.get("scale", [1, 1, 1]); translation = node.get("translation", [0, 0, 0])
        local = tuple(tuple(rotation[r][c]*scale[c] for c in range(3)) + (float(translation[r]),) for r in range(3)) + ((0., 0., 0., 1.),)
    if index in parents:
        parent = _glb_node_matrix(document, parents[index], parents, matrix_cache)
        local = tuple(tuple(sum(parent[r][k]*local[k][c] for k in range(4)) for c in range(4)) for r in range(4))
    matrix_cache[index] = local
    return local


class GLBPositionBounds:
    """Read only requested FLOAT/VEC3 views; never retain an entire town BIN."""
    def __init__(self, path, document):
        self.path, self.document, self.binary_offset = Path(path), document, None
        with self.path.open("rb") as stream:
            stream.seek(12); length, _ = struct.unpack("<II", stream.read(8))
            stream.seek(20 + length); header = stream.read(8)
            if len(header) == 8 and struct.unpack("<II", header)[1] == 0x004E4942:
                self.binary_offset = 28 + length

    def bounds(self, accessor_index, rows):
        if self.binary_offset is None:
            return None
        accessor = self.document["accessors"][accessor_index]
        require(accessor.get("componentType") == 5126 and accessor.get("type") == "VEC3" and "sparse" not in accessor,
                "Stairwell measurement requires ordinary FLOAT/VEC3 POSITION data")
        view = self.document["bufferViews"][accessor["bufferView"]]
        require(view.get("buffer", 0) == 0, "Stairwell POSITION view must use the embedded GLB buffer")
        count = int(accessor["count"]); stride = int(view.get("byteStride", 12))
        require(count > 0 and stride >= 12, "Stairwell POSITION data is empty or has invalid stride")
        with self.path.open("rb") as stream:
            stream.seek(self.binary_offset + int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0)))
            data = stream.read((count - 1)*stride + 12)
        require(len(data) == (count - 1)*stride + 12, "Truncated stairwell POSITION data")
        lows, highs = [math.inf]*len(rows), [-math.inf]*len(rows)
        for offset in range(0, len(data)-11, stride):
            point = struct.unpack_from("<fff", data, offset)
            for axis, row in enumerate(rows):
                value = row[3] + sum(row[c]*point[c] for c in range(3))
                lows[axis] = min(lows[axis], value); highs[axis] = max(highs[axis], value)
        return tuple(zip(lows, highs))


def _glb_projected_bounds(document, index, rows, position_reader=None):
    node = document["nodes"][index]
    if "mesh" not in node:
        return None
    bounds = [[] for row in rows]
    for primitive in document["meshes"][node["mesh"]]["primitives"]:
        accessor_index = primitive.get("attributes", {}).get("POSITION")
        if accessor_index is None:
            continue
        accessor = document["accessors"][accessor_index]
        measured = position_reader.bounds(accessor_index, rows) if position_reader else None
        if measured is not None:
            for axis_bounds, value in zip(bounds, measured):
                axis_bounds.append(value)
            continue
        if "min" not in accessor or "max" not in accessor:
            return None
        for row, axis_bounds in zip(rows, bounds):
            low = row[3] + sum(min(row[c]*accessor["min"][c], row[c]*accessor["max"][c]) for c in range(3))
            high = row[3] + sum(max(row[c]*accessor["min"][c], row[c]*accessor["max"][c]) for c in range(3))
            axis_bounds.append((low, high))
    return tuple((min(b[0] for b in axis), max(b[1] for b in axis)) for axis in bounds) if all(bounds) else None


def glb_height_bounds(document, index, parents, matrix_cache):
    """World Y bounds from POSITION min/max, including every glTF node transform."""
    bounds = _glb_projected_bounds(document, index, [_glb_node_matrix(document, index, parents, matrix_cache)[1]])
    return bounds[0] if bounds else None


def glb_building_bounds(document, index, parents, matrix_cache, building, position_reader=None):
    """POSITION bounds projected directly into the authored building's XYZ axes."""
    matrix = _glb_node_matrix(document, index, parents, matrix_cache)
    angle = math.radians(building["yaw_degrees"]); co, si = math.cos(angle), math.sin(angle)
    cx, cy = building["center"]
    rows = [tuple(co*matrix[0][c]-si*matrix[2][c] for c in range(4)),
            tuple(-si*matrix[0][c]-co*matrix[2][c] for c in range(4)), tuple(matrix[1])]
    offsets = (-co*cx-si*cy, si*cx-co*cy, -building["pad_level_m"])
    rows = [row[:3] + (row[3]+offset,) for row, offset in zip(rows, offsets)]
    return _glb_projected_bounds(document, index, rows, position_reader)


def stairwell_room_metadata(name, extras, building, plan, local_bounds):
    """Bind an open stair zone to existing stair/guard geometry, never a dummy room."""
    role = extras.get("interior_role")
    if role not in {"functional_stair", "stair_and_gallery_guard"}:
        return {}
    require(extras.get("model_floor_index_source") == "native_interior_structure_grammar.v1",
            "Stairwell geometry lacks verified owner/floor grammar: " + name)
    index = extras["model_floor_index"]
    level = next(level for level in plan["levels"] if int(level["level"]) == index)
    room_id = building["id"] + f"_L{index:02d}_Stairwell"
    rooms = [room for room in level["rooms"] if room["id"] == room_id and room.get("purpose") == "protected vertical circulation"]
    require(len(rooms) == 1 and plan.get("core") and local_bounds is not None,
            "Stairwell binding needs an authored zone, core and actual mesh bounds: " + name)
    zone = rooms[0]["bounds_m"]; core = plan["core"]["bounds"]
    require(all(abs(a-b) < .0001 for a, b in zip(zone, core)), "Stairwell zone differs from its authored core: " + room_id)
    (x0, x1), (y0, y1), _ = local_bounds
    # The source ShaftGuard batch may also include a church gallery perimeter.
    # Its exact native role/name always contains the core boundary guard; keep
    # that wider source batch truthful rather than pretending it is a room shell.
    overlap = min(x1, zone[2]) > max(x0, zone[0]) and min(y1, zone[3]) > max(y0, zone[1])
    contained = zone[0]-.18 <= x0 <= x1 <= zone[2]+.18 and zone[1]-.18 <= y0 <= y1 <= zone[3]+.18
    require(overlap and (contained or (role == "stair_and_gallery_guard" and "nave_void" in level)),
            "Native stair/guard geometry misses its authored stairwell core: " + name)
    return {"room_id": room_id, "model_room_binding": "existing_open_stairwell_structure.v1",
            "model_room_geometry_role": role, "model_room_bounds_local_m": [[round(a, 6), round(b, 6)] for a, b in local_bounds],
            "model_room_zone_bounds_m": zone, "model_room_enclosure": "open circulation zone; existing stair or boundary guard"}


def stage_assets(manifest_path, manifest, buildings, plans, destination):
    """One catalog per chunk avoids cross-file duplicate glTF node names."""
    require(manifest.get("native_geometry_status", "PASS") == "PASS", "Do not stage a native geometry failure")
    destination.mkdir(parents=True, exist_ok=True)
    room_map, asset_map = {}, {}
    for bid, plan in plans.items():
        rooms, assets = asset_records(plan, bid)
        room_map.update(rooms); asset_map.update(assets)
    declared = manifest.get("assets", manifest.get("chunks", []))
    require(bool(declared), "Final native manifest has no assets/chunks")
    files, staged, catalogs = [], [], []
    names = set()
    seen_buildings, seen_rooms, seen_assets = set(), set(), set()
    structural_count, measured_structural_count, stairwell_binding_count = 0, 0, 0
    for ordinal, row in enumerate(declared):
        source = resolve(manifest_path.parent, row.get("path", row.get("file", "")))
        require(source.is_file(), "Missing exported chunk: " + str(source))
        expected = row.get("sha256")
        require(isinstance(expected, str) and len(expected) == 64, "Chunk lacks SHA256: " + str(source))
        filename = f"town_{ordinal:02d}_{source.stem}.glb"
        files.append(copy_verified(source, destination / filename, expected))
        document = read_glb_json(source)
        require(not any("uri" in item for field in ("images","buffers") for item in document.get(field,[])), "Exported chunk has external dependencies: "+filename)
        records, rules = [], []
        for material in document.get("materials", []):
            rules.append({"name": material.get("name", ""), "alpha_mode": material.get("alphaMode", "OPAQUE"),
                          "base_color_factor": material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])})
        inherited = {}
        for i, node in enumerate(document.get("nodes", [])):
            for child in node.get("children", []):
                inherited[child] = i
        def extras_of(i):
            node = document["nodes"][i]
            e = extras_of(inherited[i]).copy() if i in inherited else {}
            e.update(node.get("extras", {}))
            return e
        local_names = set(); matrix_cache = {}; position_reader = GLBPositionBounds(source, document)
        for i, node in enumerate(document.get("nodes", [])):
            name = node.get("name", "")
            require(name and name not in local_names, "Duplicate/empty node identity in " + filename + ": " + name)
            local_names.add(name)
            e = extras_of(i)
            bid = str(e.get("building_id", e.get("interior_building_id", e.get("reserve_building_id", ""))))
            room = str(e.get("room_id", e.get("interior_room_id", e.get("reserve_room_id", ""))))
            asset = str(e.get("interior_asset_id", e.get("reserve_asset_id", "")))
            if asset in asset_map:
                bid, index, room = asset_map[asset]
                e["model_floor_index"] = index
            elif room in room_map:
                bid, index = room_map[room]
                e["model_floor_index"] = index
            elif "floor_index" in e:
                e["model_floor_index"] = int(e["floor_index"])
            elif "reserve_floor_index" in e:
                e["model_floor_index"] = int(e["reserve_floor_index"])
            if bid in buildings:
                e["building_id"] = bid; seen_buildings.add(bid)
                floor = structural_floor_metadata(name, e, buildings[bid], plans[bid],
                    glb_height_bounds(document, i, inherited, matrix_cache)
                    if e.get("interior_role") == "floor_slab" or e.get("interior_role") in _STRUCTURAL_STEMS else None)
                if floor:
                    require("model_floor_index" not in e or e["model_floor_index"] == floor["model_floor_index"],
                            "Conflicting authored structural floor: " + name)
                    e.update(floor); structural_count += 1
                    measured_structural_count += int(bool(floor.get("model_floor_bounds_verified")))
                if room not in room_map and e.get("interior_role") in {"functional_stair", "stair_and_gallery_guard"}:
                    require(position_reader.binary_offset is not None, "Stairwell room binding requires actual embedded POSITION vertices: " + name)
                    binding = stairwell_room_metadata(name, e, buildings[bid], plans[bid],
                        glb_building_bounds(document, i, inherited, matrix_cache, buildings[bid], position_reader))
                    e.update(binding); room = binding["room_id"]; stairwell_binding_count += 1
            if room in room_map:
                e["room_id"] = room; seen_rooms.add(room)
            if asset in asset_map:
                e["interior_asset_id"] = asset; seen_assets.add(asset)
            if "source_object" not in e:
                e["source_object"] = name
            record = {"name": name, "extras": e}
            if "mesh" in node:
                record["vertex_color"] = any("COLOR_0" in p.get("attributes", {}) for p in document["meshes"][node["mesh"]]["primitives"])
            records.append(record)
        catalog_name = filename.replace(".glb", ".catalog.json")
        catalog = {"schema": "living_town.runtime_chunk_catalog.v1", "source_glb_sha256": expected,
                   "nodes": records, "material_rules": rules}
        write_json(destination / catalog_name, catalog)
        files.append({"file": catalog_name, "bytes": (destination / catalog_name).stat().st_size, "sha256": sha256(destination / catalog_name)})
        catalogs.append(catalog)
        staged.append({"file": filename, "sha256": expected, "catalog": catalog_name,
                       "catalog_sha256": files[-1]["sha256"], "baseline": bool(row.get("baseline", ordinal == 0))})
    require(set(buildings) <= seen_buildings, "Export lacks building geometry: " + str(sorted(set(buildings) - seen_buildings)))
    require(set(room_map) <= seen_rooms, "Export lacks authored room geometry: " + str(sorted(set(room_map) - seen_rooms)[:20]))
    require(set(asset_map) <= seen_assets, "Export lacks authored furniture geometry: " + str(sorted(set(asset_map) - seen_assets)[:20]))
    identity = hashlib.sha256(json.dumps(staged, sort_keys=True).encode()).hexdigest()
    inventory = {"floor_count": sum(floor_count(p) for p in plans.values()), "room_count": len(room_map), "furnishing_count": len(asset_map)}
    stage = {"schema": "living_town.game_stage.v2", "status": "PASS", "source_blend_sha256": manifest["source_blend_sha256"],
             "source_glb_sha256": identity, "source_asset_set_sha256": identity, "source_upgrade_manifest_sha256": sha256(manifest_path),
             "building_count": len(buildings), "inventory": inventory, "assets": staged, "files": files,
             "removed_baseline_object_names": manifest.get("removed_baseline_object_names", []),
             "structural_floor_indexing": {"schema": "living_town.structural_floor_indexing.v1", "indexed_meshes": structural_count,
                 "transformed_bounds_verified": measured_structural_count, "stair_association": "departure_floor"},
             "open_stairwell_geometry_bindings": stairwell_binding_count,
             "navigation_authority": "Sim authored grid and portals; GLB visual geometry cannot grant movement"}
    write_json(destination / "stage_manifest.json", stage)
    return stage


def compile_interior(b, plan, space, old_space):
    width, depth = plan["footprint_m"]
    gw, gh = math.ceil(width / .25), math.ceil(depth / .25)
    info = copy.deepcopy(old_space)
    info.update({"kind": "interior", "label": info.get("label", b.get("use", b["id"])), "bounds": [0, 0, gw, gh],
                 "floors": [f"{i+1}f" for i in range(len(plan["levels"]))], "default_floor": "1f", "model_building_id": b["id"]})
    info.setdefault("public_venue", False)
    planes, contents, grids, rooms, checks = {}, {}, {}, {}, []
    for level in plan["levels"]:
        index = int(level["level"]); floor = f"{index+1}f"; key = space + "/" + floor
        plane = {"space": space, "floor": floor, "building_id": b["id"], "level": index,
                 "cell_size_m": .25, "origin_local_m": [-width/2, depth/2], "grid_size": [gw, gh],
                 "center_world_m": [*b["center"], b["pad_level_m"]], "yaw_degrees": b["yaw_degrees"],
                 "finished_floor_z_m": b["pad_level_m"] + level["finished_floor_local_z_m"]}
        assets = [a for r in level["rooms"] for a in r["assets"]]
        blocked = set()
        for y in range(gh):
            for x in range(gw):
                px, py = geometry.cell_xy(plane, (x, y))
                if not geometry.inside(px, py, plan["clear_bounds_m"], -geometry.AGENT_RADIUS) or any(geometry.partition_blocks(p, px, py) for p in level.get("partitions", [])):
                    blocked.add((x, y)); continue
                if plan.get("core") and geometry.inside(px, py, plan["core"]["bounds"], .015):
                    blocked.add((x, y)); continue
                if any(geometry.inside(px, py, a["footprint_m"], geometry.AGENT_RADIUS) for a in assets if a.get("collision_proxy", True)):
                    blocked.add((x, y))
        labels, sizes = geometry.components(gw, gh, blocked)
        require(bool(sizes), "Entire interior is blocked: " + key)
        target = plan.get("entrance_local_m", [0, -depth/2+.48]) if index == 0 else (plan["core"]["center_x"], plan["core"]["bounds"][3]+.28)
        # Entry target may be on the shell boundary: allow the actual inset cell.
        entry = geometry.nearest_open(plane, labels, target, .95)
        component = labels[entry]
        blocked.update(p for p, c in labels.items() if c != component)
        opened = {p: c for p, c in labels.items() if c == component}
        for room in level["rooms"]:
            candidates = [p for p in opened if geometry.inside(*geometry.cell_xy(plane, p), room["bounds_m"])]
            # A vehicle's sealed driver cab is detailed visual geometry; its
            # explicitly nonpublic driver seat is not a pedestrian activity.
            active = any(not a.get("nonpublic", False) for a in room["assets"])
            require(not active or bool(candidates), "Authored activity room disconnected from entrance: " + room["id"])
            rooms[room["id"]] = {"rect": geometry.rect_grid(plane, room["bounds_m"]), "space": space, "floor": floor,
                "enclosed": active and "gallery" not in room.get("purpose", ""), "type": room.get("purpose", "room"),
                "building": b["id"], "owner": "aria" if space == "cafe" and index > 0 else "",
                "model_room_id": room["id"], "bounds_m": room["bounds_m"]}
            checks.append({"room": room["id"], "plane": key, "activity_room": active, "nonpublic_display_only": bool(room["assets"]) and not active, "reachable_open_cells": len(candidates)})
        planes[key] = plane
        contents[floor] = {"furniture": [], "nav_blockers": [list(p) for p in sorted(blocked, key=lambda p:(p[1],p[0]))],
                           "model_building_id": b["id"], "model_level": index, "cell_size_m": .25}
        grids[key] = {"labels": opened, "entry": entry, "assets": assets, "level": level}
    return info, planes, contents, grids, rooms, checks


class SurfaceIndex:
    """Short-segment spatial index for exact route, bridge and stair deck heights."""
    def __init__(self, routes, bucket=12.):
        self.bucket = bucket
        self.cells = defaultdict(list)
        for route in routes:
            points = route.get("points_m", route.get("points_world_m", []))
            radius = float(route.get("width_m", 2)) / 2
            for a, b in zip(points, points[1:]):
                if len(a) < 3 or len(b) < 3 or math.dist(a[:2], b[:2]) < 1e-9:
                    continue
                record = (a, b, radius, int(route.get("priority", 1)), route.get("id", ""))
                for x in range(math.floor((min(a[0],b[0])-radius)/bucket), math.floor((max(a[0],b[0])+radius)/bucket)+1):
                    for y in range(math.floor((min(a[1],b[1])-radius)/bucket), math.floor((max(a[1],b[1])+radius)/bucket)+1):
                        self.cells[x,y].append(record)

    def sample(self, x, y):
        candidates = []
        for a, b, radius, priority, ident in self.cells.get((math.floor(x/self.bucket), math.floor(y/self.bucket)), ()):
            dx, dy = b[0]-a[0], b[1]-a[1]
            t = max(0., min(1., ((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
            distance = math.hypot(x-a[0]-t*dx, y-a[1]-t*dy)
            if distance <= radius + .001:
                candidates.append((-priority, distance/max(radius,.01), ident, a[2]+(b[2]-a[2])*t))
        if not candidates:
            return None
        return min(candidates)[3]


def compile_outdoor(buildings, territory, reserve, cell, trunks=()):
    bounds = territory["bounds_xyxy_m"]
    x0, y0, x1, y1 = bounds
    width, height = math.ceil((x1-x0)/cell), math.ceil((y1-y0)/cell)
    plane = {"space": "town", "floor": "outdoor", "building_id": None, "level": -1, "cell_size_m": cell,
             "origin_world_m": [x0, y1], "grid_size": [width, height], "terrain_heights_m": []}
    routes = copy.deepcopy(territory["roads"] + territory.get("approaches", []) + reserve["paths"])
    for r in reserve.get("bridges", []) + reserve.get("stairs", []):
        routes.append({**r, "priority": 4})
    # Stairs have actual short landing and flight profiles, not a ravine floor.
    for stair in reserve.get("stairs", []):
        for flight in stair.get("flights", []) + stair.get("landings", []):
            routes.append({**flight, "width_m": stair["width_m"], "id": stair["id"], "priority": 5})
    surfaces = SurfaceIndex(routes)
    from tools.town_generation import territory as planner
    height_fn = planner.make_height_function(territory, ROOT / "art/living_town")
    terrain = load_module("town_upgrade_core_terrain", ROOT / "art/living_town/tools/terrain_profile.py")
    core = [-66, -50, 68, 58]
    # Fine navigation samples on paths/pads; natural undeveloped ground uses a
    # 4m sampled authority. No flattened substitute plane is generated.
    sample_step = 4.
    coarse = {}
    def natural(x,y):
        gx,gy=math.floor(x/sample_step),math.floor(y/sample_step)
        values=[]
        for ix,iy in ((gx,gy),(gx+1,gy),(gx,gy+1),(gx+1,gy+1)):
            if (ix,iy) not in coarse:
                coarse[ix,iy]=height_fn(ix*sample_step,iy*sample_step)
            values.append(coarse[ix,iy])
        tx,ty=x/sample_step-gx,y/sample_step-gy
        return (values[0]*(1-tx)+values[1]*tx)*(1-ty)+(values[2]*(1-tx)+values[3]*tx)*ty
    parcel_index=defaultdict(list);bucket=12.
    for b in buildings.values():
        radius=math.hypot(b["width"],b["depth"])/2+.4;cx,cy=b["center"]
        for ix in range(math.floor((cx-radius)/bucket),math.floor((cx+radius)/bucket)+1):
            for iy in range(math.floor((cy-radius)/bucket),math.floor((cy+radius)/bucket)+1):parcel_index[ix,iy].append(b)
    trunk_index=defaultdict(list)
    for trunk in trunks:
        tx,ty=trunk["position_m"][:2]
        radius=float(trunk.get("trunk_radius_m",.18*float(trunk.get("scale",[1])[0])))+.08+cell*.25
        for ix in range(math.floor((tx-radius)/bucket),math.floor((tx+radius)/bucket)+1):
            for iy in range(math.floor((ty-radius)/bucket),math.floor((ty+radius)/bucket)+1):trunk_index[ix,iy].append((tx,ty,radius))
    blocked=set();labels={};route_count=0;trunk_blocked=0
    for y in range(height):
        if y%100==0:print(f"[playable-town] outdoor row {y}/{height}",flush=True)
        for x in range(width):
            wx,wy=geometry.cell_xy(plane,(x,y));surface=surfaces.sample(wx,wy)
            inside_core=geometry.inside(wx,wy,core)
            z=terrain.design_height(wx,wy) if inside_core else natural(wx,wy)
            if surface is not None:z=surface+.025;route_count+=1
            if inside_core and not geometry.inside(wx,wy,terrain.QUAY_RECT) and wx>terrain.coast_x(wy)-terrain.beach_width(wy):z=terrain.beach_height(wx,wy)
            walkable=inside_core or surface is not None
            for b in parcel_index.get((math.floor(wx/bucket),math.floor(wy/bucket)),()):
                lx,ly=geometry.world_to_local(b,wx,wy)
                # Visit courtyards/entry terraces, but never walk through shells.
                if abs(lx)<b["width"]/2+2. and abs(ly)<b["depth"]/2+2.:
                    walkable=True
                    if surface is None:z=b["pad_level_m"]
                if abs(lx)<=b["width"]/2+.08 and abs(ly)<=b["depth"]/2+.08:
                    walkable=False;break
            if (wx>=terrain.coast_x(wy) and not geometry.inside(wx,wy,terrain.QUAY_RECT)) or terrain.pond_radius(wx,wy)<=1.04:
                walkable=False
            if walkable and any(math.hypot(wx-tx,wy-ty)<=radius for tx,ty,radius in trunk_index.get((math.floor(wx/bucket),math.floor(wy/bucket)),())):
                walkable=False;trunk_blocked+=1
            plane["terrain_heights_m"].append(round(z,5))
            if walkable:labels[x,y]=0
            else:blocked.add((x,y))
    # Flood only genuine open cells. Never carve arbitrary rescue corridors.
    seed=geometry.xy_cell(plane,-8,3)
    require(seed in labels,"Core square is not walkable")
    seen={seed};queue=deque([seed])
    while queue:
        x,y=queue.popleft()
        for n in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if n in labels and n not in seen:seen.add(n);queue.append(n)
    blocked.update(set(labels)-seen)
    labels={p:0 for p in seen}
    return plane,blocked,labels,{"grid_cells":width*height,"connected_walkable_cells":len(labels),"sampled_route_cells":route_count,"coarse_natural_height_samples":len(coarse),"botanical_trunks":len(trunks),"trunk_blocked_walk_cells":trunk_blocked,"navigation_policy":"Core streets and authored reserve/expansion paths, bridges, stairs and terraces; botanical trunk blockers; no cross-ravine shortcuts"}


def adjacent_asset(plane, grid, asset):
    rect=asset["footprint_m"];cx,cy=asset["center_m"];choices=[]
    preferred=asset.get("approach_local_m")
    if preferred is None and asset["kind"] in {"sofa","banquette","lounge_chair","pew","toilet","basin","kitchen_run","cafe_counter","retail_counter","workbench","bookshelf"}:
        angle=math.radians(asset.get("rotation_degrees",0));depth=asset.get("dimensions_m",[0,0])[1]
        preferred=(cx+math.sin(angle)*(depth/2+.35),cy-math.cos(angle)*(depth/2+.35))
    for p in grid["labels"]:
        x,y=geometry.cell_xy(plane,p);distance=math.hypot(max(rect[0]-x,0,x-rect[2]),max(rect[1]-y,0,y-rect[3]))
        if .045<=distance<=.8:
            preference=.55*math.hypot(x-preferred[0],y-preferred[1]) if preferred is not None else .02*math.hypot(x-cx,y-cy)
            choices.append((distance+preference,p[1],p[0],p))
    require(bool(choices),"No reachable standing approach at actual fixture: "+asset["id"])
    return min(choices)[3]


def seating_positions(asset):
    """Exact seat centers from the bound native furniture recipes."""
    if asset["kind"] == "cafe_table_set":
        seats = [(0,-.68),(0,.68)] if asset.get("detail_source") == "hero_bistro" else [(-.43,0),(.43,0)]
    elif asset["kind"] == "dining_table":
        seats = [(0,-.36),(0,.36)]
    else:
        return []
    angle=math.radians(asset.get("rotation_degrees",0));co,si=math.cos(angle),math.sin(angle);cx,cy=asset["center_m"]
    return [[round(cx+x*co-y*si,6),round(cy+x*si+y*co,6)] for x,y in seats]


def compile_profile(manifest_path, expansion_dir, destination, asset_destination, outdoor_cell=1., expected_buildings=151, stage=True, legacy_profile=None):
    started=time.monotonic()
    manifest,buildings,plans,territory,reserve=model_inputs(manifest_path,expansion_dir)
    require(len(buildings)==expected_buildings,f"Expected {expected_buildings} authored buildings, got {len(buildings)}")
    baseline=legacy_profile or ROOT/"game/data/town3d"
    base={name:read(baseline/(name+".json")) for name in geometry.BASE_NAMES}
    old_projection=read(baseline/"projection.json")
    assigned=dict(old_projection["building_spaces"])
    for bid in buildings:assigned.setdefault(bid,"model_"+bid.lower())
    require(set(assigned)==set(buildings),"Previous profile contains unknown building IDs")
    reverse={space:bid for bid,space in assigned.items()}
    planes={};grids={};rooms={};room_checks=[];contents={};spaces={};asset_lookup={}
    for bid,b in buildings.items():
        space=assigned[bid]
        info,p,c,g,r,checks=compile_interior(b,plans[bid],space,base["spaces"]["spaces"].get(space,{}))
        spaces[space]=info;planes.update(p);contents[space]=c;grids.update(g);rooms.update(r);room_checks.extend(checks)
        for key,grid in g.items():
            for asset in grid["assets"]:asset_lookup[asset["id"]]=(key,asset)
    trunks=[]
    botanical_path=manifest.get("botanical_report")
    if botanical_path:
        botanical_file=resolve(manifest_path.parent,botanical_path)
        require(botanical_file.is_file(),"Declared botanical report is missing")
        trunks=read(botanical_file).get("placements",[])
    town,blocked,opened,outdoor_report=compile_outdoor(buildings,territory,reserve,outdoor_cell,trunks)
    planes["town/outdoor"]=town;grids["town/outdoor"]={"labels":opened}
    spaces["town"]={"kind":"outdoor","label":"Living Town and National Reserve","bounds":[0,0,*town["grid_size"]],"floors":["outdoor"],"default_floor":"outdoor"}
    old_portals=base["spaces"]["portals"];portals=[];portal_projections={}
    old_entrances={p["to"]["space"]:p for p in old_portals if p["from"]["space"]=="town"}
    old_stairs={(p["from"]["space"],p["from"]["floor"],p["to"]["floor"]):p for p in old_portals if p["from"]["space"]==p["to"]["space"]}
    def endpoint(space,floor,pos):return {"space":space,"floor":floor,"pos":list(pos)}
    def add_portal(old,ident,fr,to,kind):
        p=copy.deepcopy(old or {"kind":kind,"access":"public","traversal_cost":1 if kind=="door" else 2})
        p.update({"id":ident,"from":fr,"to":to,"bidirectional":True});portals.append(p)
        def world(e):
            plane=planes[e["space"]+"/"+e["floor"]];x,y=geometry.cell_xy(plane,e["pos"])
            if plane["building_id"] is None:return [x,y,town["terrain_heights_m"][e["pos"][1]*town["grid_size"][0]+e["pos"][0]]]
            return [*geometry.local_to_world(buildings[plane["building_id"]],x,y),plane["finished_floor_z_m"]]
        portal_projections[ident]={"from_world_m":world(fr),"to_world_m":world(to),"kind":"entrance" if kind=="door" else "stairs","model_building_id":reverse[to["space"]]}
    for bid,b in buildings.items():
        space=assigned[bid];ft=b["front_threshold"];out=b["front_outward"]
        outside=(ft[0]+out[0]*max(.6,outdoor_cell*.8),ft[1]+out[1]*max(.6,outdoor_cell*.8))
        pos=geometry.nearest_open(town,opened,outside,max(1.4,outdoor_cell*1.7))
        old=old_entrances.get(space);ident=old["id"] if old else "p_model_"+bid.lower()+"_door"
        add_portal(old,ident,endpoint("town","outdoor",pos),endpoint(space,"1f",grids[space+"/1f"]["entry"]),"door")
        for index in range(len(plans[bid]["levels"])-1):
            lower=space+f"/{index+1}f";upper=space+f"/{index+2}f";core=plans[bid]["core"]
            foot=geometry.nearest_open(planes[lower],grids[lower]["labels"],(core["center_x"],core["bounds"][1]-.27),.9)
            head=geometry.nearest_open(planes[upper],grids[upper]["labels"],(core["center_x"],core["bounds"][3]+.27),.9)
            old=old_stairs.get((space,f"{index+1}f",f"{index+2}f"));ident=old["id"] if old else f"p_model_{bid.lower()}_stairs_{index+1}_{index+2}"
            add_portal(old,ident,endpoint(space,f"{index+1}f",foot),endpoint(space,f"{index+2}f",head),"stairs")
    old_town=old_projection["planes"]["town/outdoor"]
    def move_outdoor(pos):
        xy=geometry.cell_xy(old_town,pos)
        return list(geometry.nearest_open(town,opened,xy,max(2.,outdoor_cell*2)))
    bindings={};rebound={};legacy_adverts={}
    def rebind(obj,old_id=None):
        obj=copy.deepcopy(obj);oid=old_id or obj["id"];old=old_projection["interaction_bindings"].get(oid)
        require(old is not None,"Legacy interaction has no binding: "+oid)
        info=copy.deepcopy(old);key=old["plane"];asset_id=old.get("model_asset_id")
        if asset_id:
            pair=asset_lookup.get(asset_id)
            if pair is None:
                choices=[(a["id"],k,a) for k,g in grids.items() for a in g.get("assets",[]) if k==key and a["kind"]==old.get("model_asset_kind")]
                require(bool(choices),"No compatible actual fixture for "+oid)
                _,key,asset=min(choices)
            else:key,asset=pair
            pos=list(adjacent_asset(planes[key],grids[key],asset));info.update({"model_asset_id":asset["id"],"model_asset_kind":asset["kind"],"fixture_center_local_m":asset["center_m"],"fixture_footprint_m":asset["footprint_m"],"fixture_rotation_degrees":asset.get("rotation_degrees",0),"fixture_dimensions_m":asset.get("dimensions_m",[]),"fixture_seat_centers_local_m":seating_positions(asset)})
        else:pos=move_outdoor(old["cell"])
        sp,fl=key.split("/");obj.update({"space":sp,"floor":fl,"pos":pos,"navigation_marker":True})
        info.update({"plane":key,"cell":pos,"approach_local_m":list(geometry.cell_xy(planes[key],pos))});bindings[oid]=info;rebound[oid]=obj
        if "advertises" in obj:legacy_adverts[oid]=copy.deepcopy(obj["advertises"])
        return obj
    output=copy.deepcopy(base)
    for name,field in (("map","objects"),("production","worksites"),("logistics","nodes")):
        output[name][field]=[rebind(o) for o in base[name][field]]
    for sp,floors in base["interiors"].items():
        if not isinstance(floors,dict):continue
        for fl,content in floors.items():
            if not isinstance(content,dict):continue
            for original in content.get("furniture",[]):
                marker=copy.deepcopy(original)
                oid=marker.get("object_id")
                if not oid:
                    oid="bank_counter" if marker.get("bank_counter") else "civic_observatory" if marker.get("civic_observatory") else None
                if not oid:continue
                bound=rebind({**marker,"id":oid},oid);key=bindings[oid]["plane"];dst_sp,dst_fl=key.split("/")
                marker.update({"pos":bound["pos"],"model_asset_id":bindings[oid].get("model_asset_id"),"navigation_marker":True})
                marker.pop("size",None);contents[dst_sp][dst_fl]["furniture"].append(marker)
    # New locations expose a bounded selection of existing legal core verbs.
    # Copy full ads from an existing compatible fixture; never invent Sim rules.
    templates={}
    for obj in rebound.values():
        if obj.get("advertises"):
            kind=bindings[obj["id"]].get("model_asset_kind")
            if kind:templates.setdefault(kind,obj)
    activity_rows=[];unbound_decorative=[]
    for bid in buildings:
        space=assigned[bid]
        if bid in old_projection["building_spaces"]:continue
        chosen=set()
        for level in plans[bid]["levels"]:
            key=space+f"/{level['level']+1}f"
            for room in level["rooms"]:
                for asset in room["assets"]:
                    kind=asset["kind"]
                    aliases={"counter":["retail_counter","cafe_counter"],"shower":["shower_screen","bathtub"],"dining_table":["cafe_table_set"],"bench":["sofa","banquette"],"basin":["basin"],"kitchen_run":["kitchen_run"]}
                    template_kind=next((k for k in [kind]+aliases.get(kind,[]) if k in templates),None)
                    if template_kind is None or (key,kind) in chosen:continue
                    template=templates[template_kind];oid="upgrade_"+asset["id"]
                    try:
                        pos=list(adjacent_asset(planes[key],grids[key],asset))
                    except ValueError:
                        # New visual furnishings do not automatically become
                        # gameplay offers. Retain an honest list of unsuitable
                        # candidates; never put an interaction inside furniture.
                        unbound_decorative.append({"asset_id":asset["id"],"plane":key,"kind":kind,"reason":"No reachable standing cell within0.8m of its measured footprint"})
                        continue
                    chosen.add((key,kind));sp,fl=key.split("/")
                    marker={"slot":next((f.get("slot","table") for fs in base["interiors"].values() if isinstance(fs,dict) for c in fs.values() if isinstance(c,dict) for f in c.get("furniture",[]) if f.get("object_id")==template["id"]),"table"),
                        "object_id":oid,"label":template.get("type",kind),"pos":pos,"staff":False,"advertises":copy.deepcopy(template["advertises"]),"navigation_marker":True,"model_asset_id":asset["id"]}
                    contents[sp][fl]["furniture"].append(marker)
                    bindings[oid]={"plane":key,"cell":pos,"approach_local_m":list(geometry.cell_xy(planes[key],pos)),"model_asset_id":asset["id"],"model_asset_kind":kind,"fixture_center_local_m":asset["center_m"],"fixture_footprint_m":asset["footprint_m"],"fixture_rotation_degrees":asset.get("rotation_degrees",0),"fixture_dimensions_m":asset.get("dimensions_m",[]),"fixture_seat_centers_local_m":seating_positions(asset),"advertisement_template_id":template["id"]}
                    activity_rows.append({"id":oid,"building_id":bid,"kind":kind,"template_id":template["id"]})
    output["interiors"]={"_note":"Authored upgraded rooms; original advertisements preserved; new sites copy legal fixture definitions.",**contents}
    output["spaces"]={"spaces":spaces,"portals":portals}
    output["map"].update({"width":town["grid_size"][0],"height":town["grid_size"][1],"rooms":rooms,"nav_blockers":[list(p) for p in sorted(blocked,key=lambda p:(p[1],p[0]))]})
    for area in output["map"]["areas"].values():
        x,y,w,h=area["rect"];a=geometry.cell_xy(old_town,(x-.5,y-.5));b=geometry.cell_xy(old_town,(x+w-.5,y+h-.5))
        area["rect"]=geometry.rect_grid(town,[a[0],b[1],b[0],a[1]])
        if "berth" in area:area["berth"]=move_outdoor(area["berth"])
    output["map"]["areas"]["commons"]["rect"]=[0,0,*town["grid_size"]]
    for carrier in output["logistics"].get("carriers",[]):carrier["berth"]=move_outdoor(carrier["berth"])
    for group in ("agents","affiliates"):
        for actor in output["agents"].get(group,[]):
            address=actor.get("spatial_address",{});sp=address.get("space_id","town");fl=address.get("floor_id","outdoor");key=sp+"/"+fl
            previous=address.get("position",actor.get("spawn",[0,0]))
            pos=move_outdoor(previous) if sp=="town" else list(geometry.nearest_open(planes[key],grids[key]["labels"],geometry.cell_xy(old_projection["planes"][key],previous),3.))
            actor.update({"home":pos,"spawn":pos,"spatial_address":{"space_id":sp,"floor_id":fl,"position":pos}})
    for event in output["festivals"].get("festivals",{}).values():
        for obj in event.get("objects",[]):obj["pos"]=move_outdoor(obj["pos"])
    election_obj=output["elections"].get("on_pass",{}).get("object")
    if isinstance(election_obj,dict):election_obj["pos"]=move_outdoor(election_obj["pos"])
    staged=stage_assets(manifest_path,manifest,buildings,plans,asset_destination) if stage else {"source_blend_sha256":manifest["source_blend_sha256"],"source_asset_set_sha256":"UNSTAGED"}
    projection={"schema":"living_town.projection3d.v1","coordinate_system":old_projection["coordinate_system"],"planes":planes,"building_spaces":assigned,"portal_projections":portal_projections,"interaction_bindings":bindings,"model_source_blend_sha256":manifest["source_blend_sha256"],"source_asset_set_sha256":staged["source_asset_set_sha256"],"runtime_navigation":{"authority":"Sim authored grid and portals","outdoor_cell_size_m":outdoor_cell,"interior_cell_size_m":.25,"reserve":"Authored paths, bridges, stair flights and landings; no walk-through cliff/ravine shortcuts"}}
    profile={"schema":"living_town.world_profile.v1","id":"town3d","label":"Living Town: complete upgraded playable territory","files":{name+".json":"res://data/town3d/"+name+".json" for name in geometry.BASE_NAMES},"projection_path":"res://data/town3d/projection.json","base_data_untouched":True,"save_namespace":"town3d","model_source_blend_sha256":manifest["source_blend_sha256"],"source_asset_set_sha256":staged["source_asset_set_sha256"],"source_upgrade_manifest_sha256":sha256(manifest_path)}
    presentation_sources = ["game/scripts/Main.gd", "game/scripts/WorldView3D.gd",
                            "game/scripts/TownModel3D.gd", "game/scripts/TownRayIndex3D.gd",
                            "game/scripts/TownStaticBatch3D.gd",
                            "game/scripts/TownCharacter3D.gd",
                            "game/scripts/TownWorldProfile.gd", "game/scripts/LifeMode.gd",
                            "game/scripts/Sim.gd"]
    presentation_sources.extend(path.relative_to(ROOT).as_posix()
                                for path in sorted((ROOT/"game/scripts/ui").rglob("*.gd")))
    profile["presentation_source_hashes"]={rel:sha256(ROOT/rel) for rel in presentation_sources}
    checks=[]
    def check(ident,condition,details=None):
        checks.append({"id":ident,"pass":bool(condition),"details":details})
        require(condition,ident+": "+str(details))
    expected_floors=sum(len(p["levels"]) for p in plans.values())
    check("every_building_has_one_real_space",len(assigned)==len(set(assigned.values()))==expected_buildings)
    check("every_authored_floor_has_navigation",len(planes)==expected_floors+1)
    check("every_building_has_genuine_connected_entrance",sum(p["kind"]=="door" for p in portals)==expected_buildings)
    check("every_activity_room_reachable_from_real_entry",all(r["reachable_open_cells"] for r in room_checks if r["activity_room"]))
    check("all_portal_endpoints_physically_open",all(tuple(e["pos"]) in grids[e["space"]+"/"+e["floor"]]["labels"] for p in portals for e in (p["from"],p["to"])))
    check("original_portal_ids_and_permissions_preserved",all(any(p["id"]==old["id"] and {k:v for k,v in p.items() if k not in ("from","to")}=={k:v for k,v in old.items() if k not in ("from","to")} for p in portals) for old in old_portals))
    check("original_actor_identities_and_personas_preserved",all({k:v for k,v in a.items() if k not in {"home","spawn","spatial_address"}}=={k:v for k,v in old.items() if k not in {"home","spawn","spatial_address"}} for group in ("agents","affiliates") for a,old in zip(output["agents"].get(group,[]),base["agents"].get(group,[]))))
    check("original_advertisements_unchanged",all(rebound[k].get("advertises")==v for k,v in legacy_adverts.items()))
    check("all_original_interactions_bound_to_actual_reachable_fixtures",set(old_projection["interaction_bindings"])<=set(bindings) and all(tuple(b["cell"]) in grids[b["plane"]]["labels"] for b in bindings.values()))
    check("jobs_and_housing_preserved",output["jobs"]==base["jobs"] and output["housing"]==base["housing"])
    check("terrain_is_not_a_flat_plane",max(town["terrain_heights_m"])-min(town["terrain_heights_m"])>30)
    destination.mkdir(parents=True,exist_ok=True)
    for name,data in output.items():write_json(destination/(name+".json"),data)
    write_json(destination/"projection.json",projection)
    profile["file_hashes"]={name+".json":sha256(destination/(name+".json")) for name in geometry.BASE_NAMES}
    profile["projection_sha256"]=sha256(destination/"projection.json")
    write_json(destination/"profile.json",profile)
    report={"schema":"living_town.upgrade_playable_compile.v1","status":"PASS" if stage else "PROFILE_ONLY_UNSTAGED",
        "source_blend_sha256":manifest["source_blend_sha256"],"source_upgrade_manifest_sha256":sha256(manifest_path),
        "source_asset_set_sha256":staged["source_asset_set_sha256"],"projection_sha256":profile["projection_sha256"],
        "counts":{"buildings":len(buildings),"interior_planes":expected_floors,"rooms":len(rooms),"furnishings":len(asset_lookup),"portals":len(portals),"original_interactions":len(old_projection["interaction_bindings"]),"new_legal_fixture_bindings":len(activity_rows)},
        "checks":checks,"outdoor":outdoor_report,"room_reachability":room_checks,"new_activity_bindings":activity_rows,"unbound_decorative_fixtures":unbound_decorative,
        "elapsed_seconds":round(time.monotonic()-started,3),"limits":["Compiler verifies authored raster connectivity, not engine physics.","GPU Main/LifeMode interaction and actual gameplay recording must pass on these exact staged bytes."]}
    write_json(destination/"upgrade_compile_report.json",report)
    print(json.dumps({k:report[k] for k in ("status","counts","elapsed_seconds")}),flush=True)
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upgrade-manifest",type=Path,required=True)
    parser.add_argument("--expansion-dir",type=Path,default=ROOT/"build/town_generation/territory_v6")
    parser.add_argument("--output",type=Path,default=ROOT/"game/data/town3d")
    parser.add_argument("--assets",type=Path,default=ROOT/"game/assets/town3d")
    parser.add_argument("--legacy-profile",type=Path)
    parser.add_argument("--outdoor-cell",type=float,default=1.)
    parser.add_argument("--expected-buildings",type=int,default=151)
    parser.add_argument("--no-stage",action="store_true")
    args=parser.parse_args()
    require(.25<=args.outdoor_cell<=1.,"Outdoor cells must be within0.25..1.0metres")
    compile_profile(args.upgrade_manifest.resolve(),args.expansion_dir.resolve(),args.output.resolve(),args.assets.resolve(),args.outdoor_cell,args.expected_buildings,not args.no_stage,args.legacy_profile)


if __name__=="__main__":main()
