#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_terrain_ref.py —— 从暖色 Stardew 风参考表切出 5 张 16×16 地形瓦（Lane V · AV2）。

## 这一棒替换哪 5 张、不动哪 8 张（明写，别让读者猜）

替换（切自 `docs/media/references/ref_terrain_v1_stardew.png`，一张【风格参考】=7 行×8 列）：
    grass_a       ← GRASS · CENTER            （主草地）
    grass_b       ← GRASS · ALTERNATE CENTER  （草地变体）
    grass_flowers ← GRASS · hero（第 1 列大格，花最多）
    dirt          ← DIRT PATH · CENTER
    water         ← RIVER/WATER · CENTER       （只是池心填充；岸线仍是 CC0 八向自动贴图）

**不动**：`water_{n,s,e,w,ne,nw,se,sw}.png` 这 8 张 CC0 岸线自动贴图。它们把草地一侧键成透明，
让 `WorldView._season_veg()` 染过色的草地透上来（否则秋天池塘会套一圈春绿，见 slice_shore.py 抬头），
而且它们过 POND 门。参考表的岸线是不透明、单向的，换上去会同时把那个 bug 请回来并让 POND 变红。
⇒ 暖色地形 + 冷蓝 CC0 池水，这一格是接受的（写在 docs/159）。

## 切法（几何）

参考表每格 ≈130px 见方，外圈有一道深色圆角边框。做法：
  1. 按行/列 band 定位该格；
  2. **inset** 若干 px 去掉直边框；
  3. 再取一个【居中正方形】(CORE 比例) 躲开圆角——圆角处仍留着深框，直接缩放会把它揉进边缘像素；
  4. LANCZOS 缩到 16×16（下采样质量最好），再做**轻度 posterize**把抗锯齿糊出来的过渡色吸回到
     有限调色板，恢复像素画的硬边。5 张都是不透明地面 ⇒ alpha 恒 255。

band 坐标取自 AV2 scoping（人工在参考图上量的），写死在这里；参考图不动它们就不动。
换参考图 = 重量一次 band。

用法:
    python tools/slice_terrain_ref.py                 # 切 5 张写进 game/assets/art/terrain/
    python tools/slice_terrain_ref.py --preview DIR   # 另把每张 NEAREST 放大到 160×160 写进 DIR（眼验用）
    python tools/slice_terrain_ref.py --dry           # 只切不落盘（配合 --preview 先看再决定）
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("❌ slice_terrain_ref: 需要 Pillow（pip install pillow）")

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "media", "references", "ref_terrain_v1_stardew.png")
DST = os.path.join(ROOT, "game", "assets", "art", "terrain")
T = 16

# 参考图行 y-band（上下含端点近似）与列 x-band。人工量自 1448×1086 的参考图。
ROW = {"GRASS": (48, 180), "DIRT": (219, 339), "WATER": (669, 776)}
COL = {"hero": (89, 262), "CENTER": (284, 417), "ALT": (438, 578)}

# 出货名 → (行 band, 列 band)
TILES = {
    "grass_a":       ("GRASS", "CENTER"),
    "grass_b":       ("GRASS", "ALT"),
    "grass_flowers": ("GRASS", "hero"),
    "dirt":          ("DIRT",  "CENTER"),
    "water":         ("WATER", "CENTER"),
}

INSET = 8        # 去掉直边框
CORE = 0.90      # 居中正方形占 inset 后 interior 短边的比例（躲圆角）
POSTERIZE_BITS = 5   # 每通道保留 5 bit = 32 级（轻度；把抗锯齿过渡色吸回硬边）


def slice_one(sheet, row, col):
    y0, y1 = ROW[row]
    x0, x1 = COL[col]
    # 1) inset 去直边框
    ix0, iy0, ix1, iy1 = x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET
    iw, ih = ix1 - ix0, iy1 - iy0
    # 2) 居中正方形躲圆角
    side = int(round(min(iw, ih) * CORE))
    cx, cy = (ix0 + ix1) / 2.0, (iy0 + iy1) / 2.0
    sx0 = int(round(cx - side / 2.0))
    sy0 = int(round(cy - side / 2.0))
    crop = sheet.crop((sx0, sy0, sx0 + side, sy0 + side)).convert("RGB")
    # 3) 下采样
    small = crop.resize((T, T), Image.LANCZOS)
    # 4) 轻度 posterize（RGB），补回 alpha=255
    small = ImageOps.posterize(small, POSTERIZE_BITS)
    out = small.convert("RGBA")
    px = out.load()
    for yy in range(T):
        for xx in range(T):
            r, g, b, _ = px[xx, yy]
            px[xx, yy] = (r, g, b, 255)
    return out, (sx0, sy0, side)


def mean_rgb(img):
    px = img.load()
    n = img.size[0] * img.size[1]
    sr = sg = sb = 0
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, _ = px[x, y]
            sr += r; sg += g; sb += b
    return (round(sr / n), round(sg / n), round(sb / n))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="", help="把每张 NEAREST 放大到 160×160 写进这个目录")
    ap.add_argument("--dry", action="store_true", help="只切不落盘")
    a = ap.parse_args()
    if not os.path.isfile(REF):
        sys.exit("❌ 找不到参考图：%s" % REF)
    sheet = Image.open(REF).convert("RGB")
    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
    print("参考图 %s  %dx%d" % (os.path.relpath(REF, ROOT), sheet.size[0], sheet.size[1]))
    for name, (row, col) in TILES.items():
        img, (sx0, sy0, side) = slice_one(sheet, row, col)
        n_colors = len(set(img.getdata()))
        print("  %-14s ← %s·%s  crop=(%d,%d,%dx%d)  均值 %s  色数 %d"
              % (name, row, col, sx0, sy0, side, side, mean_rgb(img), n_colors))
        if not a.dry:
            img.save(os.path.join(DST, name + ".png"), format="PNG")
        if a.preview:
            img.resize((160, 160), Image.NEAREST).save(
                os.path.join(a.preview, name + "_x10.png"), format="PNG")
    print("%s%s" % ("（--dry：未落盘）" if a.dry else "已写入 " + os.path.relpath(DST, ROOT),
                    "；预览 → " + a.preview if a.preview else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
