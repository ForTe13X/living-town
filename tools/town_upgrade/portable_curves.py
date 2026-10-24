"""Mesh actual evaluated lettering/contours for portable glTF interchange.

Called only in the disposable export scene, after the packed editable native
has been saved. Original curve/font data remain in that immutable native.
"""
from array import array
import hashlib
import math
from pathlib import Path
import json
import struct


def geometry_sha(mesh):
    digest=hashlib.sha256()
    for kind,field,count,items in (("f","co",3,mesh.vertices),("i","vertex_index",1,mesh.loops),
                                   ("i","loop_start",1,mesh.polygons),("i","loop_total",1,mesh.polygons),
                                   ("i","material_index",1,mesh.polygons)):
        values=array(kind,[0])*(len(items)*count);items.foreach_get(field,values);digest.update(values.tobytes())
    return digest.hexdigest()


def render_scope(scene):
    """Scene render visibility through collection parents; any visible path wins.

    Deliberately independent of viewport eyes and view-layer exclusions. Hidden
    review collections stay out of production exports even when their objects'
    own hide_render flags are false. One object can belong to several paths.
    """
    rows={}
    def walk(collection,parents,blocked,ancestors):
        identity=id(collection)
        if identity in ancestors:raise ValueError('Collection cycle in render scope')
        hidden=blocked or bool(collection.hide_render)
        path=parents+[collection.name]
        for ob in collection.objects:
            row=rows.setdefault(ob.name,{'name':ob.name,'type':ob.type,'object_hide_render':bool(ob.hide_render),
                                        'eligible':False,'collection_paths':[]})
            visible=not hidden and not bool(ob.hide_render)
            row['eligible']=row['eligible'] or visible
            row['collection_paths'].append({'path':path,'render_enabled':visible})
        for child in collection.children:walk(child,path,hidden,ancestors|{identity})
    walk(scene.collection,[],False,set())
    for row in rows.values():
        if not row['eligible']:
            row['reason']='object.hide_render' if row['object_hide_render'] else 'all scene collection paths hidden by hide_render'
    return rows


def prepare(bpy,scope=None):
    scope=render_scope(bpy.context.scene) if scope is None else scope
    curve_types=('FONT','CURVE','SURFACE')
    source=[ob for ob in bpy.context.scene.objects if ob.type in curve_types and scope[ob.name]['eligible']]
    excluded=[row for row in scope.values() if row['type'] in curve_types and not row['eligible']]
    bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get()
    prepared=[];pending=[]
    for ob in source:
        name=ob.name;kind=ob.type;data=ob.data
        evaluated=ob.evaluated_get(graph)
        mesh=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=graph)
        if not mesh.polygons:raise ValueError('Empty evaluated portable curve: '+name)
        if any(not math.isfinite(value) for vertex in mesh.vertices for value in vertex.co):raise ValueError('Nonfinite portable curve: '+name)
        mesh.name=data.name+'_PortableMesh';before=geometry_sha(mesh)
        # Plain lettering/contour colors need no special shader or font runtime.
        # Provide ordinary metric UV0 so tangent export is also well-defined.
        if not mesh.uv_layers:
            uv=mesh.uv_layers.new(name='MetricUV')
            for loop in mesh.loops:
                point=mesh.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(point.x,point.y)
        transform=evaluated.matrix_world.copy();properties={key:value for key,value in ob.items()}
        pending.append((ob,name,kind,data,mesh,before,transform,properties,list(ob.users_collection)))
    # Snapshot all evaluated surfaces before linking any new scene object.
    # This avoids repeated invalidation of the large woodland dependency graph.
    for ob,name,kind,data,mesh,before,transform,properties,collections in pending:
        ob.name='EditableSource_'+name
        portable=bpy.data.objects.new(name,mesh)
        for collection in collections:collection.objects.link(portable)
        portable.matrix_world=transform
        for key,value in properties.items():portable[key]=value
        portable['portable_source_type']=kind
        portable['portable_source_name']=name
        if kind=='FONT':portable['portable_text']=data.body
        if geometry_sha(mesh)!=before:raise RuntimeError('UV preparation changed evaluated curve geometry: '+name)
        prepared.append({'source_name':name,'source_type':kind,'portable_object_name':portable.name,
                         'building_id':portable.get('building_id'),'presentation_layer':portable.get('presentation_layer'),
                         'geometry_sha256':before,'vertices':len(mesh.vertices),'polygons':len(mesh.polygons),
                         'matrix_world':[list(row) for row in transform],
                         'text':data.body if kind=='FONT' else None,
                         'font':data.font.name if kind=='FONT' else None})
    return {'schema':'living_town.portable_curves.v1','objects':prepared,'font_count':sum(row['source_type']=='FONT' for row in prepared),
            'curve_count':sum(row['source_type']!='FONT' for row in prepared),
            'excluded_source_objects':excluded,
            'helper_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'visibility_policy':'Object hide_render and every scene collection parent path; any visible path wins. Hidden review overlays are excluded.',
            'policy':'Exact evaluated eligible native surfaces, materials, world transforms, names and ownership exported as ordinary meshes. Editable native curve/font file is not saved or modified by this stage.'}


def verify_export(paths,receipt):
    """Require every prepared sign/contour to exist as a real exported mesh."""
    expected={row['portable_object_name']:row for row in receipt['objects']}
    found={}
    for path in paths:
        with Path(path).open('rb') as stream:
            header=stream.read(12);length,kind=struct.unpack('<II',stream.read(8))
            if len(header)!=12 or struct.unpack('<4sII',header)!=(b'glTF',2,Path(path).stat().st_size) or kind!=0x4e4f534a:raise ValueError('Invalid portable GLB')
            document=json.loads(stream.read(length))
        for node in document.get('nodes',[]):
            name=node.get('name')
            if name not in expected:continue
            if name in found:raise ValueError('Duplicated portable curve node: '+name)
            if not isinstance(node.get('mesh'),int):raise ValueError('Portable sign is not an exported mesh: '+name)
            mesh=document['meshes'][node['mesh']];count=0
            for primitive in mesh.get('primitives',[]):
                position=primitive.get('attributes',{}).get('POSITION')
                if position is None:raise ValueError('Portable curve has no exported vertices: '+name)
                count+=document['accessors'][position]['count']
                if 'TEXCOORD_0' not in primitive.get('attributes',{}):raise ValueError('Missing portable metric UV0: '+name)
            if count<=0:raise ValueError('Empty portable sign mesh: '+name)
            extras=node.get('extras',{});source=expected[name]
            if extras.get('portable_source_type')!=source['source_type'] or extras.get('building_id')!=source.get('building_id'):raise ValueError('Portable curve ownership/source metadata changed: '+name)
            if source['source_type']=='FONT' and extras.get('portable_text')!=source['text']:raise ValueError('Portable sign text changed: '+name)
            found[name]={'glb':Path(path).name,'position_vertices':count}
    if set(found)!=set(expected):raise ValueError('Portable text/contours omitted: '+', '.join(sorted(set(expected)-set(found))))
    return {'status':'PASS','mesh_nodes':found,'count':len(found),'scope':'Actual GLB mesh vertices, UV0, source kind, text and ownership; separate from appearance/runtime tests.'}
