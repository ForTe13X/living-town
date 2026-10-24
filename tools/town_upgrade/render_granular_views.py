"""Render source-bound native patio, contact, planting and bathhouse details.

Run in Blender, with a fresh output directory. This tool changes only temporary
review cameras and render settings. Native objects, lights, terrain, vegetation,
materials and cover remain present; nothing is saved or exported. Sampled
triangle visibility is diagnostic and never grants visual or path acceptance.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
VIEWS = ("civic_table_arrangement", "civic_chair_ground_contact",
         "garden_soil_and_underplanting", "bathhouse_sign_and_approach")
SOIL = "Reference_Pocket_Gardens_Dirt"


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def binding(path):
    path = Path(path).resolve()
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha(path)}


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def bounds(points):
    return [[min(p[k] for p in points) for k in range(3)],
            [max(p[k] for p in points) for k in range(3)]]


def center(box):
    return [(box[0][k] + box[1][k]) * .5 for k in range(3)]


def corners(box):
    return [(x, y, z) for x in (box[0][0], box[1][0])
            for y in (box[0][1], box[1][1]) for z in (box[0][2], box[1][2])]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def native_guard(objects):
    return digest([(ob.name, ob.type, ob.data.name if ob.data else None,
                    [list(row) for row in ob.matrix_world], ob.hide_render, ob.hide_viewport,
                    len(ob.data.vertices) if ob.type == "MESH" else None,
                    len(ob.data.polygons) if ob.type == "MESH" else None)
                   for ob in objects])


def load_components_helper(receipt):
    relative = "tools/town_upgrade/scale_figures.py"
    path = ROOT / relative
    expected = receipt.get("source_bindings", {}).get(relative, {}).get("sha256")
    if not expected or sha(path) != expected:
        raise ValueError("Entry receipt's read-only component helper differs")
    spec = importlib.util.spec_from_file_location("granular_native_components", path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    return helper, binding(path)


class GeometryQueries:
    """Bounded local rays against actual evaluated native triangles, including props.

    Leaves remain conservative opaque triangles for this geometric diagnostic.
    Render alpha cutouts can reveal more than these rays report. No visibility
    flags or geometry are modified to improve a camera score.
    """
    def __init__(self, bpy, Vector, BVHTree, native_objects):
        self.bpy, self.Vector, self.BVHTree = bpy, Vector, BVHTree
        self.depsgraph = bpy.context.evaluated_depsgraph_get()
        self.records, self.grid, self.cache = {}, defaultdict(list), {}
        self.cell = 8.
        enabled = set()
        def walk(layer, hidden=False):
            hidden = hidden or layer.exclude or layer.collection.hide_render
            if not hidden:
                enabled.update(ob.name for ob in layer.collection.objects)
            for child in layer.children:
                walk(child, hidden)
        walk(bpy.context.view_layer.layer_collection)
        for ob in native_objects:
            if ob.name in enabled and not ob.hide_render:
                self.add(ob, ob.matrix_world.copy(), ob.name, False)
        instances = 0
        for instance in self.depsgraph.object_instances:
            if not instance.is_instance:
                continue
            ob = instance.object.original
            parent = instance.parent.original if instance.parent else None
            if ob.hide_render or (parent is not None and parent.name not in enabled):
                continue
            key = ob.name + "::instance::" + str(tuple(instance.persistent_id))
            self.add(ob, instance.matrix_world.copy(), key, True)
            instances += 1
        self.support = [r for r in self.records.values() if self.is_support(r["object"])]
        self.inventory = {"native_renderable_geometry_records": len(self.records),
                          "dependency_graph_instances": instances,
                          "support_objects": sorted({r["object"].name for r in self.support}),
                          "triangle_visibility_policy": self.__doc__.strip()}

    @staticmethod
    def is_support(ob):
        return (ob.name in ("Atlantic_Terrain_Grass", "Connected_Streets_and_Pavements_Paving")
                or ob.get("reserve_role") in ("terrain", "trail", "graded_pad", "bridge_deck")
                or ob.name.startswith("Reserve_Stone_Stairs_"))

    def add(self, ob, matrix, key, instance):
        if ob.type not in ("MESH", "FONT", "CURVE", "SURFACE", "META"):
            return
        box = bounds([tuple(matrix @ self.Vector(p)) for p in ob.bound_box])
        record = {"object": ob, "matrix": matrix, "key": key,
                  "bounds": box, "instance": instance}
        self.records[key] = record
        for x in range(math.floor(box[0][0] / self.cell), math.floor(box[1][0] / self.cell) + 1):
            for y in range(math.floor(box[0][1] / self.cell), math.floor(box[1][1] / self.cell) + 1):
                self.grid[x, y].append(key)

    def nearby(self, lo, hi):
        names = set()
        for x in range(math.floor(lo[0] / self.cell), math.floor(hi[0] / self.cell) + 1):
            for y in range(math.floor(lo[1] / self.cell), math.floor(hi[1] / self.cell) + 1):
                names.update(self.grid.get((x, y), ()))
        return [self.records[name] for name in sorted(names)
                if all(hi[k] >= self.records[name]["bounds"][0][k]
                       and lo[k] <= self.records[name]["bounds"][1][k] for k in range(3))]

    def tree(self, ob):
        key = ob.as_pointer()
        if key not in self.cache:
            evaluated = ob.evaluated_get(self.depsgraph)
            mesh = evaluated.to_mesh()
            try:
                mesh.calc_loop_triangles()
                triangles = [tuple(t.vertices) for t in mesh.loop_triangles]
                tree = self.BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices], triangles,
                                                all_triangles=True) if triangles else None
                self.cache[key] = tree, [int(t.polygon_index) for t in mesh.loop_triangles]
            finally:
                evaluated.to_mesh_clear()
        return self.cache[key]

    def cast(self, record, start, end):
        tree, polygons = self.tree(record["object"])
        if tree is None:
            return None
        inverse = record["matrix"].inverted()
        local_start, local_end = inverse @ self.Vector(start), inverse @ self.Vector(end)
        delta = local_end - local_start
        if delta.length < 1e-9:
            return None
        point, normal, triangle, _distance = tree.ray_cast(local_start, delta.normalized(), delta.length)
        if point is None:
            return None
        world = record["matrix"] @ point
        return {"object": record["object"].name, "geometry_record": record["key"],
                "instance": record["instance"], "point_world_m": list(world),
                "distance_m": (world - self.Vector(start)).length,
                "evaluated_loop_triangle": int(triangle), "evaluated_polygon": polygons[triangle]}

    def support_at(self, x, y, objects=None):
        selected = [r for r in (self.support if objects is None else objects)
                    if r["bounds"][0][0] - .001 <= x <= r["bounds"][1][0] + .001
                    and r["bounds"][0][1] - .001 <= y <= r["bounds"][1][1] + .001]
        if not selected:
            return None
        top = max(r["bounds"][1][2] for r in selected) + 1.
        bottom = min(r["bounds"][0][2] for r in selected) - 1.
        hits = [self.cast(r, (x, y, top), (x, y, bottom)) for r in selected]
        return max((hit for hit in hits if hit), key=lambda h: h["point_world_m"][2], default=None)

    def sample_visibility(self, position, sample):
        start, target = self.Vector(position), self.Vector(sample["point_world_m"])
        delta = target - start
        end = target + delta.normalized() * .025
        hits = [self.cast(r, start, end) for r in self.nearby(
            [min(start[k], end[k]) for k in range(3)],
            [max(start[k], end[k]) for k in range(3)])]
        first = min((h for h in hits if h), key=lambda h: h["distance_m"], default=None)
        visible = bool(first and first["object"] == sample["object"]
                       and abs(first["distance_m"] - delta.length) <= .025)
        return {**sample, "sampled_surface_visible": visible,
                "status": "TARGET_SURFACE_HIT" if visible else
                          "NO_TRIANGLE_CONFIRMATION" if first is None else "OCCLUDED",
                "first_hit": first, "surface_distance_tolerance_m": .025}

    def camera_surface_clearance(self, position, radius=.18):
        """Reject near-surface cameras; this is not a closed-volume proof."""
        p = self.Vector(position)
        nearest = None
        for record in self.nearby([v - radius for v in p], [v + radius for v in p]):
            tree, _polygons = self.tree(record["object"])
            if tree is None:
                continue
            inverse = record["matrix"].inverted()
            scale = min(abs(v) for v in record["matrix"].to_scale())
            point, _normal, _index, _distance = tree.find_nearest(inverse @ p, radius / max(scale, .00001))
            if point is not None:
                distance = (record["matrix"] @ point - p).length
                if distance < radius and (nearest is None or distance < nearest["distance_m"]):
                    nearest = {"object": record["object"].name, "distance_m": distance,
                               "geometry_record": record["key"]}
        return {"query_radius_m": radius, "near_surface": nearest,
                "scope": "Finite point-to-evaluated-surface clearance, not containment or collision certification"}


def triangle_samples(ob, component, Vector, label, count=1, low_side=False):
    ob.data.calc_loop_triangles()
    polygons = {p.index for p in component["polygons"]}
    choices = []
    goal = center(component["bounds"])
    for tri in ob.data.loop_triangles:
        if tri.polygon_index not in polygons:
            continue
        points = [ob.matrix_world @ ob.data.vertices[index].co for index in tri.vertices]
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        if normal.length < 1e-10:
            continue
        normal.normalize()
        if low_side:
            if abs(normal.z) > .8:
                continue
            first = min(range(3), key=lambda i: points[i].z)
            point = points[first] * .9 + points[(first + 1) % 3] * .05 + points[(first + 2) % 3] * .05
            score = abs(point.z - (component["bounds"][0][2] + .025))
        else:
            if normal.z < .65:
                continue
            point = sum(points, Vector()) / 3.
            score = (point.x - goal[0]) ** 2 + (point.y - goal[1]) ** 2 - point.z * .01
        choices.append((score, {"label": label, "object": ob.name,
                               "point_world_m": list(point), "native_polygon": tri.polygon_index,
                               "native_loop_triangle": tri.index, "weight": 1.}))
    choices.sort(key=lambda item: item[0])
    if not choices:
        raise ValueError("No positive-area native surface samples: " + label)
    return [row for _score, row in choices[:count]]


def entry_geometry(bpy, Vector, receipt, helper):
    if receipt.get("schema") != "living_town.source_bound_entry_details.v1" or len(receipt.get("components", [])) != 195:
        raise ValueError("Require the actual195-component entry detail receipt")
    cached, selected, evidence = {}, {}, []
    for row in receipt["components"]:
        name, index = row["source_object"], int(row["source_component"])
        ob = bpy.data.objects.get(name)
        if ob is None or ob.type != "MESH":
            raise ValueError("Native entry target missing: " + name)
        if name not in cached:
            cached[name] = helper._components(ob)
        component = cached[name][index]
        actual_hash = helper._component_hash(ob, component)
        if len(component["points"]) != row["vertex_count"] or actual_hash != row["new_geometry_uv_sha256"]:
            raise ValueError("Native does not contain exact receipted entry geometry: " + row["label"])
        selected[row["label"]] = ob, component
        evidence.append({"label": row["label"], "object": name, "component": index,
                         "world_geometry_uv_sha256": actual_hash, "world_bounds_m": component["bounds"]})
    text = receipt["text"]
    label = bpy.data.objects.get(text["object"])
    if label is None or label.type != "FONT":
        raise ValueError("Native bathhouse sign text is missing")
    actual = bounds([tuple(label.matrix_world @ Vector(p)) for p in label.bound_box])
    if max(abs(a - b) for aa, bb in zip(actual, text["new_world_bounds_m"]) for a, b in zip(aa, bb)) > .0002:
        raise ValueError("Actual bathhouse text bounds differ from entry receipt")
    return selected, {"verified_component_count": len(evidence), "components": evidence,
                      "actual_text_bounds_m": actual, "actual_text_body": label.data.body,
                      "actual_text_size_m": label.data.size}


def soil_geometry(bpy, helper):
    ob = bpy.data.objects.get(SOIL)
    if ob is None or ob.type != "MESH" or len(ob.data.vertices) != 781:
        raise ValueError("Expected actual781-vertex garden soil object")
    islands = helper._components(ob)
    expected = [(0, i + 1, (i + 1) % 10 + 1) for i in range(10)]
    if len(islands) != 71 or any(len(c["points"]) != 11 or c["faces"] != expected for c in islands):
        raise ValueError("Garden soil must retain its71 actual11-vertex/10-triangle ellipses")
    index, chosen = min(enumerate(islands), key=lambda row: math.dist(row[1]["points"][0][:2], (22., 3.)))
    return ob, chosen, {"object": ob.name, "vertices": len(ob.data.vertices), "islands": len(islands),
                        "chosen_component": index, "actual_center_world_m": chosen["points"][0],
                        "requested_neighborhood_xy_m": [22., 3.],
                        "current_native_fingerprint": helper._fingerprint(ob),
                        "material_slots": [m.name if m else None for m in ob.data.materials]}


def build_specs(bpy, Vector, rows, receipt, selected, soil, queries, helper, plan):
    specs = {}
    groups = {row["id"]: row for row in receipt["groups"]}
    samples, framing = [], []
    for number in range(3):
        group = groups[f"civic_patio_table_{number}"]
        framing.extend(corners(group["new_world_bounds_m"]))
        for part, count in ((0, 2), (6, 1), (35, 1)):
            ob, component = selected[f"patio_{number}_part_{part:02d}"]
            samples.extend(triangle_samples(ob, component, Vector, f"table{number}_part{part}", count))
    specs[VIEWS[0]] = {"samples": samples, "framing": framing, "target": center(bounds(framing)),
                        "distances": (8., 10.), "angles": tuple(range(0, 360, 45)), "eye": 1.7,
                        "lens_candidates": (40., 34., 28., 24.), "provenance": "All3 actual receipted civic sets"}
    foot_parts = [selected[f"patio_0_part_{i:02d}"] for i in range(6, 35)]
    minimum = min(c["bounds"][0][2] for _ob, c in foot_parts)
    feet = [(ob, c) for ob, c in foot_parts if c["bounds"][0][2] <= minimum + .011]
    foot_samples, foot_points = [], []
    for number, (ob, component) in enumerate(feet):
        foot_samples.extend(triangle_samples(ob, component, Vector, f"actual_chair_leg_{number}", 2, True))
        foot_points.extend(p for p in component["points"] if p[2] < minimum + .08)
        xy = center(component["bounds"])
        support = queries.support_at(xy[0] - .12, xy[1] - .12)
        if support:
            foot_samples.append({"label": f"actual_paving_near_foot_{number}", "object": support["object"],
                                 "point_world_m": support["point_world_m"], "weight": 1., "support": support})
    foot_box = bounds(foot_points)
    foot_box = [[foot_box[0][0] - .2, foot_box[0][1] - .2, minimum - .02],
                [foot_box[1][0] + .2, foot_box[1][1] + .2, minimum + .3]]
    specs[VIEWS[1]] = {"samples": foot_samples, "framing": corners(foot_box), "target": center(foot_box),
                        "distances": (1.7, 2.2), "angles": tuple(range(0, 360, 45)), "eye": 1.45,
                        "lens_candidates": (55., 45., 35.), "provenance": "Actual first-set positive-X chair lower native leg surfaces + measured nearby paving",
                        "receipt_grounding": groups["civic_patio_table_0"]["grounding"]}
    soil_ob, island, soil_proof = soil
    soil_samples = triangle_samples(soil_ob, island, Vector, "actual_soil_grain", 5)
    for sample in soil_samples:
        sample["weight"] = 2.
    soil_center = island["points"][0]
    plant_samples, searched, truncated = [], [], []
    for record in queries.nearby((soil_center[0] - 1., soil_center[1] - 1., soil_center[2]),
                                 (soil_center[0] + 1., soil_center[1] + 1., soil_center[2] + 1.3)):
        ob = record["object"]
        if ob.type != "MESH" or ob.name == SOIL or queries.is_support(ob) or record["instance"]:
            continue
        tags = " ".join([ob.name, *[str(ob.get(k, "")) for k in ("vegetation_role", "botanical_role", "horticulture_role", "landscape_role")]]).lower()
        if not any(word in tags for word in ("plant", "fern", "flower", "understory", "pocket_garden", "grass")):
            continue
        searched.append(ob.name)
        ob.data.calc_loop_triangles()
        for index, tri in enumerate(ob.data.loop_triangles):
            if index >= 100000:
                truncated.append(ob.name)
                break
            point = sum((ob.matrix_world @ ob.data.vertices[i].co for i in tri.vertices), Vector()) / 3.
            if math.dist(point.xy, soil_center[:2]) < .65 and soil_center[2] + .08 < point.z < soil_center[2] + 1.1:
                plant_samples.append({"label": "actual_underplanting", "object": ob.name,
                                      "point_world_m": list(point), "native_loop_triangle": tri.index, "weight": 1.})
                break
        if len(searched) >= 24:
            break
    planting = {"soil": soil_proof, "searched_native_plant_objects": searched,
                "plant_surface_samples_found": len(plant_samples), "triangle_scan_cap_per_object": 100000,
                "truncated_triangle_scans": truncated, "object_scan_cap": 24}
    bed_box = [[soil_center[0] - .7, soil_center[1] - .7, soil_center[2] - .03],
               [soil_center[0] + .7, soil_center[1] + .7, soil_center[2] + .75]]
    specs[VIEWS[2]] = {"samples": soil_samples + plant_samples[:5], "framing": corners(bed_box),
                        "target": [soil_center[0], soil_center[1], soil_center[2] + .15],
                        "distances": (2.3, 2.8), "angles": tuple(range(0, 360, 45)), "eye": 1.55,
                        "lens_candidates": (50., 42., 34.), "provenance": planting}
    text = bpy.data.objects[receipt["text"]["object"]]
    evaluated = text.evaluated_get(queries.depsgraph)
    mesh = evaluated.to_mesh()
    sign_samples = []
    try:
        mesh.calc_loop_triangles()
        candidates = []
        for tri in mesh.loop_triangles:
            points = [text.matrix_world @ mesh.vertices[i].co for i in tri.vertices]
            normal = (points[1] - points[0]).cross(points[2] - points[0])
            if normal.length > 1e-10 and normal.normalized().x > .9:
                candidates.append(sum(points, Vector()) / 3.)
        candidates.sort(key=lambda p: p.y)
        for index in sorted({0, len(candidates) // 2, len(candidates) - 1}):
            if candidates:
                sign_samples.append({"label": "actual_DOUCHES_glyph", "object": text.name,
                                     "point_world_m": list(candidates[index]), "weight": 2.})
    finally:
        evaluated.to_mesh_clear()
    if not sign_samples:
        raise ValueError("No actual front-facing bathhouse glyph triangles")
    route = next(p for p in plan["paths"] if p["id"] == "Reserve_Bathhouse_Approach")
    route_objects = [r for r in queries.records.values() if r["object"].get("reserve_route_id") == route["id"]]
    if not route_objects:
        raise ValueError("Actual bathhouse approach trail geometry is missing")
    path_samples = []
    for number, point in enumerate(route["points_m"][:2]):
        hit = queries.support_at(point[0], point[1], route_objects)
        if hit is None:
            raise ValueError("Actual approach surface not found at authored station")
        path_samples.append({"label": f"actual_approach_surface_{number}", "object": hit["object"],
                             "point_world_m": hit["point_world_m"], "weight": 1., "support": hit})
    post = groups["Reserve_Bathhouse_Approach:point0"]
    for row in receipt["components"]:
        if row["label"].startswith("bathhouse_") or row["source_object"].startswith("Reserve_Trailside_Rest_and_Wayfinding"):
            ob, component = selected[row["label"]]
            # Side faces of the real vertical assembly, sampled conservatively.
            sign_samples.extend(triangle_samples(ob, component, Vector, row["label"], 1, True))
    bath_framing = corners(receipt["text"]["new_world_bounds_m"]) + corners(post["new_world_bounds_m"])
    bath_framing.extend(s["point_world_m"] for s in path_samples)
    bath = rows["Reserve_Bathhouse"]
    specs[VIEWS[3]] = {"samples": sign_samples + path_samples, "framing": bath_framing,
                        "target": center(bounds(bath_framing)), "distances": (5.5, 7.),
                        "angles": (-25, 0, 25, 45), "eye": 1.7,
                        "lens_candidates": (48., 40., 32.), "provenance": {"actual_sign_bounds": receipt["text"]["new_world_bounds_m"],
                        "recorded_building": {k: bath[k] for k in ("id", "center_m", "yaw_degrees", "pad_level_m", "footprint_m", "door_aperture_width_m")},
                        "actual_wayfinding_bounds": post["new_world_bounds_m"], "authored_path": route,
                        "scope": "Camera samples only; no path traversal or full clearance certification"}}
    return specs


def candidate_camera(bpy, Vector, project, camera, spec, queries, rows):
    target = Vector(spec["target"])
    candidates, rejected = [], []
    aspect = bpy.context.scene.render.resolution_x / bpy.context.scene.render.resolution_y
    for distance in spec["distances"]:
        for angle in spec["angles"]:
            radians = math.radians(angle)
            x, y = target.x + distance * math.cos(radians), target.y + distance * math.sin(radians)
            support = queries.support_at(x, y)
            if support is None:
                rejected.append({"xy_m": [x, y], "reason": "no_actual_ground_triangle"})
                continue
            position = Vector((x, y, support["point_world_m"][2] + spec["eye"]))
            inside = []
            for row in rows.values():
                yaw = math.radians(row["yaw_degrees"])
                dx, dy = x - row["center_m"][0], y - row["center_m"][1]
                local = (dx * math.cos(yaw) + dy * math.sin(yaw), -dx * math.sin(yaw) + dy * math.cos(yaw))
                if abs(local[0]) < row["footprint_m"][0] / 2 + .1 and abs(local[1]) < row["footprint_m"][1] / 2 + .1:
                    inside.append(row["id"])
            if inside:
                rejected.append({"xy_m": [x, y], "reason": "inside_recorded_building_footprint", "buildings": inside})
                continue
            clearance = queries.camera_surface_clearance(position)
            if clearance["near_surface"] is not None:
                rejected.append({"xy_m": [x, y], "reason": "camera_too_near_actual_native_surface", "clearance": clearance})
                continue
            camera.location = position
            camera.rotation_euler = (target - position).to_track_quat("-Z", "Y").to_euler()
            fitted = None
            for lens in spec["lens_candidates"]:
                camera.data.lens = lens
                bpy.context.view_layer.update()
                projection = [project(bpy.context.scene, camera, Vector(point)) for point in spec["framing"]]
                if all(p.z > 0 and .035 <= p.x <= .965 and .035 <= p.y <= .965 for p in projection):
                    fitted = lens
                    break
            if fitted is None:
                rejected.append({"xy_m": [x, y], "reason": "actual_targets_do_not_fit_allowed_lenses"})
                continue
            rays = [queries.sample_visibility(position, sample) for sample in spec["samples"]]
            visible = sum(r["weight"] for r in rays if r["sampled_surface_visible"])
            candidates.append({"position_world_m": list(position), "target_world_m": list(target),
                               "eye_above_actual_ground_m": spec["eye"], "actual_camera_ground": support,
                               "camera_surface_clearance": clearance,
                               "lens_mm": fitted, "visible_weight": visible, "samples": rays,
                               "all_framing_points_inside_image": True,
                               "score": visible - distance * .002, "aspect": aspect})
    if not candidates:
        raise ValueError("No measured-ground human-height camera fits targets: " + json.dumps(rejected[-8:]))
    candidates.sort(key=lambda row: row["score"], reverse=True)
    chosen = candidates[0]
    camera.location = chosen["position_world_m"]
    camera.rotation_euler = (Vector(chosen["target_world_m"]) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = chosen["lens_mm"]
    bpy.context.view_layer.update()
    chosen["camera_matrix_world"] = [list(row) for row in camera.matrix_world]
    return {"selection": "Bounded human-eye cameras on actual native support; best sampled visibility without hiding site geometry",
            "candidate_count": len(candidates), "rejected_count": len(rejected), "selected": chosen,
            "other_candidates": [{k: v for k, v in row.items() if k != "samples"} for row in candidates[1:5]],
            "rejected": rejected, "status": "SAMPLED_GEOMETRY_DIAGNOSTIC_REQUIRES_IMAGE_REVIEW"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("native", "buildings", "entry-receipt", "output"):
        parser.add_argument("--" + flag, type=Path, required=True)
    parser.add_argument("--views", default=",".join(VIEWS))
    parser.add_argument("--size", type=int, default=1600)
    parser.add_argument("--samples", type=int, default=16)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    names = [name.strip() for name in args.views.split(",") if name.strip()]
    if not names or len(names) != len(set(names)) or set(names) - set(VIEWS):
        parser.error("--views must name distinct supported granular views")
    if not 640 <= args.size <= 4096 or not 1 <= args.samples <= 512:
        parser.error("--size must be640..4096 and --samples1..512")
    args.output = args.output.resolve()
    if args.output.exists() and any(args.output.iterdir()):
        raise FileExistsError("Keep old evidence; require a fresh output directory")
    args.output.mkdir(parents=True, exist_ok=True)
    receipt = read(args.entry_receipt)
    if sha(args.buildings) != receipt.get("record_bindings", {}).get("whole_town_buildings.json"):
        raise ValueError("Building records differ from the actual entry receipt")
    plan_path = ROOT / "art/living_town/reserve_plan.json"
    if sha(plan_path) != receipt.get("source_bindings", {}).get("art/living_town/reserve_plan.json", {}).get("sha256"):
        raise ValueError("Authored approach plan differs from entry receipt")
    helper, helper_binding = load_components_helper(receipt)
    inputs = {key: binding(value) for key, value in {"native": args.native, "buildings": args.buildings,
              "entry_receipt": args.entry_receipt, "tool": __file__, "reserve_plan": plan_path}.items()}
    report = {"schema": "living_town.granular_native_views.v1", "status": "IN_PROGRESS", "inputs": inputs,
              "component_helper": helper_binding, "requested_views": names, "views": [],
              "native_objects_hidden_or_moved": [], "native_geometry_mutations": [], "native_saved": False,
              "exported": False, "visual_acceptance": "PENDING_ACTUAL_IMAGE_REVIEW",
              "limits": "Finite conservative triangle samples do not prove every pixel, alpha transparency, path clearance, collision, art quality or concept acceptance."}
    report_path = args.output / "granular_render_receipts.json"
    write(report_path, report)
    try:
        import bpy
        from mathutils import Vector
        from mathutils.bvhtree import BVHTree
        from bpy_extras.object_utils import world_to_camera_view
        bpy.ops.wm.open_mainfile(filepath=str(args.native.resolve()), load_ui=False, use_scripts=False)
        scene = bpy.context.scene
        native_objects = list(scene.objects)
        bpy.context.view_layer.update()
        before = native_guard(native_objects)
        selected, entry_proof = entry_geometry(bpy, Vector, receipt, helper)
        soil = soil_geometry(bpy, helper)
        queries = GeometryQueries(bpy, Vector, BVHTree, native_objects)
        rows = {row["id"]: row for row in read(args.buildings)["buildings"]}
        specs = build_specs(bpy, Vector, rows, receipt, selected, soil, queries, helper, read(plan_path))
        report.update({"actual_entry_geometry": entry_proof, "native_query_inventory": queries.inventory,
                       "actual_soil": soil[2], "native_object_state_before_sha256": before,
                       "blender_version": bpy.app.version_string, "native_current_frame": scene.frame_current})
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = args.samples
        scene.cycles.use_denoising = True
        scene.render.threads_mode = "FIXED"
        scene.render.threads = 6
        scene.render.resolution_x = args.size
        scene.render.resolution_y = round(args.size * 2 / 3)
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.film_transparent = False
        scene.view_settings.view_transform = "AgX"
        report["render_settings"] = {"engine": scene.render.engine, "device": scene.cycles.device,
            "threads": scene.render.threads, "samples": scene.cycles.samples, "denoising": scene.cycles.use_denoising,
            "resolution": [scene.render.resolution_x, scene.render.resolution_y], "view_transform": scene.view_settings.view_transform,
            "look": scene.view_settings.look, "exposure": scene.view_settings.exposure, "gamma": scene.view_settings.gamma,
            "lighting": "Native world and native lights retained; no lights added, hidden or moved"}
        for name in names:
            print("GRANULAR_CAMERA_SELECT " + name, flush=True)
            data = bpy.data.cameras.new("GranularReview_" + name)
            data.type = "PERSP"
            data.clip_start, data.clip_end = .01, 3000.
            data.dof.use_dof = False
            camera = bpy.data.objects.new(data.name, data)
            scene.collection.objects.link(camera)
            scene.camera = camera
            proof = candidate_camera(bpy, Vector, world_to_camera_view, camera, specs[name], queries, rows)
            output = args.output / (name + ".png")
            scene.render.filepath = str(output)
            print("GRANULAR_RENDER " + name + " " + json.dumps({"camera": proof["selected"]["position_world_m"], "visible_samples": sum(s["sampled_surface_visible"] for s in proof["selected"]["samples"]), "sample_count": len(proof["selected"]["samples"])}), flush=True)
            bpy.ops.render.render(write_still=True)
            if native_guard(native_objects) != before:
                raise RuntimeError("Native object transforms/flags/data inventory changed during review")
            report["views"].append({"view": name, "image": binding(output), "camera_object": camera.name,
                "native_sha256": inputs["native"]["sha256"], "camera_selection": proof,
                "target_provenance": specs[name]["provenance"], "visual_acceptance": "AWAITING_IMAGE_REVIEW"})
            write(report_path, report)
        stable = all(binding(row["path"]) == row for row in inputs.values()) and binding(helper_binding["path"]) == helper_binding
        if not stable or native_guard(native_objects) != before:
            raise RuntimeError("Bound native/source/input bytes or native object state changed")
        report.update({"status": "RENDERED_REQUIRES_VISUAL_REVIEW", "inputs_stable": True,
                       "native_object_state_after_sha256": native_guard(native_objects)})
        write(report_path, report)
        print("GRANULAR_COMPLETE " + str(len(report["views"])) + " report=" + str(report_path) + " sha256=" + sha(report_path), flush=True)
    except Exception as exc:
        report.update({"status": "FAIL", "error": str(exc)})
        write(report_path, report)
        raise


if __name__ == "__main__":
    main()
