"""Exact native ground functions promoted from the source-bound unsaved002 pilot.

No engine runs on import. Preparation is a bound external artifact, not an
implicit relative dependency. All selected changes need the compositor's art
receipts and final source/preservation checks before any native is saved.
"""
import hashlib
import math
import numpy as np
from types import SimpleNamespace
import json
from pathlib import Path

SOURCE_PILOT_SHA256='d4eedfb0e7bf24f0ad75aa48c0b7ef829cbc4733cdf39b6f8d5d10f08a6efd08'
SOURCE_PREPARER_SHA256='b35e68a08396331b42e1ac8dd942b84e9efdf9344da6d28f49fae79a5c8a482a'
PREPARED_SHA256='0a225fab2d2b9677ee2bf90f2c6d2fbd35df746a76d531c47b0738480c17e665'
ENTRY_SHA256='b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
GROUND='Atlantic_Terrain_Grass'
OLD_MATERIAL='Refined_Terrain_PortableAtlas'
SOIL='Reference_Pocket_Gardens_Dirt'
SOIL_SHA='b26092090bc65cfd765fa0edb0b2ca5206795698d4e0eb14ecd671485bbb1b2e'
MATERIAL='ContinuousSummer_Grass_Pilot'
COLOUR='TownSummerMacro'
WOODLAND_MAX=.02
ROCK_BLEND_MAX=.05

def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def binding(path):
    p=Path(path).resolve(strict=True)
    return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}

def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def write(path,value):
    p=Path(path);temporary=p.with_name(p.name+'.tmp')
    temporary.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n',encoding='utf-8');temporary.replace(p)

def array_hash(collection,property_name,width=1,dtype='float32'):
    import numpy as np
    values=np.empty(len(collection)*width,dtype=dtype)
    collection.foreach_get(property_name,values)
    return hashlib.sha256(values.tobytes()).hexdigest()

def attribute_guard(mesh):
    fields={'FLOAT':('value',1,'float32'),'INT':('value',1,'int32'),'INT8':('value',1,'int8'),'BOOLEAN':('value',1,'bool'),
        'FLOAT_VECTOR':('vector',3,'float32'),'FLOAT2':('vector',2,'float32'),'INT16_2D':('value',2,'int32'),'INT32_2D':('value',2,'int32'),
        'FLOAT_COLOR':('color',4,'float32'),'BYTE_COLOR':('color',4,'float32'),'QUATERNION':('value',4,'float32'),'FLOAT4X4':('value',16,'float32')}
    result={}
    for attr in mesh.attributes:
        if attr.data_type not in fields:raise ValueError('Unreviewed native attribute type '+attr.data_type)
        prop,width,dtype=fields[attr.data_type]
        if attr.data_type=='INT16_2D' and len(attr.data):
            # Actual Blender5.2.2 Short2AttributeValue RNA is INT[2].
            # foreach_get exposes its signed shorts losslessly as int32;
            # do not truncate, skip it, or substitute a visual-only check.
            rna=attr.data[0].bl_rna.properties.get(prop)
            if rna is None or rna.type!='INT' or rna.array_length!=2:raise ValueError('INT16_2D RNA is not the measured signed INT[2] representation')
        result[attr.name]={'type':attr.data_type,'domain':attr.domain,'count':len(attr.data),'sha256':array_hash(attr.data,prop,width,dtype)}
    return result

def mesh_guard(mesh,E):
    return {'geometry':{'vertices':len(mesh.vertices),'loops':len(mesh.loops),'polygons':len(mesh.polygons),'edges':len(mesh.edges),
            'positions_sha256':array_hash(mesh.vertices,'co',3),'loop_vertices_sha256':array_hash(mesh.loops,'vertex_index',1,'int32'),
            'polygon_starts_sha256':array_hash(mesh.polygons,'loop_start',1,'int32'),'polygon_totals_sha256':array_hash(mesh.polygons,'loop_total',1,'int32'),
            'edge_vertices_sha256':array_hash(mesh.edges,'vertices',2,'int32'),'smooth_sha256':array_hash(mesh.polygons,'use_smooth',1,'bool')},
        'materials':[m.name if m else None for m in mesh.materials],
        'polygon_material_sha256':array_hash(mesh.polygons,'material_index',1,'int32'),
        'uv_layers':[{'name':uv.name,'active_render':uv.active_render,'sha256':array_hash(uv.data,'uv',2)} for uv in mesh.uv_layers],
        'active_uv':mesh.uv_layers.active_index,'attributes':attribute_guard(mesh),
        'colour_names':[a.name for a in mesh.color_attributes],
        'colour_active_index':mesh.color_attributes.active_color_index,'colour_render_index':mesh.color_attributes.render_color_index,
        'custom_properties':E._plain(dict(mesh.items()))}

