"""Purposeful surface and textile details for the preserved complete town.

No room, furniture pose or collision reservation is changed. Wall pieces need
an authored opaque internal partition and a real native support ray. Props need
an actual flat furniture-top support, remain inside its measured footprint, and
are tagged as attached detail rather than a new interactive furnishing. Rugs
remain inside their room, outside circulation/door/shaft reservations, and are
flat non-collision textile surfaces. Importing this module is engine-free.
"""
from __future__ import annotations

from collections import Counter
from array import array
import hashlib
import json
import math
from pathlib import Path


OWNER = "living_town.purposeful_interior_decoration.v1"


def _world(row, x, y, z=0):
    angle = math.radians(row["yaw_degrees"])
    return (row["center_m"][0]+x*math.cos(angle)-y*math.sin(angle),
            row["center_m"][1]+x*math.sin(angle)+y*math.cos(angle), row["pad_level_m"]+z)


def _rotate(x, y, degrees):
    angle = math.radians(degrees)
    return x*math.cos(angle)-y*math.sin(angle), x*math.sin(angle)+y*math.cos(angle)


def _overlap(a, b, margin=0):
    return min(a[2], b[2])-max(a[0], b[0]) > -margin and min(a[3], b[3])-max(a[1], b[1]) > -margin


def _inside(a, b, margin=.03):
    return a[0] >= b[0]+margin and a[1] >= b[1]+margin and a[2] <= b[2]-margin and a[3] <= b[3]-margin


def _asset_rect(asset, x, y, width, depth):
    corners = [_rotate(x+xx, y+yy, asset.get("rotation_degrees", 0)) for xx in (-width/2, width/2) for yy in (-depth/2, depth/2)]
    cx, cy = asset["center_m"]
    return [cx+min(p[0] for p in corners), cy+min(p[1] for p in corners),
            cx+max(p[0] for p in corners), cy+max(p[1] for p in corners)]


def _ray(api, ob, row, point, direction, distance):
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    if ob is None or ob.type != "MESH" or not ob.data.polygons:
        return None
    # This support geometry is immutable throughout decorate(). Native object
    # ray_cast can update the scene dependencies after every newly linked prop,
    # turning a local check into repeated whole-town scene evaluation. A local
    # actual-mesh BVH preserves the same finite segment without those updates.
    cache = api.setdefault("_decoration_support_bvh_cache", {})
    if ob.name not in cache:
        coordinates = array("f", [0.])*(3*len(ob.data.vertices))
        indices = array("i", [0])*len(ob.data.loops)
        ob.data.vertices.foreach_get("co", coordinates)
        ob.data.loops.foreach_get("vertex_index", indices)
        cache[ob.name] = {"tree": BVHTree.FromPolygons([v.co.copy() for v in ob.data.vertices],
                                                      [tuple(p.vertices) for p in ob.data.polygons], all_triangles=False),
                          "mesh_name": ob.data.name,
                          "geometry_sha256": hashlib.sha256(coordinates.tobytes()+indices.tobytes()).hexdigest(),
                          "vertices": len(ob.data.vertices), "polygons": len(ob.data.polygons),
                          "matrix_world": [list(r) for r in ob.matrix_world]}
    inv = ob.matrix_world.inverted()
    origin = Vector(_world(row, *point))
    angle = math.radians(row["yaw_degrees"])
    dx, dy, dz = direction
    ray = Vector((dx*math.cos(angle)-dy*math.sin(angle), dx*math.sin(angle)+dy*math.cos(angle), dz))
    local_origin = inv@origin
    local_segment = inv@(origin+ray*distance)-local_origin
    length = local_segment.length
    if length < 1e-10:
        return None
    local_segment.normalize()
    location, normal, face, actual_distance = cache[ob.name]["tree"].ray_cast(local_origin, local_segment, length)
    return ob.matrix_world@location if location is not None else None


def _tag(objects, row, room, role, asset=None, footprint=None):
    for ob in objects:
        ob["building_id"] = row["id"]
        ob["interior_building_id"] = row["id"]
        ob["interior_room_id"] = room["id"]
        ob["semantic_role"] = role
        ob["interior_role"] = "purposeful_surface_decoration"
        ob["generator_owner"] = OWNER
        ob["collision_policy"] = "Nonblocking surface detail; original furnishing/circulation proxies retained"
        if asset:
            ob["attached_to_asset_id"] = asset["id"]
            ob["decoration_source_footprint_m"] = asset["footprint_m"]
        if footprint:
            ob["decoration_footprint_m"] = footprint


