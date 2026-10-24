"""Source/license/metric UV and non-target preservation tests; no engines."""
from copy import deepcopy
import json
import math
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tools.town_upgrade import garden_soil_details as S


def samples(repeat=3., offset=(.02, -.03)):
    return [(x, y, x/repeat+offset[0], y/repeat+offset[1]) for x, y in ((0., 0.), (2., 0.), (0., 2.), (3., 4.), (-3., -6.), (100., -43.))]


def island():
    center = (12., -3., .8); angle = .73; co, si = math.cos(angle), math.sin(angle)
    rim = []
    for i in range(10):
        a = i*math.tau/10; x, y = .42*math.cos(a), .35*math.sin(a)
        rim.append((center[0]+x*co-y*si, center[1]+x*si+y*co, .8+i*.0001))
    return {'points': [center, *rim], 'faces': [(0, i+1, (i+1)%10+1) for i in range(10)]}


class MetricAndRecipeTests(unittest.TestCase):
    def test_uv_bytes_preserved_and_actual_metric_compensates_scan_repeat(self):
        values = samples(); before = deepcopy(values); repeat = [3.0009725093841553, 3.0009801387786865]
        result = S.measured_uv_transform(values, repeat)
        self.assertEqual(values, before)
        for x, y, u, v in values:
            self.assertAlmostEqual(u*result['mapping_scale'][0]+result['mapping_location'][0], x/repeat[0], places=10)
            self.assertAlmostEqual(v*result['mapping_scale'][1]+result['mapping_location'][1], y/repeat[1], places=10)
        self.assertFalse(result['uv_bytes_changed'])

    def test_tampered_metric_uvs_are_rejected(self):
        for values in (samples(2.), [(x, y, u+y*.02, v) for x, y, u, v in samples()],
                       [*samples()[:-1], (100., -43., 50., -14.)]):
            with self.assertRaises(ValueError): S.measured_uv_transform(values, [3.001, 3.001])

    def test_exact_eleven_vertex_ten_triangle_islands_only(self):
        self.assertEqual(S.validate_island(island())['source_triangles'], 10)
        bad = island(); bad['points'][1] = (bad['points'][1][0]+.03, *bad['points'][1][1:])
        with self.assertRaises(ValueError): S.validate_island(bad)
        bad = island(); bad['faces'][0] = (0, 2, 1)
        with self.assertRaises(ValueError): S.validate_island(bad)

    def test_earth_grade_is_darker_and_retains_nonuniform_visible_grain(self):
        from PIL import Image, ImageStat
        source = Image.new('RGB', (3, 2)); source.putdata([(180, 150, 95), (65, 90, 25), (125, 100, 60), (205, 175, 110), (100, 78, 48), (155, 130, 65)])
        result = S.grade_diffuse(source)
        self.assertLess(S._mean_linear_luma(result), S._mean_linear_luma(source)*.75)
        self.assertGreater(S._mean_linear_luma(result), S._mean_linear_luma(source)*.15)
        self.assertGreater(ImageStat.Stat(result.convert('L')).stddev[0], 4.)
        self.assertEqual(source.getpixel((0, 0)), (180, 150, 95))


