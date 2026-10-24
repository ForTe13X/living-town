"""Single-engine whole-town upgrade, packed native source and portable chunks.

Inputs are immutable previous native/plan artifacts. Every output is confined
to a fresh directory; failed geometry remains inspectable and is never stamped
as accepted. Root coordinates rendering, characters and gameplay separately.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

import bpy

ROOT=Path(__file__).resolve().parents[2]
NATIVE_RECIPE_MODULES=('architecture_upgrade.py','building_native_audit.py','interior_decoration.py',
    'botany.py','understory.py','botanical_source_lods.py','canopy_coverage.py','scale_figures.py',
    'terrain_finish.py','terrain_atlas.py','terrain_cache.py','granular_details.py','natural_surface_details.py')


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);sys.modules[name]=result;spec.loader.exec_module(result);return result


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def write(path,value):path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def export_chunks(output,rows):
    exporter=module('whole_town_export_only_recipe',Path(__file__).with_name('portable_export.py'))
    return exporter.export_chunks(bpy,output,rows)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--expansion-dir',type=Path,default=ROOT/'build/town_generation/territory_v6')
    parser.add_argument('--pbr-library',type=Path,default=ROOT/'art/living_town/refinement_pilot/scanned_pbr_v3/library_manifest.json')
    parser.add_argument('--botanical-library',type=Path);parser.add_argument('--sources',type=Path)
    parser.add_argument('--terrain-sources',type=Path);parser.add_argument('--texture-python',type=Path)
    parser.add_argument('--terrain-atlas-cache',type=Path,help='Optional completed terrain_materials folder; exact guide, scan, tool and PNG hashes must match.')
    parser.add_argument('--skip-export',action='store_true');parser.add_argument('--skip-vegetation',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);start=time.time()
    if args.terrain_atlas_cache and not args.terrain_sources:parser.error('--terrain-atlas-cache requires --terrain-sources')
    # Blender resolves image paths against the opened blend, whereas Python
    # file reads use the invocation directory. Pin all inputs before loading
    # a scene so a documented repository-relative command has one meaning.
    for name in ('expansion_dir','pbr_library','botanical_library','sources','terrain_sources','texture_python','terrain_atlas_cache'):
        value=getattr(args,name)
        if value is not None:setattr(args,name,value.resolve(strict=True))
    args.input=args.input.resolve(strict=True);args.output=args.output.resolve()
    if args.output.exists():raise FileExistsError('Use a fresh output directory: '+str(args.output))
    if args.input.is_relative_to(args.output):raise ValueError('Output may not contain the input')
    args.output.mkdir(parents=True);input_hash=sha(args.input);baseline=ROOT/'art/living_town';canonical_hash=sha(baseline/'living_town_complete.blend')
    expansion=module('whole_town_expansion_primitives',ROOT/'tools/town_generation/build_expansion_scene.py')
    architecture=module('whole_town_architecture',ROOT/'tools/town_upgrade/architecture_upgrade.py')
    native_audit=module('whole_town_native_auditor',ROOT/'tools/town_upgrade/building_native_audit.py')
    bpy.ops.wm.open_mainfile(filepath=str(args.input),load_ui=False);bpy.context.preferences.filepaths.save_version=0
    material_report=expansion.materials(args.pbr_library,args.output)
    api={'bpy':bpy,'Batch':expansion.Batch,'MATS':expansion.MATS,'collection':expansion.collection,'module':module,'sha':sha}
    figure_receipt=module('whole_town_scale_figure_cleanup',ROOT/'tools/town_upgrade/scale_figures.py').apply(api,args.output)
    if figure_receipt['status']=='REJECTED_NO_MUTATIONS':raise RuntimeError('Static scale figures no longer match their exact source primitives')
    print('WHOLE_TOWN_ARCHITECTURE_BEGIN',flush=True)
    result=architecture.upgrade(api,baseline,args.expansion_dir,args.output)
    botanical=None;terrain_finish=None
    if not args.skip_vegetation:
        if not args.botanical_library or not args.sources:raise ValueError('Supply accepted botanical library/source receipts')
        botany=module('whole_town_botanical_upgrade',ROOT/'tools/town_upgrade/botany.py')
        api.update({'buildings':result['buildings'],'expansion_dir':args.expansion_dir,
                    'understory_triangle_budget':24_000_000,'understory_max_instances':26000})
        botanical=botany.apply(api,args.sources,args.output,args.botanical_library)
    if args.terrain_sources:
        if botanical is None or args.texture_python is None:raise ValueError('Terrain finish requires botanical placements and --texture-python')
        terrain_finish=module('whole_town_terrain_finish',ROOT/'tools/town_upgrade/terrain_finish.py').apply(api,args.terrain_sources,args.output,botanical,args.texture_python,atlas_cache=args.terrain_atlas_cache)
    natural_details=None
    if botanical is not None:
        natural_details=module('whole_town_natural_surface_details',ROOT/'tools/town_upgrade/natural_surface_details.py').apply(api,args.output,botanical)
    granular_details=module('whole_town_granular_details',ROOT/'tools/town_upgrade/granular_details.py').apply(
        api,args.output,result['buildings'],result['source_furniture_geometry'])
    # Final geometry/furniture proof covers the actual detailed scene, rather
    # than the earlier pre-botanical architecture checkpoint.
    print('WHOLE_TOWN_NATIVE_AUDIT_BEGIN',flush=True)
    geometry=native_audit.audit(api,result['buildings'],args.output/'whole_town_native_geometry.json',source_furniture=result['source_furniture_geometry'])
    print('WHOLE_TOWN_NATIVE_AUDIT '+geometry['status'],flush=True)
    for image in bpy.data.images:
        if image.source=='FILE' and not image.packed_file:image.pack()
    native=args.output/'refined_whole_town.blend';bpy.ops.wm.save_as_mainfile(filepath=str(native),compress=True)
    geometry['saved_native_sha256']=sha(native)
    geometry['saved_native_path']=str(native)
    geometry['building_records_sha256']=sha(args.output/'whole_town_buildings.json')
    write(args.output/'whole_town_native_geometry.json',geometry)
    assets=export_chunks(args.output,result['buildings']) if not args.skip_export and geometry['status']=='PASS' else []
    manifest={'schema':'living_town.whole_town_upgrade.v1','status':'BUILT_REQUIRES_VISUAL_AND_GAMEPLAY_REVIEW' if geometry['status']=='PASS' else 'NATIVE_GEOMETRY_FAILED',
        'source_blend_sha256':sha(native),'native':{'path':native.name,'sha256':sha(native),'bytes':native.stat().st_size},
        'input':{'path':str(args.input),'sha256':input_hash},'buildings':result['buildings'],'interiors':{'buildings':result['interiors']},
        'assets':assets,'removed_baseline_object_names':[],'materials':material_report,
        'native_geometry_status':geometry['status'],'botanical_report':'botanical_report.json' if botanical else None,
        'scale_figure_cleanup_receipt_sha256':sha(args.output/'scale_figure_removal_receipt.json'),
        'terrain_finish_receipt_sha256':sha(args.output/'terrain_finish_receipt.json') if terrain_finish else None,
        'granular_details_receipt_sha256':sha(args.output/'granular_details_receipt.json'),
        'natural_surface_details_receipt_sha256':sha(args.output/'natural_surface_details_receipt.json') if natural_details else None,
        'native_geometry_receipt_sha256':sha(args.output/'whole_town_native_geometry.json'),
        'counts':{key:result['manifest'][key] for key in ('building_count','floor_count','room_count','furnishing_count','window_aperture_count')},'elapsed_seconds':round(time.time()-start,2),
        'recipe_bindings':{path.relative_to(ROOT).as_posix():{'sha256':sha(path)} for path in
            [Path(__file__)]+[Path(__file__).with_name(name) for name in NATIVE_RECIPE_MODULES]},
        'botanical_library':{'path':str(args.botanical_library),'sha256':sha(args.botanical_library)} if args.botanical_library else None,
        'engine':{'version':bpy.app.version_string,'threads':6,'render_device':'CPU'},
        'limits':['Native geometry, visual acceptance, performance and actual gameplay are distinct required checks.','No canonical authoring source is overwritten.']}
    write(args.output/'upgrade_manifest.json',manifest)
    if sha(args.input)!=input_hash or sha(baseline/'living_town_complete.blend')!=canonical_hash:raise RuntimeError('Immutable source changed')
    print('WHOLE_TOWN_BUILD_FINISHED '+json.dumps({'status':manifest['status'],'native':str(native),'geometry':geometry['status'],'assets':len(assets)}),flush=True)


if __name__=='__main__':main()
