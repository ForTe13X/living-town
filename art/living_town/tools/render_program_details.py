"""Read-only native asset QA plates for fitted kitchen, dining seating and mill.

Run in a separate Blender CLI process after the source is frozen. Temporary
camera/stage and visibility changes are never saved into the native model.
"""
from pathlib import Path
import bpy, hashlib, json, math, os
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
scene=bpy.data.scenes['Living_Town_Summer'];bpy.context.window.scene=scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=32
scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=8
scene.render.resolution_x=1200;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
source_sha=hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
manifest=json.loads((ROOT/'town_manifest.json').read_text())
plan=json.loads((ROOT/'interior_plan.json').read_text())
placements={b['id']:b for b in manifest['buildings']}
jobs=[('kitchen_fixture_detail','Main_cafe','private owner kitchenette','kitchen_run'),
      ('dining_seating_detail','Main_cafe','private owner kitchenette','dining_table'),
      ('mill_mechanism_detail',next(b['id'] for b in plan['buildings'] if b['kind']=='windmill'),'grain milling equipment','mill_mechanism')]
original_visibility={o.name:o.hide_render for o in scene.objects}
records=[]
for name,ident,purpose,kind in jobs:
    building=next(b for b in plan['buildings'] if b['id']==ident)
    level,room=next((f,r) for f in building['levels'] for r in f['rooms'] if r['purpose']==purpose)
    asset=next(a for a in room['assets'] if a['kind']==kind or (kind=='dining_table' and a['kind'].startswith('dining_table')))
    meshes=[o for o in scene.objects if o.type=='MESH' and o.get('interior_asset_id')==asset['id']]
    assert meshes,asset['id']
    for o in scene.objects:o.hide_render=not (o in meshes or (o.type=='LIGHT' and (o.data.type=='SUN' or room['id'] in o.name)))
    placement=placements[ident];yaw=math.radians(placement.get('yaw_degrees',0));origin=placement['center_m']
    x,y=asset['center_m'];center=Vector((origin[0]+x*math.cos(yaw)-y*math.sin(yaw),origin[1]+x*math.sin(yaw)+y*math.cos(yaw),origin[2]+.38+level['level']*2.85))
    angle=yaw+math.radians(asset['rotation_degrees'])
    def offset(x,y,z):return center+Vector((x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle),z))
    cam_data=bpy.data.cameras.new('QA_'+name);cam=bpy.data.objects.new('QA_'+name,cam_data);scene.collection.objects.link(cam)
    cam.location=offset(2.7,-3.5,2.9);target=center+Vector((0,0,.65));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO';cam_data.ortho_scale=max(2.4,max(asset['dimensions_m'][:2])*1.6);scene.camera=cam
    bpy.ops.mesh.primitive_plane_add(size=12,location=center-Vector((0,0,.015)))
    stage=bpy.context.object;stage.name='QA_temporary_stage'
    material=bpy.data.materials.new('QA_stage_neutral');material.diffuse_color=(.32,.35,.32,1);material.use_nodes=True
    material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.32,.35,.32,1)
    material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.85;stage.data.materials.append(material)
    path=ROOT/'evidence'/(name+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True,scene=scene.name)
    with path.open('rb+') as stream:os.fsync(stream.fileno())
    records.append({'image':path.name,'source_blend_sha256':source_sha,'interior_plan_sha256':scene.get('interior_plan_sha256'),'asset_id':asset['id'],'role':asset['kind'],'mesh_objects':len(meshes),'resolution':[1200,1000],'samples':32,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'scope':'Actual native fixture meshes isolated on a temporary neutral QA stage; native file not saved.'})
    bpy.data.objects.remove(stage,do_unlink=True);bpy.data.objects.remove(cam,do_unlink=True)
for name,hidden in original_visibility.items():bpy.data.objects[name].hide_render=hidden
record_path=ROOT/'evidence/program_detail_renders.json';temporary=record_path.with_suffix('.tmp')
with temporary.open('w',encoding='utf-8') as stream:
    json.dump(records,stream,indent=2);stream.flush();os.fsync(stream.fileno())
temporary.replace(record_path)
print('LT_PROGRAM_DETAIL_COMPLETE',len(records),flush=True)
