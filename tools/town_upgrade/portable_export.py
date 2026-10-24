"""Export-only preparation, visibility and source bindings for town GLBs.

This module never opens or saves a native scene. Native generation bindings are
separate, so export fixes do not require regenerating unchanged town geometry.
The coordinator supplies the loaded, immutable native in a disposable process.
"""
from collections import defaultdict
from collections import Counter
from array import array
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
EXPORT_SOURCES=(Path(__file__),Path(__file__).with_name('portable_curves.py'),
                Path(__file__).with_name('export_verified_town.py'),
                Path(__file__).with_name('build_whole_town.py'))
VISUAL_TYPES={'MESH','FONT','CURVE','SURFACE'}


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def source_bindings(paths=EXPORT_SOURCES,root=ROOT):
    root=Path(root).resolve();bindings={}
    for path in paths:
        path=Path(path).resolve(strict=True)
        if not path.is_relative_to(root):raise ValueError('Export source outside declared root')
        bindings[path.relative_to(root).as_posix()]={'sha256':sha(path),'bytes':path.stat().st_size}
    return bindings


def verify_sources(bindings,root=ROOT):
    root=Path(root).resolve()
    for relative,row in bindings.items():
        path=(root/relative).resolve(strict=True)
        if not path.is_relative_to(root) or path.stat().st_size!=row['bytes'] or sha(path)!=row['sha256']:
            raise ValueError('Export source changed during export: '+relative)


def write(path,value):
    temporary=path.with_suffix(path.suffix+'.tmp')
    with temporary.open('w',encoding='utf-8',newline='\n') as stream:
        json.dump(value,stream,indent=2,ensure_ascii=False);stream.write('\n')
    temporary.replace(path)


def curve_module():
    name='whole_town_export_only_curve_mesher'
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name('portable_curves.py'))
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module


def group_meshes(objects,rows,scope):
    groups=defaultdict(list);by_building={row['id']:row for row in rows}
    for ob in objects:
        if ob.type!='MESH' or not ob.data.polygons or not scope.get(ob.name,{}).get('eligible',False):continue
        ident=ob.get('building_id',ob.get('interior_building_id',ob.get('reserve_building_id')))
        row=by_building.get(ident)
        if row:
            key='urban_core' if row['group']=='urban' else 'reserve_amenities' if row['group']=='reserve' else row.get('district','expansion')
        elif ob.get('vegetation_role'):
            key='botanical_west' if ob.location.x < -230 else 'botanical_inland' if ob.location.y > 140 else 'botanical_town'
        else:key='territory_landscape'
        groups[key].append(ob)
    return groups


def deselect_all(bpy):
    # Operators can omit hidden objects. Clear their stored selection as well,
    # otherwise a hidden review mesh could leak through use_selection export.
    for ob in bpy.context.scene.objects:
        if ob.select_get():ob.select_set(False)


def verify_triangulated_mesh(source,mesh,face_origins,loop_origins):
    """Check actual per-corner provenance after BMesh's ngon triangulation."""
    if len(source.vertices)!=len(mesh.vertices) or any(tuple(a.co)!=tuple(b.co) for a,b in zip(source.vertices,mesh.vertices)):
        raise ValueError('Portable triangulation changed source vertex positions')
    if list(source.materials)!=list(mesh.materials):raise ValueError('Portable triangulation changed material slots')
    if [layer.name for layer in source.uv_layers]!=[layer.name for layer in mesh.uv_layers]:raise ValueError('Portable triangulation changed UV layers')
    if len(face_origins)!=len(mesh.polygons) or len(loop_origins)!=len(mesh.loops):raise ValueError('Incomplete portable corner provenance')
    counts=Counter()
    for polygon,origin in zip(mesh.polygons,face_origins):
        if not 0<=origin<len(source.polygons):raise ValueError('Invalid portable source polygon')
        before=source.polygons[origin];counts[origin]+=1
        if polygon.loop_total>4 or polygon.material_index!=before.material_index or polygon.use_smooth!=before.use_smooth:
            raise ValueError('Portable triangulation changed face material/smoothing or left an ngon')
        expected=set(range(before.loop_start,before.loop_start+before.loop_total))
        for index in range(polygon.loop_start,polygon.loop_start+polygon.loop_total):
            original=loop_origins[index]
            if original not in expected or mesh.loops[index].vertex_index!=source.loops[original].vertex_index:
                raise ValueError('Portable triangle corner escaped its source polygon')
            for before_uv,after_uv in zip(source.uv_layers,mesh.uv_layers):
                if tuple(before_uv.data[original].uv)!=tuple(after_uv.data[index].uv):raise ValueError('Portable triangulation changed corner UV')
    if set(loop_origins)!=set(range(len(source.loops))):raise ValueError('Portable triangulation omitted source corners')
    if counts!={i:(p.loop_total-2 if p.loop_total>4 else 1) for i,p in enumerate(source.polygons)}:
        raise ValueError('Portable triangulation changed polygon coverage')
    return {'vertices_exact':True,'corner_uvs_exact':True,'material_slots_and_face_assignments_exact':True,
            'smoothing_flags_exact':True,'source_polygons':len(source.polygons),'portable_polygons':len(mesh.polygons),
            'source_ngons':sum(p.loop_total>4 for p in source.polygons)}


