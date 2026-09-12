#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_shore.py —— 水岸瓦片切图（Wave G · G5；docs/49 §七）。

## 这一棒本来要"画"水，结果发现水早就在库里

docs/49 §七 给了两条路：把 `water.png` 做成有变化的瓦片，或者删掉它让 `WorldView`
的涟漪回退路复活。**两条都不是最省的那条**——

`game/assets/art/library/punyworld-overworld/punyworld-overworld-tileset.png`（CC0，已 vendored）
里躺着一整套**水-草自动贴图**：第 7-9 列 × 第 10-12 行是一个标准 3x3 块
（四角 / 四边 / 中心），**外圈自带岸泥 + 浅水亮边**，而且 10-12 / 13-15 / 16-18 / 19-21
是同一块的**四个动画帧**。

出货的 `water.png` 切自 (18,11) —— 那是**另一套**水贴图的**中心填充格**。
也就是说：**当初切图的人切走了自动贴图的正中间那一格，把外面那一圈岸线留在了原地**，
从此两个池塘就是两块纯色贴纸。岸线不需要画，它一直在同一个文件里，隔了 10 列。

⇒ 红线 #5「复用优先」在这里不是省事，是**正解**：CC0 同源、无生成图（红线 #4 / docs/43 R2）、
风格与草地/土路本来就是一套（它们切自同一张表）。

## 为什么要把草地键成透明，而不是直接用原瓦片

原瓦片的外圈**烘死了一圈春绿草地**（`(133,166,67)` 等 4 色，共 309 px）。
而 `WorldView` 给草地乘的是**季节色偏** `_season_veg()`（秋 `(1.22,0.98,0.60)`、冬 `(0.84,0.92,1.00)`），
给水面乘的是**夜罩** `wtint`。两个乘子不同 ⇒ 烘死的那圈草**入秋不会变黄**：
草地 `(133,166,67)×(1.22,0.98,0.60)=(162,163,40)`，烘死的仍是 `(133,166,67)`
⇒ 秋天每个池塘会套一圈**春天的绿边**。

所以本工具把**与瓦片边缘连通的、且颜色恰好出现在本仓库自己的 grass_*.png 里**的像素
键成透明，让下面**已经按季节染过色**的真草地透上来。

- **只键"与边缘连通"的**（而不是按颜色全局键）：否则水面里若有一颗草色像素会被打成洞。
- **只键"出货草地调色板里的 4 个精确色"**：岸泥、浅水、以及岸边那圈更黄的枯草
  （`(157,167,71)` / `(184,175,73)`，**不在** grass_*.png 的调色板里）全部保留 —— 它们正是岸线本身。

用法:
    python tools/slice_shore.py            # 把 8 张岸线瓦片写进 game/assets/art/terrain/
    python tools/slice_shore.py --check    # 只重建、不落盘，报与出货是否逐像素相同
