"""Same-topology inverse-LBS seat corrective checks; no engine imports."""
import json
import math
from pathlib import Path
import unittest

from tools.town_upgrade.characters.seat_corrective import clipped_seat_report,generate_target
from tools.town_upgrade.characters.seating import metrics_from_joints


class SeatCorrectiveTests(unittest.TestCase):
    def test_triangle_clipping_finds_penetration_without_inboard_vertices(self):
        points=[(-.5,-.1,.46),(.5,-.1,.46),(0,.5,.46)]
        report=clipped_seat_report(points,[[(0,0),(1,1),(2,2)]])
        self.assertFalse(report['success']);self.assertAlmostEqual(report['minimum_clipped_triangle_clearance_m'],-.002)
        self.assertEqual(report['triangles_intersecting_seat_volume'],1)

    def test_actual_hero_pants_clear_fixed_seat_within_40mm_and_keep_knees(self):
        from tools.town_upgrade.characters.manifest import build_manifest,BASE_HEIGHT
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.assets import fit_asset,geometry_for
        root=Path(__file__).resolve().parents[2];manifest=build_manifest(json.loads((root/'game/data/personas.json').read_text(encoding='utf-8')))
        for key in ('aria','ben'):
            look=manifest['characters'][key];body=adapted_body(look);garment=fit_asset(body,'clothes',look['outfit_asset']);geometry,_,ids=geometry_for(garment,'pants')
            faces=[tuple(ids[i] for i in face) for face in geometry[1]];before=garment['positions'][:]
            target,report=generate_target(before,faces,garment['weights'],body['joints'],metrics_from_joints(body['joints']),scale=look['body_height_m']/BASE_HEIGHT)
            self.assertEqual(len(target),len(before));self.assertEqual(before,garment['positions'])
            self.assertTrue(report['success'],(key,report))
            self.assertLessEqual(report['maximum_posed_displacement_m'],.040000001)
            self.assertEqual(report['maximum_protected_knee_lower_leg_motion_m'],0.)
            self.assertEqual(set(report['cases']),{'native','runtime','soak_90'})
            for case in ('native','runtime'):
                self.assertGreater(report['cases'][case]['post']['clipped_triangle_count'],100)
                self.assertGreaterEqual(report['cases'][case]['post']['minimum_clipped_triangle_clearance_m'],.001-1e-8)
                self.assertEqual(report['cases'][case]['post']['triangles_intersecting_seat_volume'],0)
            self.assertTrue(all(math.isfinite(v) for p in target for v in p));json.dumps(report)

    def test_too_small_cap_is_reported_without_unbounded_geometry(self):
        from tools.town_upgrade.characters.manifest import build_manifest
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.assets import fit_asset,geometry_for
        root=Path(__file__).resolve().parents[2];manifest=build_manifest(json.loads((root/'game/data/personas.json').read_text(encoding='utf-8')))
        body=adapted_body(manifest['characters']['aria']);garment=fit_asset(body,'clothes','male_casualsuit01');geometry,_,ids=geometry_for(garment,'pants');faces=[tuple(ids[i] for i in face) for face in geometry[1]]
        _,report=generate_target(garment['positions'],faces,garment['weights'],body['joints'],metrics_from_joints(body['joints']),max_posed_displacement_m=.005)
        self.assertFalse(report['success']);self.assertLessEqual(report['maximum_posed_displacement_m'],.005000001)

    def test_workwear_contact_allowance_and_child_dangling_preserve_bounded_topology(self):
        from tools.town_upgrade.characters.manifest import build_manifest,BASE_HEIGHT
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.assets import fit_asset,geometry_for
        for key in ('tie','dou'):
            look=build_manifest()['characters'][key];body=adapted_body(look);garment=fit_asset(body,'clothes',look['outfit_asset']);shoes=fit_asset(body,'clothes',look['shoe_asset'])
            soles={side:min(p[2] for p in shoes['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
            metrics=metrics_from_joints(body['joints'],soles)
            if key=='tie':metrics['pelvis_contact_allowance_m']=.005
            else:metrics['seating_policy']='child_natural_dangling'
            geometry,_,ids=geometry_for(garment,'pants');faces=[tuple(ids[i] for i in face) for face in geometry[1]]
            target,report=generate_target(garment['positions'],faces,garment['weights'],body['joints'],metrics,scale=look['body_height_m']/BASE_HEIGHT)
            self.assertTrue(report['success'],(key,report));self.assertEqual(len(target),len(garment['positions']))
            self.assertLessEqual(report['maximum_posed_displacement_m'],.040000001)
            self.assertEqual(report['maximum_protected_knee_lower_leg_motion_m'],0.)
            native=report['cases']['native'];runtime=report['cases']['runtime']
            self.assertAlmostEqual(native['post']['minimum_clipped_triangle_clearance_m'],runtime['post']['minimum_clipped_triangle_clearance_m'],places=10)
            self.assertEqual(native['post']['triangles_intersecting_seat_volume'],0)
            if key=='dou':
                self.assertEqual(report['maximum_posed_displacement_m'],0.)
                self.assertGreater(native['solution']['legs']['L']['sole_gap_m'],.1)
                self.assertEqual(native['solution']['legs']['L']['contact_status'],'intentional_dangling')
            else:self.assertAlmostEqual(native['solution']['pelvis_contact_allowance_m'],.005)


if __name__=='__main__':unittest.main()
