"""Registered CC0 texture recipes and facial asset contracts, without engines."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from tools.town_upgrade.characters.assets import VENDOR,fit_asset,geometry_for,verify_assets
from tools.town_upgrade.characters.human import adapted_body
from tools.town_upgrade.characters.manifest import build_manifest
from tools.town_upgrade.characters.prepare_textures import prepare_registered_image,recolor
from tools.town_upgrade.characters.textures import load_library
from tools.town_upgrade.characters.linen import VENDOR as LINEN_VENDOR,verify_linen,repeat_m,metric_geometry

ROOT=Path(__file__).resolve().parents[2]


class CharacterTextureTests(unittest.TestCase):
    def test_photographed_linen_preserves_source_provenance_channels_and_physical_repeat(self):
        receipt=verify_linen();repeat=repeat_m()
        self.assertEqual(receipt['license'],'CC0-1.0')
        self.assertAlmostEqual(repeat[0],.2707081392676629)
        self.assertAlmostEqual(repeat[1],.27129998803138733)
        with Image.open(LINEN_VENDOR/'rough_linen/arm.jpg') as source:
            self.assertGreater(np.asarray(source.getchannel('G')).std(),2)
            self.assertFalse(np.array_equal(np.asarray(source.getchannel('R')),np.asarray(source.getchannel('G'))))
        # A photographed repeat spans the same metric distance on a panel and
        # a narrow strap; neither stretches one atlas over the entire object.
        g=([(0.,0.,0.),(repeat[0],0.,repeat[1])],[],[(0.,0.),(1.,repeat[1]*4)])
        self.assertEqual(metric_geometry(g,1.,repeat)[2],[(0.,0.),(1.,1.)])
        strap=metric_geometry(g,1.,repeat,.012)[2]
        self.assertAlmostEqual(strap[1][0]*repeat[0],.012)
        self.assertAlmostEqual(strap[1][1],1.)

    def test_palette_bake_preserves_authored_features_and_exact_strand_alpha(self):
        pixels=np.zeros((8,8,4),dtype=np.uint8);pixels[:,:,:3]=[150,115,90];pixels[:,:,3]=np.arange(8,dtype=np.uint8)[None,:]*32
        pixels[2:4,2:4,:3]=[48,24,28];pixels[5:7,2:4,:3]=[215,190,165]
        source=Image.fromarray(pixels,'RGBA')
        for kind in ['skin','cloth','strand']:
            result=np.asarray(recolor(source,'#b39257',kind))
            self.assertTrue(np.array_equal(result[:,:,3],pixels[:,:,3]))
            self.assertGreater(float(result[5:7,2:4,:3].mean()),float(result[2:4,2:4,:3].mean()))
            self.assertGreater(int(result[:,:,:3].max())-int(result[:,:,:3].min()),30)

    def test_actual_registered_skin_garment_and_face_sources_are_licensed_and_nonflat(self):
        provenance=verify_assets();self.assertEqual(provenance['license'],'CC0-1.0')
        for relative in ['skins/young_asian_female/young_lightskinned_female_diffuse3.png','clothes/male_casualsuit01/male_casualsuit01_diffuse.png','clothes/male_casualsuit01/male_casualsuit01_normal.png','clothes/male_casualsuit01/male_casualsuit01_ao.png']:
            with Image.open(VENDOR/relative) as image:
                self.assertEqual(image.size,(2048,2048))
                sample=np.asarray(image.resize((128,128)).convert('RGB'))
                self.assertGreater(float(sample.std()),4)
        looks=build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters']
        for key in ['aria','ben','dou','dan']:
            data=adapted_body(looks[key])
            for category,name in [('eyes','high-poly'),('eyebrows','eyebrow005'),('eyelashes','eyelashes01')]:
                geometry,weights,_=geometry_for(fit_asset(data,category,name))
                self.assertGreater(len(geometry[1]),50)
                self.assertTrue(all(1.40<p[2]<1.64 for p in geometry[0]))
                self.assertTrue(all(abs(sum(row.values())-1)<1e-8 for row in weights))

    def test_official_eye_cornea_placeholder_stays_transparent_and_iris_stays_visible(self):
        with Image.open(VENDOR/'eyes/materials/brown_eye.png') as source:
            prepared=prepare_registered_image(source,'alpha_basecolor',1024)
            self.assertEqual(prepared.mode,'RGBA')
            # The official outer cornea UV island has blue RGB but alpha zero.
            # Dropping alpha turns every character's eyes opaque pale blue.
            self.assertEqual(prepared.getpixel((950,950))[3],0)
            self.assertGreater(prepared.getpixel((950,950))[2],240)
            pixels=np.asarray(prepared)
            iris=(pixels[:,:,0]>pixels[:,:,2]*1.3)&(pixels[:,:,3]>250)
            self.assertGreater(int(iris.sum()),10000)
            self.assertTrue(np.array_equal(np.asarray(source.getchannel('A')),pixels[:,:,3]))

    def test_material_loader_rejects_changed_prepared_pixels(self):
        provenance=verify_assets();origin='eyes/materials/brown_eye.png'
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);image=folder/'map.png';Image.new('RGB',(4,4),(60,80,100)).save(image)
            recipe=ROOT/'tools/town_upgrade/characters/prepare_textures.py'
            doc={'schema':'living_town.character_pbr.v1','license':'CC0-1.0','source_module_sha256':hashlib.sha256(recipe.read_bytes()).hexdigest(),'source_provenance_sha256':hashlib.sha256((VENDOR/'provenance.json').read_bytes()).hexdigest(),'source_look_manifest_sha256':hashlib.sha256((ROOT/'tools/town_upgrade/characters/manifest.py').read_bytes()).hexdigest(),'characters':{'aria':{'roles':{'eyes':{'alpha_mode':'MASK','alpha_semantics':'official cornea alpha preserved','maps':{'basecolor':{'path':'map.png','sha256':hashlib.sha256(image.read_bytes()).hexdigest(),'source':origin,'source_sha256':provenance['files'][origin]['sha256']}}}}}}}
            manifest=folder/'library_manifest.json';manifest.write_text(json.dumps(doc),encoding='utf-8')
            self.assertEqual(load_library(manifest)['schema'],doc['schema'])
            Image.new('RGB',(4,4),(100,80,60)).save(image)
            with self.assertRaisesRegex(ValueError,'texture changed'):load_library(manifest)

    def test_wardrobe_variants_keep_native_parts_and_footwear_is_grounded(self):
        looks=build_manifest(json.loads((ROOT/'game/data/personas.json').read_text(encoding='utf-8')))['characters']
        self.assertEqual({v['outfit_asset'] for v in looks.values()},{'male_casualsuit01','female_casualsuit01','male_worksuit01'})
        for key in ['aria','ben','dou','fei','tie']:
            look=looks[key];data=adapted_body(look);outfit=fit_asset(data,'clothes',look['outfit_asset'])
            for region in ['shirt','pants']:
                geometry,weights,_=geometry_for(outfit,region)
                self.assertGreater(len(geometry[1]),500)
                self.assertTrue(all(abs(sum(row.values())-1)<1e-8 for row in weights))
            footwear=fit_asset(data,'clothes',look['shoe_asset'])
            self.assertAlmostEqual(min(p[2] for p in footwear['positions']),0,places=9)
            self.assertIsNotNone(footwear['authored_weights'])
            self.assertGreater(len(footwear['deleted']),3000)
            if key=='tie':
                pants=geometry_for(outfit,'pants')[0]
                self.assertGreater(max(p[2] for p in pants[0]),1.20) # overall bib
        self.assertEqual(looks['dou']['outfit_asset'],'female_casualsuit01')
        self.assertEqual(looks['dou']['shoe_asset'],'shoes05')


if __name__=='__main__':unittest.main()
