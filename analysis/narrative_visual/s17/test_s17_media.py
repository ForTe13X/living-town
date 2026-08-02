from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
MEDIA = ROOT / "analysis" / "narrative_visual" / "s17"
VERIFIER_PATH = MEDIA / "verify_s17_media.py"
GATE = MEDIA / "media_gate.json"
CAPTURE_RECEIPT = MEDIA / "capture_receipt.json"
VIDEO = MEDIA / "compositor_read_only_review.mp4"
CONTACT_SHEET = MEDIA / "contact_sheet.png"
BANNER = "NARRATIVE LAB · NOT SIM · READ-ONLY COMMITTED TRACE · NOT GAMEPLAY"
STATE_NAMES = [
    "state_01_focus_role.png",
    "state_02_select_node.png",
    "state_03_view_traverse.png",
    "state_04_compare_handoff.png",
    "state_05_scrub_replay.png",
]


class S17MediaTests(unittest.TestCase):
    maxDiff = None

    def _verifier(self):
        self.assertTrue(VERIFIER_PATH.is_file())
        spec = importlib.util.spec_from_file_location("s17_verifier", VERIFIER_PATH)
        assert spec and spec.loader
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_01_five_dispatcher_states_are_source_bound(self) -> None:
        receipt = json.loads(CAPTURE_RECEIPT.read_text(encoding="utf-8"))
        self.assertEqual(BANNER, receipt["banner"])
        self.assertEqual(
            ["focus_role", "select_node", "view_traverse", "compare_handoff", "scrub_replay"],
            [item["action_id"] for item in receipt["captures"]],
        )
        self.assertTrue(receipt["source_trace_unchanged"])
        for item, name in zip(receipt["captures"], STATE_NAMES, strict=True):
            path = MEDIA / name
            with Image.open(path) as image:
                self.assertEqual((1280, 768), image.size)
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), item["sha256"])

    def test_02_live_gate_is_exact_and_passes(self) -> None:
        verifier = self._verifier()
        report = verifier.build_report(ROOT, "ffmpeg", "ffprobe")
        self.assertEqual("PASS", report["verdict"])
        self.assertEqual([], report["issues"])
        self.assertEqual(GATE.read_bytes(), verifier.render_report(report))

    def test_03_contact_sheet_is_review_media(self) -> None:
        with Image.open(CONTACT_SHEET) as image:
            self.assertEqual((1920, 1080), image.size)
        receipt = json.loads(CAPTURE_RECEIPT.read_text(encoding="utf-8"))
        self.assertEqual("component_review_not_sim_not_gameplay", receipt["media_kind"])

    def test_04_metadata_erasure_is_detected(self) -> None:
        verifier = self._verifier()
        with tempfile.TemporaryDirectory() as holder:
            stripped = Path(holder) / "stripped.mp4"
            subprocess.run(
                [
                    "ffmpeg",
                    "-v",
                    "error",
                    "-i",
                    str(VIDEO),
                    "-map",
                    "0",
                    "-map_metadata",
                    "-1",
                    "-c",
                    "copy",
                    "-y",
                    str(stripped),
                ],
                check=True,
            )
            issues = verifier.video_issues(stripped, "ffmpeg", "ffprobe")
            self.assertIn("VIDEO_TITLE_INVALID", {item["code"] for item in issues})
            self.assertIn("VIDEO_COMMENT_INVALID", {item["code"] for item in issues})

    def test_05_banner_erasure_is_detected(self) -> None:
        verifier = self._verifier()
        blank = Image.new("RGB", (1280, 768), "black")
        self.assertFalse(verifier.banner_present(blank))


if __name__ == "__main__":
    unittest.main()