"""
import os
import sys
from collections import deque

try:
    from PIL import Image
except ImportError:
    sys.exit("❌ slice_shore: 需要 Pillow（pip install pillow）")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "game", "assets", "art", "library",
                     "punyworld-overworld", "punyworld-overworld-tileset.png")
DST = os.path.join(ROOT, "game", "assets", "art", "terrain")
T = 16

# ── 出货 terrain 瓦片的【唯一坐标表】 ─────────────────────────────────────────
# 前 5 行与 `tools/slice_visual.py` 第 12-16 行**必须一致**；
# `tools/terrain_gate.py` 会去解析那个文件的源码来核对这一点（不是靠注释里的承诺）。
LEGACY = {                      # name: (col, row)   —— 原样裁切，不做键控
    "grass_a": (0, 0),
    "grass_b": (1, 0),
    "grass_flowers": (2, 0),
    "dirt": (11, 1),
    "water": (18, 11),
}

# 岸线 8 向。**命名按"哪一侧是陆地"**（不是按它在表里的方位），
# 因为调用方 `WorldView._water_tile()` 手里有的正是"四邻是不是水"。
# 3x3 块：列 7-9 × 行 10-12，中心 (8,11) 与出货 water.png 逐像素相同（都是 256 px 的 (4,160,180)）。
SHORE = {
    "water_nw": (7, 10), "water_n": (8, 10), "water_ne": (9, 10),
    "water_w":  (7, 11), "water_e": (9, 11),
    "water_sw": (7, 12), "water_s": (8, 12), "water_se": (9, 12),
}

GRASS_SRC = ("grass_a", "grass_b", "grass_flowers")


def grass_palette(rebuilt):
    """键控要认的"草地场"精确色集合 —— 从**当场重建出来的**草地瓦片里取。

    ⚠ 第一版是从 `game/assets/art/terrain/grass_*.png`（**出货目录**）读的。
    那正是 `coif_characters.py:444` 记过、`art_gate.py` 自证①专门要抓的那种翻车：
    **读了出货目录的"重建"不是重建，是抄答案** —— 一旦有人手改了出货的草地贴图，
    键控会跟着改，重建结果也跟着改，门就静默退化成 `x → x`。
    改成吃重建结果之后，本模块的重建路径**只读 CC0 总表一个文件**。

    仍然不写死常量：草地哪天换了切图坐标，这里自动跟着换。
    """
    pal = set()
    for n in GRASS_SRC:
        pal |= set(rebuilt[n].getdata())
    return pal


def key_grass(tile, pal):
    """把【与瓦片边缘 4-连通、且颜色在 pal 里】的像素键成全透明。返回 (新图, 键掉的像素数)。"""
    out = tile.copy()
    px = out.load()
    seen = [[False] * T for _ in range(T)]
    q = deque()
    for i in range(T):
        for (x, y) in ((i, 0), (i, T - 1), (0, i), (T - 1, i)):
            if not seen[y][x] and px[x, y] in pal:
                seen[y][x] = True
                q.append((x, y))
    n = 0
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        n += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b = x + dx, y + dy
            if 0 <= a < T and 0 <= b < T and not seen[b][a] and px[a, b] in pal:
                seen[b][a] = True
                q.append((a, b))
    return out, n


def _crop(sheet, col, row):
    return sheet.crop((col * T, row * T, (col + 1) * T, (row + 1) * T))


def build(sheet=None):
    """当场重建**全部 13 张** terrain 瓦片。返回 {name: RGBA Image}。

    `terrain_gate.py` 直接吃这个函数的输出去和出货逐像素比对 —— 与 `art_gate.py`
    吃 `coif_characters.build()` 是同一个形状（当场重建 + 逐字节比，不是校验和清单）。

    **整条路径只读 `SHEET` 一个文件**（键控用的草地调色板取自本函数刚重建出的草地瓦片），
    所以 `terrain_gate.py` 的"来源自证"可以硬性要求：出货目录读到 0 个文件。
    """
    if sheet is None:
        with Image.open(SHEET) as im:
            sheet = im.convert("RGBA")
    out = {}
    for name, (c, r) in LEGACY.items():
        out[name] = _crop(sheet, c, r)
    pal = grass_palette(out)
    for name, (c, r) in SHORE.items():
        out[name], _ = key_grass(_crop(sheet, c, r), pal)
    return out


def main():
    check = "--check" in sys.argv
    if not os.path.isfile(SHEET):
        sys.exit("❌ 找不到 CC0 源表：%s" % SHEET)
    built = build()
    n_new = n_same = n_diff = 0
    for name in sorted(SHORE):
        path = os.path.join(DST, name + ".png")
        img = built[name]
        if os.path.isfile(path):
            with Image.open(path) as raw:
                old = raw.convert("RGBA")
            same = list(old.getdata()) == list(img.getdata())
            n_same += same
            n_diff += (not same)
            print("  %-10s %s" % (name, "逐像素相同" if same else "★ 与出货不同"))
        else:
            n_new += 1
            print("  %-10s （新）" % name)
        if not check:
            img.save(path, format="PNG")
    print("\n%s：8 张岸线瓦片  新增 %d / 相同 %d / 不同 %d"
          % ("检查" if check else "已写入 " + os.path.relpath(DST, ROOT), n_new, n_same, n_diff))
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    sys.exit(main())
