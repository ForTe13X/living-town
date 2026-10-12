"""Fast adversarial checks for the portable capture evidence boundary."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import source_copy
import verify_run


class CapturePathTests(unittest.TestCase):
    def test_windows_and_posix_escape_names_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bad = (
                "C:evil.png", "C:/evil.png", "\\\\server\\share\\evil.png",
                "observations/C:evil.png", "observations/\\\\server\\share.png",
                "observations/../evil.png", "observations//evil.png",
                "observations/./evil.png", "/observations/evil.png",
                "observations/CON.png", "observations/evil.png:stream",
            )
            for name in bad:
                with self.subTest(name=name), self.assertRaises(ValueError):
                    source_copy.safe_relative_target(root, name)
            self.assertEqual(source_copy.safe_relative_target(root, "observations/000001.png"),
                             root.resolve() / "observations" / "000001.png")

    def test_png_must_be_one_file_below_observations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("observations/C:evil.png", "observations/../evil.png",
                         "observations/nested/evil.png", "other/evil.png"):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    verify_run.relative_png(root, name)
            self.assertEqual(verify_run.relative_png(root, "observations/000001.png"),
                             root.resolve() / "observations" / "000001.png")

    def test_symlink_escape_is_rejected_when_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "root"
            outside = Path(temporary) / "outside"
            root.mkdir()
            outside.mkdir()
            try:
                (root / "observations").symlink_to(outside, target_is_directory=True)
            except OSError as exc:
                self.skipTest(f"Directory symlink unavailable: {exc}")
            with self.assertRaises(ValueError):
                source_copy.safe_relative_target(root, "observations/000001.png")


class CaptureReceiptTests(unittest.TestCase):
    def test_receipt_binds_exact_processed_command_and_result(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "000001.json"
            command = {"schema": "living-town.agent-command/1", "seq": 1,
                       "action": "key", "code": "F5", "hold_ms": 80, "settle_ms": 160}
            path.write_text(json.dumps(command), encoding="utf-8")
            receipt = {"schema": "living-town.agent-receipt/1", "seq": 1,
                       "accepted": True, "rendered_capture_ok": True,
                       "action": "key", "result": {"code": "F5", "route": "Input.parse_input_event"},
                       "before_observation": 0, "after_observation": 1,
                       "command_sha256": verify_run.digest(path)}
            verify_run.verify_action_receipt(path, command, receipt, 1)
            forged = {**command, "code": "F8"}
            with self.assertRaises(ValueError):
                verify_run.verify_action_receipt(path, forged, receipt, 1)
            forged = {**command, "hold_ms": 500}
            path.write_text(json.dumps(forged), encoding="utf-8")
            with self.assertRaises(ValueError):
                verify_run.verify_action_receipt(path, forged, receipt, 1)

    def test_supervisor_project_and_bridge_share_original_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            leg = Path(temporary) / "session"
            manifest = {"user_dir_name": "LivingTownCapture_abc", "source_game_tree": "product-tree",
                        "instrumentation_commit": "head"}
            receipt = {"repo": r"C:\repo", "project_path": r"D:\capture\game", "game_tree": "instrument-tree",
                       "game_tree_after": "instrument-tree", "source_head_after": "head",
                       "arguments": ["--script", r"C:\repo\tools\in_game_capture\live_bridge.gd",
                                     "--", "--bridge-dir", r"D:\capture\session",
                                     "--expected-user-dir-name", "LivingTownCapture_abc"]}
            verify_run.verify_supervisor_origin(receipt, leg, manifest)
            receipt["project_path"] = r"D:\unrelated\game"
            with self.assertRaises(ValueError):
                verify_run.verify_supervisor_origin(receipt, leg, manifest)
            receipt["project_path"] = r"D:\capture\game"
            receipt["game_tree_after"] = "drifted-tree"
            with self.assertRaises(ValueError):
                verify_run.verify_supervisor_origin(receipt, leg, manifest)

    def test_retained_supervisor_logs_are_hashed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run-id"
            run.mkdir()
            receipt_path = run / "receipt.json"
            files = {}
            for kind in ("godot", "stdout", "stderr"):
                data = kind.encode("ascii")
                (run / f"{kind}.log").write_bytes(data)
                files[kind] = {"path": f"D:\\capture\\session\\supervisor\\run-id\\{kind}.log",
                               "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            receipt = {"run_id": "run-id", "files": files,
                       "injected_log": files["godot"]["path"]}
            verify_run.verify_supervisor_logs(receipt_path, receipt)
            (run / "stdout.log").write_bytes(b"changed")
            with self.assertRaises(ValueError):
                verify_run.verify_supervisor_logs(receipt_path, receipt)


if __name__ == "__main__":
    unittest.main()
