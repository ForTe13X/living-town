"""Blender adapter for CC0 fitted human/garments and original role details."""
import math
from array import array

from .geometry import catmull_path,ribbon,tube
from .human import adapted_body,minus,vertex_normals
from .assets import fit_asset,geometry_for,visible_skin
from .manifest import ANIMATED_JOINTS,BASE_HEIGHT,REQUIRED_JOINTS
from .apron import ApronPattern
from .footwear import fit_upper_cuff

PARENTS={'PelvisRoot':None,'BodyPivot':'PelvisRoot','HeadPivot':'BodyPivot'}
PARENTS['ApronDrape']='PelvisRoot'
PARENTS['ApronHem']='ApronDrape'
for side in ('L','R'):
    PARENTS.update({'UpperArm_'+side:'BodyPivot','Forearm_'+side:'UpperArm_'+side,'Hand_'+side:'Forearm_'+side,'Thigh_'+side:'PelvisRoot','Shin_'+side:'Thigh_'+side,'Foot_'+side:'Shin_'+side})


def rig_mesh(builder,mesh,weights,armature):
    for name in ANIMATED_JOINTS:mesh.vertex_groups.new(name='Skin_'+name)
    for index,row in enumerate(weights):
        for name,weight in row.items():
            if name in PARENTS:mesh.vertex_groups['Skin_'+name].add([index],weight,'REPLACE')
    modifier=mesh.modifiers.new('Continuous_Skin','ARMATURE');modifier.object=armature


def make_armature(builder,root,positions):
    bpy=builder.bpy
    data=bpy.data.armatures.new('Continuous_Human_Skin');armature=bpy.data.objects.new('HumanSkinRig',data)
    bpy.context.collection.objects.link(armature);armature.parent=root
    bpy.context.view_layer.objects.active=armature;armature.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name in ANIMATED_JOINTS:
        bone=data.edit_bones.new('Skin_'+name);bone.head=positions[name]
        # All rest bases share world axes, independent of the joint's extent.
        # This gives cross-engine, direct XYZ pose control without retargeting.
        bone.tail=(bone.head.x,bone.head.y+.055,bone.head.z)
        if PARENTS[name]:bone.parent=data.edit_bones['Skin_'+PARENTS[name]]
    bpy.ops.object.mode_set(mode='OBJECT');armature.select_set(False)
    for name in ANIMATED_JOINTS:
        constraint=armature.pose.bones['Skin_'+name].constraints.new('COPY_TRANSFORMS')
        constraint.name='Original_Presentation_Control';constraint.target=builder.joints[name]
        constraint.target_space='WORLD';constraint.owner_space='WORLD'
    return armature


def world_mesh(builder,name,geometry,material,root,weights,armature):
    mesh=builder.mesh(name,geometry,material,root)
    rig_mesh(builder,mesh,weights,armature)
    return mesh


def material_face_details(builder,data,look,root,armature):
    from .textures import material
    registered=builder.texture_library['characters'][look['id']]
    for category,name,role in [('eyes','high-poly','eyes'),('eyebrows',registered['brow_asset'].split('/')[-1],'brows'),('eyelashes','eyelashes01','lashes')]:
        asset=fit_asset(data,category,name);geometry,weights,_=geometry_for(asset)
        world_mesh(builder,'Registered_CC0_'+role,geometry,material(builder,look['id'],role),root,weights,armature)
    if look['detail'] in ('glasses','doctor'):
        metal=builder.material('#5e594c','metal');head=builder.joints['HeadPivot'];origin=data['joints']['HeadPivot']
        centers=[]
        for side in ['L','R']:
            eye=data['markers']['joint-'+side.lower()+'-eye'];ex,ey,ez=eye;ey+=.020;ez+=.002;centers.append((ex,ey,ez))
            points=[minus((ex+.021*math.cos(i*math.tau/28),ey,ez+.014*math.sin(i*math.tau/28)),origin) for i in range(29)]
            builder.line('Glasses_Rim_'+side,points,.0011,metal,head)
            sign=1 if ex>0 else -1
            builder.line('Glasses_Temple_'+side,[minus((ex+.021*sign,ey,ez),origin),minus((.084*sign,.048,ez),origin)],.001,metal,head)
        left,right=centers
        builder.line('Glasses_Bridge',[minus((x,(left[1]+right[1])/2,(left[2]+right[2])/2),origin) for x in [-.011,0,.011]],.001,metal,head)


