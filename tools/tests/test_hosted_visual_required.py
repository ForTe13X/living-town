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
        self.policy = base / "policy.json"
        self.policy_document = json.loads(POLICY.read_text(encoding="utf-8"))
        self.policy.write_text(json.dumps(self.policy_document), encoding="utf-8")
        self.required = self.policy_document["runtime_profiles"][0]["required_lines"]
        self.runtime.write_text("\n".join(self.required.values()) + "\n", encoding="utf-8")
        self.positive.write_text(PASS_POSITIVE, encoding="utf-8")
        self.negative.write_text(PASS_NEGATIVE, encoding="utf-8")

    def run_policy(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--runtime", str(self.runtime),
             "--positive", str(self.positive), "--negative", str(self.negative),
             "--policy", str(self.policy)],
            capture_output=True, text=True, check=False,
        )

    def test_reviewed_positive_and_expected_negative_pass(self) -> None:
        result = self.run_policy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HOSTED_VISUAL_REQUIRED PASS", result.stdout)

    def test_each_complete_reviewed_profile_passes(self) -> None:
        for profile in self.policy_document["runtime_profiles"]:
            with self.subTest(profile=profile["name"]):
                self.runtime.write_text("\n".join(profile["required_lines"].values()) + "\n", encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("profile=" + profile["name"], result.stdout)

    def test_legacy_single_profile_policy_remains_supported(self) -> None:
        profile = self.policy_document["runtime_profiles"][0]
        legacy = {"schema": "lt-hosted-visual-required/v1",
                  **{key: value for key, value in profile.items() if key != "name"}}
        self.policy.write_text(json.dumps(legacy), encoding="utf-8")
        self.assertEqual(self.run_policy().returncode, 0)

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
            "VISUAL_NEGATIVE verdict=caught_expected_daynight_fault shot_rc=0 assert_rc=1 "
            "a1=1 a2=0 gate=1 runtime_errors=0\n",
        ):
            with self.subTest(receipt=receipt):
                self.negative.write_text(receipt, encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 1)
                self.assertIn("negative:", result.stderr)

    def test_rolling_runtime_drift_fails_separately(self) -> None:
        receipt = self.runtime.read_text(encoding="utf-8")
        required = self.required
        for before, after, prefix in (
            (required["RUNNER_IMAGE "],
             "RUNNER_IMAGE os=ubuntu24 version=unreviewed arch=X64", "RUNNER_IMAGE "),
            (required["PYTHON "], "PYTHON version=unreviewed pillow=11.3.0", "PYTHON "),
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
            "\n".join(self.required.values())
            + "\nRUNNER_IMAGE os=ubuntu24 version=next arch=X64\n",
            encoding="utf-8",
        )
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("runtime: 'RUNNER_IMAGE '", result.stderr)

    def test_duplicate_identical_runtime_identity_fails(self) -> None:
        with self.runtime.open("a", encoding="utf-8") as stream:
            stream.write(self.required["RUNNER_IMAGE "] + "\n")
        self.assertEqual(self.run_policy().returncode, 1)

    def test_cross_profile_field_mix_is_not_accepted(self) -> None:
        # Make the second reviewed fixture differ on TWO identities, then try a
        # combination present in neither complete profile. Per-field allowlists
        # would accidentally accept this unreviewed combination.
        profiles = self.policy_document["runtime_profiles"]
        profiles[1]["required_lines"]["VISUAL_PACKAGE xvfb="] = "VISUAL_PACKAGE xvfb=unreviewed-combination"
        self.policy.write_text(json.dumps(self.policy_document), encoding="utf-8")
        text = self.runtime.read_text(encoding="utf-8").replace(
            self.required["VISUAL_PACKAGE xvfb="], profiles[1]["required_lines"]["VISUAL_PACKAGE xvfb="])
        self.runtime.write_text(text, encoding="utf-8")
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no complete reviewed profile matched", result.stderr)

    def test_duplicate_profiles_and_names_are_malformed(self) -> None:
        for duplicate_signature in (False, True):
            with self.subTest(signature=duplicate_signature):
                document = json.loads(json.dumps(self.policy_document))
                if duplicate_signature:
                    document["runtime_profiles"][1]["required_lines"] = dict(self.required)
                else:
                    document["runtime_profiles"][1]["name"] = document["runtime_profiles"][0]["name"]
                self.policy.write_text(json.dumps(document), encoding="utf-8")
                result = self.run_policy()
                self.assertEqual(result.returncode, 1)
                self.assertIn("duplicate", result.stderr)

    def test_partial_profile_cannot_silently_drop_identity(self) -> None:
        del self.policy_document["runtime_profiles"][1]["required_lines"]["PYTHON "]
        self.policy.write_text(json.dumps(self.policy_document), encoding="utf-8")
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("every required runtime identity", result.stderr)

    def test_profile_requires_bound_review_metadata(self) -> None:
        del self.policy_document["runtime_profiles"][1]["reviewed_artifact_sha256"]
        self.policy.write_text(json.dumps(self.policy_document), encoding="utf-8")
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("reviewed_artifact_sha256", result.stderr)

    def test_duplicate_policy_json_keys_are_rejected(self) -> None:
        self.policy.write_text('{"schema":"lt-hosted-visual-required/v2","schema":"lt-hosted-visual-required/v1"}', encoding="utf-8")
        result = self.run_policy()
        self.assertEqual(result.returncode, 1)
        self.assertIn("duplicate policy JSON key", result.stderr)


if __name__ == "__main__":
    unittest.main()
