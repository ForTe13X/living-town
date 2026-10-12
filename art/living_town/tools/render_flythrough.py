"""Render the editable 10-second coastal camera path to PNG frames.

CLI: blender -b living_town_complete.blend --python tools/render_flythrough.py
Then ffmpeg -framerate 24 -i renders/flythrough_frames/%04d.png -c:v libx264 -crf 20 -pix_fmt yuv420p renders/coastal_flythrough.mp4
The native file is never saved or changed by this renderer.
"""
from pathlib import Path
import bpy
import hashlib
import json
import time
import os
import sys

ROOT=Path(__file__).resolve().parents[1]
scene=bpy.data.scenes['Living_Town_Summer'];bpy.context.window.scene=scene
scene.camera=bpy.data.objects['08_Coastal_Flythrough']
scene.render.engine='BLENDER_EEVEE'
scene.render.threads_mode='FIXED';scene.render.threads=8
if hasattr(scene.eevee,'taa_render_samples'):scene.eevee.taa_render_samples=32
scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.fps=24
scene.frame_start=1;scene.frame_end=240;scene.frame_step=1
frames=ROOT/'renders/flythrough_frames';frames.mkdir(parents=True,exist_ok=True)
scene.render.filepath=str(frames)+'/'
for c in bpy.data.collections:
    if c.name.endswith(('_Roof','_FrontWall','_UpperFloorCover')):c.hide_render=False
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
start=time.time()
if 'probe' in args:
    probes=[]
    for frame in (1,80,160,240):
        scene.frame_set(frame)
        path=ROOT/'evidence'/f'flythrough_probe_{frame:04d}.png'
        scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True,scene=scene.name)
        with path.open('rb+') as stream:os.fsync(stream.fileno())
        probes.append({'frame':frame,'image':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    record={'scope':'Four actual native camera-path key frames; read-only probe before full animation.',
            'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
            'renderer':scene.render.engine,'resolution':[1280,720],
            'render_seconds':round(time.time()-start,2),'probes':probes}
    record_path=ROOT/'evidence/flythrough_probe.json'
    temporary=record_path.with_suffix('.tmp')
    with temporary.open('w',encoding='utf-8') as stream:
        json.dump(record,stream,indent=2);stream.flush();os.fsync(stream.fileno())
    temporary.replace(record_path)
    print('LT_FLYTHROUGH_PROBE_COMPLETE',json.dumps(record),flush=True)
else:
    bpy.ops.render.render(animation=True,scene=scene.name)
    record={'camera':scene.camera.name,'renderer':scene.render.engine,'frames':240,'fps':24,'seconds':10,
            'cpu_thread_limit':8,
            'resolution':[1280,720],'render_seconds':round(time.time()-start,2),
            'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
            'masterplan_sha256':scene.get('masterplan_sha256'),'terrain_plan_sha256':scene.get('terrain_plan_sha256'),
            'terrain_profile_sha256':scene.get('terrain_profile_sha256'),
            'landscape_plan_sha256':scene.get('landscape_plan_sha256'),'landscape_details_sha256':scene.get('landscape_details_sha256'),
            'interior_plan_sha256':scene.get('interior_plan_sha256'),'interior_module_sha256':scene.get('interior_module_sha256'),
            'video':'renders/coastal_flythrough.mp4','frame_directory':'renders/flythrough_frames'}
    record_path=ROOT/'evidence/flythrough_render.json'
    temporary=record_path.with_suffix('.tmp')
    with temporary.open('w',encoding='utf-8') as stream:
        json.dump(record,stream,indent=2);stream.flush();os.fsync(stream.fileno())
    temporary.replace(record_path)
    print('LT_FLYTHROUGH_COMPLETE',json.dumps(record),flush=True)
