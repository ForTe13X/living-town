"""Exact whole-member facade003 functions; root must configure the actual repo.

No engine runs on import. Render/CLI code is excluded; apply remains unchanged.
"""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

SOURCE_FACADE_SHA256='67fa3d9782d46eff1bc08d972c3752faff0bbf7f4836481057b90c74c70e40bc'
ROOT=None
CORE_SHA='41a59245afb3fc02789f1dfd2482c68c1b3282b029cd1087f177b8c3c699894d'
RESTORED_BATCH_SHA='d041139281360864d89dc2091e84ee7af218fa61b9d846ec456a88075dfbb214'
MATCH_M=.0007
PANEL_CYCLES=((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7))

def configure(repo):
    global ROOT
    ROOT=Path(repo).resolve(strict=True)
    if not (ROOT/'tools/town_upgrade/entry_details.py').is_file():raise ValueError('Explicit repository root required')

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def lerp(a, b, t):
    return tuple(x+(y-x)*t for x, y in zip(a, b))

def local(row, point):
    a = math.radians(row['yaw_degrees'])
    x, y = point[0]-row['center_m'][0], point[1]-row['center_m'][1]
    return (x*math.cos(a)+y*math.sin(a), -x*math.sin(a)+y*math.cos(a), point[2]-row['pad_level_m'])

def world(row, point):
    a = math.radians(row['yaw_degrees']); x, y, z = point
    return (row['center_m'][0]+x*math.cos(a)-y*math.sin(a),
            row['center_m'][1]+x*math.sin(a)+y*math.cos(a), row['pad_level_m']+z)

def rod_points(a, b, radius=.07):
    # Exact n=4 cross-section of bound core Batch.rod, including its phase.
    dx, _, dz = (b[i]-a[i] for i in range(3)); length = math.hypot(dx, dz)
    ay = -1. if dx > 0 else 1.
    bx, bz = -dz*ay/length, dx*ay/length
    return [tuple(p[j]+radius*((0., ay, 0.)[j]*math.cos(i*math.pi/2)
                  +(bx, 0., bz)[j]*math.sin(i*math.pi/2)) for j in range(3))
            for p in (a, b) for i in range(4)]

def upright_points(y, z0, z1):
    return [(x, y+dy, z) for z in (z0, z1)
            for x, dy in ((-.08, -.065), (.08, -.065), (.08, .065), (-.08, .065))]

def components(mesh):
    neighbours = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices; neighbours[a].add(b); neighbours[b].add(a)
    remaining = set(range(len(mesh.vertices))); result = []
    while remaining:
        start = min(remaining); remaining.remove(start); found = {start}; todo = [start]
        while todo:
            for other in neighbours[todo.pop()]:
                if other in remaining:
                    remaining.remove(other); found.add(other); todo.append(other)
        result.append(found)
    return result

def matched_roles(points, indices, expected):
    if len(indices) != len(expected):
        return None
    roles = {}; unused = set(range(len(expected)))
    for index in sorted(indices):
        distances = [(max(abs(points[index][j]-expected[i][j]) for j in range(3)), i) for i in unused]
        distance, role = min(distances)
        if distance > MATCH_M:
            return None
        roles[index] = role; unused.remove(role)
    return roles

def trim_rectangle(window):
    # Bound window() lines212-217: sill half-width w/2+.17, lower edge
    # pane_bottom-.195; lintel upper edge pane_top+.255. Conservative union.
    x, z, w, h = (window[k] for k in ('center_m', 'center_z_local_m', 'width_m', 'height_m'))
    return [x-w/2-.17, z-h/2-.195, x+w/2+.17, z+h/2+.255]

def source_owners(rows):
    # Two expansion records also use the semantic kind "halftimber", but
    # their generic expansion recipe is not this original core factory.
    return [r for r in rows if r['kind'] == 'halftimber' and r['group'] == 'urban']

