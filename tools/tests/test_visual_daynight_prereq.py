"""Focused positive-arm and source-isolation checks for LT-06."""

from __future__ import annotations

import contextlib
import io
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

from tools import assert_daynight, prepare_visual_canary_negative


ROOT = Path(__file__).resolve().parents[2]


def _chunk(kind: bytes, body: bytes) -> bytes:
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def _png(path: Path, rgb: tuple[int, int, int]) -> None:
    width, height = 128, 77
    raw = b"".join(b"\0" + bytes(rgb) * width for _ in range(height))
    data = (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw)) + _chunk(b"IEND", b""))
    path.write_bytes(data)


class DaynightPrereqTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.frames = self.base / "frames"
        self.frames.mkdir()
        self.receipts = self.base / "receipts"

    def check(self) -> tuple[int, dict]:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/visual_daynight_prereq.py"),
             str(self.frames), str(self.receipts), "4"], capture_output=True, text=True)
        record = json.loads((self.receipts / "daynight-prereq.json").read_text(encoding="utf-8"))
        return result.returncode, record

    def test_valid_daynight_pair_runs_negative_even_without_full_suite_verdict(self) -> None:
        noon = (215, 207, 183)
        night = assert_daynight.modulated(noon, 8 / 240)
        _png(self.frames / "vg_noon.png", noon)
        _png(self.frames / "vg_night.png", night)
        code, record = self.check()
        self.assertEqual((code, record["verdict"]), (0, "ready"))
        self.assertEqual(set(record["frame_sha256"]), {"night", "noon"})

    def test_identical_frames_are_product_failure(self) -> None:
        for name in ("night", "noon"):
            _png(self.frames / f"vg_{name}.png", (215, 207, 183))
        code, record = self.check()
        self.assertEqual((code, record["verdict"]), (77, "daynight_product_fail"))

    def test_missing_and_corrupt_frames_are_evidence_failures(self) -> None:
        _png(self.frames / "vg_noon.png", (215, 207, 183))
        code, record = self.check()
        self.assertEqual((code, record["verdict"]), (77, "missing_evidence"))
        (self.frames / "vg_night.png").write_bytes(b"not a PNG")
        code, record = self.check()
        self.assertEqual((code, record["verdict"]), (77, "corrupt_evidence"))


class NegativeCopyTests(unittest.TestCase):
    def test_only_startup_assignment_changes_in_isolated_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source, dest = base / "source", base / "negative"
            (source / "scripts").mkdir(parents=True)
            main = (b"\t_modulate = CanvasModulate.new()\n"
                    + b"\t_modulate.color = _daylight(Sim.time_of_day())\n"
                    + b"\t_goals = null\n"
                    + b"\t_modulate.color = _daylight(Sim.time_of_day())\n" * 3)
            (source / "scripts/Main.gd").write_bytes(main)
            (source / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            (source / ".godot").mkdir()
            (source / ".godot/cache").write_bytes(b"rebuildable")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = prepare_visual_canary_negative.main([str(source), str(dest)])
            self.assertEqual(code, 0)
            receipt = json.loads(output.getvalue())
            self.assertTrue(receipt["source_unchanged"])
            self.assertEqual(receipt["negative_changed_paths"], ["scripts/Main.gd"])
            self.assertEqual(receipt["source_tree_sha256_before"], receipt["source_tree_sha256_after"])
            self.assertEqual(receipt["source_tree_sha256_before"], receipt["copied_tree_sha256_before"])
            self.assertEqual((source / "scripts/Main.gd").read_bytes(), main)
            self.assertFalse((dest / ".godot").exists())
            self.assertEqual((source / "project.godot").read_bytes(), (dest / "project.godot").read_bytes())


if __name__ == "__main__":
    unittest.main()
