"""Character source contracts, independent of Blender/Godot installation."""
import json
import math
import struct
from pathlib import Path
import tempfile
import unittest

from tools.town_upgrade.characters.geometry import bounds, ellipsoid, ring_surface, tube
from tools.town_upgrade.characters.manifest import ANIMATED_JOINTS, CLIPS, DIRECTIONS, REQUIRED_JOINTS, build_manifest, validate_manifest
from tools.town_upgrade.characters.animation import pelvis_height,pose_values
from tools.town_upgrade.characters.glb import attach_animations, read_glb, write_glb
from tools.town_upgrade.characters.human import adapted_body, boundary_loops, load_source, vertex_normals
from tools.town_upgrade.characters.assets import fit_asset, geometry_for, visible_skin, verify_assets
from tools.town_upgrade.characters.apron import ApronPattern

ROOT=Path(__file__).resolve().parents[2]


class CharacterContractTests(unittest.TestCase):
    def setUp(self):
        self.personas=json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8'))
        self.manifest=build_manifest(self.personas)

    def test_every_persona_and_player_have_identity_and_pose_coverage(self):
        self.assertEqual(validate_manifest(self.manifest,set(self.personas)),[])
        self.assertEqual(len(self.manifest['characters']),25)
        for key,entry in self.manifest['characters'].items():
            self.assertEqual(set(entry['clips']),set(CLIPS))
            if key!='player':self.assertEqual(entry['name'],self.personas[key]['name'])
        self.assertEqual(DIRECTIONS,['south','south-east','east','north-east','north','north-west','west','south-west'])

    def test_invalid_coverage_or_lost_furniture_clip_fails(self):
        self.manifest['characters'].pop('player')
        self.assertTrue(validate_manifest(self.manifest,set(self.personas)))
        self.manifest=build_manifest(self.personas)
        self.manifest['characters']['aria']['clips'].remove('Sit')
        self.assertIn('aria: incomplete animation contract',validate_manifest(self.manifest,set(self.personas)))

    def test_age_and_approved_identity_palette_are_retained(self):
        entries=self.manifest['characters']
        self.assertLess(entries['dou']['body_height_m'],1.5)
        self.assertLess(entries['dou']['age'],18)
        self.assertGreater(entries['dan']['age'],65)
        self.assertEqual(entries['aria']['top'],'#ac7468')
        self.assertEqual(entries['aria']['detail'],'apron')
        self.assertEqual(entries['ben']['top'],'#b39257')
        self.assertEqual(entries['ben']['detail'],'tools')
        self.assertGreater(len({e['body_height_m'] for e in entries.values()}),10)

    def test_tube_and_anatomy_topology_are_finite_and_uv_mapped(self):
        for geometry in [ring_surface([(0,.1,.07,0),(.5,.2,.1,.02),(1,.05,.04,0)]),ellipsoid((0,0,1),(.2,.1,.3)),tube([(0,0,0),(.2,.1,.3),(.3,.2,.8)],.01)]:
            vertices,faces,uv=geometry
            self.assertEqual(len(vertices),len(uv))
            self.assertTrue(all(math.isfinite(c) for p in vertices for c in p))
            self.assertTrue(all(0<=i<len(vertices) for face in faces for i in face))
            self.assertTrue(all(len(face)>=3 for face in faces))
            # A three-point seam needs 3 × 7 vertices, not the anatomy mesh's
            # larger ring count. Require a genuine cross-section at each point.
            self.assertGreaterEqual(len(vertices),21)

    def test_anatomy_sides_face_outward_and_ground_bounds_are_exact(self):
        vertices,faces,_=ring_surface([(0,.1,.1,0),(1,.1,.1,0)])
        a,b,c=[vertices[i] for i in faces[0][:3]]
        ab=[b[i]-a[i] for i in range(3)];ac=[c[i]-a[i] for i in range(3)]
        normal=(ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0])
        self.assertGreater(normal[1],0)
        self.assertEqual(bounds(vertices)['minimum'][2],0)
        self.assertEqual(bounds(vertices)['maximum'][2],1)

    def test_all_exported_clips_have_finite_joint_poses_and_loop_seams(self):
        for clip in CLIPS:
            first=pose_values(clip,0);last=pose_values(clip,1)
            self.assertEqual(set(first),set(ANIMATED_JOINTS))
            for name in first:
                for a,b in zip(first[name],last[name]):self.assertAlmostEqual(a,b,places=10)
            for frame in range(25):
                self.assertTrue(all(math.isfinite(v) for angles in pose_values(clip,frame/24).values() for v in angles))
        self.assertNotEqual(pose_values('Walk',.25)['Thigh_L'],pose_values('Idle',.25)['Thigh_L'])
        self.assertGreater(pose_values('Sit',0)['Thigh_L'][0],1.5)
        self.assertGreater(pose_values('Lie',0)['PelvisRoot'][0],1.5)

    def test_native_glb_clips_cover_every_joint_without_exporter_nla_dependency(self):
        source={'asset':{'version':'2.0'},'nodes':[{'name':name,'translation':[0,.88,0]} for name in REQUIRED_JOINTS],'buffers':[{'byteLength':4}]}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'minimal.glb';write_glb(path,source,bytearray(4))
            attach_animations(path);doc,binary=read_glb(path)
        self.assertEqual({a['name'] for a in doc['animations']},set(CLIPS))
        for animation in doc['animations']:
            animated={doc['nodes'][c['target']['node']]['name'] for c in animation['channels']}
            self.assertEqual(animated,set(REQUIRED_JOINTS))
            self.assertEqual(len(animation['channels']),len(REQUIRED_JOINTS)+1)
        self.assertLessEqual(doc['buffers'][0]['byteLength'],len(binary))

    def test_optional_apron_hinge_is_exported_in_every_native_clip(self):
        names=list(ANIMATED_JOINTS)+['Skin_'+name for name in ANIMATED_JOINTS]
        source={'asset':{'version':'2.0'},'nodes':[{'name':name,'translation':[0,.88,0]} for name in names],'buffers':[{'byteLength':4}]}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'apron.glb';write_glb(path,source,bytearray(4))
            attach_animations(path);doc,_=read_glb(path)
        for animation in doc['animations']:
            animated={doc['nodes'][c['target']['node']]['name'] for c in animation['channels']}
            self.assertEqual(animated,set(names))
            self.assertEqual(len(animation['channels']),len(ANIMATED_JOINTS)*2+2)

    def test_native_corrective_is_a_standard_gltf_weights_channel_in_every_clip(self):
        source={'asset':{'version':'2.0'},'nodes':[{'name':name,'translation':[0,.88,0]} for name in REQUIRED_JOINTS]+[{'name':'Continuous_pants','mesh':0}], 'meshes':[{'extras':{'targetNames':['SeatContact']},'weights':[0.],'primitives':[]}], 'buffers':[{'byteLength':4}]}
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'morph.glb';write_glb(path,source,bytearray(4));attach_animations(path);doc,binary=read_glb(path)
        for animation in doc['animations']:
            channels=[c for c in animation['channels'] if c['target']['path']=='weights']
            self.assertEqual(len(channels),1)
            self.assertEqual(channels[0]['target']['node'],len(REQUIRED_JOINTS))
            sampler=animation['samplers'][channels[0]['sampler']];accessor=doc['accessors'][sampler['output']];view=doc['bufferViews'][accessor['bufferView']]
            self.assertEqual((accessor['type'],accessor['count']),('SCALAR',25))
            values=struct.unpack_from('<25f',binary,view.get('byteOffset',0)+accessor.get('byteOffset',0))
            self.assertEqual(set(values),{1. if animation['name'] in ('Sit','Soak') else 0.})

    def test_cc0_anatomy_is_checksum_bound_and_relaxed_pose_has_weighted_clothes(self):
        source=load_source()
        self.assertEqual(source[-1]['license'],'CC0-1.0')
        self.assertGreater(len(source[2]),10000)
        data=adapted_body(self.manifest['characters']['aria'])
        self.assertEqual(set(data['joints']),set(REQUIRED_JOINTS))
        # The source has outstretched arms; the deliverable must have a relaxed
        # shoulder-to-wrist descent, not simply scale an A-pose into the town.
        shoulder=data['joints']['UpperArm_L'];wrist=data['joints']['Hand_L']
        self.assertLess(abs(wrist[0]-shoulder[0]),.09)
        self.assertGreater(shoulder[2]-wrist[2],.40)
        asset=fit_asset(data,'clothes','male_casualsuit01')
        for region in ('skin','shirt','pants'):
            geometry,weights=visible_skin(data,asset) if region=='skin' else geometry_for(asset,region)[:2]
            self.assertGreater(len(geometry[1]),1000)
            self.assertEqual(len(weights),len(geometry[0]))
            for row in weights:self.assertAlmostEqual(sum(row.values()),1,places=5)
        self.assertLess(abs(data['joints']['Foot_L'][0]),.15)

    def test_coordinate_conversion_preserves_outward_forehead_normals(self):
        data=adapted_body(self.manifest['characters']['aria'])
        normals=vertex_normals(data['positions'],data['faces'])
        front=[n[1] for p,n in zip(data['positions'],normals) if abs(p[0])<.025 and 1.60<p[2]<1.64 and p[1]>.12]
        self.assertGreater(len(front),3)
        self.assertGreater(sum(front)/len(front),.4)

    def test_authored_cc0_garment_preserves_seams_and_precise_body_mask(self):
        self.assertEqual(verify_assets()['license'],'CC0-1.0')
        for key in self.manifest['characters']:
            data=adapted_body(self.manifest['characters'][key])
            asset=fit_asset(data,'clothes','male_casualsuit01')
            # A continuous tucked outfit has five purposeful openings: neck,
            # two wrists and two ankles. The belt is joined authored topology.
            loops=boundary_loops(asset['faces'])
            self.assertEqual(len(loops),5)
            self.assertTrue(all(len(loop)>=32 for loop in loops))
            self.assertEqual(len(asset['positions']),8426)
            self.assertTrue(all(.65<value<1.4 for value in asset['axis_scale'].values()))
            for row in asset['weights']:
                self.assertTrue(all(v>0 for v in row.values()))
                self.assertAlmostEqual(sum(row.values()),1,places=8)
            skin,_=visible_skin(data,asset)
            self.assertLess(len(skin[1]),len(data['faces'])*.65)
            self.assertGreater(len(skin[1]),7000)
            self.assertTrue(all(math.isfinite(v) for p in asset['positions'] for v in p))
        self.assertEqual(adapted_body(self.manifest['characters']['ben'])['morph_targets'],{'asian-male-young.target':1})

    def test_native_jeans_have_conventional_silhouette_without_profile_balloons(self):
        for key in ['aria','ben','dou','dan']:
            data=adapted_body(self.manifest['characters'][key])
            asset=fit_asset(data,'clothes','male_casualsuit01')
            for side in ['L','R']:
                center=data['joints']['Shin_'+side][0]
                rows=[p for p in asset['positions'] if .25<p[2]<.65 and (p[0]>0)==(side=='L')]
                self.assertLess(max(abs(p[0]-center) for p in rows),.11)
                self.assertLess(max(p[1] for p in rows)-min(p[1] for p in rows),.22)
            # Precise authored mask leaves no bare midriff or thighs. Preserve
            # the open collar's upper chest rather than masking by rough band.
            for face in data['faces']:
                p=tuple(sum(data['source'][i][k] for i,t in face)/len(face) for k in range(3))
                if abs(p[0])<.1 and .60<p[2]<1.18 and p[1]>.04:
                    self.assertTrue(all(i in asset['deleted'] for i,t in face),(key,p))
            for name in ['short01','ponytail01']:
                hair=fit_asset(data,'hair',name);geometry,weights,_=geometry_for(hair)
                self.assertGreater(len(geometry[0]),2000)
                self.assertGreater(min(p[2] for p in geometry[0]),1.2)
        self.assertIn('asian-male-child.target',adapted_body(self.manifest['characters']['dou'])['morph_targets'])
        self.assertIn('asian-male-old.target',adapted_body(self.manifest['characters']['dan'])['morph_targets'])

    def test_apron_is_one_closed_surface_with_coherent_pocket_and_drape_weights(self):
        data=adapted_body(self.manifest['characters']['aria'])
        pattern=ApronPattern(fit_asset(data,'clothes','male_casualsuit01'))
        geometry,weights=pattern.surface();pocket,pocket_weights=pattern.pocket()
        # Explicit thickness and edge faces are retained by ordinary glTF;
        # no renderer-only solidify modifier is needed for the back side.
        self.assertEqual(boundary_loops(geometry[1]),[])
        self.assertEqual(boundary_loops(pocket[1]),[])
        self.assertGreater(len(pocket[1]),100)
        for p,row in zip(pocket[0][:len(pocket[0])//2],pocket_weights):
            self.assertEqual(row,pattern.weights(p[0],p[2]))
            self.assertAlmostEqual(p[1],pattern.pocket_front(p[0],p[2]),places=9)
            # A smoothly eased pouch can stand off the apron by a few mm;
            # its stitch must use that same surface, never the older flat plane.
            self.assertGreater(p[1]-pattern.front(p[0],p[2]),.001)
            self.assertLess(p[1]-pattern.front(p[0],p[2]),.012)
        # No discontinuous left/right thigh seam can tear the pocket or apron.
        for z in [.5,.7,.85,.95,1.0,1.1]:
            self.assertEqual(pattern.weights(-.01,z),pattern.weights(.01,z))
        self.assertAlmostEqual(pose_values('Walk',.25)['ApronDrape'][0],.5)
        self.assertAlmostEqual(pose_values('Sit',.25)['ApronDrape'][0],math.pi/2)
        self.assertTrue(all(abs(sum(w.values())-1)<1e-8 for w in weights))

    def test_walk_keeps_stance_foot_flat_and_at_the_rest_ground_height(self):
        length=.82;rest_hip=.89
        for frame in range(25):
            phase=frame/24;poses=pose_values('Walk',phase)
            stance='L' if math.sin(phase*math.tau)>=0 else 'R'
            thigh=poses['Thigh_'+stance][0];shin=poses['Shin_'+stance][0];foot=poses['Foot_'+stance][0]
            self.assertAlmostEqual(thigh+shin+foot,0,places=9)
            height=pelvis_height('Walk',phase,rest_hip,length)
            contact=height-length*math.cos(thigh)
            self.assertAlmostEqual(contact,rest_hip-length,places=9)


if __name__=='__main__':unittest.main()
