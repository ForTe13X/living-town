"""Metric chair contact checks without Blender/Godot dependencies."""
import json
import math
from pathlib import Path
import unittest

from tools.town_upgrade.characters.seating import metrics_from_joints,poses_for,solve,sole_height
from tools.town_upgrade.characters.skinning import deform_points


class SeatedContactTests(unittest.TestCase):
    def test_analytic_solution_keeps_shoe_flat_and_rest_knee_offset_is_not_ignored(self):
        joints={'PelvisRoot':(0,0,.88),'Thigh_L':(.1,0,.88),'Shin_L':(.1,.03,.46),'Foot_L':(.1,.02,.06),
                'Thigh_R':(-.1,0,.88),'Shin_R':(-.1,.03,.46),'Foot_R':(-.1,.02,.06)}
        metrics=metrics_from_joints(joints,0.);result=solve(metrics,.462,1.,.025)
        self.assertTrue(result['reachable']);self.assertLess(result['maximum_absolute_sole_gap_m'],1e-10)
        self.assertLess(result['legs']['L']['thigh_radians'],math.pi/2)
        self.assertAlmostEqual(result['legs']['L']['thigh_radians']+result['legs']['L']['shin_radians'],0.)
        old=sole_height(metrics,'L',math.pi/2,result['source_pelvis_height_m'],root_floor_offset_m=.025)
        self.assertGreater(old,.08)
        for side,sign in [('L',1),('R',-1)]:
            foot=joints['Foot_'+side];point=(foot[0],foot[1],0.)
            posed=deform_points([point],[{'Foot_'+side:1.}],joints,clip='Sit',phase=.25,poses=result['poses'],pelvis_z=result['source_pelvis_height_m'])[0]
            self.assertAlmostEqual(.025+posed[2],0.,places=10)
        json.dumps(metrics);json.dumps(result)

    def test_actual_roster_statures_and_floor_offsets_reach_a_standard_chair(self):
        from tools.town_upgrade.characters.manifest import build_manifest,BASE_HEIGHT
        from tools.town_upgrade.characters.human import adapted_body
        root=Path(__file__).resolve().parents[2]
        manifest=build_manifest(json.loads((root/'game/data/personas.json').read_text(encoding='utf-8')))
        for key,look in manifest['characters'].items():
            body=adapted_body(look);metrics=metrics_from_joints(body['joints'],0.);scale=look['body_height_m']/BASE_HEIGHT
            for offset in (0.,.025):
                result=solve(metrics,.462,scale,offset)
                self.assertTrue(result['reachable'],key)
                self.assertLess(result['maximum_absolute_sole_gap_m'],1e-9,key)
                for side in ('L','R'):
                    self.assertGreater(result['legs'][side]['thigh_radians'],0.)
                    self.assertLess(result['legs'][side]['thigh_radians'],math.pi/2)

    def test_nonzero_authored_sole_height_and_different_sides_are_preserved(self):
        joints={'PelvisRoot':(0,0,.88),'Thigh_L':(.1,0,.88),'Shin_L':(.1,.03,.46),'Foot_L':(.1,.02,.06),
                'Thigh_R':(-.1,0,.88),'Shin_R':(-.1,.02,.455),'Foot_R':(-.1,.02,.06)}
        metrics=metrics_from_joints(joints,{'L':.003,'R':.007});result=solve(metrics)
        self.assertNotEqual(result['legs']['L']['thigh_radians'],result['legs']['R']['thigh_radians'])
        self.assertLess(result['maximum_absolute_sole_gap_m'],1e-10)
        self.assertEqual(poses_for(metrics),result['poses'])

    def test_native_and_runtime_coordinate_frames_have_identical_world_geometry(self):
        joints={'PelvisRoot':(0,0,.88),'Thigh_L':(.1,0,.88),'Shin_L':(.1,.03,.46),'Foot_L':(.1,.02,.06),
                'Thigh_R':(-.1,0,.88),'Shin_R':(-.1,.03,.46),'Foot_R':(-.1,.02,.06)}
        metrics=metrics_from_joints(joints,0.);scale=1.07
        points=[(.08,.07,.86),(.1,.06,.52),(.1,.09,.025)]
        weights=[{'PelvisRoot':.25,'Thigh_L':.75},{'Thigh_L':.65,'Shin_L':.35},{'Foot_L':1.}]
        worlds=[]
        for offset in (0.,.025):
            result=solve(metrics,.462,scale,offset)
            self.assertAlmostEqual(result['pelvis_world_height_m'],.462+.06*scale+.025)
            posed=deform_points(points,weights,joints,clip='Sit',phase=.25,poses=result['poses'],pelvis_z=result['source_pelvis_height_m'])
            worlds.append([(p[0]*scale,p[1]*scale,p[2]*scale+offset) for p in posed])
        for native,runtime in zip(*worlds):
            for a,b in zip(native,runtime):self.assertAlmostEqual(a,b,places=11)

    def test_unreachable_high_seat_is_reported_and_invalid_inputs_fail(self):
        joints={'PelvisRoot':(0,0,.88),'Thigh_L':(.1,0,.88),'Shin_L':(.1,.03,.46),'Foot_L':(.1,.02,.06),
                'Thigh_R':(-.1,0,.88),'Shin_R':(-.1,.03,.46),'Foot_R':(-.1,.02,.06)}
        metrics=metrics_from_joints(joints);result=solve(metrics,1.5)
        self.assertFalse(result['reachable']);self.assertGreater(result['maximum_absolute_sole_gap_m'],.1)
        with self.assertRaises(ValueError):solve(metrics,scale=0.)
        with self.assertRaises(ValueError):solve(metrics,seat_height_m=float('nan'))

    def test_dou_natural_child_policy_keeps_thigh_level_and_reports_intentional_dangling(self):
        from tools.town_upgrade.characters.assets import fit_asset
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.manifest import build_manifest,BASE_HEIGHT
        look=build_manifest()['characters']['dou'];body=adapted_body(look);shoes=fit_asset(body,'clothes',look['shoe_asset'])
        soles={side:min(p[2] for p in shoes['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
        metrics=metrics_from_joints(body['joints'],soles);metrics['seating_policy']='child_natural_dangling'
        scale=look['body_height_m']/BASE_HEIGHT
        for offset in (0.,.025):
            result=solve(metrics,.462,scale,offset)
            self.assertTrue(result['reachable']);self.assertEqual(result['seating_policy'],'child_natural_dangling')
            for side in ('L','R'):
                leg=metrics['legs'][side];posed=result['legs'][side];angle=posed['thigh_radians']
                self.assertAlmostEqual(leg['knee_from_hip_y_m']*math.sin(angle)+leg['knee_from_hip_z_m']*math.cos(angle),0.,places=10)
                self.assertGreater(posed['sole_gap_m'],.07)
                self.assertFalse(posed['ground_contact_required']);self.assertFalse(posed['ground_contact_reachable'])
                self.assertEqual(posed['contact_status'],'intentional_dangling')


if __name__=='__main__':unittest.main()