def scene_guard(bpy,E):
    meshes,objects,other_data={},{},{}
    for ob in bpy.data.objects:
        objects[ob.name]=E._digest(E._object_state(ob))
        if ob.type=='MESH' and ob.data.name not in meshes:meshes[ob.data.name]=mesh_guard(ob.data,E)
        elif ob.data and ob.type!='MESH' and (ob.type+':'+ob.data.name_full) not in other_data:
            other_data[ob.type+':'+ob.data.name_full]=E._digest(E._curve_state(ob.data) if ob.type in ['FONT','CURVE'] else E._rna_values(ob.data))
    return {'objects':objects,'meshes':meshes,'other_data':other_data,'materials':E._materials(bpy)}

def furniture_guard(bpy,baseline,helper):
    result={};failed=[]
    for name,expected in baseline.items():
        ob=bpy.data.objects.get(name)
        actual=helper.mesh_fingerprint(ob) if ob and ob.type=='MESH' else None
        result[name]=actual['geometry_sha256'] if actual else None
        if actual is None or actual['geometry_sha256']!=expected['geometry_sha256']:failed.append(name)
    if failed:raise ValueError('Original furnishing geometry/pose changed: '+str(failed[:12]))
    return {'count':len(result),'all_original_6739_match':len(result)==6739,'actual_geometry_sha256':result,
        'inventory_sha256':digest(result),'helper':'building_native_audit.mesh_fingerprint; source furniture scope only, not a re-run of full shell/aperture geometry audit'}

def native_arrays(ob):
    import numpy as np
    mesh=ob.data
    local=np.empty((len(mesh.vertices),3),'float32');mesh.vertices.foreach_get('co',local.ravel())
    indices=np.empty(len(mesh.loops),'int32');mesh.loops.foreach_get('vertex_index',indices)
    starts=np.empty(len(mesh.polygons),'int32');mesh.polygons.foreach_get('loop_start',starts)
    totals=np.empty(len(mesh.polygons),'int32');mesh.polygons.foreach_get('loop_total',totals)
    materials=np.empty(len(mesh.polygons),'int32');mesh.polygons.foreach_get('material_index',materials)
    if not np.all(totals==3) or not np.array_equal(starts,np.arange(len(starts))*3):raise ValueError('Exact source terrain must remain its original triangle topology')
    matrix=np.asarray(ob.matrix_world,dtype='float64')
    world=local@matrix[:3,:3].T+matrix[:3,3]
    uv=np.empty((len(indices),2),'float32');mesh.uv_layers[0].data.foreach_get('uv',uv.ravel())
    return {'world':world,'indices':indices,'starts':starts,'totals':totals,'materials':materials,'uv':uv}

def select_faces(data,old_slot,woodland,rock,bounds,P):
    import numpy as np
    world,indices=data['world'],data['indices']
    vertex_ok=(P.sample_grid(woodland,world[:,:2],bounds)<=P.WOODLAND_MAX)&(P.sample_grid(rock,world[:,:2],bounds)<=P.ROCK_BLEND_MAX)
    centers=world[indices].reshape((-1,3,3)).mean(axis=1)
    corners_ok=np.all(vertex_ok[indices].reshape((-1,3)),axis=1)
    center_ok=(P.sample_grid(woodland,centers[:,:2],bounds)<=P.WOODLAND_MAX)&(P.sample_grid(rock,centers[:,:2],bounds)<=P.ROCK_BLEND_MAX)
    selected=(data['materials']==old_slot)&corners_ok&center_ok
    if not selected.any():raise ValueError('No actual safe maintained-grass source faces matched')
    return selected,centers

def rebased_uv(data,selected,centers):
    import numpy as np
    loops=np.repeat(selected,3)
    tile=np.floor(centers[selected,:2]/64).astype('int32')
    offsets=tile*32
    uv=data['uv'].copy()
    uv[loops]=(data['world'][data['indices'][loops],:2]/2.-np.repeat(offsets,3,axis=0)).astype('float32')
    if uv[loops].min() < -1.5 or uv[loops].max()>33.5:raise ValueError('An actual face exceeds bounded integer64m tile; refuse geometry changes')
    return uv,loops,tile

