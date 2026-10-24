"""Synthetic temporary evidence fixtures exercise package fail-closed bindings."""
import json
from pathlib import Path
import tempfile
import unittest
import struct

from tools import town_runtime_assets as runtime
from tools import package_town_bridge as source_package
from tools import package_town_windows as windows_package
from tools.tests.test_town_runtime_assets import fixture,write
from tools.town_upgrade import verify_windows_export


def proof_fixture(root):
    fixture(root)
    write(root/'game/data/town3d/map.json',{'unit_test_only':True})
    write(root/runtime.PROJECTION,{'schema':'living_town.projection3d.v1','source_asset_set_sha256':'b'*64})
    renderer=root/'game/scripts/WorldView3D.gd';renderer.parent.mkdir(parents=True);renderer.write_text('unit test renderer source',encoding='utf8')
    write(root/runtime.PROFILE,{'source_asset_set_sha256':'b'*64,'file_hashes':{'map.json':runtime.sha(root/'game/data/town3d/map.json')},'projection_sha256':runtime.sha(root/runtime.PROJECTION),
        'presentation_source_hashes':{'game/scripts/WorldView3D.gd':runtime.sha(renderer)}})
    harness=root/'game/scripts/town_walkthrough.gd';harness.write_text('unit test harness bytes',encoding='utf8')
    capture=root/'docs/town_bridge/captures/actual.png';capture.parent.mkdir(parents=True);capture.write_bytes(b'unit-test-only-image')
    write(root/runtime.UPGRADE_LOGICAL,{'status':'PASS','failures':0,'checks':[{'passed':True}],'source_asset_set_sha256':'b'*64,'projection_sha256':runtime.sha(root/runtime.PROJECTION),'profile_sha256':runtime.sha(root/runtime.PROFILE)})
    visual={'status':'PASS','preview':False,'failure_count':0,'direct_agent_writes':False,'route_complete':True,'fps':18,'tour_frames_elapsed':15120,'checks':[{'passed':True}],
        'source_glb_sha256':'b'*64,'projection_sha256':runtime.sha(root/runtime.PROJECTION),'profile_sha256':runtime.sha(root/runtime.PROFILE),'stage_manifest_sha256':runtime.sha(root/runtime.STAGE),
        'characters_manifest_sha256':runtime.sha(root/runtime.CHARACTERS),'harness_sha256':runtime.sha(harness),
        'captures':[{'file':'F:/unit-test-only/actual.png','sha256':runtime.sha(capture),'tick':90,'chapter':1}]}
    write(root/runtime.UPGRADE_CAPTURE,visual)
    write(root/runtime.UPGRADE_REVIEW,{'status':'PASS','walkthrough_report_sha256':runtime.sha(root/runtime.UPGRADE_CAPTURE),'stage_manifest_sha256':runtime.sha(root/runtime.STAGE),'characters_manifest_sha256':runtime.sha(root/runtime.CHARACTERS)})
    return {p.relative_to(root).as_posix():runtime.sha(p) for p in root.rglob('*') if p.is_file()}


class UpgradePackageContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='town-package-contract-unit-');self.root=Path(self.tmp.name)
        self.hashes=proof_fixture(self.root)
    def tearDown(self):self.tmp.cleanup()

    def test_source_package_uses_new_actual_gameplay_proof(self):
        proof=source_package.validate_sources(self.root,self.hashes)
        self.assertEqual(proof['building_count'],151)
        self.assertEqual(proof['runtime_file_count'],28)
        self.assertFalse(proof['native_boot_report_included'])

    def test_changed_rebaked_model_is_rejected(self):
        (self.root/'game/assets/characters3d/player.glb').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError,'missing or changed'):
            source_package.validate_sources(self.root,self.hashes)

    def test_camera_only_preview_cannot_certify_a_full_gameplay_package(self):
        p=self.root/runtime.UPGRADE_CAPTURE;data=runtime.read(p);data['preview']=True;write(p,data)
        self.hashes[runtime.UPGRADE_CAPTURE]=runtime.sha(p)
        with self.assertRaisesRegex(ValueError,'completed actual'):
            source_package.validate_sources(self.root,self.hashes)

    def test_stale_image_review_is_rejected(self):
        p=self.root/runtime.UPGRADE_REVIEW;data=runtime.read(p);data['walkthrough_report_sha256']='0'*64;write(p,data)
        with self.assertRaisesRegex(ValueError,'image review'):
            source_package.validate_sources(self.root,self.hashes)

    def test_renderer_changed_after_profile_freeze_is_rejected(self):
        rel='game/scripts/WorldView3D.gd';(self.root/rel).write_text('changed renderer',encoding='utf8')
        self.hashes[rel]=runtime.sha(self.root/rel)
        with self.assertRaisesRegex(ValueError,'Presentation source changed'):
            source_package.validate_sources(self.root,self.hashes)

    def test_missing_actual_png_cannot_be_substituted_by_an_old_capture(self):
        self.hashes.pop('docs/town_bridge/captures/actual.png')
        with self.assertRaisesRegex(ValueError,'screenshot differs'):
            source_package.validate_sources(self.root,self.hashes)

    def test_native_binary_proof_must_bind_same_model_and_character_set(self):
        files={rel:self.root/rel for rel in self.hashes}
        report={'checks':[{'passed':True}],'boot':{'normal_product_entry':True},
            'profile_sha256':self.hashes[runtime.PROFILE],'projection_sha256':self.hashes[runtime.PROJECTION],
            'source_asset_set_sha256':'b'*64,'characters_manifest_sha256':self.hashes[runtime.CHARACTERS],
            'stage_manifest_sha256':self.hashes[runtime.STAGE],
            'source_runtime_evidence':{'logical_report_sha256':self.hashes[runtime.UPGRADE_LOGICAL],'visual_report_sha256':self.hashes[runtime.UPGRADE_CAPTURE]}}
        proof=windows_package.validate_sources_v2(self.root,files,self.hashes,report)
        self.assertTrue(proof['native_boot_report_included'])
        report['characters_manifest_sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'another upgraded runtime'):
            windows_package.validate_sources_v2(self.root,files,self.hashes,report)

    def native_fixture(self):
        export=self.root/'build/town_bridge/windows';export.mkdir(parents=True)
        (export/'LivingTown.exe').write_bytes(b'MZunit-test-only-export')
        (export/'LivingTown.pck').write_bytes(b'GDPCunit-test-only-pack')
        screenshot=self.root/'native_unit_test.png'
        screenshot.write_bytes(b'\x89PNG\r\n\x1a\n'+b'\x00\x00\x00\rIHDR'+struct.pack('>II',1280,768))
        observed={'schema':'living_town.normal_entry_runtime.v2','status':'PASS','actual_gpu':True,'normal_product_entry':True,
            'entry_scene':'res://scenes/Main.tscn','engine_frames_drawn':12,
            'view':{'model':{'loaded':True,'building_count':151},'mesh_actor_count':25,'actor_count':25},
            'executable':str(export/'LivingTown.exe'),'executable_sha256':runtime.sha(export/'LivingTown.exe'),'pack_sha256':runtime.sha(export/'LivingTown.pck'),
            'source_asset_set_sha256':'b'*64,'source_blend_sha256':'c'*64,
            'screenshots':[{'file':str(screenshot),'sha256':runtime.sha(screenshot),'width':1280,'height':768}]}
        for field,rel in (('profile_sha256',runtime.PROFILE),('projection_sha256',runtime.PROJECTION),('stage_manifest_sha256',runtime.STAGE),('characters_manifest_sha256',runtime.CHARACTERS)):
            observed[field]=runtime.sha(self.root/rel)
        path=self.root/'native_unit_test.json';write(path,observed)
        return export,path,observed

    def test_native_verifier_binds_actual_executable_and_pack_to_source_evidence(self):
        export,path,_=self.native_fixture()
        report=verify_windows_export.verify(self.root,export,path,0)
        self.assertEqual(report['status'],'PASS')
        self.assertEqual(report['binaries'][0]['sha256'],runtime.sha(export/'LivingTown.exe'))
        self.assertEqual(report['source_runtime_evidence']['visual_report_sha256'],self.hashes[runtime.UPGRADE_CAPTURE])

    def test_source_godot_launch_cannot_substitute_for_exported_binary(self):
        export,path,observed=self.native_fixture()
        observed['executable_sha256']='0'*64;write(path,observed)
        with self.assertRaisesRegex(ValueError,'runtime_launched_exact_LivingTown.exe'):
            verify_windows_export.verify(self.root,export,path,0)


if __name__=='__main__':unittest.main()
