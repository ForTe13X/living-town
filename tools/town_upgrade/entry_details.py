"""Bounded, source-bound entry corrections for a derivative of native V14.

No engine is imported on ordinary import. The Blender owner calls
``apply({'bpy': bpy}, fresh_output, buildings, source_furniture)``. This changes
three civic tables/six chairs, one keyed bathhouse wayfinding assembly and the
DOUCHES font size/outset. It never saves, opens or exports a scene.

Proposed actual pilot (ONLY the coordinating owner runs this):
  blender -b <immutable V14>/refined_whole_town.blend -P tools/town_upgrade/entry_details.py -- --pilot-output <fresh directory>
The explicit pilot performs apply, the existing native audit, then saves a COPY
in that fresh directory. A successful receipt establishes scoped geometry
preservation; actual oblique/runtime art and route review remain outstanding.
The original native file, source recipes and furniture baseline stay immutable.
"""
from __future__ import annotations

from array import array
import ast
from collections import Counter
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = 'living_town.source_bound_entry_details.v1'
NATIVE_SHA256 = '59680e9c67b184eb607430ad84b26eef780109c6420073156c0740d1193b10eb'
SOURCE_HASHES = {
    'art/living_town/tools/build_living_town.py': '41a59245afb3fc02789f1dfd2482c68c1b3282b029cd1087f177b8c3c699894d',
    'art/living_town/tools/reserve_environment.py': '520dbaef6f66dbef33dc83dda2d0d67c8dd6021f96f08f01c869ca5daae37030',
    'art/living_town/tools/reserve_amenities.py': '4187108afffea6843ab4ee62a67289f8d39a514c8714504d0f6ca01747f3b46b',
    'art/living_town/masterplan.json': 'b7e5522f62f4a390faa95502537fbbac14856cb278bccb695fbd5cabe186377f',
    'art/living_town/reserve_plan.json': '6841fdb5121e78372e9ccc80a990cb93b5acd7700db3f2661df2718b7e2980f7',
    'tools/town_upgrade/scale_figures.py': 'fda9f497d3a0ce586d1953c8b777137856cfb5eff36804522e632240248e3e59',
    'tools/town_upgrade/building_native_audit.py': 'fb562e779c3f9b366a50c6dc90c470d211264c18d30ed883fa69782f35933a19',
}
RECORD_HASHES = {
    'whole_town_buildings.json': '2ffec0c996de735cd31035b2d5ad322a8ddba9e55d73fa5e81ce949aa0cbd125',
    'source_furniture_geometry.json': 'eb650a64b89c848a9697aee978baa9d414cabe3fd2d6e348f3c5306b7192a97e',
}
CIVIC = 'Civic_Square_and_Summer_Life'
WAYFINDING = 'Reserve_Trailside_Rest_and_Wayfinding'
SIGN = 'Reserve_Bathhouse_SignText'
BACKING = 'Reserve_Bathhouse_Facade_Attachments_Sage'
TABLE_YS = (-3.3, 0., 3.3)
NEW_MIDDLE_XY = (2.3, 1.65)
# Ten centimetres west avoids the courtyard/paving crease under one chair.
NEW_UPPER_XY = (4.4, 3.3)
OLD_POST_XY = (-130.55, -78.)
NEW_POST_XY = (-130.55, -80.)
TOLERANCE_M = .00015
MAX_SUPPORT_GAP_M = .030
_HELPER = None


def _sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def _helper():
    global _HELPER
    if _HELPER is None:
        _HELPER = _load('entry_source_components', ROOT/'tools/town_upgrade/scale_figures.py')
    return _HELPER


def _read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                                     allow_nan=False).encode()).hexdigest()


def _bound_sources(repo=ROOT):
    """No changed source is executed, even when its geometry might still match."""
    bindings = {}
    for relative, expected in SOURCE_HASHES.items():
        path = Path(repo)/relative
        actual = _sha(path)
        if actual != expected:
            raise ValueError('Entry source binding mismatch: '+relative)
        bindings[relative] = {'path': str(path.resolve()), 'sha256': actual}
    return bindings


def _recipes(repo=ROOT):
    bindings = _bound_sources(repo)
    core = Path(repo)/'art/living_town/tools/build_living_town.py'
    tree = ast.parse(core.read_text(encoding='utf-8-sig'))
    functions = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
    namespace = {'math': math}
    # Only two already hash-checked pure functions receive an inert recorder.
    module = ast.Module(body=[functions['table'], functions['chair']], type_ignores=[])
    exec(compile(ast.fix_missing_locations(module), str(core), 'exec'), namespace)
    plan = _read(Path(repo)/'art/living_town/reserve_plan.json')
    paths = [p for p in plan['paths'] if p['id'] == 'Reserve_Bathhouse_Approach']
    if len(paths) != 1 or paths[0]['width_m'] != 1.5 or paths[0]['points_m'][0][:2] != [-132.5, -78.]:
        raise ValueError('Keyed bathhouse approach source differs')
    return namespace['table'], bindings


