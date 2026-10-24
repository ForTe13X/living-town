"""Textured, shared-mesh woodland and maintained garden ground layers.

The owning Blender builder supplies the accepted CC0 source mesh cache and its
actual terrain ray function. No files/scenes are opened, saved, or exported here.
Only identified primitive foliage components are removed; soil, pots, masonry,
hydrangeas, original detailed planters, trees, buildings and paths are protected.
Importing this module requires only Python's standard library.
"""
from __future__ import annotations

from array import array
import ast
import sys
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import random


OWNER = "living_town.textured_understory.v1"
ASSETS = ("fern_02", "celandine_01", "grass_medium_01")
FOLIAGE_KEYS = {"Leaf", "LeafLight", "LeafDark", "LeafSilver", "BloomBlue", "BloomCream", "BloomPink"}
LEGACY_BED_PREFIXES = ("Reference_Pocket_Gardens_", "Bocage_Field_Walls_and_Hedges_",
                       "Reserve_Ferns_Heather_and_Fallen_Wood_", "Garden_Vegetation_",
                       "Sheltered_Gardens_and_Canopies_")
POT_PREFIXES = ("Garden_Vegetation", "Sheltered_Gardens_and_Canopies", "Civic_Square_and_Summer_Life",
                "Everyday_StreetFurniture", "Study_Hydrangeas")


def _sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _ast_sha(node):
    # Python 3.13 omits empty AST fields by default. The canonical 3.12 recipe
    # hash includes them; preserve that exact representation in Blender 3.13.
    options={"include_attributes":False}
    if sys.version_info >= (3,13):options["show_empty"]=True
    return hashlib.sha256(ast.dump(node,**options).encode()).hexdigest()


