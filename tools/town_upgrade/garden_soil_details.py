"""One source-bound garden-soil material pilot; engine-free on import.

prepare_maps() makes a separately provenanced dark-earth variant of an existing
CC0 scan. apply(api, output, prepared) changes only the single material slot of
Reference_Pocket_Gardens_Dirt, preserving all geometry, UV bytes and other
objects/materials. The owner opens an immutable V14 or verified entry derivative.
prepare/apply never load/save/export a scene. An explicit owner-run pilot audits
and COPY-saves a fresh native. Actual Blender/Godot A/B remains pending.
"""
from __future__ import annotations
from collections import Counter
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys
from types import FunctionType

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path: sys.path.insert(0, str(ROOT))
from tools.town_upgrade import entry_details as E
TARGET = 'Reference_Pocket_Gardens_Dirt'
MATERIAL = 'GardenSoil_LeafLitter_DarkEarth_Pilot'
SCHEMA = 'living_town.source_bound_garden_soil.v1'
ASSET = 'forest_leaves_02'
RECEIPT_SHA256 = 'e2515e5530e1a367384084856796e74b1e6e00b27d949e4e3150bd5e831f2073'
# Actual entry-v15-002 all-preserved baseline, measured before/after its scoped
# application. Its later CLI audit-wrapper failure did not alter these states.
SOIL_NATIVE_STATE_SHA256 = 'b26092090bc65cfd765fa0edb0b2ca5206795698d4e0eb14ecd671485bbb1b2e'
DIRT_MATERIAL_STATE_SHA256 = '1ed2b04d1e23000a2f21ebad7e7f36b380e6b53f627e0c9817c56d79d50eb974'
DIRT_CANONICAL_SHA256 = 'fde572a94140528383b77384f11579d2ef7f612be2034d8447f230d1d5850592'
# Replaced only with the owner-measured original V14 baseline after capture.
MATERIAL_BASELINE_SHA256 = '05ad3ae485c655ad6e150f2a9f7e535f2ebb4d266fdbe0a1adc50db8fc9dc0ad'
MATERIAL_EXCLUDED_FIELDS = ['/settings/session_uid']
UNUSED_MATERIAL_PROOF_SHA256 = '36fa60c89ea3157a7f168c92c5056c0d5c1e1a58b0e357e87c4881b7b3a92789'
SAVE_ORPHAN_ENTRY_SHA256 = 'b550a160dede21d339ccb195339d13c631202e600b352d2f04d6be9f526b752c'
SAVE_ORPHAN_MATERIALS = ['LT_Hair', 'LT_Shirt', 'LT_Skin', 'LT_Trousers']
FACTORY_SHA256 = '284459e0383e5d4adf0e3c9ddc637bc29cf375152c8724856546d0596e25e5d8'
PLAN_SHA256 = '68b8f4d2a9269b1fa8e9dde530bc83bd41b871effaf4d224ffd12ab953f6d4b1'
LINEAR_RGB_FACTORS = (.55, .43, .32)
SATURATION = .60
MAP_FILES = {'diff': '9c38b2b151a0415457a6914966422cfca5a546c94674442e5395e0b1e908a196',
             'nor_gl': 'af0346114834c347a8d6a138f6ea16a97b0bec8d6e4db32c24f1c7e482163235',
             'arm': 'd8423b522d86285e26036d27fc51f4db7b8c6716b1558deb4575b288e14c28b7'}


def sha(path):
    with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, value):
    path = Path(path); temporary = path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8'); temporary.replace(path)


def canonical_material_state(state):
    """Remove exactly the root Material ID's process-local UID, no other field."""
    result = deepcopy(state); uid = result['settings'].pop('session_uid')
    if type(uid) is not int or uid <= 0: raise ValueError('Missing root Material session_uid')
    return result, uid


def material_inventory(bpy):
    # Execute the exact frozen E recipe with a private globals mapping. E and
    # bpy are never monkey-patched; only this copy returns structured states.
    capture = FunctionType(E._materials.__code__, {**E._materials.__globals__, '_digest': lambda state: state})
    states = capture(bpy); raw, canonical, uids = {}, {}, {}
    for name, state in states.items():
        clean, uid = canonical_material_state(state)
        raw[name], canonical[name], uids[name] = E._digest(state), E._digest(clean), uid
    if raw != E._materials(bpy): raise ValueError('Structured material capture differs from frozen raw recipe')
    return {'raw': raw, 'canonical': canonical, 'session_uid': uids}


def verify_material_baseline(path):
    if not MATERIAL_BASELINE_SHA256 or sha(path) != MATERIAL_BASELINE_SHA256: raise ValueError('Original canonical material baseline changed/unbound')
    data = read(path)
    if data.get('schema') != 'living_town.garden_original_material_baseline.v1' or data.get('status') != 'ACTUAL_ORIGINAL_V14_CANONICAL_MATERIALS_CAPTURED': raise ValueError('Original canonical material capture missing')
    if data['native']['sha256'] != E.NATIVE_SHA256 or data['entry_material_recipe_sha256'] != sha(E.__file__) or data['excluded_root_material_fields'] != MATERIAL_EXCLUDED_FIELDS: raise ValueError('Canonical baseline source/field exclusion differs')
    values = data['canonical_material_state_sha256']
    if data['material_count'] != 137 or len(values) != 137 or E._digest(values) != data['canonical_inventory_sha256'] or values['LT_Dirt'] != DIRT_CANONICAL_SHA256: raise ValueError('Original canonical137-material inventory differs')
    if set(values) != set(data['original_session_raw_material_state_sha256']) or set(values) != set(data['original_session_uid']) or data['source_soil_mesh_sha256'] != SOIL_NATIVE_STATE_SHA256: raise ValueError('Original material capture incomplete')
    if data['scene_saved'] or data['material_modified'] or data['art_pass']: raise ValueError('Canonical capture has unexpected mutation/review claims')
    return data