def _table_parts(table, x, y, z):
    recorder = _helper()._Recorder()
    table(recorder, x, y, z, .52)
    expected = Counter({'White': 3, 'Iron': 14, 'Sage': 1, 'Oak': 32, 'Linen': 14})
    if len(recorder.parts) != 64 or Counter(p['material'] for p in recorder.parts) != expected:
        raise ValueError('Bound patio primitive budget differs')
    return recorder.parts


def _post_parts(z):
    recorder = _helper()._Recorder()
    x, y = OLD_POST_XY
    recorder.rod((x, y, z), (x, y, z+1.6), .07, 'Oak', n=6)
    recorder.box((x, y, z+1.42), (.82, .08, .25), 'Sage')
    recorder.box((x, y-.05, z+1.42), (.56, .015, .025), 'White')
    return recorder.parts


def _bounds(points):
    return [[min(p[k] for p in points) for k in range(3)],
            [max(p[k] for p in points) for k in range(3)]]


def _close(a, b, tolerance=TOLERANCE_M):
    return len(a) == len(b) and all(abs(x-y) <= tolerance for x, y in zip(a, b))


def _part_match(component, part):
    return _helper()._matches(component, part)


def _find_base_z(components, name, zero_part, label):
    candidates = []
    for component in components.get(name, []):
        if len(component['points']) != len(zero_part['vertices']):
            continue
        z = component['points'][0][2]-zero_part['vertices'][0][2]
        expected = {'vertices': [(p[0], p[1], p[2]+z) for p in zero_part['vertices']],
                    'faces': zero_part['faces']}
        if _part_match(component, expected):
            candidates.append(z)
    if len(candidates) != 1:
        raise ValueError(f'{label}: expected one source anchor; found {len(candidates)}')
    return candidates[0]


def _rotate(point, center, angle):
    dx, dy = point[0]-center[0], point[1]-center[1]
    co, si = math.cos(angle), math.sin(angle)
    return (center[0]+dx*co-dy*si, center[1]+dx*si+dy*co, point[2])


def _patio_point(point, part_index, old_xy, new_xy, dz=0.):
    result = point
    if part_index >= 6:
        seat = 0 if part_index < 35 else 1
        center = (old_xy[0]+(.83 if seat == 0 else -.83), old_xy[1])
        result = _rotate(point, center, math.pi/2)
    return (result[0]+new_xy[0]-old_xy[0], result[1]+new_xy[1]-old_xy[1], result[2]+dz)


def _ground(parts, transformed, base_z, support, kind):
    """Fit one rigid assembly to actual support; reject a rocking/steep placement."""
    contacts = []
    contact_cutoff = min(p[2] for part in parts for p in part['vertices'])+.010001
    for part, points in zip(parts, transformed):
        low = min(p[2] for p in part['vertices'])
        if low > contact_cutoff:
            continue
        for old, point in zip(part['vertices'], points):
            if old[2] > low+TOLERANCE_M:
                continue
            hit = support(point[0], point[1], kind)
            if not hit or not math.isfinite(hit['z']) or hit['normal'][2] < .90:
                raise ValueError('Missing or steep actual support for '+kind)
            contacts.append({'xy_m': list(point[:2]), 'old_relative_z_m': old[2]-base_z, **hit})
    if not contacts:
        raise ValueError('No source-bound foot contacts for '+kind)
    new_base = max(c['z']-c['old_relative_z_m'] for c in contacts)+.001
    gaps = [new_base+c['old_relative_z_m']-c['z'] for c in contacts]
    if min(gaps) < -.000001 or max(gaps) > MAX_SUPPORT_GAP_M:
        raise ValueError(f'Actual support cannot ground this rigid {kind} assembly within 30mm '
                         f'(measured maximum {max(gaps)*1000:.3f}mm)')
    return new_base-base_z, {'kind': kind, 'contacts': contacts, 'new_base_z_m': new_base,
                             'minimum_gap_m': min(gaps), 'maximum_gap_m': max(gaps),
                             'fit_policy': '1mm minimum clearance; at most 30mm at any source foot; rigid geometry'}