def verify_corner_normals(target,observed):
    if len(target)!=len(observed):raise ValueError('Portable corner normal coverage changed')
    if any(not math.isfinite(value) for normal in (*target,*observed) for value in normal):raise ValueError('Nonfinite portable shaded normal')
    maximum=max((math.dist(a,b) for a,b in zip(target,observed)),default=0.)
    if maximum>2e-4:raise ValueError('Portable triangulation changed shaded corner normals')
    return maximum


def triangulated_copy(mesh,bmesh):
    """Prepare only a private mesh copy; preserve the source's shaded corners."""
    if mesh.shape_keys:raise ValueError('Ngon export preparation does not support shape-keyed town meshes: '+mesh.name)
    face_tag='_PortableSourceFace';loop_tag='_PortableSourceLoop'
    if mesh.attributes.get(face_tag) or mesh.attributes.get(loop_tag):raise ValueError('Portable provenance attribute collision: '+mesh.name)
    normals=[tuple(normal.vector) for normal in mesh.corner_normals]
    result=mesh.copy();result.name=mesh.name+'_PortableTriangles';bm=bmesh.new()
    try:
        bm.from_mesh(result);bm.faces.ensure_lookup_table()
        face_layer=bm.faces.layers.int.new(face_tag);loop_layer=bm.loops.layers.int.new(loop_tag)
        for index,face in enumerate(bm.faces):
            face[face_layer]=index
            original=mesh.polygons[index]
            for corner,loop in enumerate(face.loops):loop[loop_layer]=original.loop_start+corner
        bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if len(face.verts)>4],ngon_method='EAR_CLIP')
        bm.to_mesh(result)
    finally:bm.free()
    result.update()
    faces=[value.value for value in result.attributes[face_tag].data]
    loops=[value.value for value in result.attributes[loop_tag].data]
    report=verify_triangulated_mesh(mesh,result,faces,loops)
    # BMesh cannot itself guarantee preservation of split custom normals.
    # Carry the native per-corner normals through the verified corner map,
    # including the native shading of non-planar ngons and smooth neighbours.
    # Blender5.2's legacy normals_split_custom_set encodes INT16_2D angular
    # normals. Its quantization changed six actual positive-area promenade
    # corners by0.01283degrees. Mesh::corner_normals supports FLOAT_VECTOR
    # custom_normal directly: keep the native float32 target vectors instead.
    # https://raw.githubusercontent.com/blender/blender/v5.2.2/source/blender/blenkernel/intern/mesh_normals.cc
    old=result.attributes.get('custom_normal')
    if old:result.attributes.remove(old)
    normal_attribute=result.attributes.new(name='custom_normal',type='FLOAT_VECTOR',domain='CORNER')
    normal_attribute.data.foreach_set('vector',array('f',(value for index in loops for value in normals[index])))
    result.update()
    try:maximum=verify_corner_normals([normals[index] for index in loops],[tuple(value.vector) for value in result.corner_normals])
    except ValueError as error:raise ValueError(str(error)+': '+mesh.name) from error
    report['maximum_corner_normal_difference']=maximum
    report['maximum_allowed_corner_normal_difference']=2e-4
    report['normal_storage']='CORNER/FLOAT_VECTOR custom_normal; no legacy angular encoding'
    report['native_corner_normals_carried']=True
    result.attributes.remove(result.attributes[face_tag]);result.attributes.remove(result.attributes[loop_tag])
    return result,report


