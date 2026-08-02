from __future__ import annotations

import copy
import importlib.util
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MEDIA_DIR = ROOT / "analysis" / "narrative_visual" / "s13"
VERIFY_PATH = MEDIA_DIR / "verify_review_media.py"
GATE_PATH = MEDIA_DIR / "media_gate.json"

SPEC = importlib.util.spec_from_file_location("verify_review_media", VERIFY_PATH)
assert SPEC and SPEC.loader
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class S13RReviewMediaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ffmpeg = shutil.which("ffmpeg")
        cls.ffprobe = shutil.which("ffprobe")
        if cls.ffmpeg is None or cls.ffprobe is None:
            raise unittest.SkipTest("ffmpeg and ffprobe are required")

    def test_01_canonical_gate_is_live_rendered_and_source_bound(self) -> None:
        report = VERIFY.audit_canonical(ROOT, ffmpeg=self.ffmpeg, ffprobe=self.ffprobe)
        self.assertEqual("PASS", report["verdict"], report["issues"])
        self.assertEqual(GATE_PATH.read_bytes(), VERIFY.render_report(report))
        self.assertEqual(VERIFY.WATERMARK_TEXT, report["watermark_text"])
        self.assertTrue(all(item["present"] for item in report["images"].values()))
        self.assertTrue(
            all(item["present"] for item in report["video"]["watermark_frames"].values())
        )

    def test_02_erased_png_watermark_band_fails(self) -> None:
        with tempfile.TemporaryDirectory() as raw_temp:
            mutated = Path(raw_temp) / "role_pair.png"
            VERIFY.erase_watermark_band(MEDIA_DIR / "role_pair.png", mutated)
            report = VERIFY.inspect_watermark(mutated, require_near_bottom=True)
        self.assertFalse(report["present"])

    def test_03_missing_video_not_gameplay_metadata_fails(self) -> None:
        probe = VERIFY.probe_video(MEDIA_DIR / "component_reel.mp4", self.ffprobe)
        mutated = copy.deepcopy(probe)
        mutated.setdefault("format", {})["tags"] = {}
        issues, _ = VERIFY.validate_video_probe(mutated)
        self.assertIn("VIDEO_TITLE_NOT_GAMEPLAY_MISSING", issues)
        self.assertIn("VIDEO_COMMENT_NOT_GAMEPLAY_MISSING", issues)

    def test_04_manifest_hash_drift_fails(self) -> None:
        metadata, entries = VERIFY.parse_manifest(MEDIA_DIR / "media_manifest.sha256")
        mutated = dict(entries)
        mutated["analysis/narrative_visual/s13/role_pair.png"] = "0" * 64
        issues = VERIFY.verify_manifest(ROOT, metadata, mutated)
        self.assertTrue(any(issue.startswith("MANIFEST_HASH_MISMATCH") for issue in issues))


if __name__ == "__main__":
    unittest.main()
