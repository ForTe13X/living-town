"""Bounded acquisition regressions; tests never call the live source API."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.town_upgrade.fetch_botanical_sources import fetch,request,source_path


class BotanicalSourcesTests(unittest.TestCase):
    def test_relative_source_cannot_escape_asset_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'asset'
            self.assertEqual(source_path(root,'textures/leaf.png'),root.resolve()/'textures/leaf.png')
            with self.assertRaises(ValueError):source_path(root,'../../outside.png')

    def test_only_explicit_https_asset_hosts_are_requested(self):
        for url in ('http://dl.polyhaven.org/a','https://elsewhere.invalid/a','file:///C:/private'):
            with self.subTest(url=url),self.assertRaises(ValueError):request(url)

    def test_cached_file_requires_both_size_and_source_md5(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'asset.bin';path.write_bytes(b'valid CC0 mesh')
            record={'size':path.stat().st_size,'md5':hashlib.md5(path.read_bytes()).hexdigest(),'url':'https://dl.polyhaven.org/asset.bin'}
            with patch('tools.town_upgrade.fetch_botanical_sources.request',side_effect=AssertionError('cache should be offline')):
                result=fetch((path,record))
            self.assertEqual(result['sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
            path.write_bytes(b'invalid source')
            with patch('tools.town_upgrade.fetch_botanical_sources.request',side_effect=RuntimeError('corrupt cache refetch')):
                with self.assertRaisesRegex(RuntimeError,'corrupt cache'):fetch((path,record))



    def _local_island_acquisition(self, root, conflicting_alias=False):
        # Execute the real acquisition main against tiny cached source files.
        # Network and mesh/render engines are never used by this fixture.
        from PIL import Image
        source=Path(__file__).resolve().parents[2]/'tools/town_upgrade/fetch_botanical_sources.py'
        spec=importlib.util.spec_from_file_location('botanical_alias_acquisition_fixture',source)
        acquisition=importlib.util.module_from_spec(spec);spec.loader.exec_module(acquisition)
        folder=root/'island_tree_02';textures=folder/'textures';textures.mkdir(parents=True)
        diffuse=textures/'island_tree_02_leaves_diff_2k.jpg'
        mask=folder/'leaves_alpha.png'
        Image.new('RGB',(2,2),(68,116,42)).save(diffuse)
        Image.new('L',(2,2),128).save(mask)
        gltf=folder/'island_tree_02_2k.gltf'
        gltf.write_text(json.dumps({'materials':[{'name':'island_tree_02_leaves','alphaMode':'MASK','pbrMetallicRoughness':{'baseColorTexture':{'index':0}}}],
            'textures':[{'source':0}],'images':[{'uri':'textures/'+diffuse.name}]}),encoding='utf8')
        def record(path):return {'size':path.stat().st_size,'md5':hashlib.md5(path.read_bytes()).hexdigest(),'url':'https://dl.polyhaven.org/'+path.name}
        model=record(gltf);model['include']={'textures/'+diffuse.name:record(diffuse)}
        (root/'island_tree_02_files.json').write_text(json.dumps({'gltf':{'2k':{'gltf':model}},'leaves_alpha':{'2k':{'png':record(mask)}}}),encoding='utf8')
        alias=textures/'leaves_rgba.png'
        if conflicting_alias:alias.write_bytes(b'preserve this existing artist file')
        def cached(job):
            path,item=job
            return {'path':str(path),'source_url':item['url'],'source_md5':item['md5'],'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        def run():
            with patch.object(acquisition,'ASSETS',('island_tree_02',)),patch.object(acquisition,'fetch',side_effect=cached), \
                 patch.object(acquisition,'request',side_effect=AssertionError('fixture must stay offline')), \
                 patch.object(sys,'argv',['fetch_botanical_sources.py','--output',str(root)]):
                acquisition.main()
        return alias,textures/'island_tree_02_leaves_diff_2k_rgba.png',run

    def test_fresh_acquisition_receipts_exact_legacy_leaf_alias_and_preserves_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);alias,canonical,run=self._local_island_acquisition(root)
            self.assertFalse(alias.exists());run()
            self.assertEqual(alias.read_bytes(),canonical.read_bytes())
            receipt=json.loads((root/'source_receipts.json').read_text(encoding='utf8'))
            row=next(r for r in receipt['technical_channel_derivatives'] if r['path']==alias.relative_to(root).as_posix())
            self.assertEqual(row['sha256'],hashlib.sha256(alias.read_bytes()).hexdigest())
            self.assertEqual(row['source_inputs'],{canonical.relative_to(root).as_posix():row['sha256']})
            self.assertEqual(receipt['license'],'CC0-1.0')
            mtime=alias.stat().st_mtime_ns;run()
            self.assertEqual(alias.stat().st_mtime_ns,mtime)

    def test_conflicting_legacy_leaf_alias_is_rejected_and_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            alias,canonical,run=self._local_island_acquisition(Path(temp),conflicting_alias=True)
            before=alias.read_bytes()
            with self.assertRaisesRegex(ValueError,'alias differs; preserved'):run()
            self.assertEqual(alias.read_bytes(),before)


if __name__=='__main__':unittest.main()