def register_primitive_panels(mesh, part, roles, restored=False):
    """Accept only the two exact registered factory forms.

    Core Batch.flush retains six quads. The restored entrance post is built by
    expansion Batch.flush, which triangulates those six box panels. Its exact
    legal two-triangle diagonal may vary, but the four boundary edges, winding,
    coverage and continuous per-panel UV corner values may not.
    """
    faces = [p for p in mesh.polygons if set(p.vertices) <= part]
    wanted_count, wanted_sides = (12, 3) if restored else (6, 4)
    if len(faces) != wanted_count or any(len(p.vertices) != wanted_sides for p in faces):
        raise ValueError('Registered source form requires '+str(wanted_count)+' faces of '+str(wanted_sides)+' corners')
    panels = [{'cycle': cycle, 'faces': [], 'uv': {layer.name: {} for layer in mesh.uv_layers}}
              for cycle in PANEL_CYCLES]
    face_to_panel = {}
    for face in faces:
        logical = [roles[i] for i in face.vertices]
        candidates = [i for i, panel in enumerate(panels) if set(logical) <= set(panel['cycle'])]
        if len(candidates) != 1:
            raise ValueError('Face does not belong to one registered prism panel')
        number = candidates[0]; panel = panels[number]
        panel['faces'].append(logical); face_to_panel[face.index] = number
        for layer in mesh.uv_layers:
            lookup = panel['uv'][layer.name]
            for role, loop in zip(logical, face.loop_indices):
                uv = tuple(layer.data[loop].uv)
                if role in lookup and lookup[role] != uv:
                    raise ValueError('Registered source panel has a UV discontinuity across its triangulation')
                lookup[role] = uv
    for panel in panels:
        if len(panel['faces']) != (2 if restored else 1):
            raise ValueError('Registered source panel has missing or duplicate faces')
        directed = Counter((a, face[(j+1)%len(face)]) for face in panel['faces'] for j, a in enumerate(face))
        undirected = Counter(tuple(sorted(edge)) for edge in directed.elements())
        boundary = {(a, panel['cycle'][(j+1)%4]) for j, a in enumerate(panel['cycle'])}
        actual_boundary = {edge for edge, count in directed.items() if undirected[tuple(sorted(edge))] == 1}
        internal = [edge for edge, count in undirected.items() if count == 2]
        if actual_boundary != boundary or any(count not in (1, 2) for count in undirected.values()):
            raise ValueError('Registered panel coverage or boundary winding differs')
        if len(internal) != (1 if restored else 0) or any(directed[edge] != 1 or directed[edge[::-1]] != 1 for edge in internal):
            raise ValueError('Registered triangular panel does not contain exactly one paired internal diagonal')
        if any(set(values) != set(panel['cycle']) for values in panel['uv'].values()):
            raise ValueError('Registered panel lacks one or more source UV corners')
    return panels, face_to_panel

