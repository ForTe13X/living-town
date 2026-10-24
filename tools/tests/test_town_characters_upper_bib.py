"""Actual shirt/upper-apron clearance, including emitted lining face interiors."""
import hashlib
import json
import math
from pathlib import Path
import unittest

from tools.town_upgrade.characters.animation import pelvis_height,pose_values
from tools.town_upgrade.characters.apron import ApronPattern
from tools.town_upgrade.characters.assets import fit_asset,geometry_for
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.manifest import BASE_HEIGHT,build_manifest
from tools.town_upgrade.characters.seating import metrics_from_joints
from tools.town_upgrade.characters.seat_corrective import generate_target
from tools.town_upgrade.characters.skinning import deform_points,surface_contact_report

ROOT=Path(__file__).resolve().parents[2]
KEYS=('coco','mei','hua','mian','gui','liu')
CASES=((None,0.),('Idle',.25),('Walk',.125),('Walk',.375),('Walk',.625),('Walk',.875),('Sit',.25),('Lie',.25),('Work',.25),('Talk',.25),('Soak',.25))
# Actual v1 source42d54... mesh layout, before the upper-clearance correction.
# Front-depth Y is deliberately excluded: that is the authorized fit change.
V1_LAYOUT={'coco':'c7e232a2fdfd024743d78a4e89fa8d139a278be3b47c66d14be75fe96fe8b2a9','mei':'c7e232a2fdfd024743d78a4e89fa8d139a278be3b47c66d14be75fe96fe8b2a9','hua':'44cfff5189a7e5c79c8f853ed29a8d68cc22cfa1823226d75bf63c100421c2c8','mian':'c7e232a2fdfd024743d78a4e89fa8d139a278be3b47c66d14be75fe96fe8b2a9','gui':'434499e14b05e924b212b19122558d4f6acbaa48c806af639a6ec9f34c24fb59','liu':'67cff075b62dbd2f18399995d287920c78cafa7bc2fccb2233f4eb33199195da'}
V1_STRAP_ANCHORS={'coco':(.15905327973481695,.17018562068530424),'mei':(.15905327973481695,.17018562068530424),'hua':(.16396011042200803,.21499238951348362),'mian':(.15905327973047223,.17018163173615475),'gui':(.16419992266949907,.21624312190495865),'liu':(.1645307788673391,.21681224976684416)}