def _wall_segments(room, floor):
    a, b, c, d = room["bounds_m"]
    result = []
    for index, wall in enumerate(floor.get("partitions", [])):
        axis, co = wall["axis"], wall["coordinate_m"]
        if axis == "x" and min(abs(co-a), abs(co-c)) < .03:
            lo, hi = max(b, wall["span_m"][0]), min(d, wall["span_m"][1])
            sign, priority = (1, 3) if abs(co-a) < .03 else (-1, 0)
        elif axis == "y" and min(abs(co-b), abs(co-d)) < .03:
            lo, hi = max(a, wall["span_m"][0]), min(c, wall["span_m"][1])
            sign, priority = (1, 2) if abs(co-b) < .03 else (-1, 1)
        else:
            continue
        cuts = [(lo, hi)]
        for opening in wall.get("openings", []):
            if opening["bottom_m"] > 1.9 or opening["bottom_m"]+opening["height_m"] < 1.20:
                continue
            left, right = opening["center_m"]-opening["width_m"]/2-.10, opening["center_m"]+opening["width_m"]/2+.10
            cuts = [(x, min(y, left)) for x, y in cuts if min(y, left)-x > .01]+[(max(x, right), y) for x, y in cuts if y-max(x, right) > .01]
        for start, end in cuts:
            if end-start > .55:
                result.append({"partition_index": index, "axis": axis, "coordinate_m": co,
                               "span_m": [start, end], "sign": sign, "priority": priority,
                               "thickness_m": wall.get("thickness_m", .14)})
    return sorted(result, key=lambda r: (r["priority"], -(r["span_m"][1]-r["span_m"][0])))


def _art_kind(room):
    purpose = room["purpose"].lower()
    if any(token in purpose for token in ("bath", "toilet", "shower", "handwash", "washbasin")):
        return "mirror" if any(a["kind"] == "basin" for a in room.get("assets", [])) else "hygiene_notice"
    if "cab" in purpose:
        return "route_map"
    if any(token in purpose for token in ("cafe", "dining", "retail", "serving", "shop", "food", "kitchen")):
        return "menu_and_house_notice"
    if any(token in purpose for token in ("stock", "storage", "utility", "cleaning", "work", "laundry", "equipment")):
        return "care_and_service_chart"
    if any(token in purpose for token in ("read", "library", "study", "information", "reception")):
        return "local_coastal_map"
    return "coastal_landscape"


def _ensure_mirror(api):
    if "DecorationMirror" in api["MATS"]:
        return
    material = api["bpy"].data.materials.new("TownDecoration_Mirror")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.72, .76, .75, 1)
    shader.inputs["Metallic"].default_value = 1
    shader.inputs["Roughness"].default_value = .06
    api["MATS"]["DecorationMirror"] = material