def preflight(bpy, rows):
    plans = []; owners = source_owners(rows)
    if not owners:
        raise ValueError('No authored half-timber buildings')
    for row in owners:
        ident = row['id']; w, d = row['footprint_m']; h = row['floor_count']*2.85; front = -d/2
        a = w/2-.25
        specs = [('diagonal_left', ident+'_Front_Trunk', (-a, front-.2, 2.9), (0., front-.2, h-.25)),
                 ('diagonal_right', ident+'_Front_Trunk', (0., front-.2, h-.25), (a, front-.2, 2.9))]
        original = bpy.data.objects.get(ident+'_Front_Trunk')
        if original is None or original.type != 'MESH':
            raise ValueError('Missing exact source timber object: '+ident)
        # The source centre post either remains in the original batch (offset
        # door) or was split above the preserved door header by upgrade.
        specs += [('original_centre_upright', ident+'_Front_Trunk', (0., front-.18, 0.), (0., front-.18, h))]
        restored = bpy.data.objects.get(ident+'_Upgrade_OpenEntrance_Trunk')
        if restored:
            specs += [('restored_centre_upright', restored.name, (0., front-.18, 2.47), (0., front-.18, h))]
        found = {}
        for label, name, start, end in specs:
            ob = bpy.data.objects[name]; mesh = ob.data
            if ob.vertex_groups or mesh.color_attributes or mesh.has_custom_normals:
                raise ValueError('Unexpected source data needs explicit preservation: '+name)
            if any(e.use_seam or getattr(e, 'use_edge_sharp', False) for e in mesh.edges):
                raise ValueError('Unexpected source edge flags need explicit preservation: '+name)
            points = {v.index: local(row, ob.matrix_world@v.co) for v in mesh.vertices}
            expected = rod_points(start, end) if label.startswith('diagonal') else upright_points(front-.18, start[2], end[2])
            matches = [(part, matched_roles(points, part, expected)) for part in components(mesh)]
            matches = [(part, roles) for part, roles in matches if roles is not None]
            if label == 'original_centre_upright' and not matches:
                continue
            if len(matches) != 1:
                raise ValueError('Ambiguous/missing exact authored component '+ident+'/'+label+': '+str(len(matches)))
            part, roles = matches[0]
            try:
                panels, face_to_panel = register_primitive_panels(mesh, part, roles,
                    restored=label == 'restored_centre_upright')
            except ValueError as error:
                raise ValueError('Source primitive topology differs: '+ident+'/'+label+': '+str(error)) from error
            source_faces = [p for p in mesh.polygons if set(p.vertices) <= part]
            windows = []
            for number, window in enumerate(row['window_apertures']):
                if window['face'] != 'front':
                    continue
                trim = trim_rectangle(window)
                # Check actual matched source faces, not a conservatively
                # expanded centreline bounding rectangle. A clear primitive
                # is never removed merely because it is near a window.
                overlaps = [projected_overlap_area([points[i] for i in face.vertices], trim)
                            for face in source_faces]
                positive = [area for area in overlaps if area > 1e-10]
                if positive:
                    windows.append({'index': number, 'outer_trim_rectangle_xz_m': trim,
                        'source_face_projected_overlap_area_sum_m2_not_union': sum(positive),
                        'positive_overlap_source_faces': len(positive)})
            if windows and label == 'original_centre_upright':
                raise ValueError('Original centre upright conflicts outside the authorized diagonal/restored-post removal scope: '+ident)
            found[label] = True
            plans.append({'building_id': ident, 'object': name, 'component': label, 'indices': part,
                          'roles': roles, 'changed': bool(windows), 'start_local_m': start,
                          'end_local_m': end, 'windows': windows, 'source_component_vertex_count': 8,
                          'source_topology_form': 'UPGRADE_TRIANGULATED_BOX_12_FACES' if label == 'restored_centre_upright' else 'CORE_QUAD_PRISM_6_FACES',
                          'panels': panels, 'face_to_panel': face_to_panel,
                          'action': 'REMOVE_ENTIRE_CONFLICTING_DECORATIVE_MEMBER' if windows else 'KEEP_ENTIRE_CLEAR_MEMBER',
                          'retained_fragments_created': 0, 'source_component_roles': sorted(roles.items())})
        if not found.get('original_centre_upright') and not found.get('restored_centre_upright'):
            raise ValueError('Cannot identify the existing original/restored centre post: '+ident)
    return owners, plans

def snapshot(mesh):
    points = [tuple(v.co) for v in mesh.vertices]
    uvs = {layer.name: [tuple(x.uv) for x in layer.data] for layer in mesh.uv_layers}
    faces = [{'source_index': p.index, 'vertices': list(p.vertices), 'material': p.material_index, 'smooth': p.use_smooth,
              'uv': {name: [uvs[name][i] for i in p.loop_indices] for name in uvs}} for p in mesh.polygons]
    return points, faces

def face_signature(points, face):
    return digest({'points': [points[i] for i in face['vertices']], 'material': face['material'],
                   'smooth': face['smooth'], 'uv': face['uv']})

