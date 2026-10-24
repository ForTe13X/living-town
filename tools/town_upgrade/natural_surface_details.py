"""Source-bound natural shore finish and budget-neutral low planting drifts.

The owning builder calls apply() once after botany/terrain. Shore boulders keep
their exact vertices, topology and transforms. Only named, recipe-verified
natural boulders receive original NaturalRock PBR; built masonry is excluded.
Low planting uses existing instances with the original siting/native guards.
No scene loading/saving, exporting, added meshes, or third-party inference.
"""
from __future__ import annotations

from collections import Counter
import ast
import hashlib
import json
import math
from pathlib import Path
import random
import struct


ROOT = Path(__file__).resolve().parents[2]
OWNER = "living_town.natural_surface_details.v1"
ROCK_NAME = "Granite_Headland_Granite"
ROCK_SOURCES = {
    ROCK_NAME: {"components": 30, "factory": "town"},
    "Coastal_Granite_Outcrops_Granite": {"components": 32, "factory": "legacy_town"},
}


def _sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _key(material):
    name = material.name
    if name.rsplit(".", 1)[-1].isdigit():
        name = name.rsplit(".", 1)[0]
    for prefix in ("LT_", "Expansion_"):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def _components(vertex_count, faces):
    parent = list(range(vertex_count))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for face in faces:
        for i in face[1:]:
            parent[root(i)] = root(face[0])
    groups = {}
    for i in range(vertex_count):
        groups.setdefault(root(i), []).append(i)
    return list(groups.values())


def _ellipsoid_binding(points, faces, tolerance=.0003, source_name=ROCK_NAME):
    """Recognize one of two exact n=7/rings=4 shore recipes, never masonry."""
    if source_name not in ROCK_SOURCES:
        raise ValueError("Natural shore object name is not an approved source batch")
    if len(points) != 35 or len(faces) not in (28, 56):
        raise ValueError("headland source vertex/polygon count differs")
    expected = [(j*7+i, j*7+(i+1) % 7, (j+1)*7+(i+1) % 7, (j+1)*7+i)
                for j in range(4) for i in range(7)]
    by_quad = {i: [] for i in range(28)}
    for face in faces:
        candidates = [i for i, quad in enumerate(expected) if set(face) <= set(quad)]
        if len(candidates) != 1:
            raise ValueError("headland source face connectivity differs")
        by_quad[candidates[0]].append(tuple(face))
    for i, quad in enumerate(expected):
        got = by_quad[i]
        if len(got) == 1 and len(got[0]) == 4 and set(got[0]) == set(quad):
            continue
        if len(got) != 2 or any(len(f) != 3 for f in got):
            raise ValueError("headland source triangulation differs")
        a, b, c, d = quad
        pair = {frozenset(f) for f in got}
        if pair not in ({frozenset((a, b, c)), frozenset((a, c, d))},
                        {frozenset((a, b, d)), frozenset((b, c, d))}):
            raise ValueError("headland illegal source quad diagonals")
    cx, cy = points[0][:2]
    cz = (points[0][2] + points[-1][2]) / 2
    rz = (points[-1][2] - points[0][2]) / 2
    rx = points[14][0] - cx
    ry = (points[15][1] - cy) / math.sin(2*math.pi/7)
    if source_name == ROCK_NAME:
        if not (.6-tolerance <= rx <= 2+tolerance and .5-tolerance <= ry <= 1.5+tolerance
                and .6-tolerance <= rz <= 1.5+tolerance and abs(cz+.25) < tolerance
                and -60-tolerance <= cy <= -48+tolerance):
            raise ValueError("headland source center/radius recipe differs")
        coast = 49+2*math.sin(cy*.055)-7*math.exp(-((cy-43)/10)**2)
        if not coast-3-tolerance <= cx <= coast+2+tolerance:
            raise ValueError("headland source coastal band differs")
    elif not (.5-tolerance <= rx <= 1.8+tolerance and .6-tolerance <= ry <= 1.5+tolerance
              and .5-tolerance <= rz <= 1.4+tolerance and abs(cz+.30) < tolerance
              and 43-tolerance <= cx <= 52+tolerance and 47-tolerance <= abs(cy) <= 61+tolerance):
        raise ValueError("coastal outcrop source center/radius recipe differs")
    error = 0.
    for j in range(5):
        lat = -math.pi/2+math.pi*j/4
        for i in range(7):
            angle = i*2*math.pi/7
            wanted = (cx+rx*math.cos(lat)*math.cos(angle),
                      cy+ry*math.cos(lat)*math.sin(angle), cz+rz*math.sin(lat))
            error = max(error, max(abs(a-b) for a, b in zip(points[j*7+i], wanted)))
    if error > tolerance:
        raise ValueError("headland vertices no longer match original ellipsoid recipe")
    return {"center_world_m": [cx, cy, cz], "radii_m": [rx, ry, rz],
            "maximum_recipe_error_m": error, "vertices": 35, "source_grid_quads": 28}


