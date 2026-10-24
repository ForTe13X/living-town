"""Original branching vegetation with CC0 leaf/bark maps and shared mesh LODs.

No closed canopy shells. Every crown is open branches and individually folded,
alpha-tested leaves or photographed needle sprays. Botanical labels describe
the planting program; they do not claim survey-grade species identification.
Run lookdev in a fresh Blender scene before applying to the preserved town.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import importlib.util
import json
import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
TAU = math.tau
LEAF_CROPS = ((.012,.48,.165,.99),(.16,.57,.35,.99),(.34,.65,.48,.99),(.48,.58,.67,.98),(.68,.55,.81,.99))


def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec)
    sys.modules[name]=value;spec.loader.exec_module(value);return value


GEOM = module('town_botanical_geometry', ROOT/'tools/asset_refinement/hero_foliage.py')


def texture_material(name, color, normal, arm, *, tint=(1,1,1), leaves=False):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    mat.diffuse_color=(*((.25,.38,.16) if leaves else (.24,.19,.12)),1)
    ns,ls=mat.node_tree.nodes,mat.node_tree.links;shader=ns.get('Principled BSDF')
    tex=ns.new('ShaderNodeTexImage');tex.name='CC0 photographed basecolor';tex.image=bpy.data.images.load(str(color),check_existing=True)
    multiply=ns.new('ShaderNodeMixRGB');multiply.name='Botanical Tint';multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
    multiply.inputs[2].default_value=(*tint,1);ls.new(tex.outputs['Color'],multiply.inputs[1]);ls.new(multiply.outputs[0],shader.inputs['Base Color'])
    nor=ns.new('ShaderNodeTexImage');nor.name='CC0 tangent normal';nor.image=bpy.data.images.load(str(normal),check_existing=True);nor.image.colorspace_settings.name='Non-Color'
    mapping=ns.new('ShaderNodeNormalMap');mapping.inputs['Strength'].default_value=.42 if leaves else .72
    ls.new(nor.outputs['Color'],mapping.inputs['Color']);ls.new(mapping.outputs['Normal'],shader.inputs['Normal'])
    rough=ns.new('ShaderNodeTexImage');rough.name='CC0 ARM';rough.image=bpy.data.images.load(str(arm),check_existing=True);rough.image.colorspace_settings.name='Non-Color'
    channels=ns.new('ShaderNodeSeparateColor');ls.new(rough.outputs['Color'],channels.inputs[0]);ls.new(channels.outputs['Green'],shader.inputs['Roughness'])
    shader.inputs['Specular IOR Level'].default_value=.28
    if leaves:
        # Threshold node exports as glTF MASK, avoiding sorted alpha blending.
        cut=ns.new('ShaderNodeMath');cut.operation='GREATER_THAN';cut.inputs[1].default_value=.45
        ls.new(tex.outputs['Alpha'],cut.inputs[0]);ls.new(cut.outputs[0],shader.inputs['Alpha'])
        shader.inputs['Subsurface Weight'].default_value=.035
        mat.surface_render_method='DITHERED';mat.use_backface_culling=False
        mat['alpha_mode']='MASK';mat['alpha_cutoff']=.45;mat['botanical_material']='photographed_cutout_leaf'
    mat['source_license']='CC0-1.0';mat['source_library']='Poly Haven';return mat


def materials(sources):
    broad=sources/'island_tree_02'/'textures';pine=sources/'pine_tree_01'
    leaf=texture_material('Botanical_Broadleaf',broad/'leaves_rgba.png',broad/'island_tree_02_leaves_nor_gl_2k.jpg',broad/'island_tree_02_leaves_arm_2k.jpg',tint=(.83,1,.82),leaves=True)
    silver=leaf.copy();silver.name='Botanical_Silverleaf';silver.node_tree.nodes.get('Botanical Tint').inputs[2].default_value=(.91,1,.92,1)
    needle=texture_material('Botanical_Pine_Needles',pine/'twig_rgba.png',pine/'twig_nor_gl.jpg',pine/'twig_arm.jpg',tint=(.76,.94,.82),leaves=True)
    bark=texture_material('Botanical_Fissured_Bark',pine/'bark_diff.jpg',pine/'bark_nor_gl.jpg',pine/'bark_arm.jpg',tint=(.84,.88,.88))
    birch=bark.copy();birch.name='Botanical_Birch_Bark';birch.node_tree.nodes.get('Botanical Tint').inputs[2].default_value=(1.6,1.7,1.6,1)
    return {'leaf':leaf,'silver':silver,'needle':needle,'bark':bark,'birch':birch}


def folded_card(mesh, center, length, width, axis, normal, crop, material=0):
    axis=Vector(axis).normalized();normal=Vector(normal).normalized();right=axis.cross(normal).normalized()
    if right.length < .1:right=Vector((1,0,0))
    normal=right.cross(axis).normalized();center=Vector(center)
    u0,v0,u1,v1=crop;um=(u0+u1)/2
    points=[center-axis*length/2-right*width/2,center-axis*length/2+normal*length*.025,
            center-axis*length/2+right*width/2,center+axis*length/2-right*width/2,
            center+axis*length/2+normal*length*.07,center+axis*length/2+right*width/2]
    mesh.poly(points,[(0,1,4,3),(1,2,5,4)],material,[(u0,v0),(um,v0),(u1,v0),(u0,v1),(um,v1),(u1,v1)])


def tree_prototype(collection, mats, species, seed=0, lod='near'):
    rng=random.Random(91073+seed*103);wood=GEOM._Mesh();leaf=GEOM._Mesh()
    conifer=species in ('pine','maritime_pine','scots_pine');willow=species=='willow';birch=species in ('birch','silver_birch')
    h=10.0 if conifer else 8.4 if birch else 7.6;radius=2.6 if not willow else 3.25
    main=[];drift=rng.uniform(0,TAU)
    for j in range(9):
        t=j/8;main.append(Vector((math.sin(t*2)*.23*math.cos(drift),math.sin(t*2)*.23*math.sin(drift),h*t)))
        if j:wood.rod(main[j-1],main[j],.26*(1-(t-.125)*.9),max(.018,.26*(1-t*.94)),sides=9 if lod=='near' else 6)
    for k in range(7):
        az=k*TAU/7;wood.rod((.60*math.cos(az),.60*math.sin(az),-.05),(.11*math.cos(az),.11*math.sin(az),.50),.12,.10,sides=6)
    branches=26 if conifer else 17
    twig_count=5 if lod=='near' else 3
    cards_per_twig=32 if lod=='near' else 15
    for i in range(branches):
        az=i*2.399963+rng.uniform(-.26,.26);t=.30+i/(branches-1)*.63
        reach=radius*(math.sin((t-.15)/.85*math.pi)*.7+.25)*rng.uniform(.85,1.2)
        if conifer:reach=radius*(1-t)*1.7+rng.uniform(.05,.30)
        base=main[min(7,int(t*7))];end=Vector((math.cos(az)*reach,math.sin(az)*reach,h*(t+.10)))
        if willow:end.z=h*(t-.05)
        elbow=base.lerp(end,.53)+Vector((0,0,.18))
        wood.rod(base,elbow,.075*(1-t*.55),.035,sides=7);wood.rod(elbow,end,.035,.009,sides=6)
        for j in range(twig_count):
            a=az+(j%2*2-1)*rng.uniform(.25,1.15)
            start=elbow.lerp(end,(j+1)/(twig_count+1))
            tip=start+Vector((math.cos(a)*rng.uniform(.35,.85),math.sin(a)*rng.uniform(.35,.85),rng.uniform(-.22,.60)))
            if willow:tip.z-=.65
            wood.rod(start,tip,.013,.0035,sides=5)
            count=cards_per_twig if not conifer else max(10,cards_per_twig//2)
            for k in range(count):
                s=(k+.4)/count;angle=k*2.399963+a
                spread=rng.uniform(.07,.40 if not conifer else .28)
                center=start.lerp(tip,s)+Vector((math.cos(angle)*spread,math.sin(angle)*spread,rng.uniform(-.15,.20)))
                direction=Vector((math.cos(angle),math.sin(angle),rng.uniform(.15,1.0)))
                if willow:direction.z=-rng.uniform(.3,.8)
                normal=Vector((math.cos(angle)*.4,math.sin(angle)*.4,rng.uniform(.3,1)))
                if conifer:
                    folded_card(leaf,center,rng.uniform(.38,.64),rng.uniform(.19,.32),direction,normal,(.005,.55,.25,.995))
                else:
                    size=rng.uniform(.23,.37)*(1.14 if lod=='far' else 1)
                    folded_card(leaf,center,size,size*.43,direction,normal,LEAF_CROPS[rng.randrange(len(LEAF_CROPS))])
    prefix=f'Botanical_{species}_{seed}_{lod}'
    bark_ob=wood.object(prefix+'_Bark',collection,[mats['birch'] if birch else mats['bark']])
    leaf_ob=leaf.object(prefix+'_Leaves',collection,[mats['needle'] if conifer else mats['silver'] if willow or birch else mats['leaf']])
    for ob in (bark_ob,leaf_ob):
        for p in ob.data.polygons:p.use_smooth=ob==bark_ob
        ob['prototype_species']=species;ob['lod']=lod;ob['height_m']=h
    return [bark_ob,leaf_ob]


def fern_prototype(collection,mats,seed=0):
    rng=random.Random(112+seed);mesh=GEOM._Mesh()
    for i in range(10):
        az=i*TAU/10;start=Vector((0,0,.05));tip=Vector((math.cos(az)*.70,math.sin(az)*.70,.27+rng.random()*.4))
        mesh.rod(start,tip,.008,.0015,sides=4)
        for j in range(1,11):
            t=j/12;middle=start.lerp(tip,t)+Vector((0,0,math.sin(t*math.pi)*.23))
            for side in (-1,1):
                axis=Vector((math.cos(az+side*1.12),math.sin(az+side*1.12),.2))
                size=.23*(1-t)+.045;folded_card(mesh,middle+axis*size*.35,size,size*.3,axis,(0,0,1),LEAF_CROPS[(i+j)%5])
    return [mesh.object('Botanical_Fern_'+str(seed),collection,[mats['leaf']])]


def meadow_prototype(collection,mats,seed=0):
    rng=random.Random(606+seed);mesh=GEOM._Mesh()
    for i in range(70):
        x,y=rng.uniform(-.5,.5),rng.uniform(-.5,.5);az=rng.uniform(0,TAU);h=rng.uniform(.13,.45)
        w=rng.uniform(.007,.016);dx,dy=math.cos(az)*w,math.sin(az)*w
        mesh.poly([(x-dx,y-dy,0),(x+dx,y+dy,0),(x+math.cos(az)*.1,y+math.sin(az)*.1,h)],[(0,1,2)])
    return [mesh.object('Botanical_Meadow_'+str(seed),collection,[mats['leaf']])]


def cached_prototypes(collection,mats):
    cache={}
    for species in ('oak','beech','birch','pine','rowan','holly','willow','alder','maritime_pine'):
        for seed in range(2):
            for lod in ('near','far'):
                obs=tree_prototype(collection,mats,species,seed,lod);cache[species,seed,lod]=[ob.data for ob in obs]
                for ob in obs:bpy.data.objects.remove(ob,do_unlink=True)
    for kind,factory in (('fern',fern_prototype),('meadow',meadow_prototype)):
        for seed in range(2):
            obs=factory(collection,mats,seed);cache[kind,seed,'near']=[ob.data for ob in obs]
            for ob in obs:bpy.data.objects.remove(ob,do_unlink=True)
    return cache


def ground_surface():
    surfaces=[]
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH' and (ob.name=='Atlantic_Terrain_Grass' or ob.get('reserve_role')=='terrain'):
            surfaces.append(BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],[list(p.vertices) for p in ob.data.polygons],all_triangles=False))
    def ground(x,y,fallback):
        hits=[h[0].z for surface in surfaces if (h:=surface.ray_cast(Vector((x,y,1000)),Vector((0,0,-1)),2000))[0] is not None]
        return max(hits) if hits else fallback
    return ground


def old_trees():
    print('BOTANICAL_STAGE inspect_original_roots',flush=True)
    groups=defaultdict(list);remove=[];extra=[]
    for ob in list(bpy.context.scene.objects):
        if ob.get('reserve_role')=='tree':key=tuple(ob.location),ob.get('tree_species','oak')
        elif ob.get('prototype') in ('hero_tree','rowan','lime','birch'):
            key=tuple(ob.location),ob.get('prototype')
        else:continue
        groups[key].append(ob);remove.append(ob)
    records=[]
    for (position,species),obs in groups.items():
        zmax=max((ob.matrix_world@Vector(p)).z for ob in obs for p in ob.bound_box)
        rr=max(math.hypot((ob.matrix_world@Vector(p)).x-position[0],(ob.matrix_world@Vector(p)).y-position[1]) for ob in obs for p in ob.bound_box)
        records.append({'position':position,'species':species,'height':zmax-position[2],'radius':rr,'yaw':obs[0].rotation_euler.z,'near':obs[0].get('lod')=='near' or not obs[0].name.startswith('Reserve_')})
    # Reference street/pond trees use a separate, source-bound clear-stem
    # factory. Its accepted ledger is embedded in the exact loaded native.
    evidence=json.loads(bpy.context.scene.get('reference_landscape','{}'))
    reference_trees=[r for r in evidence.get('accepted',[]) if r.get('role') in ('street_tree','willow')]
    for role,prefix,strides in (
        ('street_tree','Reference_Street_Trees',{'Trunk':116,'Leaf':520,'LeafDark':40,'LeafLight':240}),
        ('willow','Reference_Pond_Planting',{'Trunk':188,'Leaf':1120,'LeafDark':40,'LeafSilver':360})):
        planted=[r for r in reference_trees if r['role']==role]
        if not planted:continue
        trunk=bpy.data.objects.get(prefix+'_Trunk')
        if trunk is None:raise RuntimeError('Missing accepted reference-tree trunk batch: '+prefix)
        for i,record in enumerate(planted):
            points=[trunk.matrix_world@trunk.data.vertices[i*strides['Trunk']+j].co for j in range(7)]
            root=sum(points,Vector())/7
            if math.dist(tuple(root),(*record['xy'],record['root_z_m']))>.0001:
                raise RuntimeError('Reference tree root/factory binding changed: '+record['id'])
            records.append({'position':tuple(root),'species':'willow' if role=='willow' else 'lime','height':record['height_m'],
                'radius':record['crown_radius_m'],'yaw':i*2.399963,'near':True,'source_form':'clear_stem','original_tree_id':record['id']})
        for material,stride in strides.items():
            ob=bpy.data.objects.get(prefix+'_'+material)
            if ob is None or len(ob.data.vertices)<len(planted)*stride:raise RuntimeError('Reference botanical source prefix changed: '+prefix+'/'+material)
            if role=='street_tree':
                if len(ob.data.vertices)!=len(planted)*stride:raise RuntimeError('Street-tree batch contains unexpected non-tree vertices')
                remove.append(ob)
            else:
                # The pond batch appends reed stems/leaves after its willow
                # prefix. Preserve every reed vertex and its existing UVs.
                import bmesh
                bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table()
                bmesh.ops.delete(bm,geom=[bm.verts[i] for i in range(len(planted)*stride)],context='VERTS');bm.to_mesh(ob.data);bm.free();extra.append(ob.name)
    # Original factory appends exact tree vertex prefixes before other garden
    # fixtures. Delete only those prefixes; preserve planters/edging after them.
    for prefix in ('Layered_Street_and_Orchard_Planting','Garden_Vegetation','Sheltered_Gardens_and_Canopies'):
        trunk=bpy.data.objects.get(prefix+'_Trunk')
        if trunk is None:continue
        count=len(trunk.data.vertices)//326
        if not count:continue
        for i in range(count):
            points=[trunk.matrix_world@trunk.data.vertices[i*326+j].co for j in range(9)]
            root=sum(points,Vector())/9
            # Height from this exact tree's trunk vertices, not the later bed.
            high=max((trunk.matrix_world@trunk.data.vertices[j].co).z for j in range(i*326,(i+1)*326))
            records.append({'position':tuple(root),'species':'oak','height':(high-root.z)/.85,'radius':2.5,'yaw':i*2.399963,'near':True})
        for role,stride in {'Trunk':326,'Leaf':1225,'LeafLight':490,'LeafDark':490}.items():
            ob=bpy.data.objects.get(prefix+'_'+role)
            if ob is None or len(ob.data.vertices)<count*stride:raise RuntimeError('Original tree prefix binding failed: '+prefix+'/'+role)
            import bmesh
            bm=bmesh.new();bm.from_mesh(ob.data);bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm,geom=[bm.verts[i] for i in range(count*stride)],context='VERTS');bm.to_mesh(ob.data);bm.free();extra.append(ob.name)
    names=[o.name for o in remove]
    print('BOTANICAL_STAGE remove_original_tree_nodes '+str(len(remove)),flush=True)
    # Only the explicitly inventoried object IDs are removed. Mesh data,
    # materials, scenes and all other descendants remain untouched.
    if remove:bpy.data.batch_remove(ids=remove)
    return records,names,extra


def apply(api,sources,output,library):
    print('BOTANICAL_STAGE load_shared_source_library',flush=True)
    col=api['collection']('Refined_Botanical_Landscape')
    source_manifest=json.loads(library.with_suffix('.json').read_text(encoding='utf-8'))
    with bpy.data.libraries.load(str(library),link=False) as (available,loaded):
        loaded.meshes=[entry['mesh'] for entry in source_manifest['entries']]
    cache={};entries={};radii={}
    for entry,mesh in zip(source_manifest['entries'],loaded.meshes):
        key=entry['asset'],entry['variant'],entry['lod'];cache[key]=[mesh];entries[key]=entry
        radii[key]=max(math.hypot(v.co.x,v.co.y) for v in mesh.vertices)
    trees,removed,modified=old_trees();print('BOTANICAL_STAGE build_actual_terrain_bvh',flush=True);ground=ground_surface();placements=[]
    mapping={'hero_tree':'oak','lime':'beech','sessile_oak':'oak','silver_birch':'birch','scots_pine':'pine'}
    for index,record in enumerate(trees):
        if index%500==0:print('BOTANICAL_STAGE plant_trees '+str(index)+'/'+str(len(trees)),flush=True)
        species=mapping.get(record['species'],record['species']);species=species if species in ('oak','beech','birch','pine','rowan','holly','willow','alder','maritime_pine') else 'oak'
        x,y,z=record['position'];z=ground(x,y,z)
        # Near LOD is concentrated in inhabited streets and at reserve public
        # facilities; far woodland retains real branching and alpha foliage.
        nearby_public=any(math.hypot(x-b['center_m'][0],y-b['center_m'][1])<32 for b in api.get('buildings',[]))
        lod='near' if nearby_public or (record['near'] and x>-150 and y<135) else 'far'
        asset='tree_small_02' if record.get('source_form')=='clear_stem' else 'pine_sapling_medium' if species in ('pine','maritime_pine') else 'island_tree_02' if species in ('holly','willow','alder') or index%5==0 else 'tree_small_02'
        variant=index%3 if asset=='pine_sapling_medium' else 0
        key=asset,variant,lod;reference=entries[key]['height_m']
        scale=max(.40,min(1.9,record['height']/reference));horizontal=min(scale,max(.30,record['radius']/radii[key]*.95))
        ident=f'Botanical_Tree_{index:05d}'
        for j,mesh in enumerate(cache[key]):
            ob=bpy.data.objects.new(ident+'_'+str(j),mesh);col.objects.link(ob);ob.location=(x,y,z);ob.rotation_euler.z=record['yaw'];ob.scale=(horizontal,horizontal,scale)
            ob['botanical_instance_id']=ident;ob['tree_species']=record['species'];ob['vegetation_role']='tree';ob['lod']=lod;ob['stable_id']='botanical/'+ob.name
            ob['source_asset']=asset;ob['planting_program_species']=record['species'];ob['source_license']='CC0-1.0'
        placements.append({'id':ident,'position_m':[x,y,z],'species':record['species'],'source_asset':asset,'lod':lod,'scale':[horizontal,horizontal,scale],
                           'crown_radius_m':radii[key]*horizontal,'height_m':reference*scale})
        # Sparse woodland layers are tied to real tree/root positions, not
        # scattered across town roads or thresholds. Existing path exclusions
        # are checked against the reserve planner before each new placement.
    print('BOTANICAL_STAGE measured_woodland_infill',flush=True)
    api['module']=module
    canopy=module('whole_town_canopy_coverage',ROOT/'tools/town_upgrade/canopy_coverage.py').populate(api,cache,entries,radii,placements,ground,col)
    print('BOTANICAL_STAGE texture_ground_layers',flush=True)
    understory=module('whole_town_understory',ROOT/'tools/town_upgrade/understory.py').build(api,col,cache,placements,api.get('buildings',[]),ROOT/'art/living_town',api['expansion_dir'],ground)
    report={'schema':'living_town.botanical_rebuild.v1','tree_count':len(placements),'species':dict(Counter(r['species'] for r in placements)),
            'lod_counts':dict(Counter(p['lod'] for p in placements)),'removed_objects':removed,'modified_objects':modified,
            'prototype_meshes':len({m.as_pointer() for meshes in cache.values() for m in meshes}),
            'prototype_triangles':sum(sum(len(p.vertices)-2 for p in m.polygons) for meshes in cache.values() for m in meshes),
            'placements':placements,'canopy_coverage':canopy,'understory':understory,'collection':col.name,'source_manifest':str(sources/'source_receipts.json'),
            'quality_status':'AWAITING_NATIVE_AND_RUNTIME_VISUAL_REVIEW','policy':'Old tree roots retained, terrain BVH re-grounding; adapted CC0 open branching crowns, photographed leaf normals and cutout alpha, shared mesh LODs. Source species and authored planting-program labels are separate.'}
    (output/'botanical_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


def lookdev(sources,output):
    bpy.ops.wm.read_homefile(use_empty=True,use_factory_startup=True);col=bpy.context.scene.collection;mats=materials(sources)
    for i,species in enumerate(('oak','birch','pine')):
        obs=tree_prototype(col,mats,species,i,'near')
        for ob in obs:ob.location.x=(i-1)*7
    fern_prototype(col,mats);meadow_prototype(col,mats)
    bpy.ops.import_scene.gltf(filepath=str(sources/'island_tree_02'/'island_tree_02_2k.gltf'))
    imported=[ob for ob in bpy.context.selected_objects if ob.type=='MESH']
    for ob in imported:
        for mat in ob.data.materials:
            if mat.name.startswith('island_tree_02_leaves'):
                for node in mat.node_tree.nodes:
                    if node.type=='TEX_IMAGE' and node.image and 'leaves_diff' in node.image.name:
                        node.image=bpy.data.images.load(str(sources/'island_tree_02'/'textures'/'leaves_rgba.png'),check_existing=True)
        dec=ob.modifiers.new('Authored medium botanical LOD','DECIMATE');dec.ratio=.055
        bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.location=(-7,7,0);ob.scale=(2,2,2)
    bpy.ops.mesh.primitive_plane_add(size=200);ob=bpy.context.object
    mat=bpy.data.materials.new('Lookdev warm meadow ground');mat.use_nodes=True
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.31,.32,.20,1);ob.data.materials.append(mat)
    bpy.ops.object.light_add(type='SUN',location=(0,0,12));bpy.context.object.rotation_euler=(.5,-.5,-.4);bpy.context.object.data.energy=2.2;bpy.context.object.data.angle=.20
    scene=bpy.context.scene;scene.world=bpy.data.worlds.new('Botanical lookdev summer sky');scene.world.use_nodes=True
    scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.48,.58,.72,1)
    scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.55
    bpy.ops.object.camera_add(location=(18,-30,16));cam=bpy.context.object;target=Vector((0,0,4.5));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=27;scene.camera=cam
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=6;scene.render.resolution_x=1500;scene.render.resolution_y=950;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG';scene.render.filepath=str(output/'botanical_lookdev.png')
    for image in bpy.data.images:
        if image.source=='FILE' and not image.packed_file:image.pack()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output/'botanical_lookdev.blend'),compress=True);bpy.ops.render.render(write_still=True)
    print('BOTANICAL_LOOKDEV_COMPLETE',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True);lookdev(a.sources,a.output)
