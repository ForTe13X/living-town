"""Meaningful image/physical-unit checks for the source-bound facade bake."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image


SOURCE = Path(__file__).resolve().parents[1] / "asset_refinement/hero_walls.py"
SPEC = importlib.util.spec_from_file_location("hero_walls_tested", SOURCE)
WALLS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WALLS)


class WallBakeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        source = cls.root / "scan"
        source.mkdir()
        maps = {}
        # Uniform test scan isolates the new, metre-scale authored context.
        pixels = {"basecolor": np.full((128, 128, 3), [224, 218, 204], dtype=np.uint8),
                  "roughness": np.full((128, 128), 210, dtype=np.uint8),
                  "normal": np.full((128, 128, 3), [128, 128, 255], dtype=np.uint8)}
        for role, array in pixels.items():
            path = source / (role + ".png")
            Image.fromarray(array).save(path)
            maps[role] = {"path": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                          "dimensions": [128, 128]}
        manifest = {"schema": "living_town.scanned_pbr_library.v1", "roles": {"plaster": "test"},
                    "materials": {"test": {"license": "CC0-1.0", "normal_convention": "OpenGL +Y",
                                           "repeat_metres": [1, 1], "maps": maps}}}
        cls.library = source / "library.json"
        cls.library.write_text(json.dumps(manifest))
        cls.record = WALLS.generate(cls.root / "baked", cls.library, size=256)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_broad_limewash_context_survives_street_scale_downsample(self):
        with Image.open(self.root / "baked/facade_basecolor.png") as image:
            small = np.asarray(image.resize((150, 100), Image.Resampling.LANCZOS), dtype=float)
        # A perfectly smooth scan should still read as maintained, varied paint
        # at the street camera. This fails the old subpixel-only scan treatment.
        self.assertGreater(small.std(axis=(0, 1)).min(), 7)
        self.assertLess(small.std(axis=(0, 1)).max(), 21)
        self.assertGreater(small.mean(axis=(0, 1)).min(), 190)
        self.assertLess(np.quantile(small.mean(axis=-1), .98) - np.quantile(small.mean(axis=-1), .02), 65)

    def test_sill_runoff_has_structured_spatial_effect(self):
        other = self.root / "no_sills"
        WALLS.generate(other, self.library, size=256, windows=[])
        with Image.open(self.root / "baked/facade_basecolor.png") as image:
            stained = np.asarray(image, dtype=float).mean(axis=-1)
        with Image.open(other / "facade_basecolor.png") as image:
            plain = np.asarray(image, dtype=float).mean(axis=-1)
        delta = plain - stained
        x = np.linspace(-4.3, 4.3, 256)[None, :]
        z = np.linspace(6.5, 0, 256)[:, None]
        below_sills = (abs(x) < .6) & (z > 3.1) & (z < 3.975)
        above_sills = (abs(x) < .6) & (z > 4.1) & (z < 4.7)
        self.assertGreater(delta[below_sills].mean(), 2)
        self.assertLess(abs(delta[above_sills].mean()), .1)

    def test_height_units_uint16_normal_direction_and_actual_output_hashes(self):
        for role, row in self.record["maps"].items():
            path = self.root / "baked" / row["path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
            with Image.open(path) as image:
                self.assertEqual(image.size, (256, 256))
                if role == "height":
                    height = np.asarray(image)
                    self.assertGreaterEqual(height.max(), 65534)
                    self.assertEqual(height.min(), 0)
                    self.assertEqual(row["bit_depth"], 16)
                if role == "normal":
                    normal = np.asarray(image, dtype=float) / 255 * 2 - 1
                    self.assertLess(abs(np.linalg.norm(normal, axis=-1) - 1).max(), .009)
                    self.assertGreater(normal[..., 2].min(), .98)
        encoding = self.record["height_encoding"]
        self.assertEqual(encoding["minimum_metres"], .0007)
        self.assertEqual(encoding["maximum_metres"], .004)
        height = np.broadcast_to(np.linspace(0, .003, 101)[:, None], (101, 201))
        normals = WALLS._height_normal(height, width_m=2, height_m=1)
        self.assertGreater(normals[50, 100, 1], 0)
        self.assertAlmostEqual(normals[50, 100, 1], .003, places=6)
        self.assertAlmostEqual(normals[50, 100, 0], 0)

    def test_scan_repeat_keeps_one_metre_size_on_different_facades(self):
        source = np.broadcast_to(np.sin(np.arange(128) / 128 * 2 * np.pi), (128, 128))
        a = WALLS._tile_rows(source, 0, 257, 257, 4, 4, (1, 1))
        b = WALLS._tile_rows(source, 0, 513, 513, 8, 8, (1, 1))
        np.testing.assert_allclose(a[:, :65], b[:257, :65], atol=1e-6)
        np.testing.assert_allclose(a[:, :65], a[:, 64:129], atol=1e-6)

    def test_neighbour_context_and_seed_reproducibility(self):
        kwargs = dict(size=128, width_m=5.4, height_m=6.1,
                      windows=[(-1.45, .9, 1.1, 1.5), (1.45, 3.8, 1.1, 1.5)],
                      palette_srgb=[194, 168, 117])
        first = WALLS.generate(self.root / "neighbour", self.library, **kwargs)
        second = WALLS.generate(self.root / "same", self.library, **kwargs)
        changed = WALLS.generate(self.root / "different", self.library, seed=123, **kwargs)
        self.assertEqual(first["facade_dimensions_metres"], [5.4, 6.1])
        for role in first["maps"]:
            self.assertEqual(first["maps"][role]["sha256"], second["maps"][role]["sha256"])
            self.assertNotEqual(first["maps"][role]["sha256"], changed["maps"][role]["sha256"])

    def test_bad_input_and_changed_source_fail_before_output_created(self):
        bad = self.root / "bad"
        for kwargs in ({"size": 64}, {"size": True}, {"seed": -1}, {"width_m": 0},
                       {"height_m": float("nan")}, {"windows": [(0, 1, -1, 1)]},
                       {"palette_srgb": [256, 2, 3]}):
            with self.assertRaises(ValueError):
                WALLS.generate(bad, self.library, **kwargs)
        self.assertFalse(bad.exists())
        with self.assertRaises(FileExistsError):
            WALLS.generate(self.root / "baked", self.library, size=128)
        corrupt = json.loads(self.library.read_text())
        corrupt["materials"]["test"]["maps"]["normal"]["sha256"] = "0" * 64
        path = self.library.parent / "corrupt.json"
        path.write_text(json.dumps(corrupt))
        with self.assertRaises(ValueError):
            WALLS.generate(bad, path, size=128)
        self.assertFalse(bad.exists())


if __name__ == "__main__":
    unittest.main()
