"""Remove source-bound static person() primitives from mixed public batches.

The live Blender owner calls apply(api, output). This helper opens no engine,
scene or export. It parses the current canonical person() recipe and its two
authored placement loops, requires all nine native primitives per figure, and
only then removes their exact connected components. Unmatched geometry causes
a transaction-wide rejection. Importing this module is engine-free.
"""
from __future__ import annotations

from array import array
import ast
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path


SCHEMA = "living_town.source_bound_scale_figure_removal.v1"
PREFIXES = ("Civic_Square_and_Summer_Life", "Everyday_StreetFurniture")
SHIRTS = ("Shirt", "Sage", "BluePaint", "Burgundy")
MATERIALS = ("Skin", "Hair", "Trousers", "Ink", *SHIRTS)
TOLERANCE_M = .00015


def _sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _ast_sha(node):
    return hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest()


def _source_specs(path):
    source = Path(path).read_text(encoding="utf-8-sig")
    tree = ast.parse(source)
    recipe = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "person")
    batch = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Batch")
    primitive_bindings = {n.name: _ast_sha(n) for n in batch.body if isinstance(n, ast.FunctionDef)
                          and n.name in ("poly", "box", "rod", "ellipsoid")}
    specs = []
    for loop in ast.walk(tree):
        if not isinstance(loop, ast.For):
            continue
        calls = [n.value for n in loop.body if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
                 and isinstance(n.value.func, ast.Name) and n.value.func.id == "person"]
        if not calls:
            continue
        if len(calls) != 1 or len(calls[0].args) != 4 or calls[0].keywords:
            raise ValueError("Static figure call recipe changed; explicit source review required")
        call = calls[0]
        if not isinstance(call.args[0], ast.Name):
            raise ValueError("Static figure batch is not an authored local name")
        variable = call.args[0].id
        assignments = [n for n in ast.walk(tree) if isinstance(n, ast.Assign) and n.lineno < loop.lineno
                       and any(isinstance(t, ast.Name) and t.id == variable for t in n.targets)
                       and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name)
                       and n.value.func.id == "Batch" and n.value.args
                       and isinstance(n.value.args[0], ast.Constant)]
        if not assignments:
            raise ValueError("No exact source Batch constructor for static figures")
        assignment = max(assignments, key=lambda n: n.lineno)
        prefix = assignment.value.args[0].value
        if prefix not in PREFIXES:
            raise ValueError("Unexpected static figure owner batch: "+str(prefix))
        if not isinstance(loop.target, (ast.Tuple, ast.List)) or len(loop.target.elts) != 2:
            raise ValueError("Static figure XY source loop changed")
        variables = [n.id for n in loop.target.elts if isinstance(n, ast.Name)]
        if len(variables) != 2 or any(not isinstance(n, ast.Name) or n.id != variable
                                      for n, variable in zip(call.args[1:3], variables)):
            raise ValueError("Static figure XY arguments differ from authored anchors")
        anchors = ast.literal_eval(loop.iter)
        if len(anchors) != 12 or any(len(p) != 2 for p in anchors):
            raise ValueError("Static figure source anchor count changed")
        specs.append({"prefix": prefix, "anchors_xy_m": anchors, "line": loop.lineno,
                      "placement_loop_ast_sha256": _ast_sha(loop),
                      "ground_expression": ast.get_source_segment(source, call.args[3])})
    if Counter(s["prefix"] for s in specs) != Counter(PREFIXES):
        raise ValueError("Expected one exact canonical person loop in each approved public batch")
    # Only this named function is compiled. It receives an inert geometry
    # recorder and deterministic symbolic shirt choice, never Blender globals.
    namespace = {"RNG": _ShirtChoice()}
    module = ast.Module(body=[recipe], type_ignores=[])
    exec(compile(ast.fix_missing_locations(module), str(path), "exec"), namespace)
    return namespace["person"], specs, {"path": str(Path(path).resolve()), "sha256": _sha(path),
                                      "person_function_line": recipe.lineno,
                                      "person_function_ast_sha256": _ast_sha(recipe),
                                      "batch_primitive_ast_sha256": primitive_bindings}


class _ShirtChoice:
    def choice(self, values):
        if tuple(values) != SHIRTS:
            raise ValueError("Source person() shirt alternatives changed")
        return "__SHIRT__"


