"""Disposable full-town planting preview on an immutable architecture checkpoint."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);sys.modules[name]=value;spec.loader.exec_module(value);return value


p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--buildings',type=Path,required=True);p.add_argument('--library',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);a.output.mkdir(parents=True,exist_ok=True)
exp=load('botanical_preview_primitives',ROOT/'tools/town_generation/build_expansion_scene.py');botany=load('botanical_preview_factory',ROOT/'tools/town_upgrade/botany.py')
bpy.ops.wm.open_mainfile(filepath=str(a.input),load_ui=False);bpy.context.preferences.filepaths.save_version=0
rows=json.loads(a.buildings.read_text(encoding='utf-8'))['buildings']
api={'bpy':bpy,'collection':exp.collection,'buildings':rows,'expansion_dir':ROOT/'build/town_generation/territory_v6'}
report=botany.apply(api,a.sources,a.output,a.library)
for image in bpy.data.images:
    if image.source=='FILE' and not image.packed_file:image.pack()
native=a.output/'botanical_whole_town_preview.blend';bpy.ops.wm.save_as_mainfile(filepath=str(native),compress=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.resolution_x=1500;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
views={'inhabited_district':((165,-185,170),(-48,35,6),285),'reserve_edge':((-195,-190,75),(-210,-85,28),180)}
for name,(position,target,span) in views.items():
    cam_data=bpy.data.cameras.new('BotanicalPreview_'+name);cam=bpy.data.objects.new(cam_data.name,cam_data);scene.collection.objects.link(cam);cam.location=position;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.type='ORTHO';cam_data.ortho_scale=span;scene.camera=cam
    scene.render.filepath=str(a.output/(name+'.png'));print('GLOBAL_BOTANICAL_RENDER '+name,flush=True);bpy.ops.render.render(write_still=True)
print('GLOBAL_BOTANICAL_PREVIEW_COMPLETE '+str(report['tree_count']),flush=True)