def _geometry_plan(components, table, support):
    """Pure complete recipe matching; the returned plan does not mutate a scene."""
    edits, groups, used = [], [], set()
    def select(prefix, part, label):
        name = prefix+'_'+part['material']
        matches = [(i, c) for i, c in enumerate(components.get(name, [])) if _part_match(c, part)]
        if len(matches) != 1:
            raise ValueError(f'{label}: expected one complete source primitive; found {len(matches)}')
        index, component = matches[0]
        if (name, index) in used:
            raise ValueError('Source primitive selected twice: '+label)
        used.add((name, index))
        return {'object': name, 'component': index, 'indices': component['indices'],
                'old_points': component['points'], 'faces': component['faces'], 'label': label}
    for ordinal, y in enumerate(TABLE_YS):
        old_xy = (4.5, y)
        zero = _table_parts(table, *old_xy, 0.)
        z = _find_base_z(components, CIVIC+'_White', zero[0], f'patio {ordinal} tabletop')
        parts = _table_parts(table, *old_xy, z)
        selected = [select(CIVIC, p, f'patio_{ordinal}_part_{i:02d}') for i, p in enumerate(parts)]
        new_xy = NEW_MIDDLE_XY if ordinal == 1 else NEW_UPPER_XY if ordinal == 2 else old_xy
        transformed = [[_patio_point(p, i, old_xy, new_xy) for p in e['old_points']]
                       for i, e in enumerate(selected)]
        # Each real table and chair is an independent upright rigid object.
        # Preserve their intended shapes, but fit their own feet to the graded
        # paving. The old outer sets floated 79-124mm above the actual surface.
        fits = []
        for label, first, last in (('table_and_tableware', 0, 6),
                                   ('positive_x_chair', 6, 35),
                                   ('negative_x_chair', 35, 64)):
            try:
                dz, fitted = _ground(parts[first:last], transformed[first:last], z, support, 'plaza')
            except ValueError as exc:
                raise ValueError(f'civic_patio_table_{ordinal}/{label}: {exc}') from exc
            fits.append({'assembly': label, 'first_component': first, 'component_end': last,
                         'vertical_translation_m': dz, **fitted})
            for edit, points in zip(selected[first:last], transformed[first:last]):
                edit['new_points'] = [(p[0], p[1], p[2]+dz) for p in points]
        table_base = fits[0]['new_base_z_m']
        base_offsets = [fit['new_base_z_m']-table_base for fit in fits[1:]]
        if any(abs(offset) > .05 for offset in base_offsets):
            raise ValueError('Actual patio grade changes the intended seat/table height relation by more than 50mm')
        grounding = {'kind': 'plaza', 'rigid_subassemblies': fits,
                     'minimum_gap_m': min(fit['minimum_gap_m'] for fit in fits),
                     'maximum_gap_m': max(fit['maximum_gap_m'] for fit in fits),
                     'chair_base_offsets_from_table_m': base_offsets,
                     'fit_policy': 'Each table with its tableware and each chair remains rigid; 1-30mm support gap; at most 50mm seat/table base difference'}
        edits.extend(selected)
        groups.append({'id': f'civic_patio_table_{ordinal}', 'components': 64,
                       'old_table_center_m': [*old_xy, z], 'new_table_center_m': [*new_xy, table_base],
                       'chair_rotation_delta_degrees': 90., 'table_rotation_delta_degrees': 0.,
                       'chair_front_convention': 'local -Y; both corrected fronts point toward table center',
                       'old_world_bounds_m': _bounds([p for e in selected for p in e['old_points']]),
                       'new_world_bounds_m': _bounds([p for e in selected for p in e['new_points']]),
                       'grounding': grounding})
    z = _find_base_z(components, WAYFINDING+'_Oak', _post_parts(0.)[0], 'keyed bathhouse post')
    parts = _post_parts(z)
    selected = [select(WAYFINDING, p, f'bathhouse_approach_point0_part_{i}') for i, p in enumerate(parts)]
    transformed = []
    for i, edit in enumerate(selected):
        points = [_rotate(p, OLD_POST_XY, math.pi/2) if i else p for p in edit['old_points']]
        transformed.append([(p[0]+NEW_POST_XY[0]-OLD_POST_XY[0], p[1]+NEW_POST_XY[1]-OLD_POST_XY[1], p[2]) for p in points])
    dz, grounding = _ground(parts, transformed, z, support, 'reserve')
    for edit, points in zip(selected, transformed):
        edit['new_points'] = [(p[0], p[1], p[2]+dz) for p in points]
    edits.extend(selected)
    groups.append({'id': 'Reserve_Bathhouse_Approach:point0', 'components': 3,
                   'old_post_base_m': [*OLD_POST_XY, z], 'new_post_base_m': [*NEW_POST_XY, z+dz],
                   'board_rotation_delta_degrees': 90., 'post_rotation_delta_degrees': 0.,
                   'old_world_bounds_m': _bounds([p for e in selected for p in e['old_points']]),
                   'new_world_bounds_m': _bounds([p for e in selected for p in e['new_points']]),
                   'grounding': grounding})
    if len(edits) != 195 or len(used) != 195:
        raise ValueError('Entry component budget differs')
    for edit in edits:
        edit['changed'] = any(any(abs(a-b) > 1e-10 for a, b in zip(old, new))
                              for old, new in zip(edit['old_points'], edit['new_points']))
    if sum(e['changed'] for e in edits) != 195:
        raise ValueError('Entry changed-component budget differs')
    return {'edits': edits, 'groups': groups}