def _sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def _cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def _unit(a):
    length = math.sqrt(sum(x*x for x in a))
    return tuple(x/length for x in a)


class _Recorder:
    """Canonical Batch primitive geometry; no Blender or scene side effects."""
    def __init__(self):
        self.parts = []

    def _append(self, vertices, faces, material):
        self.parts.append({"vertices": vertices, "faces": faces, "material": material,
                           "materials": SHIRTS if material == "__SHIRT__" else (material,)})

    def ellipsoid(self, p, r, material, n=10, rings=6):
        vertices = []
        for j in range(rings+1):
            latitude = -math.pi/2+math.pi*j/rings
            for i in range(n):
                angle = i*math.tau/n
                vertices.append((p[0]+r[0]*math.cos(latitude)*math.cos(angle),
                                 p[1]+r[1]*math.cos(latitude)*math.sin(angle), p[2]+r[2]*math.sin(latitude)))
        faces = [(j*n+i, j*n+(i+1) % n, (j+1)*n+(i+1) % n, (j+1)*n+i)
                 for j in range(rings) for i in range(n)]
        self._append(vertices, faces, material)

    def rod(self, p0, p1, r, material, n=10, r2=None):
        d = _unit(_sub(p1, p0))
        a = _cross(d, (0, 0, 1))
        if math.sqrt(sum(x*x for x in a)) < .01:
            a = _cross(d, (0, 1, 0))
        a = _unit(a)
        b = _cross(d, a)
        vertices = [tuple(p[k]+radius*(a[k]*math.cos(i*math.tau/n)+b[k]*math.sin(i*math.tau/n)) for k in range(3))
                    for p, radius in ((p0, r), (p1, r if r2 is None else r2)) for i in range(n)]
        faces = [tuple(range(n-1, -1, -1)), tuple(range(n, 2*n))]
        faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
        self._append(vertices, faces, material)

    def box(self, position, size, material, rot=0):
        x, y, z = position
        a, b, c = (v/2 for v in size)
        co, si = math.cos(rot), math.sin(rot)
        vertices = [(x+dx*co-dy*si, y+dx*si+dy*co, z+dz) for dx, dy, dz in
                    ((-a, -b, -c), (a, -b, -c), (a, b, -c), (-a, b, -c),
                     (-a, -b, c), (a, -b, c), (a, b, c), (-a, b, c))]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self._append(vertices, faces, material)


def _components(ob):
    mesh = ob.data
    parent = list(range(len(mesh.vertices)))
    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index
    for edge in mesh.edges:
        a, b = map(root, edge.vertices)
        parent[a] = b
    grouped = defaultdict(list)
    for index in range(len(parent)):
        grouped[root(index)].append(index)
    polygon_groups = defaultdict(list)
    for polygon in mesh.polygons:
        polygon_groups[root(polygon.vertices[0])].append(polygon)
    result = []
    for key, indices in grouped.items():
        mapping = {old: new for new, old in enumerate(indices)}
        polygons = polygon_groups.get(key, [])
        points = [tuple(ob.matrix_world@mesh.vertices[i].co) for i in indices]
        result.append({"indices": indices, "points": points,
                       "faces": [tuple(mapping[i] for i in p.vertices) for p in polygons],
                       "polygons": polygons,
                       "bounds": [[min(p[k] for p in points) for k in range(3)],
                                  [max(p[k] for p in points) for k in range(3)]]})
    return result


def _component_hash(ob, component):
    digest = hashlib.sha256(array("f", [v for p in component["points"] for v in p]).tobytes())
    for face in component["faces"]:
        digest.update(array("i", [len(face), *face]).tobytes())
    for polygon in component["polygons"]:
        digest.update(array("i", [polygon.material_index]).tobytes())
        for uv in ob.data.uv_layers:
            digest.update(uv.name.encode())
            digest.update(array("f", [v for li in polygon.loop_indices for v in uv.data[li].uv]).tobytes())
    return digest.hexdigest()