def make_material(bpy,record,uv_name):
    if bpy.data.materials.get(MATERIAL):raise ValueError('Pilot material already exists in source')
    mat=bpy.data.materials.new(MATERIAL);mat.use_nodes=True
    ns,links=mat.node_tree.nodes,mat.node_tree.links;shader=ns.get('Principled BSDF')
    uv=ns.new('ShaderNodeUVMap');uv.uv_map=uv_name
    images={};packed={}
    for role in ['diff','nor_gl','arm']:
        row=record['material_images'][role]
        image=bpy.data.images.load(row['path'],check_existing=False)
        if tuple(image.size)!=(2048,2048):raise ValueError('Prepared channel is not2K')
        image.colorspace_settings.name=row['colorspace'];image.pack()
        if not image.packed_file or hashlib.sha256(image.packed_file.data).hexdigest()!=row['sha256']:raise ValueError('Actual packed map bytes differ '+role)
        tex=ns.new('ShaderNodeTexImage');tex.image=image;tex.extension='REPEAT'
        links.new(uv.outputs['UV'],tex.inputs['Vector']);images[role]=tex
        packed[role]={'name':image.name,'bytes':len(image.packed_file.data),'sha256':hashlib.sha256(image.packed_file.data).hexdigest(),'colorspace':image.colorspace_settings.name}
    colour=ns.new('ShaderNodeVertexColor');colour.layer_name=COLOUR
    mix=ns.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MULTIPLY';mix.inputs['Factor'].default_value=1.
    a=next(s for s in mix.inputs if s.identifier=='A_Color');b=next(s for s in mix.inputs if s.identifier=='B_Color')
    result=next(s for s in mix.outputs if s.type=='RGBA' and s.enabled)
    links.new(images['diff'].outputs['Color'],a);links.new(colour.outputs['Color'],b);links.new(result,shader.inputs['Base Color'])
    normal=ns.new('ShaderNodeNormalMap');normal.uv_map=uv_name;normal.inputs['Strength'].default_value=.65
    links.new(images['nor_gl'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],shader.inputs['Normal'])
    split=ns.new('ShaderNodeSeparateColor');links.new(images['arm'].outputs['Color'],split.inputs['Color'])
    links.new(split.outputs['Green'],shader.inputs['Roughness']);links.new(split.outputs['Blue'],shader.inputs['Metallic'])
    shader.inputs['Alpha'].default_value=1.
    mat['source_license']='CC0-1.0';mat['source_asset']='leafy_grass';mat['physical_repeat_m']=2.;mat['pilot_only']=True
    evidence={'material':mat.name,'colour_attribute':COLOUR,'mix':{'type':mix.type,'data_type':mix.data_type,'blend_type':mix.blend_type,'factor':mix.inputs['Factor'].default_value,'A_identifier':a.identifier,'B_identifier':b.identifier},
        'links':[(l.from_node.name,l.from_socket.identifier,l.to_node.name,l.to_socket.identifier) for l in links],
        'packed_images':packed,'normal_strength':.65,'all_channels_uv0':uv_name,'repeat':True,'opaque_alpha':1.,'AO_red':'UNBOUND_NOT_CLAIMED'}
    return mat,evidence

