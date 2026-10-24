"""Bounded entry-layout provenance, rigid transforms and rollback; no engines."""
from copy import deepcopy
import math
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from tools.town_upgrade import entry_details as e


def support(x, y, kind):
    return {'z': .45 if kind == 'plaza' else 6.72, 'normal': [0., 0., 1.],
            'object': 'fixture_'+kind, 'polygon': 0}


def fixture(table):
    result = {}
    for y, z in zip(e.TABLE_YS, (.55023, .5545, .55945)):
        for part in e._table_parts(table, 4.5, y, z):
            name = e.CIVIC+'_'+part['material']
            offset = sum(len(c['points']) for c in result.get(name, []))
            result.setdefault(name, []).append({'indices': list(range(offset, offset+len(part['vertices']))),
                                                'points': deepcopy(part['vertices']), 'faces': part['faces']})
    for part in e._post_parts(6.77734375):
        name = e.WAYFINDING+'_'+part['material']
        result.setdefault(name, []).append({'indices': list(range(len(part['vertices']))),
                                            'points': deepcopy(part['vertices']), 'faces': part['faces']})
    # This unrelated component is intentionally in a mixed target object.
    cube = e._helper()._Recorder(); cube.box((99., 99., 3.), (1., 2., 3.), 'Oak')
    part = cube.parts[0]; name = e.CIVIC+'_Oak'
    offset = sum(len(c['points']) for c in result[name])
    result[name].append({'indices': list(range(offset, offset+8)), 'points': part['vertices'], 'faces': part['faces']})
    return result


class EntryPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        table, cls.bindings = e._recipes()
        cls.table = staticmethod(table)

    def setUp(self):
        self.components = fixture(self.table)

    def test_complete_bound_recipe_is_195_verified_and_195_changed(self):
        before = deepcopy(self.components)
        plan = e._geometry_plan(self.components, self.table, support)
        self.assertEqual(len(plan['edits']), 195)
        self.assertEqual(sum(p['changed'] for p in plan['edits']), 195)
        self.assertEqual([g['components'] for g in plan['groups']], [64, 64, 64, 3])
        self.assertEqual(self.components, before)
        self.assertTrue(all('Civic_' in p['object'] or 'Reserve_Trailside_' in p['object'] for p in plan['edits']))
        self.assertFalse(any(p['object'].startswith('Main_cafe_L') for p in plan['edits']))
        self.assertNotIn(len(self.components[e.CIVIC+'_Oak'])-1,
                         [p['component'] for p in plan['edits'] if p['object'] == e.CIVIC+'_Oak'])

    def test_all_six_seat_fronts_point_at_their_own_table(self):
        for old_xy in [(4.5, y) for y in e.TABLE_YS]:
            new_xy = e.NEW_MIDDLE_XY if old_xy[1] == 0 else e.NEW_UPPER_XY if old_xy[1] > 0 else old_xy
            for seat, angle in enumerate((0., math.pi)):
                center = (old_xy[0]+math.cos(angle)*.83, old_xy[1]+math.sin(angle)*.83)
                source_rotation = angle+math.pi
                front = (center[0]+math.sin(source_rotation), center[1]-math.cos(source_rotation), .5)
                moved_center = e._patio_point((*center, .5), 6+seat*29, old_xy, new_xy)
                moved_front = e._patio_point(front, 6+seat*29, old_xy, new_xy)
                direction = tuple(moved_front[k]-moved_center[k] for k in range(2))
                inward = tuple((new_xy[k]-moved_center[k])/.83 for k in range(2))
                self.assertAlmostEqual(sum(a*b for a, b in zip(direction, inward)), 1.)

    def test_all_sets_ground_independent_rigid_furniture_with_bounded_outer_move(self):
        plan = e._geometry_plan(self.components, self.table, support)
        for start in (0, 128):
            for edit in plan['edits'][start:start+6]:
                self.assertTrue(edit['changed'])
                for old, new in zip(edit['old_points'], edit['new_points']):
                    self.assertAlmostEqual(new[0]-old[0], 0. if start == 0 else -.1, places=13)
                    self.assertAlmostEqual(new[1], old[1], places=13)
            shifts = [edit['new_points'][0][2]-edit['old_points'][0][2]
                      for edit in plan['edits'][start:start+6]]
            self.assertLess(max(shifts)-min(shifts), 1e-12)
        middle = plan['groups'][1]
        self.assertEqual(middle['new_table_center_m'][:2], [2.3, 1.65])
        self.assertGreaterEqual(middle['grounding']['minimum_gap_m'], .000999)
        self.assertLess(middle['grounding']['maximum_gap_m'], .030001)
        self.assertEqual(len(middle['grounding']['rigid_subassemblies']), 3)
        self.assertTrue(all(abs(offset) <= .05 for offset in middle['grounding']['chair_base_offsets_from_table_m']))
        for edit in plan['edits']:
            old, new = edit['old_points'], edit['new_points']
            self.assertAlmostEqual(math.dist(old[0], old[-1]), math.dist(new[0], new[-1]), places=10)

    def test_keyed_post_board_and_marking_move_together_with_rotated_face(self):
        plan = e._geometry_plan(self.components, self.table, support)
        rod, board, marking = plan['edits'][-3:]
        b = e._bounds(board['new_points']); m = e._bounds(marking['new_points'])
        self.assertAlmostEqual(b[1][0]-b[0][0], .08)
        self.assertAlmostEqual(b[1][1]-b[0][1], .82)
        self.assertAlmostEqual((m[0][0]+m[1][0])/2, -130.50)
        self.assertAlmostEqual((m[0][1]+m[1][1])/2, -80.)
        self.assertAlmostEqual(min(p[2] for p in rod['new_points']), 6.721)

    def test_missing_last_component_rejects_whole_plan_without_mutation(self):
        self.components[e.WAYFINDING+'_White'].clear()
        before = deepcopy(self.components)
        with self.assertRaisesRegex(ValueError, 'complete source primitive'):
            e._geometry_plan(self.components, self.table, support)
        self.assertEqual(before, self.components)

    def test_duplicate_source_anchor_is_rejected(self):
        self.components[e.CIVIC+'_White'].append(deepcopy(self.components[e.CIVIC+'_White'][0]))
        with self.assertRaisesRegex(ValueError, 'source anchor; found 2'):
            e._geometry_plan(self.components, self.table, support)

    def test_wrong_primitive_topology_is_rejected(self):
        self.components[e.WAYFINDING+'_Sage'][0]['faces'] = [(0, 1, 2)]
        with self.assertRaisesRegex(ValueError, 'complete source primitive'):
            e._geometry_plan(self.components, self.table, support)

    def test_wrong_geometry_is_rejected_instead_of_spatial_fallback(self):
        c = self.components[e.CIVIC+'_Linen'][0]
        c['points'][0] = tuple(v+.02 for v in c['points'][0])
        with self.assertRaisesRegex(ValueError, 'complete source primitive'):
            e._geometry_plan(self.components, self.table, support)

    def test_missing_steep_or_rocking_actual_support_is_rejected(self):
        for callback in (lambda x, y, kind: None,
                         lambda x, y, kind: {**support(x, y, kind), 'normal': [0., .8, .6]},
                         lambda x, y, kind: {**support(x, y, kind), 'z': support(x, y, kind)['z']+x*.1}):
            with self.subTest(callback=callback), self.assertRaises(ValueError):
                e._geometry_plan(self.components, self.table, callback)

    def test_mismatched_recipe_is_rejected_before_ast_execution(self):
        with patch.object(e, '_sha', return_value='changed'), patch.object(e.ast, 'parse') as parse:
            with self.assertRaisesRegex(ValueError, 'source binding mismatch'):
                e._recipes()
            parse.assert_not_called()

    def test_font_clearance_and_panel_margins_are_real_bound_checks(self):
        text = {'backing_bounds_m': [[-132.42, -80.45, 9.391389], [-132.34, -75.55, 9.741389]],
                'new_world_bounds_m': [[-132.322, -78.66, 9.4659], [-132.318, -77.34, 9.6669]]}
        e._verify_text_bounds(text)
        for axis, value in ((0, -132.341), (1, -80.44), (2, 9.40)):
            bad = deepcopy(text); bad['new_world_bounds_m'][0][axis] = value
            with self.assertRaises(RuntimeError):
                e._verify_text_bounds(bad)


