import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORLDGEN = ROOT / "game/addons/worldgen"
EXPECTATIONS = WORLDGEN / "tests/offline_load_expectations.json"
EXPORTER = ROOT / "tools/export_worldgen_godot.py"
BUILD_NAMES = ("coastal_neighborhood", "inland_neighborhood", "standalone_cafe")
sys.path.insert(0, str(ROOT / "tools"))
import worldgen_catalog


class OfflineConsumerExportTests(unittest.TestCase):
    def test_three_pinned_builds_export_as_clean_consumer_projects(self):
        expected = json.loads(EXPECTATIONS.read_text(encoding="utf-8"))["worlds"]
        self.assertEqual(set(expected), {"warm_bay_s1", "inland_neighborhood_s0", "standalone_cafe_s0"})
        with tempfile.TemporaryDirectory() as folder:
            for name in BUILD_NAMES:
                with self.subTest(name=name):
                    package_path = WORLDGEN / "builds" / f"{name}.world.json"
                    package = json.loads(package_path.read_text(encoding="utf-8"))
                    project = Path(folder) / name
                    run = subprocess.run(
                        [sys.executable, str(EXPORTER), "--package", str(package_path), "--output", str(project)],
                        cwd=ROOT, capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    manifest = json.loads((project / "export_manifest.json").read_text(encoding="utf-8"))
                    pinned = expected[package["world_id"]]
                    self.assertEqual(worldgen_catalog.package_identity(package)[1], pinned["package_sha256"])
                    self.assertEqual(manifest["world_id"], package["world_id"])
                    self.assertEqual(manifest["semantic_sha256"], pinned["semantic_sha256"])
                    self.assertEqual(manifest["presentation_sha256"], pinned["presentation_sha256"])
                    self.assertEqual(manifest["offline_gate"], "tests/offline_load.gd")
                    self.assertFalse(manifest["private_game_dependency"])
                    self.assertFalse(manifest["authoring_tools_required_at_runtime"])
                    self.assertFalse(manifest["external_v5_qualified"])
                    self.assertEqual(json.loads((project / "world.world.json").read_text(encoding="utf-8")), package)
                    for filename in ("offline_load.gd", "offline_load_expectations.json"):
                        self.assertEqual((project / "tests" / filename).read_bytes(),
                                         (WORLDGEN / "tests" / filename).read_bytes())
                    for filename in ("worldgen_package_loader.gd", "worldgen_package_validator.gd",
                                     "world_package_spatial_queries.gd"):
                        self.assertEqual((project / "addons/worldgen/core" / filename).read_bytes(),
                                         (WORLDGEN / "core" / filename).read_bytes())
                    self.assertFalse((project / "scripts").exists())
                    self.assertFalse((project / "data").exists())
                    self.assertFalse((project / "assets/worldgen_proxy.glb").exists())
                    self.assertFalse((project / "addons/worldgen/core/worldgen_build_service.gd").exists())

    def test_corrupted_package_cannot_be_exported(self):
        package_path = WORLDGEN / "builds/standalone_cafe.world.json"
        package = json.loads(package_path.read_text(encoding="utf-8"))
        package["semantic"]["kind"] = "corrupted"
        with tempfile.TemporaryDirectory() as folder:
            candidate = Path(folder) / "corrupted.world.json"
            candidate.write_text(json.dumps(package), encoding="utf-8")
            project = Path(folder) / "project"
            run = subprocess.run(
                [sys.executable, str(EXPORTER), "--package", str(candidate), "--output", str(project)],
                cwd=ROOT, capture_output=True, text=True, check=False,
            )
            self.assertNotEqual(run.returncode, 0)
            self.assertIn("E_PACKAGE_SEMANTIC_HASH", run.stderr + run.stdout)
            self.assertFalse(project.exists())


if __name__ == "__main__":
    unittest.main()