def apply_terrain(bpy,terrain,data,selected,centers,record,P,output):
    import numpy as np
    mesh=terrain.data
    if COLOUR in mesh.color_attributes:raise ValueError('New named colour attribute already exists')
    uv,loops,tile=rebased_uv(data,selected,centers)
    points=data['world'][data['indices'][loops],:2];x0,y0,x1,y1=record['bounds_xy_m']
    expected=np.column_stack(((points[:,0]-x0)/(x1-x0),(points[:,1]-y0)/(y1-y0)))
    error=float(np.max(np.abs(expected-data['uv'][loops])))
    if error>2e-7:raise ValueError('Original selected UV0 does not match source-bound world atlas mapping')
    colour_grid=np.load(record['outputs']['macro_color_linear.npy']['path'],mmap_mode='r',allow_pickle=False)
    touched=np.unique(data['indices'][loops]);sampled=P.sample_grid(colour_grid,data['world'][touched,:2],record['bounds_xy_m']).astype('float32')
    if not np.isfinite(sampled).all() or sampled.min()<0 or sampled.max()>1:raise ValueError('Actual selected POINT colours clip; refuse clamp')
    rgba=np.ones((len(mesh.vertices),4),'float32');rgba[touched,:3]=sampled
    old_active=mesh.color_attributes.active_color_index;old_render=mesh.color_attributes.render_color_index;old_colour_count=len(mesh.color_attributes)
    normal_before=array_hash(mesh.corner_normals,'vector',3)
    mat,node_proof=make_material(bpy,record,mesh.uv_layers[0].name)
    layer=mesh.color_attributes.new(name=COLOUR,type='FLOAT_COLOR',domain='POINT');layer.data.foreach_set('color',rgba.ravel())
    if old_colour_count:
        mesh.color_attributes.active_color_index=old_active;mesh.color_attributes.render_color_index=old_render
    new_slot=len(mesh.materials);mesh.materials.append(mat)
    materials=data['materials'].copy();materials[selected]=new_slot
    mesh.uv_layers[0].data.foreach_set('uv',uv.ravel());mesh.polygons.foreach_set('material_index',materials);mesh.update()
    mesh.calc_tangents(uvmap=mesh.uv_layers[0].name);bpy.context.view_layer.update()
    actual_uv=np.empty_like(uv);mesh.uv_layers[0].data.foreach_get('uv',actual_uv.ravel())
    actual_materials=np.empty_like(materials);mesh.polygons.foreach_get('material_index',actual_materials)
    actual_colours=np.empty_like(rgba);layer.data.foreach_get('color',actual_colours.ravel())
    if not np.array_equal(actual_uv,uv) or not np.array_equal(actual_materials,materials) or not np.array_equal(actual_colours,rgba):raise ValueError('Actual intended UV/material/linear colour write differs')
    if not np.array_equal(actual_uv[~loops],data['uv'][~loops]) or not np.array_equal(actual_materials[~selected],data['materials'][~selected]):raise ValueError('Protected terrain UV/material changed')
    if normal_before!=array_hash(mesh.corner_normals,'vector',3):raise ValueError('UV material pilot changed original native corner normals')
    variants=np.column_stack((data['indices'][loops],np.repeat(tile,3,axis=0)))
    unique_variants=np.unique(variants,axis=0)
    counts=np.unique(unique_variants[:,0],return_counts=True)[1]
    tangent_hash=hashlib.sha256()
    tangents=np.empty((len(mesh.loops),3),'float32');mesh.loops.foreach_get('tangent',tangents.ravel());tangent_hash.update(tangents[loops].tobytes())
    scope=Path(output)/'actual_terrain_scope.npz'
    np.savez_compressed(scope,selected_face_indices=np.flatnonzero(selected).astype('int32'),selected_loop_indices=np.flatnonzero(loops).astype('int32'),
        selected_face64m_tile_xy=tile.astype('int32'),selected_native_vertex_indices=touched.astype('int32'))
    report={'source_material':OLD_MATERIAL,'new_material':mat.name,'new_slot':new_slot,'selected_faces':int(selected.sum()),'protected_faces':int((~selected).sum()),'selected_loops':int(loops.sum()),
        'selected_face_indices_sha256':hashlib.sha256(np.flatnonzero(selected).astype('int32').tobytes()).hexdigest(),
        'selected_loop_indices_sha256':hashlib.sha256(np.flatnonzero(loops).astype('int32').tobytes()).hexdigest(),
        'actual_scope_arrays':binding(scope),
        'original_world_atlas_uv_max_error':error,'actual_uv_range':[actual_uv[loops].min(axis=0).tolist(),actual_uv[loops].max(axis=0).tolist()],
        'distinct64m_tiles':int(len(np.unique(tile,axis=0))),'selected_native_vertices':int(len(touched)),
        'native_vertices_with_multiple_tile_uv_variants':int(np.sum(counts>1)),'additional_tile_uv_variants':int(np.sum(counts-1)),
        'export_vertex_increase':'NOT_MEASURED_NO_EXPORT; UV variants are native loop requests, not actual exported vertex count',
        'selected_linear_POINT_colour_bounds':[sampled.min(axis=0).tolist(),sampled.max(axis=0).tolist()],
        'selected_colour_clipping':False,'all_uv_write_sha256':hashlib.sha256(actual_uv.tobytes()).hexdigest(),
        'original_protected_uv_sha256':hashlib.sha256(data['uv'][~loops].tobytes()).hexdigest(),
        'actual_protected_uv_sha256':hashlib.sha256(actual_uv[~loops].tobytes()).hexdigest(),
        'original_protected_face_material_sha256':hashlib.sha256(data['materials'][~selected].tobytes()).hexdigest(),
        'actual_protected_face_material_sha256':hashlib.sha256(actual_materials[~selected].tobytes()).hexdigest(),
        'all_polygon_material_write_sha256':hashlib.sha256(actual_materials.tobytes()).hexdigest(),
        'new_colour_attribute':{'name':COLOUR,'domain':layer.domain,'type':layer.data_type,'count':len(layer.data),'sha256':hashlib.sha256(actual_colours.tobytes()).hexdigest()},
        'native_normals_preserved':True,'selected_recomputed_tangent_sha256':tangent_hash.hexdigest(),'node_bindings':node_proof,
        'original_colour_settings_preserved':bool(old_colour_count),'all_prior_colour_attributes_preserved':'VERIFIED_BY_SCENE_GUARD','no_save_no_export':True}
    return report