def replace_components(bpy, name, plans):
    ob = bpy.data.objects[name]; old = ob.data; points, faces = snapshot(old)
    changed = [p for p in plans if p['changed']]
    removed = set().union(*(p['indices'] for p in changed))
    protected = [f for f in faces if not set(f['vertices']) & removed]
    if any(set(f['vertices']) & removed and not set(f['vertices']) <= removed for f in faces):
        raise ValueError('Primitive is connected to protected geometry: '+name)
    new_points = []; new_faces = []; index_map = {}
    for index, point in enumerate(points):
        if index not in removed:
            index_map[index] = len(new_points); new_points.append(point)
    for face in protected:
        new_faces.append({**face, 'vertices': [index_map[i] for i in face['vertices']]})
    mesh = bpy.data.meshes.new(old.name+'_ConflictingMembersRemoved')
    mesh.from_pydata(new_points, [], [f['vertices'] for f in new_faces]); mesh.update()
    for key in old.keys():
        mesh[key] = old[key]
    for mat in old.materials:
        mesh.materials.append(mat)
    for layer in old.uv_layers:
        created = mesh.uv_layers.new(name=layer.name, do_init=False)
        created.active_render = layer.active_render
        for polygon, face in zip(mesh.polygons, new_faces):
            for loop, uv in zip(polygon.loop_indices, face['uv'][layer.name]):
                created.data[loop].uv = uv
    mesh.uv_layers.active_index = old.uv_layers.active_index
    for p, f in zip(mesh.polygons, new_faces):
        p.material_index = f['material']; p.use_smooth = f['smooth']
    old_slots = [(s.link, s.material.name if s.material else None) for s in ob.material_slots]
    modifiers_before = [(m.name, m.type) for m in ob.modifiers]
    ob.data = mesh
    if old_slots != [(s.link, s.material.name if s.material else None) for s in ob.material_slots]:
        raise ValueError('Object material linkage changed: '+name)
    after_points, after_faces = snapshot(mesh)
    expected = Counter(face_signature(points, f) for f in protected)
    actual = Counter(face_signature(after_points, f) for f in after_faces)
    if any(actual[key] < count for key, count in expected.items()):
        raise ValueError('Protected source faces/UVs changed: '+name)
    if modifiers_before != [(m.name, m.type) for m in ob.modifiers]:
        raise ValueError('Source modifiers changed: '+name)
    return {'object': name, 'source_mesh': old.name, 'result_mesh': mesh.name,
            'source_vertices': len(points), 'result_vertices': len(after_points),
            'source_polygons': len(faces), 'result_polygons': len(after_faces),
            'whole_source_members_removed': [p['component'] for p in changed],
            'replacement_geometry_or_clipped_fragments_created': 0,
            'protected_face_count': len(protected), 'protected_face_signature_counts_sha256': digest(sorted(expected.items())),
            'protected_geometry_uv_material_smooth_faces_preserved': True, 'source_material_slots': old_slots,
            'source_modifiers_retained': modifiers_before}

def clip_polygon(points, axis, boundary, greater):
    if not points:
        return []
    result = []; previous = points[-1]
    inside = lambda p: p[axis] >= boundary if greater else p[axis] <= boundary
    for current in points:
        pin, cin = inside(previous), inside(current)
        if pin != cin:
            t = (boundary-previous[axis])/(current[axis]-previous[axis])
            result.append(lerp(previous, current, t))
        if cin:
            result.append(current)
        previous = current
    return result

def projected_overlap_area(points, rectangle):
    """Actual prism-face XZ overlap with the bound outer-trim envelope."""
    clipped = points
    for axis, lower, upper in ((0, rectangle[0], rectangle[2]), (2, rectangle[1], rectangle[3])):
        clipped = clip_polygon(clipped, axis, lower, True)
        clipped = clip_polygon(clipped, axis, upper, False)
    if len(clipped) < 3:
        return 0.
    return abs(sum(clipped[i][0]*clipped[(i+1)%len(clipped)][2]
               -clipped[(i+1)%len(clipped)][0]*clipped[i][2] for i in range(len(clipped))))/2

