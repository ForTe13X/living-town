"""Bounded numeric terrain regressions; temporary fixtures are not asset evidence."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from tools.town_upgrade import terrain_atlas as terrain


class TerrainAtlasTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="town-terrain-unit-")
        self.root = Path(self.scratch.name)
        self.sources = self.root / "source"
        self.guide = self.root / "guide.json"
        self.receipt = {"schema": "living_town.terrain_sources.v1", "license": "CC0-1.0", "assets": {}, "files": []}
        ramp = np.zeros((32, 32, 3), dtype=np.uint8)
        ramp[..., 0] = np.arange(32, dtype=np.uint8)[None, :] * 8
        ramp[..., 1] = np.arange(32, dtype=np.uint8)[:, None] * 8
        for asset in terrain.ASSETS:
            self.receipt["assets"][asset] = {"dimensions_mm": [1000, 1000]}
            for role, pixels in (("diff", ramp), ("nor_gl", np.full((32, 32, 3), [128, 128, 255], dtype=np.uint8)),
                                 ("arm", np.full((32, 32, 3), [220, 190, 0], dtype=np.uint8))):
                path = self.sources / asset / (role + ".jpg")
                path.parent.mkdir(parents=True, exist_ok=True)
                # Lossless, synthetic unit-test pixels; PIL detects the header.
                Image.fromarray(pixels).save(path, format="PNG")
                self.receipt["files"].append({"path": path.relative_to(self.sources).as_posix(), "sha256": terrain.sha(path)})
        self.write_receipt()
        self.guide.write_text(json.dumps({"bounds_xy_m": [0, 0, 1, 1], "trees": [], "slope_samples": []}), encoding="utf-8")

    def tearDown(self):
        self.scratch.cleanup()

    def write_receipt(self):
        (self.sources / "source_receipts.json").write_text(json.dumps(self.receipt), encoding="utf-8")

    def bake(self, suffix="atlas"):
        with contextlib.redirect_stdout(io.StringIO()):
            return terrain.bake(self.guide, self.sources, self.root / suffix, 64)

    def test_overlapping_woodland_is_independent_of_tree_iteration_order(self):
        a = {"position_m": [-140, 0, 0], "scale": [2, 2, 2]}
        b = {"position_m": [-130, 0, 0], "scale": [2, 2, 2]}
        base = {"bounds_xy_m": [-170, -10, -120, 10], "slope_samples": []}
        forward, _ = terrain.fields({**base, "trees": [a, b]}, 128)
        reverse, _ = terrain.fields({**base, "trees": [b, a]}, 128)
        np.testing.assert_array_equal(forward, reverse)
        self.assertGreater(float(forward.max()), .5)

    def test_bilinear_repeat_seam_is_continuous_at_positive_and_negative_periods(self):
        pixels = np.broadcast_to(np.arange(8, dtype=np.float32)[None, :, None], (8, 8, 3))
        for boundary in (-2, -1, 0, 1, 2):
            sides = terrain.sample(pixels, np.array([boundary - 1e-6, boundary + 1e-6]), np.array([.5, .5]), [1, 1])
            self.assertLess(float(np.abs(sides[0] - sides[1]).max()), .001)

    def test_world_atlas_preserves_east_and_north_orientation(self):
        result = self.bake()
        atlas = np.asarray(Image.open(self.root / "atlas" / result["maps"]["diff"]["path"]))
        # Source image top is north in the atlas; +X runs right. Avoid wrap edges.
        self.assertGreater(float(atlas[32, 48, 0]), float(atlas[32, 16, 0]) + 60)
        self.assertGreater(float(atlas[48, 32, 1]), float(atlas[16, 32, 1]) + 60)
        guide = {"bounds_xy_m": [0, 0, 10, 10], "trees": [], "slope_samples": [[2, 8, 1]]}
        _, rock = terrain.fields(guide, 128)
        row, column = np.unravel_index(np.argmax(rock), rock.shape)
        self.assertLess(row, 64)
        self.assertLess(column, 64)

    def test_flat_opengl_normal_survives_filtering_and_portable_bake(self):
        result = self.bake()
        normal = np.asarray(Image.open(self.root / "atlas" / result["maps"]["nor_gl"]["path"]), dtype=float)
        self.assertLess(float(np.abs(normal - [128, 128, 255]).max()), 3)
        self.assertEqual(result["status"], "BAKED_REQUIRES_VISUAL_REVIEW")

    def replace_role(self, role, pixels):
        for record in self.receipt["files"]:
            if record["path"].endswith("/" + role + ".jpg"):
                path = self.sources / record["path"]
                Image.fromarray(pixels).save(path, format="PNG")
                record["sha256"] = terrain.sha(path)
        self.write_receipt()

    def test_positive_opengl_green_lobe_is_not_directx_flipped(self):
        self.replace_role("nor_gl", np.full((32, 32, 3), [128, 192, 238], dtype=np.uint8))
        result = self.bake()
        normal = np.asarray(Image.open(self.root / "atlas" / result["maps"]["nor_gl"]["path"]))
        self.assertGreater(float(normal[..., 1].mean()), 180)

    def test_coarse_albedo_is_filtered_in_linear_light(self):
        checker = np.indices((32, 32)).sum(axis=0) % 2 * 255
        self.replace_role("diff", np.repeat(checker[..., None], 3, axis=2).astype(np.uint8))
        self.guide.write_text(json.dumps({"bounds_xy_m": [0, 0, 100, 100], "trees": [], "slope_samples": []}), encoding="utf-8")
        result = self.bake()
        color = np.asarray(Image.open(self.root / "atlas" / result["maps"]["diff"]["path"]))
        # Linear mean .5 encodes near188sRGB, with bounded authored macro tint.
        # Point sampling aliases black/white; sRGB-space filtering gives~128.
        self.assertGreater(float(color.mean()), 170)
        self.assertLess(float(color.std()), 18)

    def test_invalid_physical_repeat_dimensions_are_rejected(self):
        for index, dimensions in enumerate(([0, 1000], [-1, 1000], [float("nan"), 1000], [float("inf"), 1000], [1000])):
            with self.subTest(dimensions=dimensions):
                self.receipt["assets"][terrain.ASSETS[0]]["dimensions_mm"] = dimensions
                self.write_receipt()
                with self.assertRaises(ValueError):
                    self.bake("invalid_" + str(index))

    def test_changed_source_map_cannot_receive_a_valid_bake_receipt(self):
        path = self.sources / terrain.ASSETS[0] / "diff.jpg"
        path.write_bytes(path.read_bytes() + b"changed unit-test source")
        with self.assertRaisesRegex(ValueError, "Changed CC0 terrain scan"):
            self.bake()
        self.assertFalse((self.root / "atlas/terrain_atlas_receipt.json").exists())


if __name__ == "__main__":
    unittest.main()