def wall_piece(api, row, floor, room, collection):
    if not room.get("assets"):
        return None
    kind = _art_kind(room)
    ff = floor["finished_floor_local_z_m"]
    partition_name = row["id"]+("_Partitions_Plaster" if row["group"] == "reserve" else f"_L{floor['level']:02d}_Partitions_Plaster")
    partition = api["bpy"].data.objects.get(partition_name)
    for candidate in _wall_segments(room, floor):
        lo, hi = candidate["span_m"]
        width = min(.72 if kind == "coastal_landscape" else .56, hi-lo-.18)
        height, z = (.58, 1.55) if kind == "mirror" else (.46, 1.57)
        for along in ((lo+hi)/2, lo+width/2+.09, hi-width/2-.09):
            axis, co, sign = candidate["axis"], candidate["coordinate_m"], candidate["sign"]
            surface = co+sign*(candidate["thickness_m"]/2+.002)
            # Tall shelves/cabinets keep their existing wall area. Low beds,
            # tables and basins can have normal pictures/mirrors above them.
            blocked = False
            for asset in room["assets"]:
                if asset["dimensions_m"][2] < z-height/2-.08:
                    continue
                a, b, c, d = asset["footprint_m"]
                span, near = ((b, d), min(abs(a-co), abs(c-co))) if axis == "x" else ((a, c), min(abs(b-co), abs(d-co)))
                if near < .30 and min(span[1], along+width/2)-max(span[0], along-width/2) > -.08:
                    blocked = True
                    break
            if blocked:
                continue
            point = (co+sign*.24, along, ff+z) if axis == "x" else (along, co+sign*.24, ff+z)
            direction = (-sign, 0, 0) if axis == "x" else (0, -sign, 0)
            support = _ray(api, partition, row, point, direction, .48)
            if support is None:
                continue
            # Art axes: local horizontal=along partition; local depth points
            # toward the room. Mount only on this actual internal partition.
            center = (surface, along) if axis == "x" else (along, surface)
            rotation = 90 if axis == "x" and sign == 1 else -90 if axis == "x" else 0 if sign == -1 else 180
            batch = api["Batch"](room["id"]+"_Purposeful_"+kind, collection, _world(row, *center, ff),
                                 math.radians(row["yaw_degrees"]+rotation))
            # Visible face is -Y; face and four separate timber frame rails.
            batch.box((0, -.012, z), (width, .022, height), "DecorationMirror" if kind == "mirror" else "Ink" if kind == "menu_and_house_notice" else "Linen")
            for side in (-1, 1):
                batch.box((side*(width/2+.014), -.018, z), (.028, .040, height+.055), "Oak")
                batch.box((0, -.018, z+side*(height/2+.014)), (width+.055, .040, .028), "Oak")
            if kind == "coastal_landscape":
                batch.box((0, -.026, z-.055), (width-.035, .008, height*.36), "BluePaint")
                batch.poly([(-width*.46, -.032, z-.015), (width*.03, -.032, z+.085), (width*.44, -.032, z-.015)], [(0, 1, 2)], "Sage")
                batch.box((width*.22, -.034, z+.075), (.075, .007, .09), "White")
                batch.poly([(width*.17, -.038, z+.12), (width*.27, -.038, z+.12), (width*.22, -.038, z+.16)], [(0, 1, 2)], "Terracotta")
                batch.rod((-width*.28, -.038, z+.12), (-width*.28, -.044, z+.12), .034, "Brass", n=14)
            elif kind != "mirror":
                for i in range(5):
                    line_width = width*(.72 if i % 2 else .57)
                    batch.box((-width*.03, -.027, z+height*.30-i*height*.13), (line_width, .007, .008), "Linen" if kind == "menu_and_house_notice" else "BluePaint")
                if "map" in kind:
                    for i in range(4):
                        xx = -width*.3+i*width*.2
                        batch.box((xx, -.034, z-height*.05), (.008, .006, height*.62), "Sage")
            objects = batch.flush()
            _tag(objects, row, room, "opaque_partition_wall_piece")
            return {"kind": kind, "partition_index": candidate["partition_index"], "support_object": partition_name,
                    "support_world_m": list(support), "mount_axis": axis, "mount_coordinate_m": co,
                    "along_m": along, "objects": [o.name for o in objects], "exterior_window_overlap": False}
    return None


def _rug_clear(rect, room, floor, interior):
    if not _inside(rect, room["bounds_m"], .09):
        return False
    keepouts = list(room.get("circulation_keepouts", []))+list(floor.get("access_keepouts", []))+list(room.get("nonrectangular_exclusions_m", []))
    if interior.get("core"):
        keepouts.append(interior["core"]["bounds"])
    for void in floor.get("slab_voids", []):
        if isinstance(void, list) and len(void) == 4:
            keepouts.append(void)
        elif isinstance(void, dict) and "bounds_m" in void:
            keepouts.append(void["bounds_m"])
    if any(_overlap(rect, q, .08) for q in keepouts):
        return False
    for door in room.get("door_gaps", []):
        co, along, half = door["coordinate_m"], door["center_m"], door["width_m"]/2+.15
        aperture = [co-.40, along-half, co+.40, along+half] if door["axis"] == "x" else [along-half, co-.40, along+half, co+.40]
        if _overlap(rect, aperture):
            return False
    return not any(_overlap(rect, a["footprint_m"], .04) for a in room.get("assets", []) if a["kind"] != "coffee_table")


