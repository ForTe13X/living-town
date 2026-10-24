"""Closed sewn bow, metric linen density and actual nine-persona chair fit."""
from collections import Counter
import json
import math
from pathlib import Path
import statistics
import unittest

from tools.town_upgrade.characters.apron_bow import gathered_bow
from tools.town_upgrade.characters.assets import fit_asset
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.linen import repeat_m
from tools.town_upgrade.characters.manifest import BASE_HEIGHT,build_manifest
from tools.town_upgrade.characters.animation import pelvis_height,pose_values
from tools.town_upgrade.characters.seating import metrics_from_joints
from tools.town_upgrade.characters.skinning import deform_points

ROOT=Path(__file__).resolve().parents[2]


def fixtures():
    looks=build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters'];result={}
    for key,look in looks.items():
        if look['detail'] not in ('apron','leather_apron','paint','sewing','flowers','herbs'):continue
        body=adapted_body(look);garment=fit_asset(body,'clothes',look['outfit_asset']);shoe=fit_asset(body,'clothes',look['shoe_asset'])
        core=[p for p,row in zip(garment['positions'],garment['weights']) if sum(v for k,v in row.items() if k.startswith(('UpperArm','Forearm','Hand')))<.2]
        def back(x,z,core=core):
            values=[p[1] for p in core if abs(p[0]-x)<.04 and abs(p[2]-z)<.05]
            return min(values)-.006 if values else -.12
        scale=look['body_height_m']/BASE_HEIGHT;anchor=(0,back(0,.995)-.003,.989)
        geometry,weights,report=gathered_bow(anchor,back,scale,repeat_m())
        result[key]=(look,body,shoe,geometry,weights,report,scale)
    return result


class ApronBowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.fixtures=fixtures()

    def test_all_nine_bows_are_closed_finite_original_cloth_geometry(self):
        self.assertEqual(len(self.fixtures),9)
        for key,value in self.fixtures.items():
            points,faces,uv=value[3];weights=value[4];report=value[5]
            self.assertEqual(len(points),len(uv));self.assertEqual(len(points),len(weights))
            self.assertTrue(all(math.isfinite(v) for p in points+uv for v in p),key)
            edges=Counter(tuple(sorted((a,b))) for face in faces for a,b in zip(face,face[1:]+face[:1]))
            self.assertTrue(all(count==2 for count in edges.values()),key)
            self.assertEqual(report['parts'],5);self.assertEqual(report['extra_joints'],0)
            self.assertTrue(all(row=={'PelvisRoot':1.} for row in weights))
            self.assertGreater(max(p[0] for p in points)-min(p[0] for p in points),.10)
            self.assertGreater(max(p[1] for p in points)-min(p[1] for p in points),.015)
            self.assertGreater(max(p[2] for p in points)-min(p[2] for p in points),.15)

    def test_linen_repeat_keeps_physical_strip_density_after_persona_scale(self):
        repeat=repeat_m()
        for key,value in self.fixtures.items():
            points,faces,uv=value[3];scale=value[6];ratios=[]
            for face in faces:
                for i,j in zip(face,face[1:]+face[:1]):
                    physical=math.dist(points[i],points[j])*scale
                    metric=math.hypot((uv[i][0]-uv[j][0])*repeat[0],(uv[i][1]-uv[j][1])*repeat[1])
                    if physical>.003 and metric>.001:ratios.append(metric/physical)
            self.assertGreater(statistics.median(ratios),.90,key)
            self.assertLess(statistics.median(ratios),1.10,key)

    def test_real_seated_statures_keep_bow_and_tails_above_the_chair_seat(self):
        for key,value in self.fixtures.items():
            look,body,shoe,geometry,weights,report,scale=value
            soles={side:min(p[2] for p in shoe['positions'] if p[0]*(1 if side=='L' else -1)>0) for side in ('L','R')}
            metrics=metrics_from_joints(body['joints'],soles)
            if look['outfit_asset']=='male_worksuit01':metrics['pelvis_contact_allowance_m']=.005
            poses=pose_values('Sit',.25,seat_metrics=metrics,stature_scale=scale)
            pelvis=pelvis_height('Sit',.25,body['joints']['PelvisRoot'][2],1.,seat_metrics=metrics,stature_scale=scale)
            points=deform_points(geometry[0],weights,body['joints'],clip='Sit',phase=.25,poses=poses,pelvis_z=pelvis,scale=scale)
            covered=[p for p in points if abs(p[0])<.22 and abs(p[1])<.22]
            self.assertTrue(covered,key)
            self.assertGreater(min(p[2] for p in covered),.467,(key,'seat/tail clearance'))


if __name__=='__main__':unittest.main()