def baseline_record(path, baseline):
    return {'path': str(Path(path).resolve()), 'sha256': MATERIAL_BASELINE_SHA256,
            'native_sha256': baseline['native']['sha256'], 'canonical_inventory_sha256': baseline['canonical_inventory_sha256'],
            'canonical_material_state_sha256': baseline['canonical_material_state_sha256'],
            'excluded_root_material_fields': MATERIAL_EXCLUDED_FIELDS, 'entry_material_recipe_sha256': baseline['entry_material_recipe_sha256'],
            'capture_helper_sha256': baseline['capture_helper_sha256']}


def verify_unused_proof(path, baseline):
    if sha(path) != UNUSED_MATERIAL_PROOF_SHA256: raise ValueError('Exact unused-material usage proof changed')
    proof = read(path); original, entry = proof['original'], proof['entry']; full = baseline['canonical_material_state_sha256']
    expected = {n: v for n, v in full.items() if n not in SAVE_ORPHAN_MATERIALS}
    if proof['schema'] != 'living_town.garden_unused_material_roundtrip.v1' or proof['status'] != 'PASS_EXACT_UNUSED_MATERIAL_SAVE_ROUNDTRIP' or original['sha256'] != E.NATIVE_SHA256 or entry['sha256'] != SAVE_ORPHAN_ENTRY_SHA256 or proof['entry_tool_sha256'] != sha(E.__file__): raise ValueError('Unused material proof source identity differs')
    if proof['missing_materials'] != SAVE_ORPHAN_MATERIALS or proof['added_materials'] or proof['changed_common_canonical_materials'] or proof['canonical_excluded_fields'] != MATERIAL_EXCLUDED_FIELDS or proof['original_materials_have_zero_users_and_no_owners'] is not True: raise ValueError('Unused material exception scope differs')
    if original['material_count'] != 137 or entry['material_count'] != 133 or original['inventory']['canonical'] != full or entry['inventory']['canonical'] != expected: raise ValueError('Unused material proof canonical inventories differ')
    if set(original['selected_material_usage']) != set(SAVE_ORPHAN_MATERIALS) or set(entry['selected_material_usage']) != set(SAVE_ORPHAN_MATERIALS): raise ValueError('Unused material usage records incomplete')
    for name in SAVE_ORPHAN_MATERIALS:
        row = original['selected_material_usage'][name]
        if row != {'present': True, 'users': 0, 'use_fake_user': False, 'asset_marked': False, 'mesh_owners': [], 'curve_owners': [], 'object_owners': [], 'canonical_sha256': full[name]} or entry['selected_material_usage'][name] != {'present': False}: raise ValueError('Material is not an exact measured unowned save orphan: '+name)
    if proof['scene_saved'] or proof['material_modified'] or proof['art_pass']: raise ValueError('Usage proof claims mutation/review')
    return proof


def contract_expected_inventory(chain, maps):
    full = maps['material_baseline']['canonical_material_state_sha256']
    if chain['kind'] == 'IMMUTABLE_V14' and chain['sha256'] == E.NATIVE_SHA256: return full
    if chain['kind'] == 'VERIFIED_ENTRY_DERIVATIVE' and chain['sha256'] == SAVE_ORPHAN_ENTRY_SHA256:
        return {name: value for name, value in full.items() if name not in SAVE_ORPHAN_MATERIALS}
    raise ValueError('No measured material lifecycle contract for this exact input native')


def verify_sources(sources, receipt_sha=RECEIPT_SHA256):
    sources = Path(sources).resolve(); receipt = sources/'source_receipts.json'
    if sha(receipt) != receipt_sha: raise ValueError('CC0 soil source receipt changed')
    record = read(receipt)
    if record.get('schema') != 'living_town.terrain_sources.v1' or record.get('license') != 'CC0-1.0' or record.get('license_url') != 'https://polyhaven.com/license':
        raise ValueError('Verified CC0 soil source license missing/different')
    asset = record['assets'].get(ASSET, {})
    if asset.get('asset_url') != 'https://polyhaven.com/a/'+ASSET: raise ValueError('Soil asset identity changed')
    repeat = [v/1000 for v in asset.get('dimensions_mm', [])]
    if len(repeat) != 2 or any(not math.isfinite(v) or not 3.0 <= v <= 3.002 for v in repeat): raise ValueError('Soil physical dimensions changed')
    rows = {}
    for role, expected in MAP_FILES.items():
        matches = [r for r in record['files'] if r['path'] == ASSET+'/'+role+'.jpg']
        if len(matches) != 1: raise ValueError('Soil map receipt not unique: '+role)
        row = matches[0]; path = sources/row['path']
        if row['sha256'] != expected or sha(path) != expected or path.stat().st_size != row['bytes']:
            raise ValueError('Actual CC0 soil map changed: '+role)
        rows[role] = {**row, 'absolute_path': str(path)}
    for name, expected in asset['metadata_sha256'].items():
        if sha(sources/(ASSET+'_'+name+'.json')) != expected: raise ValueError('Soil physical/source metadata changed')
    return {'root': str(sources), 'receipt_sha256': receipt_sha, 'asset_id': ASSET, 'repeat_metres': repeat,
            'license': 'CC0-1.0', 'license_url': record['license_url'], 'asset_url': asset['asset_url'], 'maps': rows}