def rug(api, row, floor, room, collection):
    purpose = room["purpose"].lower()
    if not any(token in purpose for token in ("sleep", "bed", "living", "lounge", "reading", "guest room")):
        return None
    if any(token in purpose for token in ("bath", "kitchen", "toilet", "service")):
        return None
    candidates = []
    for asset in room.get("assets", []):
        if asset["kind"] not in ("bed", "sofa", "lounge_chair", "banquette"):
            continue
        w, d, h = asset["dimensions_m"]
        dimensions = (min(1.30, w*.8), .55) if asset["kind"] == "bed" else (min(1.65, w+.1), .85)
        nx, ny = _rotate(0, -1, asset.get("rotation_degrees", 0))
        distance = d/2+dimensions[1]/2+.09
        x, y = asset["center_m"][0]+nx*distance, asset["center_m"][1]+ny*distance
        rotation = asset.get("rotation_degrees", 0)
        fake = {"center_m": [x, y], "rotation_degrees": rotation}
        rect = _asset_rect(fake, 0, 0, *dimensions)
        if _rug_clear(rect, room, floor, row["interior"]):
            candidates.append((asset, x, y, dimensions, rotation, rect))
    if not candidates:
        return None
    asset, x, y, (w, d), rotation, rect = candidates[0]
    ff = floor["finished_floor_local_z_m"]
    b = api["Batch"](room["id"]+"_Woven_Rug", collection, _world(row, x, y, ff), math.radians(row["yaw_degrees"]+rotation))
    b.box((0, 0, .018), (w, d, .004), "Linen")
    for side in (-1, 1):
        b.box((0, side*(d/2-.035), .021), (w-.055, .027, .002), "TealCloth")
        b.box((side*(w/2-.035), 0, .021), (.027, d-.055, .002), "TealCloth")
    for i in range(max(3, int(w/.14))):
        xx = -w/2+.06+i*.14
        if xx < w/2-.04:
            b.box((xx, 0, .021), (.004, d-.11, .0015), "Cushion")
    objects = b.flush()
    _tag(objects, row, room, "ground_flush_woven_textile", footprint=rect)
    return {"kind": "flat_woven_rug", "related_asset": asset["id"], "footprint_m": rect,
            "top_above_finished_floor_m": .022, "navigation_collision": False,
            "excludes_door_stair_void_and_circulation_reservations": True, "objects": [o.name for o in objects]}


def _surface_recipe(row, asset):
    kind, (w, d, h) = asset["kind"], asset["dimensions_m"]
    reserve = row["group"] == "reserve"
    if kind in ("kitchen_run", "kitchen"):
        return "kitchen_jars_and_board", w*.40, d*.24, .935 if kind == "kitchen_run" else .93, min(.23, w*.12), min(.16, d*.32)
    if kind == "cafe_counter":
        return "counter_menu", w*.43, d*.27, 1.085, min(.24, w*.11), min(.12, d*.25)
    if kind in ("counter", "food_counter", "retail_counter"):
        return "counter_menu" if kind != "food_counter" else "food_service_linen", -w*.40, d*.25, h+.08 if kind == "retail_counter" else h-.005, min(.22, w*.12), min(.15, d*.3)
    if kind in ("writing_desk", "reading_table", "meeting_table"):
        return "reading_books", -w*.33, -d*.20, .805, min(.20, w*.21), min(.15, d*.38)
    if kind == "desk" and reserve:
        return "reading_books", -w*.30, (d-.60)/2+.05, .8325, min(.22, w*.22), .16
    if kind in ("dining_table", "cafe_table_set"):
        return "table_ceramic_and_linen", .16 if kind == "cafe_table_set" else w*.22, -.12 if kind == "cafe_table_set" else .02, .76 if kind == "cafe_table_set" else .80, .15, .12
    if kind == "workbench":
        return "workshop_oil_and_rag", -w*.36, d*.30, h-.0275 if reserve else h-.035, min(.20, w*.18), min(.15, d*.3)
    if kind == "market_stall":
        return "market_folded_linen", w*.36, d*.32, .89, min(.20, w*.18), min(.15, d*.25)
    if kind == "basin":
        return "wash_soap_and_dish", -w*.33, -d*.19, .825 if reserve else .91, min(.10, w*.18), min(.08, d*.23)
    return None


