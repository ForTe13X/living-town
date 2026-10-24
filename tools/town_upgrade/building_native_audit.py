"""Read-only whole-town native geometry checks, called in an opened Blender scene.

Every building, floor, room zone, fixture and authored window/partition opening
gets an explicit row. This establishes finite geometry coverage, not visual or
gameplay acceptance. Importing the module requires only the standard library.
"""
from __future__ import annotations

from array import array
from collections import Counter
import hashlib
import json
import math
from pathlib import Path


def mesh_fingerprint(ob):
    """Exact local source vertices/topology and object transform; UV/material free.

    Material/UV upgrades must not silently move source furniture. Intentional
    source door-face removal has a separate component-level repair receipt.
    """
    vertices = array("f", [0.])*(len(ob.data.vertices)*3)
    loops = array("i", [0])*len(ob.data.loops)
    ob.data.vertices.foreach_get("co", vertices)
    ob.data.loops.foreach_get("vertex_index", loops)
    digest = hashlib.sha256(vertices.tobytes()+loops.tobytes())
    digest.update(json.dumps([list(row) for row in ob.matrix_world]).encode())
    return {"geometry_sha256": digest.hexdigest(), "vertices": len(ob.data.vertices),
            "polygons": len(ob.data.polygons), "matrix_world": [list(row) for row in ob.matrix_world]}


def capture_source_furniture(api, rows):
    bpy = api["bpy"]
    result = {}
    for row in rows:
        root = bpy.data.collections.get(row["collections"]["root"])
        for ob in root.all_objects if root else []:
            if ob.type == "MESH" and (ob.get("interior_asset_id") or ob.get("reserve_asset_id")):
                result[ob.name] = mesh_fingerprint(ob)
    return result


def _world(row, point):
    x, y, z = point
    angle = math.radians(row["yaw_degrees"])
    return (row["center_m"][0]+x*math.cos(angle)-y*math.sin(angle),
            row["center_m"][1]+x*math.sin(angle)+y*math.cos(angle), row["pad_level_m"]+z)


def _local(row, point):
    x, y = point[0]-row["center_m"][0], point[1]-row["center_m"][1]
    angle = math.radians(row["yaw_degrees"])
    return (x*math.cos(angle)+y*math.sin(angle), -x*math.sin(angle)+y*math.cos(angle), point[2]-row["pad_level_m"])


