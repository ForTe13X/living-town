#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""import_pixellab_char.py — PixelLab 角色包（download zip）→ 游戏内 8 向角色表（docs/181）。

用法：python tools/import_pixellab_char.py <persona_id> <pixellab.zip|解压目录>

出货：game/assets/art/chars/<persona_id>.png
  8 行 × (1 + N) 列，格 = 源尺寸（48×48）。
  行序（方向）：south, south-east, east, north-east, north, north-west, west, south-west
  第 0 列 = 该方向静止帧（rotation），第 1..N 列 = walk 动画帧（缺动画则全用静止帧填）。
WorldView 按 `Art.char_sheet(persona_id)` 取表；没有这张表的居民仍走旧 Puny 表（逐像素不变）。
"""
import json, sys, zipfile, io
from pathlib import Path
from PIL import Image

DIRS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
ROOT = Path(__file__).resolve().parent.parent
DST = ROOT / "game" / "assets" / "art" / "chars"


def _open(src: Path):
    if src.is_dir():
        return lambda rel: Image.open(src / rel).convert("RGBA"), json.loads((src / "metadata.json").read_text("utf-8"))
    z = zipfile.ZipFile(src)
    return (lambda rel: Image.open(io.BytesIO(z.read(rel))).convert("RGBA")), json.loads(z.read("metadata.json"))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    pid, src = sys.argv[1], Path(sys.argv[2])
    load, meta = _open(src)
    st = meta["states"][0]
    frames = st["frames"]
    rot = frames["rotations"]
    walk = frames.get("animations", {}).get("walk", {})
    n = max((len(walk.get(d, [])) for d in DIRS), default=0)
    w = int(st["character"]["size"]["width"]); h = int(st["character"]["size"]["height"])
    sheet = Image.new("RGBA", (w * (1 + max(n, 1)), h * len(DIRS)), (0, 0, 0, 0))
    for r, d in enumerate(DIRS):
        idle = load(rot[d])
        sheet.alpha_composite(idle, (0, r * h))
        seq = walk.get(d) or []
        for c in range(max(n, 1)):
            img = load(seq[c]) if c < len(seq) else idle
            sheet.alpha_composite(img, ((c + 1) * w, r * h))
    DST.mkdir(parents=True, exist_ok=True)
    out = DST / f"{pid}.png"
    sheet.save(out, optimize=True)
    print(f"{out.relative_to(ROOT)}  {sheet.size[0]}x{sheet.size[1]}  cell={w}x{h}  walk_frames={n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