def verify_preservation(before,after,terrain_mesh,soil_mesh,soil_object,change):
    expected_objects=dict(before['objects']);expected_objects.pop(soil_object)
    if after['objects']!=expected_objects or after['other_data']!=before['other_data']:raise ValueError('Non-target native object transform/ID/flags/data settings changed')
    if set(after['meshes'])!=set(before['meshes'])-{soil_mesh}:raise ValueError('Unexpected object-backed mesh inventory change')
    for name,state in before['meshes'].items():
        if name not in [terrain_mesh,soil_mesh] and after['meshes'].get(name)!=state:raise ValueError('Non-target local geometry/UV/material/attribute changed '+name)
    a,b=before['meshes'][terrain_mesh],after['meshes'][terrain_mesh]
    if a['geometry']!=b['geometry'] or a['custom_properties']!=b['custom_properties']:raise ValueError('Terrain XYZ/topology/smoothing/properties changed')
    if b['materials']!=a['materials']+[MATERIAL] or b['polygon_material_sha256']!=change['all_polygon_material_write_sha256']:raise ValueError('Terrain material slot/face mapping differs from declared change')
    if len(a['uv_layers'])!=len(b['uv_layers']) or a['active_uv']!=b['active_uv'] or a['uv_layers'][1:]!=b['uv_layers'][1:]:raise ValueError('Protected UV layer/settings changed')
    auv,buv=dict(a['uv_layers'][0]),dict(b['uv_layers'][0]);auv.pop('sha256');buv.pop('sha256')
    if auv!=buv or b['uv_layers'][0]['sha256']!=change['all_uv_write_sha256']:raise ValueError('Actual target UV write/settings differ')
    uv_name=a['uv_layers'][0]['name']
    allowed_aliases={uv_name}
    # Blender may expose its builtin polygon material array as a generic FACE
    # attribute. Authorize only an exact typed/count/hash alias of that array.
    for alias in ['material_index','.material_index']:
        if alias not in a['attributes'] and alias not in b['attributes']:continue
        for state in [a,b]:
            expected_alias={'type':'INT','domain':'FACE','count':state['geometry']['polygons'],'sha256':state['polygon_material_sha256']}
            if state['attributes'].get(alias)!=expected_alias:raise ValueError('Builtin material attribute is not the exact declared polygon-array alias')
        allowed_aliases.add(alias)
    aa={k:v for k,v in a['attributes'].items() if k not in allowed_aliases}
    bb={k:v for k,v in b['attributes'].items() if k not in allowed_aliases|{COLOUR}}
    if aa!=bb or b['colour_names']!=a['colour_names']+[COLOUR]:raise ValueError('Original terrain attributes/colours changed')
    new_colour=change['new_colour_attribute']
    expected_colour={'type':'FLOAT_COLOR','domain':'POINT','count':new_colour['count'],'sha256':new_colour['sha256']}
    if b['attributes'].get(COLOUR)!=expected_colour or new_colour['count']!=a['geometry']['vertices']:raise ValueError('New POINT colour state differs from verified actual write')
    if a['colour_names'] and (a['colour_active_index'],a['colour_render_index'])!=(b['colour_active_index'],b['colour_render_index']):raise ValueError('Original active/render colour attribute changed')
    if set(after['materials'])!=set(before['materials'])|{MATERIAL} or any(after['materials'][k]!=v for k,v in before['materials'].items()):raise ValueError('An original material changed, including shared LT_Dirt/forest/rock')
    return {'status':'EXACT_SCOPED_PRESERVATION_PASS','all_non_target_object_hashes_unchanged':len(expected_objects),
        'all_non_target_local_mesh_state_hashes_unchanged':len(before['meshes'])-2,'original_materials_unchanged':len(before['materials']),
        'terrain_xyz_topology_smoothing_original_attributes':'PASS','protected_uv_material_loops':'ACTUAL_ARRAY_EQUALITY_PASS',
        'scope':'Same-process local mesh bytes and each object instance separately, no first-representative/world-matrix alias or cross-save UID assumptions'}


def sample_grid(grid,xy,bounds):
    """Top-down host images; worldXY atlas native UV is bottom-up in Blender."""
    import numpy as np
    xy=np.asarray(xy,dtype='float64')
    x0,y0,x1,y1=bounds;h,w=grid.shape[:2]
    if np.any(xy[:,0]<x0-1e-5) or np.any(xy[:,0]>x1+1e-5) or np.any(xy[:,1]<y0-1e-5) or np.any(xy[:,1]>y1+1e-5):
        raise ValueError('Actual terrain sample outside bound original macro field')
    u=(xy[:,0]-x0)/(x1-x0)*w-.5
    v=(y1-xy[:,1])/(y1-y0)*h-.5
    ix=np.floor(u).astype('int64');iy=np.floor(v).astype('int64')
    fx=u-ix;fy=v-iy
    a=grid[np.clip(iy,0,h-1),np.clip(ix,0,w-1)]
    b=grid[np.clip(iy,0,h-1),np.clip(ix+1,0,w-1)]
    c=grid[np.clip(iy+1,0,h-1),np.clip(ix,0,w-1)]
    d=grid[np.clip(iy+1,0,h-1),np.clip(ix+1,0,w-1)]
    while fx.ndim<a.ndim:fx=fx[...,None];fy=fy[...,None]
    return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy

