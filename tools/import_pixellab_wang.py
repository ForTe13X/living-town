#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""import_pixellab_wang.py — PixelLab 顶视 Wang 瓦集（sheet PNG + metadata JSON）→ 游戏内（docs/182）。

用法：python tools/import_pixellab_wang.py <name> <sheet.png> <metadata.json>

出货：game/assets/art/wang/<name>.png（原样）+ <name>.json：
  {"tile": 16, "tiles": {"<NW><NE><SW><SE>": [x, y], ...}, "extra": [...]}
  角键每位 0=lower / 1=upper（2=transition，只出现在带崖壁的 25 瓦集里）。
  只按 metadata 的 bounding_box 切片——**不要**用 wang_N 的编号或 original_position 推位置（官方说明：会出横向条带）。
  同一角键出现多次（25 瓦集的崖壁续接瓦）时，第一个进 tiles，其余带 pattern_4x4 进 extra，由渲染侧按需挑。
"""
import json, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DST = ROOT / "game" / "assets" / "art" / "wang"
CODE = {"lower": "0", "upper": "1", "transition": "2"}


def _tiles(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "tiles" and isinstance(v, list):
                return v
            r = _tiles(v)
            if r:
                return r
    return None


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    name, png, meta = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    m = json.loads(meta.read_text("utf-8"))
    tiles = _tiles(m) or []
    out = {"tile": 16, "lower": m.get("lower_description", ""), "upper": m.get("upper_description", ""),
           "tiles": {}, "extra": []}
    for t in tiles:
        c = t["corners"]
        key = "".join(CODE[c[k]] for k in ("NW", "NE", "SW", "SE"))
        bb = t["bounding_box"]
        out["tile"] = int(bb["width"])
        if key in out["tiles"]:
            out["extra"].append({"key": key, "xy": [bb["x"], bb["y"]], "pattern": t.get("pattern_4x4")})
        else:
            out["tiles"][key] = [bb["x"], bb["y"]]
    DST.mkdir(parents=True, exist_ok=True)
    clear = [a for a in sys.argv[4:] if a in ("--clear-lower", "--clear-upper", "--clear-green")]
    if "--clear-green" in clear:
        # 草地挖空用「绿主导」判据（G 明显高于 R、B）：过渡瓦里的草色比纯草瓦的调色板更杂，
        # 只挖纯草瓦出现过的色会留下满地透明麻点（第一版眼验实测）。沙/湿泥/描边都不是绿主导 ⇒ 保留。
        from PIL import Image
        sheet = Image.open(png).convert("RGBA")
        px = sheet.load()
        for yy in range(sheet.height):
            for xx in range(sheet.width):
                r, g, b, a = px[xx, yy]
                if a > 0 and g > r + 6 and g > b + 12:
                    px[xx, yy] = (0, 0, 0, 0)
        sheet.save(DST / f"{name}.png", optimize=True)
        out["cleared"] = clear
    elif clear:
        # 纯地形挖空：把「纯 lower / 纯 upper 那张瓦」里出现过的颜色在整张表上设为透明，
        # 让游戏自己的那层地形（程序化动画海 / 出货草地瓦）从底下透出来 ⇒ 无色缝，只留岸线/过渡像素。
        from PIL import Image
        sheet = Image.open(png).convert("RGBA")
        ts = out["tile"]
        cols = set()
        for flag, key in (("--clear-lower", "0000"), ("--clear-upper", "1111")):
            if flag in clear and key in out["tiles"]:
                x, y = out["tiles"][key]
                cols |= {p[:3] for p in sheet.crop((x, y, x + ts, y + ts)).getdata() if p[3] > 0}
        px = sheet.load()
        for yy in range(sheet.height):
            for xx in range(sheet.width):
                if px[xx, yy][:3] in cols:
                    px[xx, yy] = (0, 0, 0, 0)
        sheet.save(DST / f"{name}.png", optimize=True)
        out["cleared"] = clear
    else:
        shutil.copyfile(png, DST / f"{name}.png")
    (DST / f"{name}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), "utf-8")
    print(f"{name}: {len(tiles)} tiles, {len(out['tiles'])} corner keys, {len(out['extra'])} extra")
    return 0


if __name__ == "__main__":
    sys.exit(main())
