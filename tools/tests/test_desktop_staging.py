import json
import tempfile
import unittest
import subprocess
import sys
from unittest.mock import patch
from pathlib import Path
from tools.stage_desktop_logic import digest, input_files, project_config, verify
from tools import check_desktop_candidate


class DesktopStagingHostileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.stage = Path(self.temp.name)
        self.files = {'assets/required.png': b'asset', 'data/town.json': b'{"revision":1}'}
        for rel, data in self.files.items():
            p = self.stage / 'game' / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        (self.stage / 'manifest.json').write_text(json.dumps({
            'staged_sha256': {rel: digest(data) for rel, data in self.files.items()}}))

    def tearDown(self):
        self.temp.cleanup()

    def test_missing_required_asset_is_rejected(self):
        (self.stage / 'game/assets/required.png').unlink()
        with self.assertRaisesRegex(ValueError, 'missing: assets/required.png'):
            verify(self.stage)

    def test_mismatched_data_is_rejected(self):
        (self.stage / 'game/data/town.json').write_text('{"revision":2}')
        with self.assertRaisesRegex(ValueError, 'changed: data/town.json'):
            verify(self.stage)

    def test_unrelated_extension_is_not_silently_omitted(self):
        (self.stage / 'game/unrelated.gdextension').write_text('[configuration]')
        with self.assertRaisesRegex(ValueError, 'unexpected: unrelated.gdextension'):
            verify(self.stage)

    def test_unknown_source_extension_remains_in_import_scope(self):
        game = self.stage / 'game'
        for name in ['nobodywho', 'unrelated']:
            p = game / 'addons' / name / (name + '.gdextension')
            p.parent.mkdir(parents=True)
            p.write_text('[configuration]')
        selected = {p.relative_to(game).as_posix() for p in input_files(game)}
        self.assertIn('addons/unrelated/unrelated.gdextension', selected)
        self.assertNotIn('addons/nobodywho/nobodywho.gdextension', selected)

    def test_generated_import_cache_does_not_invalidate_source(self):
        cache = self.stage / 'game/.godot/imported'
        cache.mkdir(parents=True)
        (cache / 'required.ctex').write_bytes(b'compiled')
        verify(self.stage)

    def test_generated_script_uids_are_not_staged_as_runtime_inputs(self):
        game = self.stage / 'game'
        (game / 'scripts').mkdir()
        (game / 'scripts/Main.gd').write_text('extends Node\n')
        (game / 'scripts/Main.gd.uid').write_text('uid://generated\n')
        selected = {p.relative_to(game).as_posix() for p in input_files(game)}
        self.assertIn('scripts/Main.gd', selected)
        self.assertNotIn('scripts/Main.gd.uid', selected)

    def test_unknown_autoload_using_mcp_name_is_preserved_by_refusal(self):
        with self.assertRaisesRegex(ValueError, 'unexpected script'):
            project_config('[autoload]\nMCPScreenshot="*res://scripts/Important.gd"\n')

    def test_interrupted_runtime_check_never_claims_pass(self):
        manifest = self.stage / 'manifest.json'
        (self.stage / 'LivingTown.exe').write_bytes(b'fixture executable')
        (self.stage / 'export_receipt.json').write_text(json.dumps({
            'export_result': 'PASS', 'source_clean': True,
            'staging_manifest_sha256': digest(manifest.read_bytes()),
            'artifacts': {'LivingTown.exe': digest(b'fixture executable')}}))
        with patch.object(sys, 'argv', ['check', str(self.stage)]), patch.object(
                check_desktop_candidate.subprocess, 'run', side_effect=subprocess.TimeoutExpired('fixture', 240)):
            with self.assertRaises(subprocess.TimeoutExpired):
                check_desktop_candidate.main()
        receipt = json.loads((self.stage / 'runtime_receipt.json').read_text())
        self.assertEqual(receipt['runtime_result'], 'INCOMPLETE')
        self.assertEqual(receipt['cases'], [])
        self.assertEqual(len(receipt['expected_cases']), 7)


if __name__ == '__main__':
    unittest.main()
