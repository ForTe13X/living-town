"""Image-level checks for the isolated original material generator."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image


SOURCE = Path(__file__).resolve().parents[1] / "asset_refinement/materials.py"
SPEC = importlib.util.spec_from_file_location("refinement_materials", SOURCE)
MATERIALS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATERIALS)


class RefinementMaterialsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.manifest = MATERIALS.generate_materials(cls.root / "first", size=128)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_repeat_seed_produces_exact_files_and_changed_seed_changes_maps(self):
        second = self.root / "same"
        third = self.root / "different"
        MATERIALS.generate_materials(second, size=128)
        MATERIALS.generate_materials(third, size=128, seed=20261020)
        for first in (self.root / "first").iterdir():
            self.assertEqual(first.read_bytes(), (second / first.name).read_bytes(), first.name)
            self.assertNotEqual(first.read_bytes(), (third / first.name).read_bytes(), first.name)

    def test_real_images_match_hashes_dimensions_spaces_and_periodic_edges(self):
        self.assertEqual(self.manifest, json.loads((self.root / "first/material_manifest.json").read_text()))
        for record in self.manifest["materials"].values():
            self.assertEqual(record["tile_size_metres"], 2.0)
            for kind, meta in record["maps"].items():
                path = self.root / "first" / meta["file"]
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), meta["sha256"])
                with Image.open(path) as image:
                    self.assertEqual(list(image.size), meta["dimensions"])
                    a = np.asarray(image)
                self.assertTrue(np.array_equal(a[0], a[-1]), meta["file"])
                self.assertTrue(np.array_equal(a[:, 0], a[:, -1]), meta["file"])
                self.assertTrue(all(meta["seam_checks"].values()))
                self.assertEqual(meta["color_space"], "sRGB" if kind == "basecolor" else "Non-Color")

    def test_physically_restrained_normals_roughness_and_nonuniform_albedo(self):
        for family, record in self.manifest["materials"].items():
            def read(kind):
                with Image.open(self.root / "first" / record[kind]) as image:
                    return np.asarray(image, dtype=float)
            normal = read("normal") / 255 * 2 - 1
            self.assertLess(np.abs(np.linalg.norm(normal, axis=-1) - 1).max(), .009)
            self.assertGreater(normal[..., 2].min(), .98, family)
            rough = read("roughness") / 255
            self.assertGreater(rough.min(), .30)
            self.assertLess(rough.max(), .68)
            self.assertGreater(rough.std(), .008)
            rgb = read("basecolor")
            self.assertGreater(rgb.std(axis=(0, 1)).min(), 2.0)
            self.assertLess(rgb.std(axis=(0, 1)).max(), 16.0)

    def test_no_continuous_dark_mortar_or_plank_joint_lines(self):
        # Original floor/masonry recipes fail this: a seam becomes a long dark
        # row/column. Grain/minerals may be locally dark but must not draw joints
        # across almost the entire repeat. Check both axes and every scan line.
        for family, record in self.manifest["materials"].items():
            with Image.open(self.root / "first" / record["basecolor"]) as image:
                gray = np.asarray(image, dtype=float)[..., :3].mean(axis=-1)[:-1, :-1]
            dark = gray < np.quantile(gray, .12)
            self.assertLess(dark.mean(axis=0).max(), .70, family)
            self.assertLess(dark.mean(axis=1).max(), .70, family)

    def test_normal_y_convention_uses_physical_height_gradient(self):
        n = 127
        v = np.arange(n, dtype=float) / n
        height = np.broadcast_to(np.sin(2 * np.pi * v)[:, None] * .002, (n, n))
        normal = MATERIALS._normal(height).astype(float) / 255 * 2 - 1
        self.assertGreater(normal[0, 0, 1], 0)  # Height increases down the image.
        self.assertLess(normal[n // 2, 0, 1], 0)
        # A 2 mm sine over 2 m has slope ~0.0063, not a unitless bump.
        self.assertLess(abs(normal[0, 0, 1]), .015)

    def test_rejects_invalid_input_without_creating_output(self):
        target = self.root / "invalid"
        for kwargs in ({"size": 31}, {"size": True}, {"seed": -1}, {"seed": False}):
            with self.assertRaises(ValueError):
                MATERIALS.generate_materials(target, **kwargs)
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
