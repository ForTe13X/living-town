from __future__ import annotations

import copy
import importlib.util
import json
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
        self.assertEqual(VERIFY.ANCHOR_COMMIT, report["source_receipt"]["anchor_commit"])
        self.assertEqual("descendant_or_equal", report["source_receipt"]["head_relation"])
        self.assertTrue(report["source_receipt"]["lineage_verified"])
        self.assertEqual(
            len(VERIFY.ANCHORED_PATHS),
            report["source_receipt"]["anchored_path_count"],
        )
        self.assertFalse(report["manifest"]["self_referential"])

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

    def test_05_anchor_is_real_ancestor_and_all_declared_blobs_are_exact(self) -> None:
        metadata, entries = VERIFY.parse_manifest(MEDIA_DIR / "media_manifest.sha256")
        receipt = VERIFY.verify_anchor_receipt(
            ROOT,
            metadata["anchor_commit"],
            VERIFY.ANCHORED_PATHS,
            entries,
        )
        self.assertEqual([], receipt["issues"])
        self.assertTrue(receipt["lineage_verified"])
        self.assertEqual("descendant_or_equal", receipt["head_relation"])
        self.assertEqual(set(VERIFY.ANCHORED_PATHS), set(receipt["anchored_sha256"]))

    def test_06_invalid_and_unknown_40hex_commits_fail_closed(self) -> None:
        invalid = VERIFY.verify_anchor_receipt(ROOT, "not-a-commit", (), {})
        unknown = VERIFY.verify_anchor_receipt(ROOT, "f" * 40, (), {})
        self.assertIn("ANCHOR_COMMIT_INVALID", invalid["issues"])
        self.assertIn("ANCHOR_COMMIT_UNREADABLE", unknown["issues"])

    def test_07_forged_40hex_blob_is_not_accepted_as_a_commit(self) -> None:
        blob = VERIFY._git(
            ROOT,
            "rev-parse",
            f"HEAD:{VERIFY.ANCHORED_PATHS[0]}",
        ).stdout.decode().strip()
        self.assertEqual(40, len(blob))
        report = VERIFY.verify_anchor_receipt(ROOT, blob, (), {})
        self.assertIn("ANCHOR_OBJECT_NOT_COMMIT", report["issues"])

    def test_08_real_git_provenance_mutations_are_all_detected(self) -> None:
        cases = VERIFY.run_git_mutation_probes(ROOT)
        expected = {
            "mutation.anchor_invalid_commit_syntax",
            "mutation.anchor_unknown_40hex_commit",
            "mutation.anchor_40hex_blob_forgery",
            "mutation.head_non_ancestor",
            "mutation.anchored_head_blob_drift",
            "mutation.anchor_path_missing",
            "mutation.anchored_worktree_drift",
        }
        self.assertEqual(expected, {case["id"] for case in cases})
        self.assertTrue(all(case["detected"] for case in cases), json.dumps(cases, indent=2))


if __name__ == "__main__":
    unittest.main()
