"""Failure cases must stop before a process launch or source/output mutation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "town_generation/generate_town.py"
spec = importlib.util.spec_from_file_location("town_runner", SOURCE)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class OutputSafety(unittest.TestCase):
    def test_existing_output_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            baseline, output = root / "baseline", root / "output"
            baseline.mkdir()
            output.mkdir()
            canary = output / "prior.blend"
            canary.write_bytes(b"prior-source")
            with self.assertRaises(FileExistsError):
                runner.validate_output(output, baseline)
            self.assertEqual(canary.read_bytes(), b"prior-source")

    def test_source_ancestors_and_descendants_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            baseline = Path(temp) / "baseline"
            baseline.mkdir()
            for output in (baseline, baseline / "new", baseline.parent,
                           runner.REPO / "tools/new-generation", runner.REPO / "art/new-generation"):
                with self.subTest(output=output), self.assertRaises(ValueError):
                    runner.validate_output(output, baseline)

    def test_bad_seed_cannot_launch_process(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner.subprocess, "run") as process:
            for seed in (True, -1, 2**32, 1.25):
                with self.subTest(seed=seed), self.assertRaises(ValueError):
                    runner.generate(output=Path(temp) / "new", seed=seed)
            process.assert_not_called()
            self.assertFalse((Path(temp) / "new").exists())

    def test_missing_blender_stops_before_output_creation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner.subprocess, "run") as process:
            output = Path(temp) / "new"
            with self.assertRaises(ValueError):
                runner.generate(output=output, blender=Path(temp) / "absent.exe")
            process.assert_not_called()
            self.assertFalse(output.exists())

    def test_missing_pbr_stops_before_output_creation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner.subprocess,"run") as process:
            output=Path(temp)/"new"
            # Existing file suffices to reach the library validation; it must
            # never be executed when a required build input is absent.
            with self.assertRaisesRegex(ValueError,"PBR library"):
                runner.generate(output=output,blender=SOURCE)
            process.assert_not_called()
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