def _support_sampler(bpy):
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    names = {'plaza': ('Connected_Streets_and_Pavements_Paving', 'Connected_Streets_and_Pavements_Courtyard'),
             'reserve': ('Atlantic_Terrain_Grass',)}
    trees = {}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for kind, candidates in names.items():
        trees[kind] = []
        for name in candidates:
            ob = bpy.data.objects.get(name)
            if ob is None:
                continue
            if ob.type != 'MESH' or ob.hide_render:
                raise ValueError('Actual support is not a rendered mesh: '+name)
            evaluated = ob.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            try:
                # Match the triangles Blender renders and exports. BVH's own
                # n-gon triangulation can choose a different diagonal on these
                # graded, nonplanar paving faces (measured >12cm difference).
                mesh.calc_loop_triangles()
                points = [evaluated.matrix_world@v.co for v in mesh.vertices]
                triangles = [tuple(t.vertices) for t in mesh.loop_triangles]
                tree = BVHTree.FromPolygons(points, triangles, all_triangles=True)
                origin_z = max(p.z for p in points)+1.
                polygon_indices = [t.polygon_index for t in mesh.loop_triangles]
                trees[kind].append((name, tree, origin_z, polygon_indices))
            finally:
                evaluated.to_mesh_clear()
        if not trees[kind]:
            raise ValueError('No approved actual support meshes for '+kind)
    def sample(x, y, kind):
        hits = []
        for name, tree, origin_z, polygon_indices in trees[kind]:
            point, normal, index, _distance = tree.ray_cast(Vector((x, y, origin_z)), Vector((0, 0, -1)))
            if point is not None:
                hits.append({'z': float(point.z), 'normal': list(normal), 'object': name,
                             'polygon': polygon_indices[index], 'loop_triangle': index,
                             'support_surface': 'evaluated_render_loop_triangles',
                             'ray_origin_z_m': origin_z})
        return max(hits, key=lambda h: h['z']) if hits else None
    return sample


def _plain(value):
    if value is None or isinstance(value, (str, bool, int, float)):
        return value
    if hasattr(value, 'name_full'):
        return {'id_type': type(value).__name__, 'name': value.name_full}
    if isinstance(value, dict) or hasattr(value, 'keys'):
        return {str(k): _plain(value[k]) for k in sorted(value.keys())}
    if hasattr(value, 'to_list'):
        return _plain(value.to_list())
    if hasattr(value, '__iter__'):
        return [_plain(v) for v in value]
    return str(value)


def _rna_values(value, depth=0):
    result = {}
    for prop in value.bl_rna.properties:
        # Dependency-graph dirty flags and preview caches are not authored
        # settings; evaluating the changed FONT can legitimately update them.
        if prop.identifier in ('rna_type', 'is_updated', 'is_updated_data',
                                'is_updated_transform', 'users', 'tag', 'preview'):
            continue
        if prop.type == 'COLLECTION':
            if depth < 3:
                result[prop.identifier] = [_plain(v) if hasattr(v, 'name_full') else _rna_values(v, depth+1) if hasattr(v, 'bl_rna') else _plain(v)
                                           for v in getattr(value, prop.identifier)]
        elif prop.type == 'POINTER':
            target = getattr(value, prop.identifier)
            result[prop.identifier] = (_plain(target) if target is None or hasattr(target, 'name_full')
                                       else _rna_values(target, depth+1) if depth < 3 else type(target).__name__)
        else:
            result[prop.identifier] = _plain(getattr(value, prop.identifier))
    return result


def _object_state(ob):
    return {'name': ob.name, 'type': ob.type, 'data': ob.data.name if ob.data else None,
            'matrix_world': [list(r) for r in ob.matrix_world], 'matrix_local': [list(r) for r in ob.matrix_local],
            'matrix_basis': [list(r) for r in ob.matrix_basis], 'parent': ob.parent.name if ob.parent else None,
            'properties': _plain(dict(ob.items())), 'collections': sorted(c.name for c in ob.users_collection),
            'hide_render': ob.hide_render, 'hide_viewport': ob.hide_viewport,
            'modifiers': [_rna_values(m) for m in ob.modifiers],
            'constraints': [_rna_values(c) for c in ob.constraints]}