def prepare_meshes(bpy,objects):
    """Copy each eligible shared ngon datablock once, in the unsaved scene."""
    import bmesh
    grouped=defaultdict(list)
    for ob in objects:grouped[ob.data.as_pointer()].append(ob)
    pending=[];reports=[];tangent_loops=0
    for users in grouped.values():
        source=users[0].data;mesh=source
        if any(p.loop_total>4 for p in source.polygons):
            mesh,report=triangulated_copy(source,bmesh)
            report.update(source_mesh=source.name,portable_mesh=mesh.name,eligible_objects=[ob.name for ob in users])
            reports.append(report);pending.append((users,mesh))
        if mesh.uv_layers:
            # Match the actual glTF exporter's call and fail before publishing
            # chunks if even one eligible mesh still cannot supply tangents.
            mesh.calc_tangents()
            if any(not math.isfinite(value) for loop in mesh.loops for value in (*loop.tangent,loop.bitangent_sign)):
                raise ValueError('Nonfinite portable tangent frame: '+mesh.name)
            tangent_loops+=len(mesh.loops)
    for users,mesh in pending:
        for ob in users:ob.data=mesh
    bpy.context.view_layer.update()
    return {'schema':'living_town.portable_mesh_preparation.v1','status':'PASS','helper_sha256':sha(__file__),
            'unique_eligible_meshes':len(grouped),'copied_ngon_meshes':len(reports),'verified_tangent_loops':tangent_loops,
            'meshes':reports,'policy':'Only eligible ngon mesh datablocks are privately copied, triangulated and shared by their original eligible users. Native positions, UVs, materials and shaded corners are checked. No scene save or normal-map removal.'}


def export_chunks(bpy,output,rows):
    output=Path(output);bindings=source_bindings();curves=curve_module()
    scope=curves.render_scope(bpy.context.scene)
    excluded=[row for row in scope.values() if row['type'] in VISUAL_TYPES and not row['eligible']]
    curve_receipt=curves.prepare(bpy,scope)
    write(output/'portable_curve_meshing.json',curve_receipt)
    groups=group_meshes(list(bpy.context.scene.objects),rows,scope)
    if not groups:raise ValueError('No render-eligible meshes to export')
    mesh_receipt=prepare_meshes(bpy,[ob for objects in groups.values() for ob in objects])
    write(output/'portable_mesh_preparation.json',mesh_receipt)
    verify_sources(bindings)
    folder=output/'chunks';folder.mkdir();records=[]
    for key,objects in sorted(groups.items()):
        verify_sources(bindings);deselect_all(bpy)
        for ob in objects:ob.select_set(True)
        selected={ob.name for ob in bpy.context.scene.objects if ob.select_get()}
        if selected!={ob.name for ob in objects}:raise ValueError('Portable export selection escaped its eligible chunk')
        bpy.context.view_layer.objects.active=objects[0];path=folder/(key+'.glb')
        print(f'WHOLE_TOWN_EXPORT {key} {len(objects)}',flush=True)
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_renderable=True,
            export_apply=False,export_yup=True,export_texcoords=True,export_normals=True,export_tangents=True,
            export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=True,export_all_vertex_colors=False)
        verify_sources(bindings)
        records.append({'id':key,'path':path.relative_to(output).as_posix(),'sha256':sha(path),'bytes':path.stat().st_size,
                        'baseline':False,'mesh_objects':len(objects),'unique_meshes':len({ob.data.as_pointer() for ob in objects})})
    curve_receipt['exported_mesh_verification']=curves.verify_export([output/row['path'] for row in records],curve_receipt)
    write(output/'portable_curve_meshing.json',curve_receipt)
    verify_sources(bindings);deselect_all(bpy)
    receipt={'schema':'living_town.portable_export.v1','status':'PASS','export_sources':bindings,
             'vertex_color_policy':'MATERIAL-used layers only; export_all_vertex_colors=False preserves native linear COLOR_0 and material-specific white protection.',
             'source_stability':'PASS: exact export source hashes checked before and after every chunk and at completion.',
             'visibility_policy':'Object hide_render and every scene collection parent path; any visible path wins. Viewport hiding is not an export policy.',
             'excluded_source_objects':excluded,'exported_chunks':records,
             'portable_curve_receipt_sha256':sha(output/'portable_curve_meshing.json'),
             'portable_mesh_receipt_sha256':sha(output/'portable_mesh_preparation.json'),
             'scope':'Portable byte/visibility/source verification; appearance and actual runtime behavior are separate checks.'}
    write(output/'portable_export_receipt.json',receipt);verify_sources(bindings)
    return records
