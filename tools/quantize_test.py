#!/usr/bin/env python3
"""Self-contained tests for the deterministic GPL PNG quantizer."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import quantize  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "quantize.py"
REAL_PALETTE = ROOT / "game" / "assets" / "art" / "palette.gpl"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_cli(*args: Path | str) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    return subprocess.run(
        [sys.executable, str(TOOL), *map(str, args)],
        text=True,
        capture_output=True,
        check=False,
        env=environment,
    )


def expect_failure(result: subprocess.CompletedProcess[str], fragment: str) -> None:
    assert result.returncode == 2, result
    assert fragment in result.stderr, result.stderr


def main() -> int:
    real_colors = quantize.parse_gpl(REAL_PALETTE)
    assert len(real_colors) >= 32
    with tempfile.TemporaryDirectory(prefix="living-town-quantize-") as temp_name:
        temp = Path(temp_name)
        palette = temp / "tiny.gpl"
        palette.write_text("GIMP Palette\nName: test\nColumns: 2\n0 0 0 black\n10 0 0 red\n", encoding="utf-8")
        source = temp / "source.png"
        fixture = Image.new("RGBA", (3, 1))
        # (5,0,0) is exactly tied: GPL order must choose black, not red.
        fixture.putdata([(5, 0, 0, 17), (9, 0, 0, 255), (200, 1, 2, 0)])
        fixture.save(source, format="PNG")
        source_hash = sha256(source)

        first, second = temp / "first.png", temp / "second.png"
        completed = run_cli(source, first, "--palette", palette)
        assert completed.returncode == 0, completed.stderr
        completed = run_cli(source, second, "--palette", palette)
        assert completed.returncode == 0, completed.stderr
        assert sha256(source) == source_hash, "quantizer modified source"
        assert sha256(first) == sha256(second), "same inputs produced different PNG bytes"

        with Image.open(first) as output:
            pixels = list(output.getdata())
        expected = [(0, 0, 0, 17), (10, 0, 0, 255), (10, 0, 0, 0)]
        assert pixels == expected, pixels
        assert [pixel[3] for pixel in pixels] == [17, 255, 0]
        allowed = set(quantize.parse_gpl(palette))
        assert all(pixel[:3] in allowed for pixel in pixels if pixel[3] != 0)

        # Mutation tooth: a deliberately false expected mapping must fail.
        try:
            assert pixels[0] == (10, 0, 0, 17), "mutated expected tie result"
        except AssertionError:
            pass
        else:
            raise AssertionError("mutation tooth did not detect altered expectation")

        malformed = temp / "malformed.gpl"
        malformed.write_text("not a GPL\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "bad-palette.png", "--palette", malformed), "invalid GPL header")
        empty = temp / "empty.gpl"
        empty.write_text("GIMP Palette\nName: empty\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "empty-palette.png", "--palette", empty), "has no colors")
        expect_failure(run_cli(source, temp / "missing-palette.png", "--palette", temp / "missing.gpl"), "cannot read palette")
        bad_input = temp / "not-image.png"
        bad_input.write_text("not a PNG", encoding="utf-8")
        expect_failure(run_cli(bad_input, temp / "bad-input.png", "--palette", palette), "cannot read input PNG")
        rgb_input = temp / "rgb.png"
        Image.new("RGB", (1, 1), (1, 2, 3)).save(rgb_input, format="PNG")
        expect_failure(run_cli(rgb_input, temp / "rgb-output.png", "--palette", palette), "must use RGBA mode")
        expect_failure(run_cli(source, source, "--palette", palette), "refusing in-place overwrite")
        expect_failure(run_cli(source, first, "--palette", palette), "output already exists")
    print("quantize_test: PASS (real GPL=%d colors; mutation tooth detected)" % len(real_colors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