def _mesh_state(ob):
    state = _helper()._fingerprint(ob)
    mesh = ob.data
    state['polygon_materials'] = [p.material_index for p in mesh.polygons]
    state['polygon_smooth'] = [p.use_smooth for p in mesh.polygons]
    state['edges_sha256'] = hashlib.sha256(array('i', [i for e in mesh.edges for i in e.vertices]).tobytes()).hexdigest()
    attributes = {}
    fields = {'FLOAT': ('value', 'f', 1), 'INT': ('value', 'i', 1), 'INT8': ('value', 'b', 1),
              'BOOLEAN': ('value', 'b', 1), 'FLOAT_VECTOR': ('vector', 'f', 3),
              'FLOAT2': ('vector', 'f', 2), 'INT32_2D': ('value', 'i', 2),
              'FLOAT_COLOR': ('color', 'f', 4), 'BYTE_COLOR': ('color', 'f', 4),
              'QUATERNION': ('value', 'f', 4), 'FLOAT4X4': ('value', 'f', 16)}
    for attr in mesh.attributes:
        if attr.name == 'position':
            continue  # Source position changes alone are authorized for exact selected vertices.
        field = fields.get(attr.data_type)
        if field:
            prop, code, width = field
            values = array(code, [0])*(len(attr.data)*width)
            attr.data.foreach_get(prop, values)
            digest = hashlib.sha256(values.tobytes()).hexdigest()
        else:
            digest = _digest([_rna_values(item) for item in attr.data])
        attributes[attr.name] = {'domain': attr.domain, 'type': attr.data_type, 'sha256': digest}
    state['attributes'] = attributes
    state['custom_properties'] = _plain(dict(mesh.items()))
    return state


def _materials(bpy):
    result = {}
    def tree_state(tree, visited):
        if tree.name_full in visited:
            return {'node_tree_reference': tree.name_full}
        visited = {*visited, tree.name_full}
        return {'name': tree.name_full, 'properties': _plain(dict(tree.items())),
                'nodes': [{'name': n.name, 'settings': _rna_values(n),
                           'inputs': [{'name': s.name, 'default': _plain(s.default_value) if hasattr(s, 'default_value') else None}
                                      for s in n.inputs],
                           'outputs': [{'name': s.name, 'default': _plain(s.default_value) if hasattr(s, 'default_value') else None}
                                       for s in n.outputs],
                           'nested_group': tree_state(n.node_tree, visited) if getattr(n, 'node_tree', None) else None}
                          for n in tree.nodes],
                'links': [(l.from_node.name, l.from_socket.identifier, l.to_node.name, l.to_socket.identifier) for l in tree.links]}
    for material in bpy.data.materials:
        state = {'settings': _rna_values(material), 'properties': _plain(dict(material.items()))}
        tree = material.node_tree
        if tree:
            state['node_tree'] = tree_state(tree, set())
        result[material.name] = _digest(state)
    return result


def _curve_state(curve):
    state = _rna_values(curve)
    # Automatic font texture-space bounds are derived from size; their change
    # is not a second authored modification. Actual world bounds are checked.
    for field in ('texspace_location', 'texspace_size'):
        state.pop(field, None)
    return state


def _snapshot(bpy):
    # Each mesh datablock is hashed once, even for thousands of tree instances.
    meshes, objects = {}, {}
    for ob in bpy.data.objects:
        objects[ob.name] = _object_state(ob)
        if ob.type == 'MESH' and ob.data.name not in meshes:
            meshes[ob.data.name] = _mesh_state(ob)
    return {'objects': objects, 'meshes': meshes, 'materials': _materials(bpy)}


def _text_plan(bpy, rows):
    row = next((r for r in rows if r['id'] == 'Reserve_Bathhouse'), None)
    if row is None or not _close(row['center_m'][:2], (-137., -78.)) or abs(row['pad_level_m']-6.786389) > TOLERANCE_M or row['yaw_degrees'] != 90:
        raise ValueError('Exact bathhouse building record differs')
    ob = bpy.data.objects.get(SIGN)
    if ob is None or ob.type != 'FONT' or ob.data.users != 1:
        raise ValueError('Expected one exclusively owned native bathhouse FONT')
    curve = ob.data
    expected = (-132.34, -78., row['pad_level_m']+2.78)
    if curve.body != 'DOUCHES' or abs(curve.size-.21) > 1e-6 or abs(curve.extrude-.002) > 1e-6 or not _close(ob.location, expected):
        raise ValueError('Bathhouse label source text/size/outset differs')
    if not _close(ob.rotation_euler, (math.pi/2, 0., math.pi/2)) or not _close(ob.scale, (1., 1., 1.)) or ob.parent:
        raise ValueError('Bathhouse label source transform differs')
    if ob.get('reserve_building_id') != 'Reserve_Bathhouse' or ob.get('reserve_role') != 'visitor_sign':
        raise ValueError('Bathhouse label ownership differs')
    if not curve.font or 'SourceSerif4' not in curve.font.name.replace('-', '').replace(' ', '') or [m.name for m in curve.materials] != ['LT_White']:
        raise ValueError('Bathhouse label font/material differs')
    backing = bpy.data.objects.get(BACKING)
    if backing is None or backing.type != 'MESH':
        raise ValueError('Bathhouse source fascia missing')
    # Verify the real native backing box, not merely its object name.
    recorder = _helper()._Recorder()
    recorder.box((0., -4.62, 2.78), (4.9, .08, .35), 'Sage')
    part = recorder.parts[0]
    part['vertices'] = [(-137.-p[1], -78.+p[0], row['pad_level_m']+p[2]) for p in part['vertices']]
    matches = [c for c in _helper()._components(backing) if _part_match(c, part)]
    if len(matches) != 1:
        raise ValueError('Bathhouse exact fascia source geometry differs')
    return {'object': SIGN, 'old_size_m': float(curve.size), 'new_size_m': .38,
            'old_location_m': list(ob.location), 'new_location_m': [-132.32, -78., expected[2]],
            'backing_bounds_m': matches[0]['bounds'],
            'new_expected_cap_height_m': .111027181148529*.38/.21,
            'font_body_material_extrusion_preserved': True, 'flat_front_clearance_m': .018}