def _geometry_signature(ob):
    h = hashlib.sha256()
    for vertex in ob.data.vertices:
        h.update(struct.pack("<3d", *vertex.co))
    for face in ob.data.polygons:
        h.update(struct.pack("<I", len(face.vertices)))
        h.update(struct.pack("<"+"I"*len(face.vertices), *face.vertices))
    for row in ob.matrix_world:
        h.update(struct.pack("<4d", *row))
    return h.hexdigest()


def _source_material(bpy):
    material = bpy.data.materials.get("LT_NaturalRock")
    if material is None or not material.use_nodes:
        raise ValueError("Existing original LT_NaturalRock material is required")
    expected = {"natural_rock_"+kind+".png" for kind in ("basecolor", "roughness", "normal")}
    images = {}
    for node in material.node_tree.nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        name = Path(node.image.filepath).name
        if name not in expected:
            continue
        source = ROOT/"art/living_town/textures"/name
        source_sha = _sha(source)
        if node.image.packed_file:
            image_sha = hashlib.sha256(node.image.packed_file.data).hexdigest()
        else:
            actual = Path(bpy.path.abspath(node.image.filepath))
            image_sha = _sha(actual)
        if image_sha != source_sha:
            raise ValueError("NaturalRock packed pixels differ from original source: "+name)
        images[name] = {"sha256": source_sha, "source": str(source),
                        "packed_or_file_sha256": image_sha}
    if set(images) != expected:
        raise ValueError("NaturalRock requires all three bound original PBR maps")
    return material, images


def _repair_rock_object(api, source_name):
    bpy = api["bpy"]
    spec = ROCK_SOURCES[source_name]
    ob = bpy.data.objects.get(source_name)
    if ob is None:
        return {"status": "NOT_PRESENT_NO_MUTATIONS", "object": source_name,
                "limitation": "Exact optional source batch absent; arbitrary shore meshes are not substituted."}
    if ob.type == "MESH" and not ob.data.vertices and not ob.data.polygons:
        return {"status": "EMPTY_SOURCE_BATCH_NO_MUTATIONS", "object": source_name}
    if (ob.type != "MESH" or ob.data.users != 1 or len(ob.data.materials) != 1
            or ob.data.materials[0] is None or _key(ob.data.materials[0]) != "Granite"):
        raise ValueError("Exact headland mesh ownership/material binding differs")
    if ob.get("natural_surface_detail_owner"):
        raise ValueError("Natural shore details may be applied only once to a fresh candidate")
    faces = [tuple(p.vertices) for p in ob.data.polygons]
    groups = _components(len(ob.data.vertices), faces)
    if len(groups) != spec["components"]:
        raise ValueError("Source shore batch no longer contains its exact "+str(spec["components"])+" stones")
    components = []
    for indices in groups:
        remap = {v: i for i, v in enumerate(indices)}
        component_faces = [tuple(remap[v] for v in f) for f in faces if f[0] in remap]
        points = [tuple(ob.matrix_world@ob.data.vertices[i].co) for i in indices]
        components.append(_ellipsoid_binding(points, component_faces, source_name=source_name))
    if not ob.data.uv_layers or len(ob.data.uv_layers[0].data) != len(ob.data.loops):
        raise ValueError("Source headland requires its original first metric UV layer")
    material, maps = _source_material(bpy)
    recipe = ROOT/"art/living_town/tools/build_living_town.py"
    tree = ast.parse(recipe.read_text(encoding="utf-8"))
    function = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == spec["factory"]), None)
    if function is None:
        raise ValueError("Original source factory function is absent")
    before = _geometry_signature(ob)
    old_material = ob.data.materials[0].name
    old_uv = [tuple(loop.uv) for loop in ob.data.uv_layers[0].data]
    # Original granite uses coords/2. NaturalRock is a four-metre repeat.
    for loop in ob.data.uv_layers[0].data:
        loop.uv = (loop.uv.x*.5, loop.uv.y*.5)
    ob.data.uv_layers.active_index = 0
    ob.data.uv_layers[0].active_render = True
    ob.data.materials[0] = material
    ob["natural_surface_detail_owner"] = OWNER
    ob["natural_surface_repeat_metres"] = 4.
    ob.data.update()
    after = _geometry_signature(ob)
    if after != before:
        raise RuntimeError("Natural shore material repair changed source geometry or transform")
    return {"status": "SOURCE_AND_GEOMETRY_BOUND_REQUIRES_RENDER_REVIEW", "object": ob.name,
            "source_recipe": str(recipe), "source_recipe_sha256": _sha(recipe),
            "source_factory_function": spec["factory"],
            "source_factory_function_ast_sha256": hashlib.sha256(ast.dump(function, include_attributes=False).encode()).hexdigest(),
            "components": components, "from_material": old_material, "to_material": material.name,
            "source_maps": maps, "source_kind": "Original mathematical natural-rock material; no third-party media or model inference",
            "repeat_metres": 4., "uv0_scale_from_original": .5, "uv0_loop_count": len(old_uv),
            "geometry_transform_sha256_before": before, "geometry_transform_sha256_after": after,
            "preserved": ["all source vertices, faces and world transform", "coastline and terrain",
                          "all built walls, stairs, retaining masonry and their materials"]}


