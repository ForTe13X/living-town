"""Independent, standard-library audit of the finished reserve GLB delivery.

This reads GLB JSON/accessor bounds and streams file hashes; it does not import
Blender, load mesh payloads into an engine, or claim visual/physics acceptance.
Call verify(root, manifest=None), or run --root <living_town> --report <report>.
Run --self-test for small synthetic positive/negative cases, without real assets.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import tempfile


SCHEMA = "living_town.reserve_export_verification.v1"
RESERVE_BINDINGS = {
    "reserve_plan_sha256": "reserve_plan.json",
    "reserve_plan_module_sha256": "tools/reserve_plan.py",
    "reserve_environment_module_sha256": "tools/reserve_environment.py",
    "reserve_amenities_module_sha256": "tools/reserve_amenities.py",
}
CORE_BINDINGS = {
    "masterplan_sha256": "masterplan.json",
    "terrain_plan_sha256": "terrain_plan.json",
    "interior_plan_sha256": "interior_plan.json",
    "interior_module_sha256": "tools/interior_design.py",
    "landscape_plan_sha256": "landscape_plan.json",
    "landscape_details_sha256": "tools/landscape_details.py",
}
IDENTITY = ((1., 0., 0., 0.), (0., 1., 0., 0.),
            (0., 0., 1., 0.), (0., 0., 0., 1.))


class AuditError(ValueError):
    """A concrete failed delivery invariant."""


def require(condition, message):
    if not condition:
        raise AuditError(message)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def contained(base, relative):
    require(isinstance(relative, str) and relative, "Missing relative file path")
    path = (Path(base) / relative).resolve()
    require(path.is_relative_to(Path(base).resolve()), "File escapes delivery directory: " + relative)
    require(path.is_file(), "Missing delivered file: " + str(path))
    return path


def finite_numbers(values, count, label):
    require(isinstance(values, (list, tuple)) and len(values) == count,
            "Invalid " + label)
    require(all(isinstance(v, (int, float)) and not isinstance(v, bool)
                and math.isfinite(v) for v in values), "Nonfinite " + label)
    return [float(v) for v in values]


def matmul(a, b):
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(4))
                       for c in range(4)) for r in range(4))


def transform(matrix, point):
    return [sum(matrix[r][c] * (point[c] if c < 3 else 1.) for c in range(4))
            for r in range(3)]


def local_matrix(node):
    if "matrix" in node:
        require(not any(k in node for k in ("translation", "rotation", "scale")),
                "Node mixes matrix and TRS")
        flat = finite_numbers(node["matrix"], 16, "node matrix")
        return tuple(tuple(flat[c * 4 + r] for c in range(4)) for r in range(4))
    t = finite_numbers(node.get("translation", [0, 0, 0]), 3, "node translation")
    s = finite_numbers(node.get("scale", [1, 1, 1]), 3, "node scale")
    x, y, z, w = finite_numbers(node.get("rotation", [0, 0, 0, 1]), 4, "node rotation")
    require(abs(x*x + y*y + z*z + w*w - 1.) < .001, "Nonunit node quaternion")
    rotation = ((1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)),
                (2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)),
                (2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)))
    return tuple(tuple(rotation[r][c] * s[c] if c < 3 else t[r]
                       for c in range(4)) for r in range(3)) + ((0., 0., 0., 1.),)


def nearly_equal(actual, expected, tolerance=.0003):
    if isinstance(expected, (list, tuple)):
        return (isinstance(actual, (list, tuple)) and len(actual) == len(expected)
                and all(nearly_equal(a, b, tolerance) for a, b in zip(actual, expected)))
    if isinstance(expected, (int, float)) and not isinstance(expected, bool):
        return isinstance(actual, (int, float)) and abs(actual-expected) <= tolerance
    return actual == expected


def read_glb(path):
    """Read only the JSON chunk, validating every binary chunk boundary."""
    path = Path(path)
    size = path.stat().st_size
    require(size >= 20, "Truncated GLB: " + str(path))
    with path.open("rb") as handle:
        magic, version, length = struct.unpack("<4sII", handle.read(12))
        require(magic == b"glTF" and version == 2 and length == size,
                "Invalid GLB header or declared length: " + str(path))
        doc = None
        binary_bytes = 0
        chunk_count = 0
        while handle.tell() < size:
            require(size-handle.tell() >= 8, "Truncated GLB chunk header")
            chunk_length, chunk_type = struct.unpack("<II", handle.read(8))
            require(chunk_length % 4 == 0 and handle.tell()+chunk_length <= size,
                    "Invalid GLB chunk length")
            if chunk_count == 0:
                require(chunk_type == 0x4E4F534A, "GLB first chunk is not JSON")
                # The complete delivery has thousands of nodes, not gigabytes of JSON.
                require(chunk_length <= 128*1024*1024, "Implausibly large GLB JSON chunk")
                doc = json.loads(handle.read(chunk_length).decode("utf-8"))
            else:
                require(chunk_type == 0x004E4942 and chunk_count == 1,
                        "Unexpected or duplicate GLB binary chunk")
                binary_bytes = chunk_length
                handle.seek(chunk_length, 1)
            chunk_count += 1
        require(doc is not None and doc.get("asset", {}).get("version") == "2.0",
                "Missing glTF 2.0 asset")
    validate_resources(doc, binary_bytes)
    return doc


def validate_resources(doc, binary_bytes):
    def uris(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "uri":
                    require(isinstance(item, str) and item.startswith("data:"),
                            "External URI dependency: " + str(item))
                uris(item)
        elif isinstance(value, list):
            for item in value:
                uris(item)
    uris(doc)
    buffers = doc.get("buffers", [])
    require(len(buffers) <= 1, "GLB has multiple buffers")
    if buffers:
        buffer = buffers[0]
        require("uri" not in buffer, "Delivery requires an embedded GLB buffer")
        n = buffer.get("byteLength", -1)
        require(isinstance(n, int) and n >= 0 and 0 <= binary_bytes-n <= 3,
                "GLB binary chunk does not match buffer byteLength")
    else:
        require(binary_bytes == 0, "Unreferenced GLB binary chunk")
    views = doc.get("bufferViews", [])
    for view in views:
        require(view.get("buffer") == 0 and buffers, "Invalid bufferView buffer")
        start, length = view.get("byteOffset", 0), view.get("byteLength", -1)
        require(isinstance(start, int) and isinstance(length, int)
                and start >= 0 and length >= 0 and start+length <= buffers[0]["byteLength"],
                "bufferView outside embedded buffer")
    sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4,
                  "MAT2": 4, "MAT3": 9, "MAT4": 16}
    for accessor in doc.get("accessors", []):
        require(accessor.get("componentType") in sizes and accessor.get("type") in components,
                "Unsupported accessor component/type")
        count = accessor.get("count")
        require(isinstance(count, int) and count > 0, "Invalid accessor count")
        if "bufferView" not in accessor:
            require("sparse" in accessor, "Accessor has no data")
            continue
        index = accessor["bufferView"]
        require(isinstance(index, int) and 0 <= index < len(views), "Invalid accessor bufferView")
        view = views[index]
        # Exported geometry uses scalar/vector data; matrix byte padding is irrelevant here.
        element = sizes[accessor["componentType"]] * components[accessor["type"]]
        stride = view.get("byteStride", element)
        offset = accessor.get("byteOffset", 0)
        require(isinstance(stride, int) and stride >= element and isinstance(offset, int)
                and offset >= 0 and offset+(count-1)*stride+element <= view["byteLength"],
                "Accessor outside bufferView")
    for image in doc.get("images", []):
        if "bufferView" in image:
            require(0 <= image["bufferView"] < len(views), "Invalid embedded image bufferView")
        else:
            require(isinstance(image.get("uri"), str) and image["uri"].startswith("data:"),
                    "Image is neither embedded nor a data URI")


def inspect_document(doc):
    """Validate scene ownership and calculate loaded instance geometry costs."""
    nodes, meshes, accessors = (doc.get(k, []) for k in ("nodes", "meshes", "accessors"))
    scenes = doc.get("scenes", [])
    scene_index = doc.get("scene", 0)
    require(isinstance(scene_index, int) and 0 <= scene_index < len(scenes), "No default scene")
    reachable, parent, matrices = set(), {}, {}

    def walk(index, owner, matrix):
        require(isinstance(index, int) and 0 <= index < len(nodes), "Invalid scene node reference")
        require(index not in reachable, "Cyclic or multiply owned scene node")
        reachable.add(index)
        parent[index] = owner
        matrices[index] = matmul(matrix, local_matrix(nodes[index]))
        for child in nodes[index].get("children", []):
            walk(child, index, matrices[index])
    for index in scenes[scene_index].get("nodes", []):
        walk(index, None, IDENTITY)
    require(reachable, "Empty default GLB scene")
    require(len(reachable) == len(nodes), "GLB contains unreachable nodes outside its default scene")
    mesh_triangles, mesh_bounds = [], []
    for mesh in meshes:
        triangles, points = 0, []
        require(mesh.get("primitives"), "Empty mesh")
        for primitive in mesh["primitives"]:
            position = primitive.get("attributes", {}).get("POSITION")
            require(isinstance(position, int) and 0 <= position < len(accessors),
                    "Primitive missing valid POSITION accessor")
            pa = accessors[position]
            require(pa.get("type") == "VEC3", "POSITION is not VEC3")
            lo = finite_numbers(pa.get("min"), 3, "POSITION minimum")
            hi = finite_numbers(pa.get("max"), 3, "POSITION maximum")
            require(all(a <= b for a, b in zip(lo, hi)), "Inverted POSITION bounds")
            points.extend((lo, hi))
            index = primitive.get("indices")
            if index is None:
                count = pa["count"]
            else:
                require(isinstance(index, int) and 0 <= index < len(accessors), "Invalid index accessor")
                ia = accessors[index]
                require(ia.get("type") == "SCALAR" and ia.get("componentType") in (5121, 5123, 5125),
                        "Invalid triangle index data")
                count = ia["count"]
            mode = primitive.get("mode", 4)
            require(mode in (4, 5, 6), "Nontriangle geometry in delivery")
            require(mode != 4 or count % 3 == 0, "Incomplete triangle primitive")
            triangles += count//3 if mode == 4 else max(0, count-2)
        mesh_triangles.append(triangles)
        mesh_bounds.append(([min(p[k] for p in points) for k in range(3)],
                            [max(p[k] for p in points) for k in range(3)]))
    expanded = 0
    for index in reachable:
        if "mesh" in nodes[index]:
            mesh = nodes[index]["mesh"]
            require(isinstance(mesh, int) and 0 <= mesh < len(meshes), "Invalid node mesh")
            expanded += mesh_triangles[mesh]
    return {"nodes": nodes, "reachable": reachable, "parent": parent,
            "world_matrices": matrices, "mesh_bounds": mesh_bounds,
            "mesh_triangles": mesh_triangles, "triangles": expanded,
            "unique_mesh_triangles": sum(mesh_triangles), "meshes": len(meshes)}


def descendants(info, root):
    result, stack = set(), [root]
    while stack:
        index = stack.pop()
        require(index not in result, "Cyclic descendant hierarchy")
        result.add(index)
        stack.extend(info["nodes"][index].get("children", []))
    return result


def extras(info, index):
    value = info["nodes"][index].get("extras", {})
    require(isinstance(value, dict), "Node extras are not an object")
    return value


def mesh_count(info, indices):
    return sum("mesh" in info["nodes"][i] for i in indices)


def bounds(info, indices):
    points = []
    for i in indices:
        node = info["nodes"][i]
        if "mesh" not in node:
            continue
        lo, hi = info["mesh_bounds"][node["mesh"]]
        for x in (lo[0], hi[0]):
            for y in (lo[1], hi[1]):
                for z in (lo[2], hi[2]):
                    points.append(transform(info["world_matrices"][i], (x, y, z)))
    require(points, "Hierarchy has no actual mesh bounds")
    low = [min(p[k] for p in points) for k in range(3)]
    high = [max(p[k] for p in points) for k in range(3)]
    return {"min": low, "max": high, "size": [b-a for a, b in zip(low, high)]}


def unique_by_id(records, label):
    require(isinstance(records, list), "Missing " + label + " list")
    result = {}
    for record in records:
        ident = record.get("id")
        require(isinstance(ident, str) and ident and ident not in result, "Duplicate/missing " + label + " ID")
        result[ident] = record
    return result


def validate_unit(info, record, standalone=False, export_record=None):
    """Check actual collection ancestry and mesh-bearing semantic inventory."""
    ident = record["id"]
    roots = [i for i in info["reachable"] if extras(info, i).get("reserve_role") == "building"
             and extras(info, i).get("reserve_building_id") == ident]
    require(len(roots) == 1, "Expected exactly one reserve building root: " + ident)
    root = roots[0]
    owned = descendants(info, root)
    require(mesh_count(info, owned) > 0, "Empty reserve building: " + ident)
    for i in owned:
        owner = extras(info, i).get("reserve_building_id")
        require(owner in (None, ident), "Cross-building ownership in " + ident)
    root_extras = extras(info, root)
    require(root_extras.get("reserve_floor_count") == 1, "Reserve floor count lost: " + ident)
    require(nearly_equal(root_extras.get("footprint_m"), [record["width"], record["depth"]]),
            "Reserve footprint metadata differs: " + ident)
    roles = {}
    for field in ("roof_collection", "front_cover_collection", "interior_collection"):
        found = [i for i in owned if extras(info, i).get("source_collection") == record[field]]
        require(len(found) == 1, "Missing/duplicate " + field + " hierarchy: " + ident)
        roles[field] = descendants(info, found[0])
        require(mesh_count(info, roles[field]) > 0, "Empty " + field + ": " + ident)
    require(not (roles["roof_collection"] & roles["front_cover_collection"]),
            "Roof and front cover overlap ownership: " + ident)
    require(not (roles["interior_collection"] & (roles["roof_collection"] | roles["front_cover_collection"])),
            "Interior is owned by a removable exterior cover: " + ident)
    expected_rooms = unique_by_id(record["rooms"], "room")
    actual_rooms = {}
    for i in owned:
        meta = extras(info, i)
        if meta.get("reserve_room_id") and meta.get("source_collection"):
            rid = meta["reserve_room_id"]
            require(rid not in actual_rooms, "Duplicate room collection: " + rid)
            actual_rooms[rid] = i
    require(set(actual_rooms) == set(expected_rooms), "Room IDs differ: " + ident)
    for rid, room in expected_rooms.items():
        node_index = actual_rooms[rid]
        meta = extras(info, node_index)
        require(node_index in roles["interior_collection"], "Room outside interior hierarchy: " + rid)
        require(meta.get("purpose") == room["purpose"] and meta.get("reserve_floor_index") == room["floor_index"],
                "Room purpose/floor metadata differs: " + rid)
        require(nearly_equal(meta.get("bounds_local_m"), room["bounds_m"]), "Room bounds differ: " + rid)
        require(mesh_count(info, descendants(info, node_index)) > 0, "Empty room geometry: " + rid)
    expected_assets = unique_by_id(record["assets"], "furnishing")
    actual_assets = defaultdict(list)
    picnic_ids = set()
    for i in owned:
        meta = extras(info, i)
        if meta.get("reserve_role") == "picnic_table_with_seats":
            require("mesh" in info["nodes"][i], "Outdoor picnic has no mesh")
            picnic_ids.add(meta.get("reserve_asset_id"))
        if meta.get("reserve_role") != "furnishing":
            continue
        aid = meta.get("reserve_asset_id")
        require(aid in expected_assets, "Unknown/unidentified furnishing in " + ident + ": " + str(aid))
        actual_assets[aid].append(i)
    require(set(actual_assets) == set(expected_assets), "Furnishing IDs differ: " + ident)
    for aid, asset in expected_assets.items():
        for i in actual_assets[aid]:
            meta = extras(info, i)
            require("mesh" in info["nodes"][i], "Furnishing metadata lacks actual mesh: " + aid)
            require(meta.get("reserve_room_id") == asset["room_id"], "Furnishing room ownership differs: " + aid)
            require(i in descendants(info, actual_rooms[asset["room_id"]]), "Furnishing outside its room: " + aid)
            require(meta.get("reusable_asset") is True and meta.get("reserve_floor_index") == 0,
                    "Reusable furnishing/floor metadata lost: " + aid)
            require(nearly_equal(meta.get("collision_proxy_local_xy"), asset["footprint_m"]),
                    "Furnishing footprint metadata differs: " + aid)
            require(nearly_equal(meta.get("approach_local_m"), asset["approach_local_m"]),
                    "Furnishing approach metadata differs: " + aid)
            if asset.get("integrated_fixtures"):
                integrated = meta.get("integrated_fixtures")
                if isinstance(integrated, str):
                    integrated = json.loads(integrated)
                require(integrated == asset["integrated_fixtures"], "Integrated kitchen fixtures lost: " + aid)
            if asset.get("integrated_seating"):
                require(meta.get("integrated_seating") == asset["integrated_seating"], "Contained seating metadata lost: " + aid)
    if record["kind"] == "trailer":
        require(picnic_ids == {ident+"_Outdoor_Picnic"}, "Trailer outdoor picnic assembly lost: " + ident)
    floor_nodes = [i for i in owned if extras(info, i).get("source_collection")
                   and extras(info, i).get("finished_floor_local_z_m") is not None]
    require(len(floor_nodes) == 1, "Missing/duplicate finished floor datum: " + ident)
    floor_meta = extras(info, floor_nodes[0])
    require(nearly_equal(floor_meta["finished_floor_local_z_m"], record["finished_floor_local_z_m"]),
            "Finished floor local datum differs: " + ident)
    actual_bounds = None
    if standalone:
        building_roots = [i for i in info["reachable"] if extras(info, i).get("reserve_role") == "building"]
        require(building_roots == roots, "Standalone contains another reserve building")
        require(nearly_equal(info["world_matrices"][root], IDENTITY, .00001), "Standalone building root is not local-origin identity: " + ident)
        require(owned == info["reachable"], "Standalone contains nodes outside its reserve unit: " + ident)
        actual_bounds = bounds(info, owned)
        # Site decks/steps/awnings may extend a few metres beyond the shell.
        radius = max(record["width"], record["depth"])/2 + 6
        require(max(abs(v) for axis in (0, 2) for v in (actual_bounds["min"][axis], actual_bounds["max"][axis])) <= radius,
                "Standalone geometry remains in absolute site coordinates: " + ident)
        if export_record:
            declared = export_record.get("local_bounds_gltf_metres", {})
            require(all(nearly_equal(actual_bounds[k], declared.get(k), .003) for k in ("min", "max", "size")),
                    "Standalone actual bounds differ from export manifest: " + ident)
    elif export_record:
        origin = record.get("center_m", record.get("center"))
        expected = [origin[0], record["pad_level_m"], -origin[1]]
        require(nearly_equal(transform(info["world_matrices"][root], [0, 0, 0]), expected, .003),
                "Complete-town building placement differs: " + ident)
        require(nearly_equal(export_record.get("placement_gltf_xyz"), expected), "Manifest reserve placement differs: " + ident)
    return {"id": ident, "rooms": len(actual_rooms), "furnishings": len(actual_assets),
            "mesh_nodes": mesh_count(info, owned), "outdoor_picnic_assemblies": len(picnic_ids),
            "local_bounds_gltf_metres": actual_bounds}


def validate_trees(info, native_environment, plan, linked_meshes):
    trees = defaultdict(list)
    meshes = set()
    species, zones = Counter(), Counter()
    for i in info["reachable"]:
        meta = extras(info, i)
        if meta.get("reserve_role") != "tree":
            continue
        node = info["nodes"][i]
        require("mesh" in node, "Tree instance has no mesh")
        source = meta.get("source_object", node.get("name", ""))
        match = re.match(r"^Reserve_Tree_(\d+)_", source)
        require(match is not None, "Tree instance identity lost: " + source)
        trees[match.group(1)].append(i)
        meshes.add(node["mesh"])
    for ident, indices in trees.items():
        first = extras(info, indices[0])
        require(first.get("tree_species") and first.get("reserve_zone") and first.get("lod") in ("near", "far"),
                "Tree species/zone/LOD lost: " + ident)
        for i in indices[1:]:
            current = extras(info, i)
            require(all(current.get(k) == first.get(k) for k in ("tree_species", "reserve_zone", "lod"))
                    and nearly_equal(info["world_matrices"][i], info["world_matrices"][indices[0]]),
                    "Tree prototype parts do not share instance placement: " + ident)
        species[first["tree_species"]] += 1
        zones[first["reserve_zone"]] += 1
    expected_zones = {z["id"]: z["target_tree_count"] for z in plan["forest_zones"]}
    require(len(trees) == native_environment.get("tree_instances") == sum(expected_zones.values()),
            "Actual/native/planned woodland tree counts differ")
    require(dict(species) == native_environment.get("tree_species"), "Actual tree species inventory differs")
    require(dict(zones) == expected_zones, "Actual tree instances do not fill each planned woodland zone")
    require(isinstance(linked_meshes, int) and len(meshes) == linked_meshes and 0 < len(meshes) < len(trees),
            "Woodland geometry is not shared as declared")
    references = Counter(info["nodes"][i]["mesh"] for indices in trees.values() for i in indices)
    require(max(references.values()) > 1, "No actual repeated forest mesh reference")
    return {"tree_instances": len(trees), "tree_mesh_nodes": sum(map(len, trees.values())),
            "shared_meshes": len(meshes), "species": dict(species), "zones": dict(zones),
            "expanded_tree_triangles": sum(info["mesh_triangles"][mesh]*n for mesh, n in references.items()),
            "unique_tree_mesh_triangles": sum(info["mesh_triangles"][mesh] for mesh in meshes)}


def check_file_record(path, record, info):
    require(record.get("sha256") == sha256(path), "GLB byte hash differs: " + str(path))
    require(record.get("bytes") == Path(path).stat().st_size, "GLB byte length differs: " + str(path))
    require(record.get("self_contained") is True, "Manifest does not declare self-contained GLB")
    require(record.get("nodes") == len(info["nodes"]) and record.get("meshes") == info["meshes"],
            "GLB node/mesh inventory differs: " + str(path))
    require(record.get("triangles") == info["triangles"], "Loaded instance triangles differ: " + str(path))
    require(record.get("unique_mesh_triangles") == info["unique_mesh_triangles"], "Unique mesh triangles differ: " + str(path))


def validate_environment(info, native_environment, plan):
    """Ensure geometry-bearing trails/crossings/site works survived export."""
    actual = defaultdict(set)
    for i in info["reachable"]:
        meta = extras(info, i)
        role = meta.get("reserve_role")
        if role in ("trail", "bridge", "stone_stairs", "retaining_wall", "terrain"):
            require("mesh" in info["nodes"][i], "Reserve environment role has no actual mesh")
            field = {"trail": "reserve_route_id", "bridge": "reserve_bridge_id",
                     "stone_stairs": "reserve_stair_id", "retaining_wall": "reserve_structure_id"}.get(role)
            ident = meta.get(field) if field else "terrain"
            require(isinstance(ident, str) and ident, "Reserve environment geometry lost role ID")
            actual[role].add(ident)
    expected = {
        "trail": {p["id"] for p in native_environment.get("paths", []) if p.get("sample_count", 0) > 0},
        "bridge": {p["id"] for p in plan.get("bridges", [])},
        "stone_stairs": {p["id"] for p in plan.get("stairs", [])},
        "retaining_wall": {p["id"] for p in plan.get("site_earthworks", {}).get("retaining_edges", [])},
        "terrain": {"terrain"},
    }
    for role, ids in expected.items():
        require(actual[role] == ids, "Reserve geometry IDs differ for role " + role)
    require({p["id"] for p in native_environment.get("crossings", [])} == expected["bridge"]
            and {p["id"] for p in native_environment.get("stairs", [])} == expected["stone_stairs"],
            "Native bridge/stair program differs from plan")
    return {role: sorted(ids) for role, ids in actual.items()}


def verify(root, manifest=None):
    """Return a source-bound audit; missing/in-progress exports are FAIL, never PASS."""
    root = Path(root).resolve()
    manifest = Path(manifest).resolve() if manifest else root/"game_assets/export_manifest.json"
    report = {"schema": SCHEMA, "generated_utc": datetime.now(timezone.utc).isoformat(),
              "status": "FAIL", "checks": [], "scope": "Independent GLB structure, resource containment, hashes, native semantic inventory, local prefab coordinates and loaded instance geometry cost. No engine import, visual, physics or runtime-performance claim."}

    def check(ident, operation):
        try:
            detail = operation()
            report["checks"].append({"id": ident, "status": "PASS", "details": detail})
            return detail
        except (AuditError, OSError, ValueError, KeyError, TypeError, IndexError, struct.error, RecursionError) as exc:
            report["checks"].append({"id": ident, "status": "FAIL", "error": str(exc)})
            return None

    loaded = {}
    def sources():
        m = read_json(manifest)
        n = read_json(root/"town_manifest.json")
        p = read_json(root/"reserve_plan.json")
        require(m.get("status") == "PASS" and m.get("evidence_label") == "final", "Export is missing final PASS status")
        blend = contained(root, m["source_blend"])
        source_sha = sha256(blend)
        require(m.get("source_blend_sha256") == source_sha, "Export does not bind current saved blend bytes")
        require(m.get("source_manifest_sha256") == sha256(root/"town_manifest.json"), "Export native manifest is stale")
        require(m.get("exporter_sha256") == sha256(root/"tools/export_game_assets.py"), "Exporter source changed after export")
        hashes = {}
        for field, relative in {**CORE_BINDINGS, **RESERVE_BINDINGS}.items():
            value = sha256(contained(root, relative))
            require(n.get(field) == m.get("source_"+field) == value, "Current/native/export binding differs: " + field)
            hashes[field] = value
        loaded.update(manifest=m, native=n, plan=p, hashes=hashes)
        report.update(source_blend_sha256=source_sha, export_manifest_sha256=sha256(manifest),
                      source_manifest_sha256=m["source_manifest_sha256"], source_bindings=hashes)
        return {"source_blend": blend.name, "reserve_binding_count": len(RESERVE_BINDINGS), "planning_binding_count": len(hashes)}
    if check("current_source_and_export_bindings", sources) is None:
        report["passed"] = 0
        report["failed"] = len(report["checks"])
        return report
    m, n, plan = loaded["manifest"], loaded["native"], loaded["plan"]
    records = {}
    exports = {}
    def native_inventory():
        native_report = n.get("reserve_amenities", {})
        env = n.get("reserve_environment", {})
        require(native_report == m.get("reserve_amenities") and env == m.get("reserve_environment"), "Export reserve native report differs")
        expected = unique_by_id(plan["buildings"], "planned building")
        records.update(unique_by_id(native_report.get("buildings"), "native reserve building"))
        exports.update(unique_by_id(m.get("reserve_buildings"), "export reserve building"))
        require(len(expected) == 21 and set(expected) == set(records) == set(exports), "Reserve21 program IDs differ across plan/native/export")
        require(native_report.get("building_count") == m.get("reserve_building_count") == len(records), "Reserve building totals differ")
        semantic = hashlib.sha256(json.dumps(plan, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        require(native_report.get("reserve_plan_semantic_sha256") == semantic, "Native amenity geometry does not bind current plan content")
        for ident, record in records.items():
            source = expected[ident]
            center = source.get("center_m", source.get("center"))
            require(nearly_equal(record.get("center_m", record.get("center")), center), "Reserve native center differs: " + ident)
            require(nearly_equal([record["width"], record["depth"]], source.get("size_m", [source["width"], source["depth"]]))
                    and nearly_equal(record["yaw_degrees"], source["yaw_degrees"])
                    and nearly_equal(record["pad_level_m"], source["pad_level_m"]), "Reserve native size/yaw/pad differs: " + ident)
            require(record["room_count"] == len(record["rooms"]) == exports[ident]["room_count"]
                    and record["furnishing_count"] == len(record["assets"]) == exports[ident]["furnishing_count"], "Unit native/export counts differ: " + ident)
        room_total = sum(len(r["rooms"]) for r in records.values())
        asset_total = sum(len(r["assets"]) for r in records.values())
        require(room_total == native_report.get("room_count") and asset_total == native_report.get("furnishing_count"), "Native room/furnishing totals differ")
        require(len({room["id"] for r in records.values() for room in r["rooms"]}) == room_total
                and len({asset["id"] for r in records.values() for asset in r["assets"]}) == asset_total,
                "Reserve room/furnishing IDs are not globally unique")
        audits = native_report.get("layout_audits", [])
        require(len(audits) == 21 and all(a.get("status") == "PASS" for a in audits), "Native reserve layout audits incomplete")
        return {"buildings": len(records), "rooms": room_total, "furnishings": asset_total,
                "native_geometry_report_status": native_report.get("status"),
                "native_visual_qa_claimed": native_report.get("rendered_qa", False)}
    if check("native_plan_and_program_inventory", native_inventory) is None:
        report["passed"] = sum(c["status"] == "PASS" for c in report["checks"])
        report["failed"] = len(report["checks"])-report["passed"]
        return report
    town_records = {}
    for field in ("town", "town_high_detail", "town_game"):
        if isinstance(m.get(field), dict):
            record = m[field]
            previous = town_records.setdefault(record["file"], record)
            if previous != record:
                check("consistent_town_record_alias:"+field,
                      lambda: require(False, "Contradictory complete-town records for the same GLB file"))
    if not town_records:
        check("complete_town_glb_present", lambda: require(False, "No complete town GLB records"))
    for relative, record in town_records.items():
        def town_audit(relative=relative, record=record):
            path = contained(manifest.parent, relative)
            info = inspect_document(read_glb(path))
            check_file_record(path, record, info)
            bindings = [extras(info, i) for i in info["reachable"]
                        if extras(info, i).get("asset_schema") == "living_town.glb.v1"]
            require(len(bindings) == 1 and bindings[0].get("source_blend_sha256") == report["source_blend_sha256"], "GLB town source root binding lost")
            # Terrain-plan bytes are bound by the native/export manifests;
            # portable_binding_fields is the exporter contract for root extras.
            portable_fields = m.get("portable_binding_fields", [])
            require(set(RESERVE_BINDINGS).issubset(portable_fields), "Portable root omits a reserve binding")
            require(all(k in loaded["hashes"] and bindings[0].get(k) == loaded["hashes"][k]
                        for k in portable_fields), "GLB root planning/reserve source bindings differ")
            actual_roots = [extras(info, i).get("reserve_building_id") for i in info["reachable"]
                            if extras(info, i).get("reserve_role") == "building"]
            require(len(actual_roots) == 21 and set(actual_roots) == set(records), "Complete-town reserve roots differ")
            units = [validate_unit(info, native, export_record=exports[ident]) for ident, native in records.items()]
            trees = validate_trees(info, n["reserve_environment"], plan, m.get("linked_reserve_tree_meshes"))
            environment = validate_environment(info, n["reserve_environment"], plan)
            return {"file": relative, "sha256": record["sha256"], "bytes": path.stat().st_size,
                    "loaded_instance_triangles": info["triangles"], "unique_mesh_triangles": info["unique_mesh_triangles"],
                    "reserve_units": units, "woodland": trees, "environment_geometry": environment}
        check("complete_town:"+relative, town_audit)
    for ident, native in records.items():
        def prefab_audit(ident=ident, native=native):
            record = exports[ident].get("standalone")
            require(isinstance(record, dict), "Missing independent reserve prefab: " + ident)
            path = contained(manifest.parent, record["file"])
            require(path.parent.name == "reserve" and path.suffix.lower() == ".glb", "Unexpected reserve prefab location")
            info = inspect_document(read_glb(path))
            check_file_record(path, record, info)
            detail = validate_unit(info, native, standalone=True, export_record=record)
            return {**detail, "file": record["file"], "sha256": record["sha256"], "triangles": info["triangles"]}
        check("local_origin_prefab:"+ident, prefab_audit)
    def budget():
        game = m.get("town_game")
        require(isinstance(game, dict), "No optimized complete-town export")
        optimization = m.get("optimization", {})
        limit = optimization.get("game_triangle_budget")
        require(isinstance(limit, int) and game["triangles"] <= limit and optimization.get("game_budget_passed") is True,
                "Expanded instance geometry exceeds declared game budget")
        return {"loaded_instance_triangles": game["triangles"], "budget_triangles": limit,
                "interpretation": "Loaded triangle cost, including every tree instance; not a measured runtime frame cost."}
    check("expanded_instance_game_triangle_budget", budget)
    report["passed"] = sum(c["status"] == "PASS" for c in report["checks"])
    report["failed"] = len(report["checks"])-report["passed"]
    report["status"] = "PASS" if not report["failed"] else "FAIL"
    return report


def self_test():
    """Small real binary fixtures; negative cases must be rejected explicitly."""
    import copy
    tests = []
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": [{"children": [1, 2]}, {"mesh": 0}, {"mesh": 0, "translation": [2, 0, 0]}],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
           "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
                         {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],
           "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
           "buffers": [{"byteLength": 44}]}
    binary = struct.pack("<9f3H", 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 2)+b"\0\0"
    def write_glb(path, value):
        text = json.dumps(value, separators=(",", ":")).encode()
        text += b" "*((-len(text)) % 4)
        total = 12+8+len(text)+8+len(binary)
        Path(path).write_bytes(struct.pack("<4sII", b"glTF", 2, total)+struct.pack("<II", len(text), 0x4E4F534A)+text+struct.pack("<II", len(binary), 0x004E4942)+binary)
    def run(name, callback, rejected=False):
        try:
            callback()
        except (AuditError, ValueError, KeyError, IndexError) as exc:
            require(rejected, "Positive self-test failed: "+name+": "+str(exc))
            tests.append({"id": name, "status": "PASS", "rejected": str(exc)})
            return
        require(not rejected, "Negative self-test incorrectly accepted: " + name)
        tests.append({"id": name, "status": "PASS"})
    with tempfile.TemporaryDirectory(prefix="reserve_export_selftest_") as tmp:
        path = Path(tmp)/"fixture.glb"
        write_glb(path, doc)
        run("embedded_glb_parse", lambda: read_glb(path))
        info = inspect_document(read_glb(path))
        run("expanded_shared_mesh_cost", lambda: require(info["triangles"] == 2 and info["unique_mesh_triangles"] == 1, "Instance triangles undercounted"))
        run("trs_bounds", lambda: require(nearly_equal(bounds(info, info["reachable"])["max"], [3, 1, 0]), "Transformed bounds wrong"))
        broken = copy.deepcopy(doc); broken["images"] = [{"uri": "../texture.png"}]
        run("reject_external_uri", lambda: validate_resources(broken, len(binary)), True)
        broken = copy.deepcopy(doc); broken["accessors"][0]["count"] = 1000
        run("reject_accessor_overrun", lambda: validate_resources(broken, len(binary)), True)
        broken = copy.deepcopy(doc); broken["nodes"][1]["children"] = [0]
        run("reject_hierarchy_cycle", lambda: inspect_document(broken), True)
        broken = copy.deepcopy(doc); broken["nodes"][1]["children"] = [2]
        run("reject_multiple_parent", lambda: inspect_document(broken), True)
        broken = copy.deepcopy(doc); broken["nodes"].append({"mesh": 0})
        run("reject_unreachable_payload", lambda: inspect_document(broken), True)
        record = {"sha256": "0"*64, "bytes": path.stat().st_size, "self_contained": True,
                  "nodes": len(info["nodes"]), "meshes": info["meshes"], "triangles": 2, "unique_mesh_triangles": 1}
        run("reject_stale_file_hash", lambda: check_file_record(path, record, info), True)
        record["sha256"] = sha256(path); record["triangles"] = 1
        run("reject_unique_only_triangle_claim", lambda: check_file_record(path, record, info), True)
        original = path.read_bytes(); path.write_bytes(original[:-4])
        run("reject_truncated_glb", lambda: read_glb(path), True)
        run("reject_path_escape", lambda: contained(Path(tmp)/"child", "../fixture.glb"), True)
    # A minimal semantic unit exercises the same hierarchy checks as real21 units.
    semantic = copy.deepcopy(doc)
    semantic["nodes"] = [
        {"extras": {"reserve_role": "building", "reserve_building_id": "Reserve_Test", "reserve_floor_count": 1, "footprint_m": [4, 4]}, "children": [1, 2, 3]},
        {"extras": {"source_collection": "Test_Roof"}, "mesh": 0},
        {"extras": {"source_collection": "Test_Front"}, "mesh": 0},
        {"extras": {"source_collection": "Test_Interior"}, "children": [4]},
        {"extras": {"source_collection": "Test_L00", "finished_floor_local_z_m": .18}, "children": [5]},
        {"extras": {"source_collection": "Test_Room", "reserve_room_id": "Test_Room", "purpose": "test room", "reserve_floor_index": 0, "bounds_local_m": [-2, -2, 2, 2]}, "children": [6]},
        {"extras": {"reserve_role": "furnishing", "reserve_building_id": "Reserve_Test", "reserve_room_id": "Test_Room", "reserve_asset_id": "Test_Asset", "reserve_floor_index": 0, "reusable_asset": True, "collision_proxy_local_xy": [0, 0, 1, 1], "approach_local_m": [1, 1]}, "mesh": 0}]
    native = {"id": "Reserve_Test", "kind": "reception", "width": 4, "depth": 4,
              "finished_floor_local_z_m": .18, "roof_collection": "Test_Roof", "front_cover_collection": "Test_Front", "interior_collection": "Test_Interior",
              "rooms": [{"id": "Test_Room", "purpose": "test room", "floor_index": 0, "bounds_m": [-2, -2, 2, 2]}],
              "assets": [{"id": "Test_Asset", "room_id": "Test_Room", "footprint_m": [0, 0, 1, 1], "approach_local_m": [1, 1]}]}
    run("semantic_local_origin_unit", lambda: validate_unit(inspect_document(semantic), native, True))
    broken = copy.deepcopy(semantic); broken["nodes"][6]["extras"].pop("reserve_asset_id")
    run("reject_missing_furnishing_identity", lambda: validate_unit(inspect_document(broken), native, True), True)
    broken = copy.deepcopy(semantic); broken["nodes"][0]["translation"] = [-130, 7, 50]
    run("reject_world_space_prefab", lambda: validate_unit(inspect_document(broken), native, True), True)
    broken = copy.deepcopy(semantic); broken["nodes"][0]["children"] = [1, 2]; broken["nodes"][1]["children"] = [3]
    run("reject_interior_under_roof_cover", lambda: validate_unit(inspect_document(broken), native, True), True)
    broken = copy.deepcopy(semantic); broken["nodes"][6]["extras"]["reserve_room_id"] = "Wrong_Room"
    run("reject_furnishing_wrong_room", lambda: validate_unit(inspect_document(broken), native, True), True)
    woodland = copy.deepcopy(doc)
    woodland["nodes"] = [{"children": [1, 2, 3]}] + [
        {"mesh": 0, "translation": [i*4, 0, 0],
         "extras": {"reserve_role": "tree", "source_object": "Reserve_Tree_%04d_oak_0" % i,
                    "tree_species": "oak", "reserve_zone": "Woods", "lod": "far"}}
        for i in range(3)]
    tree_native = {"tree_instances": 3, "tree_species": {"oak": 3}}
    tree_plan = {"forest_zones": [{"id": "Woods", "target_tree_count": 3}]}
    run("shared_woodland_instance_inventory", lambda: validate_trees(inspect_document(woodland), tree_native, tree_plan, 1))
    broken = copy.deepcopy(woodland)
    broken["meshes"] = [copy.deepcopy(doc["meshes"][0]) for _ in range(3)]
    for i in range(3):
        broken["nodes"][i+1]["mesh"] = i
    run("reject_unshared_woodland_meshes", lambda: validate_trees(inspect_document(broken), tree_native, tree_plan, 3), True)
    broken = copy.deepcopy(woodland); broken["nodes"][1]["extras"]["tree_species"] = "pine"
    run("reject_wrong_tree_species_inventory", lambda: validate_trees(inspect_document(broken), tree_native, tree_plan, 1), True)
    broken = copy.deepcopy(woodland); broken["nodes"][2]["extras"]["source_object"] = "Reserve_Tree_0000_oak_1"
    run("reject_detached_tree_prototype_part", lambda: validate_trees(inspect_document(broken), tree_native, tree_plan, 1), True)
    return {"schema": SCHEMA+".self_test", "status": "PASS", "checks": tests, "passed": len(tests), "real_delivery_checked": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    report = self_test() if args.self_test else verify(args.root, args.manifest)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
