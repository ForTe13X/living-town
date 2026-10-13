"""Read-only measurements of a freshly reopened Living Town native scene.

Blender: ``--background living_town_complete.blend --python this_file.py``.
``run()`` returns JSON-compatible evidence without changing the Blender scene.
Only the CLI writes evidence/reserve_native_audit.json. This supplements, and
does not replace or relax, audit_native_scene.py or the engine audits.

Geometry is inspected in world space, including baked core vertices and linked
reserve instances. Terrain/contacts/openings use saved base-mesh BVHs; furniture
poses compare every saved vertex against the source-bound primitive recipe at
the canonical plan pose. Metadata alone cannot satisfy these measurements.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import math
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rotate(x, y, angle):
    co, si = math.cos(angle), math.sin(angle)
    return x * co - y * si, x * si + y * co


def world(frame, point):
    x, y = rotate(point[0], point[1], frame[3])
    return (frame[0] + x, frame[1] + y, frame[2] + point[2])


def interpolate(a, b, t):
    return tuple(a[k] * (1 - t) + b[k] * t for k in range(3))


def inside_polygon(x, y, polygon):
    inside = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > y) != (b[1] > y):
            if x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
                inside = not inside
    return inside


def point_segment_distance(x, y, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / max(dx * dx + dy * dy, 1e-12)))
    return math.hypot(x - a[0] - t * dx, y - a[1] - t * dy)


def clearing_contains(x, y, clearing):
    if "polygon_xy" in clearing:
        return inside_polygon(x, y, clearing["polygon_xy"])
    cx, cy = clearing["center_m"][:2]
    rx, ry = clearing["radii_m"]
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1


class Findings:
    """Keep complete failure counts, bounded examples, and useful measurements."""
    def __init__(self, limit=60):
        self.count = 0
        self.examples = []
        self.limit = limit

    def add(self, **detail):
        self.count += 1
        if len(self.examples) < self.limit:
            self.examples.append(detail)

    def detail(self, **measurements):
        return {**measurements, "failure_count": self.count, "failures": self.examples,
                "omitted_failure_examples": max(0, self.count - len(self.examples))}


class MeshQueries:
    """BVHs share mesh data, but all queries respect each actual world matrix.

    Base meshes are deliberate: bevel modifiers must not erase a true door hole
    or make the underlying construction recipe/contact test ambiguous. Evaluated
    beauty geometry and camera acceptance remain separate visual checks.
    """
    def __init__(self):
        from mathutils import Vector
        from mathutils.bvhtree import BVHTree
        self.Vector, self.BVHTree = Vector, BVHTree
        self.cache = {}
        self.rays = 0

    def bvh(self, ob):
        key = ob.data.as_pointer()
        if key not in self.cache:
            self.cache[key] = self.BVHTree.FromPolygons(
                [v.co.copy() for v in ob.data.vertices],
                [tuple(p.vertices) for p in ob.data.polygons], all_triangles=False)
        return self.cache[key]

    def ray(self, objects, origin, direction, distance):
        start = self.Vector(origin)
        direction = self.Vector(direction).normalized()
        nearest = None
        self.rays += 1
        for ob in objects:
            if ob.type != "MESH" or not ob.data.polygons:
                continue
            inv = ob.matrix_world.inverted()
            local_direction = inv.to_3x3() @ direction
            scale = local_direction.length
            if scale < 1e-12:
                continue
            hit, normal, index, length = self.bvh(ob).ray_cast(
                inv @ start, local_direction / scale, distance * scale)
            if hit is None:
                continue
            point = ob.matrix_world @ hit
            travelled = (point - start).dot(direction)
            if -.0001 <= travelled <= distance + .0001 and (nearest is None or travelled < nearest["distance_m"]):
                world_normal = (inv.to_3x3().transposed() @ normal).normalized()
                nearest = {"point_m": list(point), "distance_m": float(travelled),
                           "object": ob.name, "polygon": index, "normal_world": list(world_normal)}
        return nearest

    def down(self, objects, x, y, top=180, bottom=-20):
        hit = self.ray(objects, (x, y, top), (0, 0, -1), top - bottom)
        return hit["point_m"][2] if hit else None


def capture_kit():
    """Extract only pure primitive definitions; never execute the town builder.

    Replaying a recipe produces expected vertex positions, not bpy objects.
    The acceptance comparison below reads every actual saved mesh vertex, so a
    translated/reversed instance, missing handle, or obsolete recipe fails.
    """
    from mathutils import Vector
    path = ROOT / "tools/build_living_town.py"
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    definitions = [n for n in tree.body if isinstance(n, (ast.ClassDef, ast.FunctionDef))
                   and n.name in {"Batch", "chair", "table"}]
    if {n.name for n in definitions} != {"Batch", "chair", "table"}:
        raise ValueError("Required pure primitive definitions are missing")
    namespace = {"math": math, "Vector": Vector, "defaultdict": defaultdict}
    exec(compile(ast.Module(body=definitions, type_ignores=[]), str(path), "exec"), namespace)
    collected = {}

    class CaptureBatch(namespace["Batch"]):
        def poly(self, verts, faces, material, uvs=None):
            vertices = collected.setdefault(material, [])
            vertices.extend(world((*self.origin, self.angle), p) for p in verts)

        def flush(self, bevel=0):
            return []

    return {"Batch": CaptureBatch, "table": namespace["table"], "chair": namespace["chair"]}, collected


def vertex_pose_errors(objects, expected_by_material, frame=None, tolerance=.00025):
    """Ordered native mesh vertices are a stronger pose test than object extras."""
    actual = defaultdict(list)
    for ob in sorted(objects, key=lambda o: o.name):
        material = ob.data.materials[0].name if ob.data.materials else "MISSING"
        material = re.sub(r"\.\d{3}$", "", material.removeprefix("LT_"))
        actual[material].extend(tuple(ob.matrix_world @ v.co) for v in ob.data.vertices)
    failures = []
    maximum = 0.
    vertices = 0
    if set(actual) != set(expected_by_material):
        failures.append({"reason": "material/primitive inventory mismatch", "actual": sorted(actual),
                         "expected": sorted(expected_by_material)})
    for material, expected in expected_by_material.items():
        saved = actual.get(material, [])
        vertices += len(saved)
        if len(saved) != len(expected):
            failures.append({"reason": "saved primitive vertex count mismatch", "material": material,
                             "actual": len(saved), "expected": len(expected)})
            continue
        far = 0
        for got, wanted in zip(saved, expected):
            wanted = world(frame, wanted) if frame else wanted
            error = math.dist(got, wanted)
            maximum = max(maximum, error)
            far += error > tolerance
        if far:
            failures.append({"reason": "actual world mesh pose or primitive shape differs from plan",
                             "material": material, "mismatching_vertices": far})
    return failures, maximum, vertices


def surface_triangle_quality(objects, errors, projected_tolerance_m2=1e-10):
    """Inspect the saved renderer tessellation, rather than polygon normals.

    Land and trail tops are height fields, so backwards projected winding is
    invalid. A triangle with zero XY area may still be a real vertical surface;
    only an exactly zero world-space cross product proves 3D degeneracy here.
    calc_loop_triangles fills a transient tessellation cache, without changing
    any saved vertex, polygon, material, modifier or object transform.
    """
    records = []
    for ob in objects:
        mesh = ob.data
        points = [tuple(ob.matrix_world @ vertex.co) for vertex in mesh.vertices]
        invalid = {index for index, point in enumerate(points) if not all(math.isfinite(v) for v in point)}
        for index in sorted(invalid):
            errors.add(owner=ob.name, reason="saved surface vertex is nonfinite", vertex=index)
        try:
            mesh.calc_loop_triangles()
        except (RuntimeError, ValueError) as exc:
            errors.add(owner=ob.name, reason="saved surface tessellation failed", error=str(exc))
            continue
        negative = zero_xy = degenerate = 0
        zero_examples = []
        minimum_xy = math.inf
        for triangle in mesh.loop_triangles:
            indices = tuple(triangle.vertices)
            if any(index in invalid for index in indices):
                continue
            a, b, c = (points[index] for index in indices)
            u = tuple(b[k]-a[k] for k in range(3))
            v = tuple(c[k]-a[k] for k in range(3))
            cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
            if not all(math.isfinite(value) for value in cross):
                errors.add(owner=ob.name, reason="saved surface triangle cross product is nonfinite",
                           polygon=triangle.polygon_index, vertices=list(indices))
                continue
            xy = cross[2]
            minimum_xy = min(minimum_xy, xy/2)
            is_degenerate = all(value == 0. for value in cross)
            if xy < -projected_tolerance_m2 or abs(xy) <= projected_tolerance_m2 or is_degenerate:
                detail = {"owner": ob.name, "polygon": triangle.polygon_index, "vertices": list(indices),
                          "centroid_m": [sum(p[k] for p in (a,b,c))/3 for k in range(3)],
                          "signed_xy_area_m2": xy/2}
            if xy < -projected_tolerance_m2:
                negative += 1
                errors.add(reason="saved surface triangle has backwards XY winding", **detail)
            elif abs(xy) <= projected_tolerance_m2:
                zero_xy += 1
                if len(zero_examples) < 12:
                    zero_examples.append({**detail, "world_cross_product_m2": list(cross)})
            if is_degenerate:
                degenerate += 1
                errors.add(reason="saved surface triangle is exactly degenerate in 3D", **detail)
        records.append({"owner": ob.name, "role": ob.get("reserve_role"),
                        "triangles": len(mesh.loop_triangles), "nonfinite_vertices": len(invalid),
                        "negative_xy_triangles": negative, "zero_xy_triangles": zero_xy,
                        "exactly_degenerate_3d_triangles": degenerate,
                        "minimum_signed_xy_area_m2": minimum_xy if math.isfinite(minimum_xy) else None,
                        "zero_xy_examples": zero_examples,
                        "omitted_zero_xy_examples": max(0,zero_xy-len(zero_examples))})
    return {"objects": records, "triangles": sum(r["triangles"] for r in records),
            "negative_xy_triangles": sum(r["negative_xy_triangles"] for r in records),
            "zero_xy_triangles": sum(r["zero_xy_triangles"] for r in records),
            "exactly_degenerate_3d_triangles": sum(r["exactly_degenerate_3d_triangles"] for r in records),
            "projected_cross_product_tolerance_m2": projected_tolerance_m2,
            "zero_xy_policy": "Bounded diagnostics only unless the world-space cross product is exactly zero.",
            "scope": "Actual saved world-space land and trail-top loop triangles; no repair or evaluated geometry."}


def convex_overlap_xy(subject, clip, epsilon=1e-10):
    """Clip positively wound convex faces; shared boundaries have zero area."""
    result = [point[:2] for point in subject]
    for a,b in zip(clip,clip[1:]+clip[:1]):
        if not result:
            break
        def side(point):
            return (b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0])
        previous = result[-1]
        prior = side(previous)
        output = []
        for point in result:
            current = side(point)
            if (current >= -epsilon) != (prior >= -epsilon):
                t = prior/(prior-current)
                output.append(tuple(previous[k]+t*(point[k]-previous[k]) for k in (0,1)))
            if current >= -epsilon:
                output.append(point)
            previous,prior = point,current
        result = output
    return result


def positive_polygon_area_xy(points):
    if len(points) < 3:
        return 0.
    origin = points[0]
    # Local differences avoid cancellation for small faces at large map XY.
    return abs(sum((a[0]-origin[0])*(b[1]-origin[1])-(b[0]-origin[0])*(a[1]-origin[1])
                   for a,b in zip(points[1:-1],points[2:])))/2


def same_route_coplanar_overlaps(objects, errors, area_limit_m2=1e-5, height_tolerance_m=1e-4, cell_m=4.):
    """Find actual duplicate coverage within each route, across mesh parts.

    Only finite, convex, positive-XY faces whose vertices share a height plane
    within the stated tolerance are eligible. Nonplanar/other faces are counted
    explicitly; the separate triangle-quality gate still checks their winding.
    Different route IDs are never compared: their intentional crossings may
    have independently authored vertical separation.
    """
    groups = defaultdict(list)
    skipped = Counter()
    for ob in sorted(objects,key=lambda item:item.name):
        points = [tuple(ob.matrix_world @ vertex.co) for vertex in ob.data.vertices]
        for polygon in ob.data.polygons:
            if len(polygon.vertices) < 3:
                skipped["fewer_than_three_vertices"] += 1
                continue
            face = [points[index] for index in polygon.vertices]
            if not all(math.isfinite(value) for point in face for value in point):
                skipped["nonfinite"] += 1
                continue
            n = len(face)
            turns = [(face[(j+1)%n][0]-face[j][0])*(face[(j+2)%n][1]-face[(j+1)%n][1])
                     -(face[(j+1)%n][1]-face[j][1])*(face[(j+2)%n][0]-face[(j+1)%n][0]) for j in range(n)]
            if min(turns) < -1e-10 or max(turns) <= 1e-10:
                skipped["non_positive_convex_xy"] += 1
                continue
            corner = max(range(n),key=lambda j:turns[j])
            a,b,c = [face[(corner+j)%n] for j in range(3)]
            u,v = [b[k]-a[k] for k in range(3)],[c[k]-a[k] for k in range(3)]
            normal = (u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
            plane = (a,-normal[0]/normal[2],-normal[1]/normal[2])
            def height(point,plane=plane):
                origin,xs,ys = plane
                return origin[2]+xs*(point[0]-origin[0])+ys*(point[1]-origin[1])
            if max(abs(point[2]-height(point)) for point in face) > height_tolerance_m:
                skipped["nonplanar"] += 1
                continue
            if not ob.get("reserve_route_id"):
                skipped["missing_route_id"] += 1
                errors.add(owner=ob.name,reason="saved trail face has no route ID",polygon=polygon.index)
                continue
            bounds = (min(p[0] for p in face),min(p[1] for p in face),
                      max(p[0] for p in face),max(p[1] for p in face))
            groups[ob["reserve_route_id"]].append({"owner":ob.name,"polygon":polygon.index,
                                                   "points":face,"plane":plane,"bounds":bounds})
    records = []
    for ident,faces in sorted(groups.items()):
        grid = defaultdict(list)
        candidates = coplanar = count = 0
        area_sum = maximum_area = 0.
        for index,face in enumerate(faces):
            x0,y0,x1,y1 = face["bounds"]
            keys = [(x,y) for x in range(math.floor(x0/cell_m),math.floor(x1/cell_m)+1)
                         for y in range(math.floor(y0/cell_m),math.floor(y1/cell_m)+1)]
            nearby = {other for key in keys for other in grid[key]}
            for other in sorted(nearby):
                prior = faces[other]
                a,b,c,d = prior["bounds"]
                if min(x1,c) <= max(x0,a) or min(y1,d) <= max(y0,b):
                    continue
                candidates += 1
                def plane_height(plane,point):
                    origin,xs,ys = plane
                    return origin[2]+xs*(point[0]-origin[0])+ys*(point[1]-origin[1])
                delta = max(abs(plane_height(face["plane"],p)-plane_height(prior["plane"],p))
                            for p in face["points"]+prior["points"])
                if delta > height_tolerance_m:
                    continue
                coplanar += 1
                intersection = convex_overlap_xy(face["points"],prior["points"])
                area = positive_polygon_area_xy(intersection)
                if area <= area_limit_m2:
                    continue
                count += 1
                area_sum += area
                maximum_area = max(maximum_area,area)
                errors.add(route=ident,reason="saved same-route coplanar faces overlap with positive area",
                           owners=[prior["owner"],face["owner"]],polygons=[prior["polygon"],face["polygon"]],
                           overlap_area_m2=area,maximum_height_plane_difference_m=delta,
                           overlap_center_xy_m=[sum(p[k] for p in intersection)/len(intersection) for k in (0,1)])
            for key in keys:
                grid[key].append(index)
        records.append({"route":ident,"eligible_faces":len(faces),"bbox_candidate_pairs":candidates,
                        "coplanar_candidate_pairs":coplanar,"positive_area_overlap_pairs":count,
                        "sum_pairwise_overlap_area_m2":area_sum,"maximum_overlap_area_m2":maximum_area})
    return {"routes":records,"eligible_faces":sum(r["eligible_faces"] for r in records),
            "positive_area_overlap_pairs":sum(r["positive_area_overlap_pairs"] for r in records),
            "sum_pairwise_overlap_area_m2":sum(r["sum_pairwise_overlap_area_m2"] for r in records),
            "skipped_faces":dict(skipped),"area_acceptance_limit_m2":area_limit_m2,
            "height_plane_tolerance_m":height_tolerance_m,"spatial_grid_cell_m":cell_m,
            "scope":"Saved whole convex positive-XY planar faces, same route only; pairwise area is not union area."}


def facade_cover_ownership(amenities, meshes, collections, errors):
    """Inspect saved links for complete local facade cutaways, not labels alone."""
    attachment_names = set()
    unit_records = []
    for amenity in amenities:
        ident = amenity["id"]
        building = collections.get(ident)
        front = collections.get(ident+"_FrontCover")
        site = collections.get(ident+"_Site_Utilities")
        prefix = ident+"_Facade_Attachments_"
        attachments = [ob for ob in meshes if ob.name.startswith(prefix)]
        attachment_names.update(ob.name for ob in attachments)
        if building is None or front is None or site is None:
            errors.add(owner=ident, reason="actual facade/unit/site collection missing")
        elif front.name not in building.children or site.name not in building.children:
            errors.add(owner=ident, reason="actual facade/site collection is not owned by its building")
        if not attachments:
            errors.add(owner=ident, reason="saved facade attachment meshes absent", expected_prefix=prefix)
        ground = [ob for ob in site.all_objects if ob.type == "MESH"
                  and ob.get("reserve_building_id") == ident
                  and ob.get("reserve_role") == "visitor_entry_steps_signs_and_site_utilities"] if site else []
        if not ground:
            errors.add(owner=ident, reason="actual ground utility subtree empty")
        for ob in attachments:
            links = list(ob.users_collection)
            if (front is None or ob.name not in front.objects or len(links) != 1 or links[0] != front
                    or ob.get("reserve_building_id") != ident or ob.get("reserve_role") != "front_cover"):
                errors.add(owner=ob.name, reason="saved facade attachment has wrong owner/role/collection links",
                           actual_collections=[c.name for c in links], expected_collection=ident+"_FrontCover",
                           actual_building=ob.get("reserve_building_id"), actual_role=ob.get("reserve_role"))
            if site is not None and ob.name in site.all_objects:
                errors.add(owner=ob.name, reason="facade attachment remains in actual site utility subtree")
            parent = ob.parent
            while parent is not None:
                parent_links = list(parent.users_collection)
                if (parent.get("reserve_building_id") not in (None, ident)
                        or not parent_links or any(c not in (front, building) for c in parent_links)):
                    errors.add(owner=ob.name, reason="facade attachment parent belongs outside its facade/building",
                               actual_parent=parent.name, parent_collections=[c.name for c in parent_links])
                    break
                parent = parent.parent
        unit_records.append({"building":ident, "facade_attachment_meshes":len(attachments),
                             "ground_utility_meshes":len(ground)})
    orphaned = [ob.name for ob in meshes if "_Facade_Attachments_" in ob.name and ob.name not in attachment_names]
    for name in orphaned:
        errors.add(owner=name, reason="saved facade attachment has no planned building owner")
    return {"buildings":len(unit_records), "facade_attachment_meshes":len(attachment_names),
            "ground_utility_meshes":sum(r["ground_utility_meshes"] for r in unit_records),
            "units":unit_records, "orphan_attachment_meshes":len(orphaned),
            "scope":"Actual saved mesh collection links, building collection children, object-parent ownership and ground utility presence."}


def stair_land_clearance(queries, stair, stair_objects, land, paths, trail_surfaces, errors,
                         penetration_tolerance_m=.02, head_clearance_m=2.):
    """Exclude actual saved terrain and low trail overlays from stair envelopes.

    A valid stair-only ray does not imply a usable stair: the land may bury it.
    Top-down land controls catch even terrain above the entire head band;
    within-cell body rays catch narrow banks between those vertical controls.
    Trail sheets above the walking plane inside the head band also obstruct it.
    This is not an all-scene collision check or certified-access claim.
    """
    vertical_columns = body_rays = cells = approaches = 0
    maximum_intrusion = -math.inf
    trail_columns = 0
    maximum_blocking_trail_height = None
    worst = None
    def span(a, b, surface_z, surface_objects, width, region, label, stations):
        nonlocal vertical_columns, body_rays, cells, maximum_intrusion, worst, trail_columns, maximum_blocking_trail_height
        length = math.dist(a[:2], b[:2])
        if length <= .0001 or width <= .10:
            errors.add(stair=stair["id"], region=region, owner=label, reason="invalid walking envelope")
            return
        cells += 1
        ux, uy = (b[0]-a[0])/length, (b[1]-a[1])/length
        nx, ny = -uy, ux
        half = width/2
        laterals = (-half+.05, -half*.5, 0., half*.5, half-.05)
        rows = []
        for t in stations:
            p = interpolate(a, b, t)
            row = []
            expected = surface_z if surface_z is not None else p[2]
            for lateral in laterals:
                x, y = p[0]+nx*lateral, p[1]+ny*lateral
                actual = queries.down(surface_objects, x, y, expected+.50, expected-.60)
                row.append((x, y, actual))
                vertical_columns += 1
                if actual is None:
                    errors.add(stair=stair["id"], region=region, owner=label,
                               reason="actual walking surface absent in land-clearance envelope", xy_m=[x,y])
                    continue
                # Start strictly above the measured walking surface. The
                # approach trail's own surface is therefore never a blocker;
                # a path crossing higher treads at chest height remains one.
                trail_columns += 1
                overhead = queries.ray(trail_surfaces,(x,y,actual+penetration_tolerance_m+1e-6),
                                       (0,0,1),head_clearance_m-penetration_tolerance_m-2e-6)
                if overhead:
                    delta=overhead["point_m"][2]-actual
                    maximum_blocking_trail_height=max(maximum_blocking_trail_height or 0.,delta)
                    errors.add(stair=stair["id"],region=region,owner=label,
                               reason="actual trail surface occludes stair walking/head-clearance band",
                               xy_m=[x,y],walking_z_m=actual,trail_height_above_walking_m=delta,hit=overhead)
                ground = queries.down(land, x, y, max(180.,actual+10.), min(-20.,actual-100.))
                if ground is None:
                    errors.add(stair=stair["id"], region=region, owner=label,
                               reason="actual supporting land absent beneath walking envelope", xy_m=[x,y])
                    continue
                intrusion = ground-actual
                if intrusion > maximum_intrusion:
                    maximum_intrusion = intrusion
                    worst = {"region":region,"owner":label,"xy_m":[x,y],
                             "walking_z_m":actual,"land_z_m":ground}
                if intrusion > penetration_tolerance_m:
                    errors.add(stair=stair["id"], region=region, owner=label,
                               reason="saved land occludes stair/landing/approach walking plane",
                               xy_m=[x,y], walking_z_m=actual, land_z_m=ground, intrusion_m=intrusion)
            rows.append(row)
            # Stay inside this tread/landing cell: a whole-flight horizontal
            # ray would wrongly classify legitimate future rising treads.
            if row[2][2] is not None:
                for height in (.20, 1., head_clearance_m-.10):
                    start=(row[0][0],row[0][1],row[2][2]+height)
                    hit=queries.ray(land,start,(nx,ny,0),width-.10)
                    body_rays += 1
                    if hit:
                        errors.add(stair=stair["id"],region=region,owner=label,
                                   reason="saved land crosses lateral walking/head-clearance band",
                                   height_above_walking_m=height,hit=hit)
        if len(rows)>1:
            for j in range(len(laterals)):
                first,last=rows[0][j],rows[-1][j]
                if first[2] is None or last[2] is None:
                    continue
                for height in (.20,1.,head_clearance_m-.10):
                    start=(first[0],first[1],min(first[2],last[2])+height)
                    hit=queries.ray(land,start,(ux,uy,0),length*(stations[-1]-stations[0]))
                    body_rays += 1
                    if hit:
                        errors.add(stair=stair["id"],region=region,owner=label,
                                   reason="saved land crosses longitudinal walking/head-clearance band",
                                   height_above_walking_m=height,hit=hit)
    for flight in stair.get("flights",[]):
        a,b=flight["points_m"];count=flight["step_count"]
        for j in range(count):
            aa,bb=interpolate(a,b,j/count),interpolate(a,b,(j+1)/count)
            top=a[2]+(b[2]-a[2])*((j+1)/count if b[2]>=a[2] else j/count)
            span(aa,bb,top,stair_objects,stair["width_m"],"tread",flight["id"]+":"+str(j),(.04,.5,.96))
    for index,landing in enumerate(stair.get("landings",[])):
        a,b=landing["points_m"];count=max(2,math.ceil(math.dist(a[:2],b[:2])/.12))
        span(a,b,a[2],stair_objects,stair["width_m"],"landing",str(index),
             tuple(.02+.96*j/count for j in range(count+1)))
    for endpoint in stair["points_m"]:
        matches=[]
        for path in paths:
            if path.get("kind") in ("stairs","bridge"):
                continue
            points=path["points_m"]
            for first,second in ((points[0],points[1]),(points[-1],points[-2])):
                if math.dist(endpoint,first)<.002:
                    matches.append((path,first,second))
        if not matches:
            errors.add(stair=stair["id"],reason="no authored endpoint approach for actual land-clearance check",
                       endpoint_m=endpoint)
        for path,a,b in matches:
            fraction=min(1.,.75/max(math.dist(a[:2],b[:2]),.0001));b=interpolate(a,b,fraction)
            surfaces=[ob for ob in trail_surfaces if ob.get("reserve_route_id")==path["id"]]
            span(a,b,None,surfaces,min(stair["width_m"],path["width_m"]),"approach",path["id"],
                 (.04,.25,.5,.75,.96))
            approaches += 1
    return {"id":stair["id"],"walking_cells":cells,"endpoint_approaches":approaches,
            "actual_walking_and_land_columns":vertical_columns,"within_cell_body_rays":body_rays,
            "actual_overhead_trail_columns":trail_columns,
            "maximum_blocking_trail_height_above_walking_m":maximum_blocking_trail_height,
            "maximum_land_above_walking_m":maximum_intrusion if math.isfinite(maximum_intrusion) else None,
            "worst_land_control":worst,"walking_edge_inset_m":.05,
            "land_penetration_tolerance_m":penetration_tolerance_m,"head_band_m":head_clearance_m,
            "scope":"Saved land top must stay below actual walking plane plus tolerance, including edges; within-cell land body rays test .20,1.0,1.9m. Actual trail sheets strictly above the tolerance and below2m fail; approach self surfaces and overhead paths beyond2m are excluded."}


def partition_probes(queries, objects, frame, floor, partitions, errors, owner):
    apertures = solids = 0
    for wall in partitions:
        axis, coordinate = wall["axis"], wall["coordinate_m"]
        lo, hi = wall["span_m"]
        def cross(position, z):
            start = (coordinate - .23, position, floor + z) if axis == "x" else (position, coordinate - .23, floor + z)
            dx, dy = rotate(1 if axis == "x" else 0, 1 if axis == "y" else 0, frame[3])
            return queries.ray(objects, world(frame, start), (dx, dy, 0), .46)
        holes = wall["openings"]
        for opening in holes:
            apertures += 1
            center = opening["center_m"]
            hit = cross(center, opening.get("bottom_m", 0) + opening["height_m"] * .5)
            control = cross(center, wall["height_m"] - .045)
            solids += 1
            if hit or control is None:
                errors.add(owner=owner, reason="actual aperture or lintel control failed", axis=axis,
                           coordinate_m=coordinate, opening=center, aperture_hit=hit, lintel_hit=control)
        # Sample all solid spans, not only a lintel above an opening.
        edges = [lo, hi]
        edges.extend(o["center_m"] + side * o["width_m"] / 2 for o in holes for side in (-1, 1))
        for a, b in zip(sorted(edges), sorted(edges)[1:]):
            middle = (a + b) / 2
            if b - a < .08 or any(abs(middle-o["center_m"]) < o["width_m"]/2 for o in holes):
                continue
            solids += 1
            if cross(middle, 1.20) is None:
                errors.add(owner=owner, reason="actual solid partition span missing", axis=axis,
                           coordinate_m=coordinate, station_m=middle)
    return apertures, solids


def clearance_probes(queries, objects, frame, ff, points, errors, owner):
    """Body rays at authored usable fronts; no nearest-free relocation."""
    for x, y in points:
        hit = queries.ray(objects, world(frame, (x, y, ff + .16)), (0, 0, 1), 1.54)
        if hit:
            errors.add(owner=owner, reason="saved mesh obstructs reserved body column",
                       local_xy_m=[x, y], hit=hit)
    return len(points)


def measured_route_grade(queries, path, segments, surface_sets, land, errors,
                         spacing=1., numerical_margin=.0005):
    """Measure saved surface normals and height intervals, never planned Z.

    Each surface set corresponds to one authored ground segment. Native mesh
    normals expose a steep short triangle even when a one-metre height interval
    would average it away. Missing reused paving fails even when native ground
    is available for diagnostic heights and normals.
    """
    limit = path.get("grade_limit")
    longitudinal = interval_grade = ground_longitudinal = crossfall = 0.
    maximum_station = None
    samples = intervals = ground_only_reuse = 0
    reused_surfaces = Counter()
    if limit is None:
        errors.add(route=path["id"], reason="ground route has no authored grade limit")
    for segment_index, (segment, surfaces) in enumerate(zip(segments, surface_sets)):
        previous = None
        station = 0.
        points = segment["points_m"]
        for a,b in zip(points,points[1:]):
            length = math.dist(a[:2],b[:2])
            if length < .00001:
                continue
            ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
            count=math.ceil(length/spacing)
            for i in range(count+1):
                # Enter the actual ribbon by 0.1mm at open boundaries; this
                # avoids a floating-point border miss, not a spatial search.
                inset=min(.0001,length*.10)/length
                t=max(inset,min(1-inset,i/count))
                p=interpolate(a,b,t)
                here=station+length*t
                if previous is not None and here-previous[0] < .00005:
                    continue
                hit=queries.ray(surfaces,(p[0],p[1],180),(0,0,-1),200)
                ground=queries.ray(land,(p[0],p[1],180),(0,0,-1),200)
                if hit is None and segment.get("core_reuse"):
                    errors.add(route=path["id"],segment=segment_index,station_m=here,
                               reason="actual reused paving absent",xy_m=list(p[:2]),
                               diagnostic_ground_object=ground["object"] if ground else None,
                               diagnostic_ground_point_m=ground["point_m"] if ground else None)
                    hit=ground
                    ground_only_reuse+=1
                samples+=1
                if hit is None:
                    errors.add(route=path["id"],segment=segment_index,station_m=here,
                               reason="actual graded route surface absent",xy_m=list(p[:2]))
                    previous=None
                    continue
                reused_surfaces[hit["object"]]+=1
                normal=hit["normal_world"]
                slope=abs(normal[0]*ux+normal[1]*uy)/max(abs(normal[2]),1e-12)
                if slope > longitudinal:
                    longitudinal=slope
                    maximum_station={"segment":segment_index,"station_m":here,"xy_m":list(p[:2]),
                                     "native_object":hit["object"],"native_polygon":hit["polygon"],
                                     "normal_world":normal}
                if limit is not None and slope > limit+numerical_margin:
                    errors.add(route=path["id"],segment=segment_index,station_m=here,xy_m=list(p[:2]),
                               reason="actual surface triangle exceeds longitudinal grade limit",
                               actual_grade=slope,declared_limit=limit,numerical_margin=numerical_margin,
                               native_object=hit["object"],native_polygon=hit["polygon"])
                if ground is not None:
                    n=ground["normal_world"]
                    ground_longitudinal=max(ground_longitudinal,abs(n[0]*ux+n[1]*uy)/max(abs(n[2]),1e-12))
                if previous is not None and here-previous[0] >= .01:
                    measured=abs(hit["point_m"][2]-previous[1])/(here-previous[0])
                    interval_grade=max(interval_grade,measured)
                    intervals+=1
                    if limit is not None and measured > limit+numerical_margin:
                        errors.add(route=path["id"],segment=segment_index,station_m=here,
                                   reason="actual surface height interval exceeds longitudinal grade limit",
                                   actual_grade=measured,declared_limit=limit,numerical_margin=numerical_margin,
                                   interval_length_m=here-previous[0],xy_m=list(p[:2]))
                previous=(here,hit["point_m"][2])
                # Crossfall is evidence only: the plan presently specifies no
                # crossfall cap. Do not invent one or call it certified access.
                crossfall=max(crossfall,abs(normal[0]*(-uy)+normal[1]*ux)/max(abs(normal[2]),1e-12))
            station+=length
    return {"id":path["id"],"kind":path["kind"],"declared_longitudinal_grade_limit":limit,
            "maximum_native_surface_longitudinal_triangle_grade":longitudinal,
            "maximum_native_surface_height_interval_grade":interval_grade,
            "maximum_native_land_longitudinal_triangle_grade":ground_longitudinal,
            "maximum_native_surface_crossfall_grade":crossfall,
            "maximum_longitudinal_station":maximum_station,
            "sample_spacing_maximum_m":spacing,"surface_samples":samples,"height_intervals":intervals,
            "numerical_grade_margin":numerical_margin,"surface_object_samples":dict(reused_surfaces),
            "unpaved_core_reuse_samples":ground_only_reuse,
            "crossfall_policy":"Measured for review; no authored acceptance limit currently exists."}


def run():
    import bpy
    scene = bpy.data.scenes.get("Living_Town_Summer")
    if scene is None:
        raise ValueError("Open the saved Living_Town_Summer scene before running this audit")
    objects = list(scene.objects)
    meshes = [o for o in objects if o.type == "MESH"]
    by_name = {o.name: o for o in objects}
    plan = json.loads((ROOT / "reserve_plan.json").read_text(encoding="utf-8"))
    core = json.loads((ROOT / "interior_plan.json").read_text(encoding="utf-8"))
    manifest = json.loads((ROOT / "town_manifest.json").read_text(encoding="utf-8"))
    master = json.loads((ROOT / "masterplan.json").read_text(encoding="utf-8"))
    terrain = json.loads((ROOT / "terrain_plan.json").read_text(encoding="utf-8"))
    amenity_module = load_module("reserve_audit_amenity_planner", ROOT / "tools/reserve_amenities.py")
    amenities = amenity_module.plan_reserve(plan)
    queries = MeshQueries()
    checks = []
    def check(ident, passed, detail):
        checks.append({"id": ident, "status": "PASS" if passed else "FAIL", "detail": detail})

    binding_files = {
        "masterplan_sha256": "masterplan.json", "terrain_plan_sha256": "terrain_plan.json",
        "landscape_plan_sha256": "landscape_plan.json", "terrain_profile_sha256": "tools/terrain_profile.py",
        "interior_plan_sha256": "interior_plan.json", "interior_module_sha256": "tools/interior_design.py",
        "reserve_plan_sha256": "reserve_plan.json", "reserve_plan_module_sha256": "tools/reserve_plan.py",
        "reserve_environment_module_sha256": "tools/reserve_environment.py",
        "reserve_amenities_module_sha256": "tools/reserve_amenities.py"}
    bindings = {key: sha256(ROOT / path) for key, path in binding_files.items()}
    binding_errors = Findings()
    for key, value in bindings.items():
        if manifest.get(key) != value:
            binding_errors.add(key=key, owner="manifest", expected=value, actual=manifest.get(key))
        if scene.get(key) != value:
            binding_errors.add(key=key, owner="scene", expected=value, actual=scene.get(key))
    check("saved_sources_bound_to_current_plans_and_modules", not binding_errors.count,
          binding_errors.detail(bindings=bindings))

    land = [by_name["Atlantic_Terrain_Grass"]] if "Atlantic_Terrain_Grass" in by_name else []
    check("one_active_continuous_land_mesh", len(land) == 1 and land[0].get("reserve_role") == "terrain"
          and len(land[0].data.polygons) > 20000,
          {"active_land": [o.name for o in land], "polygons": len(land[0].data.polygons) if land else 0,
           "archive_scene_objects": [o.name for o in objects if o.name.startswith("Archive_PreReserve_Land")]})

    surface_quality_errors = Findings()
    trail_surfaces = [ob for ob in meshes if ob.get("reserve_role") == "trail"]
    surface_quality = surface_triangle_quality(land+trail_surfaces, surface_quality_errors)
    check("actual_saved_land_and_trail_triangle_quality", bool(land) and bool(trail_surfaces)
          and surface_quality["triangles"] > 0 and not surface_quality_errors.count,
          surface_quality_errors.detail(**surface_quality))
    overlap_errors = Findings(limit=24)
    overlaps = same_route_coplanar_overlaps(trail_surfaces,overlap_errors)
    check("actual_saved_same_route_coplanar_overlap_absent", overlaps["eligible_faces"] > 0 and not overlap_errors.count,
          overlap_errors.detail(**overlaps))

    core_errors = Findings()
    core_measurements = []
    old_land = bpy.data.objects.get("Archive_PreReserve_Land_NotExported")
    core_rect = plan["terrain"]["core_preserve_rect_xyxy_m"]
    # Exact saved original surface is the control; analytic design labels alone
    # cannot prove preservation through a replacement/remeshing operation.
    if old_land is None:
        core_errors.add(reason="saved original land control mesh is absent")
    else:
        for x in range(-70, 66, 5):
            for y in range(-60, 61, 5):
                old = queries.down([old_land], x, y)
                new = queries.down(land, x, y)
                if old is None:
                    continue  # water/quay holes are checked by the core audit
                delta = None if new is None else abs(old - new)
                core_measurements.append(delta)
                # 0.6m remeshing of the fixed height field has a small finite
                # interpolation difference; 5cm is the explicit audit budget.
                if delta is None or delta > .05:
                    core_errors.add(reason="core saved land differs from original", xy_m=[x, y],
                                    old_z_m=old, new_z_m=new, tolerance_m=.05)
    pads = {p["id"]: p for p in terrain["building_pads"]}
    master_buildings = {b["id"]: b for b in master["buildings"]}
    records = {b["id"]: b for b in manifest["buildings"]}
    if len(records) != 49 or set(records) != set(master_buildings):
        core_errors.add(reason="frozen 49-building inventory changed")
    for ident, b in records.items():
        source = master_buildings.get(ident)
        if source is None:
            continue
        expected = (*source["center"][:2], pads[ident]["pad_base_z_m"])
        if math.dist(b["center_m"], expected) > .0001:
            core_errors.add(owner=ident, reason="building center/pad differs from frozen masterplan")
        anchor = by_name.get(ident + "_Anchor")
        if b["kind"] != "halles" and (anchor is None or math.dist(anchor.matrix_world.translation, expected) > .0001):
            core_errors.add(owner=ident, reason="actual building anchor moved or missing")
        if anchor is not None:
            forward = anchor.matrix_world.to_3x3() @ queries.Vector((1, 0, 0))
            expected_forward = queries.Vector((*rotate(1, 0, math.radians(b["yaw_degrees"])), 0))
            if (forward.normalized()-expected_forward).length > .0001:
                core_errors.add(owner=ident, reason="actual building anchor yaw differs from frozen pose")
    check("frozen_core_terrain_and_49_building_poses", not core_errors.count,
          core_errors.detail(surface_controls=len(core_measurements),
                             maximum_surface_difference_m=max((v for v in core_measurements if v is not None), default=None),
                             allowed_interpolation_difference_m=.05, buildings=len(records)))

    trees = defaultdict(list)
    tree_mesh_species = {}
    malformed = []
    for ob in meshes:
        if ob.get("reserve_role") == "tree":
            match = re.match(r"Reserve_Tree_(\d+)_([a-z_]+)_\d+$", ob.name)
            if match:
                trees[match[1]].append(ob)
                tree_mesh_species[match[1]]=match[2]
            else:
                malformed.append(ob.name)
    tree_errors = Findings()
    zone_counts, species_counts, geometry_species, lods = Counter(), Counter(), Counter(), Counter()
    base_errors = []
    prototype_meshes = set()
    species_mesh_signatures=defaultdict(set)
    species_geometry_mapping=defaultdict(set)
    mesh_signatures={}
    zone_plans = {z["id"]: z for z in plan["forest_zones"]}
    route_index = defaultdict(list)
    for path in plan["paths"]:
        radius = path["width_m"]/2+.25
        for a, b in zip(path["points_m"], path["points_m"][1:]):
            for ix in range(math.floor((min(a[0],b[0])-radius)/16), math.floor((max(a[0],b[0])+radius)/16)+1):
                for iy in range(math.floor((min(a[1],b[1])-radius)/16), math.floor((max(a[1],b[1])+radius)/16)+1):
                    route_index[ix,iy].append((a,b,radius,path["id"]))
    for ident, parts in trees.items():
        ob = parts[0]
        origin = ob.matrix_world.translation
        x, y = origin.x, origin.y
        minimum = min((p.matrix_world @ v.co).z for p in parts for v in p.data.vertices)
        ground = queries.down(land, x, y)
        delta = None if ground is None else minimum - ground
        base_errors.append(delta)
        # A root may penetrate 5cm; a 3cm air gap is visible and fails. This
        # measures the saved land, not the analytic height used by the builder.
        if delta is None or not -.05 <= delta <= .03:
            tree_errors.add(tree=ident, reason="root does not contact actual saved land", xy_m=[x, y],
                            root_z_m=minimum, native_ground_z_m=ground, root_minus_ground_m=delta)
        if any(math.dist(p.matrix_world.translation, origin) > .0001 for p in parts):
            tree_errors.add(tree=ident, reason="tree material parts have separated origins")
        if any(max(abs(p.matrix_world[r][c]-ob.matrix_world[r][c]) for r in range(4) for c in range(4)) > .0001 for p in parts):
            tree_errors.add(tree=ident, reason="tree material parts have inconsistent physical scale/yaw")
        zone, species = ob.get("reserve_zone"), ob.get("tree_species")
        zone_counts[zone] += 1
        species_counts[species] += 1
        geometry_species[tree_mesh_species[ident]] += 1
        species_geometry_mapping[species].add(tree_mesh_species[ident])
        lods[ob.get("lod")] += 1
        for part in parts:
            prototype_meshes.add(part.data.as_pointer())
            if part.data.users < 2:
                tree_errors.add(tree=ident, reason="tree geometry is not shared/linked", object=part.name)
        # Shape signatures are derived from mesh coordinates/topology, not
        # species labels or datablock names. Reuse them for linked instances.
        part_signatures=[]
        for part in parts:
            pointer=part.data.as_pointer()
            if pointer not in mesh_signatures:
                digest=hashlib.sha256()
                for vertex in part.data.vertices:
                    digest.update((",".join(f"{v:.6f}" for v in vertex.co)+";").encode())
                for polygon in part.data.polygons:
                    digest.update((",".join(str(v) for v in polygon.vertices)+";").encode())
                mesh_signatures[pointer]=digest.hexdigest()
            part_signatures.append(mesh_signatures[pointer])
        signature=hashlib.sha256("|".join(sorted(part_signatures)).encode()).hexdigest()
        species_mesh_signatures[tree_mesh_species[ident]].add(signature)
        if zone not in zone_plans or not inside_polygon(x, y, zone_plans[zone]["polygon_xy"]):
            tree_errors.add(tree=ident, reason="tree outside its woodland zone", zone=zone)
        if core_rect[0]-2 < x < core_rect[2]+2 and core_rect[1]-2 < y < core_rect[3]+2:
            tree_errors.add(tree=ident, reason="reserve tree intrudes on frozen core")
        for clearing in plan["clearings"]:
            if clearing_contains(x, y, clearing):
                tree_errors.add(tree=ident, reason="tree intrudes on authored clearing", clearing=clearing["id"])
        for a,b,radius,route in route_index[math.floor(x/16),math.floor(y/16)]:
            if point_segment_distance(x,y,a,b) < radius:
                tree_errors.add(tree=ident, reason="actual tree trunk obstructs reserved route width", route=route)
                break
    target = sum(z["target_tree_count"] for z in plan["forest_zones"])
    for ident, zone in zone_plans.items():
        if zone_counts[ident] != zone["target_tree_count"]:
            tree_errors.add(zone=ident, expected=zone["target_tree_count"], actual=zone_counts[ident])
    check("3500_linked_grounded_trees_and_preserved_clearings", len(trees) == target == 3500
          and not malformed and not tree_errors.count and len(geometry_species) >= 5
          and len(set().union(*species_mesh_signatures.values())) >= 5 and set(lods) == {"near", "far"},
          tree_errors.detail(tree_assemblies=len(trees), material_objects=sum(map(len, trees.values())),
                             species_labels=dict(species_counts), actual_mesh_species=dict(geometry_species),
                             lod_instances=dict(lods), zone_instances=dict(zone_counts), shared_mesh_datablocks=len(prototype_meshes),
                             species_geometry_mapping={k:sorted(v) for k,v in species_geometry_mapping.items()},
                             actual_mesh_shape_signatures={k:sorted(v) for k,v in species_mesh_signatures.items()},
                             root_contact_range_m=[min((v for v in base_errors if v is not None), default=None),
                                                   max((v for v in base_errors if v is not None), default=None)], malformed=malformed,
                             limits="Species labels, prototype names, and actual coordinate/topology shape diversity are reported separately."))

    trail_errors = Findings()
    trail_samples = 0
    trail_deltas = []
    quay_support_samples = 0
    quay_support = [o for o in meshes if o.name.startswith("Connected_Streets_and_Pavements_Paving")]
    for path in plan["paths"]:
        if path["kind"] in {"bridge", "stairs"}:
            continue
        trail_objects = [o for o in meshes if o.get("reserve_role") == "trail" and o.get("reserve_route_id") == path["id"]]
        segments = path.get("segments", [{"kind": "ground", "points_m": path["points_m"]}])
        ground_segments = [s for s in segments if s.get("kind") not in {"bridge", "stairs"} and not s.get("core_reuse")]
        if ground_segments and not trail_objects:
            trail_errors.add(route=path["id"], reason="actual trail mesh missing")
        for segment in ground_segments:
            points = segment["points_m"]
            # Centerline and both shoulders every ~6m. Skip endpoints shared
            # by joins; their miter construction is tested by adjacent samples.
            traversed = 0.
            for a, b in zip(points, points[1:]):
                length = math.dist(a[:2], b[:2])
                traversed += length
                if traversed < 6 and b != points[-1]:
                    continue
                traversed = 0
                if length < .001:
                    continue
                center = interpolate(a, b, .43)
                nx, ny = -(b[1]-a[1])/length, (b[0]-a[0])/length
                for offset in (-path["width_m"]*.30, 0, path["width_m"]*.30):
                    x, y = center[0]+nx*offset, center[1]+ny*offset
                    surface = queries.down(trail_objects, x, y)
                    ground = queries.down(land, x, y)
                    # The preserved harbor has an intentional grass opening.
                    # Its actual engineered quay paving is the ground support,
                    # strictly inside that known aperture and only if land is
                    # absent. No analytic height or nearest-surface search.
                    if ground is None and 31 < x < 66 and 37 < y < 55:
                        ground = queries.down(quay_support, x, y)
                        if ground is not None:
                            quay_support_samples += 1
                    delta = None if ground is None or surface is None else surface-ground
                    trail_samples += 1
                    trail_deltas.append(delta)
                    if delta is None or not -.012 <= delta <= .12:
                        trail_errors.add(route=path["id"], reason="trail buried, floating, or absent on actual land/quay support",
                                         xy_m=[x, y], trail_z_m=surface, native_ground_z_m=ground, delta_m=delta)
    check("actual_trail_center_and_shoulder_contacts", trail_samples > 100 and not trail_errors.count,
          trail_errors.detail(surface_rays=trail_samples, preserved_quay_paving_support_samples=quay_support_samples,
                              quay_fallback_domain_xyxy_m=[31,37,66,55],
                              quay_fallback_policy="Only absent land inside the preserved harbor aperture; actual saved paving mesh rays required.",
                              contact_range_m=[min((v for v in trail_deltas if v is not None), default=None),
                                                                          max((v for v in trail_deltas if v is not None), default=None)],
                              allowed_surface_above_ground_m=[-.012, .12], expected_nominal_overlay_m=.045))

    grade_errors=Findings()
    route_grades=[]
    existing_walk_surfaces=[o for o in meshes if o.name.startswith(
        ("Connected_Streets_and_Pavements_Paving","Reference_Garden_Paths_"))]
    for path in plan["paths"]:
        if path["kind"] in {"bridge","stairs"}:
            continue
        segments=[s for s in path.get("segments",[{"kind":"ground","points_m":path["points_m"]}])
                  if s.get("kind") not in {"bridge","stairs"}]
        route_meshes=[o for o in meshes if o.get("reserve_role")=="trail" and o.get("reserve_route_id")==path["id"]]
        surface_sets=[existing_walk_surfaces if s.get("core_reuse") else route_meshes for s in segments]
        route_grades.append(measured_route_grade(queries,path,segments,surface_sets,land,grade_errors))
    loop_grades=[p for p in route_grades if p["kind"]=="jogging_belt"]
    check("actual_running_loop_and_ground_route_surface_grades", len(loop_grades)==1 and not grade_errors.count,
          grade_errors.detail(running_loop=loop_grades[0] if loop_grades else None,
                              ground_routes=route_grades,
                              method="Actual saved BVH triangle normals and world-space height intervals at <=1m; authored point Z and analytic validation are not used.",
                              numerical_grade_margin=.0005))

    retaining_errors = Findings()
    retaining_measurements = []
    for edge in plan.get("site_earthworks", {}).get("retaining_edges", []):
        group = [o for o in meshes if o.get("reserve_structure_id") == edge["id"] and o.get("reserve_role") == "retaining_wall"]
        a,b = edge["points_m"]
        length = math.dist(a[:2],b[:2])
        nx,ny = -(b[1]-a[1])/length,(b[0]-a[0])/length
        upper,lower = edge["upper_level_m"],edge["lower_level_m"]
        stations = []
        for t in (.25,.75):
            p = interpolate(a,b,t)
            cap = queries.down(group,p[0],p[1],upper+.30,upper-.10)
            if cap is None or abs(cap-(upper+.10)) > .004:
                retaining_errors.add(owner=edge["id"],reason="actual retaining cap missing/wrong height",station=t,actual_z_m=cap)
            banks=[]
            for side in (-1,1):
                offset=side*(edge["thickness_m"]/2+.05)
                banks.append(queries.down(land,p[0]+nx*offset,p[1]+ny*offset))
            if any(z is None for z in banks) or abs(min(z for z in banks if z is not None)-lower) > .20 or abs(max(z for z in banks if z is not None)-upper) > .20:
                retaining_errors.add(owner=edge["id"],reason="actual lower/upper banks do not contact retaining shoulders",station=t,
                                     native_bank_z_m=banks,expected_lower_m=lower,expected_upper_m=upper)
            rail = queries.down(group,p[0],p[1],upper+1.30,upper+1.10)
            if rail is None:
                retaining_errors.add(owner=edge["id"],reason="actual upper retaining guardrail absent",station=t)
            stations.append({"station":t,"cap_z_m":cap,"side_native_ground_z_m":banks,"guardrail_z_m":rail})
        retaining_measurements.append({"id":edge["id"],"actual_surface_controls":stations})
    check("actual_retaining_caps_guardrails_and_both_bank_contacts", bool(retaining_measurements) and not retaining_errors.count,
          retaining_errors.detail(edges=retaining_measurements,bank_contact_tolerance_m=.20))

    bridge_errors = Findings()
    bridge_measurements = []
    for bridge in plan["bridges"]:
        group = [o for o in meshes if o.get("reserve_bridge_id") == bridge["id"]]
        a, b = bridge["points_m"]
        length = math.dist(a[:2], b[:2])
        ux, uy = (b[0]-a[0])/length, (b[1]-a[1])/length
        nx, ny = -uy, ux
        width = bridge["width_m"]
        count = math.ceil(length/.25)
        deck_errors = []
        for j in range(count):
            p = interpolate(a, b, (j+.5)/count)
            for side in (-.30, 0, .30):
                x, y = p[0]+nx*width*side, p[1]+ny*width*side
                actual = queries.down(group, x, y, p[2]+.20, p[2]-.40)
                if actual is None or abs(actual-p[2]) > .002:
                    deck_errors.append({"plank": j, "offset": side, "actual_z_m": actual, "expected_z_m": p[2]})
        if deck_errors:
            bridge_errors.add(bridge=bridge["id"], reason="deck plank surfaces differ", examples=deck_errors[:12], count=len(deck_errors))
        landings = []
        for endpoint, direction in ((a, -1), (b, 1)):
            # Contact at the abutment's outer edge, with all three deck-width
            # stations. A declared endpoint alone cannot prove a landing.
            for lateral in (-width*.30, 0, width*.30):
                x = endpoint[0]+ux*direction*.60+nx*lateral
                y = endpoint[1]+uy*direction*.60+ny*lateral
                ground = queries.down(land, x, y)
                error = None if ground is None else ground-endpoint[2]
                landings.append({"xy_m": [x, y], "deck_z_m": endpoint[2], "ground_z_m": ground, "difference_m": error})
                if error is None or abs(error) > .15:
                    bridge_errors.add(bridge=bridge["id"], reason="bridge landing lacks actual graded ground contact", **landings[-1])
        mid = interpolate(a, b, (count//2+.5)/count)
        deck = queries.down(group, mid[0], mid[1], mid[2]+.2, mid[2]-.4)
        ground = queries.down(land, mid[0], mid[1])
        clearance = None if deck is None or ground is None else deck-ground
        if clearance is None or clearance < 2.:
            bridge_errors.add(bridge=bridge["id"], reason="actual midpoint ravine clearance is insufficient", clearance_m=clearance)
        members = 0
        for side in (-1, 1):
            offset = side*(width/2+.13)
            # Actual timber tower tops, iron cable, vertical suspenders, and
            # backstay midpoints must each have a saved physical surface.
            for endpoint in (a, b):
                x, y = endpoint[0]+nx*offset, endpoint[1]+ny*offset
                hit = queries.down(group, x, y, endpoint[2]+3.85, endpoint[2]+3.40)
                members += 1
                if hit is None or abs(hit-(endpoint[2]+3.65)) > .035:
                    bridge_errors.add(bridge=bridge["id"], reason="actual suspension tower top absent", xy_m=[x, y], actual_z_m=hit)
            for t in (.23, .49, .77):
                p = interpolate(a, b, t)
                x, y = p[0]+nx*offset, p[1]+ny*offset
                expected = p[2]+1.65+2*(2*t-1)**2
                hit = queries.down(group, x, y, expected+.10, expected-.10)
                members += 1
                if hit is None:
                    bridge_errors.add(bridge=bridge["id"], reason="actual sagged cable surface absent", station=t, side=side)
            n = math.ceil(length/1.4)
            for i in (max(1, n//4), n//2, min(n-1, 3*n//4)):
                t = i/n
                j = min(count, round(t*count))
                p = interpolate(a, b, j/count)
                x, y, z = p[0]+nx*offset, p[1]+ny*offset, interpolate(a, b, t)[2]+.65
                hit = queries.ray(group, (x-ux*.06, y-uy*.06, z), (ux, uy, 0), .12)
                members += 1
                if hit is None:
                    bridge_errors.add(bridge=bridge["id"], reason="actual suspension hanger absent", station=t, side=side)
            for endpoint, direction in ((a, -1), (b, 1)):
                x, y = endpoint[0]+nx*offset, endpoint[1]+ny*offset
                ax, ay = x+direction*ux*3.8, y+direction*uy*3.8
                anchor_ground = queries.down(land, ax, ay)
                anchor_top = queries.down(group, ax, ay, 180, -20)
                members += 1
                if anchor_ground is None or anchor_top is None or not .30 <= anchor_top-anchor_ground <= .50:
                    bridge_errors.add(bridge=bridge["id"], reason="actual backstay anchor ground contact failed", xy_m=[ax, ay],
                                      anchor_top_m=anchor_top, native_ground_m=anchor_ground)
                if anchor_top is not None:
                    midstay=((x+ax)/2,(y+ay)/2,(endpoint[2]+3.65+anchor_top)/2)
                    members += 1
                    if queries.ray(group,(midstay[0]-nx*.07,midstay[1]-ny*.07,midstay[2]),(nx,ny,0),.14) is None:
                        bridge_errors.add(bridge=bridge["id"],reason="actual tower-to-ground backstay absent",side=side,midpoint_m=list(midstay))
        bridge_measurements.append({"id": bridge["id"], "length_m": length, "width_m": width,
                                    "planks_sampled_at_three_stations": count, "midpoint_clearance_m": clearance,
                                    "landing_controls": landings, "suspension_member_controls": members})
    check("actual_bridge_decks_landings_ravines_and_suspension", len(bridge_measurements) == 2 and not bridge_errors.count,
          bridge_errors.detail(bridges=bridge_measurements, deck_height_tolerance_m=.002, landing_contact_tolerance_m=.15))

    stair_errors = Findings()
    stair_measurements = []
    for stair in plan["stairs"]:
        group = [o for o in meshes if o.get("reserve_stair_id") == stair["id"]]
        steps = landings = 0
        rises, treads, native_tread_lengths = [], [], []
        for flight in stair.get("flights", []):
            a, b = flight["points_m"]
            count = flight["step_count"]
            length = math.dist(a[:2], b[:2])
            nx, ny = -(b[1]-a[1])/length, (b[0]-a[0])/length
            previous = a[2] if b[2] >= a[2] else b[2]
            for j in range(count):
                expected = a[2]+(b[2]-a[2])*((j+1)/count if b[2] >= a[2] else j/count)
                actual_center = None
                for t in ((j+.22)/count, (j+.50)/count, (j+.78)/count):
                    p = interpolate(a, b, t)
                    for lateral in (-stair["width_m"]*.30, 0, stair["width_m"]*.30):
                        actual = queries.down(group, p[0]+nx*lateral, p[1]+ny*lateral,
                                              max(a[2], b[2])+.25, min(a[2], b[2])-.50)
                        if actual is None or abs(actual-expected) > .002:
                            stair_errors.add(stair=stair["id"], flight=flight["id"], tread=j,
                                             reason="actual tread top absent or not level", actual_z_m=actual, expected_z_m=expected)
                        if abs(t-(j+.5)/count) < 1e-6 and lateral == 0:
                            actual_center = actual
                if actual_center is not None:
                    if j or b[2] >= a[2]:
                        rises.append(abs(actual_center-previous))
                    previous = actual_center
                steps += 1
                treads.append(length/count)
            # Handrail surface on both sides, independently of tread surfaces.
            for side in (-1, 1):
                p = interpolate(a, b, .43)
                expected = p[2]+stair.get("handrail_height_m", 1.1)
                x, y = p[0]+nx*side*(stair["width_m"]/2+.08), p[1]+ny*side*(stair["width_m"]/2+.08)
                if queries.down(group, x, y, expected+.10, expected-.10) is None:
                    stair_errors.add(stair=stair["id"], flight=flight["id"], reason="actual handrail absent", side=side)
            # Scan the actual central surface independently of authored tread
            # boundaries. Contiguous equal-height runs measure physical treads.
            scan_count=math.ceil(length/.01)
            previous_height=None
            run_start=0
            runs=[]
            for k in range(scan_count):
                p=interpolate(a,b,(k+.5)/scan_count)
                height=queries.down(group,p[0],p[1],max(a[2],b[2])+.25,min(a[2],b[2])-.5)
                if previous_height is not None and (height is None or abs(height-previous_height)>.002):
                    runs.append((k-run_start)*length/scan_count)
                    run_start=k
                previous_height=height
            runs.append((scan_count-run_start)*length/scan_count)
            native_tread_lengths.extend(runs)
            if len(runs)!=count or min(runs,default=0)<.28:
                stair_errors.add(stair=stair["id"],flight=flight["id"],reason="actual scanned tread runs are missing/short",
                                 actual_run_count=len(runs),expected_treads=count,measured_flat_runs_m=runs)
        for landing in stair.get("landings", []):
            a, b = landing["points_m"]
            length = math.dist(a[:2], b[:2])
            nx, ny = -(b[1]-a[1])/length, (b[0]-a[0])/length
            if abs(length-landing["length_m"]) > .002 or length < 1.49:
                stair_errors.add(stair=stair["id"], reason="landing has inadequate authored length", length_m=length)
            for t in (.03, .25, .50, .75, .97):
                p = interpolate(a, b, t)
                for side in (-.30, 0, .30):
                    actual = queries.down(group, p[0]+nx*stair["width_m"]*side, p[1]+ny*stair["width_m"]*side, p[2]+.25, p[2]-.50)
                    if actual is None or abs(actual-p[2]) > .002:
                        stair_errors.add(stair=stair["id"], reason="actual 1.5m landing surface missing/nonlevel",
                                         station=t, side=side, expected_z_m=p[2], actual_z_m=actual)
            landings += 1
        if steps != stair["step_count"] or not rises or max(rises) > .18 or not treads or min(treads) < .28:
            stair_errors.add(stair=stair["id"], reason="actual stair count/rise/tread limits failed", steps=steps,
                             expected_steps=stair["step_count"], maximum_rise_m=max(rises, default=None), minimum_tread_m=min(treads, default=None))
        stair_measurements.append({"id": stair["id"], "actual_treads_sampled": steps, "actual_landings_sampled": landings,
                                   "rise_range_m": [min(rises, default=None), max(rises, default=None)],
                                   "tread_plan_distance_m": [min(treads, default=None), max(treads, default=None)],
                                   "actual_scanned_flat_tread_length_m":[min(native_tread_lengths,default=None),max(native_tread_lengths,default=None)],
                                   "flat_tread_scan_resolution_m":.01,
                                   "tread_surface_method": "3 longitudinal x3 lateral actual mesh ray controls per tread"})
    check("actual_stone_stair_rises_treads_landings_and_handrails", len(stair_measurements) == 2 and not stair_errors.count,
          stair_errors.detail(stairs=stair_measurements, height_tolerance_m=.002))
    stair_land_errors = Findings()
    stair_land_measurements = [stair_land_clearance(queries,stair,
        [ob for ob in meshes if ob.get("reserve_stair_id")==stair["id"]],land,
        plan["paths"],trail_surfaces,stair_land_errors) for stair in plan["stairs"]]
    check("actual_stair_land_occlusion_and_walking_head_clearance_absent", len(stair_land_measurements)==2
          and not stair_land_errors.count,stair_land_errors.detail(stairs=stair_land_measurements))

    kit, captured = capture_kit()
    interior_module = load_module("reserve_audit_core_interior", ROOT / "tools/interior_design.py")
    asset_groups = defaultdict(list)
    for ob in meshes:
        if ob.get("interior_asset_id"):
            asset_groups[ob["interior_asset_id"]].append(ob)
    core_assets = {}
    pose_errors, ownership_errors, partition_errors, clearance_errors = Findings(), Findings(), Findings(), Findings()
    vertex_count = body_rays = apertures = solid_controls = rooms_count = 0
    maximum_pose_error = 0.
    for building in core["buildings"]:
        record = records.get(building["id"])
        if record is None:
            ownership_errors.add(owner=building["id"], reason="core manifest record missing")
            continue
        frame = (*record["center_m"], math.radians(record["yaw_degrees"]))
        for level in building["levels"]:
            ff = level["finished_floor_local_z_m"]
            partitions = [o for o in meshes if o.get("interior_building_id") == building["id"]
                          and o.get("interior_role") == "partition_with_openings"
                          and any(c.name == building["id"]+f'_Interior_L{level["level"]:02d}' for c in o.users_collection)]
            # Partition objects belong directly to their level collection.
            aa, ss = partition_probes(queries, partitions, frame, ff, level["partitions"], partition_errors,
                                      building["id"]+f'_L{level["level"]:02d}')
            apertures += aa
            solid_controls += ss
            level_assets = [o for r in level["rooms"] for a in r["assets"] for o in asset_groups.get(a["id"], [])]
            doors = [o for o in meshes if o.get("interior_building_id") == building["id"] and o.get("interior_role") in {"open_interior_door","interior_joinery"}
                     and any(c.name == building["id"]+f'_Interior_L{level["level"]:02d}' for c in o.users_collection)]
            blockers = partitions+level_assets+doors
            for room in level["rooms"]:
                rooms_count += 1
                rc = bpy.data.collections.get(room["id"])
                if rc is None:
                    ownership_errors.add(owner=room["id"], reason="native room collection missing")
                for asset in room["assets"]:
                    core_assets[asset["id"]] = asset
                    actual = asset_groups.get(asset["id"], [])
                    if not actual or any(o.get("interior_room_id") != room["id"] or o.get("interior_building_id") != building["id"]
                                         or rc is None or o.name not in rc.objects for o in actual):
                        ownership_errors.add(owner=asset["id"], reason="saved furnishing ownership missing or wrong")
                    captured.clear()
                    def local_world(x, y, z):
                        return world(frame, (x, y, z))
                    interior_module.build_asset(kit, asset, None, local_world, frame[3], ff, room["id"], [])
                    errors, maximum, vertices = vertex_pose_errors(actual, captured)
                    maximum_pose_error = max(maximum_pose_error, maximum)
                    vertex_count += vertices
                    if errors:
                        pose_errors.add(owner=asset["id"], errors=errors, maximum_vertex_error_m=maximum)
                # These rectangles are the resolved composition's protected
                # usable fronts, not generic aisle labels. At least3 samples
                # check their interior without colliding with boundary faces.
                for rect in room.get("furniture_clearances_m", []):
                    a, b, c, d = rect
                    points = [(a+(c-a)*u, b+(d-b)*v) for u, v in ((.25,.5),(.5,.5),(.75,.5))]
                    body_rays += clearance_probes(queries, blockers, frame, ff, points, clearance_errors, room["id"])
                for opening in room.get("door_gaps", []):
                    if opening.get("kind") != "door":
                        continue
                    co, center = opening["coordinate_m"], opening["center_m"]
                    points = [(co, center)] if opening["axis"] == "x" else [(center, co)]
                    body_rays += clearance_probes(queries, blockers, frame, ff, points, clearance_errors, room["id"])
    native_core_ids = {key for key in asset_groups if not key.startswith("Reserve_")}
    if native_core_ids != set(core_assets):
        ownership_errors.add(reason="core actual semantic fixture inventory differs from canonical plan",
                             missing=sorted(set(core_assets)-native_core_ids), extra=sorted(native_core_ids-set(core_assets)))
    check("core_757_actual_furniture_mesh_poses_match_refined_plan", len(core_assets) == core["furnishing_count"] == 757
          and not pose_errors.count, pose_errors.detail(assemblies=len(core_assets), actual_vertices_compared=vertex_count,
          maximum_world_vertex_error_m=maximum_pose_error, tolerance_m=.00025,
          method="Every saved vertex compared in order/material with source recipe at canonical world pose; no facing extras used."))
    check("core_room_and_fixture_ownership_preserved", rooms_count == core["room_count"] == 561 and not ownership_errors.count,
          ownership_errors.detail(rooms=rooms_count, native_assemblies=len(native_core_ids)))
    check("core_actual_partition_holes_and_solid_spans", apertures > 200 and not partition_errors.count,
          partition_errors.detail(aperture_rays=apertures, solid_control_rays=solid_controls))
    check("core_actual_furniture_front_and_door_body_clearance", body_rays > 500 and not clearance_errors.count,
          clearance_errors.detail(body_columns=body_rays, body_band_above_floor_m=[.16, 1.70],
                                 limits="Finite samples of reserved fronts/door apertures; plan BFS and runtime navigation audits remain required."))
    compositions=interior_module.audit_furniture_compositions(core)
    check("mesh_matched_core_compositions_orientation_and_density", not pose_errors.count and compositions["status"]=="PASS",
          {"furnished_rooms":compositions["rooms_tested"],"wall_back_orientations":compositions["wall_back_orientations_tested"],
           "activity_groups":compositions["related_activity_groups_tested"],"failure_count":len(compositions["failures"]),
           "failures":compositions["failures"][:60],"method":"Canonical geometric composition measures plus every saved mesh vertex matched to that canonical pose."})

    projection = json.loads((REPO / "game/data/town3d/projection.json").read_text(encoding="utf-8"))
    fixture_ids = {b["model_asset_id"] for b in projection["interaction_bindings"].values() if b.get("model_asset_id")}
    missing_fixtures = sorted(fixture_ids-set(core_assets))
    check("frozen_47_game_bound_fixture_ids_exist_in_actual_meshes", len(fixture_ids) == 47 and not missing_fixtures
          and all(asset_groups.get(ident) for ident in fixture_ids),
          {"unique_fixture_ids": len(fixture_ids), "functional_aliases": len(projection["interaction_bindings"]),
           "missing": missing_fixtures, "fixture_ids": sorted(fixture_ids),
           "projection_sha256": sha256(REPO / "game/data/town3d/projection.json")})

    amenity_errors, amenity_pose_errors, amenity_partition_errors, amenity_clearance_errors = Findings(), Findings(), Findings(), Findings()
    amenity_rooms = amenity_assets = amenity_vertices = amenity_apertures = amenity_solids = amenity_body = 0
    native_reserve_assets = defaultdict(list)
    for ob in meshes:
        if ob.get("reserve_asset_id") and ob.get("reserve_role") == "furnishing":
            native_reserve_assets[ob["reserve_asset_id"]].append(ob)
    expected_amenity_ids = set()
    for amenity in amenities:
        ident = amenity["id"]
        frame = (*amenity["center"][:2], amenity["pad_level_m"], math.radians(amenity["yaw_degrees"]))
        ff = amenity["finished_floor_local_z_m"]
        for suffix in ("", "_Structure", "_Roof", "_FrontCover", "_Interior", "_Interior_L00", "_Site_Utilities"):
            collection = bpy.data.collections.get(ident+suffix)
            if collection is None:
                amenity_errors.add(owner=ident+suffix, reason="required amenity collection missing")
        group = [o for o in meshes if o.get("reserve_building_id") == ident]
        partitions = [o for o in group if o.get("reserve_role") == "interior_partitions_with_real_door_holes"]
        aa, ss = partition_probes(queries, partitions, frame, ff, amenity["partitions"], amenity_partition_errors, ident)
        amenity_apertures += aa
        amenity_solids += ss
        room_collections = {}
        for room in amenity["rooms"]:
            amenity_rooms += 1
            rc = bpy.data.collections.get(room["id"])
            room_collections[room["id"]] = rc
            if rc is None or rc.get("reserve_room_id") != room["id"]:
                amenity_errors.add(owner=room["id"], reason="actual reserve room collection/owner missing")
            floor_objects = [o for o in group if o.get("reserve_room_id") == room["id"] and o.get("reserve_role") == "room_floor_finish"]
            a, b, c, d = room["bounds_m"]
            x, y, z = world(frame, ((a+c)/2, (b+d)/2, ff+.12))
            hit = queries.down(floor_objects, x, y, z, z-.25)
            expected = frame[2]+ff
            if hit is None or abs(hit-expected) > .002:
                amenity_errors.add(owner=room["id"], reason="native room floor finish absent/wrong level", actual_z_m=hit, expected_z_m=expected)
        assets = []
        for asset in amenity["assets"]:
            amenity_assets += 1
            expected_amenity_ids.add(asset["id"])
            actual = native_reserve_assets.get(asset["id"], [])
            assets.extend(actual)
            rc = room_collections.get(asset["room_id"])
            if not actual or any(o.get("reserve_room_id") != asset["room_id"] or rc is None or o.name not in rc.objects for o in actual):
                amenity_errors.add(owner=asset["id"], reason="actual reserve furnishing ownership missing/wrong")
            captured.clear()
            batch = kit["Batch"](asset["id"], None)
            amenity_module._asset_geometry(batch, asset)
            position = world(frame, (*asset["center_m"], ff))
            asset_frame = (*position, frame[3]+math.radians(asset.get("rotation_degrees", 0)))
            failures, maximum, vertices = vertex_pose_errors(actual, captured, asset_frame)
            amenity_vertices += vertices
            if failures:
                amenity_pose_errors.add(owner=asset["id"], errors=failures, maximum_vertex_error_m=maximum)
        blockers = partitions+assets+[o for o in group if o.get("reserve_role")=="open_interior_door"]
        for asset in amenity["assets"]:
            # Shower trays are below the body-ray band; the authored shower
            # standing center is still tested against glass/fixtures/partitions.
            amenity_body += clearance_probes(queries, blockers, frame, ff,
                                              [asset["approach_local_m"]], amenity_clearance_errors, asset["id"])
        entry_x, entry_y = amenity["entry_local"]
        front = [o for o in group if o.get("reserve_role") == "front_cover"]
        dx, dy = rotate(0, 1, frame[3])
        hit = queries.ray(front, world(frame, (entry_x, entry_y-.25, ff+1.10)), (dx, dy, 0), .50)
        if hit:
            amenity_partition_errors.add(owner=ident, reason="actual entrance aperture obstructed", hit=hit)
        amenity_body += clearance_probes(queries, blockers, frame, ff,
                                         [(entry_x, entry_y+.30), (entry_x, entry_y+.65)], amenity_clearance_errors, ident)
        # Native entry steps are measured individually, not inferred from ff.
        steps = max(2, math.ceil(ff/.15))
        site = [o for o in group if o.get("reserve_role") == "visitor_entry_steps_signs_and_site_utilities"]
        step_material = "Oak" if amenity["kind"] == "trailer" else "Granite"
        # Welcome mats sit 24mm above the last tread. Isolate the structural
        # stair material so its actual rise is not confused with that overlay.
        stair_surfaces = [o for o in site if o.data.materials and
                          re.sub(r"\.\d{3}$", "", o.data.materials[0].name.removeprefix("LT_")) == step_material]
        for j in range(steps):
            p = world(frame, (entry_x, entry_y-.27*(steps-j)+.135, ff+.15))
            actual = queries.down(stair_surfaces, p[0], p[1], p[2], frame[2]-.2)
            expected = frame[2]+ff*(j+1)/steps
            if actual is None or abs(actual-expected) > .002:
                amenity_errors.add(owner=ident, reason="actual entry stair surface missing/wrong rise", tread=j,
                                   actual_z_m=actual, expected_z_m=expected)
    if set(native_reserve_assets) != expected_amenity_ids:
        amenity_errors.add(reason="actual reserve fixture inventory differs from source plan",
                          missing=sorted(expected_amenity_ids-set(native_reserve_assets)),
                          extra=sorted(set(native_reserve_assets)-expected_amenity_ids))
    check("21_reserve_amenities_actual_ownership_floors_and_entry_steps", len(amenities) == 21 and not amenity_errors.count,
          amenity_errors.detail(buildings=len(amenities), kinds=dict(Counter(a["kind"] for a in amenities)),
                                rooms=amenity_rooms, assemblies=amenity_assets))
    check("reserve_furnishing_actual_world_mesh_poses", not amenity_pose_errors.count and amenity_vertices > 10000,
          amenity_pose_errors.detail(assemblies=amenity_assets, vertices_compared=amenity_vertices, tolerance_m=.00025))
    check("reserve_actual_partitions_and_entrance_holes", amenity_apertures > 30 and not amenity_partition_errors.count,
          amenity_partition_errors.detail(partition_apertures=amenity_apertures, solid_controls=amenity_solids, entrances=len(amenities)))
    check("reserve_actual_fixture_approaches_and_entry_body_clearance", amenity_body > 100 and not amenity_clearance_errors.count,
          amenity_clearance_errors.detail(body_columns=amenity_body, body_band_above_floor_m=[.16, 1.70]))
    facade_errors = Findings()
    facade_ownership = facade_cover_ownership(amenities, meshes, bpy.data.collections, facade_errors)
    check("all21_actual_facade_attachments_owned_by_local_front_cover", facade_ownership["buildings"] == 21
          and not facade_errors.count, facade_errors.detail(**facade_ownership))

    source = Path(bpy.data.filepath) if bpy.data.filepath else None
    failed = [c["id"] for c in checks if c["status"] == "FAIL"]
    report = {"schema": "living_town.reserve_native_audit.v1", "generated_utc": datetime.now(timezone.utc).isoformat(),
              "status": "FAIL" if failed else "PASS", "blender_version": bpy.app.version_string,
              "source_blend": str(source) if source else None,
              "source_blend_sha256": sha256(source) if source and source.is_file() else None,
              "source_bindings": bindings,
              "audit_module_sha256": sha256(Path(__file__)),
              "primitive_recipe_module_sha256": sha256(ROOT / "tools/build_living_town.py"),
              "measurements": {"native_scene_meshes": len(meshes), "mesh_bvhs": len(queries.cache), "ray_queries": queries.rays},
              "checks": checks, "failed_checks": failed,
              "scope": "Saved base meshes in world space: land/core controls, linked tree roots and clearings, trail shoulders, bridge decks/landings/suspension, stone stair treads/landings, core and reserve fixture vertex poses, room ownership, partition holes and finite body columns. Does not replace core native audit, collision/navigation/playtest, evaluated beauty render QA, or accessibility certification.",
              "scene_mutations": "None: no operators, view-layer changes, visibility changes, selection, depsgraph evaluation, or save."}
    if report["source_blend_sha256"] is None:
        report["status"] = "FAIL"
        report["failed_checks"].append("saved_native_source_file_missing")
    return report


def main():
    output = ROOT / "evidence/reserve_native_audit.json"
    args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    if args:
        if len(args) != 2 or args[0] != "--output":
            raise ValueError("Expected -- --output <audit.json>")
        output = Path(args[1]).resolve()
    report = run()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False)+"\n", encoding="utf-8", newline="\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