def _freeze_inputs(bpy, buildings, source_furniture):
    native = Path(bpy.data.filepath).resolve()
    if not native.is_file() or _sha(native) != NATIVE_SHA256:
        raise ValueError('Open the immutable bound V14 native before entry correction')
    records = {}
    for name, expected in RECORD_HASHES.items():
        path = native.parent/name
        if not path.is_file() or _sha(path) != expected:
            raise ValueError('V14 record binding mismatch: '+name)
        records[name] = _read(path)
    if buildings != records['whole_town_buildings.json'] or source_furniture != records['source_furniture_geometry.json']:
        raise ValueError('Supplied building/furniture records differ from immutable V14')
    return native, records


def _validate_preservation(before, after, target_meshes, text):
    if before['materials'] != after['materials']:
        raise RuntimeError('A material changed during the entry-only transaction')
    if before['objects'].keys() != after['objects'].keys() or before['meshes'].keys() != after['meshes'].keys():
        raise RuntimeError('Entry correction changed scene identity/topology ownership')
    for name, expected in before['objects'].items():
        actual = after['objects'][name]
        if name == SIGN:
            expected = dict(expected)
            # Only the font object's world/local/basis X translation is authorized.
            for key in ('matrix_world', 'matrix_local', 'matrix_basis'):
                expected[key] = [list(r) for r in expected[key]]
                expected[key][0][3] += text['new_location_m'][0]-text['old_location_m'][0]
            # Blender matrices store float32; compare the matrices numerically.
            for key in ('matrix_world', 'matrix_local', 'matrix_basis'):
                if not all(_close(a, b, 2e-5) for a, b in zip(actual[key], expected[key])):
                    raise RuntimeError('Unexpected bathhouse text transform')
                expected[key] = actual[key]
        if expected != actual:
            raise RuntimeError('Non-authorized object state changed: '+name)
    for name, expected in before['meshes'].items():
        actual = after['meshes'][name]
        if name in target_meshes:
            expected, actual = dict(expected), dict(actual)
            expected.pop('geometry_sha256'); actual.pop('geometry_sha256')
        if expected != actual:
            raise RuntimeError('Non-authorized mesh/UV/material state changed: '+name)


