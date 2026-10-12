"""Read-only evaluated roof/chimney contact diagnosis; never saves the native file."""
from pathlib import Path
import bpy, hashlib, json, math, os
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(__file__).resolve().parents[1]

def _evaluated_tree(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        tree = BVHTree.FromPolygons(points, [list(face.vertices) for face in mesh.polygons])
        return tree, points
    finally:
        evaluated.to_mesh_clear()


def _roof_trees(collection, depsgraph):
    result = []
    for obj in collection.all_objects:
        if obj.type != 'MESH' or obj.hide_render:
            continue
        if any(mat and mat.name.removeprefix('LT_') in ('Slate', 'ClaySlate')
               for mat in obj.data.materials):
            tree, points = _evaluated_tree(obj, depsgraph)
            result.append((obj.name, tree, max(point.z for point in points)))
    return result


def audit_roof_contact(scene):
    """Check actual body-only bottom/roof intersection at nine inset points.

    Stored bottom/top metadata are not used as geometric evidence. Body rays
    go upward from below; Slate/ClaySlate rays go downward from above. Neither
    ray queries caps, mortar rings, chimney pots, or other scene objects.
    """
    bpy.context.window.scene = scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    bodies = sorted((obj for obj in scene.objects if obj.type == 'MESH'
                     and obj.get('asset_role') == 'chimney_body'), key=lambda obj:obj.name)
    failures, per_chimney = [], []
    cache = {}
    sample_count = 0
    seen_ids = set()
    required = ('chimney_id', 'building_id', 'roof_collection',
                'chimney_center_world_xy', 'chimney_width_m', 'chimney_yaw_degrees')
    for body in bodies:
        missing = [key for key in required if key not in body]
        ident = str(body.get('chimney_id', body.name))
        if missing or ident in seen_ids:
            failures.append({'chimney_id':ident, 'reason':'missing metadata or duplicate ID',
                             'missing':missing, 'duplicate':ident in seen_ids})
            continue
        seen_ids.add(ident)
        roof_name = str(body['roof_collection'])
        if roof_name not in cache:
            collection = bpy.data.collections.get(roof_name)
            cache[roof_name] = [] if collection is None else _roof_trees(collection, depsgraph)
        roofs = cache[roof_name]
        tree, points = _evaluated_tree(body, depsgraph)
        minimum_z, maximum_z = min(p.z for p in points), max(p.z for p in points)
        cx, cy = map(float, body['chimney_center_world_xy'])
        width = float(body['chimney_width_m'])
        half = width/2-.03
        if half <= 0:
            failures.append({'chimney_id':ident, 'reason':'invalid width', 'width_m':width})
            continue
        yaw = math.radians(float(body['chimney_yaw_degrees']))
        co, si = math.cos(yaw), math.sin(yaw)
        offsets = [('center',0,0), ('corner_SW',-half,-half), ('corner_SE',half,-half),
                   ('corner_NE',half,half), ('corner_NW',-half,half),
                   ('edge_S',0,-half), ('edge_E',half,0), ('edge_N',0,half), ('edge_W',-half,0)]
        samples = []
        for label, dx, dy in offsets:
            x, y = cx+dx*co-dy*si, cy+dx*si+dy*co
            body_hit = tree.ray_cast(Vector((x,y,minimum_z-1)), Vector((0,0,1)),
                                     maximum_z-minimum_z+2)[0]
            roof_hits = []
            ray_z = max([maximum_z]+[r[2] for r in roofs])+10
            for roof_obj, roof_tree, _ in roofs:
                hit = roof_tree.ray_cast(Vector((x,y,ray_z)), Vector((0,0,-1)), 100)[0]
                if hit is not None:
                    roof_hits.append((hit.z, roof_obj))
            roof_hit = max(roof_hits) if roof_hits else None
            gap = None if body_hit is None or roof_hit is None else body_hit.z-roof_hit[0]
            passed = gap is not None and gap <= .02
            sample = {'sample':label, 'world_xy_m':[x,y],
                      'actual_body_bottom_z_m':None if body_hit is None else body_hit.z,
                      'actual_roof_z_m':None if roof_hit is None else roof_hit[0],
                      'roof_object':None if roof_hit is None else roof_hit[1],
                      'body_bottom_above_roof_m':gap, 'status':'PASS' if passed else 'FAIL'}
            samples.append(sample)
            sample_count += 1
            if not passed:
                failures.append({'chimney_id':ident, 'owner':str(body['building_id']), **sample})
        per_chimney.append({'chimney_id':ident, 'owner':str(body['building_id']),
            'body_object':body.name, 'roof_collection':roof_name,
            'actual_body_bounds_z_m':[minimum_z,maximum_z], 'width_m':width,
            'status':'PASS' if all(s['status']=='PASS' for s in samples) else 'FAIL',
            'samples':samples})
    if not bodies:
        failures.append({'reason':'No metadata-tagged chimney body meshes found'})
    return {'status':'PASS' if not failures else 'FAIL', 'chimney_count':len(bodies),
        'sample_count':sample_count, 'failures':failures, 'per_chimney':per_chimney,
        'method':'Evaluated body-only upward BVH rays and Slate/ClaySlate downward BVH rays',
        'inset_m':.03, 'maximum_allowed_gap_m':.02, 'native_file_saved':False}


def _legacy_main():
    scene = bpy.data.scenes['Living_Town_Summer']
    bpy.context.window.scene = scene
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 8
    scene.frame_set(160)
    camera = bpy.data.objects['08_Coastal_Flythrough']
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    manifest = json.loads((ROOT / 'town_manifest.json').read_text())
    target = (1023, 269)

    def components(mesh):
        parent = list(range(len(mesh.vertices)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for edge in mesh.edges:
            a, b = map(find, edge.vertices)
            if a != b:
                parent[b] = a
        groups = {}
        for i in range(len(parent)):
            groups.setdefault(find(i), []).append(i)
        return list(groups.values())

    def projected_bounds(points):
        projected = [world_to_camera_view(scene, camera, p) for p in points]
        pixels = [(p.x * 1280, (1-p.y) * 720) for p in projected if p.z > 0]
        if not pixels:
            return None
        return [min(p[0] for p in pixels), min(p[1] for p in pixels),
                max(p[0] for p in pixels), max(p[1] for p in pixels)]

    records = []
    for building in manifest['buildings']:
        collection = bpy.data.collections[building['roof_collection']]
        objects = [o for o in collection.all_objects if o.type == 'MESH' and not o.hide_render]
        roof_surfaces = []
        for obj in objects:
            if not any(m and m.name.removeprefix('LT_') in ('Slate', 'ClaySlate') for m in obj.data.materials):
                continue
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            vertices = [obj.matrix_world @ v.co for v in mesh.vertices]
            polygons = [list(p.vertices) for p in mesh.polygons]
            roof_surfaces.append((obj.name, BVHTree.FromPolygons(vertices, polygons)))
            evaluated.to_mesh_clear()
        for obj in objects:
            if not any(m and m.name.removeprefix('LT_') == 'Granite' for m in obj.data.materials):
                continue
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            for indices in components(mesh):
                points = [obj.matrix_world @ mesh.vertices[i].co for i in indices]
                minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
                maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
                extent = maximum - minimum
                # Masonry shafts are 0.68m square; accept extended bases after repair.
                # Other roof Granite components are horizontal caps/window sills.
                if not (1.24 <= extent.z <= 6.0 and .60 <= extent.x <= 1.02 and .60 <= extent.y <= 1.02):
                    continue
                center = (minimum + maximum) / 2
                hits = []
                for name, tree in roof_surfaces:
                    location, normal, polygon, distance = tree.ray_cast(
                        Vector((center.x, center.y, maximum.z+10)), Vector((0,0,-1)), 50)
                    if location is not None:
                        hits.append((location.z, name, list(location)))
                roof_hit = max(hits) if hits else None
                bounds = projected_bounds(points)
                distance = math.inf if bounds is None else math.hypot(
                    max(bounds[0]-target[0], 0, target[0]-bounds[2]),
                    max(bounds[1]-target[1], 0, target[1]-bounds[3]))
                records.append({'owner':building['id'], 'kind':building['kind'],
                    'typology':building['typology'], 'object':obj.name,
                    'roof_collection':collection.name, 'evaluated_component_vertices':len(indices),
                    'world_bounds_min':list(minimum), 'world_bounds_max':list(maximum),
                    'pixel_bounds_frame160':bounds, 'pixel_distance_to_target':distance,
                    'actual_slate_downray_hit':None if roof_hit is None else roof_hit[2],
                    'actual_slate_object':None if roof_hit is None else roof_hit[1],
                    'shaft_base_above_actual_roof_m':None if roof_hit is None else minimum.z-roof_hit[0]})
            evaluated.to_mesh_clear()
    records.sort(key=lambda r:r['pixel_distance_to_target'])
    record = {'schema':'living_town.roof_contact_diagnosis.v1',
        'scope':'Read-only evaluated mesh connected components; roof-only vertical BVH rays exclude chimney masonry.',
        'native_file_saved':False, 'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
        'frame':160, 'camera':camera.name, 'resolution':[1280,720], 'target_pixel':target,
        'shaft_count':len(records), 'near_target':records[:5],
        'detached_center_ray_count':sum(r['shaft_base_above_actual_roof_m'] is not None and r['shaft_base_above_actual_roof_m']>.05 for r in records),
        'all_shafts':records}
    path = ROOT / 'evidence/roof_contact_diagnosis.json'
    temporary = path.with_suffix('.tmp')
    with temporary.open('w',encoding='utf-8') as stream:
        json.dump(record,stream,indent=2);stream.flush();os.fsync(stream.fileno())
    temporary.replace(path)
    print('LT_ROOF_CONTACT_DIAGNOSIS',json.dumps({k:v for k,v in record.items() if k!='all_shafts'}),flush=True)


if __name__ == '__main__':
    scene = bpy.data.scenes['Living_Town_Summer']
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 8
    if not any(obj.get('asset_role') == 'chimney_body' for obj in scene.objects):
        _legacy_main()
    else:
        report = audit_roof_contact(scene)
        report.update({'schema':'living_town.roof_contact_diagnosis.v2',
            'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()})
        output_path = ROOT / 'evidence/roof_contact_diagnosis.json'
        temporary = output_path.with_suffix('.tmp')
        with temporary.open('w', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2); stream.flush(); os.fsync(stream.fileno())
        temporary.replace(output_path)
        print('LT_ROOF_CONTACT_DIAGNOSIS', json.dumps(
            {k:v for k,v in report.items() if k!='per_chimney'}), flush=True)
