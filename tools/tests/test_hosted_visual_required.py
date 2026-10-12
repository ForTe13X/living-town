"""Required hosted visual policy checks, using receipts without launching Godot."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/assert_hosted_visual_required.py"
POLICY = ROOT / "analysis/p1z/hosted_visual_runtime_policy.json"
PASS_POSITIVE = "VISUAL_CANARY verdict=pass rc=0 png_count=75 runtime_errors=0\n"
PASS_NEGATIVE = (
    "VISUAL_NEGATIVE verdict=caught_expected_daynight_fault "
    "shot_rc=0 assert_rc=1 a1=1 a2=1 gate=1 runtime_errors=0\n"
)


class HostedVisualRequiredTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        self.runtime = base / "visual-runtime.txt"
        self.positive = base / "visual-verdict.txt"
        self.negative = base / "negative-verdict.txt"
        required = json.loads(POLICY.read_text(encoding="utf-8"))["required_lines"]
        self.runtime.write_text("\n".join(required.values()) + "\n", encoding="utf-8")
        self.positive.write_text(PASS_POSITIVE, encoding="utf-8")
        self.negative.write_text(PASS_NEGATIVE, encoding="utf-8")

    def run_policy(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--runtime", str(self.runtime),
             "--positive", str(self.positive), "--negative", str(self.negative),
             "--policy", str(POLICY)],
            capture_output=True, text=True, check=False,
        )

    def test_reviewed_positive_and_expected_negative_pass(self) -> None:
        result = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HOSTED_VISUAL_REQUIRED PASS", result.stdout)

    def test_candidate_fail_and_skip_are_nonpassing_verdicts(self) -> None:
        for receipt in (
            "VISUAL_CANARY verdict=candidate_fail rc=1 png_count=75 runtime_errors=0\n",
            "VISUAL_CANARY verdict=skip rc=77 png_count=0 runtime_errors=0\n",
        ):
            with self.subTest(receipt=receipt):
                self.positive.write_text(receipt, encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 1)
                self.assertIn("positive: nonpassing verdict=", result.stderr)

    def test_empty_png_set_and_runtime_error_fail(self) -> None:
        self.positive.write_text(
            "VISUAL_CANARY verdict=pass rc=0 png_count=0 runtime_errors=1\n",
            encoding="utf-8",
        )
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("positive: empty PNG set", result.stderr)
        self.assertIn("positive: undeclared runtime_errors=1", result.stderr)

    def test_not_run_and_wrong_negative_shape_fail(self) -> None:
        for receipt in (
            "VISUAL_NEGATIVE verdict=not_run prerequisite=missing_evidence positive_verdict=skip\n",
            "VISUAL_NEGATIVE verdict=unexpected_failure shot_rc=0 assert_rc=1 "
            "a1=0 a2=1 gate=1 runtime_errors=0\n",
        ):
            with self.subTest(receipt=receipt):
                self.negative.write_text(receipt, encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 1)
                self.assertIn("negative:", result.stderr)

    def test_rolling_runtime_drift_fails_separately(self) -> None:
        receipt = self.runtime.read_text(encoding="utf-8")
        for before, after, prefix in (
            ("version=20260927.320.1", "version=20261003.1", "RUNNER_IMAGE "),
            ("libgl1-mesa-dri=25.2.8-0ubuntu0.24.04.4",
             "libgl1-mesa-dri=25.2.9-0ubuntu0.24.04.4", "VISUAL_PACKAGE libgl1-mesa-dri="),
        ):
            with self.subTest(prefix=prefix):
                self.runtime.write_text(receipt.replace(before, after), encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 1)
                self.assertIn(f"runtime: {prefix!r}", result.stderr)
                self.assertNotIn("positive: ", result.stderr)

    def test_missing_positive_receipt_fails(self) -> None:
        self.positive.unlink()
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("positive: missing or unreadable receipt", result.stderr)

    def test_missing_runtime_receipt_and_duplicate_identity_fail(self) -> None:
        self.runtime.unlink()
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("runtime: missing or unreadable receipt", result.stderr)
        self.runtime.write_text(
            "\n".join(json.loads(POLICY.read_text(encoding="utf-8"))["required_lines"].values())
            + "\nRUNNER_IMAGE os=ubuntu24 version=next arch=X64\n",
            encoding="utf-8",
        )
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("runtime: 'RUNNER_IMAGE '", result.stderr)


if __name__ == "__main__":
    unittest.main()
