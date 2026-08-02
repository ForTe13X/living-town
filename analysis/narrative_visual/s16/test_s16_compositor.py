from __future__ import annotations

import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
S16 = ROOT / "game" / "narrative_lab" / "s16"
MEDIA = ROOT / "analysis" / "narrative_visual" / "s16"
FIXTURE = S16 / "fixtures" / "s16_compositor_projection.json"
RECEIPT = S16 / "fixtures" / "source_receipt.json"
COMPOSITOR = S16 / "scripts" / "S16Compositor.gd"
AUDIT = MEDIA / "audit.json"
GATE = MEDIA / "media_gate.json"
LAB_ROOT = ROOT.parents[1] / "living-town-narrative-lab"
VERIFIER_PATH = MEDIA / "verify_s16_artifacts.py"

SPEC = importlib.util.spec_from_file_location("s16_media_verifier", VERIFIER_PATH)
assert SPEC and SPEC.loader
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)

EXPECTED_BANNER = "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE"
EXPECTED_FIXTURE_SHA256 = (
    "90ddd379d67b3e251ac0113a548706c95f840ae6c5aea0ee50a587a2ab3e8198"
)
EXPECTED_SOURCE_COMMIT = "1a195e06f1dd6b6aef2668906d6a816b8799e67b"
EXPECTED_SCREENSHOTS = {
    "compositor_1024x768.png": (1024, 768),
    "compositor_1280x768.png": (1280, 768),
    "compositor_2688x1216.png": (2688, 1216),
}


class S16CompositorArtifactTests(unittest.TestCase):
    maxDiff = None

    def test_01_fixture_is_exact_source_bound_copy(self) -> None:
        self.assertTrue(FIXTURE.is_file())
        self.assertEqual(EXPECTED_FIXTURE_SHA256, hashlib.sha256(FIXTURE.read_bytes()).hexdigest())
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
        self.assertEqual(EXPECTED_FIXTURE_SHA256, receipt["sha256"])
        self.assertEqual(EXPECTED_SOURCE_COMMIT, receipt["lab_commit"])
        self.assertEqual(
            "artifacts/integration/s16_compositor_projection.json",
            receipt["lab_path"],
        )

    def test_02_fixture_is_committed_trace_not_sim(self) -> None:
        value = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual("READ_ONLY_COMMITTED_TRACE", value["mode"])
        self.assertEqual("NOT_SIM", value["simulation"])
        self.assertFalse(value["production_gate"])
        self.assertEqual(list(range(13)), [frame["offset"] for frame in value["frames"]])
        self.assertTrue(all(frame["transition"] is None or frame["transition"]["outcome"] == "committed" for frame in value["frames"]))

    def test_03_compositor_declares_one_dispatcher_and_no_raw_mouse_handler(self) -> None:
        source = COMPOSITOR.read_text(encoding="utf-8")
        self.assertIn(EXPECTED_BANNER, source)
        self.assertEqual(1, source.count("func _dispatch("))
        for action in (
            "focus_role",
            "select_node",
            "view_traverse",
            "compare_handoff",
            "scrub_replay",
        ):
            self.assertIn(f'"{action}"', source)
        self.assertNotIn("InputEventMouseButton", source)
        self.assertIn("InputEventScreenTouch", source)

    def test_04_audit_is_honest_and_exact(self) -> None:
        value = json.loads(AUDIT.read_text(encoding="utf-8"))
        self.assertEqual("PASS_WITH_BLOCKERS", value["result"])
        self.assertFalse(value["production_gate"])
        self.assertEqual(EXPECTED_BANNER, value["banner"])
        self.assertEqual(13, value["metrics"]["frames"])
        self.assertEqual(10, value["metrics"]["snapshot_fields"])
        self.assertEqual(5, value["metrics"]["dispatcher_actions"])
        self.assertEqual(3, value["metrics"]["responsive_layouts"])
        self.assertTrue(value["checks"]["handoff_half_mutation_rejected"])
        self.assertTrue(value["checks"]["replay_fingerprints_stable"])
        self.assertTrue(value["checks"]["source_trace_unchanged"])

    def test_05_screenshots_have_exact_sizes_and_banner_band(self) -> None:
        for name, expected_size in EXPECTED_SCREENSHOTS.items():
            with self.subTest(name=name):
                image = Image.open(MEDIA / name).convert("RGB")
                self.assertEqual(expected_size, image.size)
                width, _ = image.size
                accent = 0
                for y in range(46, 55):
                    accent = max(
                        accent,
                        sum(
                            1
                            for x in range(width)
                            if (lambda p: p[0] >= 180 and 80 <= p[1] <= 180 and p[2] <= 130)(
                                image.getpixel((x, y))
                            )
                        ),
                    )
                self.assertGreaterEqual(accent, int(width * 0.85))

    def test_06_live_gate_is_exact_and_passes(self) -> None:
        report = VERIFIER.build_report(ROOT, LAB_ROOT)
        self.assertEqual("PASS", report["verdict"])
        self.assertEqual([], report["issues"])
        self.assertEqual(GATE.read_bytes(), VERIFIER.render_report(report))

    def test_07_low_cost_mutations_are_detected(self) -> None:
        fixture_bytes = FIXTURE.read_bytes()
        self.assertTrue(VERIFIER.fixture_bytes_valid(fixture_bytes))
        self.assertFalse(VERIFIER.fixture_bytes_valid(fixture_bytes + b"tamper"))
        blank = Image.new("RGB", (1024, 768), "black")
        self.assertEqual(0, VERIFIER.banner_pixels(blank))


if __name__ == "__main__":
    unittest.main()
