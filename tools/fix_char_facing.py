#!/usr/bin/env python
# fix_char_facing.py — repair PixelLab 8-dir sheets whose idle frame and walk frames disagree on facing.
# docs/193 §一: facecheck (walk frame closer to the mirrored idle than to the idle itself) flagged
# qin (E/NE/NW/W idle frames turned the wrong way). tao's SW flag is a false positive: his sack sits on
# the other shoulder in the mirrored walk frames, but the face and stride already point south-west.
# Idempotent: re-running on a fixed sheet leaves it unchanged. Usage: python tools/fix_char_facing.py
from pathlib import Path
from PIL import Image

C = 48
ROOT = Path(__file__).resolve().parent.parent / "game" / "assets" / "art" / "chars"
ROWS = {"S": 0, "SE": 1, "E": 2, "NE": 3, "N": 4, "NW": 5, "W": 6, "SW": 7}
# pid -> [("idle", row) | ("mirror_walk", dst_row, src_row)]
FIXES = {
    "qin": [("idle", "E"), ("idle", "NE"), ("idle", "NW"), ("idle", "W")],
}


def cell(im, c, r):
    return im.crop((c * C, r * C, c * C + C, r * C + C))


def main() -> int:
    for pid, fixes in FIXES.items():
        path = ROOT / f"{pid}.png"
        im = Image.open(path).convert("RGBA")
        n = im.width // C
        for fx in fixes:
            if fx[0] == "idle":
                r = ROWS[fx[1]]
                # the most closed stride (narrowest alpha bbox) reads as standing
                best = min(range(1, n), key=lambda c: (cell(im, c, r).getbbox() or (0, 0, 99, 0))[2] - (cell(im, c, r).getbbox() or (0, 0, 0, 0))[0])
                frame = cell(im, best, r)
                im.paste((0, 0, 0, 0), (0, r * C, C, r * C + C))
                im.alpha_composite(frame, (0, r * C))
            else:
                dst, src = ROWS[fx[1]], ROWS[fx[2]]
                for c in range(1, n):
                    f = cell(im, c, src).transpose(Image.FLIP_LEFT_RIGHT)
                    im.paste((0, 0, 0, 0), (c * C, dst * C, c * C + C, dst * C + C))
                    im.alpha_composite(f, (c * C, dst * C))
        im.save(path, optimize=True)
        print(f"fixed {path.name}: {fixes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