def preservation_fixture():
    matrix = [[1., 0., 0., 0.], [0., 1., 0., 0.], [0., 0., 1., 0.], [0., 0., 0., 1.]]
    objects = {'unrelated': {'matrix_world': matrix, 'properties': {'interior_asset_id': 'keep'}},
               e.SIGN: {key: deepcopy(matrix) for key in ('matrix_world', 'matrix_local', 'matrix_basis')}}
    return {'objects': objects, 'meshes': {'target': {'geometry_sha256': 'old', 'uv': 'same'},
                                        'unrelated': {'geometry_sha256': 'keep', 'uv': 'same'}},
            'materials': {'LT_White': 'same'}}


class PreservationTests(unittest.TestCase):
    def test_only_target_position_hash_and_exact_text_outset_are_authorized(self):
        before = preservation_fixture(); after = deepcopy(before)
        after['meshes']['target']['geometry_sha256'] = 'new'
        for key in ('matrix_world', 'matrix_local', 'matrix_basis'):
            after['objects'][e.SIGN][key][0][3] = .02
        e._validate_preservation(before, after, {'target'}, {'old_location_m': [0, 0, 0], 'new_location_m': [.02, 0, 0]})
        for section, name, key in (('meshes', 'target', 'uv'), ('meshes', 'unrelated', 'geometry_sha256'),
                                   ('objects', 'unrelated', 'properties')):
            bad = deepcopy(after); bad[section][name][key] = 'corrupt'
            with self.assertRaises(RuntimeError):
                e._validate_preservation(before, bad, {'target'}, {'old_location_m': [0, 0, 0], 'new_location_m': [.02, 0, 0]})
        bad = deepcopy(after); bad['materials']['LT_White'] = 'changed'
        with self.assertRaises(RuntimeError):
            e._validate_preservation(before, bad, {'target'}, {'old_location_m': [0, 0, 0], 'new_location_m': [.02, 0, 0]})

    def test_source_native_and_both_record_files_are_frozen_before_input_use(self):
        with tempfile.TemporaryDirectory(prefix='town_entry_bindings_') as directory:
            folder = Path(directory)
            native = folder/'source.blend'; native.write_bytes(b'not a real engine file')
            buildings = {'buildings': [{'id': 'fixture'}]}
            furniture = {'objects': {'fixture': {'geometry_sha256': 'frozen'}}}
            (folder/'whole_town_buildings.json').write_text(e.json.dumps(buildings), encoding='utf-8')
            (folder/'source_furniture_geometry.json').write_text(e.json.dumps(furniture), encoding='utf-8')
            bpy = SimpleNamespace(data=SimpleNamespace(filepath=str(native)))
            hashes = {native.name: e.NATIVE_SHA256, **e.RECORD_HASHES}
            with patch.object(e, '_sha', side_effect=lambda p: hashes[Path(p).name]):
                self.assertEqual(e._freeze_inputs(bpy, buildings, furniture)[0], native.resolve())
                with self.assertRaisesRegex(ValueError, 'Supplied building/furniture records differ'):
                    e._freeze_inputs(bpy, buildings, {'objects': {}})
                hashes['source_furniture_geometry.json'] = 'changed'
                with self.assertRaisesRegex(ValueError, 'record binding mismatch'):
                    e._freeze_inputs(bpy, buildings, furniture)
                hashes[native.name] = 'changed'
                with self.assertRaisesRegex(ValueError, 'immutable bound V14'):
                    e._freeze_inputs(bpy, buildings, furniture)


class Matrix:
    def __matmul__(self, point): return tuple(point)
    def inverted(self): return self


class FakeMesh:
    def __init__(self, name, components):
        self.name = name; self.users = 1; self.shape_keys = None
        self.vertices = [SimpleNamespace(co=tuple(p)) for c in components for p in c['points']]
    def update(self): pass


class FakeObject:
    def __init__(self, name, components):
        self.name = name; self.type = 'MESH'; self.data = FakeMesh(name, components); self.matrix_world = Matrix()


