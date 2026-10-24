"""Upgrade a loaded v6 town without discarding its authoritative architecture.

Called inside Blender by the owning build entrypoint. Importing this module is
engine-free. API: upgrade(api, baseline_root, expansion_dir, output), where api
contains bpy, Batch, MATS, collection, module and sha from build_expansion_scene.
No Blender file is opened, saved, rendered or exported here.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path


OWNER = "living_town.whole_town_upgrade.v1"
PAINTS = {"White": (.84, .82, .75), "Sage": (.24, .36, .31),
          "BluePaint": (.21, .34, .40), "Burgundy": (.35, .15, .16)}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def local_world(record, x, y, z=0):
    angle = math.radians(record["yaw_degrees"])
    return (record["center_m"][0]+x*math.cos(angle)-y*math.sin(angle),
            record["center_m"][1]+x*math.sin(angle)+y*math.cos(angle), record["pad_level_m"]+z)


def world_local(record, point):
    angle = math.radians(record["yaw_degrees"])
    x, y = point[0]-record["center_m"][0], point[1]-record["center_m"][1]
    return (x*math.cos(angle)+y*math.sin(angle), -x*math.sin(angle)+y*math.cos(angle), point[2]-record["pad_level_m"])


def _window(axis, coordinate, center, z, width, height, level, face):
    return {"axis": axis, "coordinate_m": coordinate, "center_m": center, "center_z_local_m": z,
            "width_m": width, "height_m": height, "level": level, "face": face,
            "expectation": "authored_geometric_wall_aperture"}


def core_window_ledger(record, neighbors):
    """Mirror the bound build_living_town.building recipe, including party walls.

    Attic dormers/cross-gable glazing are explicitly separate: the source adds
    glazed furniture onto roof/gable meshes, not a tested habitable wall hole.
    """
    if record["kind"] == "halles":
        return [], []
    ident = record["id"]
    w, d = record["footprint_m"]
    count_floors = record["floor_count"]
    angle = math.radians(record["yaw_degrees"])
    windows = []
    for side in (-1, 1):
        spans = []
        for other in neighbors:
            if other["id"] == ident:
                continue
            ow, od = other["footprint_m"]
            lx, ly, _ = world_local(record, (*other["center_m"][:2], record["pad_level_m"]))
            rel = (math.radians(other["yaw_degrees"])-angle) % math.pi
            if min(rel, math.pi-rel) < .015:
                pass
            elif abs(rel-math.pi/2) < .015:
                ow, od = od, ow
            else:
                continue
            if abs(side*w/2-(lx-side*ow/2)) > .065:
                continue
            lo, hi = max(-d/2, ly-od/2), min(d/2, ly+od/2)
            if hi > lo:
                spans.append((lo, hi))
        n = max(1, int(d/3))
        valid = [y for y in (-d/2+(j+.5)*d/n for j in range(n))
                 if not any(lo-.6 < y < hi+.6 for lo, hi in spans)]
        for level in range(count_floors):
            windows += [_window("x", side*w/2, y, level*2.85+1.38, .85, 1.25, level,
                                "side_west" if side == -1 else "side_east") for y in valid]
    commercial = record["kind"] in ("cafe", "shop", "bakery", "creperie", "halles", "hotel") or record.get("typology") == "shop_house"
    door_x = record["door_local_x"]
    n = max(1, int(w/2.6))
    positions = [-w/2+(i+.5)*w/n for i in range(n)]
    rear_count = max(1, int(w/3))
    for level in range(count_floors):
        windows += [_window("y", d/2, -(-w/2+(j+.5)*w/rear_count), level*2.85+1.38, .85, 1.25, level, "rear") for j in range(rear_count)]
        for x in positions:
            if level == 0 and abs(x-door_x) < 1.5:
                continue
            width = min(1.8 if commercial and level == 0 else 1., w/n*.55)
            height = 1.75 if commercial and level == 0 else 1.35
            windows.append(_window("y", -d/2, x, level*2.85+1.37, width, height, level, "front"))
    decorative = []
    if record.get("typology") == "cross_gable_villa":
        decorative.append({"kind": "cross_gable_glazing", "native_aperture_status": "not_asserted"})
    dormers = max(1, int(w/5.5)) if count_floors > 1 and record.get("typology") not in ("plain_gable", "cross_gable_villa") and record["kind"] not in ("work", "cannery", "netshed", "halles") else 0
    decorative += [{"kind": "attic_dormer_glazing", "index": i, "native_aperture_status": "not_asserted"} for i in range(dormers)]
    return windows, decorative


def reserve_window_ledger(record):
    p = record["reserve_source"]
    w, d = record["footprint_m"]
    ff, kind = p["finished_floor_local_z_m"], p["kind"]
    trailer, truck = kind == "trailer", kind == "food_truck"
    result = []
    if not truck:
        width = min(1.65, w*.22)
        for x in ((-w*.28, w*.28) if w > 5 else (-w*.32, w*.32)):
            if abs(x-p["entry_local"][0]) > width/2+p["entry_width_m"]/2+.17:
                height = .85 if trailer else 1.30
                bottom = 1.0 if trailer else .85
                result.append(_window("y", -d/2, x, ff+bottom+height/2, width, height, 0, "front"))
    for side in (-1, 1):
        for y in (-d*.30, d*.30):
            bottom = 1.05 if trailer else 1.45 if kind in ("bathhouse", "toilets") else .85
            height = .75 if trailer else .70 if kind in ("bathhouse", "toilets") else 1.30
            result.append(_window("x", side*w/2, y, ff+bottom+height/2, min(1.15, d*.18), height, 0,
                                  "side_west" if side == -1 else "side_east"))
    result.append(_window("y", d/2, 0, ff+(1.1 if trailer else 1.6)+.375, min(1.1, w*.30), .75, 0, "rear"))
    return result


def expansion_window_ledger(record, source):
    w, d = record["footprint_m"]
    ff = source.get("finished_floor_offset_m", .38)
    count = max(2, min(5, int((w-1.3)/2.25)))
    positions = [-w/2+(i+1)*w/(count+1) for i in range(count)]
    commercial = source["kind"] in {"cafe", "shop", "workshop", "creperie", "bakery"}
    result = []
    for level in range(record["floor_count"]):
        for x in positions:
            if level == 0 and abs(x) < 1.2:
                continue
            height = 1.44 if level else 1.60
            for side in (-1, 1):
                if side == -1 and level == 0 and commercial:
                    continue
                result.append(_window("y", side*d/2, x, ff+level*2.85+1.48, 1.02, height, level, "front" if side == -1 else "rear"))
        for side in (-1, 1):
            for y in (-d*.27, d*.27):
                result.append(_window("x", side*w/2, y, ff+level*2.85+1.47, .86, 1.36, level, "side_west" if side == -1 else "side_east"))
    if commercial:
        width = min(w*.26, w*.57-1.04-.32)
        result += [_window("y", -d/2, side*w*.285, ff+1.20, width, 1.60, 0, "front") for side in (-1, 1)]
    return result


def normalize_reserve(p):
    interior = {"id": p["id"], "kind": p["kind"], "footprint_m": [p["width"], p["depth"]],
                "floors": 1, "floor_count": 1, "clear_bounds_m": p["clear_bounds_m"],
                "core": None, "room_count": p["room_count"], "furnishing_count": p["furnishing_count"],
                "entrance_local_m": p["entry_local"], "levels": []}
    rooms = []
    for room in p["rooms"]:
        room = deepcopy(room)
        room["assets"] = [deepcopy(a) for a in p["assets"] if a["room_id"] == room["id"]]
        rooms.append(room)
    interior["levels"] = [{"level": 0, "finished_floor_local_z_m": p["finished_floor_local_z_m"],
                            "rooms": rooms, "partitions": p["partitions"], "slab_voids": [],
                            "stair_to_next_level": None, "access_keepouts": p["circulation_keepouts"]}]
    return interior


def source_records(baseline, expansion):
    manifest = read(baseline/"town_manifest.json")
    master = read(baseline/"masterplan.json")
    core_interiors = {b["id"]: b for b in manifest["interiors"]}
    master_ids = {b["id"] for b in master["buildings"]}
    if master_ids != {b["id"] for b in manifest["buildings"]} or master_ids != set(core_interiors):
        raise ValueError("Core authored/generated IDs differ")
    rows = []
    for b in manifest["buildings"]:
        yaw = b["yaw_degrees"]+(180 if b.get("front_face") == "N" else 0)
        interior = deepcopy(core_interiors[b["id"]])
        rows.append({**deepcopy(b), "group": "urban", "floor_count": b["floors"],
                     "pad_level_m": b["center_m"][2], "yaw_degrees": yaw,
                     "room_count": interior["room_count"], "furnishing_count": interior["furnishing_count"],
                     "collections": {"root": b["collection"], "front": b["front_collection"],
                                     "roof": b["roof_collection"], "upper": b["upper_cover_collection"]},
                     "interior": interior})
    for p in manifest["reserve_amenities"]["buildings"]:
        interior = normalize_reserve(p)
        rows.append({"id": p["id"], "group": "reserve", "kind": p["kind"],
                     "center_m": p["center"], "pad_level_m": p["pad_level_m"],
                     "yaw_degrees": p["yaw_degrees"], "footprint_m": [p["width"], p["depth"]],
                     "floors": 1, "floor_count": 1, "room_count": p["room_count"],
                     "furnishing_count": p["furnishing_count"], "reserve_source": deepcopy(p),
                     "door_local_x": p["entry_local"][0], "door_aperture_width_m": p["entry_width_m"],
                     "finished_floor_world_z_m": p["finished_floor_z_m"],
                     "collections": {"root": p["root_collection"], "front": p["front_cover_collection"],
                                     "roof": p["roof_collection"], "upper": p["id"]+"_UpperCover"},
                     "interior": interior})
    expansion_manifest = read(expansion/"scene/expansion_manifest.json")
    native_interiors = {b["id"]: b for b in read(expansion/"scene/interiors.json")["buildings"]}
    sources = {b["id"]: b for b in read(expansion/"territory_plan.json")["buildings"]}
    if set(sources) != set(native_interiors) or set(sources) != {b["id"] for b in expansion_manifest["buildings"]}:
        raise ValueError("Expansion authored/generated IDs differ")
    for b in expansion_manifest["buildings"]:
        rows.append({**deepcopy(b), "group": "expansion", "floors": b["floor_count"],
                     "door_local_x": 0, "interior": deepcopy(native_interiors[b["id"]])})
    core = [b for b in rows if b["group"] == "urban"]
    for b in rows:
        b["interior"]["floors"] = len(b["interior"]["levels"])
        b["interior"]["floor_count"] = len(b["interior"]["levels"])
        if b["group"] == "urban":
            b["window_apertures"], b["decorative_glazing"] = core_window_ledger(b, core)
        elif b["group"] == "reserve":
            b["window_apertures"] = reserve_window_ledger(b)
        else:
            b["window_apertures"] = expansion_window_ledger(b, sources[b["id"]])
            if len(b["window_apertures"]) != b["window_aperture_count"]:
                raise ValueError("Expansion aperture recipe/manifest mismatch: "+b["id"])
        b["window_aperture_count"] = len(b["window_apertures"])
        b["aperture_ledger_authority"] = "Exact existing bound generator recipe; actual mesh openings require native rays."
    return rows


def _components(mesh):
    parents = list(range(len(mesh.vertices)))
    def root(x):
        while parents[x] != x:
            parents[x] = parents[parents[x]]
            x = parents[x]
        return x
    for edge in mesh.edges:
        a, b = map(root, edge.vertices)
        parents[a] = b
    groups = defaultdict(list)
    for i in range(len(parents)):
        groups[root(i)].append(i)
    return list(groups.values())


def _bounds(points):
    return [min(p[i] for p in points) for i in range(3)]+[max(p[i] for p in points) for i in range(3)]


def _matches(actual, expected, tolerance=.0007):
    return max(abs(a-b) for a, b in zip(actual, expected)) <= tolerance


def repair_core_door(api, record):
    """Remove only five exact authored leaf components and the crossing plinth.

    Component bounds are checked in the building frame before any mutation. A
    partial/ambiguous match fails without deleting anything. Jambs, actual wall
    opening, glass in windows and offset source door positions are preserved.
    """
    if record["kind"] == "halles":
        # The source's x=0 entrance points at its real central timber post.
        # Use the adjacent open bay while staying inside the actual 3.2m steps.
        # A 1.0m corridor centred at x=1.10 lies inside x=.60..1.60, clear of
        # the centre post (half-width .10m) and the next post at x=3.25m.
        w = record["footprint_m"][0]
        bays = max(3, int(w/3))
        posts = [-w/2+i*w/bays for i in range(bays+1)]
        candidate = 1.10
        if any(abs(candidate-post) < .60 for post in posts):
            return {"building_id": record["id"], "status": "FAIL", "reason": "No source-bound clear market bay inside front steps"}
        record["source_door_local_x"] = record["door_local_x"]
        record["door_local_x"] = candidate
        record["interior"]["source_entrance_local_m"] = list(record["interior"]["entrance_local_m"])
        record["interior"]["entrance_local_m"][0] = candidate
        record["door_aperture_width_m"] = 1.0
        record["front_door_clear_width_m"] = 1.0
        record["front_door_state"] = "open timber market bay; original centre post preserved"
        return {"building_id": record["id"], "status": "MARKET_BAY_RELOCATED_REQUIRES_NATIVE_SWEEP",
                "source_door_local_x": record["source_door_local_x"], "door_local_x": candidate,
                "clear_width_inside_actual_front_steps_m": 1.0, "source_post_centres_local_x": posts,
                "modified_objects": [], "added_objects": []}
    bpy, Batch = api["bpy"], api["Batch"]
    front = bpy.data.collections.get(record["collections"]["front"])
    if front is None:
        return {"building_id": record["id"], "status": "FAIL", "reason": "missing front collection"}
    d, w, x = record["footprint_m"][1], record["footprint_m"][0], record["door_local_x"]
    y = -d/2
    targets = {
        "wood_leaf": [x-.48, y-.07, 0, x+.48, y+.04, 2.24],
        "glass_leaf": [x-.33, y-.0975, 1.115, x+.33, y-.0725, 2.045],
        "lower_panel_left": [x-.39, y-.0975, .22, x-.07, y-.0625, .72],
        "lower_panel_right": [x+.07, y-.0975, .22, x+.39, y-.0625, .72],
        "brass_knob": [x+.293, y-.210, .963, x+.367, y-.130, 1.037],
        "crossing_plinth": [-w/2, y-.12, .335, w/2, y-.02, .505],
    }
    timber_height = record["floor_count"]*2.85
    if record["kind"] == "halftimber" and abs(x) < .62:
        # The exact original vertical centre beam was drawn straight through
        # the door. Keep its upper continuation and the rest of the framework.
        targets["crossing_timber_post"] = [-.08, y-.245, 0, .08, y-.115, timber_height]
    found = defaultdict(list)
    # Only the exact source front batch; utility signs and later upgrades are
    # excluded even if their bounds happen to lie close to the door.
    for ob in front.all_objects:
        if ob.type != "MESH" or not ob.name.startswith(record["id"]+"_Front_"):
            continue
        for vertices in _components(ob.data):
            bounds = _bounds([world_local(record, ob.matrix_world@ob.data.vertices[i].co) for i in vertices])
            for label, target in targets.items():
                if _matches(bounds, target):
                    found[label].append((ob, vertices, bounds))
    missing = {label: len(found[label]) for label in targets if len(found[label]) != 1}
    if missing:
        return {"building_id": record["id"], "status": "FAIL", "reason": "exact leaf/plinth components not uniquely matched", "component_match_counts": missing}
    source_timber_material = (found["crossing_timber_post"][0][0].material_slots[0].material
                              if "crossing_timber_post" in found else None)
    import bmesh
    removals = defaultdict(list)
    receipts = []
    for label in targets:
        ob, vertices, bounds = found[label][0]
        removals[ob.name].extend(vertices)
        receipts.append({"component": label, "object": ob.name, "vertex_count": len(vertices), "source_bounds_local_m": bounds})
    for name, indices in removals.items():
        ob = bpy.data.objects[name]
        if ob.data.users > 1:
            ob.data = ob.data.copy()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(indices))], context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
    batch = Batch(record["id"]+"_Upgrade_OpenEntrance", front,
                  (*record["center_m"][:2], record["pad_level_m"]), math.radians(record["yaw_degrees"]))
    paint = "BluePaint" if record["kind"] in ("cafe", "shop", "creperie") else "Sage"
    # Fold the original .96 m leaf outward along -Y, completely outside the
    # central approach. Its low panel height stays as authored, below datum.
    hinge = x-.54
    batch.box((hinge, y-.60, 1.12), (.055, .96, 2.24), paint)
    batch.box((hinge-.036, y-.60, 1.58), (.018, .66, .93), "Glass")
    for delta in (-.23, .23):
        batch.box((hinge-.037, y-.60+delta, .47), (.018, .32, .5), "Oak")
    batch.ellipsoid((hinge-.065, y-.92, 1.0), (.025, .035, .035), "Brass", n=8, rings=4)
    # Split the old plinth outside both jambs and the .87 m actual inner width.
    gap_left, gap_right = x-.65, x+.65
    for lo, hi in ((-w/2, gap_left), (gap_right, w/2)):
        if hi > lo:
            batch.box(((lo+hi)/2, y-.07, .42), (hi-lo, .1, .17), "Stone")
    if source_timber_material and timber_height > 2.47:
        batch.box((0, y-.18, (timber_height+2.47)/2), (.16, .13, timber_height-2.47), "Trunk")
    added = batch.flush()
    for ob in added:
        if source_timber_material and ob.data.name.endswith("_Trunk"):
            # Retain the source timber's texture and exact physical UV basis,
            # rather than exchanging it for the generic palette brown.
            ob.material_slots[0].material = source_timber_material
            tile = source_timber_material.get("tile_size_metres", 2)
            uv = ob.data.uv_layers.get("MetricUV")
            if uv and tile != 2:
                for loop in uv.data:
                    loop.uv *= 2/tile
            ob["timber_post_starts_above_preserved_door_header_z_m"] = 2.47
            ob["source_timber_material"] = source_timber_material.name
        ob["building_id"] = record["id"]
        ob["semantic_role"] = "repaired_open_exterior_door_and_split_plinth"
        ob["door_state"] = "90 degrees outward from source .96 metre leaf"
        ob["door_aperture_width_m"] = 1.08
        ob["generator_owner"] = OWNER
    record["front_door_state"] = "day-open 90 degrees outward"
    record["front_door_clear_width_m"] = .87
    record["door_aperture_width_m"] = 1.08
    return {"building_id": record["id"], "status": "REPAIRED_REQUIRES_NATIVE_SWEEP", "components": receipts,
            "modified_objects": sorted(removals), "added_objects": [o.name for o in added],
            "clear_width_between_preserved_jambs_m": .87,
            "halftimber_post_split_above_source_header": bool(source_timber_material),
            "source_timber_material": source_timber_material.name if source_timber_material else None}


def _paint_materials(api):
    mats = api["MATS"]
    reports = []
    for name, color in PAINTS.items():
        material = mats["Oak"].copy()
        material.name = "TownUpgrade_PaintedOak_"+name
        nodes, links = material.node_tree.nodes, material.node_tree.links
        shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        for link in list(shader.inputs["Base Color"].links):
            links.remove(link)
        shader.inputs["Base Color"].default_value = (*color, 1)
        material.diffuse_color = (*color, 1)
        material["source_license"] = mats["Oak"].get("source_license", "")
        material["upgrade_recipe"] = "Painted oak: linear pigment color with source scanned oak normal and roughness; no fabricated PBR maps."
        mats["Painted"+name] = material
        reports.append({"material": material.name, "source": mats["Oak"].name, "linear_pigment_rgb": color})
    return reports


def _material_key(material):
    name = material.name.rsplit(".", 1)[0] if material.name.rsplit(".", 1)[-1].isdigit() else material.name
    for prefix in ("LT_", "Expansion_"):
        if name.startswith(prefix):
            return name[len(prefix):]
    return None


def _has_images(material):
    return bool(material.use_nodes and any(n.type == "TEX_IMAGE" and n.image for n in material.node_tree.nodes))


def _wall_mesh(ob, group):
    key = _material_key(ob.material_slots[0].material) if ob.material_slots and ob.material_slots[0].material else None
    if group == "expansion":
        return ob.get("semantic_role") == "apertured_exterior_wall"
    if group == "reserve":
        return ob.get("reserve_role") in ("exterior_shell_and_supports", "front_cover") and key in ("White", "Plaster", "BluePaint")
    return ("_SideWall" in ob.name or "_RearWindows" in ob.name or "_Front_" in ob.name) and key in ("Plaster", "Granite", "Stone", "Ochre", "PaleRose")


def _metric_uv(ob, record):
    """Physical planar projection in the building frame, exactly metres / 2.

    Z stays tied to the pad datum so context grime starts near local ground;
    fine scan normals retain their separate physical repeat transform.
    """
    mesh = ob.data
    layer = mesh.uv_layers.get("MetricUV") or mesh.uv_layers.new(name="MetricUV")
    local = [world_local(record, ob.matrix_world@v.co) for v in mesh.vertices]
    for polygon in mesh.polygons:
        normal = polygon.normal
        # Geometry in source batches is world-aligned at identity, whereas
        # reusable furnishings may have object transforms. Use actual edges.
        indices = list(polygon.vertices)
        if len(indices) < 3:
            continue
        a, b, c = (local[i] for i in indices[:3])
        e1, e2 = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
        n = (e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0])
        dominant = max(range(3), key=lambda i: abs(n[i]))
        axes = [i for i in range(3) if i != dominant]
        for loop_index in polygon.loop_indices:
            point = local[mesh.loops[loop_index].vertex_index]
            layer.data[loop_index].uv = (point[axes[0]]/2, point[axes[1]]/2)
    mesh.uv_layers.active = layer


def refresh_materials(api, record, modified, mapped_meshes):
    bpy, mats = api["bpy"], api["MATS"]
    root = bpy.data.collections.get(record["collections"]["root"])
    if root is None:
        raise ValueError("Missing building root: "+record["id"])
    counts = Counter()
    index = int(hashlib.sha256(record["id"].encode()).hexdigest()[:8], 16) % 5
    walls = []
    for ob in root.all_objects:
        if ob.type != "MESH":
            continue
        wall = _wall_mesh(ob, record["group"])
        ob["town_upgrade_wall_surface"] = bool(wall)
        if wall:
            walls.append(ob.name)
        changed = False
        replacements = []
        for slot_index, slot in enumerate(ob.material_slots):
            old = slot.material
            if old is None:
                raise ValueError("Empty material slot: "+ob.name)
            key = _material_key(old)
            target = None
            if key in ("Plaster", "Ochre", "PaleRose"):
                target = mats["Facade"+str(index)] if wall else mats["Plaster"]
            elif key and key.startswith("Facade") and key in mats:
                target = mats[key]
            elif key in ("Oak", "Granite", "Stone", "Tile"):
                target = mats[key]
            elif key in PAINTS:
                # Smooth sanitary ceramic and painted metal do not receive
                # wood grain. Existing ceramic parts stay smooth white.
                is_wood = key != "White" or any(token in ob.name for token in ("Joinery", "Door", "Window", "Facade"))
                if is_wood:
                    target = mats["Painted"+key]
            elif key in mats:
                # Preserve original textured slate/cloth when the expansion
                # equivalent is a flat swatch; replacing it loses detail.
                if not _has_images(old) or _has_images(mats[key]):
                    target = mats[key]
            if target is not None and target != old:
                replacements.append((slot_index, target, old.name))
        if replacements:
            # Object-linked slots avoid changing other owners of a shared
            # reusable mesh. glTF retains the explicit material assignment.
            for slot_index, target, old_name in replacements:
                ob.material_slots[slot_index].link = "OBJECT"
                ob.material_slots[slot_index].material = target
                counts[old_name+" -> "+target.name] += 1
            changed = True
        if any(_has_images(slot.material) and slot.material.name.startswith(("Expansion_", "TownUpgrade_")) for slot in ob.material_slots):
            # Shared furnishings use a local mesh frame and constant scans;
            # avoid the last building's projection mutating previous owners.
            if ob.data.users > 1 and ob.data.as_pointer() not in mapped_meshes:
                ob.data = ob.data.copy()
            if ob.data.as_pointer() not in mapped_meshes:
                _metric_uv(ob, record)
                mapped_meshes.add(ob.data.as_pointer())
            changed = True
        if changed:
            ob["town_upgrade_materials"] = "physical MetricUV; source scans and portable pixel-baked facade weather"
            modified.add(ob.name)
    record["exterior_wall_objects"] = walls
    return {"building_id": record["id"], "slot_replacements": dict(counts), "wall_objects": walls,
            "mesh_objects": sum(o.type == "MESH" for o in root.all_objects)}


def add_architecture(api, record):
    """Fitted trim and roof craft keep the original aperture/special-shell mesh."""
    bpy, Batch = api["bpy"], api["Batch"]
    front = bpy.data.collections[record["collections"]["front"]]
    roof = bpy.data.collections[record["collections"]["roof"]]
    w, d = record["footprint_m"]
    origin = (*record["center_m"][:2], record["pad_level_m"])
    angle = math.radians(record["yaw_degrees"])
    created = []
    # Keep already detailed expansion shells; material refresh still applies.
    if record["group"] == "expansion":
        return {"building_id": record["id"], "policy": "Existing detailed expansion shell retained", "added_objects": []}
    p = record.get("reserve_source", {})
    mobile = record["kind"] in ("trailer", "food_truck")
    special = record["kind"] in ("chapel", "windmill", "halles")
    front_batch = Batch(record["id"]+"_Upgrade_Joinery", front, origin, angle)
    if not special and not mobile:
        top = p.get("finished_floor_local_z_m", .0)+p.get("wall_height_m", record["floor_count"]*2.85)
        # Two restrained exterior cornice courses fit above all existing bays.
        for z, depth, height in ((top-.07, .23, .11), (top-.20, .14, .045)):
            front_batch.box((0, -d/2-.10, z), (w+.12, depth, height), "White" if height > .05 else "Stone")
        # Cast-iron shoe scrapers sit outside the walking and door corridor.
        door_x = record.get("door_local_x", 0)
        for side in (-1, 1):
            x = door_x+side*.82
            if abs(x)+.10 < w/2-.12:
                front_batch.box((x, -d/2-.18, .24), (.20, .10, .025), "Iron")
    # Painted number plates and small glazed enamel border add street scale,
    # staying away from the centre door, shop bays and all window holes.
    if w > 3.2 and not special:
        x, z = -w/2+.32, (p.get("finished_floor_local_z_m", .38)+1.66)
        front_batch.box((x, -d/2-.085, z), (.23, .035, .18), "BluePaint")
        for zz in (-.075, .075):
            front_batch.box((x, -d/2-.108, z+zz), (.21, .012, .012), "White")
        for xx in (-.105, .105):
            front_batch.box((x+xx, -d/2-.108, z), (.012, .012, .16), "White")
        # Small real mesh numeral marks avoid external font dependencies.
        number = 1+int(hashlib.sha256(record["id"].encode()).hexdigest()[:4], 16) % 4
        for i in range(number):
            front_batch.box((x+(i-(number-1)/2)*.032, -d/2-.12, z), (.008, .01, .075), "White")
    created.extend(front_batch.flush())
    # Existing roof forms are preserved. Fine extra slate seams are added only
    # to simple gables whose exact source roof equation is known.
    typology = record.get("typology", "")
    if record["group"] == "urban" and typology not in ("mansard_hotel", "cross_gable_villa") and not special:
        h = record["floor_count"]*2.85
        if record["kind"] in ("work", "cannery", "netshed"):
            h = 3.8
        rise = max(1.5, min(3.7, d*.38))
        b = Batch(record["id"]+"_Upgrade_SlateCraft", roof, origin, angle)
        # The canonical gable_roof ridge is at local Y=0 and eaves include
        # .25m overhang; samples follow its actual unmodified equation.
        for side in (-1, 1):
            rows = max(7, math.ceil(math.hypot(d/2+.24, rise)/.30))
            for j in range(1, rows):
                t = j/rows
                y = side*(d/2+.24)*(1-t)
                z = h+rise*t+.016
                b.rod((-w/2-.24, y, z), (w/2+.24, y, z), .009, "SlateLight", n=4)
        created.extend(b.flush())
    for ob in created:
        ob["building_id"] = record["id"]
        ob["generator_owner"] = OWNER
        ob["semantic_role"] = "fitted_architectural_joinery_and_roof_craft"
    return {"building_id": record["id"], "specialized_shell_retained": special or mobile,
            "policy": "Original shell/partitions/window openings unchanged; fitted detail only", "added_objects": [o.name for o in created]}


def add_furniture_craft(api, record):
    """Apply real-scale joinery detail inside existing furniture proxies.

    Canonical furniture poses already pass measured facing/density checks. No
    arbitrary rearrangement is made. Tiny brass fasteners and contained inset
    edges improve close-range reading without changing collision reservations.
    """
    bpy, Batch = api["bpy"], api["Batch"]
    if record["group"] == "expansion":
        return {"building_id": record["id"], "pose_policy": "Existing audited detailed furnishings retained", "assets": []}
    reports = []
    for floor in record["interior"]["levels"]:
        ff = floor["finished_floor_local_z_m"]
        for room in floor["rooms"]:
            room_col = bpy.data.collections.get(room["id"])
            if room_col is None:
                raise ValueError("Missing room collection: "+room["id"])
            for asset in room.get("assets", []):
                kind = asset["kind"]
                if kind not in ("bed", "bookshelf", "cupboard", "wardrobe", "linen_cabinet", "lockers", "writing_desk", "coffee_table", "reading_table", "meeting_table", "kitchen_run", "counter", "kitchen"):
                    continue
                w, d, h = asset["dimensions_m"]
                center = local_world(record, *asset["center_m"], ff)
                b = Batch(asset["id"]+"_Upgrade_Craft", room_col, center,
                          math.radians(record["yaw_degrees"]+asset.get("rotation_degrees", 0)))
                if kind == "bed" and record["group"] == "urban":
                    # Upholstery seam on the existing blanket, contained at
                    # z=.578 and width inside the authored mattress.
                    for side in (-1, 1):
                        b.rod((side*(w/2-.095), -d*.40, .577),
                              (side*(w/2-.095), d*.16, .577), .0035, "Linen", n=4)
                elif kind in ("writing_desk", "coffee_table", "reading_table", "meeting_table"):
                    z = .43 if kind == "coffee_table" else .76
                    for side in (-1, 1):
                        for yy in (-d/2+.075, d/2-.075):
                            b.rod((side*(w/2-.075), yy, z+.044),
                                  (side*(w/2-.075), yy, z+.050), .006, "Brass", n=8)
                elif kind in ("bookshelf", "cupboard", "wardrobe", "linen_cabinet", "lockers"):
                    for side in (-1, 1):
                        for zz in (.16, max(.2, h-.16)):
                            b.rod((side*(w/2-.024), -d*.34, zz),
                                  (side*(w/2-.015), -d*.34, zz), .007, "Brass", n=8)
                elif kind in ("kitchen", "kitchen_run", "counter"):
                    # Plinth kick plate stays in the original cabinet envelope;
                    # never crosses the kitchen sink opening or tap geometry.
                    b.box((0, -d/2+.012, .105), (max(.05, w-.10), .012, .045), "Zinc")
                created = b.flush()
                if not created:
                    continue
                for ob in created:
                    ob["building_id"] = record["id"]
                    ob["interior_building_id"] = record["id"]
                    ob["interior_asset_id"] = asset["id"]
                    ob["interior_room_id"] = room["id"]
                    ob["asset_role"] = kind
                    ob["reusable_asset"] = True
                    ob["generator_owner"] = OWNER
                    ob["semantic_role"] = "contained_furniture_craft_detail"
                    ob["collision_proxy_local_xy"] = asset["footprint_m"]
                    if record["group"] == "reserve":
                        ob["reserve_building_id"] = record["id"]
                        ob["reserve_room_id"] = room["id"]
                        ob["reserve_asset_id"] = asset["id"]
                        ob["reserve_role"] = "furnishing"
                reports.append({"asset_id": asset["id"], "room_id": room["id"], "added_objects": [o.name for o in created],
                                "pose_unchanged": True, "proxy_unchanged": True})
    return {"building_id": record["id"], "pose_policy": "Source-audited composition preserved", "assets": reports}


def classify(api, rows):
    bpy = api["bpy"]
    claimed, failures, counts = {}, [], Counter()
    for row in rows:
        root = bpy.data.collections.get(row["collections"]["root"])
        if not root:
            raise ValueError("Missing root: "+row["id"])
        upper_name = row["collections"]["upper"]
        if bpy.data.collections.get(upper_name) is None:
            api["collection"](upper_name, root)
        layers = {o.name: "structure" for o in root.all_objects}
        for role in ("front", "roof", "upper"):
            col = bpy.data.collections.get(row["collections"][role])
            if col is None:
                raise ValueError("Missing presentation collection: "+row["collections"][role])
            for ob in col.all_objects:
                layers[ob.name] = role
        for ob in root.all_objects:
            if ob.name in claimed and claimed[ob.name] != row["id"]:
                failures.append({"object": ob.name, "owners": [claimed[ob.name], row["id"]]})
            claimed[ob.name] = row["id"]
            ob["building_id"] = row["id"]
            ob["presentation_layer"] = layers[ob.name]
            if ob.get("interior_building_id"):
                ob["interior_building_id"] = row["id"]
            counts[layers[ob.name]] += 1
        row["object_names"] = sorted(o.name for o in root.all_objects)
        for floor in row["interior"]["levels"]:
            for room in floor["rooms"]:
                rc = bpy.data.collections.get(room["id"])
                for asset in room.get("assets", []):
                    asset.setdefault("source_object_names", list(asset.get("object_names", [])))
                    asset["object_names"] = sorted(o.name for o in rc.all_objects
                                                  if o.get("interior_asset_id", o.get("reserve_asset_id")) == asset["id"]) if rc else []
        row["interior"]["rooms"] = [{**room, "level": floor["level"]}
                                     for floor in row["interior"]["levels"] for room in floor["rooms"]]
        row["interior"]["object_names"] = sorted({o.name for floor in row["interior"]["levels"]
            for room in floor["rooms"] for o in (bpy.data.collections.get(room["id"]).all_objects
                                                  if bpy.data.collections.get(room["id"]) else [])})
    if failures:
        raise ValueError("Duplicate building ownership: "+json.dumps(failures))
    return {"status": "PASS", "building_count": len(rows), "owned_objects": len(claimed), "presentation_layer_counts": dict(counts)}


def correct_reserve_physical_proxies(api, rows, baseline, modified):
    """Keep real washer glass/accessible grabrails and expose their exact bounds.

    The six known source fixtures have valid geometry but body-only proxies:
    washer glass extends .067m in front; the larger WC's actual rail projects
    .096m beyond body width. Measure the native hardware and expand only those
    records, then rerun unchanged reserve layout/approach gates. No mesh moves.
    """
    bpy = api["bpy"]
    authority = api["module"]("whole_town_reserve_proxy_authority", Path(baseline)/"tools/reserve_amenities.py")
    corrections, layout_audits, approach_corrections = [], [], []
    for row in rows:
        if row["group"] != "reserve":
            continue
        root = bpy.data.collections[row["collections"]["root"]]
        source = row["reserve_source"]
        source_assets = {a["id"]: a for a in source["assets"]}
        changed = False
        for floor in row["interior"]["levels"]:
            for room in floor["rooms"]:
                for asset in room.get("assets", []):
                    if not (asset["kind"] == "washer" or (asset["kind"] == "toilet" and asset.get("grab_rails"))):
                        continue
                    objects = [o for o in root.all_objects if o.type == "MESH" and o.get("reserve_asset_id") == asset["id"]]
                    if not objects:
                        raise ValueError("Missing actual hardware for physical proxy correction: "+asset["id"])
                    points = [world_local(row, o.matrix_world@v.co) for o in objects for v in o.data.vertices]
                    actual = [min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)]
                    old = list(asset["footprint_m"])
                    measured = [min(old[0], actual[0]), min(old[1], actual[1]), max(old[2], actual[2]), max(old[3], actual[3])]
                    if max(abs(a-b) for a, b in zip(old, measured)) < 1e-4:
                        continue
                    reason = "Actual accessible WC grabrail is part of collision geometry" if asset["kind"] == "toilet" else "Actual source washer/dryer glass dish extends 0.067m in front of body"
                    asset["source_footprint_m"] = old
                    asset["footprint_m"] = measured
                    asset["physical_proxy_correction"] = reason
                    asset["physical_mesh_bounds_m"] = actual
                    source_assets[asset["id"]]["source_footprint_m"] = old
                    source_assets[asset["id"]]["footprint_m"] = measured
                    for ob in objects:
                        ob["collision_proxy_local_xy"] = measured
                        modified.add(ob.name)
                    corrections.append({"building_id": row["id"], "asset_id": asset["id"], "source_footprint_m": old,
                                        "actual_mesh_bounds_m": actual, "corrected_footprint_m": measured,
                                        "reason": reason, "mesh_pose_unchanged": True,
                                        "actual_objects": [o.name for o in objects]})
                    changed = True
        if changed:
            audit = authority.validate_plan(source)
            # Accurate hardware can expose an old standing marker positioned
            # against its neighboring dryer. Search only the same fixture's
            # physical working front, within .18m of that authored marker.
            # Full unchanged reserve reachability validates each candidate.
            failed_ids = [a["id"] for a in source["assets"] if any(
                error.startswith(a["id"]+": exact approach obstructed or disconnected") for error in audit["errors"])]
            interior_assets = {a["id"]: a for f in row["interior"]["levels"] for r in f["rooms"] for a in r.get("assets", [])}
            offsets = sorted([(i*.02, j*.02) for i in range(-9, 10) for j in range(-9, 10)
                              if 0 < math.hypot(i*.02, j*.02) <= .180001], key=lambda p: (p[0]*p[0]+p[1]*p[1], p[0], p[1]))
            for asset_id in failed_ids:
                asset = source_assets[asset_id]
                if asset["kind"] != "washer":
                    continue
                original = list(asset["approach_local_m"])
                angle = math.radians(asset.get("rotation_degrees", 0))
                normal = (math.sin(angle), -math.cos(angle))
                tangent = (math.cos(angle), math.sin(angle))
                cx, cy = asset["center_m"]
                a, b, c, d = asset["footprint_m"]
                front = max((x-cx)*normal[0]+(y-cy)*normal[1] for x in (a, c) for y in (b, d))
                handle_xy = (cx+normal[0]*front, cy+normal[1]*front)
                old_errors = set(audit["errors"])
                selected = None
                for dx, dy in offsets:
                    candidate = [original[0]+dx, original[1]+dy]
                    facing = (candidate[0]-cx)*normal[0]+(candidate[1]-cy)*normal[1]
                    lateral = abs((candidate[0]-cx)*tangent[0]+(candidate[1]-cy)*tangent[1])
                    if facing < front+.195 or lateral > max(.40, asset["dimensions_m"][0]*.55):
                        continue
                    if math.dist(candidate, handle_xy) > .8:
                        continue
                    asset["approach_local_m"] = candidate
                    tested = authority.validate_plan(source)
                    this_error = asset_id+": exact approach obstructed or disconnected"
                    if this_error not in tested["errors"] and set(tested["errors"]) <= old_errors-{this_error}:
                        selected, audit = candidate, tested
                        break
                if selected is None:
                    asset["approach_local_m"] = original
                    continue
                asset["source_approach_local_m"] = original
                interior_assets[asset_id]["source_approach_local_m"] = original
                interior_assets[asset_id]["approach_local_m"] = selected
                for ob in root.all_objects:
                    if ob.get("reserve_asset_id") == asset_id:
                        ob["approach_local_m"] = selected
                        modified.add(ob.name)
                approach_corrections.append({"building_id": row["id"], "asset_id": asset_id,
                                             "source_approach_local_m": original, "corrected_approach_local_m": selected,
                                             "displacement_m": math.dist(original, selected), "actual_front_handle_xy_m": handle_xy,
                                             "direct_handle_reach_m": math.dist(selected, handle_xy),
                                             "mesh_pose_unchanged": True, "gate": "Unchanged reserve validate_plan at .10m cells/.20m body radius"})
            layout_audits.append(audit)
            if audit["status"] != "PASS":
                raise ValueError("Measured reserve hardware proxy blocks unchanged layout gate: "+json.dumps(audit))
    return {"schema": "living_town.actual_fixture_proxy_corrections.v1", "status": "PASS",
            "corrections": corrections, "approach_corrections": approach_corrections,
            "unchanged_reserve_layout_gates": layout_audits,
            "policy": "Only exact existing hardware projections expand exported collision footprints; no visual geometry shrunk or source positions moved."}


def _polygon_area(poly):
    return .5*sum(a[0]*b[1]-b[0]*a[1] for a, b in zip(poly, poly[1:]+poly[:1]))


def _clip_half_plane(poly, a, b, keep_inside):
    """Convex polygon clip, with the left side of a->b being inside."""
    if not poly:
        return []
    def distance(point):
        value = (b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0])
        return value if keep_inside else -value
    result = []
    previous = poly[-1]
    pd = distance(previous)
    for current in poly:
        cd = distance(current)
        pin, cin = pd >= -1e-9, cd >= -1e-9
        if pin != cin:
            t = pd/(pd-cd)
            result.append([previous[0]+t*(current[0]-previous[0]), previous[1]+t*(current[1]-previous[1])])
        if cin:
            result.append(list(current))
        previous, pd = current, cd
    clean = []
    for point in result:
        if not clean or math.dist(point, clean[-1]) > 1e-7:
            clean.append(point)
    if len(clean) > 1 and math.dist(clean[0], clean[-1]) < 1e-7:
        clean.pop()
    return clean if len(clean) >= 3 and abs(_polygon_area(clean)) > 1e-8 else []


def _subtract_convex(subject, clip):
    """Partition subject minus convex clip into nonoverlapping convex pieces."""
    clip = clip if _polygon_area(clip) >= 0 else list(reversed(clip))
    remainder, outside = list(subject), []
    for a, b in zip(clip, clip[1:]+clip[:1]):
        piece = _clip_half_plane(remainder, a, b, False)
        if piece:
            outside.append(piece)
        remainder = _clip_half_plane(remainder, a, b, True)
        if not remainder:
            break
    return outside


def _party_interfaces(rows):
    core = [r for r in rows if r["group"] == "urban"]
    result, seen = [], set()
    for row in core:
        ident = row["id"]
        w, d = row["footprint_m"]
        angle = math.radians(row["yaw_degrees"])
        for side in (-1, 1):
            for other in core:
                if other["id"] == ident:
                    continue
                pair = tuple(sorted((ident, other["id"])))
                if pair in seen:
                    continue
                ow, od = other["footprint_m"]
                lx, ly, _ = world_local(row, (*other["center_m"][:2], row["pad_level_m"]))
                rel = (math.radians(other["yaw_degrees"])-angle) % math.pi
                if min(rel, math.pi-rel) < .015:
                    pass
                elif abs(rel-math.pi/2) < .015:
                    ow, od = od, ow
                else:
                    continue
                if abs(side*w/2-(lx-side*ow/2)) > .065:
                    continue
                lo, hi = max(-d/2, ly-od/2), min(d/2, ly+od/2)
                if hi-lo <= .01:
                    continue
                owner_id = other["id"] if ident == "Main_cafe" else ident if other["id"] == "Main_cafe" else min(pair)
                # Use the borrowing building frame for the missing-wall face.
                if owner_id == ident:
                    continue
                seen.add(pair)
                result.append({"id": "SharedShell_"+"__".join(pair), "building_ids": list(pair),
                               "wall_owner_id": owner_id, "borrowing_building_id": ident,
                               "borrower_side": side, "coordinate_local_x_m": side*w/2,
                               "span_local_y_m": [lo, hi]})
    return sorted(result, key=lambda r: r["id"])


def shared_shell_ledger(api, rows):
    """Resolve single-owned actual wall coverage and fill only real missing areas.

    Existing side-wall box faces and opaque gable triangles are projected into
    the borrowing wall's Y/Z frame. Their convex union is subtracted from the
    required habitable wall rectangle. Added prisms occupy only the uncovered
    pieces, under the original wall owner's root; no overlapping wall is added.
    Read-only native rays independently validate the assembled result afterward.
    """
    bpy, Batch = api["bpy"], api["Batch"]
    by_id = {r["id"]: r for r in rows}
    interfaces = _party_interfaces(rows)
    for row in rows:
        row["shared_shell_object_names"] = []
        row["shared_building_ids"] = [row["id"]]
        row["shared_shell_interfaces"] = []
    added, modified, gable_repartitions, total_missing_area = [], [], [], 0.
    for interface in interfaces:
        borrower, owner = by_id[interface["borrowing_building_id"]], by_id[interface["wall_owner_id"]]
        co = interface["coordinate_local_x_m"]
        lo, hi = interface["span_local_y_m"]
        bottom, top = borrower["interior"]["levels"][0]["finished_floor_local_z_m"], borrower["floor_count"]*2.85
        missing = [[[lo, bottom], [hi, bottom], [hi, top], [lo, top]]]
        root = bpy.data.collections[owner["collections"]["root"]]
        source_objects, projected_polygons = [], []
        for ob in list(root.all_objects):
            if ob.type != "MESH" or not (ob.name.startswith(owner["id"]+"_SideWall") or
                (ob.name.startswith(owner["id"]+"_RoofParts_") and ob.name.rsplit("_", 1)[-1] in ("Plaster", "Granite", "Stone", "Ochre", "PaleRose"))):
                continue
            if ob.name.startswith(owner["id"]+"_RoofParts_"):
                # The original material batch can contain BOTH end gables.
                # Repartition only the connected borrowed component; never
                # duplicate its geometry or borrow an unrelated far gable.
                selected = []
                for component in _components(ob.data):
                    # The source gable is a disconnected single triangle.
                    # Chimney boxes/dormer carcasses sharing its material are
                    # not wall coverage merely because one side is nearby.
                    if len(component) != 3:
                        continue
                    local = [world_local(borrower, ob.matrix_world@ob.data.vertices[i].co) for i in component]
                    if all(abs(point[0]-co) < .225 for point in local):
                        selected.extend(component)
                if selected:
                    import bmesh
                    old_name, before_count = ob.name, len(ob.data.vertices)
                    new = ob.copy()
                    new.data = ob.data.copy()
                    new.name = owner["id"]+"_SharedGable_for_"+borrower["id"]
                    for col in ob.users_collection:
                        col.objects.link(new)
                    keep = set(selected)
                    bm = bmesh.new(); bm.from_mesh(new.data); bm.verts.ensure_lookup_table()
                    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
                    bm.to_mesh(new.data); bm.free(); new.data.update()
                    if ob.data.users > 1:
                        ob.data = ob.data.copy()
                    bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
                    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in selected], context="VERTS")
                    bm.to_mesh(ob.data); bm.free(); ob.data.update()
                    new["building_id"] = owner["id"]
                    new["semantic_role"] = "single_owned_shared_gable"
                    new["generator_owner"] = OWNER
                    added.append(new.name); modified.append(old_name)
                    gable_repartitions.append({"source_object": old_name, "new_object": new.name,
                                                "source_vertices_before": before_count,
                                                "vertices_retained_in_source": len(ob.data.vertices),
                                                "vertices_transferred": len(new.data.vertices),
                                                "positions_materials_uvs_unchanged": True})
                    ob = new
                else:
                    continue
            points = [world_local(borrower, ob.matrix_world@v.co) for v in ob.data.vertices]
            has_surface = False
            for face in ob.data.polygons:
                vertices = [points[i] for i in face.vertices]
                if not all(abs(p[0]-co) < .225 for p in vertices):
                    continue
                polygon = [[p[1], p[2]] for p in vertices]
                if abs(_polygon_area(polygon)) < 1e-8:
                    continue
                has_surface = True
                projected_polygons.append(polygon)
                missing = [piece for subject in missing for piece in _subtract_convex(subject, polygon)]
            if has_surface:
                source_objects.append(ob.name)
        initial_missing = [poly for poly in missing if abs(_polygon_area(poly)) > 1e-5]
        area = sum(abs(_polygon_area(poly)) for poly in initial_missing)
        total_missing_area += area
        patch_names = []
        if initial_missing:
            batch = Batch(owner["id"]+"_SharedShellClosure_for_"+borrower["id"], root,
                          (*borrower["center_m"][:2], borrower["pad_level_m"]), math.radians(borrower["yaw_degrees"]))
            for polygon in initial_missing:
                # Identical .30m construction thickness; convex subtraction
                # ensures no Y/Z area overlaps any existing owner wall face.
                count = len(polygon)
                vertices = [(co+side*.15, y, z) for side in (-1, 1) for y, z in polygon]
                faces = [tuple(range(count-1, -1, -1)), tuple(range(count, 2*count))]
                faces += [(i, (i+1) % count, (i+1) % count+count, i+count) for i in range(count)]
                batch.poly(vertices, faces, "Plaster")
            for ob in batch.flush():
                ob["building_id"] = owner["id"]
                ob["semantic_role"] = "single_owned_shared_party_wall_closure"
                ob["generator_owner"] = OWNER
                ob["shared_building_ids"] = interface["building_ids"]
                ob["shared_shell_interface_id"] = interface["id"]
                patch_names.append(ob.name)
            added.extend(patch_names)
        names = sorted(set(source_objects+patch_names))
        interface.update({"object_names": names, "original_owner_objects": sorted(source_objects),
                          "added_gap_closure_objects": patch_names, "required_local_z_m": [bottom, top],
                          "measured_uncovered_area_before_m2": area, "uncovered_polygons_local_yz_m": initial_missing,
                          "coverage_status": "REQUIRES_NATIVE_BODY_RAYS", "owner_policy": "Original shared-wall single owner retained"})
        for name in names:
            ob = bpy.data.objects[name]
            participants = set(ob.get("shared_building_ids", [])) | set(interface["building_ids"])
            ob["shared_building_ids"] = sorted(participants)
            ob["shared_shell_geometry"] = True
            ob["shared_shell_primary_owner"] = owner["id"]
        for row in (borrower, owner):
            row["shared_shell_object_names"] = sorted(set(row["shared_shell_object_names"]+names))
            row["shared_building_ids"] = sorted(set(row["shared_building_ids"]+interface["building_ids"]))
            row["shared_shell_interfaces"].append(interface)
    return {"schema": "living_town.single_owned_shared_shell.v1", "status": "BUILT_REQUIRES_NATIVE_COVERAGE",
            "interface_count": len(interfaces), "interfaces": interfaces,
            "added_objects": added, "modified_objects": sorted(set(modified)),
            "exact_gable_component_repartitions": gable_repartitions,
            "actual_uncovered_area_filled_m2": total_missing_area,
            "policy": "Exact source touching interfaces; existing native wall/gable projection subtraction; a single primary building_id remains on every shared wall."}


def consolidate_cafe_attic(api, rows):
    """Resolve only the two exact source cafe/neighbor coincident gables.

    Canonical building() emits a gable for both adjoining buildings, unlike
    its single-owned habitable party wall. Remove the exact redundant cafe
    triangle, keep the original neighbor owner, and fill only measured missing
    silhouette slivers. A solid attic ray and an above-roof air control follow.
    """
    from array import array
    bpy, Batch = api["bpy"], api["Batch"]
    by_id = {r["id"]: r for r in rows}
    cafe = by_id["Main_cafe"]
    w, d = cafe["footprint_m"]
    h, rise = cafe["floor_count"]*2.85, max(1.5, min(3.7, d*.38))
    if cafe["kind"] != "cafe" or cafe.get("typology") != "mixed_use":
        raise ValueError("Cafe shared attic source typology changed")
    def fingerprint(ob):
        coordinates = array("f", [0.])*(3*len(ob.data.vertices))
        loops = array("i", [0])*len(ob.data.loops)
        ob.data.vertices.foreach_get("co", coordinates); ob.data.loops.foreach_get("vertex_index", loops)
        return hashlib.sha256(coordinates.tobytes()+loops.tobytes()).hexdigest()
    root = bpy.data.collections[cafe["collections"]["root"]]
    plans = []
    for interface in cafe["shared_shell_interfaces"]:
        side, co = interface["borrower_side"], interface["coordinate_local_x_m"]
        target = [(co, -d/2, h), (co, d/2, h), (co, 0, h+rise)]
        matches = []
        for ob in root.all_objects:
            if ob.type != "MESH" or not ob.name.startswith("Main_cafe_RoofParts_") or ob.name.rsplit("_", 1)[-1] not in ("Plaster", "Ochre", "PaleRose", "Stone", "Granite"):
                continue
            for indices in _components(ob.data):
                if len(indices) != 3:
                    continue
                points = [world_local(cafe, ob.matrix_world@ob.data.vertices[i].co) for i in indices]
                if all(min(math.dist(point, expected) for expected in target) < .0005 for point in points) and all(
                        min(math.dist(point, expected) for point in points) < .0005 for expected in target):
                    matches.append((ob, indices))
        if len(matches) != 1 or abs(co-side*w/2) > .0001 or any(abs(a-b) > .0001 for a, b in zip(interface["span_local_y_m"], [-d/2, d/2])):
            raise ValueError("Cafe attic source triangle/interface mismatch: "+interface["id"])
        missing = [[[-d/2, h], [d/2, h], [0, h+rise]]]
        for name in interface["object_names"]:
            ob = bpy.data.objects[name]
            for polygon in ob.data.polygons:
                points = [world_local(cafe, ob.matrix_world@ob.data.vertices[i].co) for i in polygon.vertices]
                if all(abs(p[0]-co) < .225 for p in points):
                    clip = [[p[1], p[2]] for p in points]
                    if abs(_polygon_area(clip)) > 1e-8:
                        missing = [piece for subject in missing for piece in _subtract_convex(subject, clip)]
        plans.append((interface, matches[0], [p for p in missing if abs(_polygon_area(p)) > 1e-7]))
    if len(plans) != 2:
        raise ValueError("Expected the two exact cafe party attic interfaces")
    receipts, modified, added = [], set(), []
    deletions = defaultdict(list)
    for interface, (ob, indices), missing in plans:
        deletions[ob.name].extend(indices)
        receipts.append({"interface_id": interface["id"], "redundant_source_object": ob.name,
                         "redundant_source_vertices": indices, "source_geometry_before_sha256": fingerprint(ob),
                         "missing_silhouette_polygons_yz_m": missing})
    import bmesh
    for name, indices in deletions.items():
        ob = bpy.data.objects[name]
        if ob.data.users > 1: ob.data = ob.data.copy()
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(indices))], context="VERTS")
        bm.to_mesh(ob.data); bm.free(); ob.data.update(); modified.add(name)
        for receipt in receipts:
            if receipt["redundant_source_object"] == name:
                receipt["source_geometry_after_sha256"] = fingerprint(ob)
    for (interface, _, missing), receipt in zip(plans, receipts):
        owner = by_id[interface["wall_owner_id"]]
        owner_root = bpy.data.collections[owner["collections"]["root"]]
        # Correct a reversed original end-gable face under its actual primary
        # owner's outward X direction; retain its materials and loop UVs.
        normals = []
        for name in interface["object_names"]:
            if "_SharedGable_for_Main_cafe" not in name: continue
            ob = bpy.data.objects[name]
            points = [world_local(owner, ob.matrix_world@v.co) for v in ob.data.vertices]
            sign = 1 if sum(p[0] for p in points) > 0 else -1
            bm = bmesh.new(); bm.from_mesh(ob.data); bm.normal_update()
            flipped = 0
            from mathutils import Vector
            angle = math.radians(owner["yaw_degrees"])
            desired = Vector((math.cos(angle)*sign, math.sin(angle)*sign, 0))
            for face in bm.faces:
                normal = ob.matrix_world.to_3x3()@face.normal
                if normal.dot(desired) < 0:
                    face.normal_flip(); flipped += 1
            bm.to_mesh(ob.data); bm.free(); ob.data.update()
            if flipped: modified.add(name)
            normals.append({"object": name, "primary_owner": owner["id"], "outward_owner_local_x": sign,
                            "source_faces_flipped": flipped, "materials_and_loop_uvs_retained": True})
        patch_names = []
        if missing:
            batch = Batch(owner["id"]+"_CafeSharedAtticSliver", owner_root,
                          (*cafe["center_m"][:2], cafe["pad_level_m"]), math.radians(cafe["yaw_degrees"]))
            co = interface["coordinate_local_x_m"]
            for polygon in missing:
                count = len(polygon)
                vertices = [(co+side*.07, y, z) for side in (-1, 1) for y, z in polygon]
                faces = [tuple(range(count-1, -1, -1)), tuple(range(count, count*2))]
                faces += [(i, (i+1) % count, (i+1) % count+count, i+count) for i in range(count)]
                batch.poly(vertices, faces, "Plaster")
            for ob in batch.flush():
                ob["building_id"] = owner["id"]; ob["shared_building_ids"] = interface["building_ids"]
                ob["shared_shell_geometry"] = True; ob["shared_shell_primary_owner"] = owner["id"]
                ob["semantic_role"] = "single_owned_shared_party_attic_sliver"
                ob["generator_owner"] = OWNER; patch_names.append(ob.name)
            added.extend(patch_names)
        interface["object_names"] = sorted(set(interface["object_names"]+patch_names))
        interface["attic_gable_shell"] = {"base_local_z_m": h, "rise_m": rise, "half_depth_m": d/2,
                                           "exact_redundant_cafe_triangle_removed": True,
                                           "added_only_missing_silhouette_slivers": patch_names}
        for participant in interface["building_ids"]:
            by_id[participant]["shared_shell_object_names"] = sorted(set(by_id[participant]["shared_shell_object_names"]+patch_names))
        receipt.update({"retained_primary_owner": owner["id"], "retained_source_gable_normals": normals,
                        "added_only_missing_sliver_objects": patch_names,
                        "missing_area_m2": sum(abs(_polygon_area(p)) for p in missing)})
    return {"schema": "living_town.cafe_single_owned_shared_attic.v1", "status": "BUILT_REQUIRES_NATIVE_ATTIC_RAYS",
            "interfaces": receipts, "modified_objects": sorted(modified), "added_objects": added,
            "policy": "Only two exact Main_cafe source triangles consolidated; neighbor-owned silhouette retained, no patch over existing faces."}


def review_candidates(rows):
    result = []
    for row in rows:
        w, d = row["footprint_m"]
        target_z = row["interior"]["levels"][0]["finished_floor_local_z_m"]+.8
        result.append({"building_id": row["id"], "kind": "exterior", "level": None,
                       "camera_world_m": local_world(row, w*.95, -d*1.7, max(w, d)*.9),
                       "target_world_m": local_world(row, 0, 0, target_z+row["floor_count"]*.8),
                       "hide_collections": [], "status": "PLANNED_NOT_RENDERED"})
        for floor in row["interior"]["levels"]:
            level, ff = floor["level"], floor["finished_floor_local_z_m"]
            result.append({"building_id": row["id"], "kind": "interior_cutaway", "level": level,
                           "camera_world_m": local_world(row, w*.32, -d*.88, ff+max(w, d)*.80),
                           "target_world_m": local_world(row, 0, 0, ff+.45),
                           "ortho_scale_m": max(w, d)*1.35,
                           "hide_collections": [row["collections"]["roof"], row["collections"]["front"]],
                           "hide_higher_floor_collections": [row["id"]+f"_Interior_L{n:02d}" for n in range(level+1, row["floor_count"])],
                           "limit": "Do not hide the whole upper cover when reviewing its own floor. Outside neighboring meshes and higher exterior shells may need additional clipping.",
                           "status": "PLANNED_NOT_RENDERED"})
    return result


def upgrade(api, baseline_root, expansion_dir, output):
    baseline, expansion, output = Path(baseline_root), Path(expansion_dir), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    rows = source_records(baseline, expansion)
    expected = {"urban": 49, "reserve": 21, "expansion": 81}
    if dict(Counter(row["group"] for row in rows)) != expected:
        raise ValueError("Unexpected whole-town building inventory")
    # Material prerequisites are explicit: the caller first builds the current
    # CC0 scan library, then this module refreshes loaded old material slots.
    required = {"Oak", "Plaster", "Stone", "Granite", "Tile", "Glass", "Brass", "SlateLight", "Zinc", "Iron", "Linen", *PAINTS, *("Facade"+str(i) for i in range(5))}
    if required-set(api["MATS"]):
        raise ValueError("Missing upgrade material API: "+str(sorted(required-set(api["MATS"]))))
    original_names = {o.name for o in api["bpy"].context.scene.objects}
    native_helper = api["module"]("whole_town_building_native_helper", Path(__file__).with_name("building_native_audit.py"))
    source_furniture = native_helper.capture_source_furniture(api, rows)
    write(output/"source_furniture_geometry.json", {"schema": "living_town.source_furniture_geometry.v1",
                                                   "objects": source_furniture,
                                                   "scope": "Before upgrade, exact source mesh vertices/topology/transform; independent canonical source hashes follow in upgrade receipt."})
    painted = _paint_materials(api)
    modified, mapped_meshes = set(), set()
    door_repairs, material_reports, architecture_reports, furniture_reports = [], [], [], []
    for index, row in enumerate(rows):
        print(f"ARCHITECTURE_UPGRADE_BUILDING {index+1}/{len(rows)} {row['id']}", flush=True)
        if row["group"] == "urban":
            repair = repair_core_door(api, row)
            door_repairs.append(repair)
            modified.update(repair.get("modified_objects", []))
        material_reports.append(refresh_materials(api, row, modified, mapped_meshes))
        architecture_reports.append(add_architecture(api, row))
        furniture_reports.append(add_furniture_craft(api, row))
    print("ARCHITECTURE_UPGRADE_PHYSICAL_PROXY_CHECK", flush=True)
    physical_proxy_report = correct_reserve_physical_proxies(api, rows, baseline, modified)
    print("ARCHITECTURE_UPGRADE_SHARED_SHELL", flush=True)
    shared_shell_report = shared_shell_ledger(api, rows)
    modified.update(shared_shell_report["modified_objects"])
    print("ARCHITECTURE_UPGRADE_CAFE_SHARED_ATTIC", flush=True)
    shared_attic_report = consolidate_cafe_attic(api, rows)
    modified.update(shared_attic_report["modified_objects"])
    print("ARCHITECTURE_UPGRADE_INTERIOR_DECORATION", flush=True)
    decoration_module = api["module"]("whole_town_purposeful_interior_decoration", Path(__file__).with_name("interior_decoration.py"))
    decoration_report = decoration_module.decorate(api, rows, output/"interior_decoration_receipt.json")
    print("ARCHITECTURE_UPGRADE_CLASSIFY_AND_RECEIPTS", flush=True)
    ownership = classify(api, rows)
    added = sorted({o.name for o in api["bpy"].context.scene.objects}-original_names)
    source_paths = {"baseline_native": baseline/"living_town_complete.blend", "town_manifest": baseline/"town_manifest.json",
                    "masterplan": baseline/"masterplan.json", "interior_plan": baseline/"interior_plan.json",
                    "reserve_plan": baseline/"reserve_plan.json", "core_builder": baseline/"tools/build_living_town.py",
                    "reserve_amenities_module": baseline/"tools/reserve_amenities.py", "interior_module": baseline/"tools/interior_design.py",
                    "expansion_native": expansion/"scene/expanded_town.blend", "expansion_plan": expansion/"territory_plan.json",
                    "expansion_manifest": expansion/"scene/expansion_manifest.json", "expansion_interiors": expansion/"scene/interiors.json",
                    "architecture_upgrade_module": Path(__file__), "native_audit_helper": Path(__file__).with_name("building_native_audit.py"),
                    "interior_decoration_module": Path(__file__).with_name("interior_decoration.py")}
    bindings = {key: {"path": str(path.resolve()), "sha256": sha(path), "bytes": path.stat().st_size} for key, path in source_paths.items()}
    for row in rows:
        row["floor_count"] = len(row["interior"]["levels"])
        row["room_count"] = sum(len(f["rooms"]) for f in row["interior"]["levels"])
        row["furnishing_count"] = sum(len(r.get("assets", [])) for f in row["interior"]["levels"] for r in f["rooms"])
    unified = {"schema": "living_town.whole_town_buildings.v1", "source_bindings": bindings,
               "building_count": len(rows), "floor_count": sum(r["floor_count"] for r in rows),
               "room_count": sum(r["room_count"] for r in rows), "furnishing_count": sum(r["furnishing_count"] for r in rows),
               "window_aperture_count": sum(r["window_aperture_count"] for r in rows), "buildings": rows}
    write(output/"whole_town_buildings.json", unified)
    write(output/"whole_town_interiors.json", {"schema": "living_town.whole_town_interiors.v1", "source_bindings": bindings,
                                              "buildings": [r["interior"] for r in rows]})
    candidates = review_candidates(rows)
    write(output/"whole_town_review_candidates.json", {"schema": "living_town.whole_town_review_candidates.v1", "status": "PLANNED_NOT_RENDERED", "views": candidates})
    receipt = {"schema": OWNER, "status": "BUILT_REQUIRES_NATIVE_AND_VISUAL_REVIEW", "source_bindings": bindings,
               "counts": {k: unified[k] for k in ("building_count", "floor_count", "room_count", "furnishing_count", "window_aperture_count")},
               "ownership": ownership, "painted_materials": painted, "materials": material_reports,
               "door_repairs": door_repairs, "architecture": architecture_reports, "furniture": furniture_reports,
               "physical_proxy_corrections": physical_proxy_report,
               "shared_shell_ledger": shared_shell_report,
               "cafe_shared_attic": shared_attic_report,
               "interior_decoration": {k: decoration_report[k] for k in ("schema", "status", "building_count", "floor_count", "room_zones_visited", "detail_counts", "new_interactive_furnishings", "tool_sha256")},
               "modified_object_names": sorted(modified), "added_object_names": added,
               "canonical_geometry_programs_preserved": True, "all_visual_acceptance": False,
               "limits": ["Door repair requires exact source components; failures remain explicit and require repair before acceptance.",
                          "Original furniture facing/room programs are preserved; new detail stays in source proxies.",
                          "Per-window ledger mirrors source recipes; only actual native wall rays establish open geometry.",
                          "No source-hash receipt or planned camera constitutes visual acceptance."]}
    write(output/"architecture_upgrade_receipt.json", receipt)
    return {"buildings": rows, "interiors": [r["interior"] for r in rows], "receipt": receipt,
            "review_candidates": candidates, "manifest": unified,
            "source_furniture_geometry": source_furniture,
            "manifest_path": str((output/"whole_town_buildings.json").resolve())}
