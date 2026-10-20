#!/usr/bin/env python3
"""Enforce the reviewed hosted visual positive, negative, and raster receipts."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


POSITIVE = re.compile(
    r"VISUAL_CANARY verdict=(\S+) rc=(\d+) png_count=(\d+) runtime_errors=(\d+)"
)
NEGATIVE = re.compile(
    r"VISUAL_NEGATIVE verdict=(\S+) shot_rc=(\d+) assert_rc=(\d+) "
    r"a1=(\d+) a2=(\d+) gate=(\d+) runtime_errors=(\d+)"
)
RUNTIME_PREFIXES = {
    "RUNNER_IMAGE ", "GODOT_ARCHIVE ", "GODOT_BINARY ", "PYTHON ",
    "VISUAL_PACKAGE libgl1=", "VISUAL_PACKAGE libgl1-mesa-dri=",
    "VISUAL_PACKAGE libglx-mesa0=", "VISUAL_PACKAGE mesa-utils=",
    "VISUAL_PACKAGE xauth=", "VISUAL_PACKAGE xvfb=",
    "OpenGL vendor string: ", "OpenGL renderer string: ", "OpenGL version string: ",
}


def _read(path: Path, label: str, issues: list[str]) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        issues.append(f"{label}: missing or unreadable receipt ({exc})")
        return None


def _verdict(path: Path, label: str, pattern: re.Pattern[str], issues: list[str]) -> tuple[str, ...] | None:
    content = _read(path, label, issues)
    if content is None:
        return None
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if len(lines) != 1 or (match := pattern.fullmatch(lines[0])) is None:
        issues.append(f"{label}: malformed or missing single-line verdict")
        return None
    return match.groups()


def check_positive(path: Path, issues: list[str]) -> None:
    receipt = _verdict(path, "positive", POSITIVE, issues)
    if receipt is None:
        return
    verdict, rc, png_count, runtime_errors = receipt
    if verdict != "pass" or rc != "0":
        issues.append(f"positive: nonpassing verdict={verdict} rc={rc}")
    if int(png_count) < 1:
        issues.append("positive: empty PNG set")
    if runtime_errors != "0":
        issues.append(f"positive: undeclared runtime_errors={runtime_errors}")


def check_negative(path: Path, issues: list[str]) -> None:
    content = _read(path, "negative", issues)
    if content is None:
        return
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    if len(lines) != 1:
        issues.append("negative: missing or duplicated verdict line")
        return
    if lines[0].startswith("VISUAL_NEGATIVE verdict=not_run "):
        issues.append(f"negative: {lines[0]}")
        return
    match = NEGATIVE.fullmatch(lines[0])
    if match is None:
        issues.append(f"negative: malformed or nonqualifying verdict {lines[0]!r}")
        return
    receipt = match.groups()
    if receipt != ("caught_expected_daynight_fault", "0", "1", "1", "1", "1", "0"):
        issues.append(f"negative: unexpected tooth receipt {' '.join(receipt)}")


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate policy JSON key {key!r}")
        result[key] = value
    return result


def _runtime_profiles(policy: object) -> list[dict]:
    if not isinstance(policy, dict):
        raise ValueError("policy must be an object")
    schema = policy.get("schema")
    if schema == "lt-hosted-visual-required/v1":
        # Historical single-profile policies remain usable as written.
        profiles = [{"name": "legacy-v1", "required_lines": policy.get("required_lines")}]
    elif schema == "lt-hosted-visual-required/v2":
        profiles = policy.get("runtime_profiles")
        if "required_lines" in policy or not isinstance(profiles, list) or not profiles:
            raise ValueError("v2 requires explicit runtime_profiles without a fallback mapping")
    else:
        raise ValueError("unsupported schema")
    names, signatures = set(), set()
    for profile in profiles:
        if not isinstance(profile, dict):
            raise ValueError("runtime profile must be an object")
        name = profile.get("name")
        if not isinstance(name, str) or re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,100}", name) is None or name in names:
            raise ValueError("invalid or duplicate runtime profile name")
        names.add(name)
        required = profile.get("required_lines")
        if not isinstance(required, dict) or not required or any(
            not isinstance(prefix, str) or not prefix or not isinstance(expected, str)
            or not expected.startswith(prefix) or "\n" in expected or "\r" in expected
            for prefix, expected in required.items()
        ):
            raise ValueError("invalid required_lines mapping")
        if schema.endswith("/v2"):
            if set(required) != RUNTIME_PREFIXES:
                raise ValueError("each v2 profile must contain every required runtime identity")
            for key in ("source_run_id", "reviewed_artifact_id"):
                if type(profile.get(key)) is not int or profile[key] <= 0:
                    raise ValueError(f"profile {name!r} lacks positive {key}")
            for key, length in (("reviewed_pr_head", 40), ("reviewed_event_sha", 40),
                                ("reviewed_artifact_sha256", 64)):
                if not isinstance(profile.get(key), str) or re.fullmatch("[0-9a-f]{" + str(length) + "}", profile[key]) is None:
                    raise ValueError(f"profile {name!r} lacks exact {key}")
        signature = tuple(sorted(required.items()))
        if signature in signatures:
            raise ValueError("duplicate complete runtime profile")
        signatures.add(signature)
    return profiles


def check_runtime(runtime_path: Path, policy_path: Path, issues: list[str]) -> str | None:
    try:
        policy = json.loads(policy_path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
        profiles = _runtime_profiles(policy)
    except (OSError, UnicodeError, ValueError) as exc:
        issues.append(f"runtime policy: missing or malformed ({exc})")
        return
    content = _read(runtime_path, "runtime", issues)
    if content is None:
        return
    lines = content.splitlines()
    evaluations = []
    for profile in profiles:
        mismatches = []
        for prefix, expected in profile["required_lines"].items():
            found = [line for line in lines if line.startswith(prefix)]
            if found != [expected]:
                mismatches.append(f"runtime: {prefix!r} expected exactly once as {expected!r}; found {found!r}")
        evaluations.append((profile["name"], mismatches))
    matched = [name for name, mismatches in evaluations if not mismatches]
    if len(matched) == 1:
        return matched[0]
    if matched:
        issues.append("runtime: ambiguous complete reviewed profiles")
        return
    issues.append("runtime: no complete reviewed profile matched")
    # Preserve precise drift diagnostics without treating per-field alternatives
    # as interchangeable. A single COMPLETE profile must match the whole receipt.
    closest_name, closest = min(evaluations, key=lambda item: len(item[1]))
    issues.append(f"runtime: nearest reviewed profile={closest_name}")
    issues.extend(closest)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--positive", type=Path, required=True)
    parser.add_argument("--negative", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    args = parser.parse_args(argv)
    issues: list[str] = []
    check_positive(args.positive, issues)
    check_negative(args.negative, issues)
    runtime_profile = check_runtime(args.runtime, args.policy, issues)
    if issues:
        for issue in issues:
            print(f"HOSTED_VISUAL_REQUIRED FAIL {issue}", file=sys.stderr)
        return 1
    print("HOSTED_VISUAL_REQUIRED PASS positive=pass negative=caught_expected_daynight_fault "
          f"runtime=reviewed profile={runtime_profile}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
