"""Export immutable whole-town native geometry after its native audit passes.

The save and export are separate so visual review can precede the costly export.
This does not certify appearance, frame rate, character motion or gameplay.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import sys

import bpy

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('whole_town_export_recipe',Path(__file__).with_name('build_whole_town.py'))
recipe=importlib.util.module_from_spec(spec);spec.loader.exec_module(recipe)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);path=args.manifest.resolve(strict=True);folder=path.parent
    manifest=json.loads(path.read_text(encoding='utf-8'));native=folder/manifest['native']['path']
    if manifest['native_geometry_status']!='PASS':raise ValueError('Native geometry is not accepted')
    audit_path=folder/'whole_town_native_geometry.json';audit=json.loads(audit_path.read_text(encoding='utf-8'))
    native_hash=recipe.sha(native)
    if audit['status']!='PASS' or audit['saved_native_sha256']!=native_hash or manifest['source_blend_sha256']!=native_hash or manifest['native']['sha256']!=native_hash:raise ValueError('Native/audit identity mismatch')
    if recipe.sha(audit_path)!=manifest['native_geometry_receipt_sha256']:raise ValueError('Changed native audit receipt')
    if recipe.sha(folder/'whole_town_buildings.json')!=audit['building_records_sha256']:raise ValueError('Changed native building records')
    for relative,binding in manifest['recipe_bindings'].items():
        if recipe.sha(ROOT/relative)!=binding['sha256']:raise ValueError('Source recipe changed after native build: '+relative)
    if manifest['assets'] or (folder/'chunks').exists():raise FileExistsError('Use a native candidate with no previous/partial chunks')
    bpy.ops.wm.open_mainfile(filepath=str(native),load_ui=False)
    manifest['assets']=recipe.export_chunks(folder,manifest['buildings'])
    export_receipt=json.loads((folder/'portable_export_receipt.json').read_text(encoding='utf-8'))
    exporter=recipe.module('whole_town_export_source_verifier',Path(__file__).with_name('portable_export.py'))
    exporter.verify_sources(export_receipt['export_sources'])
    if export_receipt['status']!='PASS':raise ValueError('Portable export receipt did not pass')
    manifest['export_recipe']={'path':str(Path(__file__).relative_to(ROOT)),'sha256':recipe.sha(__file__),
                               'native_sha256':native_hash,'engine':bpy.app.version_string,'threads':6,
                               'portable_curve_receipt_sha256':recipe.sha(folder/'portable_curve_meshing.json'),
                               'portable_export_receipt_sha256':recipe.sha(folder/'portable_export_receipt.json'),
                               'export_sources':export_receipt['export_sources']}
    if recipe.sha(native)!=native_hash:raise RuntimeError('Export modified immutable native source')
    exporter.verify_sources(export_receipt['export_sources'])
    temporary=path.with_suffix('.json.tmp');recipe.write(temporary,manifest);temporary.replace(path)
    print('WHOLE_TOWN_PORTABLE_EXPORT_FINISHED '+json.dumps({'chunks':len(manifest['assets']),'bytes':sum(a['bytes'] for a in manifest['assets']),'native_sha256':native_hash}),flush=True)


if __name__=='__main__':main()
