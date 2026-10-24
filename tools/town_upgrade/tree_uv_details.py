"""Bounded source-replay UV payload adapter; never replays/saves/renders by itself.

Copied pure/native functions retain their frozen tree pilot contracts. The
actual successful unsaved pilot receipt plus both ten-mesh NPZ sets are input;
an absent/pending/failing receipt cannot authorize final native composition.
"""
from __future__ import annotations
import hashlib
import json
import copy
import math
from pathlib import Path
from types import FunctionType,SimpleNamespace
import numpy as np

ENTRY_SHA='b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
SOURCE_PILOT_SHA='edaaa8b72eba71d91b8f76dcd6dc7d0a936ace9df0ad3bf4c8d17bc9edfe3e86'
SOURCE_CONTRACT_SHA='4c7f8ba097f381594d04474b8179baa9264f7e3ecea75785a323938eca6e862e'
LIBRARY_SHA='0244dd0e9d7ef5a7293d4c9d84cf9805efa8858ac5210b422d5fb146f91f0898'
RNA_SHA='b1d99d0d4db0f7968646973b0fc3e3df5506f3fbfd51b3cecb0cf66c9dc40ab1'
PILOT_SUCCESS='EXACT_REPLAY_WOOD_UV_AND_15_FIELDS_PRESERVATION_PASS_ART_PENDING'
EXPECTED_OWNERS={'tree_small_02_0_near_0':361,'tree_small_02_0_far_0':3824,'island_tree_02_0_near_0':93,'island_tree_02_0_far_0':1037,
    'pine_sapling_medium_0_near_0':15,'pine_sapling_medium_0_far_0':456,'pine_sapling_medium_1_near_0':16,'pine_sapling_medium_1_far_0':460,'pine_sapling_medium_2_near_0':15,'pine_sapling_medium_2_far_0':424}

"""Pure exact source/accessor/UV contracts for the bounded tree pilot."""
import hashlib
import math
from pathlib import Path
import numpy as np

ASSETS=('tree_small_02','island_tree_02','pine_sapling_medium')
WOOD_MATERIALS={'tree_small_02_branches','tree_small_02_trunk','island_tree_02','island_tree_02_branches','pine_sapling_medium_bark','pine_sapling_medium_dead_branches'}
LEAF_MATERIALS={'Botanical_Broadleaf','Botanical_Pine_Needles'}
def need(value,message):
    if not value:raise ValueError(message)
def uv_name(index):return 'UVMap' if index==0 else 'UVMap.%03d'%index
def effective_uv(info):
    index=info.get('extensions',{}).get('KHR_texture_transform',{}).get('texCoord',info.get('texCoord',0))
    need(type(index) is int and 0<=index<=7,'Unsupported/invalid effective texture coordinate set');return index

def mapping_vectors(info):
    """Installed importer conversion.py55–69, then RNA float32 storage.

    No mapping is baked into UVs. None means the source has no Mapping node.
    """
    transform=info.get('extensions',{}).get('KHR_texture_transform')
    if not transform:return None
    offset=transform.get('offset',[0,0]);scale=transform.get('scale',[1,1]);rotation=transform.get('rotation',0)
    return {'Location':np.array([offset[0]+scale[1]*math.sin(rotation),1-offset[1]-scale[1]*math.cos(rotation),0],'float32'),
            'Rotation':np.array([0,0,rotation],'float32'),'Scale':np.array([*scale,1],'float32')}
def material_roles(doc):
    result={}
    for material in doc['materials']:
        name=material['name']
        if name not in WOOD_MATERIALS:continue
        pbr=material.get('pbrMetallicRoughness',{})
        channels={'baseColor':pbr.get('baseColorTexture'),'normal':material.get('normalTexture'),'metalRough':pbr.get('metallicRoughnessTexture')}
        need(all(channels.values()),'Registered woody material requires three texture channels: '+name)
        if material.get('occlusionTexture'):channels['occlusion']=material['occlusionTexture']
        indices={effective_uv(row) for row in channels.values()}
        need(len(indices)==1,'Woody channels disagree on effective UV set: '+name)
        index=indices.pop();result[name]={'texcoord':index,'imported_layer':uv_name(index),'source_textureInfo':channels,'mapping_policy':'PRE_MAPPING_UV_ONLY; importer KHR Mapping graph remains unchanged'}
    need(bool(result),'No registered wood materials')
    for mesh in doc.get('meshes',[]):
        for primitive in mesh['primitives']:
            material=doc['materials'][primitive['material']]['name']
            if material in result:need('TEXCOORD_'+str(result[material]['texcoord']) in primitive['attributes'],'Required woody UV accessor is absent: '+material)
    return result