def native_hair(builder,data,look,root,armature):
    name='ponytail01' if look['hair_style'] in ('ponytail','bun') else 'short01'
    asset=fit_asset(data,'hair',name);geometry,weights,_=geometry_for(asset)
    key='CC0_Hair_'+name+'_'+look['hair'].lstrip('#')
    if key not in builder.materials:
        bpy=builder.bpy;source=bpy.data.images.load(str(asset['stem'].parent/(name+'_diffuse.png')),check_existing=True)
        # Bake a palette-preserving derivative, retaining authored individual
        # strand opacity. A plain solid cap cannot supply this silhouette.
        work=source.copy();size=builder.texture_size*2;work.scale(size,size)
        pixels=array('f',[0])*(size*size*4);work.pixels.foreach_get(pixels)
        from .build import rgb
        tint=rgb(look['hair'])
        for i in range(0,len(pixels),4):
            value=.64+min(1.0,(pixels[i]+pixels[i+1]+pixels[i+2])*2.7)
            for k in range(3):pixels[i+k]=min(1,tint[k]*value)
        image=bpy.data.images.new(key,width=size,height=size,alpha=True);image.pixels.foreach_set(pixels)
        image.filepath_raw=str(builder.output/'textures'/(key+'.png'));image.file_format='PNG';image.save();image.pack();bpy.data.images.remove(work)
        material=bpy.data.materials.new(key);material.use_nodes=True;material.use_backface_culling=False
        nodes=material.node_tree.nodes;links=material.node_tree.links;bsdf=nodes.get('Principled BSDF')
        tex=nodes.new('ShaderNodeTexImage');tex.image=image
        links.new(tex.outputs['Color'],bsdf.inputs['Base Color']);links.new(tex.outputs['Alpha'],bsdf.inputs['Alpha'])
        bsdf.inputs['Roughness'].default_value=.64
        if hasattr(material,'surface_render_method'):material.surface_render_method='DITHERED'
        if hasattr(material,'blend_method'):material.blend_method='CLIP';material.alpha_threshold=.35
        builder.materials[key]=material;builder.images[key]=image
    world_mesh(builder,'Authored_CC0_Hair_'+name,geometry,builder.materials[key],root,weights,armature)
    return name


