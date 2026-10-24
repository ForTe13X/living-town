"""Source-space FK/LBS and directional cloth clearance regression checks."""
import math
import json
from pathlib import Path
import unittest

from tools.town_upgrade.characters.skinning import deform_points,pose_transforms,source_rotation,surface_contact_report,surface_envelope_report


class CharacterSkinningTests(unittest.TestCase):
    def setUp(self):
        self.joints={'PelvisRoot':(0.,0.,1.),'Thigh_L':(.1,0.,1.),'Shin_L':(.1,0.,.55),'Foot_L':(.1,0.,.1),
                     'ApronDrape':(0.,0.,1.),'ApronHem':(0.,0.,.55)}
        self.parents={'PelvisRoot':None,'Thigh_L':'PelvisRoot','Shin_L':'Thigh_L','Foot_L':'Shin_L',
                      'ApronDrape':'PelvisRoot','ApronHem':'ApronDrape'}

    def assertPoint(self,a,b,places=10):
        for x,y in zip(a,b):self.assertAlmostEqual(x,y,places=places)

    def test_rest_lbs_is_identity_including_blended_optional_bones(self):
        points=[(.02,.13,.8),(.13,.03,.23),(-.1,.1,.65)]
        weights=[{'PelvisRoot':.25,'ApronDrape':.75},{'Shin_L':.6,'Foot_L':.4},{'ApronDrape':.3,'ApronHem':.7}]
        for a,b in zip(points,deform_points(points,weights,self.joints,self.parents)):self.assertPoint(a,b)

    def test_source_euler_axis_conversion_faces_up_and_lifts_seated_leg(self):
        rotation=source_rotation((math.pi/2,0.,0.))
        def apply(p):return tuple(sum(rotation[i][k]*p[k] for k in range(3)) for i in range(3))
        self.assertPoint(apply((0.,1.,0.)),(0.,0.,1.)) # Blender front faces upward.
        self.assertPoint(apply((0.,0.,-1.)),(0.,1.,0.)) # A downward leg lifts forward.
        rotation=source_rotation((0.,0.,math.pi/2))
        self.assertPoint(tuple(rotation[i][0] for i in range(3)),(0.,0.,1.)) # Engine Z -> source -Y.

    def test_joint_segment_lengths_survive_fk_and_hem_inherits_drape(self):
        transforms=pose_transforms(self.joints,self.parents,'Sit',.25,poses={'ApronHem':(-math.pi/2,0.,0.)})
        for name,parent in self.parents.items():
            if parent is None:continue
            old=math.dist(self.joints[name],self.joints[parent]);new=math.dist(transforms[name]['position'],transforms[parent]['position'])
            self.assertAlmostEqual(old,new,places=10)
        self.assertPoint(transforms['Shin_L']['position'],(.1,.45,.52))
        self.assertPoint(transforms['Foot_L']['position'],(.1,.45,.07))
        self.assertPoint(transforms['ApronHem']['position'],(0.,.45,.52))
        # ApronHem counterrotation keeps lower cloth vertical, matching knees.
        self.assertPoint(deform_points([(0.,.02,.35)],[{'ApronHem':1.}],self.joints,self.parents,'Sit',.25,poses={'ApronHem':(-math.pi/2,0.,0.)})[0],(0.,.47,.32))

    def test_invalid_weights_and_cycles_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'sum'):deform_points([(0,0,0)],[{'PelvisRoot':.4}],self.joints,self.parents)
        with self.assertRaisesRegex(ValueError,'Unknown'):deform_points([(0,0,0)],[{'Missing':1}],self.joints,self.parents)
        parents=dict(self.parents);parents['PelvisRoot']='ApronDrape'
        with self.assertRaisesRegex(ValueError,'Cyclic'):pose_transforms(self.joints,parents)

    def test_actual_adapted_native_garment_preserves_rest_and_all_joint_lengths(self):
        from tools.town_upgrade.characters.assets import fit_asset
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.manifest import build_manifest,CLIPS
        root=Path(__file__).resolve().parents[2]
        manifest=build_manifest(json.loads((root/'game/data/personas.json').read_text(encoding='utf-8')))
        for key in ['aria','ben']:
            body=adapted_body(manifest['characters'][key]);garment=fit_asset(body,'clothes',manifest['characters'][key]['outfit_asset'])
            from tools.town_upgrade.characters.skinning import default_parents
            parents=default_parents(body['joints'])
            # Sample across the entire authored vertex ordering, including
            # shoulder/cuff, belt, crotch, knee and hem mapping influences.
            points=garment['positions'][::37];weights=garment['weights'][::37]
            rest=deform_points(points,weights,body['joints'],parents)
            for a,b in zip(points,rest):self.assertPoint(a,b)
            for clip in CLIPS:
                posed=pose_transforms(body['joints'],parents,clip,.25)
                for name,parent in parents.items():
                    if parent is not None:self.assertAlmostEqual(math.dist(posed[name]['position'],posed[parent]['position']),math.dist(body['joints'][name],body['joints'][parent]),places=9)
                result=deform_points(points,weights,body['joints'],parents,clip,.25)
                self.assertTrue(all(math.isfinite(v) for p in result for v in p))

    def test_barycentric_surface_clearance_detects_crossing_between_vertices(self):
        inner=[(-1.,0.,0.),(1.,0.,0.),(1.,0.,1.),(-1.,0.,1.)]
        outer=[(-.5,.02,.1),(.5,.02,.1),(.5,.02,.9),(-.5,.02,.9)]
        report=surface_contact_report(outer,inner,[(0,1,2,3)],outer_faces=[(0,1,2,3)],minimum_clearance=.01)
        self.assertEqual(report['violation_samples'],0);self.assertEqual(report['matched_samples'],6)
        self.assertAlmostEqual(report['minimum_clearance_m'],.02)
        # A protruding inner triangle is wholly inside the outer quad, so all
        # four outer vertices are clear but a face-interior sample penetrates.
        peak=[(-.4,.09,.3),(.4,.09,.3),(0.,.09,.7)]
        report=surface_contact_report(outer,inner+peak,[(0,1,2,3),(4,5,6)],outer_faces=[(0,1,2,3)],interior_samples=3)
        self.assertGreater(report['violation_samples'],0)
        self.assertTrue(any(sample['outer_kind']=='face' for sample in report['worst_samples']))

    def test_seated_lap_and_walk_cloth_clearance_use_actual_deformed_surfaces(self):
        # A small thigh top patch and an apron 20 mm forward use corresponding
        # hip controls. Seated rotation turns front clearance into +Z clearance.
        inner=[(-.08,0.,.68),(.08,0.,.68),(.08,0.,.90),(-.08,0.,.90)]
        outer=[(x,y+.02,z) for x,y,z in inner];face=[(0,1,2,3)]
        for clip,phase,axis in [('Sit',.25,2),('Walk',.125,1),('Walk',.375,1)]:
            pose={'ApronDrape':(math.pi/2 if clip=='Sit' else math.sin(phase*math.tau)*.47,0.,0.)}
            inner_pose=deform_points(inner,[{'Thigh_L':1.}]*4,self.joints,self.parents,clip,phase,poses=pose)
            outer_pose=deform_points(outer,[{'ApronDrape':1.}]*4,self.joints,self.parents,clip,phase,poses=pose)
            report=surface_contact_report(outer_pose,inner_pose,face,outer_faces=face,axis=axis,minimum_clearance=.019)
            self.assertGreater(report['matched_samples'],0)
            self.assertEqual(report['violation_samples'],0)
            self.assertGreaterEqual(report['minimum_clearance_m'],.019)

    def test_seated_envelope_accepts_front_waist_without_inflating_it_above_lap(self):
        # A cube's front Y=0 and top Z=1. A point can be outside the front while
        # below the top: the waist must not be inflated above it unnecessarily.
        inner=[(-1,-1,0),(1,-1,0),(1,0,0),(-1,0,0),(-1,-1,1),(1,-1,1),(1,0,1),(-1,0,1)]
        faces=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        report=surface_envelope_report([(0,.02,.9),(0,-.01,.99)],inner,faces,minimum_clearance=.005)
        self.assertEqual(report['matched_samples'],2)
        self.assertEqual(report['violation_samples'],1)
        self.assertAlmostEqual(report['minimum_clearance_m'],-.01)

    def test_actual_apron_clears_seated_jeans_and_hem_hangs_at_the_knee(self):
        from tools.town_upgrade.characters.assets import fit_asset,geometry_for
        from tools.town_upgrade.characters.human import adapted_body
        from tools.town_upgrade.characters.manifest import build_manifest
        from tools.town_upgrade.characters.apron import ApronPattern
        root=Path(__file__).resolve().parents[2]
        manifest=build_manifest(json.loads((root/'game/data/personas.json').read_text(encoding='utf-8')))
        from tools.town_upgrade.characters.seating import metrics_from_joints
        from tools.town_upgrade.characters.seat_corrective import generate_target
        from tools.town_upgrade.characters.manifest import BASE_HEIGHT
        for key in ['aria','ben','coco','tie','lin']:
            body=adapted_body(manifest['characters'][key]);garment=fit_asset(body,'clothes',manifest['characters'][key]['outfit_asset'])
            footwear=fit_asset(body,'clothes',manifest['characters'][key]['shoe_asset'])
            soles={side:min(p[2] for p in footwear['positions'] if (p[0]>0)==(side=='L')) for side in ['L','R']}
            metrics=metrics_from_joints(body['joints'],soles)
            if garment['name']=='male_worksuit01':metrics['pelvis_contact_allowance_m']=.005
            pants,_,source_ids=geometry_for(garment,'pants')
            pants_faces=[tuple(source_ids[i] for i in face) for face in pants[1]]
            target,contact=generate_target(garment['positions'],pants_faces,garment['weights'],body['joints'],metrics,scale=manifest['characters'][key]['body_height_m']/BASE_HEIGHT)
            self.assertTrue(contact['success'],(key,contact))
            garment['seat_contact_target']=target
            pattern=ApronPattern(garment);joints={**body['joints'],**pattern.joints(body['joints'],seat_kinematics=metrics,stature_scale=manifest['characters'][key]['body_height_m']/BASE_HEIGHT)}
            # Reject the V9 wax-like vertex ripples: the ruled source should
            # have broad curvature, a symmetric cross-section and a tidy pocket.
            sample=[pattern.front(0,.45+i*.005) for i in range(155)]
            curvature=max(abs(sample[i-1]-2*sample[i]+sample[i+1]) for i in range(1,len(sample)-1))
            self.assertLess(curvature,.00035,(key,'5mm longitudinal second difference'))
            for z in [.6,.8,.9,1.1]:
                for x in [.02,.05,.08]:self.assertAlmostEqual(pattern.front(x,z),pattern.front(-x,z),places=10)
            gaps=[pattern.pocket_front(x,z)-pattern.front(x,z) for z in [.805+i*.005 for i in range(21)] for x in [-.064+i*.0064 for i in range(21)]]
            self.assertGreater(min(gaps),.0015)
            self.assertLess(max(gaps),.007)
            self.assertLess(pattern.width(.375),pattern.width(.6))
            self.assertEqual(pattern.fit_report['independent_cross_section_columns'],0)
            self.assertTrue(pattern.fit_report['seat_contact_target_used'])
            self.assertEqual(set(pattern.fit_report['cases']),{'Sit_0.25','Sit_runtime_0.25','Soak_0.25','Walk_0.125','Walk_0.25','Walk_0.625','Walk_0.75'})
            self.assertAlmostEqual(pattern.fit_report['post_fit_clearance_margin_m'],.0015)
            for name,case in pattern.fit_report['cases'].items():
                self.assertGreater(case['matched_samples'],2500,(key,name))
                self.assertGreaterEqual(case['minimum_clearance_m'],.005,(key,name))
                self.assertEqual(case['violation_samples'],0,(key,name))
            geometry,weights=pattern.surface();vertices=geometry[0];solution=pattern.fit_report['seating_solutions']['Sit'];poses=solution['poses'];pelvis_z=solution['source_pelvis_height_m']
            apron=deform_points(vertices,weights,joints,clip='Sit',phase=.25,poses=poses,pelvis_z=pelvis_z)
            jeans=deform_points(target,garment['weights'],joints,clip='Sit',phase=.25,poses=poses,pelvis_z=pelvis_z)
            hem=[apron[i] for i,p in enumerate(vertices) if p[2]<.4]
            knee_front=max(jeans[i][1] for i,p in enumerate(garment['unposed']) if .4<p[2]<.53)
            self.assertLessEqual(max(p[1] for p in hem),knee_front+.04)
            posed_joints=pose_transforms(joints,clip='Sit',phase=.25,poses=poses,pelvis_z=pelvis_z)
            drop=posed_joints['ApronHem']['position'][2]-min(p[2] for p in hem)
            self.assertGreater(drop,.065);self.assertLess(drop,.13)
            # Optional controls remain available on residents without an apron,
            # but their build does not spend time solving unused cloth.
            no_fit=ApronPattern(garment);controls=no_fit.joints(body['joints'],fit=False)
            self.assertEqual(set(controls),{'ApronDrape','ApronHem'})
            self.assertFalse(no_fit.fit_report['enabled'])
            json.dumps(pattern.fit_report) # Saved build provenance must be portable.


if __name__=='__main__':unittest.main()
