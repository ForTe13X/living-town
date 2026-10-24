"""Blender CPU source/export entry point. Run only under the engine supervisor.

blender --background --factory-startup --threads 6 --python PATH/build.py -- \
  --output "F:/Living Town/2026-10-20_Refined_Town/characters" \
  --game-assets PATH/game/assets/characters3d --render-review

Adapts the verified CC0 MakeHuman anatomical base, tailored system outfit and
strand-alpha hair with original fitting, aprons, role details, palette texture
derivatives and animation. No remote inference is required.
The hierarchy exports as ordinary glTF nodes and continuous skinning; runtime
animation is reproduced in TownCharacter3D.gd and seven native glTF clips.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
if str(REPO) not in sys.path:
    sys.path.insert(0,str(REPO))
from tools.town_upgrade.characters.geometry import ellipsoid, ring_surface, tube
from tools.town_upgrade.characters.manifest import ANIMATED_JOINTS, BASE_HEIGHT, CLIPS, REQUIRED_JOINTS, build_manifest, source_digest, validate_manifest
from tools.town_upgrade.characters.animation import pelvis_height,pose_values


def arguments():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--game-assets",type=Path)
    p.add_argument("--texture-library",type=Path,required=True,help="Source-bound 2K registered PBR library manifest from prepare_textures.py")
    p.add_argument("--personas",default="",help="Comma-separated inspection subset; default all 25.")
    p.add_argument("--texture-size",type=int,default=512,choices=[256,512,1024])
    p.add_argument("--render-review",action="store_true")
    p.add_argument("--review-size",type=int,default=768)
    p.add_argument("--samples",type=int,default=24)
    return p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])


def srgb(value):
    c=int(value,16)/255
    return c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4


def rgb(value): return tuple(srgb(value[i:i+2]) for i in (1,3,5))


class CharacterBuilder:
    def __init__(self,bpy,output,texture_size,texture_library):
        self.bpy=bpy;self.output=output;self.texture_size=texture_size
        from tools.town_upgrade.characters.textures import load_library
        self.texture_library=load_library(texture_library)
        self.materials={};self.images={};self.joints={};self.meshes=[]
        (output/"textures").mkdir(parents=True,exist_ok=True)

    def bitmap(self,key,color,kind):
        if key in self.images: return self.images[key]
        size=self.texture_size
        image=self.bpy.data.images.new(key,width=size,height=size,alpha=True)
        pixels=array('f');base=rgb(color)
        seed=int(hashlib.sha256(key.encode()).hexdigest()[:8],16)
        for y in range(size):
            for x in range(size):
                n=((x*73856093 ^ y*19349663 ^ seed)*83492791 & 65535)/65535-.5
                warp=math.sin(2*math.pi*x/8);weft=math.sin(2*math.pi*y/8)
                if kind=="normal":
                    pixels.extend((.5+.11*warp,.5+.11*weft,.983,1))
                elif kind=="rough":
                    pixels.extend((1,.68+n*.12,0,1))
                elif kind=="cloth":
                    shade=1+.010*warp*weft+.009*n+.001*math.sin(x*.12+y*.03)
                    pixels.extend(tuple(min(1,max(0,c*shade)) for c in base)+(1,))
                elif kind=="skin":
                    # Fine pore variation, not a projected photographic face.
                    shade=1+n*.038
                    pixels.extend(tuple(min(1,c*shade) for c in base)+(1,))
                else:
                    grain=.04*math.sin(x*.23+math.sin(y*.03))+.06*n
                    pixels.extend(tuple(max(0,c*(1+grain)) for c in base)+(1,))
        if kind in ("normal","rough"):
            image.colorspace_settings.name="Non-Color"
        else:
            # Pixel buffer contains linear values; PNG encoding converts to sRGB.
            image.colorspace_settings.name="sRGB"
        image.pixels.foreach_set(pixels)
        image.filepath_raw=str(self.output/"textures"/(key+".png"));image.file_format='PNG'
        image.save();image.pack();self.images[key]=image
        return image

    def material(self,color,kind="cloth",label=""):
        key=kind+"_"+color.lstrip('#')
        if key in self.materials: return self.materials[key]
        mat=self.bpy.data.materials.new(label or key);mat.use_nodes=True
        mat.diffuse_color=rgb(color)+(1,)
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        bsdf=nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=rgb(color)+(1,)
        bsdf.inputs['Roughness'].default_value=.74 if kind=="cloth" else .48
        if kind in ("cloth","skin","leather"):
            tex=nodes.new('ShaderNodeTexImage');tex.image=self.bitmap(key,color,kind)
            links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        if kind=="cloth":
            normal=nodes.new('ShaderNodeTexImage');normal.image=self.bitmap('woven_normal',"#ffffff","normal")
            nm=nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.10
            links.new(normal.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bsdf.inputs['Normal'])
            rough=nodes.new('ShaderNodeTexImage');rough.image=self.bitmap('woven_roughness',"#ffffff","rough")
            separate=nodes.new('ShaderNodeSeparateColor');links.new(rough.outputs['Color'],separate.inputs['Color'])
            links.new(separate.outputs['Green'],bsdf.inputs['Roughness'])
        elif kind=="skin":
            if 'Subsurface Weight' in bsdf.inputs: bsdf.inputs['Subsurface Weight'].default_value=.065
            bsdf.inputs['Roughness'].default_value=.57
        elif kind=="hair": bsdf.inputs['Roughness'].default_value=.47
        elif kind=="metal":
            bsdf.inputs['Metallic'].default_value=.75;bsdf.inputs['Roughness'].default_value=.35
        self.materials[key]=mat
        return mat

    def joint(self,name,parent,location):
        obj=self.bpy.data.objects.new(name,None);self.bpy.context.collection.objects.link(obj)
        obj.parent=parent;obj.location=location;self.joints[name]=obj
        return obj

    def mesh(self,name,geometry,mat,parent,location=(0,0,0)):
        verts,faces,uv=geometry
        mesh=self.bpy.data.meshes.new(name+"_mesh");mesh.from_pydata(verts,[],faces);mesh.update()
        layer=mesh.uv_layers.new(name="UVMap")
        for polygon in mesh.polygons:
            polygon.use_smooth=len(polygon.vertices)==4
            for li in polygon.loop_indices:
                layer.data[li].uv=uv[mesh.loops[li].vertex_index]
        obj=self.bpy.data.objects.new(name,mesh);self.bpy.context.collection.objects.link(obj)
        obj.parent=parent;obj.location=location;mesh.materials.append(mat)
        self.meshes.append(obj)
        return obj

    def line(self,name,points,radius,mat,parent):
        return self.mesh(name,tube(points,radius,6),mat,parent)

    def orb(self,name,center,radii,mat,parent,segments=20,rings=12):
        return self.mesh(name,ellipsoid(center,radii,segments,rings),mat,parent)

    def patch(self,name,verts,mat,parent):
        # Thin cloth panel with a genuine rear surface, valid from all cameras.
        # Most tailoring vertices are given bottom-left to top-right, which
        # winds away from the front (+Y); reverse for outward lighting.
        verts=list(reversed(verts))
        back=[(x,y-.0015,z) for x,y,z in verts]
        n=len(verts);faces=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        xmin=min(v[0] for v in verts);xspan=max(v[0] for v in verts)-xmin or 1
        zmin=min(v[2] for v in verts);zspan=max(v[2] for v in verts)-zmin or 1
        uv=[((x-xmin)/xspan,(z-zmin)/zspan) for x,y,z in verts]*2
        return self.mesh(name,(verts+back,faces,uv),mat,parent)

    def optimize(self):
        """Batch rigid detail meshes per joint/material; preserve skinned layers."""
        import bmesh
        groups={};retained=[]
        for obj in self.meshes:
            if obj.modifiers:
                retained.append(obj);continue
            key=(obj.parent,obj.data.materials[0] if obj.data.materials else None)
            groups.setdefault(key,[]).append(obj)
        for (parent,material),objects in groups.items():
            if len(objects)==1:
                retained.extend(objects);continue
            vertices=[];faces=[];uv=[]
            for obj in objects:
                offset=len(vertices)
                # matrix_local depends on evaluated parent transforms. Newly
                # constructed joints have not necessarily been evaluated yet;
                # matrix_basis is the explicitly authored local transform.
                vertices.extend(tuple(obj.matrix_basis@v.co) for v in obj.data.vertices)
                source_uv=[(0.,0.) for _ in obj.data.vertices]
                for loop in obj.data.loops:source_uv[loop.vertex_index]=tuple(obj.data.uv_layers.active.data[loop.index].uv)
                uv.extend(source_uv)
                faces.extend(tuple(offset+i for i in face.vertices) for face in obj.data.polygons)
            obj=self.mesh(parent.name+'_Detail_'+material.name,(vertices,faces,uv),material,parent)
            retained.append(obj)
            for old in objects:self.bpy.data.objects.remove(old,do_unlink=True)
        self.meshes=retained
        # Tangent export requires triangles, including seam and hair end caps.
        for obj in self.meshes:
            if obj.data.shape_keys is not None:
                if any(len(face.vertices)!=3 for face in obj.data.polygons):raise ValueError('Corrective mesh must be triangulated before shape creation')
                continue
            bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free();obj.data.update()
        return list(self.meshes)

    def details(self,look,pelvis,body,top,stitch):
        detail=look['detail'];leather=self.material('#805e40','leather')
        if detail in ('apron','leather_apron','paint','sewing','flowers','herbs'):
            apron=self.material(look['apron'] if detail!='paint' else '#c8baa0')
            self.patch('Apron_Bib',[(-.105,.117,.10),(.105,.117,.10),(.094,.127,.37),(-.094,.127,.37)],apron,body)
            # Curved hem with thickness; separated from legs for joint motion.
            self.patch('Apron_Skirt',[(-.18,.123,-.40),(.18,.123,-.40),(.157,.119,.11),(-.157,.119,.11)],apron,pelvis)
            self.patch('Apron_Pocket',[(-.073,.129,-.20),(.073,.129,-.20),(.073,.131,-.07),(-.073,.131,-.07)],apron,pelvis)
            self.line('Apron_Pocket_Stitch',[(-.071,.135,-.07),(-.071,.135,-.195),(.071,.135,-.195),(.071,.135,-.07)],.0009,stitch,pelvis)
            for sign in [-1,1]:
                self.line('Apron_Shoulder_Strap_'+str(sign),[(.08*sign,.131,.36),(.11*sign,.055,.451),(.11*sign,-.082,.40)],.009,apron,body)
                self.line('Apron_Tie_'+str(sign),[(.16*sign,0,.06),(.11*sign,-.118,.06),(0,-.121,.055),(.06*sign,-.128,-.17)],.006,apron,pelvis)
        if detail=='tools':
            self.mesh('Leather_Belt',ring_surface([(.043,.168,.113,0),(.074,.168,.113,0)],32),leather,pelvis)
            self.orb('Tool_Pouch',(.18,.015,-.05),(.055,.04,.10),leather,pelvis,20,12)
            wood=self.material('#ac8757','wood');metal=self.material('#8f928c','metal')
            for n in range(3):
                x=.15+n*.023
                self.line('Tool_Handle_'+str(n),[(x,.015,-.06),(x,.015,.11)],.006,wood,pelvis)
                self.line('Tool_Steel_'+str(n),[(x,.015,.11),(x,.018,.15)],.004,metal,pelvis)
        if detail in ('satchel','backpack','garden','fisher','herbs'):
            bagmat=self.material('#8d7854','cloth')
            self.orb('Canvas_Bag',(0,-.145,.235),(.118,.055,.158),bagmat,body,28,18)
            self.patch('Bag_Flap',[(-.10,-.201,.22),(.10,-.201,.22),(.10,-.199,.35),(-.10,-.199,.35)],bagmat,body)
            for sign in [-1,1]:
                self.line('Canvas_Strap_'+str(sign),[(.08*sign,-.18,.29),(.12*sign,-.06,.45),(.12*sign,.105,.35),(.11*sign,.106,.10)],.009,leather,body)
        if detail=='doctor':
            metal=self.material('#7e898c','metal')
            self.line('Stethoscope',[(-.067,.112,.39),(-.074,.123,.27),(-.015,.128,.21),(.061,.12,.27),(.061,.11,.39)],.0035,self.material('#4b5154','rubber'),body)
            self.orb('Stethoscope_Bell',(-.015,.137,.205),(.015,.005,.015),metal,body)
        if detail=='captain':
            navy=self.material('#414b49')
            head=self.joints['HeadPivot']
            self.mesh('Captain_Cap',ring_surface([(.19,.094,.080,-.005),(.23,.09,.077,-.008),(.247,.070,.06,-.012)],32),navy,head)
            self.orb('Captain_Visor',(0,.066,.193),(.088,.057,.006),navy,head,24,8)
            self.orb('Captain_Badge',(0,.079,.216),(.010,.002,.012),self.material('#a38c55','metal'),head)
        if detail=='guitar':
            # A small attached instrument, not a silhouette-changing permanent prop.
            instrument=self.joint('InstrumentPivot',body,(.10,-.12,.03))
            wood=self.material('#a37143','leather')
            self.orb('Guitar_Lower_Bout',(0,-.025,.10),(.105,.034,.125),wood,instrument,28,16)
            self.orb('Guitar_Upper_Bout',(0,-.025,.23),(.081,.030,.085),wood,instrument,24,14)
            self.mesh('Guitar_Neck',ring_surface([(.25,.021,.014,-.026),(.56,.020,.014,-.026)],12),self.material('#5c4730','wood'),instrument)
            self.line('Guitar_Strap',[(-.02,-.12,.16),(-.15,-.02,.44),(.10,.10,.12)],.007,leather,body)


def bake_actions(bpy,joints):
    """Native glTF animation survives export without Blender-only rig features."""
    rest={name:tuple(j.rotation_euler) for name,j in joints.items()}
    rest_location={name:tuple(j.location) for name,j in joints.items()}
    parameters=review_parameters(joints)
    leg_length=joints['Shin_L'].location.length+joints['Foot_L'].location.length
    # glTF groups equal track names into one clip across rigid animated parts.
    for clip in CLIPS:
        for joint_name in ANIMATED_JOINTS:
            obj=joints[joint_name];obj.animation_data_clear();obj.animation_data_create()
            action=bpy.data.actions.new(clip+'_'+joint_name);obj.animation_data.action=action
            for frame in range(1,26,2):
                angles=pose_values(clip,(frame-1)/24,**parameters)[joint_name]
                blender_angles=(angles[0],-angles[2],angles[1])
                obj.rotation_euler=tuple(rest[joint_name][i]+blender_angles[i] for i in range(3))
                obj.keyframe_insert(data_path='rotation_euler',frame=frame)
                if joint_name=='PelvisRoot':
                    obj.location=(rest_location[joint_name][0],rest_location[joint_name][1],pelvis_height(clip,(frame-1)/24,rest_location[joint_name][2],leg_length,**parameters))
                    obj.keyframe_insert(data_path='location',frame=frame)
            track=obj.animation_data.nla_tracks.new();track.name=clip
            strip=track.strips.new(clip,1,action);strip.name=clip
            obj.animation_data.action=None
    for name,obj in joints.items():
        obj.rotation_euler=rest[name]
        obj.location=rest_location[name]
        if obj.animation_data:
            for track in obj.animation_data.nla_tracks:track.mute=True
    for obj in joints['PelvisRoot'].parent.children_recursive:
        keys=obj.data.shape_keys if obj.type=='MESH' else None
        if keys is None or 'SeatContact' not in keys.key_blocks:continue
        keys.animation_data_clear();keys.animation_data_create();target=keys.key_blocks['SeatContact']
        for clip in CLIPS:
            action=bpy.data.actions.new(clip+'_SeatContact');keys.animation_data.action=action
            for frame in (1,25):
                target.value=1. if clip in ('Sit','Soak') else 0.;target.keyframe_insert(data_path='value',frame=frame)
            track=keys.animation_data.nla_tracks.new();track.name=clip;track.strips.new(clip,1,action);track.mute=True
        keys.animation_data.action=None;target.value=0.


def review_parameters(joints):
    root=joints['PelvisRoot'].parent
    return {'seat_metrics':root.get('seat_kinematics'),'stature_scale':float(root.scale.x)}


def set_review_pose(joints,clip,phase,*,root_floor_offset_m=0.):
    for name,angles in pose_values(clip,phase,root_floor_offset_m=root_floor_offset_m,**review_parameters(joints)).items():
        joints[name].rotation_euler=(angles[0],-angles[2],angles[1])
    for obj in joints['PelvisRoot'].parent.children_recursive:
        keys=obj.data.shape_keys if obj.type=='MESH' else None
        if keys is not None and 'SeatContact' in keys.key_blocks:keys.key_blocks['SeatContact'].value=1. if clip in ('Sit','Soak') else 0.


def review_seat_reference(bpy,root,joints,camera,key,output):
    """An explicit metric lookdev fixture, created only after model export."""
    from mathutils import Vector
    scene=bpy.context.scene;objects=[]
    def surface(name,color):
        mat=bpy.data.materials.new(name);mat.use_nodes=True
        bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1);bsdf.inputs['Roughness'].default_value=.88
        return mat
    seat_material=surface('Lookdev_Seat_Reference_Blue',(.16,.24,.30));floor_material=surface('Lookdev_Floor_Reference',(.30,.31,.30))
    def box(name,center,dimensions,material):
        bpy.ops.mesh.primitive_cube_add(size=1,location=center);obj=bpy.context.object;obj.name='LOOKDEV_REFERENCE_'+name;obj.dimensions=dimensions
        obj.data.materials.append(material);obj['lookdev_reference_only']=True;objects.append(obj)
    seat_height=.462;root_floor_offset=.025
    box('Ground',(0,0,-.015),(1.6,1.6,.03),floor_material)
    box('Seat_0462m',(0,0,seat_height-.0225),(.44,.44,.045),seat_material)
    for x in [-.185,.185]:
        for y in [-.185,.185]:box('Leg',(x,y,(seat_height-.045)/2),(.035,.035,seat_height-.045),seat_material)
    box('Chair_Back',(0,-.2225,.76),(.44,.035,.58),seat_material)
    original_root=tuple(root.location);original_hip=tuple(joints['PelvisRoot'].location)
    root.location=(0,0,root_floor_offset);set_review_pose(joints,'Sit',.25,root_floor_offset_m=root_floor_offset)
    scale=float(root.scale.x);joints['PelvisRoot'].location=(original_hip[0],original_hip[1],pelvis_height('Sit',.25,original_hip[2],1.,root_floor_offset_m=root_floor_offset,**review_parameters(joints)))
    def evaluated_contact():
        bpy.context.view_layer.update();depsgraph=bpy.context.evaluated_depsgraph_get();shoes=[];pants=[];faces=[]
        for obj in root.children_recursive:
            if obj.type!='MESH' or not (obj.name.startswith('Registered_CC0_Footwear_') or obj.name=='Continuous_pants'):continue
            evaluated=obj.evaluated_get(depsgraph);mesh=evaluated.to_mesh();points=[tuple(evaluated.matrix_world@vertex.co) for vertex in mesh.vertices]
            if obj.name.startswith('Registered_CC0_Footwear_'):shoes.extend(points)
            else:
                offset=len(pants);pants.extend(points);faces.extend(tuple(offset+i for i in face.vertices) for face in mesh.polygons)
            evaluated.to_mesh_clear()
        return shoes,pants,faces
    shoe_points,pants_points,pants_faces=evaluated_contact()
    seat_points=[p for p in pants_points if abs(p[0])<.20 and -.18<p[1]<.18]
    report={'scope':'Actual evaluated skinned mesh against isolated lookdev chair/ground; fixture is not exported town geometry','seat_top_m':seat_height,'floor_top_m':0,'actor_root_floor_offset_m':root_floor_offset,'body_height_m':root.get('body_height_m'),'source_hip_height_m':float(joints['PelvisRoot'].location.z),'current_thigh_radians':float(joints['Thigh_L'].rotation_euler.x),'source_scale':scale,'minimum_sole_z_m':min(p[2] for p in shoe_points),'left_sole_gap_m':min(p[2] for p in shoe_points if p[0]>0),'right_sole_gap_m':min(p[2] for p in shoe_points if p[0]<0),'minimum_garment_z_over_seat_m':min((p[2] for p in seat_points),default=None)}
    from tools.town_upgrade.characters.seat_corrective import clipped_seat_report
    report['seat_triangle_contact']=clipped_seat_report(pants_points,pants_faces,seat_height_m=seat_height)
    report['seating_policy']=root.get('seat_kinematics',{}).get('seating_policy','adult_grounded')
    report['ground_contact_required']=report['seating_policy']!='child_natural_dangling'
    root.location=(0,0,0);set_review_pose(joints,'Sit',.25)
    joints['PelvisRoot'].location=(original_hip[0],original_hip[1],pelvis_height('Sit',.25,original_hip[2],1.,**review_parameters(joints)))
    native_shoes,native_pants,native_faces=evaluated_contact()
    report['native_frame_maximum_world_difference_m']=max(math.dist(a,b) for a,b in zip(shoe_points+pants_points,native_shoes+native_pants))
    report['native_seat_triangle_contact']=clipped_seat_report(native_pants,native_faces,seat_height_m=seat_height)
    report['native_minimum_sole_z_m']=min(p[2] for p in native_shoes)
    root.location=(0,0,root_floor_offset);set_review_pose(joints,'Sit',.25,root_floor_offset_m=root_floor_offset)
    joints['PelvisRoot'].location=(original_hip[0],original_hip[1],pelvis_height('Sit',.25,original_hip[2],1.,root_floor_offset_m=root_floor_offset,**review_parameters(joints)))
    (output/'review'/f'{key}_sit_reference_contact.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    camera.data.ortho_scale=1.72
    for label,angle in [('three_quarter',math.pi*.20),('side',math.pi/2)]:
        camera.location=(3.5*math.sin(angle),3.5*math.cos(angle),.86);camera.rotation_euler=(Vector((0,0,.64))-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(output/'review'/f'{key}_sit_reference_{label}.png');bpy.ops.render.render(write_still=True)
    root.location=original_root;joints['PelvisRoot'].location=original_hip;set_review_pose(joints,'Idle',0)
    camera.data.ortho_scale=2.06
    for obj in objects:bpy.data.objects.remove(obj,do_unlink=True)


def review_scene(bpy,root,key,output,args):
    from mathutils import Vector
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=args.samples
    scene.render.threads_mode='FIXED';scene.render.threads=6
    scene.render.resolution_x=args.review_size;scene.render.resolution_y=args.review_size;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    scene.world.use_nodes=True
    background=scene.world.node_tree.nodes.get('Background')
    background.inputs['Color'].default_value=(.72,.69,.63,1);background.inputs['Strength'].default_value=.6
    scene.view_settings.view_transform='AgX'
    light_data=bpy.data.lights.new('Review_Key','AREA');light=bpy.data.objects.new('Review_Key',light_data);scene.collection.objects.link(light)
    light.location=(3,4,5);light_data.energy=650;light_data.shape='DISK';light_data.size=4
    light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
    fill_data=bpy.data.lights.new('Review_Fill','AREA');fill=bpy.data.objects.new('Review_Fill',fill_data);scene.collection.objects.link(fill)
    fill.location=(-3,-1,3);fill_data.energy=330;fill_data.size=3
    fill.rotation_euler=(Vector((0,0,1))-fill.location).to_track_quat('-Z','Y').to_euler()
    camera_data=bpy.data.cameras.new('Review_Camera');camera=bpy.data.objects.new('Review_Camera',camera_data);scene.collection.objects.link(camera)
    scene.camera=camera;camera_data.type='ORTHO';camera_data.ortho_scale=2.06
    for label,angle in [('front',0),('three_quarter',math.pi*.20),('side',math.pi/2),('back',math.pi)]:
        camera.location=(3.5*math.sin(angle),3.5*math.cos(angle),1.10)
        camera.rotation_euler=(Vector((0,0,.88))-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(output/'review'/f'{key}_{label}.png');bpy.ops.render.render(write_still=True)
    if args.personas:
        # Portrait framing follows each character's physical stature.  A fixed
        # adult camera clipped taller Ben's forehead despite identical source UVs.
        stature_scale=float(root.scale.z)
        for lighting in ['neutral','summer']:
            light_data.color=(1,1,1) if lighting=='neutral' else (1,.88,.73)
            fill_data.color=(1,1,1) if lighting=='neutral' else (.72,.83,1)
            background.inputs['Color'].default_value=(.65,.65,.65,1) if lighting=='neutral' else (.72,.69,.63,1)
            for label,angle in [('front',0),('three_quarter',math.pi*.20)]:
                camera_data.ortho_scale=.34*stature_scale;focus=1.52*stature_scale
                camera.location=(3.5*math.sin(angle),3.5*math.cos(angle),focus+.012)
                camera.rotation_euler=(Vector((0,0,focus))-camera.location).to_track_quat('-Z','Y').to_euler()
                scene.render.filepath=str(output/'review'/f'{key}_portrait_{lighting}_{label}.png');bpy.ops.render.render(write_still=True)
        for label,angle in [('front',0),('three_quarter',math.pi*.20)]:
            camera_data.ortho_scale=.76*stature_scale;focus=1.13*stature_scale
            camera.location=(3.5*math.sin(angle),3.5*math.cos(angle),focus+.012)
            camera.rotation_euler=(Vector((0,0,focus))-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(output/'review'/f'{key}_garment_detail_{label}.png');bpy.ops.render.render(write_still=True)
        light_data.color=(1,1,1);fill_data.color=(1,1,1)
        camera_data.ortho_scale=2.06
    # Hero builds include joint/garment motion evidence before a whole roster
    # is accepted. These are genuine pose renders from the authored skin rig.
    if args.personas:
        joints={obj.name:obj for obj in root.children_recursive if obj.name in ANIMATED_JOINTS}
        rest_location=tuple(joints['PelvisRoot'].location)
        length=joints['Shin_L'].location.length+joints['Foot_L'].location.length
        camera.location=(2.4,3.0,1.2);camera.rotation_euler=(Vector((0,0,.85))-camera.location).to_track_quat('-Z','Y').to_euler()
        poses=[('walk_a','Walk',.125),('walk_b','Walk',.375),('walk_c','Walk',.625),('walk_d','Walk',.875),('sit','Sit',.25),('lie','Lie',.25),('work','Work',.25),('talk','Talk',.25),('soak','Soak',.25)]
        for label,clip,phase in poses:
            set_review_pose(joints,clip,phase)
            joints['PelvisRoot'].location=(rest_location[0],rest_location[1],pelvis_height(clip,phase,rest_location[2],length,**review_parameters(joints)))
            scene.render.filepath=str(output/'review'/f'{key}_pose_{label}.png');bpy.ops.render.render(write_still=True)
        review_seat_reference(bpy,root,joints,camera,key,output)
        set_review_pose(joints,'Idle',0);joints['PelvisRoot'].location=rest_location
    for obj in [light,fill,camera]:bpy.data.objects.remove(obj,do_unlink=True)


def export_one(bpy,root,joints,meshes,path):
    from tools.town_upgrade.characters.glb import attach_animations
    bpy.ops.object.select_all(action='DESELECT')
    def select_tree(obj):
        obj.select_set(True)
        for child in obj.children:select_tree(child)
    select_tree(root)
    bpy.context.view_layer.objects.active=root
    # Export stable rest transforms first. Native glTF channels are appended
    # explicitly, avoiding version-dependent action/NLA merging in exporters.
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,
        export_animations=False,
        export_apply=False,export_extras=True,export_texcoords=True,export_normals=True,export_tangents=True,export_skins=True,export_morph=True)
    attach_animations(path)


def main():
    import bpy
    from tools.town_upgrade.characters.build_human import make_human
    args=arguments();args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    for directory in ['models','review','source']:(args.output/directory).mkdir(exist_ok=True)
    if args.game_assets:args.game_assets.mkdir(parents=True,exist_ok=True)
    personas=json.loads((REPO/'game/data/personas.json').read_text(encoding='utf-8'))
    manifest=build_manifest(personas);errors=validate_manifest(manifest,set(personas))
    if errors:raise RuntimeError('; '.join(errors))
    keys=args.personas.split(',') if args.personas else list(manifest['characters'])
    if set(keys)-set(manifest['characters']):raise ValueError('Unknown personas')
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    bpy.context.scene.render.fps=24;bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=25
    builder=CharacterBuilder(bpy,args.output,args.texture_size,args.texture_library);report={}
    shutil.copytree(args.texture_library.resolve().parent,args.output/'registered_pbr',dirs_exist_ok=True)
    for key in keys:
        root,joints,meshes=make_human(builder,manifest['characters'][key]);meshes=builder.optimize();bake_actions(bpy,joints)
        missing=set(REQUIRED_JOINTS)-set(joints)
        if missing:raise RuntimeError(f'{key}: missing joints {missing}')
        path=args.output/'models'/f'{key}.glb';export_one(bpy,root,joints,meshes,path)
        if args.game_assets:shutil.copy2(path,args.game_assets/path.name)
        # Each source is isolated and all procedural material images are packed.
        bpy.ops.wm.save_as_mainfile(filepath=str(args.output/'source'/f'{key}.blend'))
        if args.render_review:review_scene(bpy,root,key,args.output,args)
        report[key]={"vertices":sum(len(m.data.vertices) for m in meshes),"triangles":sum(sum(len(p.vertices)-2 for p in m.data.polygons) for m in meshes),"meshes":len(meshes),"joints":len(joints),"clips":CLIPS,"glb_bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
        report[key]['garment_fitting']=builder.garment_clearance
        report[key]['cc0_asset_mapping']=builder.asset_mapping
        report[key]['anatomical_macro_targets']=builder.morph_targets
        manifest['characters'][key]['model_sha256']=report[key]['sha256']
        manifest['characters'][key]['model_bytes']=report[key]['glb_bytes']
        for obj in list(dict.fromkeys([root]+list(joints.values())+meshes+builder.extra_objects)):
            if obj.name in bpy.data.objects:bpy.data.objects.remove(obj,do_unlink=True)
        # Bound peak memory for the full roster: 2K float image buffers must not
        # accumulate for all previous residents after their packed source/GLB
        # has already been saved. Shared maps are reloaded for the next model.
        builder.materials={};builder.images={}
        bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=False,do_recursive=True)
        print('CHARACTER_EXPORTED '+key+' '+json.dumps(report[key]),flush=True)
    (args.output/'characters.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.game_assets and set(keys)==set(manifest['characters']):
        staged_manifest=args.game_assets.resolve().parents[1]/'data/town3d/characters.json'
        staged_manifest.parent.mkdir(parents=True,exist_ok=True)
        staged_manifest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    provenance={"source_digest":source_digest(),"blender_version":bpy.app.version_string,"engine_threads":6,"render_device":"CPU","original_apron_palette_textures_rig_adaptation":True,"external_models":[{"name":"MakeHuman anatomical base, weights and macro targets","license":"CC0-1.0","provenance":"source/vendor/makehuman/provenance.json"},{"name":"MakeHuman tailored system outfits and alpha-textured hair","license":"CC0-1.0","provenance":"source/vendor/system_assets/provenance.json"}],"texture_size":args.texture_size,"entries":report,"complete":set(keys)==set(manifest['characters'])}
    provenance['registered_pbr_library']={'path':'registered_pbr/library_manifest.json','sha256':hashlib.sha256(args.texture_library.read_bytes()).hexdigest(),'source_size':builder.texture_library['size'],'uv_registration':'authored body/garment/face-component UV, no tiling or projection'}
    provenance['external_textiles']={'name':'Poly Haven rough_linen','license':'CC0-1.0','provenance':'source/vendor/polyhaven_rough_linen/source_receipts.json','mapping':'measured physical repeat on original apron/straps/pocket; authored AO/roughness/normal'}
    runtime_adapter=REPO/'game/scripts/TownCharacter3D.gd'
    provenance['runtime_adapter_sha256']=hashlib.sha256(runtime_adapter.read_bytes()).hexdigest()
    shutil.copy2(runtime_adapter,args.output/'source/TownCharacter3D.gd')
    (args.output/'build_report.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8')
    for p in HERE.glob('*.py'):shutil.copy2(p,args.output/'source'/p.name)
    for p in HERE.glob('*.gd'):shutil.copy2(p,args.output/'source'/p.name)
    shutil.copy2(HERE/'README.md',args.output/'source/README.md')
    shutil.copytree(HERE/'vendor',args.output/'source/vendor',dirs_exist_ok=True)
    print('CHARACTER_BUILD_FINISHED '+str(args.output),flush=True)


if __name__=='__main__':main()
