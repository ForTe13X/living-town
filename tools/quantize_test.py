#!/usr/bin/env python3
"""Self-contained tests for the deterministic GPL PNG quantizer."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

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


def assert_no_temporary_residue(directory: Path, destination: Path) -> None:
    assert not list(directory.glob(".%s.quantize-*" % destination.name))


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

        partial_destination = temp / "partial.png"

        def partial_write_then_fail(_image: Image.Image, file: Path, **_kwargs: object) -> None:
            Path(file).write_bytes(b"partial-output")
            raise OSError("injected write failure")

        with patch.object(Image.Image, "save", partial_write_then_fail):
            try:
                quantize.quantize_image(source, partial_destination, palette)
            except quantize.QuantizeError as exc:
                assert "cannot write output PNG" in str(exc)
            else:
                raise AssertionError("injected partial write unexpectedly succeeded")
        assert not partial_destination.exists(), "partial write leaked into final destination"
        assert_no_temporary_residue(temp, partial_destination)

        race_destination = temp / "race.png"
        race_bytes = b"third-party-output"
        original_link = quantize.os.link

        def create_destination_race(source_path: Path, destination_path: Path, **kwargs: object) -> None:
            Path(destination_path).write_bytes(race_bytes)
            original_link(source_path, destination_path, **kwargs)

        with patch.object(quantize.os, "link", create_destination_race):
            try:
                quantize.quantize_image(source, race_destination, palette)
            except quantize.QuantizeError as exc:
                assert "output already exists" in str(exc)
            else:
                raise AssertionError("destination race unexpectedly succeeded")
        assert race_destination.read_bytes() == race_bytes, "race destination was clobbered"
        assert_no_temporary_residue(temp, race_destination)

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
        empty_name = temp / "empty-name.gpl"
        empty_name.write_text("GIMP Palette\nName: \n0 0 0 black\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "empty-name.png", "--palette", empty_name), "empty GPL Name metadata")
        nonnumeric_columns = temp / "nonnumeric-columns.gpl"
        nonnumeric_columns.write_text("GIMP Palette\nColumns: nope\n0 0 0 black\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "nonnumeric-columns.png", "--palette", nonnumeric_columns), "invalid GPL Columns metadata")
        zero_columns = temp / "zero-columns.gpl"
        zero_columns.write_text("GIMP Palette\nColumns: 0\n0 0 0 black\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "zero-columns.png", "--palette", zero_columns), "invalid GPL Columns metadata")
        duplicate_columns = temp / "duplicate-columns.gpl"
        duplicate_columns.write_text("GIMP Palette\nColumns: 2\nColumns: 2\n0 0 0 black\n", encoding="utf-8")
        expect_failure(run_cli(source, temp / "duplicate-columns.png", "--palette", duplicate_columns), "duplicate GPL Columns metadata")
        expect_failure(run_cli(source, temp / "missing-palette.png", "--palette", temp / "missing.gpl"), "cannot read palette")
        bad_input = temp / "not-image.png"
        bad_input.write_text("not a PNG", encoding="utf-8")
        expect_failure(run_cli(bad_input, temp / "bad-input.png", "--palette", palette), "cannot read input PNG")
        rgb_input = temp / "rgb.png"
        Image.new("RGB", (1, 1), (1, 2, 3)).save(rgb_input, format="PNG")
        expect_failure(run_cli(rgb_input, temp / "rgb-output.png", "--palette", palette), "must use RGBA mode")
        expect_failure(run_cli(source, source, "--palette", palette), "refusing in-place overwrite")
        expect_failure(run_cli(source, first, "--palette", palette), "output already exists")
    print("quantize_test: PASS (real GPL=%d colors; mutation and atomicity teeth detected)" % len(real_colors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