def audit(api, buildings, output=None, source_furniture=None):
    bpy = api["bpy"]
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    rows = buildings.get("buildings", []) if isinstance(buildings, dict) else buildings
    trees, tree_failures, tree_face_materials = {}, [], {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    def tree(ob):
        if ob.name not in trees:
            if ob.type != "MESH" or not ob.data.polygons:
                trees[ob.name] = None
            else:
                evaluated = ob.evaluated_get(depsgraph)
                evaluated_mesh = evaluated.to_mesh()
                try:
                    vertices = [evaluated.matrix_world@v.co for v in evaluated_mesh.vertices]
                    polygons = [tuple(p.vertices) for p in evaluated_mesh.polygons]
                    trees[ob.name] = BVHTree.FromPolygons(vertices, polygons, all_triangles=False)
                    tree_face_materials[ob.name] = [ob.material_slots[p.material_index].material.name
                        if p.material_index < len(ob.material_slots) and ob.material_slots[p.material_index].material else None
                        for p in evaluated_mesh.polygons]
                except Exception as error:
                    tree_failures.append({"object": ob.name, "error": str(error)})
                    trees[ob.name] = None
                finally:
                    evaluated.to_mesh_clear()
        return trees[ob.name]
    def segment(objects, row, start, end):
        a, b = Vector(_world(row, start)), Vector(_world(row, end))
        direction = b-a
        length = direction.length
        if length < 1e-8:
            return []
        direction.normalize()
        hits = []
        for ob in objects:
            bvh = tree(ob)
            if bvh is None:
                continue
            location, normal, index, distance = bvh.ray_cast(a, direction, length)
            if location is not None:
                materials = tree_face_materials.get(ob.name, [])
                hits.append({"object": ob.name, "distance_m": distance, "world_m": list(location),
                             "face_index": index, "normal_world": list(normal),
                             "material": materials[index] if index is not None and index < len(materials) else None})
        return hits
    reports, failures, totals = [], [], Counter()
    source_furniture = source_furniture or {}
    source_pose_results = []
    for name, expected in source_furniture.items():
        ob = bpy.data.objects.get(name)
        actual = mesh_fingerprint(ob) if ob and ob.type == "MESH" else None
        passed = bool(actual and actual["geometry_sha256"] == expected["geometry_sha256"])
        source_pose_results.append({"object": name, "pass": passed,
                                    "expected_geometry_sha256": expected["geometry_sha256"],
                                    "actual_geometry_sha256": actual["geometry_sha256"] if actual else None})
        if not passed:
            failures.append({"object": name, "reason": "Source furnishing vertices/topology/pose changed or disappeared"})
    for row in rows:
        ident, group = row["id"], row["group"]
        root = bpy.data.collections.get(row["collections"]["root"])
        objects = list(root.all_objects) if root else []
        meshes = [o for o in objects if o.type == "MESH"]
        errors = []
        if not root:
            errors.append("missing building root collection")
        owner_failures = [o.name for o in objects if o.get("building_id") != ident]
        if owner_failures:
            errors.append("incorrect explicit building owner")
        wall_meshes = [bpy.data.objects[n] for n in row.get("exterior_wall_objects", []) if bpy.data.objects.get(n)]
        windows = []
        for index, window in enumerate(row.get("window_apertures", [])):
            co, center, z = window["coordinate_m"], window["center_m"], window["center_z_local_m"]
            # Reserve frames include an authored .035m centre mullion. Test
            # actual pane interiors on each side and at two heights, keeping
            # the opaque-wall solid control below the opening. The bar itself
            # is legitimate joinery, not an obstructed wall aperture.
            hits, solid_hits = [], []
            probes = [(delta, dz) for delta in (-.22, .22) for dz in (-.18, .18)] if group == "reserve" else [(-.22, 0), (0., 0), (.22, 0)]
            for delta, vertical_delta in probes:
                along = center+delta*window["width_m"]
                zz = z+vertical_delta*window["height_m"]
                start = (co-.32, along, zz) if window["axis"] == "x" else (along, co-.32, zz)
                end = (co+.32, along, zz) if window["axis"] == "x" else (along, co+.32, zz)
                hits.extend(segment(wall_meshes, row, start, end))
            # Control immediately below the actual wall window, avoiding the
            # decorative external sill. This must intersect the opaque shell.
            control_z = z-window["height_m"]/2-.13
            start = (co-.32, center, control_z) if window["axis"] == "x" else (center, co-.32, control_z)
            end = (co+.32, center, control_z) if window["axis"] == "x" else (center, co+.32, control_z)
            solid_hits = segment(wall_meshes, row, start, end)
            passed = bool(wall_meshes) and not hits and bool(solid_hits)
            windows.append({"index": index, "level": window["level"], "face": window["face"],
                            "pane_probe_offsets_width_height": probes,
                            "pass": passed, "opaque_shell_hits_in_window": hits, "below_window_solid_controls": solid_hits})
            if not passed:
                errors.append(f"window {index} lacks an actual clear shell aperture or solid control")
        floors = []
        for floor in row["interior"]["levels"]:
            level, ff = floor["level"], floor["finished_floor_local_z_m"]
            floor_errors = []
            level_col = bpy.data.collections.get(ident+f"_Interior_L{level:02d}")
            if level_col is None:
                floor_errors.append("missing floor collection")
            elif (level_col.get("reserve_floor_index" if group == "reserve" else "floor_index") != level
                  or abs(level_col.get("finished_floor_local_z_m", -999)-ff) > 1e-5):
                floor_errors.append("wrong native floor index or elevation")
            partitions = [o for o in meshes if (o.get("interior_role") == "partition_with_openings" and f"_L{level:02d}_" in o.name)
                          or (group == "reserve" and o.get("reserve_role") == "interior_partitions_with_real_door_holes")]
            opening_results = []
            solid_partition_results = []
            for wall_index, wall in enumerate(floor.get("partitions", [])):
                co, axis = wall["coordinate_m"], wall["axis"]
                for opening_index, opening in enumerate(wall.get("openings", [])):
                    center = opening["center_m"]
                    z = ff+opening["bottom_m"]+opening["height_m"]*.5
                    start = (co-.30, center, z) if axis == "x" else (center, co-.30, z)
                    end = (co+.30, center, z) if axis == "x" else (center, co+.30, z)
                    hits = segment(partitions, row, start, end)
                    solid_z = ff+wall["height_m"]-.06
                    start = (co-.30, center, solid_z) if axis == "x" else (center, co-.30, solid_z)
                    end = (co+.30, center, solid_z) if axis == "x" else (center, co+.30, solid_z)
                    control = segment(partitions, row, start, end)
                    passed = bool(partitions) and not hits and bool(control)
                    opening_results.append({"partition_index": wall_index, "opening_index": opening_index,
                                            "kind": opening["kind"], "pass": passed, "aperture_hits": hits,
                                            "solid_lintel_controls": control})
                    if not passed:
                        floor_errors.append(f"partition {wall_index} opening {opening_index} failed geometric hole/lintel test")
                lo, hi = wall["span_m"]
                count = max(1, math.ceil((hi-lo)/.25))
                for i in range(count):
                    along = lo+(hi-lo)*(i+.5)/count
                    z = min(1.2, wall["height_m"]*.6)
                    if any(abs(along-o["center_m"]) < o["width_m"]/2+.025 and
                           o["bottom_m"]-.025 < z < o["bottom_m"]+o["height_m"]+.025
                           for o in wall.get("openings", [])):
                        continue
                    start = (co-.22, along, ff+z) if axis == "x" else (along, co-.22, ff+z)
                    end = (co+.22, along, ff+z) if axis == "x" else (along, co+.22, ff+z)
                    hits = segment(partitions, row, start, end)
                    passed = bool(hits)
                    solid_partition_results.append({"partition_index": wall_index, "station_m": along,
                                                    "height_above_floor_m": z, "pass": passed, "hits": hits})
                    if not passed:
                        floor_errors.append(f"partition {wall_index} has missing solid span at {along:.4f}m")
            stair_results = []
            stair = floor.get("stair_to_next_level")
            if stair:
                stairs = [o for o in meshes if o.get("interior_role") == "functional_stair" and f"_L{level:02d}_" in o.name]
                for tread in range(stair["risers"]):
                    y = stair["first_tread_y"]+tread*stair["tread_m"]
                    x = stair["center_x"]
                    hits = segment(stairs, row, (x, y, ff+3.35), (x, y, ff-.05))
                    nearest = min(hits, key=lambda h: h["distance_m"]) if hits else None
                    expected = row["pad_level_m"]+ff+(tread+1)*stair["riser_m"]
                    passed = bool(nearest and abs(nearest["world_m"][2]-expected) <= .001)
                    stair_results.append({"tread": tread, "pass": passed, "expected_world_z_m": expected,
                                          "actual_hit": nearest})
                    if not passed:
                        floor_errors.append(f"missing or wrong-height actual stair tread {tread}")
                last_end = stair["first_tread_y"]+(stair["risers"]-1)*stair["tread_m"]+stair["tread_m"]/2
                if stair["bounds"][3]+.025 > last_end:
                    y = (last_end+stair["bounds"][3])*.5
                    x = stair["center_x"]
                    hits = segment(stairs, row, (x, y, ff+3.35), (x, y, ff+2.4))
                    nearest = min(hits, key=lambda h: h["distance_m"]) if hits else None
                    expected = row["pad_level_m"]+ff+row["interior"].get("floor_height_m", 2.85)
                    passed = bool(nearest and abs(nearest["world_m"][2]-expected) <= .001)
                    stair_results.append({"upper_landing_bridge": True, "pass": passed,
                                          "expected_world_z_m": expected, "actual_hit": nearest})
                    if not passed:
                        floor_errors.append("missing or wrong-height actual stair-to-upper-landing bridge")
            shaft_result = None
            if level > 0 and row["interior"].get("core"):
                slabs = [o for o in meshes if o.get("interior_role") == "floor_slab" and f"_Floor{level+1}_" in o.name]
                x0, y0, x1, y1 = row["interior"]["core"]["bounds"]
                x, y = (x0+x1)/2, (y0+y1)/2
                blocked = segment(slabs, row, (x, y, ff-.4), (x, y, ff+.2))
                bounds = floor.get("partial_slab_bounds", row["interior"]["clear_bounds_m"])
                control = segment(slabs, row, (bounds[0]+.35, bounds[1]+.35, ff-.4),
                                  (bounds[0]+.35, bounds[1]+.35, ff+.2))
                passed = bool(slabs and not blocked and control)
                shaft_result = {"pass": passed, "shaft_obstructions": blocked, "solid_slab_control": control}
                if not passed:
                    floor_errors.append("actual upper slab lacks clear stair shaft or solid slab control")
            rooms = []
            for room in floor["rooms"]:
                rc = bpy.data.collections.get(room["id"])
                room_errors = []
                if rc is None:
                    room_errors.append("missing room zone collection")
                elif rc.get("purpose") != room["purpose"]:
                    room_errors.append("room purpose differs from authoritative program")
                if rc and level_col and rc.name not in level_col.children:
                    room_errors.append("room outside expected floor ownership")
                fixtures = []
                for asset in room.get("assets", []):
                    own = [o for o in (rc.all_objects if rc else []) if o.type == "MESH" and
                           (o.get("interior_asset_id") == asset["id"] or o.get("reserve_asset_id") == asset["id"])]
                    wrong = [o.name for o in own if o.get("building_id") != ident or
                             o.get("interior_room_id", o.get("reserve_room_id")) != room["id"]]
                    missing_source_objects = [name for name in asset.get("source_object_names", [])
                                              if name not in {o.name for o in own}]
                    outside = []
                    x0, y0, x1, y1 = asset["footprint_m"]
                    for ob in own:
                        # Every actual vertex, not an object-origin estimate.
                        for vertex in ob.data.vertices:
                            point = _local(row, ob.matrix_world@vertex.co)
                            if not x0-.065 <= point[0] <= x1+.065 or not y0-.065 <= point[1] <= y1+.065:
                                outside.append(ob.name)
                                break
                    passed = bool(own) and not wrong and not outside and not missing_source_objects
                    fixtures.append({"asset_id": asset["id"], "kind": asset["kind"], "pass": passed,
                                     "objects": [o.name for o in own], "wrong_owner_objects": wrong,
                                     "missing_source_objects": missing_source_objects,
                                     "objects_outside_authored_footprint_plus_065m": outside})
                    if not passed:
                        room_errors.append("missing/misowned/out-of-proxy fixture: "+asset["id"])
                totals["room_zones"] += 1
                totals["furnishings"] += len(fixtures)
                rooms.append({"room_id": room["id"], "purpose": room["purpose"],
                              "status": "FAIL" if room_errors else "PASS", "errors": room_errors,
                              "enclosure_assertion": "none; native partition tests below are explicit, circulation remains an open zone",
                              "fixtures": fixtures})
                floor_errors.extend(room_errors)
            # Actual floor controls use authored zone interiors away from shaft
            # keepouts. Ray only floor/slab surfaces, not tables above them.
            surface_meshes = [o for o in meshes if o.get("interior_role") in ("floor_finish", "floor_slab") or o.get("reserve_role") == "room_floor_finish"]
            floor_controls = []
            for room in floor["rooms"]:
                if room.get("purpose") == "protected vertical circulation":
                    continue
                a, b, c, d = room["bounds_m"]
                x, y = (a+c)/2, (b+d)/2
                exclusions = room.get("nonrectangular_exclusions_m", [])
                if any(q[0] <= x <= q[2] and q[1] <= y <= q[3] for q in exclusions):
                    x, y = a+.15, b+.15
                hits = segment(surface_meshes, row, (x, y, ff+.12), (x, y, ff-.18))
                passed = bool(hits)
                floor_controls.append({"room_id": room["id"], "pass": passed, "hits": hits})
                if not passed:
                    floor_errors.append("missing native floor control under zone: "+room["id"])
            floors.append({"level": level, "status": "FAIL" if floor_errors else "PASS", "errors": floor_errors,
                           "room_zone_count": len(rooms), "rooms": rooms, "partition_openings": opening_results,
                           "solid_partition_spans": solid_partition_results, "stair_treads_and_bridge": stair_results,
                           "upper_slab_shaft": shaft_result,
                           "floor_controls": floor_controls, "window_apertures": [r for r in windows if r["level"] == level],
                           "visual_review": "MISSING"})
            totals["floors"] += 1
            totals["partition_openings"] += len(opening_results)
            totals["solid_partition_samples"] += len(solid_partition_results)
            totals["stair_flights"] += bool(stair)
            totals["stair_tread_and_bridge_samples"] += len(stair_results)
            totals["upper_slab_shafts"] += shaft_result is not None
            errors.extend(f"L{level}: "+e for e in floor_errors)
        # Full half-metre horizontal approach at three body heights, through
        # actual saved building meshes. Glass doors/paint leaves count as solid.
        door_x = row.get("door_local_x", 0.)
        d = row["footprint_m"][1]
        ff = row["interior"]["levels"][0]["finished_floor_local_z_m"]
        entry_results = []
        for offset in (-.24, 0., .24):
            for z in (.16, .90, 1.70):
                hits = segment(meshes, row, (door_x+offset, -d/2-.45, ff+z), (door_x+offset, -d/2+.38, ff+z))
                entry_results.append({"lateral_offset_m": offset, "height_above_floor_m": z,
                                      "pass": not hits, "hits": hits})
        if any(not x["pass"] for x in entry_results):
            errors.append("exterior entry body sweep blocked")
        material_failures, uv_failures, nonfinite = [], [], []
        for ob in meshes:
            if not ob.material_slots or any(s.material is None for s in ob.material_slots):
                material_failures.append(ob.name)
            if not ob.data.uv_layers.get("MetricUV"):
                uv_failures.append(ob.name)
            if any(not math.isfinite(value) for vertex in ob.data.vertices for value in vertex.co):
                nonfinite.append(ob.name)
        if material_failures or uv_failures or nonfinite:
            errors.append("invalid native mesh material/UV/finite-coordinate structure")
        reports.append({"building_id": ident, "group": group, "status": "FAIL" if errors else "PASS",
                        "errors": errors, "mesh_objects": len(meshes), "owner_failures": owner_failures,
                        "window_apertures": windows, "entrance_body_sweeps": entry_results, "floors": floors,
                        "material_failures": material_failures, "missing_metric_uv": uv_failures,
                        "nonfinite_meshes": nonfinite, "visual_review": "MISSING"})
        totals["buildings"] += 1
        totals["window_apertures"] += len(windows)
        failures.extend({"building_id": ident, "reason": error} for error in errors)
    failures.extend(tree_failures)
    shared_reports, shared_seen = [], set()
    by_id = {r["id"]: r for r in rows}
    for row in rows:
        for interface in row.get("shared_shell_interfaces", []):
            if interface["id"] in shared_seen:
                continue
            shared_seen.add(interface["id"])
            borrower = by_id[interface["borrowing_building_id"]]
            owner_id = interface["wall_owner_id"]
            objects = [bpy.data.objects[n] for n in interface["object_names"] if bpy.data.objects.get(n)]
            missing_objects = [n for n in interface["object_names"] if not bpy.data.objects.get(n)]
            wrong_owners = [o.name for o in objects if o.get("building_id") != owner_id or
                            not set(interface["building_ids"]) <= set(o.get("shared_building_ids", []))]
            competing = []
            for ident in interface["building_ids"]:
                root = bpy.data.collections.get(by_id[ident]["collections"]["root"])
                for ob in root.all_objects if root else []:
                    if ob.type == "MESH" and (ob.name.startswith(ident+"_SideWall") or
                        "_SharedGable_for_" in ob.name or ob.get("semantic_role") in ("single_owned_shared_party_wall_closure", "single_owned_shared_party_attic_sliver") or
                        (ob.name.startswith(ident+"_RoofParts_") and ob.name.rsplit("_", 1)[-1] in ("Plaster", "Granite", "Stone", "Ochre", "PaleRose"))):
                        competing.append(ob)
            co, (lo, hi) = interface["coordinate_local_x_m"], interface["span_local_y_m"]
            samples, uncovered, duplicate_owners = [], [], []
            count = max(1, math.ceil((hi-lo)/.25))
            for floor in borrower["interior"]["levels"]:
                ff = floor["finished_floor_local_z_m"]
                for i in range(count):
                    along = lo+(hi-lo)*(i+.5)/count
                    for height in (.16, .90, 1.70, 2.35):
                        point = {"level": floor["level"], "station_m": along, "height_above_floor_m": height}
                        start, end = (co-.24, along, ff+height), (co+.24, along, ff+height)
                        hits = segment(objects, borrower, start, end)
                        other_hits = segment(competing, borrower, start, end)
                        actual_owners = sorted({bpy.data.objects[h["object"]].get("building_id") for h in other_hits})
                        passed = bool(hits) and actual_owners == [owner_id]
                        samples.append({**point, "pass": passed, "owner_ids": actual_owners,
                                        "covering_object_names": sorted({h["object"] for h in hits})})
                        if not hits:
                            uncovered.append(point)
                        if actual_owners != [owner_id]:
                            duplicate_owners.append({**point, "owner_ids": actual_owners})
            attic_samples, attic_errors = [], []
            attic = interface.get("attic_gable_shell")
            if attic:
                h, rise, half = attic["base_local_z_m"], attic["rise_m"], attic["half_depth_m"]
                owner = by_id[owner_id]
                owner_x = _local(owner, _world(borrower, (co, 0, h+rise*.4)))[0]
                owner_sign = 1 if owner_x > 0 else -1
                owner_angle = math.radians(owner["yaw_degrees"])
                expected_normal = Vector((owner_sign*math.cos(owner_angle), owner_sign*math.sin(owner_angle), 0))
                for fraction in (.12, .35, .60, .82, .94, .99985):
                    for lateral in (-.7, 0, .7):
                        station = lateral*half*(1-fraction)
                        start, end = (co-.24, station, h+rise*fraction), (co+.24, station, h+rise*fraction)
                        hits = segment(objects, borrower, start, end)
                        actual = segment(competing, borrower, start, end)
                        owners = sorted({bpy.data.objects[hit["object"]].get("building_id") for hit in actual})
                        normal_failures = [hit["object"] for hit in actual if "_SharedGable_for_Main_cafe" in hit["object"]
                                           and Vector(hit["normal_world"]).dot(expected_normal) < .95]
                        ok = bool(hits) and owners == [owner_id] and not normal_failures
                        attic_samples.append({"kind": "attic_solid_control", "station_m": station,
                                              "height_local_m": h+rise*fraction, "pass": ok, "hits": actual,
                                              "actual_owner_ids": owners, "expected_primary_owner_normal_world": list(expected_normal),
                                              "incorrect_source_gable_winding": normal_failures})
                        if not ok: attic_errors.append("Uncovered or multiply owned attic solid control")
                air_hits = segment(competing, borrower, (co-.24, 0, h+rise+.35), (co+.24, 0, h+rise+.35))
                attic_samples.append({"kind": "above_roof_air_control", "pass": not air_hits, "hits": air_hits})
                if air_hits: attic_errors.append("Unexpected geometry above the exact attic silhouette")
            passed = not (missing_objects or wrong_owners or uncovered or duplicate_owners or attic_errors)
            shared_reports.append({"interface_id": interface["id"], "building_ids": interface["building_ids"],
                                   "wall_owner_id": owner_id, "borrowing_building_id": borrower["id"],
                                   "status": "PASS" if passed else "FAIL", "checked_habitable_floors": borrower["floor_count"],
                                   "body_ray_samples": len(samples), "samples": samples,
                                   "missing_objects": missing_objects, "wrong_owners": wrong_owners,
                                   "attic_gable_samples": attic_samples, "attic_gable_errors": attic_errors,
                                   "uncovered_samples": uncovered, "unexpected_or_duplicate_owner_samples": duplicate_owners})
            if not passed:
                failures.append({"shared_shell_interface": interface["id"], "reason": "Shared wall has uncovered body samples or does not retain one actual owner"})
    totals["shared_shell_interfaces"] = len(shared_reports)
    totals["shared_shell_body_rays"] = sum(r["body_ray_samples"] for r in shared_reports)
    report = {"schema": "living_town.whole_town_native_geometry.v1", "status": "FAIL" if failures else "PASS",
              "scope": "Read-only actual-mesh checks in the current scene: every zone/fixture/partition/window and entry, with finite ray samples. Visual quality and gameplay require separate evidence.",
              "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "scene": bpy.context.scene.name, "loaded_native_path": bpy.data.filepath,
              "counts": dict(totals), "source_furniture_geometry_checks": source_pose_results,
              "shared_shell_coverage": shared_reports,
              "source_furniture_geometry_status": "PASS" if source_pose_results and all(x["pass"] for x in source_pose_results) else "NOT_SUPPLIED" if not source_pose_results else "FAIL",
              "buildings": reports, "failures": failures, "all_visual_acceptance": False,
              "scene_mutations": []}
    if output:
        Path(output).write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    return report