def contoured_apron(builder,pattern,look,root,armature,body,pelvis,data):
    from .textures import material as registered_material
    from .linen import metric_geometry
    material=registered_material(builder,look['id'],'apron')
    repeat=builder.texture_library['characters'][look['id']]['roles']['apron']['repeat_m'];scale=float(root.scale.x)
    material['surface_role']='PolyHaven_CC0_rough_linen_original_tailored_apron'
    stitch=builder.material('#c1b294')
    geometry,weights=pattern.surface()
    world_mesh(builder,'Apron_Continuous_Tailored_Panel',metric_geometry(geometry,scale,repeat),material,root,weights,armature)
    geometry,weights=pattern.pocket()
    world_mesh(builder,'Apron_Subdivided_Sewn_Pocket',metric_geometry(geometry,scale,repeat),material,root,weights,armature)
    origin=data['joints']['PelvisRoot']
    core=[p for p,row in zip(pattern.garment['positions'],pattern.garment['weights']) if sum(v for k,v in row.items() if k.startswith(('UpperArm','Forearm','Hand')))<.2]
    radius=max(abs(p[0]) for p in core if abs(p[2]-.995)<.04)+.006
    def back(x,z):
        values=[p[1] for p in core if abs(p[0]-x)<.04 and abs(p[2]-z)<.05]
        return min(values)-.006 if values else -.12
    for sign in [-1,1]:
        path=[(sign*.137,pattern.front(sign*.137,.995),.995),(sign*radius,.01,.995),(sign*.11,back(sign*.11,.995),.995),(0,back(0,.995)-.003,.989)]
        builder.mesh('Apron_Waist_Ribbon_'+str(sign),metric_geometry(ribbon([minus(p,origin) for p in catmull_path(path)],.012,.0012,across=(0,0,1)),scale,repeat,.012),material,pelvis)
        shoulder=[(sign*.078,pattern.front(sign*.078,1.28)+.001,1.28),(sign*.10,.045,1.40),(sign*.10,back(sign*.10,1.33),1.33),(sign*.11,back(sign*.11,1.18),1.18),(sign*.11,back(sign*.11,.995),.995)]
        builder.mesh('Apron_Shoulder_Ribbon_'+str(sign),metric_geometry(ribbon([minus(p,origin) for p in catmull_path(shoulder)],.013,.0012),scale,repeat,.013),material,body)
    from .apron_bow import gathered_bow
    geometry,weights,bow_report=gathered_bow((0,back(0,.995)-.003,.989),back,scale,repeat)
    world_mesh(builder,'Apron_Gathered_Linen_Waist_Bow',geometry,material,root,weights,armature)
    root['apron_bow']=bow_report
    builder.apron_bow_report=bow_report
    points=[]
    for a,b in zip([(-.064,.905),(-.064,.805),(.064,.805),(.064,.905)],[(-.064,.805),(.064,.805),(.064,.905),(-.064,.905)]):
        for i in range(10):
            t=i/10;x=a[0]+(b[0]-a[0])*t;z=a[1]+(b[1]-a[1])*t
            points.append((x,(pattern.pocket_front(x,z) if hasattr(pattern,'pocket_front') else pattern.front(x,z)+.0025)+.001,z))
    edge=tube(points+[points[0]],.00065,6)
    world_mesh(builder,'Apron_Pocket_Stitch',edge,stitch,root,[pattern.weights(p[0],p[2]) for p in edge[0]],armature)
    # A narrow sewn binding follows the actual cloth silhouette and the same
    # drape weights. It remains geometric detail after an ordinary GLB export.
    outline=[]
    for z in pattern.rows:
        x=-pattern.width(z)+.004;outline.append((x,pattern.front(x,z)+.001,z+.002))
    for z in reversed(pattern.rows):
        x=pattern.width(z)-.004;outline.append((x,pattern.front(x,z)+.001,z+.002))
    for n in range(33):
        u=1-n/16;x=u*(pattern.width(.375)-.004);z=.378+.014*abs(u)**4
        outline.append((x,pattern.front(x,z)+.001,z))
    edge=tube(outline+[outline[0]],.00042,6)
    world_mesh(builder,'Apron_Sewn_Edge_Binding',edge,stitch,root,[pattern.weights(p[0],p[2]) for p in edge[0]],armature)