def _read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def _point_segment(point, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    length2 = dx*dx+dy*dy
    t = max(0., min(1., ((point[0]-a[0])*dx+(point[1]-a[1])*dy)/length2)) if length2 else 0.
    return math.hypot(point[0]-a[0]-t*dx, point[1]-a[1]-t*dy)


def _inside(point, polygon):
    x, y = point
    result = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        if (a[1] > y) != (b[1] > y):
            if x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
                result = not result
    return result


def _world(row, x, y):
    a = math.radians(row.get("yaw_degrees", 0))
    center = row.get("center_m", row.get("center"))
    return center[0]+x*math.cos(a)-y*math.sin(a), center[1]+x*math.sin(a)+y*math.cos(a)


def _local(row, x, y):
    a = math.radians(row.get("yaw_degrees", 0))
    center = row.get("center_m", row.get("center"))
    dx, dy = x-center[0], y-center[1]
    return dx*math.cos(a)+dy*math.sin(a), -dx*math.sin(a)+dy*math.cos(a)


class Spatial:
    def __init__(self, cell=16.):
        self.cell, self.grid, self.rows = cell, defaultdict(list), []

    def add(self, value, bounds):
        ident = len(self.rows)
        self.rows.append(value)
        x0, y0, x1, y1 = bounds
        for x in range(math.floor(x0/self.cell), math.floor(x1/self.cell)+1):
            for y in range(math.floor(y0/self.cell), math.floor(y1/self.cell)+1):
                self.grid[x, y].append(ident)

    def near(self, x, y, radius=0):
        seen = set()
        for xx in range(math.floor((x-radius)/self.cell), math.floor((x+radius)/self.cell)+1):
            for yy in range(math.floor((y-radius)/self.cell), math.floor((y+radius)/self.cell)+1):
                seen.update(self.grid.get((xx, yy), ()))
        return [self.rows[i] for i in sorted(seen)]


class Siting:
    """Authoritative footprint/route masks, with no invented flat-ground fallback."""
    def __init__(self, master, landscape, reserve, expansion, buildings):
        self.routes, self.parcels, self.points = Spatial(), Spatial(), Spatial()
        self.public_route_rows = []
        self.pond = landscape.get("pond", landscape.get("park", {}).get("pond", {}))
        self.polygons = [("civic_plaza", master["plaza"]["polygon"])] if master.get("plaza") else []
        # The quay remains hardscape even where its opening has no terrain hit.
        self.polygons.append(("harbor_quay", [[31, 37], [66, 37], [66, 55], [31, 55]]))
        for source, rows in (("urban_street", master.get("streets", [])),
                             ("garden_path", landscape.get("paths", [])),
                             ("reserve_path", reserve.get("paths", [])),
                             ("bridge", reserve.get("bridges", [])),
                             ("stone_stair", reserve.get("stairs", [])),
                             ("expansion_road", expansion.get("roads", [])),
                             ("threshold_approach", expansion.get("approaches", []))):
            for row in rows:
                points = row.get("points_m", row.get("points_xy", row.get("points", [])))
                width = row.get("width_m", row.get("width", 1.5))
                # Sidewalk widths are per side; the reserve shoulder is a dry
                # verge, not automatic paving. Actual hardscape rays follow.
                sidewalk = row.get("sidewalk_width_m", 0)
                margin = .40 if source in ("urban_street", "expansion_road") else .28
                buffer = width/2+sidewalk+margin
                if source in ("urban_street", "garden_path", "reserve_path", "expansion_road") and row.get("public") is not False:
                    self.public_route_rows.append({"id": row.get("id"), "source": source,
                                                   "points": points, "buffer_m": buffer})
                for a, b in zip(points, points[1:]):
                    self.routes.add((a, b, buffer, source, row.get("id")),
                                    [min(a[0], b[0])-buffer, min(a[1], b[1])-buffer,
                                     max(a[0], b[0])+buffer, max(a[1], b[1])+buffer])
        self.buildings = buildings
        for row in buildings:
            w, d = row["footprint_m"]
            corners = [_world(row, x, y) for x in (-w/2-.45, w/2+.45) for y in (-d/2-.45, d/2+.45)]
            self.parcels.add(row, [min(p[0] for p in corners), min(p[1] for p in corners),
                                   max(p[0] for p in corners), max(p[1] for p in corners)])
        utility_points = reserve.get("utilities", {}).get("points", [])+reserve.get("utilities", {}).get("pitch_hookups", [])
        utility_points += landscape.get("park", {}).get("benches", [])
        for row in utility_points:
            point = row.get("center_m", row.get("center", row.get("xy")))
            if point:
                self.points.add((point, 1.35, row.get("id", "public_fixture")),
                                [point[0]-1.35, point[1]-1.35, point[0]+1.35, point[1]+1.35])
        self.clearings = reserve.get("clearings", [])

    def threshold_reason(self, x, y, radius):
        for row in self.parcels.near(x, y, radius+2.2):
            lx, ly = _local(row, x, y)
            w, d = row["footprint_m"]
            door = row.get("door_local_x", row.get("reserve_source", {}).get("entry_local", [0])[0])
            if abs(lx-door) < .85+radius and -d/2-1.85-radius < ly < -d/2+.35+radius:
                return "building_threshold:"+row["id"]
        return None

    def reason(self, x, y, radius, habitat):
        blocked = self.threshold_reason(x, y, radius)
        if blocked:
            return blocked
        for row in self.parcels.near(x, y, radius+.5):
            lx, ly = _local(row, x, y)
            w, d = row["footprint_m"]
            if abs(lx) < w/2+.20+radius and abs(ly) < d/2+.20+radius:
                return "building_envelope:"+row["id"]
        for a, b, width, source, ident in self.routes.near(x, y, radius):
            if _point_segment((x, y), a, b) < width+radius:
                return source+":"+str(ident)
        for point, width, ident in self.points.near(x, y, radius):
            if math.dist((x, y), point[:2]) < width+radius:
                return "public_fixture:"+str(ident)
        for ident, polygon in self.polygons:
            if _inside((x, y), polygon) or any(_point_segment((x, y), a, b) < radius+.1 for a, b in zip(polygon, polygon[1:]+polygon[:1])):
                return ident
        if self.pond:
            cx, cy = self.pond["center"]
            rx, ry = self.pond["water_radii_m"]
            if ((x-cx)/(rx+radius+.25))**2+((y-cy)/(ry+radius+.25))**2 < 1:
                return "pond_water_and_shore_clearance"
        coast = 49+2*math.sin(y*.055)-7*math.exp(-((y-43)/10)**2)
        # No new grass in the beach/coastal access strips. Existing authored
        # dune-grass clumps remain intact and separately owned.
        beach_width = 7-6*max(0, min(1, (y-24)/11))**2*(3-2*max(0, min(1, (y-24)/11)))
        if x+radius > coast-beach_width-.4:
            return "coast_or_beach_access"
        if habitat == "woodland_root_drift":
            for row in self.clearings:
                point = row.get("center_m", row.get("center"))
                radii = row.get("radii_m", row.get("radii"))
                if point and radii and ((x-point[0])/(radii[0]+radius))**2+((y-point[1])/(radii[1]+radius))**2 < 1:
                    return "retained_view_or_public_clearing:"+row["id"]
        return None


def _source_key(material):
    name = material.name
    if name.rsplit(".", 1)[-1].isdigit():
        name = name.rsplit(".", 1)[0]
    for prefix in ("LT_", "Expansion_"):
        if name.startswith(prefix):
            return name[len(prefix):]
    return name


def _components(mesh):
    parent = list(range(len(mesh.vertices)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for edge in mesh.edges:
        a, b = map(root, edge.vertices)
        parent[a] = b
    groups = defaultdict(list)
    for i in range(len(parent)):
        groups[root(i)].append(i)
    return list(groups.values())


def _mesh_hash(mesh):
    vertices = array("f", [0])*(3*len(mesh.vertices))
    mesh.vertices.foreach_get("co", vertices)
    loops = array("i", [0])*len(mesh.loops)
    mesh.loops.foreach_get("vertex_index", loops)
    return hashlib.sha256(vertices.tobytes()+loops.tobytes()).hexdigest()


def _ellipsoid_recipe(points):
    """Recognize the exact original Batch.ellipsoid vertex order/formula."""
    if len(points) < 24:
        return None
    first = points[0]
    n = 0
    for p in points:
        if math.dist(p, first) > .00002:
            break
        n += 1
    if not 5 <= n <= 16 or len(points) % n:
        return None
    rings = len(points)//n-1
    if not 3 <= rings <= 10:
        return None
    center = [first[0], first[1], (first[2]+points[-1][2])/2]
    rz = (points[-1][2]-first[2])/2
    j = rings//2
    cosine = math.cos(-math.pi/2+math.pi*j/rings)
    i = max(range(n), key=lambda index: abs(math.sin(index*math.tau/n)))
    rx = (points[j*n][0]-center[0])/cosine
    ry = (points[j*n+i][1]-center[1])/(cosine*math.sin(i*math.tau/n))
    if min(rx, ry, rz) <= .003:
        return None
    expected = [(center[0]+rx*math.cos(-math.pi/2+math.pi*jj/rings)*math.cos(ii*math.tau/n),
                 center[1]+ry*math.cos(-math.pi/2+math.pi*jj/rings)*math.sin(ii*math.tau/n),
                 center[2]+rz*math.sin(-math.pi/2+math.pi*jj/rings)) for jj in range(rings+1) for ii in range(n)]
    deviation = max(abs(a-b) for p, q in zip(points, expected) for a, b in zip(p, q))
    if deviation > .0002:
        return None
    return {"segments": n, "rings": rings, "center_m": center, "radii_m": [rx, ry, rz],
            "maximum_recipe_deviation_m": deviation}


def _source_component_binding(ob, indices, polygons):
    coordinates = array("f", [v for i in indices for v in ob.data.vertices[i].co])
    remap = {old: new for new, old in enumerate(indices)}
    geometry = hashlib.sha256(coordinates.tobytes())
    uv = hashlib.sha256()
    for polygon in polygons:
        geometry.update(array("i", [len(polygon.vertices), *(remap[i] for i in polygon.vertices)]).tobytes())
        for layer in ob.data.uv_layers:
            uv.update(layer.name.encode())
            uv.update(array("f", [v for li in polygon.loop_indices for v in layer.data[li].uv]).tobytes())
    return {"source_geometry_sha256": geometry.hexdigest(), "source_uv_sha256": uv.hexdigest(),
            "source_vertices": len(indices), "source_polygons": len(polygons)}


def _reserve_triangulation_binding(baseline):
    """Bind the exact canonical reserve recipes and v6 clipping operation."""
    source = Path(baseline)/"tools/reserve_environment.py"
    clipper = Path(__file__).resolve().parents[1]/"town_generation/build_expansion_scene.py"
    tree = ast.parse(source.read_text(encoding="utf-8-sig"))
    authored = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute) or node.func.attr != "ellipsoid":
            continue
        if not isinstance(node.func.value, ast.Name) or node.func.value.id != "understory" or len(node.args) < 3:
            continue
        if not isinstance(node.args[2], ast.Constant) or node.args[2].value not in ("LeafDark", "LeafSilver"):
            continue
        authored[node.args[2].value] = {"radii_m": list(ast.literal_eval(node.args[1])),
                                      **{k.arg: ast.literal_eval(k.value) for k in node.keywords},
                                      "call_ast_sha256": _ast_sha(node)}
    expected = {"LeafDark": [.55, .5, .43], "LeafSilver": [.8, .65, .30]}
    if set(authored) != set(expected) or any(authored[key]["radii_m"] != radii or authored[key].get("n") != 6 or authored[key].get("rings") != 3
                                           for key, radii in expected.items()):
        raise ValueError("Canonical reserve ellipsoid recipes changed; triangulated recognition requires explicit review")
    clip_tree = ast.parse(clipper.read_text(encoding="utf-8-sig"))
    node = next(n for n in clip_tree.body if isinstance(n, ast.FunctionDef) and n.name == "clip_baseline_obstacles")
    clip_ast = _ast_sha(node)
    if clip_ast != "ba7abd58030fa249e96689dbfa94e0619185d1f98ac0ff9049cf1e9c007a4c10":
        raise ValueError("Bound reserve clipping/triangulation operation changed; explicit review required")
    return {"reserve_source": {"path": str(source.resolve()), "sha256": _sha(source)},
            "clipper_source": {"path": str(clipper.resolve()), "sha256": _sha(clipper),
                               "function": "clip_baseline_obstacles", "function_ast_sha256": clip_ast},
            "authored_recipes": authored,
            "scope": "Only the exact two n6/rings3 reserve primitive batches triangulated by the bound corridor cleanup; no generic topology acceptance."}


def _triangulated_reserve_proof(ob, indices, polygons, recipe, provenance):
    """Prove 36 triangles are precisely the 18 original source grid quads."""
    prefix = "Reserve_Ferns_Heather_and_Fallen_Wood_"
    if ob.name not in (prefix+"LeafDark", prefix+"LeafSilver") or recipe["segments"] != 6 or recipe["rings"] != 3:
        return None
    material = ob.name.removeprefix(prefix)
    if any(abs(a-b) > .0003 for a, b in zip(recipe["radii_m"], provenance["authored_recipes"][material]["radii_m"])):
        return None
    if len(indices) != 24 or len(polygons) != 36 or any(len(p.vertices) != 3 for p in polygons) or not ob.data.uv_layers.get("MetricUV"):
        return None
    remap = {v: i for i, v in enumerate(indices)}
    quads = [(j*6+i, j*6+(i+1) % 6, (j+1)*6+(i+1) % 6, (j+1)*6+i) for j in range(3) for i in range(6)]
    groups = defaultdict(list)
    points = [tuple(ob.matrix_world@ob.data.vertices[i].co) for i in indices]
    outward, degenerate = 0, 0
    for polygon in polygons:
        face = tuple(remap[v] for v in polygon.vertices)
        candidates = [i for i, quad in enumerate(quads) if set(face) < set(quad)]
        if len(candidates) != 1 or len(set(face)) != 3:
            return None
        groups[candidates[0]].append((polygon, face))
        a, b, c = (points[i] for i in face)
        ab, ac = [b[k]-a[k] for k in range(3)], [c[k]-a[k] for k in range(3)]
        normal = [ab[1]*ac[2]-ab[2]*ac[1], ab[2]*ac[0]-ab[0]*ac[2], ab[0]*ac[1]-ab[1]*ac[0]]
        if sum(v*v for v in normal) < 1e-14:
            degenerate += 1
        else:
            radial = [(a[k]+b[k]+c[k])/3-recipe["center_m"][k] for k in range(3)]
            if sum(a*b for a, b in zip(normal, radial)) <= 0:
                return None
            outward += 1
    if len(groups) != 18 or outward != 24 or degenerate != 12:
        return None
    diagonals, uv_checks = Counter(), 0
    for index, quad in enumerate(quads):
        pair = groups[index]
        if len(pair) != 2:
            return None
        a, b, c, d = quad
        triangles = {frozenset(face) for polygon, face in pair}
        if triangles == {frozenset((a, b, c)), frozenset((a, c, d))}:
            diagonals["AC"] += 1
        elif triangles == {frozenset((a, b, d)), frozenset((b, c, d))}:
            diagonals["BD"] += 1
        else:
            return None
        # Triangulation copies the original quad's corner UVs. Require exact
        # float32 agreement on both shared diagonal corners in every layer.
        for layer in ob.data.uv_layers:
            corners = {}
            for polygon, face in pair:
                for vertex, loop in zip(face, polygon.loop_indices):
                    value = tuple(layer.data[loop].uv)
                    if vertex in corners:
                        if corners[vertex] != value:
                            return None
                        uv_checks += 1
                    corners[vertex] = value
            if len(corners) != 4:
                return None
    return {"variant": "bound_v6_reserve_corridor_triangulation", "original_grid_quads": 18,
            "verified_triangles": 36, "legal_diagonal_counts": dict(diagonals),
            "outward_nondegenerate_faces": outward, "original_pole_degenerate_faces": degenerate,
            "exact_shared_corner_uv_checks": uv_checks,
            "source_primitive_call_ast_sha256": provenance["authored_recipes"][material]["call_ast_sha256"],
            "source_clipper_function_ast_sha256": provenance["clipper_source"]["function_ast_sha256"]}


def _legacy_foliage(bpy):
    """Exact named foliage material batches, never arbitrary scenery ellipsoids."""
    eligible, anchor_points, planter_groups = [], [], defaultdict(list)
    # The old pot() factory has individually shaped 17-petal flower heads.
    # Keep those fine flowers and their foliage rather than treating their
    # raised leaves as ground-cover anchors. Its paired 12-sided terracotta
    # body/rim components are an exact source identity, not a guessed planter.
    protected_flowerpots = []
    for prefix in ("Garden_Vegetation_", "Sheltered_Gardens_and_Canopies_"):
        ob = bpy.data.objects.get(prefix+"Terracotta")
        if ob is None or ob.type != "MESH":
            continue
        for indices in _components(ob.data):
            if len(indices) != 24:
                continue
            points = [ob.matrix_world@ob.data.vertices[i].co for i in indices]
            low = [min(p[k] for p in points) for k in range(3)]
            high = [max(p[k] for p in points) for k in range(3)]
            width = max(high[0]-low[0], high[1]-low[1])
            if .26 <= width <= .63 and .025 <= high[2]-low[2] <= .48:
                protected_flowerpots.append(((low[0]+high[0])/2, (low[1]+high[1])/2,
                                            low[2], high[2]+width*1.15, width*.5+.17))
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH":
            continue
        if ob.get("prototype") == "flowers" and ob.data.name.startswith("ExpansionProto_FlowerPlanter_"):
            planter_groups[ob.name.rsplit("_", 1)[0]].append(ob)
            continue
        if not ob.name.startswith(LEGACY_BED_PREFIXES):
            continue
        keys = {_source_key(slot.material) for slot in ob.material_slots if slot.material}
        if not keys or not keys <= FOLIAGE_KEYS:
            continue
        components = []
        for indices in _components(ob.data):
            points = [ob.matrix_world@ob.data.vertices[i].co for i in indices]
            center = [(min(p[k] for p in points)+max(p[k] for p in points))/2 for k in range(3)]
            if ob.name.startswith(("Garden_Vegetation_", "Sheltered_Gardens_and_Canopies_")) and any(
                    math.dist(center[:2], pot[:2]) < pot[4] and pot[2] <= center[2] <= pot[3]
                    for pot in protected_flowerpots):
                continue
            components.append({"vertices": indices, "center_m": center})
            # LeafDark is the reserve fern mass and LeafLight is the vegetable
            # bed foliage. Tiny grass triangles and rod stems cannot become
            # independent anchors; they follow a nearby replaced leaf mass.
            if keys & {"Leaf", "LeafSilver", "LeafDark", "LeafLight"} and len(indices) >= 24:
                anchor_points.append(center+[next(key for key in ("LeafSilver", "LeafDark", "Leaf", "LeafLight") if key in keys)])
        eligible.append({"object": ob, "components": components, "source_geometry_sha256": _mesh_hash(ob.data)})
    # Two ellipsoid halves belonging to one old planting island merge into
    # one source anchor; no regular new scatter grid is created from these.
    clusters, index = [], Spatial(1.)
    for point in sorted(anchor_points, key=lambda p: (p[0], p[1], p[2])):
        nearby = [p for p in index.near(point[0], point[1], .43) if math.dist(p[:2], point[:2]) < .43]
        if nearby:
            continue
        clusters.append(point)
        index.add(point, [point[0], point[1], point[0], point[1]])
    return eligible, clusters, planter_groups


def _route_verge_candidates(mask, seed=20261020_711):
    """Public route arc-length stations; never an unrestricted field scatter."""
    candidates, coverage = [], []
    for route in sorted(mask.public_route_rows, key=lambda r: (r["source"], str(r["id"]))):
        stable_seed = int(hashlib.sha256((str(seed)+"/"+str(route["id"])).encode()).hexdigest()[:16], 16)
        rng = random.Random(stable_seed)
        next_station, travelled, count = rng.uniform(.15, .75), 0., 0
        for a, b in zip(route["points"], route["points"][1:]):
            length = math.dist(a[:2], b[:2])
            if length < 1e-7:
                continue
            nx, ny = -(b[1]-a[1])/length, (b[0]-a[0])/length
            while next_station <= travelled+length:
                t = (next_station-travelled)/length
                x, y = a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t
                for side in (-1, 1):
                    # Main verge plus a broken outer row: dense irregular
                    # drifts, with the complete paved width kept clear.
                    for lane in range(2 if rng.random() < .58 else 1):
                        offset = route["buffer_m"]+rng.uniform(.78, 1.17)+lane*rng.uniform(.62, 1.02)
                        along = rng.uniform(-.14, .14)
                        candidates.append({"x": x+side*nx*offset-ny*along,
                                           "y": y+side*ny*offset+nx*along,
                                           "source": route["source"], "route_id": route["id"],
                                           "station_m": next_station, "side": side, "lane": lane,
                                           "asset": "celandine_01" if rng.random() < .085 else "grass_medium_01",
                                           "height_m": rng.uniform(.27, .47), "max_radius_m": rng.uniform(.31, .47)})
                        count += 1
                next_station += rng.uniform(.8, 1.4)
            travelled += length
        coverage.append({"route_id": route["id"], "source": route["source"], "length_m": travelled,
                         "candidate_count": count, "station_cadence_m": [.8, 1.4]})
    # Shuffling candidates, rather than traversing route vertices in order,
    # gives all towns/reserve sectors coverage before any bounded budget ends.
    random.Random(seed).shuffle(candidates)
    return candidates, coverage


class _PotRecorder:
    def __init__(self):
        self.parts = []

    def rod(self, p0, p1, radius, material, n=10, r2=None):
        if p0[:2] != p1[:2]:
            raise ValueError("Canonical pot body is no longer vertical")
        self.parts.append({"material": material,
                           "points": [(p[0]-r*math.cos(i*math.tau/n), p[1]-r*math.sin(i*math.tau/n), p[2])
                                      for p, r in ((p0, radius), (p1, radius if r2 is None else r2)) for i in range(n)]})

    def ellipsoid(self, p, r, material, n=10, rings=6):
        self.parts.append({"material": material,
                           "points": [(p[0]+r[0]*math.cos(-math.pi/2+j*math.pi/rings)*math.cos(i*math.tau/n),
                                       p[1]+r[1]*math.cos(-math.pi/2+j*math.pi/rings)*math.sin(i*math.tau/n),
                                       p[2]+r[2]*math.sin(-math.pi/2+j*math.pi/rings))
                                      for j in range(rings+1) for i in range(n)]})


def _pot_sources(bpy, baseline):
    """Exact paired source pot rods plus all seven coarse leaf ellipsoids."""
    path = Path(baseline)/"tools/build_living_town.py"
    tree = ast.parse(path.read_text(encoding="utf-8-sig"))
    recipe = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "pot")
    namespace = {"math": math, "flower_head": lambda *args, **kwargs: None}
    exec(compile(ast.fix_missing_locations(ast.Module(body=[recipe], type_ignores=[])), str(path), "exec"), namespace)
    pots, failures, guards = [], [], []
    def matches(points, expected):
        return len(points) == len(expected) and max(abs(a-b) for p, q in zip(points, expected) for a, b in zip(p, q)) < .0002
    for prefix in POT_PREFIXES:
        body, foliage = bpy.data.objects.get(prefix+"_Terracotta"), bpy.data.objects.get(prefix+"_Leaf")
        if body is None or foliage is None or body.type != "MESH" or foliage.type != "MESH":
            continue
        body_components = [[tuple(body.matrix_world@body.data.vertices[i].co) for i in c] for c in _components(body.data)]
        leaf_components = [{"vertices": c, "points": [tuple(foliage.matrix_world@foliage.data.vertices[i].co) for i in c]}
                           for c in _components(foliage.data)]
        for points in body_components:
            if len(points) != 24:
                continue
            low, high = [min(p[k] for p in points) for k in range(3)], [max(p[k] for p in points) for k in range(3)]
            scale = (high[2]-low[2])/.44
            if not .4 <= scale <= 1.6:
                continue
            x, y, z = (low[0]+high[0])/2, (low[1]+high[1])/2, low[2]
            expected = _PotRecorder(); namespace["pot"](expected, x, y, z, True, scale)
            if len(expected.parts) != 9 or not matches(points, expected.parts[0]["points"]):
                continue
            guards.append((x, y, z, z+1.12*scale, .48*scale))
            rim = [c for c in body_components if matches(c, expected.parts[1]["points"])]
            leaves = [[c for c in leaf_components if matches(c["points"], part["points"])] for part in expected.parts[2:]]
            if len(rim) != 1 or any(len(c) != 1 for c in leaves):
                failures.append({"prefix": prefix, "position_m": [x, y, z], "reason": "Exact pot rim/seven source leaves do not all match"})
                continue
            pots.append({"id": prefix+"_SourceFlowerpot_"+str(len(pots)), "position_m": [x, y, z], "scale": scale,
                         "pot_object": body.name, "foliage_object": foliage,
                         "vertices": [i for leaf in leaves for i in leaf[0]["vertices"]],
                         "source_geometry_sha256": _mesh_hash(foliage.data),
                         "protected_shaped_flower_objects": [o.name for o in bpy.context.scene.objects if o.name.startswith(prefix+"_Bloom")]})
    return pots, failures, guards, {"path": str(path.resolve()), "sha256": _sha(path),
                                  "pot_function_ast_sha256": _ast_sha(recipe)}


def _window_boxes(bpy, buildings):
    """Bind only original cafe/creperie/whitehouse window-box primitives."""
    boxes, failures = [], []
    for row in buildings:
        if row.get("group") != "urban" or row["kind"] not in ("cafe", "creperie", "whitehouse"):
            continue
        prefix = row["id"]+"_Front_"
        objects = {key: bpy.data.objects.get(prefix+key) for key in ("Terracotta", "Leaf", "BloomPink")}
        if any(ob is None or ob.type != "MESH" for ob in objects.values()):
            failures.append({"building_id": row["id"], "reason": "exact_source_window_box_batch_missing"})
            continue
        w, d = row["footprint_m"]
        count = max(1, int(w/2.6))
        centers = [-w/2+(i+.5)*w/count for i in range(count)][::2]
        pad = row["pad_level_m"]
        components = {}
        for key, ob in objects.items():
            records = []
            for indices in _components(ob.data):
                points = [ob.matrix_world@ob.data.vertices[i].co for i in indices]
                points = [(*_local(row, p.x, p.y), p.z-pad) for p in points]
                low = [min(p[k] for p in points) for k in range(3)]
                high = [max(p[k] for p in points) for k in range(3)]
                records.append({"vertices": indices, "center": [(a+b)/2 for a, b in zip(low, high)],
                                "size": [b-a for a, b in zip(low, high)]})
            components[key] = records
        for index, xx in enumerate(centers):
            expected = {"Terracotta": [(xx, -d/2-.35, 3.48)],
                        "Leaf": [(xx-.36+j*.18, -d/2-.35, 3.65) for j in range(5)],
                        "BloomPink": [(xx-.3+j*.2, -d/2-.38, 3.76) for j in range(4)]}
            selected = {}
            valid = True
            for key, positions in expected.items():
                selected[key] = []
                for position in positions:
                    hits = [r for r in components[key] if math.dist(r["center"], position) < .0002
                            and len(r["vertices"]) == (8 if key == "Terracotta" else 48)]
                    if len(hits) != 1:
                        valid = False
                        break
                    selected[key].append(hits[0])
                if not valid:
                    break
            if valid and all(abs(a-b) < .0002 for a, b in zip(selected["Terracotta"][0]["size"], (.92, .38, .20))):
                boxes.append({"id": row["id"]+"_window_box_"+str(index), "row": row, "local_x": xx,
                              "local_y": -d/2-.35, "base_z_m": pad+3.58,
                              "pot_object": objects["Terracotta"].name,
                              "foliage": [{"object": objects[key], "vertices": [i for r in selected[key] for i in r["vertices"]],
                                           "source_geometry_sha256": _mesh_hash(objects[key].data)} for key in ("Leaf", "BloomPink")]})
            else:
                failures.append({"building_id": row["id"], "box_index": index,
                                 "reason": "source_box_or_ellipsoid_component_recipe_mismatch"})
    return boxes, failures


def _hardscape(api):
    """Actual saved paving, path, bridge, stair and utility projections."""
    bpy = api["bpy"]
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    index, trees = Spatial(20.), {}
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH" or not ob.data.polygons:
            continue
        role, reserve_role = ob.get("semantic_role"), ob.get("reserve_role")
        named = ob.name.startswith(("Connected_Streets_and_Pavements_", "Reference_Garden_Paths_", "Harbor_Quay_", "Atlantic_Quay_"))
        if not (role in ("graded_street", "raised_road_bedding", "granite_terrace_retaining_wall", "preservation_boundary_retaining_wall", "constrained_pad_retaining_wall")
                or reserve_role in ("trail", "bridge", "stone_stairs", "retaining_wall", "public_utility", "visitor_entry_steps_signs_and_site_utilities", "picnic_table_with_seats", "public_rest_and_trailhead_furniture") or named):
            continue
        corners = [ob.matrix_world@Vector(p) for p in ob.bound_box]
        index.add(ob, [min(p.x for p in corners), min(p.y for p in corners), max(p.x for p in corners), max(p.y for p in corners)])
    def blocked(x, y, radius):
        points = [(x, y)]+[(x+math.cos(i*math.pi/4)*radius, y+math.sin(i*math.pi/4)*radius) for i in range(8)]
        for ob in index.near(x, y, radius+.1):
            if ob.name not in trees:
                trees[ob.name] = BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],
                                                     [tuple(p.vertices) for p in ob.data.polygons], all_triangles=False)
            bvh = trees[ob.name]
            for xx, yy in points:
                if bvh.ray_cast(Vector((xx, yy, 1000)), Vector((0, 0, -1)), 2000)[0] is not None:
                    return ob.name
        return None
    return blocked, len(index.rows)


