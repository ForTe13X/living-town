#!/usr/bin/env python3
"""Deterministically quantize an RGBA PNG against a GIMP GPL palette.

Colors are compared using squared Euclidean distance in encoded 8-bit sRGB
space.  Equal distances select the first color in GPL file order.  The alpha
channel is copied byte-for-byte; this is an offline production tool and never
uses randomness, the network, or source-image metadata.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable

from PIL import Image, UnidentifiedImageError


DEFAULT_PALETTE = Path(__file__).resolve().parents[1] / "game" / "assets" / "art" / "palette.gpl"


class QuantizeError(ValueError):
    """A concise, user-correctable input error."""


def parse_gpl(path: Path) -> list[tuple[int, int, int]]:
    """Return palette colors in file order, rejecting ambiguous GPL input."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise QuantizeError("cannot read palette: %s" % path) from exc
    if not lines or lines[0].strip() != "GIMP Palette":
        raise QuantizeError("invalid GPL header: %s" % path)

    colors: list[tuple[int, int, int]] = []
    seen: set[tuple[int, int, int]] = set()
    for line_number, raw in enumerate(lines[1:], start=2):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("Name:") or line.startswith("Columns:"):
            continue
        fields = line.split()
        if len(fields) < 3:
            raise QuantizeError("malformed GPL color at line %d" % line_number)
        try:
            color = tuple(int(value) for value in fields[:3])
        except ValueError as exc:
            raise QuantizeError("malformed GPL color at line %d" % line_number) from exc
        if any(value < 0 or value > 255 for value in color):
            raise QuantizeError("GPL color out of range at line %d" % line_number)
        if color in seen:
            raise QuantizeError("duplicate GPL color at line %d" % line_number)
        seen.add(color)
        colors.append(color)
    if not colors:
        raise QuantizeError("GPL palette has no colors: %s" % path)
    return colors


def nearest_color(rgb: tuple[int, int, int], palette: Iterable[tuple[int, int, int]]) -> tuple[int, int, int]:
    """Return the first palette entry at the minimum encoded-sRGB distance."""
    best: tuple[int, int, int] | None = None
    best_distance: int | None = None
    for candidate in palette:
        distance = sum((source - target) ** 2 for source, target in zip(rgb, candidate))
        if best_distance is None or distance < best_distance:
            best, best_distance = candidate, distance
    if best is None:
        raise QuantizeError("GPL palette has no colors")
    return best


def quantize_image(source: Path, destination: Path, palette_path: Path) -> None:
    if source.resolve() == destination.resolve():
        raise QuantizeError("refusing in-place overwrite")
    if destination.exists():
        raise QuantizeError("output already exists: %s" % destination)
    if destination.suffix.lower() != ".png":
        raise QuantizeError("output must use a .png extension")
    palette = parse_gpl(palette_path)
    try:
        with Image.open(source) as opened:
            if opened.format != "PNG":
                raise QuantizeError("input must be a PNG")
            if opened.mode != "RGBA":
                raise QuantizeError("input PNG must use RGBA mode, got %s" % opened.mode)
            image = opened.copy()
    except (OSError, UnidentifiedImageError) as exc:
        raise QuantizeError("cannot read input PNG: %s" % source) from exc

    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            mapped = nearest_color((red, green, blue), palette)
            pixels[x, y] = (*mapped, alpha)
    try:
        image.save(destination, format="PNG")
    except OSError as exc:
        raise QuantizeError("cannot write output PNG: %s" % destination) from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input_png", type=Path)
    parser.add_argument("output_png", type=Path)
    parser.add_argument("--palette", type=Path, default=DEFAULT_PALETTE, help="GPL palette path")
    args = parser.parse_args(argv)
    try:
        quantize_image(args.input_png, args.output_png, args.palette)
    except QuantizeError as exc:
        print("quantize: %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