def _linear(v): return v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4
def _srgb(v): return 12.92*v if v <= .0031308 else 1.055*v**(1/2.4)-.055


def grade_pixel(r, g, b):
    linear = [_linear(v) for v in (r, g, b)]; luma = sum(v*w for v, w in zip(linear, (.2126, .7152, .0722)))
    return tuple(_srgb(max(0., min(1., (luma+(v-luma)*SATURATION)*factor)))
                 for v, factor in zip(linear, LINEAR_RGB_FACTORS))


def grade_diffuse(image):
    from PIL import ImageFilter
    return image.convert('RGB').filter(ImageFilter.Color3DLUT.generate(33, grade_pixel))


def _mean_linear_luma(image):
    channels = image.convert('RGB').split(); count = image.width*image.height
    return sum(sum(n*_linear(i/255) for i, n in enumerate(c.histogram()))/count*w
               for c, w in zip(channels, (.2126, .7152, .0722)))


def prepare_maps(sources, output, material_baseline, unused_material_proof):
    """Host texture preparation only: original licensed source maps never edited."""
    from PIL import Image, ImageStat
    source = verify_sources(sources); origin = source; output = Path(output).resolve()
    baseline = verify_material_baseline(material_baseline)
    usage = verify_unused_proof(unused_material_proof, baseline)
    if output.exists(): raise FileExistsError('Prepare soil maps in a fresh directory')
    with Image.open(source['maps']['diff']['absolute_path']) as original:
        original = original.convert('RGB')
        if original.size != (2048, 2048): raise ValueError('Expected original verified 2K soil diffuse')
        derived = grade_diffuse(original)
        stats = {'source_mean_linear_luminance': _mean_linear_luma(original),
                 'derived_mean_linear_luminance': _mean_linear_luma(derived),
                 'source_grayscale_standard_deviation': ImageStat.Stat(original.convert('L')).stddev[0],
                 'derived_grayscale_standard_deviation': ImageStat.Stat(derived.convert('L')).stddev[0]}
    if not .15 < stats['derived_mean_linear_luminance']/stats['source_mean_linear_luminance'] < .75 or stats['derived_grayscale_standard_deviation'] < 4:
        raise ValueError('Soil grade lost useful luminance/grain; no scene applied')
    output.mkdir(parents=True, exist_ok=False)
    # A self-contained selected-source archive: the original full receipt is
    # retained verbatim; only the explicitly selected forest asset is copied.
    # This does not claim the other terrain assets in that receipt are present.
    archive = output/'provenance'; (archive/ASSET).mkdir(parents=True)
    shutil.copyfile(Path(sources)/'source_receipts.json', archive/'source_receipts.json')
    for role in MAP_FILES: shutil.copyfile(source['maps'][role]['absolute_path'], archive/ASSET/(role+'.jpg'))
    for name in ('info', 'files'): shutil.copyfile(Path(sources)/(ASSET+'_'+name+'.json'), archive/(ASSET+'_'+name+'.json'))
    shutil.copyfile(material_baseline, archive/'garden_original_material_baseline.json')
    verify_material_baseline(archive/'garden_original_material_baseline.json')
    capture_helper = ROOT/'build/town_upgrade/staging/capture_garden_material_baseline.py'
    if sha(capture_helper) != baseline['capture_helper_sha256']: raise ValueError('Actual canonical capture helper source changed')
    shutil.copyfile(capture_helper, archive/'capture_garden_material_baseline.py')
    shutil.copyfile(unused_material_proof, archive/'garden_unused_material_roundtrip.json')
    usage_helper = ROOT/'build/town_upgrade/diagnose_garden_orphan_materials.py'
    if sha(usage_helper) != usage['helper_sha256']: raise ValueError('Usage proof helper source changed')
    shutil.copyfile(usage_helper, archive/'diagnose_garden_orphan_materials.py')
    source = verify_sources(archive)
    path = output/'garden_soil_dark_earth_diff.png'; derived.save(path, compress_level=6)
    maps = {'diff': {'path': str(path), 'sha256': sha(path), 'bytes': path.stat().st_size, 'role': 'sRGB diffuse'}}
    for role in ('nor_gl', 'arm'):
        row = source['maps'][role]
        maps[role] = {'path': row['absolute_path'], 'sha256': row['sha256'], 'bytes': row['bytes'], 'role': 'Non-Color '+role}
    report = {'schema': 'living_town.garden_soil_prepared_maps.v1', 'status': 'PREPARED_REQUIRES_ACTUAL_AB_REVIEW',
              'tool_sha256': sha(__file__), 'source': source, 'maps': maps, 'dimensions': [2048, 2048],
              'selected_source_archive': {'original_root': origin['root'], 'path': str(archive), 'source_receipt_verbatim': True,
                                          'selected_asset_only': ASSET, 'unrelated_receipt_assets_not_copied_or_claimed': True},
              'grade': {'linear_rgb_factors': LINEAR_RGB_FACTORS, 'saturation': SATURATION, 'lut_size': 33,
                        'intent': 'Modest dark brown soil with retained photographed leaves/grain; not uniform black disks'},
              'statistics': stats, 'source_images_modified': False, 'art_pass': False}
    report['material_baseline'] = baseline_record(archive/'garden_original_material_baseline.json', baseline)
    report['unused_material_roundtrip'] = {'path': str(archive/'garden_unused_material_roundtrip.json'), 'sha256': UNUSED_MATERIAL_PROOF_SHA256,
        'original_native_sha256': E.NATIVE_SHA256, 'entry_native_sha256': SAVE_ORPHAN_ENTRY_SHA256, 'missing_materials': SAVE_ORPHAN_MATERIALS, 'helper_sha256': usage['helper_sha256']}
    verify_sources(sources); write(output/'garden_soil_maps.json', report); return report