def _protected_signature(ob):
    return (ob.type, ob.data.as_pointer() if ob.data else None,
            len(ob.data.vertices) if ob.type == "MESH" else None,
            len(ob.data.polygons) if ob.type == "MESH" else None,
            tuple(tuple(row) for row in ob.matrix_world))


def build(api, collection, cache, tree_placements, buildings, baseline_root, expansion_dir, ground):
    bpy = api["bpy"]
    baseline, expansion = Path(baseline_root), Path(expansion_dir)
    paths = {"masterplan": baseline/"masterplan.json", "landscape_plan": baseline/"landscape_plan.json",
             "reserve_plan": baseline/"reserve_plan.json", "territory_plan": expansion/"territory_plan.json"}
    documents = {key: _read(path) for key, path in paths.items()}
    reserve_tri_binding = _reserve_triangulation_binding(baseline)
    mask = Siting(documents["masterplan"], documents["landscape_plan"], documents["reserve_plan"], documents["territory_plan"], buildings)
    hardscape, hardscape_count = _hardscape(api)
    variants = {asset: sorted([key for key in cache if key[0] == asset and key[2] == "near"]) for asset in ASSETS}
    if any(not keys for keys in variants.values()):
        raise ValueError("Understory requires actual fern_02, celandine_01 and grass_medium_01 source meshes")
    prototype_info = {}
    for keys in variants.values():
        for key in keys:
            meshes = cache[key]
            points = [v.co for mesh in meshes for v in mesh.vertices]
            low, high = min(p.z for p in points), max(p.z for p in points)
            prototype_info[key] = {"height_m": high-low, "base_z_m": low,
                                   "radius_m": max(math.hypot(p.x, p.y) for p in points),
                                   "triangles": sum(sum(len(p.vertices)-2 for p in mesh.polygons) for mesh in meshes),
                                   "mesh_names": [m.name for m in meshes],
                                   "mesh_sha256": [_mesh_hash(m) for m in meshes]}
            if high-low <= .001:
                raise ValueError("Invalid botanical source height: "+str(key))
    eligible, old_anchors, planter_groups = _legacy_foliage(bpy)
    eligible_source_names = [entry["object"].name for entry in eligible]
    source_pots, source_pot_failures, pot_guards, pot_binding = _pot_sources(bpy, baseline)
    window_boxes, window_box_binding_failures = _window_boxes(bpy, buildings)
    mutable_names = {r["object"].name for r in eligible}
    mutable_names.update(r["object"].name for box in window_boxes for r in box["foliage"])
    mutable_names.update(p["foliage_object"].name for p in source_pots)
    for group in planter_groups.values():
        mutable_names.update(o.name for o in group if any(_source_key(s.material) in FOLIAGE_KEYS for s in o.material_slots if s.material))
    protected = {o.name: _protected_signature(o) for o in bpy.context.scene.objects if o.name not in mutable_names}
    rng, occupied, placements, rejected = random.Random(20261020_8341), Spatial(2.), [], Counter()
    max_instances = int(api.get("understory_max_instances", 26000))
    triangle_budget = int(api.get("understory_triangle_budget", 24_000_000))
    total_triangles, source_part_count = 0, 0

    def place(asset, x, y, habitat, owner, height=None, max_radius=None, planter_z=None, source_island=None):
        nonlocal total_triangles, source_part_count
        key = rng.choice(variants[asset])
        info = prototype_info[key]
        target = height if height is not None else rng.uniform(*({"fern_02": (.38, .72), "celandine_01": (.20, .40), "grass_medium_01": (.18, .48)}[asset]))
        scale = target/info["height_m"]
        if max_radius:
            scale = min(scale, max_radius/max(.01, info["radius_m"]))
        if source_island is not None:
            low, high = source_island["bounds_world_m"]
            # A fitted replacement may be in an existing inset/raised bed.
            # It inherits only that measured island's volume, never a general
            # exemption for planting on paving or inside building envelopes.
            terrain_z = ground(x, y, float("nan"))
            if not math.isfinite(terrain_z):
                rejected["source_island_no_actual_ground"] += 1
                return False
            planter_z = max(terrain_z, low[2])
            available_radius = min(x-low[0], high[0]-x, y-low[1], high[1]-y)-.006
            available_height = high[2]-planter_z-.009
            if available_radius <= .015 or available_height <= .04:
                rejected["source_island_no_contained_plant_volume"] += 1
                return False
            scale = min(scale, available_radius/max(.01, info["radius_m"]), available_height/info["height_m"])
        radius = info["radius_m"]*scale
        if len(placements) >= max_instances or total_triangles+info["triangles"] > triangle_budget:
            rejected["bounded_instance_or_triangle_budget"] += 1
            return False
        if planter_z is None:
            reason = mask.reason(x, y, radius, habitat)
            if reason:
                rejected[reason.split(":", 1)[0]] += 1
                return False
            if any(math.dist((x, y), p[:2]) < max(.18, (radius+p[2])*.52) for p in occupied.near(x, y, radius+.9)):
                rejected["nearby_existing_understory_drift"] += 1
                return False
            on_hardscape = hardscape(x, y, radius)
            if on_hardscape:
                rejected["actual_native_hardscape"] += 1
                return False
            z = ground(x, y, float("nan"))
            step = max(.16, min(.55, radius*.7))
            elevations = [ground(x+dx, y+dy, float("nan")) for dx, dy in ((step, 0), (-step, 0), (0, step), (0, -step))]
            if not math.isfinite(z) or not all(math.isfinite(q) for q in elevations):
                rejected["no_actual_ground_surface"] += 1
                return False
            grade = max(abs(q-z)/step for q in elevations)
            limit = .60 if asset == "fern_02" else .44 if asset == "celandine_01" else .50
            if grade > limit:
                rejected["steep_or_broken_terrain"] += 1
                return False
        else:
            # Existing verified factory pot stays on its native position. New
            # flowers are constrained inside its .36m rim, above its .35m body.
            # An exact source-bound first-floor window box is above all
            # pedestrian bodies, so its ground projection may cross an entry.
            # Freestanding ground planters still require threshold clearance.
            reason = None if habitat == "retained_elevated_window_box" else mask.threshold_reason(x, y, radius)
            if reason:
                rejected["existing_planter_threshold_clearance"] += 1
                return False
            z, grade = planter_z, None
        ident = f"Botanical_Understory_{len(placements):05d}"
        yaw = rng.uniform(0, math.tau)
        names = []
        for part, mesh in enumerate(cache[key]):
            ob = bpy.data.objects.new(ident+"_"+str(part), mesh)
            collection.objects.link(ob)
            ob.location = (x, y, z-info["base_z_m"]*scale+.008)
            ob.rotation_euler.z = yaw
            ob.scale = (scale,)*3
            ob["vegetation_role"] = "understory"
            ob["botanical_instance_id"] = ident
            ob["source_asset"] = asset
            ob["source_variant"] = key[1]
            ob["lod"] = key[2]
            ob["source_license"] = "CC0-1.0"
            ob["generator_owner"] = OWNER
            ob["stable_id"] = "botanical/understory/"+ident+"/"+str(part)
            ob["planting_habitat"] = habitat
            ob["planting_owner"] = str(owner)
            names.append(ob.name)
        placements.append({"id": ident, "source_asset": asset, "source_variant": key[1], "lod": key[2],
                           "position_m": [x, y, z], "scale": scale, "yaw_radians": yaw,
                           "footprint_radius_m": radius, "actual_ground_maximum_grade": grade,
                           "habitat": habitat, "owner": str(owner), "objects": names})
        if source_island is not None:
            placements[-1]["source_island_binding"] = source_island
            placements[-1]["actual_replacement_bounds_world_m"] = [[x-radius, y-radius, z+.008],
                                                                   [x+radius, y+radius, z+.008+info["height_m"]*scale]]
        occupied.add((x, y, radius), [x-radius, y-radius, x+radius, y+radius])
        total_triangles += info["triangles"]
        source_part_count += len(names)
        return True

    removed, modified, replacement_receipts = [], [], []
    pot_deletions, replaced_pots = {}, []
    # Only the seven source-bound coarse leaf ellipsoids change. Original
    # shaped flower heads remain, nestled in the real fern-frond canopy.
    for pot in source_pots:
        x, y, z = pot["position_m"]
        scale = pot["scale"]
        start = len(placements)
        for side in (-1, 1):
            place("fern_02", x+side*.055*scale, y, "retained_source_flowerpot_leaf_replacement", pot["id"],
                  height=.42*scale, max_radius=.32*scale, planter_z=z+.48*scale)
        if len(placements) == start:
            continue
        ob = pot["foliage_object"]
        entry = pot_deletions.setdefault(ob.name, {"object": ob, "vertices": [], "pots": [],
                                                   "source_geometry_sha256": pot["source_geometry_sha256"]})
        entry["vertices"].extend(pot["vertices"])
        entry["pots"].append(pot["id"])
        replaced_pots.append({"id": pot["id"], "protected_pot_object": pot["pot_object"],
                              "protected_shaped_flower_objects": pot["protected_shaped_flower_objects"],
                              "removed_exact_leaf_components": 7,
                              "new_placements": [p["id"] for p in placements[start:]]})
    # First-floor window boxes have a separate exact source recipe. Rebuild
    # just their nine primitive flower/leaf components, after all three real
    # flower clumps fit inside the protected .92 x .38m terracotta box rim.
    # These batches never include doors, opaque walls or window hardware.
    window_deletions = {}
    for box in window_boxes:
        start = len(placements)
        for offset in (-.28, 0., .28):
            x, y = _world(box["row"], box["local_x"]+offset, box["local_y"])
            place("celandine_01", x, y, "retained_elevated_window_box", box["id"],
                  height=.27, max_radius=.13, planter_z=box["base_z_m"])
        if len(placements)-start != 3:
            # Never erase the source flowers when the real replacements did
            # not fit the current explicit triangle/instance budget.
            for record in placements[start:]:
                for name in record["objects"]:
                    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
                key = record["source_asset"], record["source_variant"], record["lod"]
                total_triangles -= prototype_info[key]["triangles"]
                source_part_count -= len(record["objects"])
            del placements[start:]
            rejected["window_box_replacement_incomplete_preserved_original"] += 1
            continue
        for source in box["foliage"]:
            name = source["object"].name
            entry = window_deletions.setdefault(name, {**source, "vertices": [], "boxes": [], "placements": []})
            entry["vertices"].extend(source["vertices"])
            entry["boxes"].append(box["pot_object"])
            entry["placements"].extend(p["id"] for p in placements[start:])
    for name, entry in window_deletions.items():
        import bmesh
        ob = entry["object"]
        if ob.data.users > 1:
            ob.data = ob.data.copy()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(entry["vertices"]))], context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
        replacement_receipts.append({"source_object": name, "source_geometry_sha256": entry["source_geometry_sha256"],
                                     "exact_source_recipe": "build_living_town.building first-floor window box",
                                     "removed_source_vertices": len(set(entry["vertices"])),
                                     "protected_terracotta_box_objects": sorted(set(entry["boxes"])),
                                     "new_placements": entry["placements"],
                                     "replacement_geometry_inside_source_box_rim": True})
        if not ob.data.vertices:
            bpy.data.objects.remove(ob, do_unlink=True)
            removed.append(name)
        else:
            modified.append(name)
    # Source factory separates pot/foliage by material. Replace only its known
    # primitive foliage and keep the actual terracotta pot geometry untouched.
    for ident, group in sorted(planter_groups.items()):
        pot = next((o for o in group if any(_source_key(s.material) == "Terracotta" for s in o.material_slots if s.material)), None)
        foliage = [o for o in group if o.name in mutable_names]
        if pot is None or not foliage:
            continue
        x, y, z = pot.location
        start = len(placements)
        for j in range(3):
            angle = j*2.39996+(.3 if len(placements) % 2 else 0)
            rr = .065 if j else 0
            place("celandine_01", x+math.cos(angle)*rr, y+math.sin(angle)*rr,
                  "retained_terracotta_planter", ident, height=rng.uniform(.32, .46), max_radius=.23,
                  planter_z=z+.345*pot.scale.z)
        if len(placements) == start:
            continue
        old_names = []
        for ob in foliage:
            replacement_receipts.append({"source_object": ob.name, "source_mesh": ob.data.name,
                                          "source_geometry_sha256": _mesh_hash(ob.data),
                                          "protected_pot": pot.name, "new_placements": [p["id"] for p in placements[start:]]})
            old_names.append(ob.name)
            bpy.data.objects.remove(ob, do_unlink=True)
        removed.extend(old_names)

    accepted_anchors = []
    for index, anchor in enumerate(old_anchors):
        x, y = anchor[:2]
        start = len(placements)
        # One meaningful textured clump reaches every old island before extra
        # layering can consume the budget in only the first part of the map.
        # Reserve fern masses, pale heath and vegetable-bed leaves have exact
        # source material identities, so they receive distinct source forms.
        asset = "celandine_01" if anchor[3] == "LeafSilver" else "grass_medium_01" if anchor[3] == "LeafLight" else "fern_02"
        place(asset, x, y, "preserved_soil_and_stone_bed", "legacy_bed_"+str(index),
              max_radius=.46, height=.48 if asset == "fern_02" else .32)
        if len(placements) > start:
            accepted_anchors.append((x, y, index))
    for x, y, index in accepted_anchors:
        for asset, offset in (("celandine_01", (.32, -.14)), ("grass_medium_01", (-.35, .16))):
            place(asset, x+offset[0], y+offset[1], "layered_retained_garden_bed", "legacy_bed_"+str(index),
                  max_radius=.25, height=.26)
    # Delete only connected foliage components associated with an actually
    # replaced source island. Unmatched source plants remain explicitly intact.
    old_anchor_index = Spatial(1.)
    for index, anchor in enumerate(old_anchors):
        old_anchor_index.add((anchor[0], anchor[1], index), [anchor[0], anchor[1], anchor[0], anchor[1]])
    accepted_anchor_ids = {anchor[2] for anchor in accepted_anchors}
    for entry in eligible:
        ob = entry["object"]
        indices, replaced_components = [], 0
        for component in entry["components"]:
            center = component["center_m"]
            near = [anchor for anchor in old_anchor_index.near(center[0], center[1], .72)
                    if math.dist(center[:2], anchor[:2]) < .72]
            nearest = min(near, key=lambda a: math.dist(center[:2], a[:2])) if near else None
            if nearest and nearest[2] in accepted_anchor_ids:
                indices.extend(component["vertices"])
                replaced_components += 1
        pot_entry = pot_deletions.pop(ob.name, None)
        if pot_entry:
            indices.extend(pot_entry["vertices"])
        if not indices:
            continue
        import bmesh
        if ob.data.users > 1:
            ob.data = ob.data.copy()
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(indices))], context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
        name = ob.name
        replacement_receipts.append({"source_object": name, "source_geometry_sha256": entry["source_geometry_sha256"],
                                      "source_foliage_components": len(entry["components"]),
                                      "replaced_foliage_components": replaced_components,
                                      "preserved_components": len(entry["components"])-replaced_components,
                                      "source_flowerpots_leaf_replaced": pot_entry["pots"] if pot_entry else [],
                                      "preserved_soil_and_masonry": True})
        if not ob.data.vertices:
            bpy.data.objects.remove(ob, do_unlink=True)
            removed.append(name)
        else:
            modified.append(name)
    for name, entry in pot_deletions.items():
        # Civic/study flower pots share a public furniture batch and never
        # enter the ground-bed replacement path above.
        import bmesh
        ob = entry["object"]
        if ob.data.users > 1:
            ob.data = ob.data.copy()
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(entry["vertices"]))], context="VERTS")
        bm.to_mesh(ob.data); bm.free(); ob.data.update()
        replacement_receipts.append({"source_object": name, "source_geometry_sha256": entry["source_geometry_sha256"],
                                      "source_flowerpots_leaf_replaced": entry["pots"],
                                      "removed_exact_source_leaf_vertices": len(set(entry["vertices"])),
                                      "all_pots_and_shaped_flowerheads_preserved": True})
        if not ob.data.vertices:
            bpy.data.objects.remove(ob, do_unlink=True); removed.append(name)
        else:
            modified.append(name)

    # Complete the exact old bed replacement even where conservative NEW
    # planting masks rejected an inset bed. Each remaining original ellipsoid
    # grants only its own measured 3D volume; threshold clearance still wins.
    # This cannot authorize planting elsewhere on paving or inside a parcel.
    contained_receipts, unmatched_green, contained_removed, contained_replaced = [], [], 0, 0
    def component_records(ob):
        groups = _components(ob.data)
        owner = {v: index for index, group in enumerate(groups) for v in group}
        polygons = defaultdict(list)
        for polygon in ob.data.polygons:
            polygons[owner[polygon.vertices[0]]].append(polygon)
        return [(group, polygons[index]) for index, group in enumerate(groups)]
    for name in eligible_source_names:
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        keys = {_source_key(s.material) for s in ob.material_slots if s.material}
        if not keys or not keys <= {"Leaf", "LeafLight", "LeafDark", "LeafSilver"}:
            continue
        input_hash, deletion, bodies, retained = _mesh_hash(ob.data), [], [], Counter()
        for ordinal, (indices, polygons) in enumerate(component_records(ob)):
            points = [tuple(ob.matrix_world@ob.data.vertices[i].co) for i in indices]
            recipe = _ellipsoid_recipe(points)
            binding = _source_component_binding(ob, indices, polygons)
            if recipe is None:
                # Original fine stems, fern rods and grass triangles are not
                # coarse body blobs. Their exact geometry/UVs stay unchanged.
                retained[(binding["source_geometry_sha256"], binding["source_uv_sha256"])] += 1
                if len(indices) >= 24 and polygons and all(len(p.vertices) == 4 for p in polygons):
                    unmatched_green.append({"source_object": name, "component": ordinal, **binding,
                                            "reason": "Large green primitive does not match source ellipsoid recipe; preserved for explicit review"})
                continue
            n, rings = recipe["segments"], recipe["rings"]
            remap = {v: i for i, v in enumerate(indices)}
            faces = [tuple(remap[v] for v in polygon.vertices) for polygon in polygons]
            expected_faces = [(j*n+i, j*n+(i+1) % n, (j+1)*n+(i+1) % n, (j+1)*n+i)
                              for j in range(rings) for i in range(n)]
            topology_proof = {"variant": "exact_original_quad_grid", "source_quads": len(expected_faces)} if faces == expected_faces else _triangulated_reserve_proof(ob, indices, polygons, recipe, reserve_tri_binding)
            if topology_proof is None:
                unmatched_green.append({"source_object": name, "component": ordinal, **binding,
                                        "reason": "Source ellipsoid vertex recipe matches but polygon topology changed"})
                retained[(binding["source_geometry_sha256"], binding["source_uv_sha256"])] += 1
                continue
            low, high = [min(p[k] for p in points) for k in range(3)], [max(p[k] for p in points) for k in range(3)]
            x, y = (low[0]+high[0])/2, (low[1]+high[1])/2
            island = {"source_object": name, "source_component": ordinal, **binding,
                      "bounds_world_m": [low, high], "exact_primitive_recipe": recipe,
                      "exact_topology_proof": topology_proof}
            radius = max(high[0]-low[0], high[1]-low[1])/2
            threshold = mask.threshold_reason(x, y, radius)
            start = len(placements)
            rejection_before = rejected.copy()
            if not threshold:
                asset = "grass_medium_01" if keys == {"LeafLight"} else "fern_02"
                place(asset, x, y, "exact_retained_bed_island", name+"/"+str(ordinal),
                      height=min(.68, high[2]-low[2]), source_island=island)
            new_ids = [p["id"] for p in placements[start:]]
            deletion.extend(indices)
            contained_removed += 1
            contained_replaced += bool(new_ids)
            bodies.append({**island, "new_placements": new_ids,
                           "action": "REPLACED_FULLY_INSIDE_ORIGINAL_BOUNDS" if new_ids else "REMOVED_UNSAFE_OR_UNFIT_SOURCE_FOLIAGE_WITHOUT_NEW_BLOCKER",
                           "source_threshold_conflict": threshold,
                           "replacement_rejections": dict(rejected-rejection_before)})
        if not deletion:
            continue
        import bmesh
        if ob.data.users > 1:
            ob.data = ob.data.copy()
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(set(deletion))], context="VERTS")
        bm.to_mesh(ob.data); bm.free(); ob.data.update()
        actual_retained = Counter()
        for indices, polygons in component_records(ob):
            binding = _source_component_binding(ob, indices, polygons)
            actual_retained[(binding["source_geometry_sha256"], binding["source_uv_sha256"])] += 1
        if actual_retained != retained:
            raise RuntimeError("Contained bed replacement changed protected source stem geometry/UVs: "+name)
        contained_receipts.append({"source_object": name, "input_geometry_sha256": input_hash,
                                   "output_geometry_sha256": _mesh_hash(ob.data), "islands": bodies,
                                   "preserved_other_components_geometry_and_uv": "PASS",
                                   "preserved_other_component_count": sum(retained.values()),
                                   "flowerheads_containers_soil_edging_untouched": True})
        if not ob.data.vertices:
            bpy.data.objects.remove(ob, do_unlink=True); removed.append(name)
        else:
            modified.append(name)

    # Domestic borders are intentionally asymmetric and skip front thresholds.
    for row in buildings:
        w, d = row["footprint_m"]
        if row["kind"] in ("halles", "cannery", "refuse", "maintenance", "food_truck"):
            continue
        slots = [(-w*.28, d/2+.82), (w*.28, d/2+1.10),
                 (-w/2-.82, d*.23), (w/2+.88, -d*.18)]
        if row.get("group") == "reserve":
            slots = slots[:2]
        for index, (lx, ly) in enumerate(slots):
            x, y = _world(row, lx+rng.uniform(-.18, .18), ly+rng.uniform(-.18, .18))
            asset = "fern_02" if index % 3 == 0 else "celandine_01" if index % 3 == 1 else "grass_medium_01"
            place(asset, x, y, "domestic_garden_border", row["id"], max_radius=.45)

    # Source-authored garden envelopes and park meadows receive clustered
    # flowers/ferns with visible ground between groups, not uniform lawn noise.
    landscape = documents["landscape_plan"]
    envelopes = landscape.get("gardens", [])+landscape.get("park", {}).get("flowerbeds", [])+landscape.get("meadow_polygons", [])
    for envelope in envelopes:
        polygon = envelope.get("polygon")
        center = envelope.get("center")
        radii = envelope.get("radii", envelope.get("radii_m"))
        if polygon:
            x0, x1 = min(p[0] for p in polygon), max(p[0] for p in polygon)
            y0, y1 = min(p[1] for p in polygon), max(p[1] for p in polygon)
        elif center and radii:
            x0, x1, y0, y1 = center[0]-radii[0], center[0]+radii[0], center[1]-radii[1], center[1]+radii[1]
        else:
            continue
        attempts = min(1200, max(65, int((x1-x0)*(y1-y0)*1.4)))
        for i in range(attempts):
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
            if polygon and not _inside((x, y), polygon):
                continue
            if center and radii and ((x-center[0])/radii[0])**2+((y-center[1])/radii[1])**2 > .82:
                continue
            meadow = envelope in landscape.get("meadow_polygons", [])
            asset = ("celandine_01" if i % 13 == 0 else "grass_medium_01") if meadow else "celandine_01" if i % 4 in (0, 1) else "fern_02" if i % 4 == 2 else "grass_medium_01"
            place(asset, x, y, "authored_garden_or_park_envelope", envelope["id"], max_radius=.43)

    # Public verge coverage follows real route arc-length stations. Both
    # authored exclusion masks and actual hardscape/terrain rays still apply.
    verge_candidates, verge_routes = _route_verge_candidates(mask)
    verge_start, verge_triangle_start = len(placements), total_triangles
    verge_limit = int(api.get("understory_verge_max_instances", max_instances*.52))
    verge_triangle_limit = max(0, int((triangle_budget-total_triangles)*.72))
    for candidate in verge_candidates:
        if len(placements)-verge_start >= verge_limit or total_triangles-verge_triangle_start >= verge_triangle_limit:
            break
        if place(candidate["asset"], candidate["x"], candidate["y"], "public_route_verge_drift", candidate["route_id"],
                 height=candidate["height_m"], max_radius=candidate["max_radius_m"]):
            placements[-1]["route_binding"] = {k: candidate[k] for k in ("source", "route_id", "station_m", "side", "lane")}

    # Irregular root-adjacent drifts use the already approved tree habitat.
    # Distant canopy gets fewer plants; inhabited edges receive finer coverage.
    shuffled_trees = sorted(tree_placements, key=lambda t: str(t["id"]))
    random.Random(20261020_1739).shuffle(shuffled_trees)
    for tree in shuffled_trees:
        near = tree.get("lod") == "near"
        if rng.random() > (.82 if near else .42):
            continue
        x, y, z = tree["position_m"]
        count = rng.randrange(3, 6) if near else rng.randrange(1, 4)
        phase = rng.uniform(0, math.tau)
        shade = tree.get("species", "") not in ("maritime_pine", "scots_pine", "pine")
        for i in range(count):
            angle = phase+i*2.399963+rng.uniform(-.36, .36)
            distance = rng.uniform(.85, 2.75 if near else 3.30)
            xx, yy = x+math.cos(angle)*distance, y+math.sin(angle)*distance
            asset = "fern_02" if shade and i % 3 != 1 else "grass_medium_01" if i % 3 != 2 else "celandine_01"
            place(asset, xx, yy, "woodland_root_drift", tree["id"], max_radius=.62)
        if len(placements) >= max_instances or total_triangles >= triangle_budget-2200:
            break
    protection_failures = []
    for name, signature in protected.items():
        ob = bpy.data.objects.get(name)
        if ob is None or _protected_signature(ob) != signature:
            protection_failures.append(name)
    if protection_failures:
        raise RuntimeError("Understory altered protected ancestry geometry: "+json.dumps(protection_failures[:20]))
    return {"schema": OWNER, "status": "BUILT_REQUIRES_VISUAL_REVIEW", "instance_count": len(placements),
            "mesh_objects_added": source_part_count, "placed_triangles": total_triangles,
            "triangle_budget": triangle_budget, "instance_budget": max_instances,
            "asset_counts": dict(Counter(p["source_asset"] for p in placements)),
            "habitat_counts": dict(Counter(p["habitat"] for p in placements)),
            "source_variants": [{"asset": key[0], "variant": key[1], "lod": key[2], **value} for key, value in prototype_info.items()],
            "input_bindings": {key: {"path": str(path.resolve()), "sha256": _sha(path)} for key, path in paths.items()},
            "tool_sha256": _sha(__file__), "rejection_counts": dict(rejected),
            "actual_hardscape_meshes_checked": hardscape_count, "placements": placements,
            "removed_object_names": sorted(removed), "modified_object_names": sorted(modified),
            "replacement_receipts": replacement_receipts,
            "source_bound_window_boxes": len(window_boxes),
            "window_box_binding_failures": window_box_binding_failures,
            "source_flowerpot_leaf_replacement": {"binding": pot_binding, "source_pot_count": len(source_pots),
                                                    "replaced_pot_count": len(replaced_pots), "pots": replaced_pots,
                                                    "source_binding_failures": source_pot_failures,
                                                    "policy": "Only all-seven exact source leaf ellipsoids replaced; original pot rods and shaped flower heads preserved."},
            "public_route_verge_coverage": {"routes": verge_routes, "candidates": len(verge_candidates),
                                            "placed_instances": sum(p["habitat"] == "public_route_verge_drift" for p in placements),
                                            "instance_stage_budget": verge_limit, "triangle_stage_budget": verge_triangle_limit,
                                            "policy": "0.8–1.4m arc-length stations, two irregular outside-edge drifts; full masks/native hardscape/slope/threshold checks; source-shuffled order across all public routes."},
            "woodland_budget_order": {"seed": 20261020_1739, "tree_count": len(shuffled_trees),
                                      "policy": "Stable-ID sort then deterministic shuffle; existing beds before public route verges before woodland."},
            "eligible_legacy_bed_prefixes": list(LEGACY_BED_PREFIXES),
            "contained_source_bed_completion": {"status": "PASS" if not unmatched_green else "REQUIRES_SOURCE_REVIEW",
                                                 "bound_reserve_triangulation_source": reserve_tri_binding,
                                                 "original_coarse_body_components_removed": contained_removed,
                                                 "body_components_replaced_inside_exact_source_bounds": contained_replaced,
                                                 "unsafe_or_unfit_components_removed_without_replacement": contained_removed-contained_replaced,
                                                 "unmatched_large_green_components": unmatched_green,
                                                 "objects": contained_receipts,
                                                 "policy": "Only exact source ellipsoid vertices+topology; each original measured 3D box is the entire replacement scope. Full source threshold clearance retained. Global new-planting masks unchanged; Bloom flowerhead geometry is excluded from this completion stage."},
            "legacy_bed_coverage": {"source_anchor_count": len(old_anchors), "replaced_anchor_count": len(accepted_anchors),
                                    "retained_anchor_count": len(old_anchors)-len(accepted_anchors),
                                    "policy": "One actual textured source clump per safe old island before secondary layering; unsafe or over-budget islands retain original foliage."},
            "ancestry_geometry_protection": {"status": "PASS", "protected_objects": len(protected),
                "changed_protected_objects": [], "signature": "Object identity/data pointer, vertex/polygon counts and exact world matrix; this helper performs no writes to protected mesh geometry.",
                "preserved": ["all 151 building roots and interior geometry", "roads, trails, bridge/stair surfaces and utilities", "terrain, graded pond banks, water and coastline", "detailed hydrangea and upstream planter prototypes", "existing terracotta pots, garden soil and stone boundaries", "rebuilt botanical trees and source prototype meshes"]},
            "limits": ["Vegetation habitat labels are artistic planting intent; source_asset is the actual licensed botanical mesh identity.",
                       "No source flower is promoted to a different botanical species or seasonal survey claim.",
                       "Existing planters may stand on paving; only their contained primitive foliage is replaced, after threshold checks.",
                       "Placement uses authored masks plus actual hardscape vertical ray tests and terrain slope samples; final native images/gameplay remain required.",
                       "No new pots, terrain edits or invisible flat-ground fallback are authored."]}
