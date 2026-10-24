"""Upper footwear must remain underneath the trousers it actually overlaps."""
import json
import math
from pathlib import Path
import unittest

from tools.town_upgrade.characters.animation import pelvis_height,pose_values
from tools.town_upgrade.characters.assets import fit_asset,geometry_for
from tools.town_upgrade.characters.footwear import fit_upper_cuff
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.manifest import BASE_HEIGHT,build_manifest
from tools.town_upgrade.characters.seating import metrics_from_joints
from tools.town_upgrade.characters.skinning import ProjectedSurface,deform_points

ROOT=Path(__file__).resolve().parents[2]


def fixture(key):
    look=build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters'][key]
    body=adapted_body(look);garment=fit_asset(body,'clothes',look['outfit_asset']);raw=fit_asset(body,'clothes',look['shoe_asset'])
    fitted=fit_upper_cuff(raw,garment,body['joints'])
    return look,body,garment,raw,fitted


def upper_cuff_clearance(value,clip=None,phase=0.):
    """Independently query actual posed triangles along four cardinal rays.

    The lower shoe, laces and exposed heel are intentionally outside this
    under-trouser check. The confirmed erroneous ankle polygons are above
    0.14 m in the normalized source mesh for both footwear assets.
    """
    look,body,garment,raw,fitted=value;scale=look['body_height_m']/BASE_HEIGHT
    sole={side:min(p[2] for p in fitted['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
    metrics=metrics_from_joints(body['joints'],sole)
    poses=pose_values(clip,phase,seat_metrics=metrics,stature_scale=scale) if clip else None
    pelvis=pelvis_height(clip,phase,body['joints']['PelvisRoot'][2],1.,seat_metrics=metrics,stature_scale=scale) if clip else None
    pants,weights,_=geometry_for(garment,'pants')
    posed_pants=deform_points(pants[0],weights,body['joints'],clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=scale)
    posed_shoes=deform_points(fitted['positions'],fitted['weights'],body['joints'],clip=clip,phase=phase,poses=poses,pelvis_z=pelvis,scale=scale)
    gaps=[];matched=0;unmatched=0
    for sign in (-1,1):
        # Keep every original leg face. Cropping by all vertex heights opens
        # the tube through triangles spanning the crop and gives false hits
        # when a high-stride projection crosses that artificial boundary.
        calf_faces=[face for face in pants[1] if all(pants[0][i][0]*sign>0 for i in face)]
        upper_faces=[face for face in fitted['faces'] if all(raw['positions'][i][0]*sign>0 and raw['positions'][i][2]>.14 for i,t in face)]
        ids=sorted({i for face in upper_faces for i,t in face});samples=[posed_shoes[i] for i in ids]
        for face in upper_faces:
            vertices=[i for i,t in face]
            for n in range(1,len(vertices)-1):
                triangle=[vertices[0],vertices[n],vertices[n+1]]
                samples.append(tuple(sum(posed_shoes[i][k] for i in triangle)/3 for k in range(3)))
        # Lying rotates the calf axis onto Y, so its cross-section is X/Z.
        axes=(0,2) if clip=='Lie' else (0,1)
        for axis,direction in ((axis,direction) for axis in axes for direction in (-1,1)):
            surface=ProjectedSurface(posed_pants,calf_faces,axis,direction)
            for point in samples:
                depth,_=surface.depth_at(point)
                if depth is None:unmatched+=1;continue
                matched+=1;gaps.append(depth-point[axis]*direction)
    return {'minimum_clearance_m':min(gaps) if gaps else None,'matched_samples':matched,'unmatched_samples':unmatched,'negative_samples':sum(value<-.00001 for value in gaps)}


class FootwearCuffTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures={key:fixture(key) for key in build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters']}

    def test_confirmed_shoe_upper_polygons_no_longer_show_through_trousers(self):
        # These are the exact actual V2 ray hits whose gray shoe UV pixels
        # explain the visible calf patches, not guesses from a fit formula.
        for key,x,z in [('coco',.1225,.175),('ben',.07,.165),('dou',.1075,.1775)]:
            value=self.fixtures[key];pants=geometry_for(value[2],'pants')[0]
            trousers=ProjectedSurface(pants[0],pants[1]);before=ProjectedSurface(value[3]['positions'],value[3]['faces']);after=ProjectedSurface(value[4]['positions'],value[4]['faces'])
            point=(x,0.,z);limit,_=trousers.depth_at(point);old,_=before.depth_at(point);new,_=after.depth_at(point)
            self.assertGreater(old-limit,.002,key)
            if new is not None:self.assertGreater(limit-new,.0003,key)

    def test_all_cast_keep_original_mesh_contract_and_lower_footwear(self):
        for key,value in self.fixtures.items():
            raw,fitted=value[3:];report=fitted['upper_cuff_fit'];protected=report['protected_lower_z_m']
            self.assertTrue(report['success'],(key,report['after']))
            self.assertEqual(len(raw['positions']),len(fitted['positions']),key)
            for field in ('faces','uv','weights','unposed','mapping','deleted','authored_weights'):
                self.assertEqual(raw[field],fitted[field],(key,field))
            self.assertTrue(all(math.isfinite(v) for p in fitted['positions'] for v in p),key)
            sizes={component:list(raw['components'].values()).count(component) for component in set(raw['components'].values())}
            main_shoes=set(sorted(sizes,key=sizes.get,reverse=True)[:2])
            for index,(old,new) in enumerate(zip(raw['positions'],fitted['positions'])):
                self.assertEqual(old[2],new[2],(key,'source Z and contact height'))
                if old[2]<=protected or raw['components'][index] in main_shoes:
                    self.assertEqual(old,new,(key,'protected complete shoe/sole/toe/laces'))
            self.assertEqual(min(p[2] for p in raw['positions']),min(p[2] for p in fitted['positions']),key)
            json.dumps(report)

    def test_actual_upper_cuffs_are_inside_trouser_calves_at_rest_and_motion(self):
        contexts=[(None,0.),('Idle',.25),('Walk',.125),('Walk',.25),('Walk',.375),('Walk',.625),('Walk',.75),('Walk',.875),('Sit',.25),('Lie',.25),('Work',.25),('Talk',.25),('Soak',.25)]
        cases=[(key,clip,phase) for key in self.fixtures for clip,phase in contexts]
        for key,clip,phase in cases:
            with self.subTest(persona=key,clip=clip or 'Rest',phase=phase):
                report=upper_cuff_clearance(self.fixtures[key],clip,phase)
                self.assertGreater(report['matched_samples'],200)
                self.assertEqual(report['negative_samples'],0,report)


if __name__=='__main__':unittest.main()