class PreservationAndPortableTests(unittest.TestCase):
    def before(self):
        return {'objects': {'soil': {'id': 'same'}, 'unrelated': {'id': 'same'}},
                'meshes': {'soil': {'geometry_sha256': 'same', 'uv': 'same', 'material_slots': ['LT_Dirt']},
                           'unrelated': {'geometry_sha256': 'same', 'uv': 'same', 'material_slots': ['LT_Dirt']}},
                'materials': {'LT_Dirt': 'same', 'Fern_MASK': 'same'}}

    def test_only_soil_slot_change_is_allowed(self):
        before = self.before(); after = deepcopy(before); after['meshes']['soil']['material_slots'] = [S.MATERIAL]; after['materials'][S.MATERIAL] = 'new'
        S._preservation(before, after, 'soil')
        for section, name, field in (('meshes', 'soil', 'uv'), ('meshes', 'soil', 'geometry_sha256'), ('meshes', 'unrelated', 'material_slots'), ('objects', 'unrelated', 'id')):
            bad = deepcopy(after); bad[section][name][field] = 'changed'
            with self.assertRaises(RuntimeError): S._preservation(before, bad, 'soil')
        bad = deepcopy(after); bad['materials']['LT_Dirt'] = 'beach/path changed'
        with self.assertRaises(RuntimeError): S._preservation(before, bad, 'soil')

    def test_actual_gltf_all_three_channels_share_metric_uv0_transform(self):
        transform = S.measured_uv_transform(samples(), [3.001, 3.001])
        scale = transform['mapping_scale'][:2]; loc = transform['mapping_location']; ext = {'scale': scale, 'offset': [loc[0], 1-scale[1]-loc[1]]}
        info = lambda i: {'index': i, 'texCoord': 0, 'extensions': {'KHR_texture_transform': deepcopy(ext)}}
        mat = {'name': S.MATERIAL, 'alphaMode': 'OPAQUE', 'pbrMetallicRoughness': {'baseColorTexture': info(0), 'metallicRoughnessTexture': info(2)}, 'normalTexture': info(1)}
        self.assertFalse(S.verify_portable_mapping({'materials': [mat]}, transform)['pixel_match_and_art_pass'])
        bad = deepcopy(mat); bad['normalTexture']['extensions']['KHR_texture_transform']['scale'] = [1, 1]
        with self.assertRaises(ValueError): S.verify_portable_mapping({'materials': [bad]}, transform)
        bad = deepcopy(mat); bad['normalTexture']['texCoord'] = 1
        with self.assertRaises(ValueError): S.verify_portable_mapping({'materials': [bad]}, transform)
        bad = deepcopy(mat); bad['alphaMode'] = 'MASK'
        with self.assertRaises(ValueError): S.verify_portable_mapping({'materials': [bad]}, transform)

    def test_missing_actual_baseline_rejects_before_any_material_mutation(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(S, 'SOIL_NATIVE_STATE_SHA256', None), patch.object(S, '_make_material') as mutate:
            with self.assertRaisesRegex(ValueError, 'fingerprints not pinned'): S.apply({'bpy': SimpleNamespace()}, Path(directory)/'fresh', 'never read')
            mutate.assert_not_called()


class SourceAndChainTests(unittest.TestCase):
    def test_only_exact_saved_entry_can_use_four_proven_unused_exceptions(self):
        full={n:'canonical-'+n for n in [*S.SAVE_ORPHAN_MATERIALS,'LT_Dirt','OtherLive']}
        maps={'material_baseline':{'canonical_material_state_sha256':full}}
        self.assertEqual(S.contract_expected_inventory({'kind':'IMMUTABLE_V14','sha256':S.E.NATIVE_SHA256},maps),full)
        live=S.contract_expected_inventory({'kind':'VERIFIED_ENTRY_DERIVATIVE','sha256':S.SAVE_ORPHAN_ENTRY_SHA256},maps)
        self.assertEqual(set(full)-set(live),set(S.SAVE_ORPHAN_MATERIALS))
        with self.assertRaisesRegex(ValueError,'No measured material lifecycle'):
            S.contract_expected_inventory({'kind':'VERIFIED_ENTRY_DERIVATIVE','sha256':'different saved entry'},maps)

    def test_actual_exact_unused_material_proof_and_any_owner_rejected(self):
        path=Path('F:/Living Town/2026-10-20_Refined_Town/source_assets/garden_unused_material_roundtrip_v15_001.json')
        bp=Path('F:/Living Town/2026-10-20_Refined_Town/source_assets/garden_original_material_baseline_v15_001.json')
        if not path.exists():self.skipTest('Actual owner usage proof unavailable')
        baseline=S.verify_material_baseline(bp);proof=S.verify_unused_proof(path,baseline)
        self.assertEqual(proof['entry']['material_count'],133)
        with tempfile.TemporaryDirectory() as directory:
            for key,value in [('users',1),('mesh_owners',['OwnedMesh']),('use_fake_user',True)]:
                bad=deepcopy(proof);bad['original']['selected_material_usage']['LT_Hair'][key]=value
                dest=Path(directory)/(key+'.json');dest.write_text(json.dumps(bad))
                with patch.object(S,'UNUSED_MATERIAL_PROOF_SHA256',S.sha(dest)):
                    with self.assertRaisesRegex(ValueError,'measured unowned save orphan'):S.verify_unused_proof(dest,baseline)

    def test_canonicalization_excludes_only_root_session_uid(self):
        state = {'settings': {'session_uid': 12, 'roughness': .84, 'name': 'LT_Dirt'}, 'properties': {'keep': True},
                 'node_tree': {'nodes': [{'settings': {'session_uid': 90, 'location': [1., 2.]}, 'inputs': [{'default': .65}]}]}}
        original = deepcopy(state); first, uid = S.canonical_material_state(state)
        self.assertEqual(uid, 12); self.assertEqual(state, original)
        other = deepcopy(state); other['settings']['session_uid'] = 27
        self.assertEqual(S.canonical_material_state(other)[0], first)
        for mutate in (lambda v: v['settings'].__setitem__('roughness', .2),
                       lambda v: v['node_tree']['nodes'][0]['settings'].__setitem__('session_uid', 99),
                       lambda v: v['node_tree']['nodes'][0]['inputs'][0].__setitem__('default', .3)):
            changed = deepcopy(state); mutate(changed)
            self.assertNotEqual(S.E._digest(S.canonical_material_state(changed)[0]), S.E._digest(first))
        bad = deepcopy(state); bad['settings'].pop('session_uid')
        with self.assertRaises(KeyError): S.canonical_material_state(bad)

    def test_actual_original137_canonical_baseline_is_pinned(self):
        path = Path('F:/Living Town/2026-10-20_Refined_Town/source_assets/garden_original_material_baseline_v15_001.json')
        if not path.exists(): self.skipTest('Owner actual canonical baseline unavailable')
        baseline = S.verify_material_baseline(path)
        self.assertEqual(len(baseline['canonical_material_state_sha256']), 137)
        self.assertEqual(baseline['canonical_material_state_sha256']['LT_Dirt'], S.DIRT_CANONICAL_SHA256)
        with tempfile.TemporaryDirectory() as directory:
            bad = Path(directory)/'changed.json'; bad.write_bytes(path.read_bytes()+b' ')
            with self.assertRaisesRegex(ValueError, 'baseline changed'): S.verify_material_baseline(bad)

    def test_same_process_raw_material_changes_still_reject(self):
        before = PreservationAndPortableTests().before(); after = deepcopy(before)
        after['meshes']['soil']['material_slots'] = [S.MATERIAL]; after['materials'][S.MATERIAL] = 'new'
        after['materials']['LT_Dirt'] = 'only session_uid changed within same process'
        with self.assertRaisesRegex(RuntimeError, 'pre-existing material'): S._preservation(before, after, 'soil')

    def test_actual_selected_cc0_sources_and_channels_are_bound(self):
        sources = Path('F:/Living Town/2026-10-20_Refined_Town/source_assets/terrain_leafy_polyhaven')
        if not sources.exists(): self.skipTest('Local licensed scan cache absent')
        data = S.verify_sources(sources)
        self.assertEqual(data['license'], 'CC0-1.0'); self.assertEqual(set(data['maps']), {'diff', 'nor_gl', 'arm'})
        self.assertAlmostEqual(data['repeat_metres'][0], 3.0009725093841553)
        with patch.object(S, 'sha', return_value='changed'):
            with self.assertRaises(ValueError): S.verify_sources(sources)

    def test_unknown_native_and_incomplete_derivation_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); native = folder/'new.blend'; native.write_bytes(b'unit only')
            path = folder/'entry_native_derivation.json'; path.write_text(json.dumps({'schema': 'wrong'}))
            with self.assertRaisesRegex(ValueError, 'Unsupported soil input derivation'): S.verified_native_chain(native)

    def test_verified_entry_chain_accepted_and_native_or_receipt_tamper_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(S, 'SOIL_NATIVE_STATE_SHA256', 'soil'), patch.object(S, 'DIRT_MATERIAL_STATE_SHA256', 'dirt'):
            folder = Path(directory); native = folder/'candidate.blend'; native.write_bytes(b'candidate unit'); source_native = folder/'original.blend'; source_native.write_bytes(b'original unit')
            source = {'path': str(source_native), 'sha256': S.E.NATIVE_SHA256}
            receipt = {'schema': S.E.SCHEMA, 'tool_sha256': S.sha(S.E.__file__), 'source_native': source,
                       'preserved_inventory': {'all_non_target_mesh_state_sha256': {S.TARGET: 'soil'}, 'all_material_state_sha256': {'LT_Dirt': 'dirt'}}}
            audit = {'status': 'PASS', 'source_furniture_geometry_status': 'PASS'}
            rp = folder/'entry_detail_changes.json'; rp.write_text(json.dumps(receipt)); ap = folder/'whole_town_native_geometry_audit.json'; ap.write_text(json.dumps(audit))
            derivative = {'schema': 'living_town.entry_native_derivation.v1', 'status': 'NATIVE_CANDIDATE_SAVED_REQUIRES_ART_AND_RUNTIME_REVIEW',
                          'candidate': {'path': str(native), 'sha256': S.sha(native)}, 'source': source, 'entry_receipt_sha256': S.sha(rp), 'native_audit_sha256': S.sha(ap),
                          'native_geometry_audit': 'PASS', 'protected_interior_furniture': 'PASS'}
            dp = folder/'entry_native_derivation.json'; dp.write_text(json.dumps(derivative)); actual_sha = S.sha
            with patch.object(S, 'sha', side_effect=lambda p: S.E.NATIVE_SHA256 if Path(p) == source_native else actual_sha(p)):
                self.assertEqual(S.verified_native_chain(native)['kind'], 'VERIFIED_ENTRY_DERIVATIVE')
                relocated = folder/'copied.blend'; relocated.write_bytes(native.read_bytes())
                self.assertTrue(S.verified_native_chain(relocated)['input_is_byte_identical_relocated_copy'])
                rp.write_text(json.dumps({**receipt, 'tool_sha256': 'changed'}))
                with self.assertRaisesRegex(ValueError, 'chain changed'): S.verified_native_chain(native)
                rp.write_text(json.dumps(receipt)); native.write_bytes(b'candidate altered')
                with self.assertRaisesRegex(ValueError, 'native identity mismatch'): S.verified_native_chain(native)