def surface_props(api, row, floor, room, asset, collection):
    recipe = _surface_recipe(row, asset)
    if not recipe:
        return None
    kind, x, y, top, width, depth = recipe
    rect = _asset_rect(asset, x, y, width, depth)
    if not _inside(rect, asset["footprint_m"], .008):
        return None
    ff, rotation = floor["finished_floor_local_z_m"], asset.get("rotation_degrees", 0)
    objects = [o for o in collection.all_objects if o.type == "MESH" and
               (o.get("interior_asset_id") == asset["id"] or o.get("reserve_asset_id") == asset["id"])]
    support_points = []
    for dx, dy in ((0, 0), (-width*.40, -depth*.40), (-width*.40, depth*.40), (width*.40, -depth*.40), (width*.40, depth*.40)):
        xx, yy = _rotate(x+dx, y+dy, rotation)
        point = (asset["center_m"][0]+xx, asset["center_m"][1]+yy, ff+top+.12)
        hits = [_ray(api, ob, row, point, (0, 0, -1), .30) for ob in objects]
        hits = [p for p in hits if p is not None]
        if not hits:
            return None
        actual = max(p.z for p in hits)-row["pad_level_m"]-ff
        if abs(actual-top) > .022:
            return None
        support_points.append(actual)
    xx, yy = _rotate(x, y, rotation)
    origin = _world(row, asset["center_m"][0]+xx, asset["center_m"][1]+yy, ff+sum(support_points)/len(support_points)+.002)
    b = api["Batch"](asset["id"]+"_Purposeful_"+kind, collection, origin, math.radians(row["yaw_degrees"]+rotation))
    if kind == "reading_books":
        for i in range(3):
            ww, dd = width*(1-.07*(i % 2)), depth*(1-.05*(i % 2))
            z = .010+i*.023
            b.box((0, 0, z), (ww, dd, .015), ("BluePaint", "Sage", "Burgundy")[i])
            b.box((0, -.001, z+.009), (ww*.91, dd*.92, .006), "Linen")
    elif kind == "counter_menu":
        b.box((0, 0, .008), (width, depth, .016), "Oak")
        b.box((0, depth*.10, .105), (width*.90, .018, .19), "Ink")
        for i in range(5):
            b.box((0, depth*.10-.011, .17-i*.029), (width*.65, .006, .0045), "Linen")
    elif kind in ("food_service_linen", "market_folded_linen"):
        for i in range(3):
            b.box((0, 0, .006+i*.009), (width*(1-.07*i), depth*(1-.09*i), .010), "Linen")
        for side in (-1, 1):
            b.box((side*width*.35, 0, .033), (.005, depth*.70, .002), "TealCloth")
    elif kind == "table_ceramic_and_linen":
        b.box((-width*.15, 0, .006), (width*.68, depth*.88, .012), "Linen")
        radius = min(width, depth)*.24
        b.rod((width*.23, 0, .004), (width*.23, 0, .011), radius*1.2, "White", n=14)
        b.rod((width*.23, 0, .013), (width*.23, 0, .068), radius*.70, "White", n=14, r2=radius)
        b.rod((width*.23, 0, .069), (width*.23, 0, .071), radius*.78, "Ink", n=14)
    elif kind == "wash_soap_and_dish":
        b.box((0, 0, .006), (width, depth, .012), "White")
        b.box((0, 0, .020), (width*.68, depth*.66, .020), "Sage")
    else:
        b.box((-width*.22, 0, .006), (width*.50, depth*.90, .012), "Linen" if kind == "workshop_oil_and_rag" else "Oak")
        radius = min(width*.20, depth*.28)
        cx = width*.26
        b.rod((cx, 0, .005), (cx, 0, .075), radius, "Terracotta" if kind == "kitchen_jars_and_board" else "Zinc", n=14)
        b.rod((cx, 0, .075), (cx, 0, .090), radius, "Terracotta" if kind == "kitchen_jars_and_board" else "Zinc", n=14, r2=radius*.76)
        b.rod((cx, 0, .090), (cx, 0, .103), radius*.88, "Oak", n=14)
    added = b.flush()
    _tag(added, row, room, "purposeful_furniture_surface_props", asset=asset, footprint=rect)
    return {"kind": kind, "attached_to_asset_id": asset["id"], "footprint_m": rect,
            "support_samples_local_z_m": support_points, "support_matches_actual_native_top": True,
            "objects": [o.name for o in added]}


