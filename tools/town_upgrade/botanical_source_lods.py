"""Adapt explicit CC0 botanical models into verified shared mesh LOD sources.

This imports only source models obtained by fetch_botanical_sources.py. No
website preview is used as evidence. Actual Blender review renders are saved.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import sys

import bpy
import numpy as np
from mathutils import Matrix,Vector

ASSETS=('tree_small_02','island_tree_02','pine_sapling_medium','fern_02','celandine_01','grass_medium_01')


def tree_lod(ob,asset,index,lod,collection,botany,materials):
    """Retain wood independently; replace tiny leaf geometry with folded cards.

    A global decimator erases narrow trunks and thins every needle. Separate
    budgets preserve each woody material and sample the original canopy volume.
    """
    mesh=ob.data
    if any(len(p.vertices)!=3 for p in mesh.polygons):raise ValueError('glTF source is not triangulated')
    coordinates=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',coordinates);coordinates=coordinates.reshape(-1,3)
    loops=np.empty(len(mesh.loops),dtype=np.int32);mesh.loops.foreach_get('vertex_index',loops);faces=loops.reshape(-1,3)
    uv=np.empty(len(mesh.loops)*2,dtype=np.float32);mesh.uv_layers.active.data.foreach_get('uv',uv);uv=uv.reshape(-1,3,2)
    indices=np.empty(len(mesh.polygons),dtype=np.int32);mesh.polygons.foreach_get('material_index',indices)
    parts=[];leaf_faces=[];prefix=f'BotanicalSource_{asset}_{index}_{lod}'
    for mat_index,material in enumerate(mesh.materials):
        selected=np.nonzero(indices==mat_index)[0]
        if 'leaves' in material.name or 'twig' in material.name:
            leaf_faces.extend(selected.tolist());continue
        selected_faces=faces[selected];unique,inverse=np.unique(selected_faces,return_inverse=True)
        data=bpy.data.meshes.new(prefix+'_'+str(mat_index));data.from_pydata(coordinates[unique].tolist(),[],inverse.reshape(-1,3).tolist());data.materials.append(material)
        layer=data.uv_layers.new(name='BotanicalUV');layer.data.foreach_set('uv',uv[selected].reshape(-1));data.update()
        part=bpy.data.objects.new(data.name,data);collection.objects.link(part);parts.append(part)
        # Bark scan, branch skeleton and deadwood each keep their own budget.
        budget=(5500 if lod=='near' else 1700) if 'branch' in material.name else (5000 if lod=='near' else 1800)
        if len(selected)>budget:
            bpy.ops.object.select_all(action='DESELECT');part.select_set(True);bpy.context.view_layer.objects.active=part
            modifier=part.modifiers.new('Wood material LOD','DECIMATE');modifier.ratio=budget/len(selected);bpy.ops.object.modifier_apply(modifier=modifier.name)
    rng=random.Random(7718+index);conifer=asset=='pine_sapling_medium';count=(2100 if conifer else 6500) if lod=='near' else (800 if conifer else 2400)
    cards=botany.GEOM._Mesh()
    for face_index in rng.sample(leaf_faces,min(count,len(leaf_faces))):
        center=Vector(coordinates[faces[face_index]].mean(axis=0));angle=rng.uniform(0,math.tau)
        if conifer:
            axis=Vector((center.x,center.y,rng.uniform(.1,.7))).normalized()
            normal=Vector((math.cos(angle)*.5,math.sin(angle)*.5,1))
            area_scale=math.sqrt(2100/800) if lod=='far' else 1
            botany.folded_card(cards,center,rng.uniform(.38,.60)*area_scale,rng.uniform(.22,.34)*area_scale,axis,normal,(.005,.55,.25,.995))
        else:
            axis=Vector((math.cos(angle),math.sin(angle),rng.uniform(-.25,1)))
            normal=mesh.polygons[face_index].normal.copy()
            if normal.length<.01:normal=Vector((0,0,1))
            # Preserve projected leaf area while reducing card count. A far
            # mesh must not turn a full summer crown into winter twigs.
            size=rng.uniform(.18,.28)*(math.sqrt(6500/2400) if lod=='far' else 1)
            botany.folded_card(cards,center,size,size*.46,axis,normal,botany.LEAF_CROPS[rng.randrange(5)])
    leaves=cards.object(prefix+'_PhotographedFoliage',collection,[materials['needle'] if conifer else materials['leaf']])
    # Join preserves UV maps by name. Different names silently leave the active
    # bark UV map at (0,0) on every leaf, making opaque black cards at render.
    leaves.data.uv_layers.active.name='BotanicalUV';parts.append(leaves)
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:part.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();result=parts[0];result.name=prefix
    return result


def fix_imported_materials(objects,sources,asset):
    for material in {m for ob in objects for m in ob.data.materials if m}:
        material['source_license']='CC0-1.0';material['source_asset_url']='https://polyhaven.com/a/'+asset
        for node in material.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image and node.image.source=='FILE':
                path=Path(bpy.path.abspath(node.image.filepath));rgba=path.with_name(path.stem+'_rgba.png')
                if rgba.is_file():
                    node.image=bpy.data.images.load(str(rgba),check_existing=True)
                    # Exports portable glTF MASK from a true alpha threshold.
                    shader=material.node_tree.nodes.get('Principled BSDF')
                    threshold=material.node_tree.nodes.new('ShaderNodeMath');threshold.operation='GREATER_THAN';threshold.inputs[1].default_value=.42
                    material.node_tree.links.new(node.outputs['Alpha'],threshold.inputs[0]);material.node_tree.links.new(threshold.outputs[0],shader.inputs['Alpha'])
                    material.surface_render_method='DITHERED';material.use_backface_culling=False
                    material['alpha_cutoff']=.42;material['alpha_mode']='MASK'


def adapt(sources,output):
    bpy.ops.wm.read_homefile(use_empty=True,use_factory_startup=True);bpy.context.preferences.filepaths.save_version=0
    collection=bpy.data.collections.new('CC0_Botanical_LOD_Library');bpy.context.scene.collection.children.link(collection)
    import importlib.util
    spec=importlib.util.spec_from_file_location('botanical_card_geometry',Path(__file__).with_name('botany.py'));botany=importlib.util.module_from_spec(spec);spec.loader.exec_module(botany)
    botanical_materials=botany.materials(sources)
    entries=[]
    for asset in ASSETS:
        print('BOTANICAL_SOURCE_IMPORT '+asset,flush=True)
        before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(sources/asset/(asset+'_2k.gltf')))
        imported=sorted(set(bpy.data.objects)-before,key=lambda ob:ob.name);objects=[o for o in imported if o.type=='MESH'];helpers=[o for o in imported if o.type!='MESH']
        fix_imported_materials(objects,sources,asset)
        for index,ob in enumerate(objects):
            ob.data.transform(ob.matrix_world);ob.matrix_world=Matrix.Identity(4)
            points=[v.co for v in ob.data.vertices];low=min(p.z for p in points);high=max(p.z for p in points)
            is_tree=asset in ASSETS[:3];target_height=7.8 if asset=='tree_small_02' else 5.4 if asset=='island_tree_02' else 9.6 if is_tree else high-low
            roots=[p for p in points if p.z<low+(high-low)*.025];center=sum(roots,Vector())/len(roots)
            scale=target_height/(high-low)
            for v in ob.data.vertices:v.co=(v.co-Vector((center.x,center.y,low)))*scale
            original_triangles=sum(len(p.vertices)-2 for p in ob.data.polygons)
            for lod,budget in [('near',42000),('far',11000)] if is_tree else [('near',2200)]:
                if is_tree:
                    copy=tree_lod(ob,asset,index,lod,collection,botany,botanical_materials)
                else:
                    copy=bpy.data.objects.new(f'BotanicalSource_{asset}_{index}_{lod}',ob.data.copy());collection.objects.link(copy)
                bpy.ops.object.select_all(action='DESELECT');copy.select_set(True);bpy.context.view_layer.objects.active=copy
                if not is_tree and original_triangles>budget:
                    modifier=copy.modifiers.new('Bounded engine LOD','DECIMATE');modifier.ratio=budget/original_triangles
                    bpy.ops.object.modifier_apply(modifier=modifier.name)
                # Explicit persistent triangles preserve tangents/UVs on export.
                import bmesh
                bm=bmesh.new();bm.from_mesh(copy.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(copy.data);bm.free()
                copy['source_asset']=asset;copy['source_variant']=index;copy['lod']=lod;copy['source_license']='CC0-1.0'
                copy['vegetation_role']='tree' if is_tree else 'understory';copy['botanical_prototype']=True
                entries.append({'name':copy.name,'mesh':copy.data.name,'asset':asset,'variant':index,'lod':lod,
                    'height_m':target_height,'triangles':len(copy.data.polygons),'source_triangles':original_triangles,
                    'materials':[m.name for m in copy.data.materials],'vertices':len(copy.data.vertices)})
            data=ob.data;bpy.data.objects.remove(ob,do_unlink=True)
            if data.users==0:bpy.data.meshes.remove(data)
        for ob in helpers:
            bpy.data.objects.remove(ob,do_unlink=True)
    for image in bpy.data.images:
        if image.source=='FILE' and not image.packed_file:image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'botanical_prototypes.blend'),compress=True)
    native=output/'botanical_prototypes.blend'
    report={'schema':'living_town.cc0_botanical_lods.v1','source_receipts_sha256':hashlib.sha256((sources/'source_receipts.json').read_bytes()).hexdigest(),
        'native_sha256':hashlib.sha256(native.read_bytes()).hexdigest(),'entries':entries,'credit':'Powered by Poly Haven',
        'quality_status':'REQUIRES_LOOKDEV_REVIEW','license':'CC0-1.0','policy':'Source meshes adapted to metric planting sizes, true packed alpha, explicit near/far triangle budgets; retained source geometry is not replaced by solid crown shells.'}
    (output/'botanical_prototypes.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return entries


def review(output,entries):
    # Arrange real prototype geometry; far LODs are separately reviewed later.
    roots=[]
    for ob in list(bpy.context.scene.objects):
        ob.hide_render=True
    picks=[next(e for e in entries if e['asset']==asset and e['lod']=='near') for asset in ASSETS]
    for i,entry in enumerate(picks):
        ob=bpy.data.objects[entry['name']];ob.hide_render=False
        if i<3:ob.location=((i-1)*8,1,0)
        else:ob.location=((i-4)*1.5,-5,0)
    bpy.ops.mesh.primitive_plane_add(size=200);ground=bpy.context.object
    material=bpy.data.materials.new('Warm meadow review ground');material.use_nodes=True;material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.24,.28,.15,1);ground.data.materials.append(material)
    scene=bpy.context.scene;scene.world=bpy.data.worlds.new('Summer review daylight');scene.world.use_nodes=True
    background=scene.world.node_tree.nodes.get('Background');background.inputs['Color'].default_value=(.6,.75,1,1);background.inputs['Strength'].default_value=.65
    bpy.ops.object.light_add(type='SUN',location=(0,0,15));sun=bpy.context.object;sun.rotation_euler=(.4,-.6,-.45);sun.data.energy=2.6;sun.data.angle=.12
    bpy.ops.object.camera_add(location=(17,-32,16));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,4))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=27;scene.camera=camera
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=6
    scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(output/'botanical_source_review.png');bpy.ops.render.render(write_still=True)
    for entry in picks[:3]:bpy.data.objects[entry['name']].hide_render=True
    far=[next(e for e in entries if e['asset']==asset and e['lod']=='far') for asset in ASSETS[:3]]
    for i,entry in enumerate(far):
        ob=bpy.data.objects[entry['name']];ob.hide_render=False;ob.location=((i-1)*8,1,0)
    scene.render.filepath=str(output/'botanical_far_review.png');bpy.ops.render.render(write_still=True)
    # Keep a separate review scene; the library remains at rest at the origin.
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'botanical_source_review.blend'),compress=True)
    print('BOTANICAL_SOURCES_READY '+str(len(entries)),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True);entries=adapt(a.sources,a.output);review(a.output,entries)