class PilotWrapperTests(unittest.TestCase):
    def exercise(self, accepted):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory); source = folder/'source'; source.mkdir(); native = source/'native.blend'; native.write_bytes(b'unit input only')
            buildings = {'schema': 'fixture', 'buildings': [{'id': 'one'}]}; furniture = {'schema': 'fixture', 'objects': {'protected_one': {'geometry_sha256': 'original'}}}
            (source/'whole_town_buildings.json').write_text(json.dumps(buildings)); (source/'source_furniture_geometry.json').write_text(json.dumps(furniture))
            records = {name: S.sha(source/name) for name in ('whole_town_buildings.json', 'source_furniture_geometry.json')}
            chain = {'kind': 'IMMUTABLE_V14', 'native': str(native), 'sha256': S.sha(native)}; output = folder/'candidate'; saved = []
            def apply(api, destination, prepared):
                destination.mkdir(); (destination/'garden_soil_details.json').write_text('{}'); return {'input_native': chain}
            def audit(api, rows, path, protected):
                self.assertEqual(rows, buildings['buildings']); self.assertEqual(protected, furniture['objects'])
                report = {'status': 'PASS' if accepted else 'FAIL', 'source_furniture_geometry_status': 'PASS'}
                path.write_text(json.dumps(report)); return report
            def save(**kwargs):
                self.assertTrue(kwargs['copy']); Path(kwargs['filepath']).write_bytes(b'unit candidate only'); saved.append(kwargs); return {'FINISHED'}
            bpy = SimpleNamespace(data=SimpleNamespace(filepath=str(native)), app=SimpleNamespace(version_string='unit fake'),
                                  ops=SimpleNamespace(wm=SimpleNamespace(save_as_mainfile=save)))
            with patch.dict(S.sys.modules, {'bpy': bpy}), patch.object(S, 'apply', side_effect=apply), \
                 patch.object(S.E, 'RECORD_HASHES', records), patch.object(S.E, '_load', return_value=SimpleNamespace(audit=audit)):
                if accepted:
                    result = S.pilot('unit-unused-prepared.json', output)
                    self.assertEqual(result['status'], 'MATERIAL_CANDIDATE_SAVED_REQUIRES_ACTUAL_AB_REVIEW')
                    self.assertFalse(result['rendered_review']); self.assertFalse(result['portable_export']); self.assertEqual(len(saved), 1)
                else:
                    with self.assertRaisesRegex(RuntimeError, 'audit failed'): S.pilot('unit-unused-prepared.json', output)
                    self.assertFalse(saved); self.assertFalse((output/'garden_soil_native_derivation.json').exists())

    def test_owner_pilot_passes_decoded_rows_and_protected_map_to_existing_audit(self): self.exercise(True)
    def test_failed_native_audit_cannot_save_a_garden_candidate(self): self.exercise(False)


if __name__ == '__main__': unittest.main()
