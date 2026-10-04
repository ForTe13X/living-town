#!/usr/bin/env python3
"""Decide whether the hosted day/night fault injector has a valid positive arm.

The full visual product verdict includes unrelated detectors. This prerequisite
rechecks only the two captured frames consumed by the day/night ruler and writes
a separate receipt so missing evidence cannot be mistaken for product failure.
Exit 0 means run the negative, 77 means do not run it, and 2 means this checker
itself failed.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print("usage: visual_daynight_prereq.py <positive-frames> <receipt-dir> [tol]", file=sys.stderr)
        return 2
    frames = Path(argv[0]).resolve()
    receipt_dir = Path(argv[1]).resolve()
    tol = argv[2] if len(argv) == 3 else "4"
    if not tol.isdecimal():
        print("tolerance must be a nonnegative integer", file=sys.stderr)
        return 2
    receipt_dir.mkdir(parents=True, exist_ok=True)
    paths = {name: frames / f"vg_{name}.png" for name in ("night", "noon")}
    hashes: dict[str, str] = {}
    reason = ""
    for name, path in paths.items():
        if not path.is_file():
            reason = "missing_evidence"
            break
        data = path.read_bytes()
        if len(data) <= len(PNG_MAGIC) or not data.startswith(PNG_MAGIC):
            reason = "corrupt_evidence"
            break
        hashes[name] = hashlib.sha256(data).hexdigest()

    log = ""
    detector_rc: int | None = None
    if not reason:
        cmd = [sys.executable, str(Path(__file__).with_name("assert_daynight.py")),
               str(paths["night"]), str(paths["noon"]), "488", "600", "--tol", tol]
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        detector_rc = result.returncode
        log = result.stdout + result.stderr
        if detector_rc == 0 and all(token in log for token in (
            "PASS A1", "PASS A2", "=== DAYNIGHT GATE: PASS ===")):
            reason = "ready"
        elif detector_rc == 1 and "=== DAYNIGHT GATE: FAIL" in log:
            reason = "daynight_product_fail"
        elif detector_rc != 0 and any(token in log for token in (
            "FileNotFoundError", "UnidentifiedImageError", "OSError", "ValueError", "IndexError")):
            reason = "corrupt_evidence"
        else:
            reason = "detector_error"

    (receipt_dir / "daynight-prereq.log").write_text(log, encoding="utf-8")
    record = {"schema": "living-town.visual-daynight-prereq.v1", "verdict": reason,
              "positive_frames": str(frames), "frame_sha256": hashes,
              "detector_rc": detector_rc, "tolerance": int(tol)}
    (receipt_dir / "daynight-prereq.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"VISUAL_DAYNIGHT_PREREQ verdict={reason} detector_rc={detector_rc}")
    return 0 if reason == "ready" else (2 if reason == "detector_error" else 77)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