def _fingerprint(ob):
    coordinates = array("f", [0.])*(len(ob.data.vertices)*3)
    indices = array("i", [0])*len(ob.data.loops)
    ob.data.vertices.foreach_get("co", coordinates)
    ob.data.loops.foreach_get("vertex_index", indices)
    digest = hashlib.sha256(coordinates.tobytes()+indices.tobytes())
    digest.update(array("i", [len(p.vertices) for p in ob.data.polygons]).tobytes())
    matrix = [list(r) for r in ob.matrix_world]
    digest.update(json.dumps(matrix).encode())
    return {"geometry_sha256": digest.hexdigest(), "mesh": ob.data.name,
            "vertices": len(ob.data.vertices), "polygons": len(ob.data.polygons), "matrix_world": matrix,
            "uv_layers": {uv.name: hashlib.sha256(array("f", [v for p in uv.data for v in p.uv]).tobytes()).hexdigest()
                          for uv in ob.data.uv_layers},
            "material_slots": [slot.material.name if slot.material else None for slot in ob.material_slots]}


def _matches(actual, expected):
    if len(actual["points"]) != len(expected["vertices"]) or actual["faces"] != expected["faces"]:
        return False
    return max(abs(a-b) for point, target in zip(actual["points"], expected["vertices"])
               for a, b in zip(point, target)) <= TOLERANCE_M