def _repair_rocks(api):
    results = []
    for name in ROCK_SOURCES:
        try:
            results.append(_repair_rock_object(api, name))
        except ValueError as exc:
            # Source/material/UV checks precede mutation, independently for
            # each exact named source batch. Rejecting one cannot hide another.
            results.append({"status": "SOURCE_BINDING_REJECTED_NO_MUTATIONS",
                            "object": name, "reason": str(exc)})
    changed = [row for row in results if row["status"] == "SOURCE_AND_GEOMETRY_BOUND_REQUIRES_RENDER_REVIEW"]
    rejected = [row for row in results if row["status"] == "SOURCE_BINDING_REJECTED_NO_MUTATIONS"]
    status = ("PARTIAL_SOURCE_BINDING_REJECTED_REQUIRES_REVIEW" if rejected else
              "SOURCE_AND_GEOMETRY_BOUND_REQUIRES_RENDER_REVIEW" if changed else "NO_ELIGIBLE_SOURCE_BATCH_NO_MUTATIONS")
    return {"status": status, "source_batches": results,
            "changed_object_count": len(changed), "rejected_object_count": len(rejected),
            "bound_natural_stone_components": sum(len(row["components"]) for row in changed),
            "selection_policy": "Exact whitelist only: town headland and legacy coastal outcrop factories. Built masonry and arbitrary Granite meshes excluded."}


def drift_targets(pond, buildings):
    """Five bounded design intents, always clipped by the unchanged siting guard."""
    targets = []
    if pond:
        x, y = pond["center"]
        rx, ry = pond["water_radii_m"]
        for ident, point, radii in (
            ("pond_west_low_drift", (x-rx-1.25, y-.7), (1.10, 1.65)),
            ("pond_south_low_drift", (x+.4, y-ry-1.65), (2.10, .85)),
            ("pond_northeast_low_drift", (x+rx+.45, y+ry+.45), (1.20, .90))):
            targets.append({"id": ident, "center": point, "radii": radii,
                            "habitat": "authored_garden_or_park_envelope"})
    bath = next((b for b in buildings if b["id"] == "Reserve_Bathhouse"), None)
    if bath:
        a = math.radians(bath["yaw_degrees"])
        w, d = bath["footprint_m"]
        for side in (-1, 1):
            lx, ly = side*w*.34, -d/2-1.45
            x, y = bath["center_m"][:2]
            point = (x+lx*math.cos(a)-ly*math.sin(a), y+lx*math.sin(a)+ly*math.cos(a))
            targets.append({"id": "bath_"+("left" if side < 0 else "right")+"_low_drift",
                            "center": point, "radii": (1.45, .90),
                            "habitat": "domestic_garden_border"})
    return targets


def candidate_ground(mask, hardscape, ground, x, y, radius, habitat, asset):
    """Same guards/grade limits as original low-understory placement, no waivers."""
    reason = mask.reason(x, y, radius, habitat)
    if reason:
        return None, reason
    if hardscape(x, y, radius):
        return None, "actual_native_hardscape"
    z = ground(x, y, float("nan"))
    step = max(.16, min(.55, radius*.7))
    heights = [ground(x+dx, y+dy, float("nan")) for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step))]
    if not math.isfinite(z) or not all(math.isfinite(q) for q in heights):
        return None, "no_actual_ground_surface"
    grade = max(abs(q-z)/step for q in heights)
    if grade > (.60 if asset == "fern_02" else .50):
        return None, "steep_or_broken_terrain"
    return (z, grade), None