def aperture_audit(bpy, rows):
    """Evaluated structural-family triangles only; no plants or joinery."""
    depsgraph = bpy.context.evaluated_depsgraph_get(); reports = []; total = 0
    for row in source_owners(rows):
        triangles = []
        names = [row['id']+'_Front_Trunk', row['id']+'_Upgrade_OpenEntrance_Trunk']
        for name in names:
            ob = bpy.data.objects.get(name)
            if ob is None:
                continue
            evaluated = ob.evaluated_get(depsgraph); mesh = evaluated.to_mesh()
            try:
                mesh.calc_loop_triangles()
                points = [local(row, evaluated.matrix_world@v.co) for v in mesh.vertices]
                triangles += [(name, tri.polygon_index, [points[i] for i in tri.vertices]) for tri in mesh.loop_triangles]
            finally:
                evaluated.to_mesh_clear()
        windows = []
        for index, window in enumerate(row['window_apertures']):
            depth = 0 if window['axis'] == 'x' else 1; along = 1-depth
            co, center, z, w, h = (window[k] for k in ('coordinate_m', 'center_m', 'center_z_local_m', 'width_m', 'height_m'))
            hits = []; area_sum = 0.
            for name, polygon, tri in triangles:
                clipped = clip_polygon(tri, depth, co-.40, True)
                clipped = clip_polygon(clipped, depth, co+.40, False)
                for axis, lower, upper in ((along, center-w/2, center+w/2), (2, z-h/2, z+h/2)):
                    clipped = clip_polygon(clipped, axis, lower, True)
                    clipped = clip_polygon(clipped, axis, upper, False)
                if len(clipped) < 3:
                    continue
                area = abs(sum(clipped[i][along]*clipped[(i+1)%len(clipped)][2]
                           -clipped[(i+1)%len(clipped)][along]*clipped[i][2] for i in range(len(clipped))))/2
                if area > 1e-10:
                    area_sum += area
                    hits.append({'object': name, 'evaluated_polygon': polygon, 'projected_overlap_area_m2': area})
            windows.append({'index': index, 'face': window['face'], 'level': window['level'],
                            'pass': not hits, 'structural_overlap_triangles': len(hits),
                            'projected_triangle_area_sum_m2_not_union': area_sum, 'examples': hits[:12]})
            total += 1
        reports.append({'building_id': row['id'], 'structural_object_families': names, 'windows': windows})
    failures = [{'building_id': b['building_id'], 'index': w['index'], 'face': w['face'], 'level': w['level']}
                for b in reports for w in b['windows'] if not w['pass']]
    return {'status': 'PASS' if not failures else 'FAIL', 'all_source_half_timber_buildings': len(reports),
            'all_authored_window_apertures_tested': total, 'failing_windows': failures, 'buildings': reports,
            'scope': 'Evaluated Front_Trunk and original/restored entrance Trunk families; each authored pane rectangle and +/-0.40m facade depth slab. No tree, plant, legitimate window joinery or unrelated facade object is classified as a brace.',
            'positive_area_numerical_floor_m2': 1e-10}

def apply(bpy, rows):
    if sha(ROOT/'art/living_town/tools/build_living_town.py') != CORE_SHA:
        raise ValueError('The bound core source factory changed')
    if sha(ROOT/'tools/town_generation/build_expansion_scene.py') != RESTORED_BATCH_SHA:
        raise ValueError('The registered restored-post Batch implementation changed')
    owners, plans = preflight(bpy, rows)
    before = aperture_audit(bpy, rows); changes = []
    for name in sorted({p['object'] for p in plans if p['changed']}):
        changes.append(replace_components(bpy, name, [p for p in plans if p['object'] == name]))
    bpy.context.view_layer.update(); after = aperture_audit(bpy, rows)
    serial = [{k: v for k, v in p.items() if k not in ('indices', 'roles', 'panels', 'face_to_panel')} for p in plans]
    result = {'schema': 'living_town.half_timber_aperture_finish.v1', 'status': after['status'],
              'tool_sha256': sha(__file__), 'matched_source_core_builder_sha256': CORE_SHA,
              'registered_restored_post_batch_sha256': RESTORED_BATCH_SHA,
              'all_source_half_timber_ids': [r['id'] for r in owners],
              'policy': 'Remove whole exact decorative diagonal or centre-upright source primitives only if their actual matched face projection overlaps an authored outer-window-trim rectangle. Preserve all clear members. No clipped stubs or replacement geometry.',
              'selection_outer_trim_additional_margin_m': 0.,
              'whole_source_members_removed': sum(p['changed'] for p in plans),
              'replacement_geometry_or_clipped_fragments_created': 0,
              'other_factory_semantic_halftimber_records': [{'id': r['id'], 'group': r['group'],
                  'source_ref': r.get('source_ref'), 'reason': 'Different generic expansion factory; not the bound original Front_Trunk primitive recipe'}
                  for r in rows if r['kind'] == 'halftimber' and r['group'] != 'urban'],
              'primitive_match_tolerance_m': MATCH_M, 'plans': serial, 'changed_objects': changes,
              'structural_apertures_before': before, 'structural_apertures_after': after,
              'window_shell_interiors_party_walls_changed': False,
              'limits': 'Whole-conflicting-member decorative-frame finish; evaluated family/aperture checks do not grant art, structural engineering, collision or gameplay acceptance.'}
    if after['status'] != 'PASS':
        raise ValueError('A source timber family still overlaps authored pane regions: '+json.dumps(after['failing_windows']))
    return result