def measured_uv_transform(samples, physical_repeat):
    """Fit UV0 to actual world XY, retaining bytes and compensating material scale."""
    if len(samples) < 6: raise ValueError('Insufficient actual soil UV/world samples')
    means = [sum(s[k] for s in samples)/len(samples) for k in range(4)]
    centered = [[s[k]-means[k] for k in range(4)] for s in samples]
    xx = sum(s[0]*s[0] for s in centered); xy = sum(s[0]*s[1] for s in centered); yy = sum(s[1]*s[1] for s in centered); det = xx*yy-xy*xy
    if det <= 1e-12: raise ValueError('Degenerate soil UV/world fit')
    coefficients = []
    for channel in (2, 3):
        xu = sum(s[0]*s[channel] for s in centered); yu = sum(s[1]*s[channel] for s in centered)
        a, b = (xu*yy-yu*xy)/det, (yu*xx-xu*xy)/det
        coefficients.append((a, b, means[channel]-a*means[0]-b*means[1]))
    residual = max(abs(s[channel+2]-(a*s[0]+b*s[1]+c)) for s in samples for channel, (a, b, c) in enumerate(coefficients))
    u, v = coefficients
    if residual > 2e-5 or abs(u[1]) > 1e-6 or abs(v[0]) > 1e-6 or u[0] <= 0 or v[1] <= 0:
        raise ValueError('Soil UV0 is not the original registered world-XY metric mapping')
    repeat = (1/u[0], 1/v[1])
    if max(abs(r-3.) for r in repeat) > .00003: raise ValueError('Measured soil UV0 repeat differs from authored 3m')
    scale = [repeat[k]/physical_repeat[k] for k in range(2)]
    offset = [-u[2]*scale[0], -v[2]*scale[1]]
    return {'actual_world_to_uv_affine': coefficients, 'maximum_fit_residual_uv': residual,
            'measured_uv_repeat_metres': repeat, 'source_repeat_metres': physical_repeat,
            'mapping_scale': [*scale, 1.], 'mapping_location': [*offset, 0.], 'mapping_rotation': [0., 0., 0.],
            'all_channels_share_uv0_and_transform': True, 'uv_bytes_changed': False,
            'portable_policy': 'UV Map(first actual layer) -> POINT Mapping -> each image; KHR_texture_transform expected, actual GLB verification still required'}


def validate_island(component):
    points, faces = component['points'], component['faces']
    if len(points) != 11 or faces != [(0, i+1, (i+1)%10+1) for i in range(10)]: raise ValueError('Garden soil source 10-gon fan topology differs')
    center = points[0]; rim = points[1:]; rotation = math.atan2(rim[0][1]-center[1], rim[0][0]-center[0]); co, si = math.cos(rotation), math.sin(rotation)
    error = 0.
    for i, p in enumerate(rim):
        angle = i*math.tau/10; x, y = .42*math.cos(angle), .35*math.sin(angle)
        error = max(error, abs(p[0]-(center[0]+x*co-y*si)), abs(p[1]-(center[1]+x*si+y*co)))
    if error > .00015: raise ValueError('Garden soil shape is not the exact authored .84x.70m ellipse')
    return {'center_world_m': list(center), 'maximum_xy_recipe_error_m': error, 'vertices': 11, 'source_triangles': 10}