def folded_bed_linen(api, row, floor, room, asset, collection):
    if asset["kind"] not in ("bed", "bunk"):
        return None
    w, d, h = asset["dimensions_m"]
    width, depth, x, y = w*.68, min(.26, d*.16), 0, -d*.30
    rect = _asset_rect(asset, x, y, width, depth)
    if not _inside(rect, asset["footprint_m"], .01):
        return None
    xx, yy = _rotate(x, y, asset.get("rotation_degrees", 0))
    ff = floor["finished_floor_local_z_m"]
    top = .5525 if row["group"] == "reserve" else .578
    b = api["Batch"](asset["id"]+"_Folded_Linen", collection,
                      _world(row, asset["center_m"][0]+xx, asset["center_m"][1]+yy, ff+top+.006),
                      math.radians(row["yaw_degrees"]+asset.get("rotation_degrees", 0)))
    for i in range(3):
        b.box((0, 0, i*.010), (width-i*.022, depth-i*.018, .012), "Linen")
    for side in (-1, 1):
        b.box((side*width*.35, 0, .027), (.008, depth*.76, .002), "TealCloth")
    added = b.flush()
    _tag(added, row, room, "folded_bed_textile", asset=asset, footprint=rect)
    return {"kind": "folded_bed_textile", "attached_to_asset_id": asset["id"], "footprint_m": rect,
            "objects": [o.name for o in added]}


def decorate(api, rows, output=None):
    _ensure_mirror(api)
    api["_decoration_support_bvh_cache"] = {}
    bpy = api["bpy"]
    results, counts, added_names = [], Counter(), []
    for index, row in enumerate(rows):
        print(f"INTERIOR_DECORATION_BUILDING {index+1}/{len(rows)} {row['id']}", flush=True)
        building = {"building_id": row["id"], "floors": []}
        for floor in row["interior"]["levels"]:
            level_result = {"level": floor["level"], "rooms": []}
            for room in floor["rooms"]:
                collection = bpy.data.collections.get(room["id"])
                if collection is None:
                    raise ValueError("Decoration has no actual room collection: "+room["id"])
                details = []
                art = wall_piece(api, row, floor, room, collection)
                carpet = rug(api, row, floor, room, collection)
                if art:
                    details.append(art)
                if carpet:
                    details.append(carpet)
                for asset in room.get("assets", []):
                    props = surface_props(api, row, floor, room, asset, collection)
                    linen = folded_bed_linen(api, row, floor, room, asset, collection)
                    if props:
                        details.append(props)
                    if linen:
                        details.append(linen)
                for detail in details:
                    counts[detail["kind"]] += 1
                    added_names.extend(detail["objects"])
                level_result["rooms"].append({"room_id": room["id"], "purpose": room["purpose"], "details": details,
                                              "status": "DETAILS_ADDED_REQUIRES_VISUAL_REVIEW" if details else "EXISTING_DETAIL_RETAINED",
                                              "reason_if_no_new_detail": None if details else "Open circulation or no safe real partition/tabletop/bed surface; no arbitrary furnishing added."})
            building["floors"].append(level_result)
        results.append(building)
    report = {"schema": OWNER, "status": "BUILT_REQUIRES_VISUAL_REVIEW", "building_count": len(rows),
              "floor_count": sum(len(r["interior"]["levels"]) for r in rows),
              "room_zones_visited": sum(len(f["rooms"]) for r in rows for f in r["interior"]["levels"]),
              "detail_counts": dict(counts), "added_object_names": added_names, "modified_source_object_names": [],
              "source_furnishing_poses_and_programs_unchanged": True, "new_interactive_furnishings": 0,
              "support_ray_geometry": {name: {k: v for k, v in entry.items() if k != "tree"}
                                       for name, entry in api["_decoration_support_bvh_cache"].items()},
              "support_ray_policy": "Immutable actual native base-mesh local BVH per support object; finite world segment transformed into object space, preserving scale and world support location. Bevel modifiers do not change the tested flat surface centers.",
              "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "buildings": results,
              "limits": ["Detailed decoration recipes are original geometry and existing portable materials; no licensed picture imagery is borrowed.",
                         "Partition-mounted pieces never use an exterior/window wall. Furniture props require actual native flat support and fit the existing physical footprint.",
                         "Rugs preserve doors, circulation, shafts and authored nonrectangular voids; textiles and small props add no walkable-floor collision.",
                         "Every building/floor/zone is enumerated. Safe omissions remain explicit; visual acceptance requires actual images."]}
    if output:
        Path(output).write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    return report
