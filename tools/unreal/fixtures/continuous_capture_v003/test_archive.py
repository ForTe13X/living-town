"""CPU-only archive mutation and destination-safety controls; no native tools."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).absolute().parent
SPEC = importlib.util.spec_from_file_location('capture_archive', HERE.parents[1] / 'stage_capture_fixture.py')
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)


class ArchiveControls(unittest.TestCase):
    def copy_fixture(self, temporary):
        fixture = Path(temporary) / 'fixture'
        shutil.copytree(HERE, fixture)
        return fixture

    def test_default_verifies_original_ten_bytes_without_writes(self):
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns)
                  for p in HERE.rglob('*') if p.is_file()}
        original_open = Path.open

        def read_only_open(path, mode='r', *args, **kwargs):
            self.assertFalse(any(flag in mode for flag in 'wax+'), 'Default tried to write')
            return original_open(path, mode, *args, **kwargs)

        with patch.object(Path, 'open', read_only_open), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(archive.main(['--fixture', 'continuous_capture_v003']), 0)
        self.assertIn('VERIFIED_SOURCE_ONLY', output.getvalue())
        self.assertEqual(len(archive.verify_fixture()), 10)
        self.assertEqual(before, {p: (p.read_bytes(), p.stat().st_mtime_ns)
                                  for p in HERE.rglob('*') if p.is_file()})

    def test_modified_source_is_refused_before_output_creation(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            fixture = self.copy_fixture(temporary)
            source = fixture / 'HostProject/Source/CapturePilotHost/Private/CapturePilotHost.cpp'
            data = source.read_bytes()
            source.write_bytes(bytes([data[0] ^ 1]) + data[1:])
            destination = Path(temporary) / 'new-output'
            with patch.object(archive, 'FIXTURE', fixture), patch.object(
                    archive, 'verify_fixture', wraps=lambda: archive_verify(fixture)):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(archive.main(['--stage-source', '--artifact-root', str(destination)]), 1)
            self.assertFalse(destination.exists())

    def test_extra_source_is_refused(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            fixture = self.copy_fixture(temporary)
            (fixture / 'HostProject/extra.cpp').write_bytes(b'extra')
            with self.assertRaisesRegex(ValueError, 'Extra source file'):
                archive.verify_fixture(fixture)

    def test_existing_output_is_untouched_and_refused_before_source_read(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            destination = Path(temporary) / 'retained'
            destination.mkdir()
            sentinel = destination / 'keep.bin'
            sentinel.write_bytes(b'retained')
            before = sentinel.stat().st_mtime_ns
            with patch.object(archive, 'verify_fixture', side_effect=AssertionError('Read source after existing output')):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(archive.main(['--stage-source', '--artifact-root', str(destination)]), 1)
            self.assertEqual(list(destination.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_bytes(), b'retained')
            self.assertEqual(sentinel.stat().st_mtime_ns, before)

    def test_fresh_stage_contains_exact_source_only(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            destination = Path(temporary) / 'new-output'
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(archive.main(['--stage-source', '--artifact-root', str(destination)]), 0)
            project = destination / 'project'
            actual = {p.relative_to(project).as_posix(): p.read_bytes()
                      for p in project.rglob('*') if p.is_file()}
            self.assertEqual(actual, dict(archive.verify_fixture()))
            self.assertEqual(list(destination.iterdir()), [project])

    def test_traversal_and_repository_destination_are_refused(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            with self.assertRaisesRegex(ValueError, 'without traversal'):
                archive.fresh_external_root(Path(temporary) / '..' / 'escape')
        destination = archive.REPOSITORY / 'capture-output-must-not-exist'
        with self.assertRaisesRegex(ValueError, 'inside repository'):
            archive.fresh_external_root(destination)
        self.assertFalse(destination.exists())

    def test_manifest_cannot_redefine_the_allowlist_or_hash(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            fixture = self.copy_fixture(temporary)
            manifest = fixture / 'SOURCE_MANIFEST.json'
            text = manifest.read_text()
            manifest.write_text(text.replace('CapturePilotHost.uproject', '../CapturePilotHost.uproject'))
            with self.assertRaisesRegex(ValueError, 'independent ten-path'):
                archive.verify_fixture(fixture)

    def test_symlink_source_and_destination_parent_are_refused(self):
        with tempfile.TemporaryDirectory(prefix='capture_archive_') as temporary:
            fixture = self.copy_fixture(temporary)
            source = fixture / 'HostProject/Source/CapturePilotHost/Private/CapturePilotHost.cpp'
            original = HERE / source.relative_to(fixture)
            source.unlink()
            try:
                source.symlink_to(original)
            except OSError as error:
                self.skipTest('Host does not permit unprivileged symlink creation: ' + str(error))
            with self.assertRaisesRegex(ValueError, 'Symlink or reparse'):
                archive.verify_fixture(fixture)
            alias = Path(temporary) / 'alias'
            alias.symlink_to(Path(temporary), target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Symlink or reparse'):
                archive.fresh_external_root(alias / 'new-output')


archive_verify = archive.verify_fixture

if __name__ == '__main__':
    unittest.main()