def verified_native_chain(native, entry_derivation=None):
    native = Path(native).resolve(); current_sha = sha(native)
    if current_sha == E.NATIVE_SHA256:
        return {'kind': 'IMMUTABLE_V14', 'native': str(native), 'sha256': current_sha}
    path = Path(entry_derivation).resolve() if entry_derivation else native.parent/'entry_native_derivation.json'
    d = read(path); receipt_path = path.parent/'entry_detail_changes.json'; audit_path = path.parent/'whole_town_native_geometry_audit.json'
    if d.get('schema') != 'living_town.entry_native_derivation.v1' or d.get('status') != 'NATIVE_CANDIDATE_SAVED_REQUIRES_ART_AND_RUNTIME_REVIEW': raise ValueError('Unsupported soil input derivation')
    original_candidate = Path(d.get('candidate', {}).get('path', '')).resolve()
    if d.get('candidate', {}).get('sha256') != current_sha or not original_candidate.is_file() or sha(original_candidate) != current_sha:
        raise ValueError('Entry derivative native identity mismatch')
    source = d.get('source', {})
    if source.get('sha256') != E.NATIVE_SHA256 or sha(source['path']) != E.NATIVE_SHA256 or sha(receipt_path) != d.get('entry_receipt_sha256') or sha(audit_path) != d.get('native_audit_sha256'):
        raise ValueError('Entry derivative source/receipt chain changed')
    receipt, audit = read(receipt_path), read(audit_path)
    if receipt.get('schema') != E.SCHEMA or receipt.get('tool_sha256') != sha(E.__file__) or receipt.get('source_native') != source:
        raise ValueError('Entry source recipe/identity differs')
    if audit.get('status') != 'PASS' or audit.get('source_furniture_geometry_status') != 'PASS' or d.get('native_geometry_audit') != 'PASS' or d.get('protected_interior_furniture') != 'PASS':
        raise ValueError('Entry native/furniture audit not verified')
    inventory = receipt.get('preserved_inventory', {})
    if inventory.get('all_non_target_mesh_state_sha256', {}).get(TARGET) != SOIL_NATIVE_STATE_SHA256 or inventory.get('all_material_state_sha256', {}).get('LT_Dirt') != DIRT_MATERIAL_STATE_SHA256:
        raise ValueError('Entry receipt does not preserve exact original soil/material baseline')
    return {'kind': 'VERIFIED_ENTRY_DERIVATIVE', 'native': str(native), 'sha256': current_sha,
            'recorded_original_saved_candidate': str(original_candidate), 'input_is_byte_identical_relocated_copy': original_candidate != native,
            'entry_derivation_path': str(path), 'entry_derivation_sha256': sha(path),
            'entry_receipt_sha256': sha(receipt_path), 'native_audit_sha256': sha(audit_path), 'original_v14': source,
            'entry_art_or_runtime_acceptance_inferred': False}


def verify_prepared(path):
    path = Path(path).resolve(); data = read(path)
    if data.get('schema') != 'living_town.garden_soil_prepared_maps.v1' or data.get('tool_sha256') != sha(__file__) or data.get('dimensions') != [2048, 2048]: raise ValueError('Prepared soil recipe differs')
    if data.get('grade', {}).get('linear_rgb_factors') != list(LINEAR_RGB_FACTORS) or data.get('grade', {}).get('saturation') != SATURATION: raise ValueError('Prepared soil grade changed')
    source = verify_sources(data['source']['root'])
    if data['source'] != source: raise ValueError('Prepared soil source provenance changed')
    baseline = verify_material_baseline(data['material_baseline']['path'])
    if data['material_baseline'] != baseline_record(data['material_baseline']['path'], baseline) or sha(Path(data['material_baseline']['path']).parent/'capture_garden_material_baseline.py') != baseline['capture_helper_sha256']: raise ValueError('Prepared canonical material baseline differs')
    usage_row = data['unused_material_roundtrip']; usage = verify_unused_proof(usage_row['path'], baseline)
    if usage_row != {'path': str(Path(usage_row['path']).resolve()), 'sha256': UNUSED_MATERIAL_PROOF_SHA256, 'original_native_sha256': E.NATIVE_SHA256, 'entry_native_sha256': SAVE_ORPHAN_ENTRY_SHA256, 'missing_materials': SAVE_ORPHAN_MATERIALS, 'helper_sha256': usage['helper_sha256']} or sha(Path(usage_row['path']).parent/'diagnose_garden_orphan_materials.py') != usage['helper_sha256']: raise ValueError('Prepared unused material lifecycle proof differs')
    if set(data['maps']) != {'diff', 'nor_gl', 'arm'}: raise ValueError('Prepared soil PBR channels incomplete')
    for role, row in data['maps'].items():
        if sha(row['path']) != row['sha256'] or Path(row['path']).stat().st_size != row['bytes']: raise ValueError('Prepared soil map changed: '+role)
        if role != 'diff' and row['sha256'] != MAP_FILES[role]: raise ValueError('Original soil normal/ARM substituted')
    return data