def make_human(builder,look):
    builder.joints={};builder.meshes=[]
    data=adapted_body(look);positions=data['joints']
    garment=fit_asset(data,'clothes',look['outfit_asset'])
    footwear=fit_asset(data,'clothes',look['shoe_asset'])
    footwear=fit_upper_cuff(footwear,garment,positions)
    if not footwear['upper_cuff_fit']['success']:
        raise ValueError('Upper footwear lining remains outside trousers: '+look['id'])
    from .seating import metrics_from_joints
    sole={side:min(p[2] for p in footwear['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
    seat_metrics=metrics_from_joints(positions,sole)
    seat_metrics['seating_policy']='child_natural_dangling' if look['build']=='child' else 'adult_grounded'
    seat_metrics['pelvis_contact_allowance_m']=.005 if look['outfit_asset']=='male_worksuit01' else 0.
    look['seat_kinematics']=seat_metrics
    from .seat_corrective import generate_target
    pants_base,pants_weights,pants_ids=geometry_for(garment,'pants')
    pants_faces=[tuple(pants_ids[i] for i in face) for face in pants_base[1]]
    target,seat_report=generate_target(garment['positions'],pants_faces,garment['weights'],positions,seat_metrics,scale=look['body_height_m']/BASE_HEIGHT)
    if not seat_report.get('success',False):raise ValueError('Seat contact corrective failed: '+look['id']+' '+str(seat_report))
    garment['seat_contact_target']=target;pattern=ApronPattern(garment)
    look['seat_contact_corrective']={'target':'SeatContact','clips':['Sit','Soak'],'maximum_displacement_m':seat_report.get('maximum_posed_displacement_m'),'source':'localized source-space inverse-LBS cloth compression; topology/UV/weights retained'}
    has_apron=look['detail'] in ('apron','leather_apron','paint','sewing','flowers','herbs')
    positions.update(pattern.joints(positions,fit=has_apron,seat_kinematics=seat_metrics,stature_scale=look['body_height_m']/BASE_HEIGHT))
    root=builder.joint('CharacterRoot',None,(0,0,0));root.scale=(look['body_height_m']/BASE_HEIGHT,)*3
    root['persona_key']=look['id'];root['body_height_m']=look['body_height_m'];root['source_asset']='MakeHuman CC0 body/macro targets/tailored outfit/hair; original fitting, apron, role palette and rig'
    root['seat_kinematics']=seat_metrics
    for name in ANIMATED_JOINTS:
        parent=builder.joints[PARENTS[name]] if PARENTS[name] else root
        local=minus(positions[name],positions[PARENTS[name]]) if PARENTS[name] else positions[name]
        builder.joint(name,parent,local)
    armature=make_armature(builder,root,positions)
    from .textures import material as registered_material
    skin=registered_material(builder,look['id'],'skin');top=registered_material(builder,look['id'],'shirt');lower=registered_material(builder,look['id'],'pants')
    shirt_geometry=None;pants_geometry=None
    for region,material in [('skin',skin),('shirt',top),('pants',lower)]:
        if region=='skin':geometry,weights=visible_skin(data,garment,(footwear,))
        else:geometry,weights,source_ids=geometry_for(garment,region)
        if region=='shirt':shirt_geometry=(*geometry,weights)
        if region=='pants':pants_geometry=(*geometry,weights)
        if region=='pants':geometry=(geometry[0],[tuple((face[0],face[i],face[i+1])) for face in geometry[1] for i in range(1,len(face)-1)],geometry[2])
        mesh=world_mesh(builder,'Continuous_'+region,geometry,material,root,weights,armature)
        if region=='pants':
            for polygon in mesh.data.polygons:polygon.use_smooth=True
            mesh.shape_key_add(name='Basis');shape=mesh.shape_key_add(name='SeatContact')
            for vertex,index in zip(shape.data,source_ids):vertex.co=target[index]
            shape.value=0.;mesh['seat_contact_corrective']='Sit/Soak1; Idle/Walk/Lie/Work/Talk0'
    material_face_details(builder,data,look,root,armature)
    hair_asset=native_hair(builder,data,look,root,armature)
    body=builder.joints['BodyPivot'];pelvis=builder.joints['PelvisRoot'];origin=positions['BodyPivot']
    stitch=builder.material('#b5a58a')
    # Authored outfit already contains continuous cuffs, collar, belt, pockets,
    # placket and seams. Do not float a second procedural collar above it.
    if has_apron:
        contoured_apron(builder,pattern,look,root,armature,body,pelvis,data)
    # Keep occupation accessories, excluding the discarded planar apron system.
    if look['detail'] in ('tools','satchel','backpack','garden','fisher','doctor','captain','guitar'):
        builder.details(look,pelvis,body,top,stitch)
    geometry,weights,_=geometry_for(footwear)
    world_mesh(builder,'Registered_CC0_Footwear_'+look['shoe_asset'],geometry,registered_material(builder,look['id'],'shoes'),root,weights,armature)
    builder.extra_objects=[armature]
    builder.garment_clearance={'fitting':'CC0 authored barycentric helper offset and native occlusion mask'}
    builder.garment_clearance['seat_contact_corrective']=seat_report
    builder.garment_clearance['apron_pose_fit']=pattern.fit_report
    builder.garment_clearance['upper_shoe_cuff_fit']=footwear['upper_cuff_fit']
    if has_apron:builder.garment_clearance['apron_bow']=builder.apron_bow_report
    builder.asset_mapping={'outfit':'clothes/'+look['outfit_asset'],'hair':'hair/'+hair_asset,'face':builder.texture_library['characters'][look['id']]['skin_asset'],'eyes':'eyes/high-poly','brows':builder.texture_library['characters'][look['id']]['brow_asset'],'lashes':'eyelashes/eyelashes01','fit':'unposed hm08 three-vertex barycentric offsets scaled by anatomical axis; mapped 15-bone normalized skin weights','masked_body_vertices':len(garment['deleted'])}
    builder.asset_mapping['shoes']={'asset':'clothes/'+look['shoe_asset'],'source_authored_weights':True,'ground_translation_m':footwear['ground_offset_m'],'masked_body_vertices':len(footwear['deleted']),'upper_cuff_fit':footwear['upper_cuff_fit']}
    builder.morph_targets=dict(data['morph_targets'])
    return root,dict(builder.joints),list(builder.meshes)