def apply(api, output):
    bpy = api["bpy"]
    baseline = Path(api.get("baseline_root", Path(__file__).resolve().parents[2]/"art/living_town"))
    recipe, specs, source_binding = _source_specs(baseline/"tools/build_living_town.py")
    objects, components, before, retained_before = {}, {}, {}, {}
    for prefix in PREFIXES:
        for material in MATERIALS:
            ob = bpy.data.objects.get(prefix+"_"+material)
            if ob is None:
                continue
            if ob.type != "MESH":
                raise ValueError("Approved source public batch is not a mesh: "+ob.name)
            objects[ob.name] = ob
            components[ob.name] = _components(ob)
            before[ob.name] = _fingerprint(ob)
    protected_public = {ob.name: _fingerprint(ob) for ob in bpy.context.scene.objects
                        if ob.type == "MESH" and ob.name.startswith(tuple(p+"_" for p in PREFIXES))
                        and ob.name not in objects}
    figures, failures, delete = [], [], defaultdict(set)
    present_prefixes = {prefix for prefix in PREFIXES if any(name.startswith(prefix+"_") for name in objects)}
    for spec in specs:
        prefix = spec["prefix"]
        if prefix not in present_prefixes:
            continue
        for index, (x, y) in enumerate(spec["anchors_xy_m"]):
            ident = prefix+f"_SourceScaleFigure_{index:02d}"
            # Exact 48-vertex source head identifies the shared base Z. Every
            # other primitive must then match the same complete source pose.
            zero = _Recorder(); recipe(zero, x, y, 0)
            head = zero.parts[0]
            head_candidates = []
            for component in components.get(prefix+"_Skin", []):
                if len(component["points"]) != len(head["vertices"]):
                    continue
                low, high = component["bounds"]
                if abs((low[0]+high[0])/2-x) > TOLERANCE_M or abs((low[1]+high[1])/2-y) > TOLERANCE_M:
                    continue
                z = (low[2]+high[2])/2-1.53
                expected = _Recorder(); recipe(expected, x, y, z)
                if _matches(component, expected.parts[0]):
                    head_candidates.append((z, expected))
            if len(head_candidates) != 1:
                failures.append({"figure_id": ident, "reason": "Exact source head missing or ambiguous", "head_matches": len(head_candidates)})
                continue
            z, expected = head_candidates[0]
            matched, local_failures, used = [], [], set()
            for part_index, part in enumerate(expected.parts):
                hits = [(prefix+"_"+material, cindex, component) for material in part["materials"]
                        for cindex, component in enumerate(components.get(prefix+"_"+material, []))
                        if _matches(component, part)]
                if len(hits) != 1 or hits[0][:2] in used:
                    local_failures.append({"part": part_index, "allowed_materials": list(part["materials"]), "matches": len(hits)})
                    continue
                name, component_index, component = hits[0]
                used.add((name, component_index))
                matched.append({"part": part_index, "source_object": name, "component_index": component_index,
                                "vertices": len(component["indices"]), "polygons": len(component["faces"]),
                                "actual_bounds_world_m": component["bounds"],
                                "maximum_source_vertex_deviation_m": max(abs(a-b) for actual, target in zip(component["points"], part["vertices"])
                                                                           for a, b in zip(actual, target)),
                                "geometry_and_uv_sha256": _component_hash(objects[name], component)})
            if len(expected.parts) != 9 or local_failures:
                failures.append({"figure_id": ident, "reason": "Incomplete or ambiguous exact source figure; no partial removal", "parts": local_failures})
                continue
            for name, component_index in used:
                delete[name].update(components[name][component_index]["indices"])
            figures.append({"id": ident, "source_prefix": prefix, "source_anchor_xy_m": [x, y],
                            "source_base_z_inferred_from_exact_head_m": z, "parts": matched,
                            "status": "VERIFIED_ALL_NINE_SOURCE_COMPONENTS"})
    # Strict preflight across all present batches: a changed pose/source never
    # leaves a partially erased static person or removes nearby public props.
    removed, modified, after, preservation = [], [], {}, []
    if not failures:
        import bmesh
        for name, indices in delete.items():
            ob = objects[name]
            keep = [c for c in components[name] if not set(c["indices"]) & indices]
            retained_before[name] = Counter(_component_hash(ob, c) for c in keep)
            if ob.data.users > 1:
                ob.data = ob.data.copy()
            bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(indices)], context="VERTS")
            bm.to_mesh(ob.data); bm.free(); ob.data.update()
            if ob.data.vertices:
                after[name] = _fingerprint(ob)
                retained_after = Counter(_component_hash(ob, c) for c in _components(ob))
                passed = retained_after == retained_before[name] and before[name]["matrix_world"] == after[name]["matrix_world"]
                modified.append(name)
            else:
                after[name] = {"object_removed": True, "vertices": 0, "polygons": 0}
                retained_after, passed = Counter(), not retained_before[name]
                bpy.data.objects.remove(ob, do_unlink=True)
                removed.append(name)
            preservation.append({"object": name, "status": "PASS" if passed else "FAIL",
                                 "protected_remaining_components": sum(retained_before[name].values()),
                                 "before_component_fingerprints": dict(retained_before[name]),
                                 "after_component_fingerprints": dict(retained_after)})
            if not passed:
                raise RuntimeError("Static figure cleanup altered protected furniture geometry/UVs: "+name)
        for figure in figures:
            figure["status"] = "REMOVED_EXACT_SOURCE_COMPONENTS"
    for name, ob in objects.items():
        if name not in after:
            after[name] = _fingerprint(ob)
    protected_after = {name: _fingerprint(bpy.data.objects[name]) if bpy.data.objects.get(name) else None
                       for name in protected_public}
    if protected_after != protected_public:
        raise RuntimeError("Static figure cleanup altered protected public batch geometry")
    report = {"schema": SCHEMA, "status": "REJECTED_NO_MUTATIONS" if failures else "PASS" if figures else "NOT_PRESENT",
              "tool_sha256": _sha(__file__), "source_binding": source_binding, "source_placement_specs": specs,
              "present_source_prefixes": sorted(present_prefixes), "absent_source_prefixes": sorted(set(PREFIXES)-present_prefixes),
              "figure_count_removed": 0 if failures else len(figures), "removed_figure_ids": [] if failures else [f["id"] for f in figures],
              "removed_object_names": removed, "modified_object_names": modified,
              "input_geometry": before, "output_geometry": after,
              "protected_public_batches": {"status": "PASS", "input_geometry": protected_public,
                                           "output_geometry": protected_after},
              "retained_public_geometry_and_uv_checks": preservation, "figures": figures, "failures": failures,
              "matching_tolerance_m": TOLERANCE_M,
              "policy": "Only nine exact connected source primitives at each literal authored XY anchor; one of four authored shirt materials; all present figures verified before any mutation. Other public objects, furniture, pots, boats, lamps and Ink components retained with component geometry+UV fingerprints.",
              "scene_or_engine_opened": False, "runtime_residents_added": False}
    destination = Path(output)
    if destination.suffix.lower() != ".json":
        destination.mkdir(parents=True, exist_ok=True)
        destination = destination/"scale_figure_removal_receipt.json"
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    return report