def _make_material(bpy, maps, uv_name, transform):
    mat = bpy.data.materials.new(MATERIAL); mat.use_nodes = True; ns, ls = mat.node_tree.nodes, mat.node_tree.links
    shader = ns.get('Principled BSDF'); shader.inputs['Alpha'].default_value = 1.; shader.inputs['Metallic'].default_value = 0.
    shader.inputs['Specular IOR Level'].default_value = .22; shader.inputs['Roughness'].default_value = .92
    uv = ns.new('ShaderNodeUVMap'); uv.uv_map = uv_name; uv.name = 'Exact original UV0'
    mapping = ns.new('ShaderNodeMapping'); mapping.vector_type = 'POINT'; mapping.name = 'Registered 3.001m scan transform'
    for key, value in (('Scale', transform['mapping_scale']), ('Location', transform['mapping_location']), ('Rotation', transform['mapping_rotation'])): mapping.inputs[key].default_value = value
    ls.new(uv.outputs['UV'], mapping.inputs['Vector']); images = {}
    for role in ('diff', 'nor_gl', 'arm'):
        node = ns.new('ShaderNodeTexImage'); node.name = 'Garden soil '+role
        node.image = bpy.data.images.load(maps['maps'][role]['path'], check_existing=False)
        node.image.name = 'GardenSoil_'+role; node.image.colorspace_settings.name = 'sRGB' if role == 'diff' else 'Non-Color'; node.extension = 'REPEAT'; node.image.pack()
        if not node.image.packed_file or hashlib.sha256(node.image.packed_file.data).hexdigest() != maps['maps'][role]['sha256']:
            raise ValueError('Actual packed garden soil map differs: '+role)
        ls.new(mapping.outputs['Vector'], node.inputs['Vector']); images[role] = node
    ls.new(images['diff'].outputs['Color'], shader.inputs['Base Color'])
    normal = ns.new('ShaderNodeNormalMap'); normal.uv_map = uv_name; normal.inputs['Strength'].default_value = .65
    ls.new(images['nor_gl'].outputs['Color'], normal.inputs['Color']); ls.new(normal.outputs['Normal'], shader.inputs['Normal'])
    split = ns.new('ShaderNodeSeparateColor'); ls.new(images['arm'].outputs['Color'], split.inputs[0]); ls.new(split.outputs['Green'], shader.inputs['Roughness']); ls.new(split.outputs['Blue'], shader.inputs['Metallic'])
    mat['source_license'] = 'CC0-1.0'; mat['source_asset'] = ASSET; mat['garden_soil_owner'] = SCHEMA
    mat['alpha_mode'] = 'OPAQUE'; mat['source_repeat_metres'] = maps['source']['repeat_metres']; mat.diffuse_color = (.12, .085, .05, 1.)
    return mat, [node.image for node in images.values()]


def _preservation(before, after, mesh_name):
    if before['objects'] != after['objects'] or before['meshes'].keys() != after['meshes'].keys(): raise RuntimeError('Garden soil changed object IDs/transforms or mesh inventory')
    if set(after['materials']) != set(before['materials'])|{MATERIAL} or any(after['materials'].get(k) != v for k, v in before['materials'].items()): raise RuntimeError('Garden soil changed a pre-existing material, including shared LT_Dirt')
    for name, state in before['meshes'].items():
        expected = dict(state)
        if name == mesh_name: expected['material_slots'] = [MATERIAL]
        if expected != after['meshes'][name]: raise RuntimeError('Garden soil changed geometry, UVs or a non-target mesh: '+name)


def verify_portable_mapping(document, transform):
    """Read-only actual-glTF registration check; never certifies art or pixels."""
    matches = [m for m in document.get('materials', []) if m.get('name') == MATERIAL]
    if len(matches) != 1: raise ValueError('Actual portable soil material missing/duplicated')
    mat = matches[0]
    if mat.get('alphaMode', 'OPAQUE') != 'OPAQUE': raise ValueError('Soil unexpectedly exported with alpha blending/masking')
    pbr = mat.get('pbrMetallicRoughness', {})
    infos = {'diff': pbr.get('baseColorTexture'), 'nor_gl': mat.get('normalTexture'), 'arm': pbr.get('metallicRoughnessTexture')}
    scale = transform['mapping_scale'][:2]; location = transform['mapping_location']
    expected_offset = [location[0], 1.-scale[1]-location[1]]
    result = {}
    for role, info in infos.items():
        if not isinstance(info, dict): raise ValueError('Actual portable soil channel missing: '+role)
        extension = info.get('extensions', {}).get('KHR_texture_transform', {})
        if int(extension.get('texCoord', info.get('texCoord', 0))) != 0: raise ValueError('Portable soil channel does not use original UV0')
        if max(abs(a-b) for a, b in zip(extension.get('scale', [1., 1.]), scale)) > 2e-6 or max(abs(a-b) for a, b in zip(extension.get('offset', [0., 0.]), expected_offset)) > 2e-6 or abs(extension.get('rotation', 0.)) > 1e-6:
            raise ValueError('Portable soil transform differs: '+role)
        result[role] = {'texture': info['index'], 'texCoord': 0, 'extension': extension}
    return {'status': 'PASS_TEXTURE_REGISTRATION_ONLY', 'channels': result, 'pixel_match_and_art_pass': False}