def apply(api, output, buildings, source_furniture):
    """Mutate only exact preflighted components, returning an explicit design receipt.

    ``buildings`` and ``source_furniture`` are complete decoded original V14 JSON
    files. ``output`` is a separate directory for the receipt; existing receipts
    are refused. A rejection before mutation creates no success evidence. No
    global furniture fingerprint is relaxed: the 6,739 protected interiors are
    checked against their ORIGINAL baseline before and after this transaction.
    """
    bpy = api['bpy']
    repo = Path(api.get('repo_root', ROOT)).resolve()
    table, bindings = _recipes(repo)
    native, records = _freeze_inputs(bpy, buildings, source_furniture)
    output = Path(output).resolve()
    if output == native.parent or native.is_relative_to(output):
        raise ValueError('Entry receipt output must be separate from immutable source native')
    receipt_path = output/'entry_detail_changes.json'
    if receipt_path.exists():
        raise ValueError('Entry receipt already exists; use a fresh iteration directory')
    objects = {}
    for prefix, materials in ((CIVIC, ('White', 'Iron', 'Sage', 'Oak', 'Linen')),
                              (WAYFINDING, ('Oak', 'Sage', 'White'))):
        for material in materials:
            name = prefix+'_'+material
            ob = bpy.data.objects.get(name)
            if ob is None or ob.type != 'MESH' or ob.data.users != 1 or ob.data.shape_keys:
                raise ValueError('Expected exclusive, unshaped source mixed mesh: '+name)
            if name in source_furniture['objects']:
                raise ValueError('Entry target unexpectedly belongs to protected interior furniture: '+name)
            objects[name] = ob
    components = {name: _helper()._components(ob) for name, ob in objects.items()}
    plan = _geometry_plan(components, table, _support_sampler(bpy))
    rows = buildings['buildings']
    text = _text_plan(bpy, rows)
    audit = _load('entry_native_geometry_audit', repo/'tools/town_upgrade/building_native_audit.py')
    protected = source_furniture['objects']
    def protected_check():
        for name, expected in protected.items():
            ob = bpy.data.objects.get(name)
            if ob is None or audit.mesh_fingerprint(ob) != expected:
                raise ValueError('Protected source furniture geometry differs: '+name)
    protected_check()
    before = _snapshot(bpy)
    selected = {(e['object'], e['component']) for e in plan['edits'] if e['changed']}
    retained = {name: Counter(_helper()._component_hash(ob, c) for i, c in enumerate(components[name]) if (name, i) not in selected)
                for name, ob in objects.items()}
    curve = bpy.data.objects[SIGN].data
    curve_before = _curve_state(curve)
    text['old_world_bounds_m'] = _font_bounds(bpy.data.objects[SIGN])
    target_meshes = {ob.data.name for ob in objects.values()}
    changed = []
    # Every source primitive, original protected object and support query has
    # passed before the first mutation. Exact local backups enable rollback.
    backups = {name: [tuple(v.co) for v in ob.data.vertices] for name, ob in objects.items()}
    old_text_location = tuple(bpy.data.objects[SIGN].location)
    try:
        from mathutils import Vector
        for edit in plan['edits']:
            if not edit['changed']:
                continue
            ob = objects[edit['object']]
            inverse = ob.matrix_world.inverted()
            for index, point in zip(edit['indices'], edit['new_points']):
                ob.data.vertices[index].co = inverse@Vector(point)
        for ob in objects.values():
            ob.data.update()
        label = bpy.data.objects[SIGN]
        curve.size = text['new_size_m']; label.location = text['new_location_m']
        bpy.context.view_layer.update()
        current = {name: _helper()._components(ob) for name, ob in objects.items()}
        for edit in plan['edits']:
            ob = objects[edit['object']]
            actual = current[ob.name][edit['component']]
            if actual['indices'] != edit['indices'] or not _part_match(actual, {'vertices': edit['new_points'], 'faces': edit['faces']}):
                raise RuntimeError('Authorized transformed primitive verification failed: '+edit['label'])
            if not edit['changed']:
                continue
            changed.append({'label': edit['label'], 'source_object': ob.name, 'source_component': edit['component'],
                            'vertex_count': len(edit['indices']), 'old_world_bounds_m': _bounds(edit['old_points']),
                            'new_world_bounds_m': actual['bounds'],
                            'original_geometry_uv_sha256': _helper()._component_hash(ob, components[ob.name][edit['component']]),
                            'new_expected_world_points_sha256': _digest(edit['new_points']),
                            'new_geometry_uv_sha256': _helper()._component_hash(ob, actual)})
        for name, ob in objects.items():
            remaining = Counter(_helper()._component_hash(ob, c) for i, c in enumerate(current[name]) if (name, i) not in selected)
            if retained[name] != remaining:
                raise RuntimeError('Unrelated mixed-batch component/UV changed: '+name)
        curve_expected = dict(curve_before); curve_expected['size'] = float(curve.size)
        if _curve_state(curve) != curve_expected or abs(curve.size-.38) > 1e-6:
            raise RuntimeError('Font changed beyond authorized size')
        text['new_world_bounds_m'] = _font_bounds(label)
        _verify_text_bounds(text)
        protected_check()
        after = _snapshot(bpy)
        _validate_preservation(before, after, target_meshes, text)
        _bound_sources(repo)
        # Recheck both external record files as well as the immutable native;
        # receipts never certify input files that drifted during the transaction.
        _freeze_inputs(bpy, buildings, source_furniture)
        report = {'schema': SCHEMA, 'status': 'APPLIED_SCOPED_GEOMETRY_VERIFIED_REQUIRES_ART_AND_RUNTIME_REVIEW',
                  'source_native': {'path': str(native), 'sha256': NATIVE_SHA256}, 'source_bindings': bindings,
                  'record_bindings': RECORD_HASHES, 'tool_sha256': _sha(__file__),
                  'authorization': 'User requested furniture/design refinement; targeted preservation expectations are deliberately revised.',
                  'preservation_contract': {'changed_component_count': len(changed),
                      'verified_source_component_count': len(plan['edits']),
                      'original_target_fingerprints_unchanged': False,
                      'new_target_expectations': 'Actual coordinates must equal independently planned rigid transforms; topology, UVs, materials and IDs are unchanged.',
                      'untargeted_component_count': sum(sum(c.values()) for c in retained.values()),
                      'untargeted_mixed_geometry_uv': 'PASS', 'all_non_target_meshes': 'PASS',
                      'all_materials': 'PASS', 'all_non_target_object_transforms_and_ids': 'PASS',
                      'protected_interior_furniture_count': len(protected), 'original_protected_interior_baseline': 'PASS'},
                  'scene_before_sha256': _digest(before), 'scene_after_sha256': _digest(after),
                  'all_mesh_count': len(before['meshes']), 'all_object_count': len(before['objects']),
                  'all_material_count': len(before['materials']), 'groups': plan['groups'], 'text': text,
                  'preserved_inventory': {
                      'all_non_target_mesh_state_sha256': {name: _digest(state) for name, state in before['meshes'].items() if name not in target_meshes},
                      'all_non_target_object_state_sha256': {name: _digest(state) for name, state in before['objects'].items() if name != SIGN},
                      'all_material_state_sha256': before['materials'],
                      'target_mesh_old_state_sha256': {name: _digest(before['meshes'][name]) for name in sorted(target_meshes)},
                      'target_mesh_new_state_sha256': {name: _digest(after['meshes'][name]) for name in sorted(target_meshes)}},
                  'components': changed, 'scene_saved': False, 'exported': False,
                  'art_review': 'PENDING_ACTUAL_OBLIQUE_FRAMES', 'runtime_clearance_review': 'PENDING',
                  'whole_town_concept_acceptance': False}
        output.mkdir(parents=True, exist_ok=True)
        temporary = receipt_path.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
        temporary.replace(receipt_path)
        return report
    except BaseException:
        for name, coordinates in backups.items():
            ob = objects[name]
            for vertex, coordinate in zip(ob.data.vertices, coordinates):
                vertex.co = coordinate
            ob.data.update()
        curve.size = text['old_size_m']; bpy.data.objects[SIGN].location = old_text_location
        bpy.context.view_layer.update()
        if _snapshot(bpy) != before:
            raise RuntimeError('Entry rollback did not restore original scene; discard the unsaved process')
        raise