def accessor(doc,index,folder,cache):
    a=doc['accessors'][index];need(not a.get('sparse') and not a.get('normalized',False),'Sparse/normalized source accessor needs a separate reviewed decoder')
    widths={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4};types={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}
    need(a['type'] in widths and a['componentType'] in types,'Unsupported registered accessor type')
    view=doc['bufferViews'][a['bufferView']];buffer=doc['buffers'][view['buffer']];uri=Path(buffer['uri'])
    need(not uri.is_absolute() and '..' not in uri.parts,'Unsafe external glTF buffer path')
    file=Path(folder)/uri
    if file not in cache:cache[file]=file.read_bytes()
    raw=cache[file];dtype=np.dtype(types[a['componentType']]);width=widths[a['type']];count=a['count'];stride=view.get('byteStride',width*dtype.itemsize)
    relative=a.get('byteOffset',0);offset=view.get('byteOffset',0)+relative
    need(type(count) is int and count>=0 and stride>=width*dtype.itemsize and stride%dtype.itemsize==0 and relative>=0 and (count==0 or relative+(count-1)*stride+width*dtype.itemsize<=view['byteLength']) and offset+max(0,count-1)*stride+width*dtype.itemsize<=len(raw),'Source accessor buffer bounds/stride differ')
    return np.ndarray((count,width),dtype=dtype,buffer=raw,offset=offset,strides=(stride,dtype.itemsize)).copy()