class TransactionTests(unittest.TestCase):
    def exercise(self, inject_failure=False):
        table, _ = e._recipes(); components = fixture(table)
        objects = {name: FakeObject(name, parts) for name, parts in components.items()}
        label = SimpleNamespace(name=e.SIGN, data=SimpleNamespace(size=.21), location=[-132.34, -78., 9.566389])
        objects[e.SIGN] = label
        bpy = SimpleNamespace(data=SimpleNamespace(objects=objects),
                              context=SimpleNamespace(view_layer=SimpleNamespace(update=lambda: None)))
        original_helper = e._helper()
        def current_components(ob):
            return [{**c, 'points': [tuple(ob.data.vertices[i].co) for i in c['indices']],
                     'bounds': e._bounds([tuple(ob.data.vertices[i].co) for i in c['indices']])}
                    for c in components[ob.name]]
        helper = SimpleNamespace(_Recorder=original_helper._Recorder, _matches=original_helper._matches,
                                 _components=current_components,
                                 _component_hash=lambda ob, c: e._digest({'points': c['points'], 'faces': c['faces'], 'uv': 'unchanged'}))
        snapshots = [0]
        def snapshot(_):
            result = preservation_fixture()
            result['objects'].pop('unrelated')
            for name in objects:
                if name != e.SIGN:
                    result['objects'][name] = {'name': name, 'matrix_world': 'identity', 'ids': 'unchanged'}
            for key in ('matrix_world', 'matrix_local', 'matrix_basis'):
                result['objects'][e.SIGN][key][0][3] = label.location[0]+132.34
            result['meshes'] = {name: {'geometry_sha256': e._digest([tuple(v.co) for v in ob.data.vertices]), 'uv': 'same'}
                                for name, ob in objects.items() if name != e.SIGN}
            snapshots[0] += 1
            if inject_failure and snapshots[0] == 2:
                result['materials']['LT_White'] = 'injected failure after all geometry edits'
            return result
        before = snapshot(bpy); snapshots[0] = 0
        text = {'object': e.SIGN, 'old_size_m': .21, 'new_size_m': .38, 'old_location_m': list(label.location),
                'new_location_m': [-132.32, -78., 9.566389],
                'backing_bounds_m': [[-132.42, -80.45, 9.391389], [-132.34, -75.55, 9.741389]]}
        fake_audit = SimpleNamespace(mesh_fingerprint=lambda ob: {})
        with tempfile.TemporaryDirectory(prefix='town_entry_unit_') as folder:
            with patch.object(e, '_recipes', return_value=(table, {})), \
                 patch.object(e, '_freeze_inputs', return_value=(Path(folder)/'source'/'bound.blend', {})), \
                 patch.object(e, '_support_sampler', return_value=support), \
                 patch.object(e, '_text_plan', return_value=text), \
                 patch.object(e, '_load', return_value=fake_audit), \
                 patch.object(e, '_HELPER', helper), patch.object(e, '_snapshot', side_effect=snapshot), \
                 patch.object(e, '_curve_state', side_effect=lambda curve: {'size': curve.size}), \
                 patch.object(e, '_font_bounds', return_value=[[-132.322, -78.66, 9.4659], [-132.318, -77.34, 9.6669]]), \
                 patch.object(e, '_bound_sources', return_value={}), patch.object(e, '_sha', return_value=e.NATIVE_SHA256), \
                 patch.dict(sys.modules, {'mathutils': SimpleNamespace(Vector=tuple)}):
                output = Path(folder)/'candidate'
                if inject_failure:
                    with self.assertRaisesRegex(RuntimeError, 'material changed'):
                        e.apply({'bpy': bpy}, output, {'buildings': []}, {'objects': {}})
                    self.assertFalse((output/'entry_detail_changes.json').exists())
                    self.assertEqual(snapshot(bpy), before)
                    self.assertEqual(label.data.size, .21)
                    self.assertEqual(list(label.location), [-132.34, -78., 9.566389])
                else:
                    receipt = e.apply({'bpy': bpy}, output, {'buildings': []}, {'objects': {}})
                    self.assertEqual(receipt['preservation_contract']['verified_source_component_count'], 195)
                    self.assertEqual(receipt['preservation_contract']['changed_component_count'], 195)
                    self.assertFalse(receipt['preservation_contract']['original_target_fingerprints_unchanged'])
                    self.assertFalse(receipt['scene_saved']); self.assertFalse(receipt['exported'])
                    self.assertFalse(receipt['whole_town_concept_acceptance'])
                    self.assertEqual(receipt['runtime_clearance_review'], 'PENDING')
                    self.assertTrue((output/'entry_detail_changes.json').is_file())

    def test_success_emits_explicit_new_expectations_without_claiming_art_pass(self):
        self.exercise()

    def test_late_guard_failure_rolls_back_all_coordinates_text_and_success_evidence(self):
        self.exercise(inject_failure=True)


if __name__ == '__main__':
    unittest.main()
