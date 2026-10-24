"""Bind a CC0 scan bake and metric detail maps to the actual authored terrain."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess

import numpy as np


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def apply(api,sources,output,botanical,texture_python,size=8192,atlas_cache=None):
    bpy=api['bpy'];surfaces=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.name=='Atlantic_Terrain_Grass' or o.get('reserve_role')=='terrain')]
    if not surfaces:raise RuntimeError('No actual authored terrain for ground finish')
    minimum=np.array([np.inf,np.inf]);maximum=-minimum;samples=[];original=[]
    def geometry_hash(ob):
        mesh=ob.data
        coords=np.empty(len(mesh.vertices)*3,np.float32);mesh.vertices.foreach_get('co',coords)
        loops=np.empty(len(mesh.loops),np.int32);mesh.loops.foreach_get('vertex_index',loops)
        starts=np.empty(len(mesh.polygons),np.int32);mesh.polygons.foreach_get('loop_start',starts)
        totals=np.empty(len(mesh.polygons),np.int32);mesh.polygons.foreach_get('loop_total',totals)
        return hashlib.sha256(coords.tobytes()+loops.tobytes()+starts.tobytes()+totals.tobytes()+np.asarray(ob.matrix_world,dtype=np.float64).tobytes()).hexdigest()
    for ob in surfaces:
        coords=np.empty((len(ob.data.vertices),3),np.float32);ob.data.vertices.foreach_get('co',coords.ravel())
        matrix=np.asarray(ob.matrix_world);world=coords@matrix[:3,:3].T+matrix[:3,3]
        minimum=np.minimum(minimum,world[:,:2].min(axis=0));maximum=np.maximum(maximum,world[:,:2].max(axis=0))
        centers=np.empty((len(ob.data.polygons),3),np.float32);normals=np.empty_like(centers)
        ob.data.polygons.foreach_get('center',centers.ravel());ob.data.polygons.foreach_get('normal',normals.ravel())
        centers=centers@matrix[:3,:3].T+matrix[:3,3]
        normals=normals@np.linalg.inv(matrix[:3,:3]);normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],.0001)
        # A 768px slope guide needs one representative per half-metre cell;
        # retain the steepest actual face in that cell, without mesh changes.
        selected={}
        for index in range(len(centers)):
            point=centers[index];key=int(np.floor(point[0]*2)),int(np.floor(point[1]*2))
            slope=1-abs(float(normals[index,2]))
            if slope>.15 and (key not in selected or slope>selected[key][2]):selected[key]=[float(point[0]),float(point[1]),slope]
        samples.extend(selected.values())
        original.append({'name':ob.name,'geometry_sha256':geometry_hash(ob),'vertices':len(coords),'polygons':len(centers)})
    folder=output/'terrain_materials';folder.mkdir()
    guide={'bounds_xy_m':[*minimum.tolist(),*maximum.tolist()],'slope_samples':samples,'trees':botanical['placements'],
           'scan_adaptation':{'anti_tile':True,'linear_rgb_factors':{'leafy_grass':[.58,1.08,.52]},
                              'art_direction':'Artist-authored temperate summer lawn palette; source photographs retained unchanged. Three rotated/offset lawn samples reduce grid repetition; tangent XY vectors rotate with their samples.'}}
    guide_path=folder/'terrain_bake_guide.json';guide_path.write_text(json.dumps(guide)+'\n',encoding='utf-8')
    cached=None
    if atlas_cache:
        reuse=api['module']('whole_town_exact_terrain_cache',Path(__file__).with_name('terrain_cache.py')).reuse
        cached=reuse(atlas_cache,guide_path,sources,folder,Path(__file__).with_name('terrain_atlas.py'),size)
        print('TERRAIN_PORTABLE_ATLAS_EXACT_CACHE_REUSED '+str(size),flush=True)
    else:
        print('TERRAIN_PORTABLE_ATLAS_BAKE '+str(size),flush=True)
        subprocess.run([str(texture_python),str(Path(__file__).with_name('terrain_atlas.py')),'--guide',str(guide_path),'--sources',str(sources),'--output',str(folder),'--size',str(size)],check=True)
    receipt=json.loads((folder/'terrain_atlas_receipt.json').read_text(encoding='utf-8'))
    mat=bpy.data.materials.new('Refined_Terrain_PortableAtlas');mat.use_nodes=True
    nodes,links=mat.node_tree.nodes,mat.node_tree.links;shader=nodes.get('Principled BSDF')
    images={}
    for role,row in receipt['maps'].items():
        node=nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(folder/row['path']),check_existing=True);node.extension='REPEAT';images[role]=node
        if role!='diff':node.image.colorspace_settings.name='Non-Color'
    # No explicit UVMap node: every channel uses the same active UV0. Godot
    # 4.6 ignores per-texture glTF texCoord selectors, so UV1 is insufficient.
    links.new(images['diff'].outputs['Color'],shader.inputs['Base Color'])
    normal_map=nodes.new('ShaderNodeNormalMap');normal_map.inputs['Strength'].default_value=.65
    links.new(images['nor_gl'].outputs['Color'],normal_map.inputs['Color']);links.new(normal_map.outputs['Normal'],shader.inputs['Normal'])
    split=nodes.new('ShaderNodeSeparateColor');links.new(images['arm'].outputs['Color'],split.inputs[0]);links.new(split.outputs['Green'],shader.inputs['Roughness']);links.new(split.outputs['Blue'],shader.inputs['Metallic'])
    shader.inputs['Specular IOR Level'].default_value=.28;mat['source_license']='CC0-1.0';mat['source_assets']=list(receipt['source_repeat_metres']);mat['world_atlas_sha256']=receipt['maps']['diff']['sha256']
    changed={};x0,y0,x1,y1=guide['bounds_xy_m']
    for ob,before in zip(surfaces,original):
        mesh=ob.data
        world_uv=mesh.uv_layers[0] if mesh.uv_layers else mesh.uv_layers.new(name='MetricUV')
        mesh.uv_layers.active_index=0;world_uv.active_render=True
        slot=len(mesh.materials);mesh.materials.append(mat);changed[ob.name]=0
        coords=[ob.matrix_world@vertex.co for vertex in mesh.vertices]
        old_uv=np.empty((len(mesh.loops),2),np.float32);world_uv.data.foreach_get('uv',old_uv.ravel())
        old_materials=np.empty(len(mesh.polygons),np.int32);mesh.polygons.foreach_get('material_index',old_materials)
        protected_loops=[];protected_faces=[]
        for face in mesh.polygons:
            old=mesh.materials[face.material_index]
            if old is None or old.name not in ('LT_Grass','Grass','Expansion_Grass'):
                protected_faces.append(face.index);protected_loops.extend(face.loop_indices);continue
            for index in face.loop_indices:
                v=coords[mesh.loops[index].vertex_index]
                world_uv.data[index].uv=((v.x-x0)/(x1-x0),(v.y-y0)/(y1-y0))
            face.material_index=slot;changed[ob.name]+=1
        mesh.update();ob['ground_finish']='living_town.scanned_terrain.v1'
        if geometry_hash(ob)!=before['geometry_sha256']:raise RuntimeError('Ground finish changed native terrain geometry: '+ob.name)
        after_uv=np.empty_like(old_uv);world_uv.data.foreach_get('uv',after_uv.ravel())
        after_materials=np.empty_like(old_materials);mesh.polygons.foreach_get('material_index',after_materials)
        if not np.array_equal(old_uv[protected_loops],after_uv[protected_loops]) or not np.array_equal(old_materials[protected_faces],after_materials[protected_faces]):raise RuntimeError('Ground finish changed protected rock UVs/materials: '+ob.name)
        before['protected_rock_and_other_loops']=len(protected_loops);before['protected_uv_materials']='PASS'
    if sum(changed.values())==0:raise RuntimeError('No exact terrain grass material slots matched')
    report={'schema':'living_town.scanned_terrain.v1','status':'BUILT_REQUIRES_VISUAL_REVIEW','atlas':receipt,'terrain_geometry_before':original,
            'changed_faces':dict(changed),'source_receipts_sha256':sha(sources/'source_receipts.json'),'tool_sha256':sha(__file__),'exact_atlas_cache':cached,
            'topology_policy':'Actual connected terrain vertices and faces preserved; no floating ground patches or flat replacement plane.',
            'geometry_preservation':'PASS: exact coordinates, loop indices, polygon boundaries and world matrices SHA256 match before and after.',
            'export_policy':'All glTF channels share the actual first UV layer (UV0), with REPEAT wrapping; existing rock/non-grass UV loops stay untouched. Portable through Godot4.6 without custom material adaptation.'}
    (output/'terrain_finish_receipt.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report