# These source functions are copied verbatim from feather_revision_002.
# The compositor supplies the exact prepared archive; no source-image regrade.
SOURCE_FEATHER_PILOT_SHA256='0b224c854622717a7b301f11aac759a7c17569d0616801733daab93e97324baf'
SOURCE_FEATHER_MATH_SHA256='afb608a472b55ac6609b94068b16e1563dc1785fe811bd4f550b8e29a0b9b04b'
ORIGINAL_PIXELS_RECEIPT_SHA256='dcfff8c98eec0837c1261c81483d70aae460a04e95815dc3f7e9463c67662fe2'
SOURCE_RENDERED_BASELINE_SHA256='baeead4459219ebd9f1030ae38150ff3ed43176c274af756599173c824ffa04d'
WIDTH_M=4.
OLD=Path('SOURCE_FUNCTION_PREPARER_IDENTITY_ONLY')
def boundary_segments(edge_vertices,loop_edges,selected,world):
    edges=np.asarray(edge_vertices,dtype='int32');loop_edges=np.asarray(loop_edges,dtype='int32')
    if edges.ndim!=2 or edges.shape[1]!=2 or len(loop_edges)!=len(selected)*3:raise ValueError('Expected actual triangle edge incidence')
    if not len(edges) or loop_edges.min()<0 or loop_edges.max()>=len(edges):raise ValueError('Invalid actual edge indices')
    selected_loops=np.repeat(np.asarray(selected,dtype=bool),3)
    selected_count=np.bincount(loop_edges[selected_loops],minlength=len(edges))
    protected_count=np.bincount(loop_edges[~selected_loops],minlength=len(edges))
    ids=np.flatnonzero((selected_count>0)&(protected_count>0)).astype('int32')
    if not len(ids):raise ValueError('No measured selected/protected shared boundary edges')
    return world[edges[ids],:2],ids

def segment_distance(points,segments):
    points=np.asarray(points,dtype='float64');segments=np.asarray(segments,dtype='float64')
    start=segments[:,0];delta=segments[:,1]-start
    t=np.sum((points[:,None,:]-start[None,:,:])*delta[None,:,:],axis=2)/np.maximum(np.sum(delta*delta,axis=1),1e-30)[None,:]
    nearest=start[None,:,:]+np.clip(t,0.,1.)[:,:,None]*delta[None,:,:]
    return np.sqrt(np.sum((points[:,None,:]-nearest)**2,axis=2)).min(axis=1)

