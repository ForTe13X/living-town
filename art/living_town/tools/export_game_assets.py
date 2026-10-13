"""Read a saved Living Town .blend in a disposable Blender CLI process.

Example:
  blender --background living_town_complete.blend --python export_game_assets.py --
    --out game_assets --manifest town_manifest.json --prefabs all --label final

Never saves the source blend. Exports one self-contained glTF 2.0 GLB town and
optional standalone local-origin building GLBs, with explicit reveal ownership.
"""
import argparse
import hashlib
import json
import math
import os
import struct
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

_DESCENDANT_CHILDREN = None
_DESCENDANT_MEMO = {}


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as handle:
        for chunk in iter(lambda: handle.read(8*1024*1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def flush_file(path):
    with Path(path).open('rb+') as handle:
        handle.flush()
        os.fsync(handle.fileno())


def args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--manifest', type=Path)
    p.add_argument('--prefabs', choices=('all', 'main', 'none'), default='all')
    p.add_argument('--label', default='final', help='Use baseline for development evidence')
    p.add_argument('--scene', default='Living_Town_Summer')
    p.add_argument('--camera-rig', action='store_true', help='Also export native cameras in a separate cameras.glb')
    p.add_argument('--detail', choices=('both', 'game', 'high'), default='both')
    p.add_argument('--triangle-budget', type=int, default=3000000, help='Maximum triangles in optimized complete town')
    return p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])


def empty(name, collection, parent=None, **extras):
    ob = bpy.data.objects.new(name, None)
    collection.objects.link(ob)
    ob.parent = parent
    ob.empty_display_type = 'PLAIN_AXES'
    for key, value in extras.items():
        if value is not None:
            ob[key] = value
    return ob


def read_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF' or version != 2 or length != len(data):
        raise RuntimeError('Invalid glTF 2.0 binary header: '+str(path))
    chunk_length, chunk_type = struct.unpack_from('<II', data, 12)
    if chunk_type != 0x4E4F534A:
        raise RuntimeError('GLB does not begin with JSON chunk')
    return json.loads(data[20:20+chunk_length])


def glb_summary(path):
    doc = read_glb(path)
    primitives = [p for m in doc.get('meshes', []) for p in m.get('primitives', [])]
    images = doc.get('images', [])
    if any('uri' in im for im in images):
        raise RuntimeError('GLB has external image dependency: '+str(path))
    if any('uri' in b for b in doc.get('buffers', [])):
        raise RuntimeError('GLB has external buffer dependency')
    if any('POSITION' not in p.get('attributes', {}) for p in primitives):
        raise RuntimeError('Primitive without geometry')
    return {
        'file': Path(path).name, 'sha256': sha(path), 'bytes': Path(path).stat().st_size,
        'nodes': len(doc.get('nodes', [])), 'meshes': len(doc.get('meshes', [])),
        'materials': len(doc.get('materials', [])), 'embedded_images': len(images),
        'triangles': sum(doc['accessors'][p['indices']]['count']//3
                         for node in doc.get('nodes',[]) if 'mesh' in node
                         for p in doc['meshes'][node['mesh']]['primitives'] if 'indices' in p),
        'unique_mesh_triangles': sum(doc['accessors'][p['indices']]['count']//3 for p in primitives if 'indices' in p),
        'vertex_color_primitives': sum('COLOR_0' in p.get('attributes', {}) for p in primitives),
        'normal_mapped_materials': sum('normalTexture' in m for m in doc.get('materials', [])),
        'alpha_blend_materials': sum(m.get('alphaMode') == 'BLEND' for m in doc.get('materials', [])),
        'extensions_used': doc.get('extensionsUsed', []),
        'extensions_required': doc.get('extensionsRequired', []),
        'animations': len(doc.get('animations', [])),
        'animation_channels': sum(len(a.get('channels', [])) for a in doc.get('animations', [])),
        'tangent_primitives': sum('TANGENT' in p.get('attributes', {}) for p in primitives),
        'self_contained': True,
    }


def snapshot_descendants(objects):
    """Cache the completed geometry hierarchy before temporary prefab detaches.

    Blender's Object.children scans the object database. Reading it at every
    recursive visit makes large forests quadratic; one parent scan is enough.
    Reparenting a prefab root does not change the descendants within that root.
    Later camera exports use their own explicit object lists.
    """
    global _DESCENDANT_CHILDREN
    objects = tuple(objects)
    children = {ob: [] for ob in objects}
    for ob in objects:
        if ob.parent in children:
            children[ob.parent].append(ob)
    _DESCENDANT_CHILDREN = {ob: tuple(items) for ob, items in children.items()}
    _DESCENDANT_MEMO.clear()


def descendants(ob):
    if _DESCENDANT_CHILDREN is None or ob not in _DESCENDANT_CHILDREN:
        yield ob
        for child in ob.children:
            yield from descendants(child)
        return
    if ob not in _DESCENDANT_MEMO:
        _DESCENDANT_MEMO[ob] = (ob,) + tuple(
            item for child in _DESCENDANT_CHILDREN[ob] for item in descendants(child))
    yield from _DESCENDANT_MEMO[ob]


def remove_zero_area_tree_triangles(mesh, threshold_m2=1e-12):
    """Clean only a copied tree mesh, keeping BMesh custom-data layers intact.

    Pole rings in the authored ellipsoids contain coincident coordinates.
    Triangulate first so the genuine polar triangle remains; delete only its
    geometrically zero-area companion. No dissolve, merge, decimation or
    position/normal/UV/color edits are performed.
    """
    before = sum(max(0, poly.loop_total-2) for poly in mesh.polygons)
    editable = bmesh.new()
    try:
        editable.from_mesh(mesh)
        polygons = [face for face in editable.faces if len(face.verts) > 3]
        if polygons:
            bmesh.ops.triangulate(editable, faces=polygons)
        triangulated = len(editable.faces)
        zero_area = [face for face in editable.faces if face.calc_area() <= threshold_m2]
        largest_removed = max((face.calc_area() for face in zero_area), default=0.)
        if zero_area:
            bmesh.ops.delete(editable, geom=zero_area, context='FACES_ONLY')
        after = len(editable.faces)
        if any(len(face.verts) != 3 for face in editable.faces):
            raise RuntimeError('Tree cleanup left a non-triangle face: '+mesh.name)
        editable.to_mesh(mesh)
    finally:
        editable.free()
    mesh.update()
    return {'source_implied_triangles': before,
            'triangulated_faces_before_deletion': triangulated,
            'triangles_after': after,
            'zero_area_triangle_faces_deleted': len(zero_area),
            'triangulation_triangle_count_change': before-triangulated,
            'triangle_count_reduction': before-after,
            'maximum_deleted_area_m2': largest_removed,
            'threshold_m2': threshold_m2}


def bounds(objects):
    lo, hi = Vector((math.inf,)*3), Vector((-math.inf,)*3)
    for ob in objects:
        if ob.type != 'MESH':
            continue
        for corner in ob.bound_box:
            point = ob.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i], hi[i] = min(lo[i], point[i]), max(hi[i], point[i])
    return {'min': list(lo), 'max': list(hi), 'size': list(hi-lo)}


