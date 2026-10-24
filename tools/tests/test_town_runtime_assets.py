"""Offline source/release/package contracts; fixtures never invoke an engine."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools import fetch_town_assets as fetch
from tools import town_runtime_assets as runtime


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')


def fixture(root):
    town=root/'game/assets/town3d';town.mkdir(parents=True)
    model=town/'town_00_urban_core.glb';model.write_bytes(b'unit-test-model')
    characters={}
    for i,key in enumerate(['player']+[f'persona{i:02}' for i in range(24)]):
        p=root/f'game/assets/characters3d/{key}.glb';p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(('model-'+key).encode())
        characters[key]={'model':f'res://assets/characters3d/{key}.glb','model_bytes':p.stat().st_size,'model_sha256':runtime.sha(p)}
    write(root/runtime.CHARACTERS,{'schema':'living_town.characters.v1','characters':characters})
    write(root/runtime.STAGE,{'schema':'living_town.game_stage.v2','status':'PASS','source_blend_sha256':'c'*64,'source_asset_set_sha256':'b'*64,'building_count':151,
        'assets':[{'file':model.name,'sha256':runtime.sha(model)}],
        'files':[{'file':model.name,'bytes':model.stat().st_size,'sha256':runtime.sha(model)}]})
    return model


class RuntimeAssetTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='town-runtime-unit-')
        self.root=Path(self.tmp.name);self.model=fixture(self.root)

    def tearDown(self):self.tmp.cleanup()

    def test_complete_staged_town_runs_without_network_or_release_urls(self):
        with patch.object(fetch,'download_urllib',side_effect=AssertionError('network forbidden')):
            paths=fetch.retrieve_runtime(self.root,local=True)
        self.assertEqual(len(paths),28)

    def test_local_missing_asset_is_rejected_without_network(self):
        self.model.unlink()
        with patch.object(fetch,'download_urllib',side_effect=AssertionError('network forbidden')):
            with self.assertRaisesRegex(fetch.IntegrityError,'no network attempted'):
                fetch.retrieve_runtime(self.root,local=True)

    def test_pending_public_urls_do_not_trigger_an_invented_download(self):
        write(self.root/runtime.RELEASE,runtime.release_document(self.root))
        self.model.unlink()
        with patch.object(fetch,'download_urllib',side_effect=AssertionError('network forbidden')):
            with self.assertRaisesRegex(fetch.FetchError,'published URLs are pending'):
                fetch.retrieve_runtime(self.root)

    def test_verified_local_source_can_restore_a_missing_chunk(self):
        source=self.root/'offline-source';path=source/'game/assets/town3d'/self.model.name
        path.parent.mkdir(parents=True);path.write_bytes(self.model.read_bytes());self.model.unlink()
        fetch.retrieve_runtime(self.root,local=True,local_source=source)
        self.assertEqual(self.model.read_bytes(),b'unit-test-model')

    def test_mismatched_existing_asset_is_preserved(self):
        self.model.write_bytes(b'user-edited-existing-model')
        with self.assertRaisesRegex(fetch.IntegrityError,'preserved'):
            fetch.retrieve_runtime(self.root,local=True)
        self.assertEqual(self.model.read_bytes(),b'user-edited-existing-model')

    def test_changed_character_or_catalogue_invalidates_release_binding(self):
        write(self.root/runtime.RELEASE,runtime.release_document(self.root))
        runtime.read_release(self.root)
        data=runtime.read(self.root/runtime.CHARACTERS);data['revision']='changed'
        write(self.root/runtime.CHARACTERS,data)
        with self.assertRaisesRegex(ValueError,'another staged town or character set'):
            runtime.read_release(self.root)

    def test_windows_path_traversal_is_rejected(self):
        for name in ('../escape.glb','C:/escape.glb','\\\\server\\share','/absolute','a/../../b'):
            with self.assertRaises(ValueError):runtime.safe_relative(name)

    def test_frozen_v1_release_remains_pinned(self):
        p=self.root/'legacy_stage.json'
        write(p,{'source_glb_sha256':fetch.EXPECTED_SHA256,'files':[{'file':fetch.ASSET_NAME,'bytes':fetch.EXPECTED_BYTES,'sha256':fetch.EXPECTED_SHA256}]})
        self.assertEqual(fetch.expected_asset(p).sha256,fetch.EXPECTED_SHA256)
        data=runtime.read(p);data['files'][0]['sha256']='0'*64;write(p,data)
        with self.assertRaises(fetch.IntegrityError):fetch.expected_asset(p)

    def test_new_release_config_and_upload_files_keep_v1_release_untouched(self):
        manifest=self.root/'new-release.json';upload=self.root/'upload'
        self.assertEqual(fetch.main(['--root',str(self.root),'--write-release-manifest',str(manifest),'--prepare-release-assets',str(upload)]),0)
        data,records=runtime.read_release(self.root,manifest)
        self.assertEqual(data['status'],'LOCAL_VERIFIED_URLS_PENDING')
        self.assertTrue(all(item.get('url') is None for item in records.values()))
        self.assertEqual(len(list(upload.iterdir())),28)
        self.assertEqual(fetch.RELEASE_TAG,'town3d-walkthrough-2026-10-12')


    def add_static_cache(self):
        resource=self.root/runtime.STATIC_CACHE_RESOURCE
        resource.write_bytes(b'unit-test-engine-cache')
        manifest={'schema':'living_town.static_render_cache.v1','status':'PASS_FULL_BUILDER_CODEC_VALIDATION_AND_RESOURCE_READBACK',
            'resource_file':resource.name,'resource_bytes':resource.stat().st_size,'resource_sha256':runtime.sha(resource),
            'full_build_validation':{key:True for key in ('ok','original_mesh_buffers_unchanged','batch_buffers_unchanged','semantic_ray_registry_unchanged')}}
        write(self.root/runtime.STATIC_CACHE,manifest)
        return resource

    def test_static_cache_is_required_and_missing_binary_restores_offline(self):
        resource=self.add_static_cache()
        records=runtime.verify_runtime(self.root)
        self.assertIn(runtime.STATIC_CACHE,records)
        self.assertIn(runtime.STATIC_CACHE_RESOURCE,records)
        offline=self.root/'offline';copy=offline/runtime.STATIC_CACHE_RESOURCE
        copy.parent.mkdir(parents=True);copy.write_bytes(resource.read_bytes());resource.unlink()
        with self.assertRaisesRegex(ValueError,'missing or changed'):runtime.verify_runtime(self.root)
        with patch.object(fetch,'download_urllib',side_effect=AssertionError('network forbidden')):
            fetch.retrieve_runtime(self.root,local=True,local_source=offline)
        self.assertEqual(resource.read_bytes(),b'unit-test-engine-cache')

    def test_static_cache_release_cannot_omit_or_change_either_member(self):
        resource=self.add_static_cache()
        release=runtime.release_document(self.root)
        write(self.root/runtime.RELEASE,release);runtime.read_release(self.root)
        release['files']=[r for r in release['files'] if r['path']!=runtime.STATIC_CACHE_RESOURCE]
        write(self.root/runtime.RELEASE,release)
        with self.assertRaisesRegex(ValueError,'omits or adds'):runtime.read_release(self.root)
        resource.write_bytes(b'changed-engine-cache')
        with self.assertRaisesRegex(ValueError,'missing or changed'):runtime.verify_runtime(self.root)

    def test_static_cache_manifest_rejects_escape_and_incomplete_proof(self):
        self.add_static_cache();manifest=runtime.read(self.root/runtime.STATIC_CACHE)
        manifest['resource_file']='../escape.res';write(self.root/runtime.STATIC_CACHE,manifest)
        with self.assertRaisesRegex(ValueError,'Unsupported'):runtime.runtime_records(self.root)
        manifest['resource_file']='static_render_cache.res';manifest['full_build_validation']['ok']=False
        write(self.root/runtime.STATIC_CACHE,manifest)
        with self.assertRaisesRegex(ValueError,'incomplete'):runtime.runtime_records(self.root)

    def test_orphan_static_cache_binary_is_rejected(self):
        self.add_static_cache();(self.root/runtime.STATIC_CACHE).unlink()
        with self.assertRaisesRegex(ValueError,'lacks its required manifest'):runtime.runtime_records(self.root)


if __name__=='__main__':unittest.main()