def bounded_distances(points,segments,width=WIDTH_M):
    """Exact distance to candidate segments within width; interior saturates.

    Expanded segment AABB cells conservatively include every possible point
    within width. Group points once; never scan all vertices for each cell.
    """
    points=np.asarray(points,dtype='float64');segments=np.asarray(segments,dtype='float64')
    if width<=0 or points.ndim!=2 or points.shape[1]!=2 or segments.ndim!=3 or segments.shape[1:]!=(2,2) or not len(segments) or not np.isfinite(points).all() or not np.isfinite(segments).all():raise ValueError('Finite XY points and boundary segments required')
    grid={}
    for i,segment in enumerate(segments):
        lo=np.floor((segment.min(axis=0)-width)/width).astype('int64');hi=np.floor((segment.max(axis=0)+width)/width).astype('int64')
        if np.prod(hi-lo+1)>1024:raise ValueError('Unexpectedly large native edge would explode bounded grid')
        for x in range(int(lo[0]),int(hi[0])+1):
            for y in range(int(lo[1]),int(hi[1])+1):grid.setdefault((x,y),[]).append(i)
    cells=np.floor(points/width).astype('int64')
    unique,inverse,counts=np.unique(cells,axis=0,return_inverse=True,return_counts=True)
    order=np.argsort(inverse,kind='stable');starts=np.cumsum(np.r_[0,counts[:-1]])
    distances=np.full(len(points),width,'float64');evaluated_pairs=0
    for cell,start,count in zip(unique,starts,counts):
        candidates=grid.get(tuple(cell))
        if candidates is None:continue
        selected=order[start:start+count]
        # Bound each temporary point×segment array; large cells stay finite.
        step=max(1,262144//len(candidates))
        for offset in range(0,len(selected),step):
            chunk=selected[offset:offset+step]
            distances[chunk]=np.minimum(width,segment_distance(points[chunk],segments[candidates]))
            evaluated_pairs+=len(chunk)*len(candidates)
    return distances,{'boundary_segments':len(segments),'spatial_cells':len(grid),'selected_point_cells':len(unique),'evaluated_point_segment_pairs':evaluated_pairs,'distance':'EXACT_XY_POINT_TO_SHARED_BOUNDARY_SEGMENT_SATURATED_AT_WIDTH','width_m':width}

def sample_original_linear(rgb8,uv):
    """Old REPEAT/Linear texture at actual UV0, top-down RGB8 pixel source.

    Decode each texel before interpolation. This is not the blurred2K macro
    nor interpolation in gamma-encoded sRGB. No whole8K float copy is made.
    """
    if rgb8.dtype!=np.uint8 or rgb8.ndim!=3 or rgb8.shape[2]!=3:raise ValueError('Exact RGB8 atlas required')
    uv=np.asarray(uv,dtype='float64')
    if uv.ndim!=2 or uv.shape[1]!=2 or not np.isfinite(uv).all():raise ValueError('Finite actual original UV0 required')
    h,w=rgb8.shape[:2];x=uv[:,0]*w-.5;y=(1.-uv[:,1])*h-.5
    ix=np.floor(x).astype('int64');iy=np.floor(y).astype('int64');fx=(x-ix)[:,None];fy=(y-iy)[:,None]
    encoded=np.arange(256,dtype='float64')/255.;lut=np.where(encoded<=.04045,encoded/12.92,((encoded+.055)/1.055)**2.4)
    a=lut[rgb8[iy%h,ix%w]];b=lut[rgb8[iy%h,(ix+1)%w]]
    c=lut[rgb8[(iy+1)%h,ix%w]];d=lut[rgb8[(iy+1)%h,(ix+1)%w]]
    return (a*(1.-fx)+b*fx)*(1.-fy)+(c*(1.-fx)+d*fx)*fy

def blend_colours(current,original_linear,mean_detail,distances,width=WIDTH_M):
    current=np.asarray(current,dtype='float64');original=np.asarray(original_linear,dtype='float64');mean=np.asarray(mean_detail,dtype='float64')
    if current.shape!=original.shape or current.ndim!=2 or current.shape[1]!=3 or mean.shape!=(3,) or np.any(mean<=0):raise ValueError('Registered RGB/current/detail mean required')
    t=np.clip(np.asarray(distances,dtype='float64')/width,0.,1.);w=t*t*(3.-2.*t)
    value=current*w[:,None]+original/mean*(1.-w[:,None])
    if not np.isfinite(value).all() or np.any(value<0.) or np.any(value>1.):raise ValueError('Feathered POINT colour would clip; do not silently clamp')
    value=value.astype('float32')
    return value,{'width_m':width,'curve':'SMOOTHSTEP','boundary_vertices':int(np.sum(t<=1e-12)),'feather_band_vertices':int(np.sum(t<1.)),'interior_vertices':int(np.sum(t>=1.)),'actual_linear_POINT_min':value.min(axis=0).tolist(),'actual_linear_POINT_max':value.max(axis=0).tolist(),'clipping':False,'mean_match_only':'Original boundary expected mean albedo; new micrograin and interpolated coarse-face samples are not a pixel-identical old texture.'}
def actual_feather(terrain,data,selected,centers,record,archive,M,B,output):
    import numpy as np
    mesh=terrain.data;loops=np.repeat(selected,3);selected_loop_ids=np.flatnonzero(loops)
    touched,first=np.unique(data['indices'][loops],return_index=True)
    original_uv=data['uv'][selected_loop_ids[first]]
    lookup=np.full(len(mesh.vertices),-1,'int32');lookup[touched]=np.arange(len(touched))
    if not np.array_equal(original_uv[lookup[data['indices'][loops]]],data['uv'][loops]):raise ValueError('Shared selected native vertex has inconsistent original UV0; POINT cannot reproduce both')
    edge_vertices=np.empty((len(mesh.edges),2),'int32');mesh.edges.foreach_get('vertices',edge_vertices.ravel())
    edge_ids=np.empty(len(mesh.loops),'int32');mesh.loops.foreach_get('edge_index',edge_ids)
    segments,boundary_edge_ids=M.boundary_segments(edge_vertices,edge_ids,selected,data['world'])
    distances,spatial=M.bounded_distances(data['world'][touched,:2],segments)
    macro=np.load(record['outputs']['macro_color_linear.npy']['path'],mmap_mode='r',allow_pickle=False)
    current=B.module(OLD/'prepare.py','feather_frozen_preparer_sampling').sample_grid(macro,data['world'][touched,:2],record['bounds_xy_m'])
    original_pixels=np.load(archive['array']['path'],mmap_mode='r',allow_pickle=False)
    if original_pixels.shape!=(8192,8192,3) or original_pixels.dtype!=np.uint8:raise ValueError('Exact source8K RGB8 archive differs')
    original=M.sample_original_linear(original_pixels,original_uv)
    colours,grade=M.blend_colours(current,original,archive['neutral_detail_mean_linear_rgb'],distances)
    interior=distances>=M.WIDTH_M;boundary=distances<=1e-10
    if not np.array_equal(colours[interior],current.astype('float32')[interior]):raise ValueError('Feather changed the original candidate core colour')
    mean_error=float(np.max(np.abs(colours[boundary]*np.asarray(archive['neutral_detail_mean_linear_rgb'])-original[boundary])))
    if mean_error>2e-7:raise ValueError('Boundary expected mean colour does not match original atlas')
    # All other calls retain the exact frozen field sampler. The existing
    # apply function receives this explicit macro-only adapter via its P API;
    # no frozen module/function is monkey-patched or edited.
    P=B.module(OLD/'prepare.py','feather_frozen_preparer_adapter')
    macro_path=Path(record['outputs']['macro_color_linear.npy']['path']).resolve();calls=[]
    expected_xy=data['world'][touched,:2]
    def sample(grid,xy,bounds):
        if hasattr(grid,'filename') and Path(grid.filename).resolve()==macro_path:
            if bounds!=record['bounds_xy_m'] or not np.array_equal(xy,expected_xy):raise ValueError('Unexpected macro sampling request')
            calls.append('MACRO_ONLY_EXPLICIT_ADAPTER');return colours
        return P.sample_grid(grid,xy,bounds)
    adapter=SimpleNamespace(sample_grid=sample,WOODLAND_MAX=P.WOODLAND_MAX,ROCK_BLEND_MAX=P.ROCK_BLEND_MAX)
    scope=output/'actual_feather_scope.npz'
    np.savez_compressed(scope,selected_native_vertices=touched,boundary_edge_ids=boundary_edge_ids,original_uv0=original_uv.astype('float32'),boundary_distance_xy_m=distances.astype('float32'),new_linear_POINT_rgb=colours)
    return adapter,calls,{'distance':spatial,'grade':grade,'actual_scope_arrays':B.binding(scope),'source8K_sampler':'Exact actual original UV0, pixel-center bilinear REPEAT, texels decoded to linear before interpolation','source_pixels':archive['array'],'neutral_detail_mean_linear_rgb':archive['neutral_detail_mean_linear_rgb'],'original_boundary_expected_mean_rgb_min':original[boundary].min(axis=0).tolist(),'original_boundary_expected_mean_rgb_max':original[boundary].max(axis=0).tolist(),'boundary_expected_mean_max_error':mean_error,'interior_current_candidate_linear_POINT_bytes_unchanged':True,'selection_mask_changed':False,'new_geometry_created':False,'BRDF_parameters_changed':False}

def check_original_pixels(folder,record):
    receipt=Path(folder)/'original_atlas_rgb8_receipt.json'
    if sha(receipt)!=ORIGINAL_PIXELS_RECEIPT_SHA256:raise ValueError('Exact original8K archive receipt required')
    archive=json.loads(receipt.read_text(encoding='utf-8-sig'))
    if archive['schema']!='living_town.original_atlas_rgb8_archive.v1' or archive['source']!=record['original_atlas_diff'] or archive['source_prepared_receipt']['sha256']!=PREPARED_SHA256 or archive['neutral_detail_mean_linear_rgb']!=record['neutral_detail_stats']['actual_quantized_mean_linear_rgb']:raise ValueError('Exact source RGB8 archive/preparer registration differs')
    for row in (archive['tool'],archive['feather_math'],archive['array']):
        if binding(row['path'])!=row:raise ValueError('Original RGB8 archive source changed')
    if archive['feather_math']['sha256']!=SOURCE_FEATHER_MATH_SHA256:raise ValueError('Source feather sampler differs')
    return archive

def feather_adapter(terrain,data,selected,centers,record,archive,output):
    # Verbatim actual_feather uses its explicit B/P API. Supply the copied
    # exact sampler through that API; no module loading or monkey patching.
    sampler=SimpleNamespace(sample_grid=sample_grid,WOODLAND_MAX=WOODLAND_MAX,ROCK_BLEND_MAX=ROCK_BLEND_MAX)
    def registered_module(path,_name):
        if Path(path)!=OLD/'prepare.py':raise ValueError('Unexpected sampler dependency')
        return sampler
    api=SimpleNamespace(module=registered_module,binding=binding)
    math_api=SimpleNamespace(boundary_segments=boundary_segments,bounded_distances=bounded_distances,sample_original_linear=sample_original_linear,blend_colours=blend_colours,WIDTH_M=WIDTH_M)
    return actual_feather(terrain,data,selected,centers,record,archive,math_api,api,output)