def apply(api, output, prepared):
    bpy = api['bpy']; output = Path(output).resolve(); target_receipt = output/'garden_soil_details.json'
    if target_receipt.exists(): raise FileExistsError('Garden soil receipt exists; use a fresh iteration')
    if not SOIL_NATIVE_STATE_SHA256 or not DIRT_MATERIAL_STATE_SHA256: raise ValueError('Actual immutable V14 soil/material fingerprints not pinned')
    for relative, expected in (('art/living_town/tools/landscape_details.py', FACTORY_SHA256), ('art/living_town/landscape_plan.json', PLAN_SHA256)):
        if sha(ROOT/relative) != expected: raise ValueError('Garden soil authored source binding changed: '+relative)
    E._bound_sources(); native = Path(bpy.data.filepath).resolve(); chain = verified_native_chain(native, api.get('entry_derivation'))
    if output == native.parent or native.is_relative_to(output): raise ValueError('Keep garden receipts separate from immutable input')
    maps = verify_prepared(prepared); ob = bpy.data.objects.get(TARGET)
    if not ob or ob.type != 'MESH' or ob.data.users != 1 or ob.data.shape_keys or [m.name if m else None for m in ob.data.materials] != ['LT_Dirt']:
        raise ValueError('Exact garden soil source object/material identity differs')
    if bpy.data.materials.get(MATERIAL): raise ValueError('Garden soil material pilot already present')
    mesh = ob.data
    if not mesh.uv_layers or mesh.uv_layers.active_index != 0 or not mesh.uv_layers[0].active_render or any(p.material_index != 0 for p in mesh.polygons): raise ValueError('Original garden UV0/material face mapping differs')
    before_materials = material_inventory(bpy)
    expected_materials = contract_expected_inventory(chain, maps)
    if before_materials['canonical'] != expected_materials: raise ValueError('Actual exact-source canonical material inventory differs')
    if E._digest(E._mesh_state(ob)) != SOIL_NATIVE_STATE_SHA256 or before_materials['canonical'].get('LT_Dirt') != DIRT_CANONICAL_SHA256:
        raise ValueError('Actual garden soil/UV/material fingerprint differs from immutable original')
    components = [validate_island(c) for c in E._helper()._components(ob)]
    samples = []
    for polygon in mesh.polygons:
        for li in polygon.loop_indices:
            point = ob.matrix_world@mesh.vertices[mesh.loops[li].vertex_index].co; uv = mesh.uv_layers[0].data[li].uv
            samples.append((point.x, point.y, uv.x, uv.y))
    transform = measured_uv_transform(samples, maps['source']['repeat_metres'])
    before = E._snapshot(bpy)
    if before['materials'] != before_materials['raw'] or E._digest(before['meshes'][mesh.name]) != SOIL_NATIVE_STATE_SHA256: raise ValueError('Input changed after cheap target/canonical preflight')
    old = mesh.materials[0]; material = None; images = []; old_images = {im.as_pointer() for im in bpy.data.images}
    try:
        material, images = _make_material(bpy, maps, mesh.uv_layers[0].name, transform)
        mesh.materials[0] = material; bpy.context.view_layer.update()
        after = E._snapshot(bpy); _preservation(before, after, mesh.name)
        after_materials = material_inventory(bpy)
        old_names = set(before_materials['raw'])
        if set(after_materials['raw']) != old_names|{MATERIAL} or any({k: after_materials[mode][k] for k in old_names} != before_materials[mode] for mode in ('raw', 'canonical', 'session_uid')) or after['materials'] != after_materials['raw']: raise RuntimeError('Actual same-process original material preservation differs')
        verify_prepared(prepared); E._bound_sources()
        if verified_native_chain(native, api.get('entry_derivation')) != chain: raise RuntimeError('Immutable garden input derivation changed')
        report = {'schema': SCHEMA, 'status': 'MATERIAL_ONLY_APPLIED_REQUIRES_ACTUAL_BLENDER_AND_GODOT_AB', 'tool_sha256': sha(__file__),
                  'input_native': chain, 'target_object': TARGET, 'source_mesh': mesh.name, 'island_count': len(components),
                  'source_islands': components, 'original_mesh_state_sha256': SOIL_NATIVE_STATE_SHA256,
                  'new_mesh_state_sha256': E._digest(after['meshes'][mesh.name]), 'original_shared_dirt_material_sha256': DIRT_MATERIAL_STATE_SHA256,
                  'new_material': MATERIAL, 'new_material_state_sha256': after['materials'][MATERIAL],
                  'prepared_receipt': {'path': str(Path(prepared).resolve()), 'sha256': sha(prepared)}, 'maps': maps, 'uv_transform': transform,
                  'packed_material_images': [{'name': image.name, 'sha256': hashlib.sha256(image.packed_file.data).hexdigest(),
                                              'bytes': len(image.packed_file.data), 'color_space': image.colorspace_settings.name} for image in images],
                  'geometry_uv_topology_world_transform_preservation': 'PASS', 'all_non_target_meshes_and_objects': 'PASS',
                  'all_original_materials_including_shared_LT_Dirt': 'PASS',
                  'preserved_mesh_state_sha256': {n: E._digest(s) for n, s in before['meshes'].items() if n != mesh.name},
                  'preserved_material_state_sha256': before['materials'], 'scene_before_sha256': E._digest(before), 'scene_after_sha256': E._digest(after),
                  'material_session_preservation': {'excluded_root_material_fields': MATERIAL_EXCLUDED_FIELDS,
                      'source_baseline_material_count': 137, 'live_original_material_count': len(expected_materials),
                      'permitted_missing_unused_materials': sorted(set(maps['material_baseline']['canonical_material_state_sha256'])-set(expected_materials)),
                      'unused_material_proof_sha256': UNUSED_MATERIAL_PROOF_SHA256,
                      'material_baseline_sha256': MATERIAL_BASELINE_SHA256, 'canonicalizer_tool_sha256': sha(__file__),
                      'raw_before': before_materials['raw'], 'raw_after_original': {k: after_materials['raw'][k] for k in old_names},
                      'canonical_before': before_materials['canonical'], 'canonical_after_original': {k: after_materials['canonical'][k] for k in old_names},
                      'session_uid_before': before_materials['session_uid'], 'session_uid_after_original': {k: after_materials['session_uid'][k] for k in old_names},
                      'raw_same_process_preservation': 'PASS', 'canonical_same_process_preservation': 'PASS',
                      'historical_entry_raw_hashes_compared_across_sessions': False, 'raw_whole_scene_digest_compared_across_sessions': False,
                      'live_original_LT_Dirt_raw_sha256': before_materials['raw']['LT_Dirt'], 'LT_Dirt_canonical_sha256': DIRT_CANONICAL_SHA256},
                  'material_slot_change': {'from': ['LT_Dirt'], 'to': [MATERIAL]}, 'alpha_mode': 'OPAQUE',
                  'geometry_reconstruction': False, 'scene_saved': False, 'exported': False, 'art_pass': False,
                  'portable_transform_verification': 'PENDING_ACTUAL_GLTF_TEXTURE_TRANSFORM_AND_PBR_IMAGES', 'gameplay_ab': 'PENDING'}
        output.mkdir(parents=True, exist_ok=True); write(target_receipt, report); return report
    except BaseException:
        mesh.materials[0] = old
        created = bpy.data.materials.get(MATERIAL)
        if created: bpy.data.materials.remove(created)
        for image in list(bpy.data.images):
            if image.as_pointer() in old_images: continue
            if image.users == 0: bpy.data.images.remove(image)
        bpy.context.view_layer.update()
        if E._snapshot(bpy) != before: raise RuntimeError('Garden material rollback incomplete; discard unsaved scene')
        raise