def _font_bounds(ob):
    from mathutils import Vector
    return _bounds([tuple(ob.matrix_world@Vector(p)) for p in ob.bound_box])


def _verify_text_bounds(text):
    bounds = text['new_world_bounds_m']; backing = text['backing_bounds_m']
    if bounds[0][0] < backing[1][0]+.015:
        raise RuntimeError('DOUCHES glyph face remains too near/inside fascia')
    if bounds[0][1] < backing[0][1]+.05 or bounds[1][1] > backing[1][1]-.05:
        raise RuntimeError('DOUCHES enlarged width exceeds panel margins')
    if bounds[0][2] < backing[0][2]+.04 or bounds[1][2] > backing[1][2]-.04:
        raise RuntimeError('DOUCHES enlarged height exceeds panel margins')


def _pilot():
    import argparse
    import bpy
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pilot-output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    output = args.pilot_output.resolve()
    if output.exists():
        raise ValueError('Actual Blender pilot requires a new output directory')
    original = Path(bpy.data.filepath).resolve()
    buildings = _read(original.parent/'whole_town_buildings.json')
    furniture = _read(original.parent/'source_furniture_geometry.json')
    report = apply({'bpy': bpy}, output, buildings, furniture)
    audit = _load('entry_pilot_native_audit', ROOT/'tools/town_upgrade/building_native_audit.py')
    native_audit = audit.audit({'bpy': bpy}, buildings['buildings'],
                               output/'whole_town_native_geometry_audit.json', furniture['objects'])
    if native_audit['status'] != 'PASS' or native_audit['source_furniture_geometry_status'] != 'PASS':
        raise RuntimeError('V15 entry pilot native audit failed; candidate not saved')
    destination = output/'refined_whole_town.blend'
    result = bpy.ops.wm.save_as_mainfile(filepath=str(destination), copy=True)
    if 'FINISHED' not in result or not destination.is_file() or _sha(original) != NATIVE_SHA256:
        raise RuntimeError('Fresh candidate save or immutable source check failed')
    derivation = {'schema': 'living_town.entry_native_derivation.v1',
                  'status': 'NATIVE_CANDIDATE_SAVED_REQUIRES_ART_AND_RUNTIME_REVIEW',
                  'source': report['source_native'], 'candidate': {'path': str(destination), 'sha256': _sha(destination)},
                  'entry_receipt_sha256': _sha(output/'entry_detail_changes.json'),
                  'native_audit_sha256': _sha(output/'whole_town_native_geometry_audit.json'),
                  'native_geometry_audit': 'PASS', 'protected_interior_furniture': 'PASS',
                  'rendered_review': False, 'runtime_review': False, 'portable_export': False}
    (output/'entry_native_derivation.json').write_text(json.dumps(derivation, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(derivation))


if __name__ == '__main__':
    _pilot()
