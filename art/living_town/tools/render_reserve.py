"""Render source-bound reserve/interior review views in a disposable Blender process.

blender -b living_town_complete.blend -t 6 --python tools/render_reserve.py -- --preview
Use --only comma-separated IDs to inspect a changed area without repeating all views.
Never saves visibility or temporary review cameras into the native source.
"""
import argparse
import hashlib
import json
import math
import os
import sys
import time
from pathlib import Path

import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview',action='store_true')
    parser.add_argument('--only')
    parser.add_argument('--width',type=int)
    parser.add_argument('--samples',type=int)
    opt=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    scene=bpy.data.scenes['Living_Town_Summer']
    bpy.context.window.scene=scene
    source=Path(bpy.data.filepath)
    source_sha=hashlib.sha256(source.read_bytes()).hexdigest()
    render_module_sha=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    manifest=json.loads((ROOT/'town_manifest.json').read_text(encoding='utf-8'))
    reserve={b['id']:b for b in manifest['reserve_amenities']['buildings']}
    plan=json.loads((ROOT/'reserve_plan.json').read_text(encoding='utf-8'))
    scene.render.engine='CYCLES';scene.cycles.device='CPU'
    scene.cycles.samples=opt.samples or (8 if opt.preview else 32)
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=6
    scene.render.resolution_x=opt.width or (1000 if opt.preview else 1800)
    scene.render.resolution_y=round(scene.render.resolution_x*.67)
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    directory=ROOT/'renders/reserve_v6';directory.mkdir(parents=True,exist_ok=True)
    evidence=ROOT/'evidence'/('reserve_renders_preview.json' if opt.preview else 'reserve_renders.json')
    records=[]
    if evidence.exists():
        records=[r for r in json.loads(evidence.read_text(encoding='utf-8')) if r.get('source_blend_sha256')==source_sha]
    covers={c.name:(c.hide_render,c.hide_viewport) for c in bpy.data.collections
            if c.name.endswith(('_Roof','_FrontWall','_UpperFloorCover','_FrontCover'))}

    def pose(ident,offset,target_z=1.):
        b=reserve[ident];x,y=b['center'];z=b['pad_level_m'];yaw=math.radians(b['yaw_degrees'])
        dx,dy,dz=offset
        return (x+math.cos(yaw)*dx-math.sin(yaw)*dy,y+math.sin(yaw)*dx+math.cos(yaw)*dy,z+dz),(x,y,z+target_z)

    def amenity(shot,ident,offset,cut=False,lens=48):
        location,target=pose(ident,offset)
        return (shot,None,ident if cut else None,location,target,lens)

    jobs=[
        ('01_reserve_overview','15_Reserve_Overview',None,None,None,45),
        ('02_reserve_topography','16_Reserve_Topography',None,None,None,45),
        ('03_visitor_hub','17_Reserve_Visitor_Hub',None,None,None,45),
        ('04_trailer_park','18_Reserve_Camp',None,None,None,45),
        ('05_cafe_composition','03_Cafe_Section','Main_cafe',None,None,45),
        ('06_home_composition','09_Home_Section','Main_home',None,None,45),
        amenity('07_trailer_family_interior','Reserve_Trailer_N01',(1,-1,18),True,45),
        amenity('08_trailer_twin_interior','Reserve_Trailer_N02',(1,-1,18),True,45),
        amenity('09_convenience_interior','Reserve_Convenience',(9,-13,12),True,48),
        amenity('10_souvenir_interior','Reserve_Souvenir',(8,-12,10),True,48),
        amenity('11_bathhouse_interior','Reserve_Bathhouse',(5,-7,24),True,48),
        amenity('12_public_toilets','Reserve_Public_Toilets',(3,-4,15),True,48),
        amenity('13_lunch_car','Reserve_Food_Truck',(8,-11,5),False,55),
    ]
    bridge=plan['bridges'][0];a,b=bridge['points_m'];mid=[(a[i]+b[i])/2 for i in range(3)]
    jobs.append(('14_ravine_bridge',None,None,(mid[0]+36,mid[1]-46,mid[2]+20),mid,42))
    stair=plan['stairs'][0];a,b=stair['points_m'];mid=[(a[i]+b[i])/2 for i in range(3)]
    # View the flight from its clear lower approach, beneath the forest canopy.
    dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
    stair_eye=(a[0]-dx/length*4,a[1]-dy/length*4,a[2]+1.8)
    stair_target=stair['flights'][2]['points_m'][-1]
    jobs.append(('15_stone_stairs',None,None,stair_eye,stair_target,28))
    if opt.only:
        selected=set(opt.only.split(','));jobs=[j for j in jobs if j[0] in selected]
        if len(jobs)!=len(selected):raise RuntimeError('Unknown review shot ID')
    review_lights=[]
    for ident,camera_name,cut,location,target,lens in jobs:
        for light in review_lights:light.hide_render=True
        scene.render.resolution_y=round(scene.render.resolution_x*.67)
        for name,flags in covers.items():
            c=bpy.data.collections[name];c.hide_render=flags[0];c.hide_viewport=flags[1]
        if cut:
            names=([reserve[cut]['roof_collection'],reserve[cut]['front_cover_collection']]
                   if cut in reserve else [cut+'_'+suffix for suffix in ('Roof','FrontWall','UpperFloorCover')])
            for name in names:
                c=bpy.data.collections[name];c.hide_render=True;c.hide_viewport=True
        if camera_name:
            camera=bpy.data.objects[camera_name]
        else:
            camera=bpy.data.objects.new('Review_'+ident,bpy.data.cameras.new('Review_'+ident))
            scene.collection.objects.link(camera)
            camera.location=location
            camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
            camera.data.lens=lens;camera.data.clip_end=2500
        if ident=='02_reserve_topography':
            # A square map frames the entire north/south extent rather than
            # cropping the running loop to the landscape beauty aspect ratio.
            scene.render.resolution_y=scene.render.resolution_x
            x0,y0,x1,y1=plan['terrain']['bounds_xyxy_m']
            camera=camera.copy();camera.data=camera.data.copy()
            camera.name='Review_02_Complete_Topography';scene.collection.objects.link(camera)
            camera.location=((x0+x1)/2,(y0+y1)/2,1000)
            camera.rotation_euler=(0,0,0)
            camera.data.type='ORTHO';camera.data.ortho_scale=max(x1-x0,y1-y0)*1.06
            camera.data.clip_end=2500
        if ident=='13_lunch_car':
            # A soft presentation fill reveals the service hatch beneath its
            # awning without changing the saved native lighting or materials.
            light_data=bpy.data.lights.new('Review_Lunch_Car_Fill','AREA')
            light_data.energy=1200;light_data.shape='DISK';light_data.size=5
            light_data.color=(1.,.94,.84)
            light=bpy.data.objects.new('Review_Lunch_Car_Fill',light_data)
            scene.collection.objects.link(light)
            light.location,light_target=pose('Reserve_Food_Truck',(0,-8,5),1.2)
            light.rotation_euler=(Vector(light_target)-light.location).to_track_quat('-Z','Y').to_euler()
            review_lights.append(light)
        scene.camera=camera
        filename=ident+('_preview' if opt.preview else '')+'.png'
        target_path=directory/filename;scene.render.filepath=str(target_path)
        started=time.perf_counter()
        print('RESERVE_RENDER_START',ident,flush=True)
        bpy.ops.render.render(write_still=True,scene=scene.name)
        with target_path.open('rb+') as handle:os.fsync(handle.fileno())
        record={'id':ident,'image':'renders/reserve_v6/'+filename,'source_blend_sha256':source_sha,
                'render_module_sha256':render_module_sha,
                'reserve_plan_sha256':scene.get('reserve_plan_sha256'),
                'interior_plan_sha256':scene.get('interior_plan_sha256'),
                'camera':camera.name,'cutaway_building':cut,'samples':scene.cycles.samples,
                'camera_location_blender_m':list(camera.location),'camera_rotation_euler_radians':list(camera.rotation_euler),
                'camera_type':camera.data.type,'camera_lens_mm':camera.data.lens,'camera_ortho_scale_m':camera.data.ortho_scale,
                'presentation_lights':[{'name':ob.name,'type':ob.data.type,'energy_w':ob.data.energy,
                                        'size_m':ob.data.size,'color':list(ob.data.color),'location_m':list(ob.location),
                                        'rotation_euler_radians':list(ob.rotation_euler)}
                                       for ob in review_lights if not ob.hide_render],
                'resolution':[scene.render.resolution_x,scene.render.resolution_y],
                'seconds':round(time.perf_counter()-started,3),
                'sha256':hashlib.sha256(target_path.read_bytes()).hexdigest()}
        records=[r for r in records if r['id']!=ident]+[record]
        evidence.write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
        print('RESERVE_RENDER_DONE',json.dumps(record),flush=True)
    if hashlib.sha256(source.read_bytes()).hexdigest()!=source_sha:
        raise RuntimeError('Native source changed while rendering')


if __name__=='__main__':main()