def pilot(prepared, output, entry_derivation=None):
    """Explicit owner-run Blender pilot, audit then COPY save; no art claim."""
    import bpy
    output = Path(output).resolve()
    if output.exists(): raise FileExistsError('Actual garden pilot requires a fresh output directory')
    native = Path(bpy.data.filepath).resolve(); api = {'bpy': bpy}
    if entry_derivation: api['entry_derivation'] = entry_derivation
    report = apply(api, output, prepared); chain = report['input_native']
    original = Path(chain['original_v14']['path']) if chain['kind'] == 'VERIFIED_ENTRY_DERIVATIVE' else native
    for name, expected in E.RECORD_HASHES.items():
        if sha(original.parent/name) != expected: raise ValueError('Original architectural/furniture records changed')
    buildings = read(original.parent/'whole_town_buildings.json'); furniture = read(original.parent/'source_furniture_geometry.json')
    audit_module = E._load('garden_pilot_original_native_audit', ROOT/'tools/town_upgrade/building_native_audit.py')
    audit_path = output/'whole_town_native_geometry_audit.json'
    audited = audit_module.audit({'bpy': bpy}, buildings['buildings'], audit_path, furniture['objects'])
    if audited['status'] != 'PASS' or audited['source_furniture_geometry_status'] != 'PASS': raise RuntimeError('Garden native geometry audit failed; candidate not saved')
    destination = output/'refined_whole_town.blend'; result = bpy.ops.wm.save_as_mainfile(filepath=str(destination), copy=True)
    if 'FINISHED' not in result or not destination.is_file() or sha(native) != chain['sha256']: raise RuntimeError('Garden candidate save/immutable source identity failed')
    derivation = {'schema': 'living_town.garden_soil_native_derivation.v1', 'status': 'MATERIAL_CANDIDATE_SAVED_REQUIRES_ACTUAL_AB_REVIEW',
                  'input_native': chain, 'candidate': {'path': str(destination), 'sha256': sha(destination)},
                  'garden_receipt_sha256': sha(output/'garden_soil_details.json'), 'native_audit_sha256': sha(audit_path),
                  'native_geometry_audit': 'PASS', 'protected_interior_furniture': 'PASS', 'packed_soil_image_count': 3,
                  'tool_sha256': sha(__file__), 'blender_version': bpy.app.version_string,
                  'rendered_review': False, 'godot_review': False, 'portable_export': False}
    write(output/'garden_soil_native_derivation.json', derivation); return derivation


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest='command', required=True)
    prep = sub.add_parser('prepare'); prep.add_argument('--sources', type=Path, required=True); prep.add_argument('--output', type=Path, required=True); prep.add_argument('--material-baseline', type=Path, required=True); prep.add_argument('--unused-material-proof', type=Path, required=True)
    run = sub.add_parser('pilot'); run.add_argument('--prepared', type=Path, required=True); run.add_argument('--output', type=Path, required=True); run.add_argument('--entry-derivation', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if args.command == 'prepare':
        result = prepare_maps(args.sources, args.output, args.material_baseline, args.unused_material_proof); print(json.dumps({'status': result['status'], 'output': str(args.output), 'statistics': result['statistics']}))
    else: print(json.dumps(pilot(args.prepared, args.output, args.entry_derivation)))


if __name__ == '__main__': main()
