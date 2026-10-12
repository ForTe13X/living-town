"""Render saved native Blender scenes. CLI: blender -b FILE --python THIS -- study|town [preview]."""
import bpy,json,sys,hashlib,time,os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['town']
stage=args[0];preview='preview' in args
s=bpy.data.scenes['LT_Study' if stage=='study' else 'Living_Town_Summer']
bpy.context.window.scene=s
s.render.engine='CYCLES';s.cycles.samples=8 if preview else 64;s.cycles.use_denoising=True
s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG'
threads=int(next((a.split('=',1)[1] for a in args if a.startswith('threads=')),8))
s.render.threads_mode='FIXED';s.render.threads=threads;s.cycles.device='CPU'
jobs=[('study_exterior','Study_Exterior',None,'exterior'),('study_cutaway','Study_Cutaway','Study_Cafe','ground'),('study_restored','Study_Exterior',None,'exterior')] if stage=='study' else [
 ('01_town_overview','01_Town_Beauty',None,'exterior'),('02_cafe_street','02_Cafe_Street',None,'exterior'),
 ('03_cafe_cutaway','03_Cafe_Section','Main_cafe','ground'),('04_promenade','04_Promenade',None,'exterior'),
 ('05_harbor','05_Harbor',None,'exterior'),('06_orthogonal_plan','06_Production_Orthogonal',None,'exterior'),
 ('07_material_detail','07_Material_Closeup',None,'exterior'),
 ('08_home_section','09_Home_Section','Main_home','ground'),
 ('09_hotel_section','10_Hotel_Section',next(b['id'] for b in json.loads((ROOT/'town_manifest.json').read_text())['buildings'] if b['kind']=='hotel'),'ground'),
 ('10_library_section','11_Library_Section','Main_library','ground'),
 ('11_cafe_interior','12_Cafe_Interior',None,'interior'),
 ('12_cafe_upperfloor','13_Cafe_UpperFloor','Main_cafe','upper'),
 ('13_pond_park','14_Pond_Park',None,'exterior')]
only=next((a.split('=',1)[1].split(',') for a in args if a.startswith('only=')),None)
if only:jobs=[j for j in jobs if j[0] in only]
cover_names=[c.name for c in bpy.data.collections if c.name.endswith(('_Roof','_FrontWall','_UpperFloorCover'))]
initial={name:(bpy.data.collections[name].hide_render,bpy.data.collections[name].hide_viewport) for name in cover_names}
source_blend_sha256=hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
evidence_path=ROOT/'evidence'/('renders_'+stage+('_preview' if preview else '')+'.json')
record=[]
if ('resume' in args or only) and evidence_path.exists():
    for previous in json.loads(evidence_path.read_text(encoding='utf-8')):
        previous_path=ROOT/'renders'/previous['image']
        if previous.get('source_blend_sha256')==source_blend_sha256 and previous_path.is_file() and hashlib.sha256(previous_path.read_bytes()).hexdigest()==previous.get('sha256'):
            record.append(previous)
if only and 'resume' not in args:
    replaced={(name+'_preview' if preview else name)+'.png' for name,_,_,_ in jobs}
    record=[item for item in record if item['image'] not in replaced]
completed={item['image'] for item in record} if 'resume' in args else set()
override_path=ROOT/'presentation_camera_overrides.json'
overrides=json.loads(override_path.read_text(encoding='utf-8')) if override_path.is_file() and stage=='town' else {}
if overrides:assert overrides['source_blend_sha256']==source_blend_sha256,'Camera recipe binds another native source'
masterplan_sha256=s.get('masterplan_sha256')
for name,cam,prefix,mode in jobs:
    if (name+'_preview' if preview else name)+'.png' in completed:
        print('LT_RENDER_RESUME_SKIP',name,flush=True);continue
    for colname,flags in initial.items():
        col=bpy.data.collections[colname];col.hide_render=flags[0];col.hide_viewport=flags[1]
    cut=mode in ('ground','upper')
    if cut:
        for suffix in (('Roof','FrontWall','UpperFloorCover') if mode=='ground' else ('Roof','FrontWall')):
            col=bpy.data.collections[prefix+'_'+suffix];col.hide_render=True;col.hide_viewport=True
    s.camera=bpy.data.objects[cam]
    override=overrides.get('shots',{}).get(name)
    if override:
        assert override['camera']==cam
        s.camera.location=override['location_m']
        s.camera.rotation_euler=(Vector(override['target_m'])-s.camera.location).to_track_quat('-Z','Y').to_euler()
        s.camera.data.type='PERSP';s.camera.data.lens=override['lens_mm']
    s.render.resolution_x=1000 if preview else (2400 if stage=='town' and name in ('01_town_overview','06_orthogonal_plan') else 1800)
    s.render.resolution_y=int(s.render.resolution_x*(.67 if name!='06_orthogonal_plan' else .75))
    path=ROOT/'renders'/((name+'_preview' if preview else name)+'.png');s.render.filepath=str(path)
    t=time.time();bpy.ops.render.render(write_still=True,scene=s.name)
    with path.open('rb+') as stream:os.fsync(stream.fileno())
    record.append({'image':path.name,'camera':cam,'scene':s.name,'cutaway':cut,'section_mode':mode,'render_seconds':round(time.time()-t,2),'samples':s.cycles.samples,'resolution':[s.render.resolution_x,s.render.resolution_y],'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'roof_scope':prefix if cut else None,'source_blend_sha256':source_blend_sha256,'masterplan_sha256':masterplan_sha256,'terrain_plan_sha256':s.get('terrain_plan_sha256'),'terrain_profile_sha256':s.get('terrain_profile_sha256'),'interior_plan_sha256':s.get('interior_plan_sha256'),'interior_module_sha256':s.get('interior_module_sha256'),'landscape_plan_sha256':s.get('landscape_plan_sha256'),'landscape_details_sha256':s.get('landscape_details_sha256')})
    if override:
        record[-1]['presentation_camera_override']={'recipe':'presentation_camera_overrides.json',
            'recipe_sha256':hashlib.sha256(override_path.read_bytes()).hexdigest(),
            'location_m':override['location_m'],'target_m':override['target_m'],'lens_mm':override['lens_mm'],
            'native_file_saved':False}
    temporary=evidence_path.with_suffix('.tmp')
    with temporary.open('w',encoding='utf-8') as stream:
        json.dump(record,stream,indent=2);stream.flush();os.fsync(stream.fileno())
    temporary.replace(evidence_path)
for colname,flags in initial.items():
    col=bpy.data.collections[colname];col.hide_render=flags[0];col.hide_viewport=flags[1]
print('LT_RENDER_COMPLETE',stage,len(record),flush=True)
