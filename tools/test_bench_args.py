#!/usr/bin/env python3
"""Exercise the actual gate entry points; bad bake commands must stop before work.

Run after Godot import: python tools/test_bench_args.py --godot /path/to/godot
No tracked anchors are written. Each process has a bounded runtime and its own log.
"""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GATES = [
    ("Harness", ["--script", "res://bench/Harness.gd"],
     ["--golden", "--bake-golden", "--shadow-dump", "--chain-dump", "--chain-ref"]),
    ("DetGate", ["--script", "res://bench/DetGate.gd"], ["--golden", "--bake-golden"]),
    ("ModelPathGate", ["res://bench/ModelPathGate.tscn"], ["--anchor", "--bake-anchor"]),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    options = parser.parse_args()
    anchors = [ROOT / "game/bench" / name for name in
               ("golden_digests.json", "modelpath_anchor.json")]
    before = [hashlib.sha256(path.read_bytes()).digest() for path in anchors]
    count = 0
    with tempfile.TemporaryDirectory(prefix="lt-bench-args-") as tmp:
        def run(entry, args):
            command = [options.godot, "--headless", "--path", str(ROOT / "game"),
                       "--log-file", str(Path(tmp) / f"case-{count}.log"), *entry, "--", *args]
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, encoding="utf-8",
                                    errors="replace", timeout=30)
            assert not any(marker in result.stdout for marker in
                           ("SCRIPT ERROR", "Parse Error", "Failed to load script")), result.stdout
            return result

        result = run(["--script", "res://bench/BenchArgsTest.gd"], [])
        assert result.returncode == 0 and "BenchArgsTest: PASS" in result.stdout, result.stdout
        for name, entry, flags in GATES:
            for flag in flags:
                for suffix in ([], ["--days", "1"], ["   "]):
                    count += 1
                    result = run(entry, ["--seeds", "1", "--days", "0", flag, *suffix])
                    expected = f"{name} CLI: FAIL: {flag} requires a non-empty path argument"
                    assert expected in result.stdout, result.stdout
                    assert f"=== {name}" not in result.stdout, result.stdout
                    # Windows Godot may return 0 despite SceneTree.quit(nonzero).
                    # The specific fail verdict is mandatory on every platform.
                    assert result.returncode != 0 or os.name == "nt", result.stdout
                    print(f"PASS {name} {flag}: {suffix!r}")
    assert before == [hashlib.sha256(path.read_bytes()).digest() for path in anchors], "Anchors changed"
    print(f"Benchmark CLI: PASS ({count} invalid commands; 29 positive controls; anchors unchanged)")


if __name__ == "__main__":
    main()