def expected_uv(doc,mesh_index,uv_index,folder,cache):
    pieces=[];material_names=[]
    for primitive in doc['meshes'][mesh_index]['primitives']:
        need(primitive.get('mode',4)==4,'Registered source replay requires triangles')
        if 'indices' in primitive:
            indices=accessor(doc,primitive['indices'],folder,cache)
            need(indices.dtype.kind=='u' and indices.shape[1]==1,'Unsigned scalar triangle indices required');indices=indices[:,0]
        else:indices=np.arange(doc['accessors'][primitive['attributes']['POSITION']]['count'],dtype='uint32')
        need(len(indices)%3==0,'Incomplete source triangle primitive')
        key='TEXCOORD_'+str(uv_index)
        if key in primitive['attributes']:
            row=doc['accessors'][primitive['attributes'][key]];need(row['componentType']==5126 and row['type']=='VEC2','Registered UV accessor must be float32 VEC2')
            values=accessor(doc,primitive['attributes'][key],folder,cache);need(not len(indices) or indices.max()<len(values),'UV accessor index out of range');uv=values[indices].copy()
        else:uv=np.zeros((len(indices),2),'float32')
        uv[:,1]=1.-uv[:,1];pieces.append(uv)
        material_names.extend([doc['materials'][primitive['material']]['name']]*(len(indices)//3))
    return np.concatenate(pieces),material_names

def array_state(array):
    array=np.asarray(array);return {'dtype':array.dtype.str,'shape':list(array.shape),'sha256':hashlib.sha256(array.tobytes()).hexdigest()}
def same_bytes(a,b):return array_state(a)==array_state(b)
def compare_arrays(expected,actual,wood_loops,allow_wood_uv=False):
    need(set(expected)==set(actual),'Replay/native buffer key set differs')
    for key in expected:
        if key=='uv' and allow_wood_uv:
            need(same_bytes(expected[key][~wood_loops],actual[key][~wood_loops]),'Complete original leaf UV bytes changed')
        else:need(same_bytes(expected[key],actual[key]),'Exact replay/native buffer differs: '+key)
    return {'status':'EXACT_GEOMETRY_AND_LEAF_UV_PASS','geometry_tolerance':'NONE','leaf_uv_sha256':array_state(actual['uv'][~wood_loops])['sha256'],'wood_uv_sha256':array_state(actual['uv'][wood_loops])['sha256']}

def permitted_material_delta(before,after,fields):
    import copy
    wanted=copy.deepcopy(before);seen=set()
    need(len(fields)==15,'Exact fifteen UV-name fields required')
    for field in fields:
        material,node,old=field['material'],field['node'],field['old']
        need(material in WOOD_MATERIALS and (material,node) not in seen and field['new']=='BotanicalUV','Unexpected/duplicate UV-name correction')
        seen.add((material,node))
        candidates=[n for n in wanted[material]['node_tree']['nodes'] if n['name']==node]
        need(len(candidates)==1 and candidates[0]['settings']['uv_map']==old,'Exact source material UV field differs')
        candidates[0]['settings']['uv_map']='BotanicalUV'
    need(wanted==after,'Material/node/socket/image/mapping/link state changed beyond exact fifteen fields')
    return {'status':'EXACT_15_UV_NAME_FIELDS_ONLY','materials':sorted({r['material'] for r in fields}),'fields':fields,'KHR_mapping_or_pixels_changed':False}

def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def binding(path):
    p=Path(path).resolve(strict=True);return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}

def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def verify(row):need(binding(row['path'])==row,'Bound source changed: '+row['path'])

def mesh_arrays(mesh):
    import numpy as np
    def grab(items,prop,width,dtype):
        values=np.empty((len(items),width),dtype);items.foreach_get(prop,values.ravel());return values if width>1 else values[:,0]
    need(len(mesh.uv_layers)==1 and mesh.uv_layers[0].name=='BotanicalUV' and mesh.uv_layers.active_index==0 and mesh.uv_layers[0].active_render,'Expected exactly active BotanicalUV')
    return {'xyz':grab(mesh.vertices,'co',3,'float32'),'edge_vertices':grab(mesh.edges,'vertices',2,'int32'),
        'loop_vertices':grab(mesh.loops,'vertex_index',1,'int32'),'loop_edges':grab(mesh.loops,'edge_index',1,'int32'),
        'polygon_starts':grab(mesh.polygons,'loop_start',1,'int32'),'polygon_totals':grab(mesh.polygons,'loop_total',1,'int32'),
        'material_index':grab(mesh.polygons,'material_index',1,'int32'),'smooth':grab(mesh.polygons,'use_smooth',1,'bool'),
        'corner_normals':grab(mesh.corner_normals,'vector',3,'float32'),'uv':grab(mesh.uv_layers[0].data,'uv',2,'float32')}

def wood_loops(mesh,C):
    import numpy as np
    indices=np.empty(len(mesh.polygons),'int32');mesh.polygons.foreach_get('material_index',indices)
    names=[m.name if m else None for m in mesh.materials]
    need(set(names)<=C.WOOD_MATERIALS|C.LEAF_MATERIALS and len(names)==3,'Unexpected native/replay tree material roles')
    need(all(len(p.vertices)==3 for p in mesh.polygons),'Tree must remain explicitly triangulated')
    return np.repeat(np.array([names[i] in C.WOOD_MATERIALS for i in indices]),3)

def mapping_proof(materials,doc,roles,C):
    """Check each source channel's existing Mapping/UV nodes, never rebake."""
    import numpy as np
    result={}
    for name,role in roles.items():
        mat=materials.get(name);need(mat and mat.node_tree,'Registered source/native wood material absent')
        channels={}
        for channel,info in role['source_textureInfo'].items():
            tex=doc['textures'][info['index']];image=doc['images'][tex['source']]
            filename=Path(image['uri']).name
            nodes=[n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and Path(n.image.filepath).name==filename]
            need(len(nodes)==1,'Registered per-channel texture identity differs: '+name+'/'+channel)
            node=nodes[0];expected=C.mapping_vectors(info);vector=node.inputs['Vector']
            actual={}
            if expected is not None:
                need(len(vector.links)==1 and vector.links[0].from_node.type=='MAPPING','Existing KHR Mapping node missing/ambiguous')
                mapping=vector.links[0].from_node;need(mapping.vector_type=='POINT','Existing KHR Mapping mode differs')
                for key,value in expected.items():
                    values=np.array(mapping.inputs[key].default_value,'float32')
                    need(C.same_bytes(values,value),'Existing converted KHR Mapping differs: '+name+'/'+channel+'/'+key);actual[key]=values.tolist()
                vector=mapping.inputs['Vector']
            if vector.is_linked:
                need(len(vector.links)==1 and vector.links[0].from_node.type=='UVMAP' and vector.links[0].from_node.uv_map==role['imported_layer'],'Per-channel source UV selector differs')
                actual['uv_selector']=vector.links[0].from_node.uv_map
            else:need(role['texcoord']==0 and expected is None,'Required per-channel UV selector absent');actual['uv_selector']='ACTIVE_UV0'
            channels[channel]={'source_image_filename':filename,'existing_mapping_vectors':actual,'transform_applied_by':'UNCHANGED_EXISTING_SHADER_GRAPH_ONCE','UV_buffer':'PRE_MAPPING_ACCESSOR_VALUES'}
        result[name]=channels
    return result

def structured_materials(bpy,E):
    private=FunctionType(E._materials.__code__,{**E.__dict__,'_digest':lambda value:value})
    return private(bpy)

def placements(bpy,E,C,rna):
    targets=[ob for ob in bpy.context.scene.objects if ob.type=='MESH' and ob.get('vegetation_role') in ('tree','understory') and ob.get('botanical_instance_id')]
    need(len(targets)==30176 and len({ob.data.name for ob in targets})==36,'Original all30176 placements/36meshes differ')
    owners={}
    for ob in targets:owners.setdefault(ob.data.name,[]).append(ob.name)
    for tail,count in EXPECTED_OWNERS.items():need(len(owners.get('BotanicalSource_'+tail,[]))==count,'Exact tree mesh owner count differs')
    need(sum(len(owners['BotanicalSource_'+k]) for k in EXPECTED_OWNERS)==6701,'Exact all6701 tree owners differ')
    for ob in bpy.data.objects:
        for slot in ob.material_slots:
            if slot.material and slot.material.name in C.WOOD_MATERIALS:
                need(ob.type=='MESH' and ob.data.name in owners and ob.data.name in {'BotanicalSource_'+k for k in EXPECTED_OWNERS} and ob.name in owners[ob.data.name],'Wood material has an owner outside proven ten prototype scope')
    for mesh in bpy.data.meshes:
        if any(m and m.name in C.WOOD_MATERIALS for m in mesh.materials):need(mesh.name in owners and mesh.name in {'BotanicalSource_'+k for k in EXPECTED_OWNERS},'Wood material has an unexpected unused/non-target mesh user')
    for curve in bpy.data.curves:need(not any(m and m.name in C.WOOD_MATERIALS for m in curve.materials),'Wood material has a curve/font user')
    return {'count':len(targets),'unique_meshes':36,'tree_owners':6701,'per_mesh_owners':{k:sorted(v) for k,v in owners.items()},'all_object_states_sha256':E._digest({ob.name:E._object_state(ob) for ob in targets})}

def images(bpy,rna):
    result={}
    for name,expected in rna['images'].items():
        image=bpy.data.images.get(name);need(image and image.packed_file,'Original packed botanical image missing')
        actual={'sha256':hashlib.sha256(image.packed_file.data).hexdigest(),'bytes':len(image.packed_file.data),'size':list(image.size),'colorspace':image.colorspace_settings.name,'alpha_mode':image.alpha_mode,'filepath':image.filepath}
        need(actual['sha256']==expected['packed_sha256'] and actual['bytes']==expected['packed_bytes'] and actual['size']==expected['size'] and actual['colorspace']==expected['colorspace'] and actual['alpha_mode']==expected['alpha_mode'] and actual['filepath']==expected['filepath'],'Original packed image/source settings differ: '+name)
        result[name]=actual
    need(len(result)==30,'Expected thirty botanical images');return result

def dangling_uv_fields(bpy,entries):
    result=[]
    for row in entries:
        mesh=bpy.data.meshes[row['mesh']]
        for material in mesh.materials:
            if material and material.node_tree:
                for node in material.node_tree.nodes:
                    name=getattr(node,'uv_map','')
                    if name and mesh.uv_layers.get(name) is None:result.append({'mesh':mesh.name,'material':material.name,'node':node.name,'uv_map':name})
    return result

def prove_mesh_guards(before,after,target_names):
    need(set(before)==set(after),'Actual mesh set changed')
    changed=[]
    for name,row in before.items():
        actual=after[name]
        if name not in target_names:need(row==actual,'Non-target mesh bytes changed: '+name);continue
        expected=copy.deepcopy(row)
        need(len(row['uv_layers'])==1 and row['uv_layers'][0]['name']=='BotanicalUV' and row['attributes']['BotanicalUV']['type']=='FLOAT2','Target guard UV identity differs')
        expected['uv_layers'][0]['sha256']=actual['uv_layers'][0]['sha256']
        expected['attributes']['BotanicalUV']['sha256']=actual['attributes']['BotanicalUV']['sha256']
        need(expected==actual,'Target changed beyond existing UV0 bytes: '+name)
        if row!=actual:changed.append(name)
    need(set(changed)=={'BotanicalSource_tree_small_02_0_near_0','BotanicalSource_tree_small_02_0_far_0'},'Actual changed UV mesh set differs from two small-tree branch transports')
    return {'status':'EXACT_UV_ONLY_LOCAL_MESH_PRESERVATION_PASS','non_target_mesh_count':len(before)-len(target_names),'changed_uv_meshes':changed,'other_eight_tree_meshes_exact':True}

def contract_api():
    return SimpleNamespace(ASSETS=ASSETS,WOOD_MATERIALS=WOOD_MATERIALS,LEAF_MATERIALS=LEAF_MATERIALS,
        array_state=array_state,same_bytes=same_bytes,compare_arrays=compare_arrays,
        mapping_vectors=mapping_vectors,permitted_material_delta=permitted_material_delta)

def raw_state_sha256(state):
    # Exact frozen E._digest serialization, including Unicode preservation.
    return hashlib.sha256(json.dumps(state,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()).hexdigest()

def validate_composed_material_states(original,before_tree,after_tree,fields):
    need(len(original)==133 and set(before_tree)==set(after_tree)==set(original)|{'ContinuousSummer_Grass_Pilot'},'Composed material inventory must be original133 plus one grass shader')
    need({name:before_tree[name] for name in original}==original,'Pre-tree ground/facade shader change cannot be hidden in allowed wood scope')
    return permitted_material_delta(before_tree,after_tree,fields)

def payload_contract(report):
    """Cheap status/scope gate before opening any NPZ or touching a native."""
    need(report['schema']=='living_town.tree_uv_repair_unsaved_pilot.v1' and report['status']==PILOT_SUCCESS,'Actual complete tree UV pilot receipt required; pending/failure cannot authorize payload')
    need(report['native']['sha256']==ENTRY_SHA and report['source_native_unchanged'] is True and report['saved'] is False and report['exported'] is False and report['whole_town_concept_acceptance'] is False,'Tree pilot input/save/review scope differs')
    need(report['all_original_6739_furniture']=='ACTUAL_SAME_PROCESS_EXACT_PASS' and report['material_changes']['status']=='EXACT_15_UV_NAME_FIELDS_ONLY' and not report['dangling_uv_after'] and len(report['dangling_uv_before'])==50,'Tree pilot preservation incomplete')
    expected={'BotanicalSource_'+name for name in EXPECTED_OWNERS}
    for stage in ('baseline_replay','uv_aware_replay'):
        need(set(report[stage]['prototypes'])==expected,'Tree pilot replay mesh set differs')
    for stage in ('baseline_native_exact_buffers','alternate_native_exact_geometry_leaf_buffers'):
        need(set(report[stage])==expected and all(row['status']=='EXACT_GEOMETRY_AND_LEAF_UV_PASS' and row['geometry_tolerance']=='NONE' for row in report[stage].values()),'Tree pilot native/leaf replay proof differs')
    need(report['mesh_preservation']['status']=='EXACT_UV_ONLY_LOCAL_MESH_PRESERVATION_PASS' and set(report['mesh_preservation']['changed_uv_meshes'])=={'BotanicalSource_tree_small_02_0_near_0','BotanicalSource_tree_small_02_0_far_0'},'Exact UV mesh scope differs')
    need(report['placements']['count']==30176 and report['placements']['unique_meshes']==36 and report['placements']['tree_owners']==6701 and len(report['packed_images'])==30,'Tree pilot placement/image inventory differs')
    a,b=report['raw_material_before'],report['raw_material_after']
    need(set(a)==set(b) and len(a)==133 and {k for k in a if a[k]!=b[k]}==WOOD_MATERIALS,'Tree pilot original material change scope differs')
    need(len(report['intended_fields'])==15 and report['material_changes']['fields']==report['intended_fields'],'Exact source fifteen UV fields differ')
    return expected

def validate_array_layout(values,entry):
    vertices,faces=entry['vertices'],entry['triangles'];loops=faces*3
    layouts={'xyz':('float32',(vertices,3)),'edge_vertices':('int32',None),'loop_vertices':('int32',(loops,)),
        'loop_edges':('int32',(loops,)),'polygon_starts':('int32',(faces,)),'polygon_totals':('int32',(faces,)),
        'material_index':('int32',(faces,)),'smooth':('bool',(faces,)),'corner_normals':('float32',(loops,3)),'uv':('float32',(loops,2))}
    need(set(values)==set(layouts),'Tree replay NPZ omits/adds protected geometry/shading buffers')
    for key,(dtype,shape) in layouts.items():
        array=values[key];need(array.dtype==np.dtype(dtype) and (shape is None or array.shape==shape),'Tree replay array dtype/shape differs: '+key)
        if array.dtype.kind=='f':need(np.isfinite(array).all(),'Nonfinite tree replay float buffer: '+key)
    edges=values['edge_vertices']
    need(edges.ndim==2 and edges.shape[1]==2 and len(edges)>0 and edges.min()>=0 and edges.max()<vertices,'Invalid tree replay edge buffer')
    need(values['loop_vertices'].min()>=0 and values['loop_vertices'].max()<vertices and values['loop_edges'].min()>=0 and values['loop_edges'].max()<len(edges),'Invalid tree replay loop topology')
    need(np.all(values['polygon_totals']==3) and np.array_equal(values['polygon_starts'],np.arange(faces,dtype='int32')*3),'Tree replay triangle order differs')
    need(values['material_index'].min()>=0 and values['material_index'].max()<len(entry['materials']),'Tree replay material role index differs')
    return True

def check_payload(folder,expected_receipt_sha256,repo):
    folder,repo=Path(folder).resolve(strict=True),Path(repo).resolve(strict=True)
    receipt=folder/'tree_uv_repair_pilot.json';need(sha(receipt)==expected_receipt_sha256 and len(expected_receipt_sha256)==64,'Actual tree pilot receipt hash differs')
    report=read(receipt);expected=payload_contract(report)
    for relative,expected_sha in [('build/town_upgrade/tree_uv_repair/pilot.py',SOURCE_PILOT_SHA),('build/town_upgrade/tree_uv_repair/contract.py',SOURCE_CONTRACT_SHA)]:
        need(sha(repo/relative)==expected_sha,'Frozen tree pilot/contract source differs')
        matching=[row for row in report['source_bindings'].values() if Path(row['path']).resolve()==(repo/relative).resolve()]
        need(len(matching)==1 and matching[0]['sha256']==expected_sha,'Actual tree pilot source binding missing')
    for row in report['source_bindings'].values():verify(row)
    def source(name,expected_sha):
        rows=[row for row in report['source_bindings'].values() if Path(row['path']).name==name and row['sha256']==expected_sha]
        need(len(rows)==1,'Actual bound source missing/ambiguous: '+name);return read(rows[0]['path'])
    library=source('botanical_prototypes.json',LIBRARY_SHA);rna=source('botanical_material_rna_002.json',RNA_SHA)
    fields=[]
    for name in sorted(WOOD_MATERIALS):
        for node in rna['materials'][name]['nodes']:
            old=node.get('parameters',{}).get('uv_map')
            if old:fields.append({'material':name,'node':node['name'],'old':old,'new':'BotanicalUV'})
    need(fields==report['intended_fields'],'Actual tree payload field list differs from pinned source RNA')
    entries=[row for row in library['entries'] if row['asset'] in ASSETS]
    need({row['mesh'] for row in entries}==expected and len(entries)==10,'Actual library tree mapping differs')
    arrays={};artifact_rows=[]
    for stage in ('baseline_replay','uv_aware_replay'):
        arrays[stage]={}
        for entry in entries:
            name=entry['mesh'];row=report[stage]['prototypes'][name];verify(row['arrays'])
            p=Path(row['arrays']['path']).resolve();need(p.is_relative_to(folder),'Tree NPZ lies outside actual immutable pilot folder')
            with np.load(p,allow_pickle=False) as z:values={k:z[k] for k in z.files}
            validate_array_layout(values,entry)
            need({k:array_state(v) for k,v in values.items()}==row['buffers'] and row['materials']==entry['materials'],'Actual tree NPZ buffers/material roles differ')
            arrays[stage][name]=values;artifact_rows.append(row['arrays'])
    for entry in entries:
        name=entry['mesh'];a=arrays['baseline_replay'][name];b=arrays['uv_aware_replay'][name]
        names=entry['materials'];wood=np.repeat(np.array([names[i] in WOOD_MATERIALS for i in a['material_index']]),3)
        compare_arrays(a,b,wood,True)
        if entry['asset']!='tree_small_02':need(same_bytes(a['uv'],b['uv']),'Payload changes UVs outside two small-tree meshes')
        actual=report['uv_changes'][name]
        need(actual['before']==array_state(a['uv']) and actual['after']==array_state(b['uv']) and actual['leaf_uv_bytes_exact'] is True and actual['wood_loop_count']==int(wood.sum()),'Tree pilot actual assigned UV hashes differ from complete replay payload')
    return {'receipt':binding(receipt),'report':report,'entries':entries,'rna':rna,'arrays':arrays,'artifacts':artifact_rows,
        'proof_scope':'Actual frozen source replay receipt + both exact ten-mesh payloads; art/root final closeups remain pending'}

def preflight_native(bpy,E,payload):
    """Native source target must exactly match original replay, after other stages."""
    C=contract_api();entries=payload['entries'];proof={}
    for entry in entries:
        name=entry['mesh'];mesh=bpy.data.meshes.get(name)
        need(mesh is not None and [m.name for m in mesh.materials]==entry['materials'],'Native tree mesh/material identity differs')
        current=mesh_arrays(mesh);wood=wood_loops(mesh,C)
        proof[name]=compare_arrays(payload['arrays']['baseline_replay'][name],current,wood)
        compare_arrays(current,payload['arrays']['uv_aware_replay'][name],wood,True)
    actual_placements=placements(bpy,E,C,payload['rna']);actual_images=images(bpy,payload['rna'])
    need(actual_placements==payload['report']['placements'] and actual_images==payload['report']['packed_images'],'Actual botanical ownership/placements/images differ from original pilot')
    need(dangling_uv_fields(bpy,entries)==payload['report']['dangling_uv_before'],'Actual dangling source fields differ')
    material_before=structured_materials(bpy,E)
    # Check every source field and the exact intended graph delta BEFORE UVs.
    predicted=copy.deepcopy(material_before)
    for field in payload['report']['intended_fields']:
        node=next(n for n in predicted[field['material']]['node_tree']['nodes'] if n['name']==field['node'])
        need(node['settings']['uv_map']==field['old'],'Source exact wood UV name differs')
        node['settings']['uv_map']=field['new']
    permitted_material_delta(material_before,predicted,payload['report']['intended_fields'])
    return {'materials':material_before,'placements':actual_placements,'images':actual_images,'target_baseline_proof':proof}

def apply(bpy,E,payload,context):
    C=contract_api();changes={}
    # All ten payloads/material users/source fields passed before this firstwrite.
    for entry in payload['entries']:
        name=entry['mesh'];mesh=bpy.data.meshes[name];current=mesh_arrays(mesh);wood=wood_loops(mesh,C)
        wanted=current['uv'].copy();wanted[wood]=payload['arrays']['uv_aware_replay'][name]['uv'][wood]
        if not same_bytes(wanted,current['uv']):
            mesh.uv_layers[0].data.foreach_set('uv',wanted.ravel());mesh.update()
        actual=mesh_arrays(mesh);compare_arrays(current,actual,wood,True)
        need(same_bytes(wanted,actual['uv']),'Actual tree UV write differs from exact payload')
        changes[name]={'before':array_state(current['uv']),'after':array_state(actual['uv']),'complete_leaf_uv_unchanged':same_bytes(current['uv'][~wood],actual['uv'][~wood])}
    for field in payload['report']['intended_fields']:bpy.data.materials[field['material']].node_tree.nodes[field['node']].uv_map=field['new']
    bpy.context.view_layer.update()
    material_proof=permitted_material_delta(context['materials'],structured_materials(bpy,E),payload['report']['intended_fields'])
    need(not dangling_uv_fields(bpy,payload['entries']),'Dangling target tree UV name remains')
    need(placements(bpy,E,C,payload['rna'])==context['placements'] and images(bpy,payload['rna'])==context['images'],'Tree repair changed placements/sharing/images')
    return {'schema':'living_town.composed_tree_uv_delta.v1','status':'EXACT_REPLAY_UV_ONLY_AND_15_FIELDS_PASS_ART_PENDING','source_pilot':payload['receipt'],
        'target_meshes':[row['mesh'] for row in payload['entries']],'uv_changes':changes,'material_changes':material_proof,
        'placements':context['placements'],'packed_images':context['images'],'geometry_leaf_uv_preserved':True,'saved_or_exported_by_stage':False,
        'art_review':'PENDING_ROOT_FINAL_CLOSEUPS_AND_CATALOG','black_leaf_preview_resolution':'NOT_CLAIMED'}


# Revision004 adapters below preserve every copied original function above.
# The only native writes still execute the exact original apply code object;
# its material proof is replaced by the sealed actual 66-path projection.
ALIAS_MODULE_SHA='190764fd19755296284b48d85933a0087c151b4bcc79f41659094298511ea091'
ALIAS_TABLE_SHA='2691ac9303fc377e273f76ef7a50bd91aff2e315c64cac6bf85f2bb86879314a'
ACTUAL_TREE004_SHA='c107356f062abc4c026df43022f2c15da742087e1a887cc827ac2709d0a308a8'
ACTUAL_WRAPPER004_SHA='b4d4a07a7d98e0a46b76ab89104518274ec666301249d975493a717556e1a630'
WRAPPER_SOURCE_SHA='6c0c03a3557033bb9577102a345dd9848dfbcf688781eb6ccf894ab0e2852923'
MATERIAL_V4_STATUS='EXACT_15_UV_NAME_FIELDS_AND_66_MEASURED_SERIALIZED_PATHS_ONLY'
WRAPPER_V4_STATUS='FROZEN_FULL_PIPELINE_EXACT_SOURCE_EVENT_AND_66_PATH_MATERIAL_PROJECTION_PASS_ART_PENDING'


def alias_api():
    import importlib.util
    here=Path(__file__).resolve().parent
    module_path=here/'alias_projection_001.py';table_path=here/'alias_paths_001.json'
    need(sha(module_path)==ALIAS_MODULE_SHA and sha(table_path)==ALIAS_TABLE_SHA,'Sealed exact alias recipe differs')
    spec=importlib.util.spec_from_file_location('composed_tree004_exact_alias',module_path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def payload_contract_v4(report):
    """Require the measured new result, then reuse all old payload assertions."""
    need(report.get('schema')=='living_town.tree_uv_repair_unsaved_pilot.v1'
         and report.get('status')==PILOT_SUCCESS,'Actual completed revision004 tree pilot required')
    proof=report['material_changes']
    need(proof['status']==MATERIAL_V4_STATUS and proof['authored_field_count']==15
         and proof['serialized_changed_path_count']==66 and proof['ignored_or_normalized_state']==[]
         and proof['cross_session_raw_state_equality_claim'] is False
         and proof['model_source']['sha256']==ALIAS_MODULE_SHA and proof['path_table']['sha256']==ALIAS_TABLE_SHA
         and proof['whole_live_after_sha256']==proof['expected_live_after_sha256'],
         'Actual complete exact66-path tree proof required')
    # Only the expected named result identifier differs in the old contract;
    # no scene/material/UV state is normalized or excluded by this adapter.
    old_result=copy.deepcopy(report)
    old_result['material_changes']['status']='EXACT_15_UV_NAME_FIELDS_ONLY'
    return payload_contract(old_result)


def wrapper_contract_v4(wrapper,pilot_binding):
    need(wrapper.get('schema')=='living_town.tree_full_replay_material_alias_wrapper.v4'
         and wrapper.get('status')==WRAPPER_V4_STATUS,'Actual finished revision004 wrapper required; RUNNING/FAIL rejected')
    need(wrapper['actual_full_pipeline_receipt']==pilot_binding
         and wrapper['authored_uv_name_writes']==15 and wrapper['serialized_alias_paths']==66
         and wrapper['ignored_or_normalized_material_fields']==[] and wrapper['saved'] is False
         and wrapper['exported'] is False and wrapper['art_review']=='PENDING'
         and wrapper['original_replay_body_RNG_writes_geometry_leaf_images_placements_full_scene_guards']=='UNCHANGED_FROZEN_EDAAA'
         and len(wrapper['source_checker_records'])==10,
         'Actual finished revision004 full pipeline wrapper required; RUNNING/FAIL cannot authorize composition')
    need(wrapper['private_overrides']==[
        'replay.checked_source_uv: exact frozen revision003 event model',
        'run.load: same frozen contract except exact measured permitted_material_delta projection'],
         'Tree004 override scope differs')
    sources=wrapper['sources']
    need(any(Path(row['path']).name=='pilot.py' and row['sha256']==WRAPPER_SOURCE_SHA for row in sources.values())
         and any(row['sha256']==ALIAS_MODULE_SHA for row in sources.values())
         and any(row['sha256']==ALIAS_TABLE_SHA for row in sources.values()),'Wrapper/alias recipe binding missing')
    return True


def check_payload_v4(folder,expected_receipt_sha256,expected_wrapper_sha256,repo):
    folder=Path(folder).resolve(strict=True)
    need(expected_receipt_sha256==ACTUAL_TREE004_SHA and expected_wrapper_sha256==ACTUAL_WRAPPER004_SHA,
         'Only the exact completed root actual004 proof is accepted')
    wrapped=folder/'revision004_wrapper.json'
    need(sha(wrapped)==expected_wrapper_sha256,'Actual tree004 wrapper bytes differ')
    wrapper=read(wrapped);pilot=binding(folder/'tree_uv_repair_pilot.json')
    wrapper_contract_v4(wrapper,pilot)
    for row in [*wrapper['sources'].values(),*wrapper['source_checker_records']]:verify(row)
    checked=FunctionType(check_payload.__code__,{**check_payload.__globals__,'payload_contract':payload_contract_v4})
    payload=checked(folder,expected_receipt_sha256,repo)
    A=alias_api()
    need(A.encoded(sorted(payload['report']['material_changes']['fields'],key=lambda row:(row['material'],row['node'])))
         ==A.encoded(A.model()['models']['wood_uv']['authors']),
         'Actual tree authors differ from sealed measured path model')
    payload.update(wrapper_receipt=binding(wrapped),wrapper_report=wrapper,
                   alias_recipe_bindings=A.evidence_bindings())
    return payload


def preflight_native_v4(bpy,E,payload):
    # Original source geometry/leaf/owner/image/field gates run unchanged.
    context=preflight_native(bpy,E,payload)
    A=alias_api();predicted=A.expected(context['materials'],'wood_uv')
    A.permitted_material_delta(context['materials'],predicted,payload['report']['intended_fields'])
    context['expected_exact66_materials']=predicted
    return context


def apply_v4(bpy,E,payload,context):
    A=alias_api()
    writer=FunctionType(apply.__code__,{**apply.__globals__,'permitted_material_delta':A.permitted_material_delta})
    result=writer(bpy,E,payload,context)
    need(raw_state_sha256(structured_materials(bpy,E))==raw_state_sha256(context['expected_exact66_materials']),
         'Actual tree004 full material graph differs from preflight finite projection')
    result['source_wrapper']=payload['wrapper_receipt']
    return result


def validate_composed_material_states_v4(original,before_tree,after_tree,fields):
    need(len(original)==133 and set(before_tree)==set(after_tree)==set(original)|{'ContinuousSummer_Grass_Pilot'},
         'Composed material inventory must remain original133 plus one grass shader')
    need(raw_state_sha256({name:before_tree[name] for name in original})==raw_state_sha256(original),
         'Ground/facade changed an original shader before tree UV stage')
    return alias_api().permitted_material_delta(before_tree,after_tree,fields)
