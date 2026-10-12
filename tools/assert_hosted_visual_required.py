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


def check_runtime(runtime_path: Path, policy_path: Path, issues: list[str]) -> None:
    try:
        policy = json.loads(policy_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        issues.append(f"runtime policy: missing or malformed ({exc})")
        return
    if policy.get("schema") != "lt-hosted-visual-required/v1":
        issues.append("runtime policy: unsupported schema")
        return
    required = policy.get("required_lines")
    if not isinstance(required, dict) or not required or any(
        not isinstance(prefix, str) or not prefix or not isinstance(expected, str)
        or not expected.startswith(prefix) for prefix, expected in required.items()
    ):
        issues.append("runtime policy: invalid required_lines mapping")
        return
    content = _read(runtime_path, "runtime", issues)
    if content is None:
        return
    lines = content.splitlines()
    for prefix, expected in required.items():
        found = [line for line in lines if line.startswith(prefix)]
        if found != [expected]:
            issues.append(f"runtime: {prefix!r} expected exactly once as {expected!r}; found {found!r}")


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
    check_runtime(args.runtime, args.policy, issues)
    if issues:
        for issue in issues:
            print(f"HOSTED_VISUAL_REQUIRED FAIL {issue}", file=sys.stderr)
        return 1
    print("HOSTED_VISUAL_REQUIRED PASS positive=pass negative=caught_expected_daynight_fault runtime=reviewed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