def _reallocate_drifts(api, botanical):
    if not botanical or not botanical.get("understory", {}).get("placements"):
        return {"status": "NO_EXISTING_UNDERSTORY_NO_MUTATIONS", "moved_instances": 0}
    bpy, module = api["bpy"], api["module"]
    helper = module("natural_detail_existing_siting", Path(__file__).with_name("understory.py"))
    botany = module("natural_detail_existing_ground", Path(__file__).with_name("botany.py"))
    baseline = ROOT/"art/living_town"
    paths = {"master": baseline/"masterplan.json", "landscape": baseline/"landscape_plan.json",
             "reserve": baseline/"reserve_plan.json", "expansion": Path(api["expansion_dir"])/"territory_plan.json"}
    docs = {key: json.loads(path.read_text(encoding="utf-8-sig")) for key, path in paths.items()}
    mask = helper.Siting(docs["master"], docs["landscape"], docs["reserve"], docs["expansion"], api["buildings"])
    hardscape, hardscape_count = helper._hardscape(api)
    ground = botany.ground_surface()
    rows = botanical["understory"]["placements"]
    original_count, triangles = len(rows), botanical["understory"]["placed_triangles"]
    variants = {(r["asset"], r["variant"], r["lod"]): r for r in botanical["understory"]["source_variants"]}
    donors = [r for r in rows if r["habitat"] == "woodland_root_drift"
              and r["source_asset"] in ("fern_02", "grass_medium_01")
              and r["footprint_radius_m"] <= .62
              and math.hypot(r["position_m"][0]-26, r["position_m"][1]+42) > 140
              and all(math.hypot(r["position_m"][0]-b["center_m"][0],
                                 r["position_m"][1]-b["center_m"][1]) > 40 for b in api["buildings"])
              and variants[r["source_asset"], r["source_variant"], r["lod"]]["height_m"]*r["scale"] <= .72]
    donors.sort(key=lambda r: r["id"])
    rng = random.Random(20261020_18337)
    rng.shuffle(donors)
    donor_names = {r["id"] for r in donors}
    occupied = helper.Spatial(2.)
    for row in rows:
        if row["id"] not in donor_names:
            x, y = row["position_m"][:2]
            radius = row["footprint_radius_m"]
            occupied.add((x, y, radius), [x-radius, y-radius, x+radius, y+radius])
    rejected, moved, drifts, mesh_hashes = Counter(), [], [], {}
    pool = iter(donors)
    donor = next(pool, None)
    for drift in drift_targets(docs["landscape"].get("pond"), api["buildings"]):
        accepted = []
        for i in range(180):
            if donor is None or len(accepted) >= 12:
                break
            angle = i*2.399963+rng.uniform(-.12, .12)
            radial = math.sqrt((i % 40+.5)/40)*.86
            x = drift["center"][0]+math.cos(angle)*drift["radii"][0]*radial
            y = drift["center"][1]+math.sin(angle)*drift["radii"][1]*radial
            radius = donor["footprint_radius_m"]
            if any(math.dist((x, y), p[:2]) < max(.18, (radius+p[2])*.52)
                   for p in occupied.near(x, y, radius+.9)):
                rejected["nearby_existing_understory_drift"] += 1
                continue
            site, reason = candidate_ground(mask, hardscape, ground, x, y, radius, drift["habitat"], donor["source_asset"])
            if reason:
                rejected[reason.split(":", 1)[0]] += 1
                continue
            objects = [bpy.data.objects.get(name) for name in donor["objects"]]
            if any(ob is None or ob.type != "MESH" or ob.parent is not None
                   or ob.get("botanical_instance_id") != donor["id"] for ob in objects):
                rejected["donor_instance_binding_mismatch"] += 1
                donor = next(pool, None)
                continue
            z, grade = site
            before = list(donor["position_m"])
            delta = [x-before[0], y-before[1], z-before[2]]
            signatures = []
            for ob in objects:
                pointer = ob.data.as_pointer()
                if pointer not in mesh_hashes:
                    mesh_hashes[pointer] = helper._mesh_hash(ob.data)
                mesh = ob.data
                scale, rotation = tuple(ob.scale), tuple(ob.rotation_euler)
                signatures.append({"object": ob.name, "mesh": ob.data.name,
                                   "scale": list(ob.scale), "rotation_euler": list(ob.rotation_euler),
                                   "vertex_count": len(ob.data.vertices), "polygon_count": len(ob.data.polygons),
                                   "source_mesh_geometry_sha256": mesh_hashes[pointer]})
                ob.location = tuple(ob.location[k]+delta[k] for k in range(3))
                ob["planting_habitat"] = drift["habitat"]
                ob["planting_owner"] = drift["id"]
                ob["natural_detail_reallocation"] = OWNER
                if ob.data != mesh or tuple(ob.scale) != scale or tuple(ob.rotation_euler) != rotation:
                    raise RuntimeError("Understory reallocation changed source mesh/scale/yaw")
            row = {"id": donor["id"], "source_asset": donor["source_asset"], "from_position_m": before,
                   "from_habitat": donor["habitat"], "from_owner": donor["owner"],
                   "to_position_m": [x, y, z], "to_owner": drift["id"], "retained_objects": signatures,
                   "actual_ground_maximum_grade": grade, "footprint_radius_m": radius}
            donor.update(position_m=[x, y, z], habitat=drift["habitat"], owner=drift["id"],
                         actual_ground_maximum_grade=grade, concept_drift_reallocation=OWNER)
            occupied.add((x, y, radius), [x-radius, y-radius, x+radius, y+radius])
            moved.append(row)
            accepted.append(donor["id"])
            donor = next(pool, None)
        drifts.append({**drift, "moved_instance_ids": accepted,
                       "status": "PLANTED_REQUIRES_ACTUAL_RENDER_REVIEW" if accepted else "NO_SAFE_REALLOCATION"})
    if len(rows) != original_count or botanical["understory"]["placed_triangles"] != triangles:
        raise RuntimeError("Planting reallocation altered count/triangle budget")
    checked = set()
    for row in moved:
        for signature in row["retained_objects"]:
            mesh = bpy.data.objects[signature["object"]].data
            pointer = mesh.as_pointer()
            if pointer not in checked:
                if helper._mesh_hash(mesh) != signature["source_mesh_geometry_sha256"]:
                    raise RuntimeError("Understory reallocation changed actual source mesh geometry")
                checked.add(pointer)
    botanical["understory"]["habitat_counts"] = dict(Counter(row["habitat"] for row in rows))
    botanical["understory"]["concept_drift_reallocation"] = {"owner": OWNER, "moved_instances": len(moved),
                                                             "counts_and_source_meshes_unchanged": True}
    return {"status": "REALLOCATED_REQUIRES_NATIVE_AND_VISUAL_REVIEW" if moved else "NO_SAFE_REALLOCATION",
            "moved_instances": len(moved), "moves": moved, "drifts": drifts,
            "existing_instance_count_before": original_count, "existing_instance_count_after": len(rows),
            "understory_triangles_before": triangles, "understory_triangles_after": triangles,
            "native_hardscape_meshes_checked": hardscape_count,
            "input_bindings": {key: {"path": str(path.resolve()), "sha256": _sha(path)} for key, path in paths.items()},
            "guards": "Unchanged Siting.reason, exact native hardscape rays, actual terrain BVH and original source-specific slope limits; no clearance waivers",
            "rejections": dict(rejected),
            "limits": ["These are existing photographed fern/grass source instances, not a new sedge species claim.",
                       "No tree, threshold, path, pond, terrain, building, pot or source mesh geometry is moved or rebuilt.",
                       "Visible drift cohesion and coverage require actual same-camera review."]}


def apply(api, output, botanical_report):
    output = Path(output)
    target = output/"natural_surface_details_receipt.json"
    if target.exists():
        raise FileExistsError("Use a fresh candidate; natural details receipt already exists")
    try:
        rocks = _repair_rocks(api)
    except ValueError as exc:
        # Every source validation precedes the first UV/material mutation.
        # Preserve a complete inspectable candidate when an upstream recipe
        # differs; a rejected binding is explicit, never visual acceptance.
        rocks = {"status": "SOURCE_BINDING_REJECTED_NO_MUTATIONS", "object": ROCK_NAME,
                 "reason": str(exc)}
    drifts = _reallocate_drifts(api, botanical_report)
    if botanical_report:
        (output/"botanical_report.json").write_text(json.dumps(botanical_report, indent=2)+"\n", encoding="utf-8")
    receipt = {"schema": OWNER, "status": "BUILT_REQUIRES_NATIVE_AND_ACTUAL_VISUAL_REVIEW",
               "tool_sha256": _sha(__file__), "natural_shore": rocks, "low_planting_drifts": drifts,
               "botanical_report_sha256": _sha(output/"botanical_report.json") if botanical_report else None,
               "visual_status": "NOT_YET_RENDERED"}
    target.write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    return receipt