def yup_bounds(b):
    return {'min': [b['min'][0], b['min'][2], -b['max'][1]],
            'max': [b['max'][0], b['max'][2], -b['min'][1]],
            'size': [b['size'][0], b['size'][2], b['size'][1]]}


def geometry_cost(objects):
    meshes = [ob for ob in objects if ob.type == 'MESH']
    return {'mesh_nodes': len(meshes), 'triangles': sum(max(0, poly.loop_total-2) for ob in meshes for poly in ob.data.polygons)}


def interior_metadata_inventory(doc):
    extras = [node.get('extras', {}) for node in doc.get('nodes', [])]
    return {'floor_count': sum(item.get('floor_index') is not None for item in extras),
            'room_count': sum(bool(item.get('room_id')) for item in extras),
            'furnishing_count': len({item['interior_asset_id'] for item in extras if item.get('interior_asset_id')})}


def main():
    opt = args()
    run_started = time.perf_counter()
    stage_events = []
    retained_unused_mesh_count = 0
    def stage(name):
        event = {'stage': name, 'utc': datetime.now(timezone.utc).isoformat(timespec='seconds'),
                 'elapsed_seconds': round(time.perf_counter()-run_started, 3)}
        stage_events.append(event)
        print(f"{event['utc']} | STAGE | {name} | {event['elapsed_seconds']:.3f}s", flush=True)
    stage('source_preparation_started')
    source = Path(bpy.data.filepath).resolve()
    if not source.is_file():
        raise RuntimeError('Open a saved source .blend first')
    source_sha = sha(source)
    source_scene = bpy.data.scenes.get(opt.scene)
    if source_scene is None:
        raise RuntimeError('Required scene missing: '+opt.scene)
    if source_scene.unit_settings.scale_length != 1:
        raise RuntimeError('Exporter requires a metre-scale source scene')
    manifest_path = (opt.manifest or source.parent/'town_manifest.json').resolve()
    source_manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    planning_bindings = {}
    for field, relative_path in (('masterplan_sha256', 'masterplan.json'),
                                 ('interior_plan_sha256', 'interior_plan.json'),
                                 ('interior_module_sha256', 'tools/interior_design.py')):
        native_hash = source_scene.get(field)
        declared_hash = source_manifest.get(field)
        if native_hash is None and declared_hash is None:
            continue
        if not isinstance(native_hash, str) or len(native_hash) != 64 or declared_hash != native_hash:
            raise RuntimeError('Native/manifest planning binding mismatch: '+field)
        if sha(source.parent/relative_path) != native_hash:
            raise RuntimeError('Frozen native planning source changed: '+relative_path)
        planning_bindings[field] = native_hash
    interior_inventory = None
    if planning_bindings.get('interior_plan_sha256'):
        plan = json.loads((source.parent/'interior_plan.json').read_text(encoding='utf-8'))
        interior_inventory = {field: plan[field] for field in ('floor_count', 'room_count', 'furnishing_count')}
        for field, expected in interior_inventory.items():
            if source_manifest.get('interior_'+field) != expected:
                raise RuntimeError('Native manifest interior inventory mismatch: '+field)
    layout_inventory = None
    if planning_bindings.get('masterplan_sha256'):
        plan = json.loads((source.parent/'masterplan.json').read_text(encoding='utf-8'))
        layout_inventory = {'route_count': len(plan['streets']),
                            'authored_public_street_count': sum(item.get('kind') == 'public_street' for item in plan['streets'])}
    landscape_bindings = {}
    for field, relative_path in (('landscape_plan_sha256', 'landscape_plan.json'),
                                 ('landscape_details_sha256', 'tools/landscape_details.py')):
        native_hash = source_scene.get(field)
        declared_hash = source_manifest.get(field)
        if native_hash is None and declared_hash is None:
            continue  # Pre-landscape checkpoints remain readable.
        if not isinstance(native_hash, str) or len(native_hash) != 64 or declared_hash != native_hash:
            raise RuntimeError('Native/manifest landscape binding mismatch: '+field)
        if sha(source.parent/relative_path) != native_hash:
            raise RuntimeError('Frozen native landscape source changed: '+relative_path)
        landscape_bindings[field] = native_hash
    if landscape_bindings and len(landscape_bindings) != 2:
        raise RuntimeError('Landscape plan and details bindings must both be present')
    reserve_bindings = {}
    for field, relative_path in (('reserve_plan_sha256', 'reserve_plan.json'),
                                 ('reserve_plan_module_sha256', 'tools/reserve_plan.py'),
                                 ('reserve_environment_module_sha256', 'tools/reserve_environment.py'),
                                 ('reserve_amenities_module_sha256', 'tools/reserve_amenities.py')):
        native_hash = source_scene.get(field)
        declared_hash = source_manifest.get(field)
        if native_hash is None and declared_hash is None:
            continue
        if not isinstance(native_hash, str) or len(native_hash) != 64 or declared_hash != native_hash:
            raise RuntimeError('Native/manifest reserve binding mismatch: '+field)
        if sha(source.parent/relative_path) != native_hash:
            raise RuntimeError('Frozen native reserve source changed: '+relative_path)
        reserve_bindings[field] = native_hash
    if reserve_bindings and len(reserve_bindings) != 4:
        raise RuntimeError('Reserve plan and both geometry module bindings must be present')
    pond_description = None
    if landscape_bindings:
        terrain_path = source.parent/'terrain_plan.json'
        if sha(terrain_path) != source_scene.get('terrain_plan_sha256'):
            raise RuntimeError('Frozen native terrain plan changed before pond export')
        pond = json.loads(terrain_path.read_text(encoding='utf-8')).get('park_pond')
        if not pond:
            raise RuntimeError('Landscape-bound source requires its authored pond descriptor')
        pond_description = {'center_gltf_metres': [pond['center'][0], pond['water_z_m'], -pond['center'][1]],
                            'water_level_y_metres': pond['water_z_m'], 'bed_level_y_metres': pond['bed_z_m'],
                            'maximum_depth_metres': pond['maximum_water_depth_m'],
                            'water_radii_metres': pond['water_radii_m'],
                            'water_mesh_prefix': 'Atlantic_Terrain_PondWater',
                            'bed_mesh_prefixes': ['Atlantic_Terrain_Grass', 'Atlantic_Terrain_Dirt'],
                            'verification_scope': 'Visual mesh level/depth only; no physics or hydrology authority'}
    buildings = source_manifest['buildings']
    if len(buildings) != source_manifest['building_count']:
        raise RuntimeError('Building manifest count mismatch')
    source_names = {o.name for o in source_scene.objects}
    bpy.context.window.scene = source_scene
    source_scene.view_layers[0].update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    disabled_bevels = []
    def disable_tiny_bevels():
        for src in source_scene.objects:
            for modifier in src.modifiers:
                if modifier.type == 'BEVEL' and modifier.width <= .025 and modifier.show_viewport:
                    disabled_bevels.append((src.name, modifier.name))
                    modifier.show_viewport = False
        source_scene.view_layers[0].update()
    if opt.detail == 'game':
        disable_tiny_bevels()
    opt.out.mkdir(parents=True, exist_ok=True)
    export_scene = bpy.data.scenes.new('LivingTownPortableExport')
    export_scene.unit_settings.system = 'METRIC'
    export_scene.unit_settings.scale_length = 1
    export_scene.render.fps = source_scene.render.fps
    export_scene.render.fps_base = source_scene.render.fps_base
    export_scene.frame_start = source_scene.frame_start
    export_scene.frame_end = source_scene.frame_end
    collection = export_scene.collection
    root = empty('LivingTown', collection, asset_schema='living_town.glb.v1',
                 source_blend_sha256=source_sha, units='metres', evidence_label=opt.label,
                 **planning_bindings, **landscape_bindings, **reserve_bindings)
    architecture = empty('Buildings', collection, root, building_count=len(buildings))
    environment = empty('Environment', collection, root)
    props = empty('StreetLife', collection, root)
    vegetation = empty('Vegetation', collection, root)
    materials = {}
    conversion_notes = []

    def portable_material(src):
        if src is None:
            return None
        if src.name in materials:
            return materials[src.name]
        dst = src.copy()
        dst.name = src.name+'_PBR'
        # Preserve texture/factor/vertex-colour chains, UVs and tangent normals.
        # Core glTF does not reproduce Blender's procedural ocean bump shader.
        if dst.use_nodes:
            p = next((n for n in dst.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if p:
                normal = p.inputs.get('Normal')
                if normal and normal.is_linked and normal.links[0].from_node.type == 'BUMP':
                    for link in list(normal.links):
                        dst.node_tree.links.remove(link)
                    conversion_notes.append(src.name+': procedural bump omitted; core PBR retained')
                transmission = p.inputs.get('Transmission Weight')
                if transmission and transmission.default_value:
                    transmission.default_value = 0
                    conversion_notes.append(src.name+': transmission extension omitted; source alpha preserved in core PBR')
        materials[src.name] = dst
        return dst

    copied_source = set()
    geometry_records = []
    linked_reserve_meshes = {}
    reserve_tree_cleanup = {}
    def evaluated_mesh(src, to_local):
        evaluated = src.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
        if not len(mesh.vertices):
            bpy.data.meshes.remove(mesh)
            return None
        mesh.transform(to_local @ src.matrix_world)
        # glTF is triangular. Explicitly triangulate n-gons before tangent
        # generation; Blender otherwise drops tangents on some bevel caps.
        if any(poly.loop_total > 4 for poly in mesh.polygons):
            editable = bmesh.new()
            editable.from_mesh(mesh)
            bmesh.ops.triangulate(editable, faces=[face for face in editable.faces if len(face.verts) > 3])
            editable.to_mesh(mesh)
            editable.free()
        for i, src_mat in enumerate(list(mesh.materials)):
            mesh.materials[i] = portable_material(src_mat)
        return mesh
    def clone_mesh(src, parent, to_local, name=None):
        if src.type not in ('MESH', 'CURVE', 'FONT', 'SURFACE'):
            return None
        if src.type == 'MESH' and src.get('reserve_role') == 'tree' and not src.modifiers:
            key=src.data.name
            if key not in linked_reserve_meshes:
                mesh=src.data.copy()
                reserve_tree_cleanup[key]=dict(remove_zero_area_tree_triangles(mesh), instances=0)
                for i,material in enumerate(list(mesh.materials)):
                    mesh.materials[i]=portable_material(material)
                linked_reserve_meshes[key]=mesh
            reserve_tree_cleanup[key]['instances']+=1
            obj=bpy.data.objects.new(name or src.name,linked_reserve_meshes[key])
            collection.objects.link(obj);obj.parent=parent
            obj.matrix_local=to_local @ src.matrix_world
            for key in src.keys():
                if key != '_RNA_UI':obj[key]=src[key]
            obj['source_object']=src.name;obj['visual_only']=True
            copied_source.add(src.name)
            return obj
        mesh = evaluated_mesh(src, to_local)
        if mesh is None:
            return None
        obj = bpy.data.objects.new(name or src.name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        for key in src.keys():
            if key != '_RNA_UI':
                try:
                    obj[key] = src[key]
                except (TypeError, ValueError):
                    pass
        obj['source_object'] = src.name
        obj['visual_only'] = True
        copied_source.add(src.name)
        geometry_records.append((src, obj, to_local.copy()))
        return obj

    building_roots = {}
    building_exports = []
    building_collections = set()
    review_objects = {ob.name for sc in source_scene.collection.children if sc.name.startswith('04_Topographic_Review') for ob in sc.all_objects}
    stage('clone_preparation_started')
    for item in buildings:
        ident = item['id']
        src_coll = bpy.data.collections.get(item.get('collection', ident))
        if src_coll is None:
            raise RuntimeError('Missing native building collection: '+ident)
        if not all(ob.name in source_names for ob in src_coll.all_objects):
            raise RuntimeError('Building collection not contained in selected source scene: '+ident)
        origin = item['center_m']
        angle = math.radians(item.get('yaw_degrees', 0))
        transform = Matrix.Translation(Vector(origin)) @ Matrix.Rotation(angle, 4, 'Z')
        building_root = empty(ident, collection, architecture, building_id=ident,
                              kind=item['kind'], district=item.get('district'),
                              source_ref=item.get('source_ref'), typology=item.get('typology'),
                              units='metres', visual_only=True)
        building_root.matrix_local = transform
        groups = {}
        for role in ('Shell', 'Interior', 'Roof', 'FrontCover', 'UpperCover'):
            groups[role] = empty(ident+'__'+role, collection, building_root, building_id=ident,
                                 role=role, reveal_control=role in ('Roof', 'FrontCover', 'UpperCover'))
        node_map = {src_coll.name: groups['Shell']}
        role_names = {item['roof_collection']: 'Roof', item['front_collection']: 'FrontCover',
                      item['upper_cover_collection']: 'UpperCover', ident+'_Interior': 'Interior'}
        def visit_coll(sc, parent_node):
            building_collections.add(sc.name)
            for child in sc.children:
                role = role_names.get(child.name)
                if role:
                    node = groups[role]
                else:
                    suffix = child.name.removeprefix(ident+'_')
                    node = empty(ident+'__'+suffix, collection, parent_node, source_collection=child.name, building_id=ident)
                    for key in child.keys():
                        if key != '_RNA_UI':
                            try:
                                node[key] = child[key]
                            except (TypeError, ValueError):
                                pass
                node_map[child.name] = node
                visit_coll(child, node)
        visit_coll(src_coll, groups['Shell'])
        for src_obj in src_coll.all_objects:
            if src_obj.type == 'EMPTY':
                continue
            own = next((c for c in src_obj.users_collection if c.name in node_map), src_coll)
            clone_mesh(src_obj, node_map[own.name], transform.inverted(), src_obj.name.removeprefix(ident+'_'))
        entrance = empty(ident+'__EntryAnchor', collection, building_root, anchor_kind='finished_floor_threshold')
        entrance.location = (item.get('door_local_x', 0), -item['footprint_m'][1]/2, .38)
        ground = empty(ident+'__PadAnchor', collection, building_root, anchor_kind='level_parcel_base')
        ground.location = (0, 0, 0)
        building_roots[ident] = building_root
        building_exports.append({'id': ident, 'kind': item['kind'], 'district': item.get('district'),
                                 'source_ref': item.get('source_ref'), 'footprint_metres': item['footprint_m'],
                                 'placement_blender_xyz': origin, 'yaw_blender_degrees': item.get('yaw_degrees', 0),
                                 'placement_gltf_xyz': [origin[0], origin[2], -origin[1]],
                                 'roles': {role: f'Buildings/{ident}/{ident}__{role}' for role in groups},
                                 'role_mesh_counts': {role: sum(ob.type == 'MESH' for ob in descendants(node)) for role, node in groups.items()},
                                 'nested_collection_nodes': [node.name for name, node in node_map.items() if name != src_coll.name and node not in groups.values()]})
        print('Prepared building '+ident, flush=True)
    reserve_building_roots = {}
    reserve_exports = []
    if reserve_bindings:
        reserve_root=empty('NaturalReserve',collection,root,
            reserve_plan_sha256=source_scene['reserve_plan_sha256'],asset_schema='living_town.reserve.v1')
        reserve_records={r['root_collection']:r for r in source_manifest['reserve_amenities']['buildings']}
        def reserve_collection_tree(src_collection,parent,to_local=Matrix.Identity(4)):
            record=reserve_records.get(src_collection.name)
            node=empty(src_collection.name+'__Group',collection,parent,
                source_collection=src_collection.name,reserve_role='collection')
            for key in src_collection.keys():
                if key!='_RNA_UI':
                    node[key]=src_collection[key]
            if record:
                origin=record.get('center_m',record.get('center'))
                # Amenity centers contain XY; floor/pad Z remains an explicit placement datum.
                z=record.get('pad_level_m',0)
                transform=Matrix.Translation(Vector((origin[0],origin[1],z))) @ Matrix.Rotation(math.radians(record.get('yaw_degrees',0)),4,'Z')
                node.matrix_local=transform
                node['reserve_building_id']=record['id']
                node['reserve_role']='building'
                to_local=transform.inverted()
                reserve_building_roots[record['id']]=node
                reserve_exports.append({'id':record['id'],'kind':record['kind'],
                    'placement_blender_xyz':[origin[0],origin[1],z],
                    'placement_gltf_xyz':[origin[0],z,-origin[1]],
                    'yaw_blender_degrees':record.get('yaw_degrees',0),
                    'room_count':record['room_count'],'furnishing_count':record['furnishing_count'],
                    'roof_collection':record['roof_collection'],'front_cover_collection':record['front_cover_collection']})
            for src in src_collection.objects:
                if src.name not in copied_source:
                    clone_mesh(src,node,to_local)
            for child in src_collection.children:
                reserve_collection_tree(child,node,to_local)
        for reserve_collection in source_scene.collection.children:
            if reserve_collection.name in ('06_Natural_Reserve','07_Reserve_Amenities'):
                reserve_collection_tree(reserve_collection,reserve_root)
    for src_obj in source_scene.objects:
        if src_obj.name in copied_source or src_obj.name in review_objects or src_obj.type not in ('MESH', 'CURVE', 'FONT', 'SURFACE'):
            continue
        colls = [c.name for c in src_obj.users_collection]
        if any(c in building_collections or c.startswith('90_') or 'Contour' in c or 'Contour' in src_obj.name for c in colls):
            continue
        if any(c.startswith('03_') for c in colls):
            parent = vegetation
        elif any(c.startswith('02_') for c in colls):
            parent = props
        else:
            parent = environment
        clone_mesh(src_obj, parent, Matrix.Identity(4))
    bpy.context.window.scene = export_scene
    export_scene.view_layers[0].update()
    snapshot_descendants(export_scene.objects)
    world_bounds = bounds(export_scene.objects)
    arch_bounds = bounds(descendants(architecture))
    stage('clone_preparation_completed')

    def export(path, selected, cameras=False):
        bpy.ops.object.select_all(action='DESELECT')
        for ob in selected:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = selected[0]
        result = bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB',
                  use_selection=True, use_active_scene=True, export_extras=True,
                  export_yup=True, export_apply=False, export_animations=cameras,
                  export_cameras=cameras, export_lights=False, export_materials='EXPORT',
                  export_image_format='AUTO', export_normals=True, export_tangents=True,
                  export_texcoords=True, export_hierarchy_full_collections=False)
        if 'FINISHED' not in result:
            raise RuntimeError('glTF export failed: '+str(path))
        flush_file(path)
        return glb_summary(path)

    high_detail = None
    game_detail = None
    if opt.detail in ('both', 'high'):
        stage('high_detail_write_started')
        high_detail = export(opt.out/'living_town.glb', list(export_scene.objects))
        stage('high_detail_write_completed')
    if opt.detail == 'both':
        stage('optimized_mesh_preparation_started')
        bpy.context.window.scene = source_scene
        disable_tiny_bevels()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for index, (src, obj, to_local) in enumerate(geometry_records, 1):
            old_mesh = obj.data
            obj.data = evaluated_mesh(src, to_local)
            if not old_mesh.users:
                retained_unused_mesh_count += 1
            if index % 500 == 0:
                print(f'Prepared optimized mesh {index}/{len(geometry_records)}', flush=True)
        stage('optimized_mesh_references_replaced')
        bpy.context.window.scene = export_scene
        # These high-detail mesh IDs have zero users. Keep them until this
        # disposable CLI exits: ID removal repeatedly dirties dependency
        # graphs, while selected active-scene export cannot include orphans.
        export_scene.view_layers[0].update()
        world_bounds = bounds(export_scene.objects)
        arch_bounds = bounds(descendants(architecture))
        stage('optimized_mesh_preparation_completed')
    if opt.detail in ('both', 'game'):
        stage('game_write_started')
        game_detail = export(opt.out/'living_town_game.glb', list(export_scene.objects))
        stage('game_write_completed')
    budget_overrun = game_detail is not None and game_detail['triangles'] > opt.triangle_budget
    complete = game_detail or high_detail
    if complete['normal_mapped_materials'] < 9:
        raise RuntimeError('Portable town lost expected PBR normal textures')
    expected_colored_meshes = sum(bool(obj.data.color_attributes.active_color) for obj in export_scene.objects if obj.type == 'MESH')
    if complete['vertex_color_primitives'] < expected_colored_meshes:
        raise RuntimeError('Portable town lost active source vertex colors')
    expected_blend = 0
    for material in materials.values():
        if not material.use_nodes:
            continue
        principal = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if principal and not principal.inputs['Alpha'].is_linked and 0 < principal.inputs['Alpha'].default_value < 1:
            expected_blend += 1
    if complete['alpha_blend_materials'] < expected_blend:
        raise RuntimeError('Portable town lost source alpha-blended materials')
    gltf_doc = read_glb(opt.out/complete['file'])
    root_nodes = [n for n in gltf_doc['nodes'] if n.get('extras', {}).get('building_id') in building_roots
                  and n.get('name') in building_roots]
    if len(root_nodes) != len(buildings):
        raise RuntimeError('GLB building hierarchy count differs from source')
    if interior_inventory is not None and interior_metadata_inventory(gltf_doc) != interior_inventory:
        raise RuntimeError('GLB floor, logical-zone or furniture metadata inventory differs from frozen plan')
    category_cost = {ob.name: geometry_cost(descendants(ob)) for ob in (architecture, environment, props, vegetation)}
    if reserve_bindings:
        category_cost['NaturalReserve']=geometry_cost(descendants(reserve_root))
    for item in building_exports:
        br = building_roots[item['id']]
        item['geometry_cost'] = geometry_cost(descendants(br))
        item['role_geometry_cost'] = {role: geometry_cost(descendants(next(ob for ob in br.children if ob.get('role') == role)))
                                     for role in ('Shell', 'Interior', 'Roof', 'FrontCover', 'UpperCover')}
    prefab_dir = opt.out/'buildings'
    if opt.prefabs != 'none':
        prefab_dir.mkdir(exist_ok=True)
    stage('prefabs_write_started')
    for item in building_exports:
        ident = item['id']
        if opt.prefabs == 'none' or (opt.prefabs == 'main' and not ident.startswith('Main_')):
            continue
        br = building_roots[ident]
        original = br.matrix_local.copy()
        br.parent = None
        br.matrix_world = Matrix.Identity(4)
        export_scene.view_layers[0].update()
        local_bounds = yup_bounds(bounds(descendants(br)))
        record = export(prefab_dir/(ident+'.glb'), list(descendants(br)))
        record['file'] = 'buildings/'+ident+'.glb'
        record['local_bounds_gltf_metres'] = local_bounds
        item['standalone'] = record
        br.parent = architecture
        br.matrix_local = original
        export_scene.view_layers[0].update()
    stage('prefabs_write_completed')
    if opt.prefabs != 'none' and reserve_exports:
        stage('reserve_prefabs_write_started')
        reserve_prefab_dir=opt.out/'reserve'
        reserve_prefab_dir.mkdir(exist_ok=True)
        for item in reserve_exports:
            br=reserve_building_roots[item['id']]
            original=br.matrix_local.copy();original_parent=br.parent
            br.parent=None;br.matrix_world=Matrix.Identity(4)
            export_scene.view_layers[0].update()
            record=export(reserve_prefab_dir/(item['id']+'.glb'),list(descendants(br)))
            record['file']='reserve/'+item['id']+'.glb'
            record['local_bounds_gltf_metres']=yup_bounds(bounds(descendants(br)))
            item['standalone']=record
            br.parent=original_parent;br.matrix_local=original
            export_scene.view_layers[0].update()
        stage('reserve_prefabs_write_completed')
    camera_record = None
    if opt.camera_rig:
        stage('camera_write_started')
        camera_root = empty('CameraRig', collection, units='metres', **landscape_bindings)
        camera_objects = [camera_root]
        for src in source_scene.objects:
            if src.type != 'CAMERA':
                continue
            dst = src.copy()
            dst.data = src.data.copy()
            dst.name = src.name+'__portable'
            collection.objects.link(dst)
            dst.parent = camera_root
            dst.matrix_world = src.matrix_world.copy()
            camera_objects.append(dst)
        if len(camera_objects) > 1:
            export_scene.view_layers[0].update()
            camera_record = export(opt.out/'cameras.glb', camera_objects, cameras=True)
            camera_record['camera_count'] = len(camera_objects)-1
            camera_record['frames_per_second'] = source_scene.render.fps/source_scene.render.fps_base
            if any(ob.animation_data and ob.animation_data.action for ob in camera_objects[1:]) and not camera_record['animations']:
                raise RuntimeError('Native camera keyframes were lost during rig export')
        stage('camera_write_completed')
    stage('assets_flushed')
    if sha(source) != source_sha:
        raise RuntimeError('Source blend changed during export; rerun against a frozen source')
    result = {'schema': 'living_town.game_assets.v1', 'status': 'FAIL' if budget_overrun else 'PASS', 'evidence_label': opt.label,
              'exporter_sha256': sha(Path(__file__)),
              'output_flush': 'Each completed GLB and final manifest flushed with os.fsync before consumer handoff',
              'source_blend': source.name, 'source_blend_sha256': source_sha,
              'source_manifest_sha256': sha(manifest_path), 'blender_version': bpy.app.version_string,
              'units': 'metres', 'coordinate_system': 'glTF 2.0 right-handed +Y up; Blender(X,Y,Z) -> glTF(X,Z,-Y)',
              'source_masterplan_sha256': source_scene.get('masterplan_sha256'),
              'source_terrain_plan_sha256': source_scene.get('terrain_plan_sha256'),
              'source_interior_plan_sha256': source_scene.get('interior_plan_sha256'),
              'source_interior_module_sha256': source_scene.get('interior_module_sha256'),
              'source_landscape_plan_sha256': landscape_bindings.get('landscape_plan_sha256'),
              'source_landscape_details_sha256': landscape_bindings.get('landscape_details_sha256'),
              'source_reserve_plan_sha256': source_scene.get('reserve_plan_sha256'),
              'source_reserve_plan_module_sha256': source_scene.get('reserve_plan_module_sha256'),
              'source_reserve_environment_module_sha256': source_scene.get('reserve_environment_module_sha256'),
              'source_reserve_amenities_module_sha256': source_scene.get('reserve_amenities_module_sha256'),
              'reserve_environment': source_manifest.get('reserve_environment'),
              'reserve_amenities': source_manifest.get('reserve_amenities'),
              'linked_reserve_tree_meshes': len(linked_reserve_meshes),
              'portable_binding_fields': sorted(set(planning_bindings) | set(landscape_bindings) | set(reserve_bindings)),
              'reserve_building_count':len(reserve_exports),'reserve_buildings':reserve_exports,
              'interior_inventory': interior_inventory,
              'layout_inventory': layout_inventory,
              'landscape_pond': pond_description,
              'source_world_bounds_gltf_metres': yup_bounds(world_bounds),
              'source_building_bounds_gltf_metres': yup_bounds(arch_bounds),
              'town': complete, 'building_count': len(buildings), 'buildings': building_exports,
              'expected_vertex_colored_meshes': expected_colored_meshes,
              'town_high_detail': high_detail, 'town_game': game_detail,
              'optimization': {'mode': opt.detail, 'game_triangle_budget': opt.triangle_budget,
                               'game_budget_passed': game_detail is None or game_detail['triangles'] <= opt.triangle_budget,
                               'disabled_bevel_modifiers': len(disabled_bevels),
                               'method': 'Omit source BEVEL modifiers <=0.025 m in disposable export copy; triangulate shared copied reserve-tree meshes and delete only faces with geometric area <=1e-12 m²; preserve positions, visible silhouettes, UV/color/material layers, furniture and openings',
                               'reserve_tree_zero_area_cleanup': {
                                   'scope': 'Copied shared tree prototypes only; native meshes, terrain, trails and all instance poses unchanged',
                                   'area_threshold_m2': 1e-12,
                                   'unique_meshes_processed': len(reserve_tree_cleanup),
                                   'expanded_tree_mesh_nodes': sum(r['instances'] for r in reserve_tree_cleanup.values()),
                                   'unique_source_implied_triangles': sum(r['source_implied_triangles'] for r in reserve_tree_cleanup.values()),
                                   'unique_triangles_after': sum(r['triangles_after'] for r in reserve_tree_cleanup.values()),
                                   'unique_zero_area_triangle_faces_deleted': sum(r['zero_area_triangle_faces_deleted'] for r in reserve_tree_cleanup.values()),
                                   'expanded_zero_area_triangle_faces_deleted': sum(r['zero_area_triangle_faces_deleted']*r['instances'] for r in reserve_tree_cleanup.values()),
                                   'unique_triangle_count_reduction': sum(r['triangle_count_reduction'] for r in reserve_tree_cleanup.values()),
                                   'expanded_triangle_count_reduction': sum(r['triangle_count_reduction']*r['instances'] for r in reserve_tree_cleanup.values()),
                                   'maximum_deleted_area_m2': max((r['maximum_deleted_area_m2'] for r in reserve_tree_cleanup.values()), default=0.),
                                   'by_source_mesh': reserve_tree_cleanup},
                               'triangle_reduction_percent': round(100*(1-game_detail['triangles']/high_detail['triangles']), 2) if game_detail and high_detail else None,
                               'byte_reduction_percent': round(100*(1-game_detail['bytes']/high_detail['bytes']), 2) if game_detail and high_detail else None,
                               'lod': 'Distance-selected authored near/far woodland meshes; shared forest meshes remain instanced. Core and reserve local-origin building prefabs supplied.'},
              'export_performance': {'unused_mesh_cleanup': 'Unused high-detail mesh IDs retained until disposable CLI exit; export remains selected objects in active scene only',
                                     'descendant_traversal': 'One cached parent-to-children snapshot and memoized geometry subtrees; prefab root detach preserves internal descendants; camera rig uses explicit selection',
                                     'retained_unused_high_detail_meshes': retained_unused_mesh_count,
                                     'stage_events': stage_events},
              'geometry_cost_by_category': category_cost,
              'visibility_budget_note': 'Counts are loaded asset triangles, not measured on-screen triangles. Floor/room/cover groups allow the consumer to cull locally; no runtime occlusion, streaming or performance claim.',
              'camera_rig': camera_record,
              'material_conversion_notes': sorted(set(conversion_notes)),
              'collision': 'Visual meshes only; no collision or navigation authority supplied',
              'cutaway': 'Toggle only selected building Roof/FrontCover/UpperCover nodes; Interior remains present',
              'excluded': ['Blender camera/light rig', 'optional contour overlay', 'Blender-only procedural sea bump'],
              'portability': 'Core metallic-roughness PBR; embedded PNG images; geometry signs; no engine scripts required'}
    (opt.out/'export_manifest.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    flush_file(opt.out/'export_manifest.json')
    if budget_overrun:
        raise RuntimeError(f"Optimized town exceeds explicit triangle budget: {game_detail['triangles']} > {opt.triangle_budget}. Category and per-building diagnosis saved in export_manifest.json.")
    print(json.dumps({'status': 'PASS', 'label': opt.label, 'buildings': len(buildings), 'town': complete}), flush=True)


if __name__ == '__main__':
    main()