def fitted_fixture(key,pattern_class=ApronPattern):
    look=build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters'][key]
    body=adapted_body(look);garment=fit_asset(body,'clothes',look['outfit_asset']);shoe=fit_asset(body,'clothes',look['shoe_asset']);scale=look['body_height_m']/BASE_HEIGHT
    sole={side:min(p[2] for p in shoe['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
    metrics=metrics_from_joints(body['joints'],sole)
    pants,_,source_ids=geometry_for(garment,'pants');faces=[tuple(source_ids[i] for i in face) for face in pants[1]]
    target,report=generate_target(garment['positions'],faces,garment['weights'],body['joints'],metrics,scale=scale)
    if not report['success']:raise ValueError('Existing seat-contact guard failed: '+key)
    garment['seat_contact_target']=target;pattern=pattern_class(garment)
    joints={**body['joints'],**pattern.joints(body['joints'],seat_kinematics=metrics,stature_scale=scale)}
    return look,garment,pattern,joints,metrics


def upper_clearance(fixture,clip,phase):
    look,garment,pattern,joints,metrics=fixture;scale=look['body_height_m']/BASE_HEIGHT
    geometry,weights=pattern.surface();vertices,faces,_=geometry;n=len(vertices)//2
    chosen=[face for face in faces if max(face)<n and all(vertices[i][2]>=1.04-1e-9 for i in face)]
    selected=sorted({i for face in chosen for i in face});remap={i:j for j,i in enumerate(selected)}
    # Test the inside lining rather than merely the visible front surface.
    outer=[vertices[n+i] for i in selected];outer_weights=[weights[n+i] for i in selected]
    outer_faces=[tuple(remap[i] for i in face) for face in chosen]
    shirt_ids=set(geometry_for(garment,'shirt')[2])
    core={i for i in shirt_ids if 1.005<garment['unposed'][i][2]<1.34 and sum(v for k,v in garment['weights'][i].items() if k.startswith(('UpperArm','Forearm','Hand')))<.2}
    shirt_faces=[face for face in garment['faces'] if all(i in core for i,t in face)]
    poses=pose_values(clip,phase,seat_metrics=metrics,stature_scale=scale) if clip else None
    pelvis=pelvis_height(clip,phase,joints['PelvisRoot'][2],1.,seat_metrics=metrics,stature_scale=scale) if clip else None
    source=garment['seat_contact_target'] if clip in ('Sit','Soak') else garment['positions']
    outer=deform_points(outer,outer_weights,joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=scale)
    inner=deform_points(source,garment['weights'],joints,clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=scale)
    return surface_contact_report(outer,inner,shirt_faces,outer_faces=outer_faces,axis=2 if clip=='Lie' else 1,minimum_clearance=.002,interior_samples=3,max_examples=3)


def layout_fingerprint(pattern):
    geometry,weights=pattern.surface();vertices,faces,uv=geometry
    record={'xz':[(x,z) for x,y,z in vertices],'faces':faces,'uv':uv,'weights':weights}
    return hashlib.sha256(json.dumps(record,sort_keys=True,separators=(',',':')).encode()).hexdigest()


class UpperBibTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.fixtures={key:fitted_fixture(key) for key in KEYS}

    def test_all_six_actual_shirts_clear_the_upper_lining_in_rest_and_every_pose(self):
        for key,fixture in self.fixtures.items():
            for clip,phase in CASES:
                with self.subTest(persona=key,clip=clip or 'Rest',phase=phase):
                    report=upper_clearance(fixture,clip,phase)
                    self.assertGreater(report['matched_samples'],2500)
                    self.assertEqual(report['violation_samples'],0,report)
                    self.assertGreaterEqual(report['minimum_clearance_m'],.002,report)

    def test_upper_fit_is_smooth_symmetric_and_does_not_add_shirt_feature_imprints(self):
        for key,fixture in self.fixtures.items():
            pattern=fixture[2]
            for x in (-.06,0.,.06):
                values=[pattern.front(x,1.035+i*.0025) for i in range(103)]
                curvature=max(abs(values[i-1]-2*values[i]+values[i+1]) for i in range(1,len(values)-1))
                self.assertLess(curvature,.00025,(key,x,curvature))
                # Keep the existing broad-cloth guard over the entire bib,
                # including its return to the unchanged shoulder attachment.
                values=[pattern.front(x,1.+i*.005) for i in range(61)]
                curvature=max(abs(values[i-1]-2*values[i]+values[i+1]) for i in range(1,len(values)-1))
                self.assertLess(curvature,.00035,(key,x,'5mm upper longitudinal second difference'))
            for z in (1.05,1.1,1.15,1.2,1.25,1.29):
                for x in (.02,.05,.08):self.assertAlmostEqual(pattern.front(x,z),pattern.front(-x,z),places=10)

    def test_all_six_keep_v1_topology_uv_weights_and_cutting_layout(self):
        for key,fixture in self.fixtures.items():
            with self.subTest(persona=key):self.assertEqual(layout_fingerprint(fixture[2]),V1_LAYOUT[key])

    def test_strap_anchors_keep_their_geometry_and_cumulative_metric_uv(self):
        # The builder uses these points in the shoulder/waist ribbon paths.
        # Keeping them exact preserves ribbon geometry and length-based UVs.
        for key,fixture in self.fixtures.items():
            pattern=fixture[2];shoulder,waist=V1_STRAP_ANCHORS[key]
            for sign in (-1,1):
                self.assertAlmostEqual(pattern.front(sign*.078,1.28),shoulder,places=12)
                self.assertAlmostEqual(pattern.front(sign*.137,.995),waist,places=12)


if __name__=='__main__':unittest.main()
