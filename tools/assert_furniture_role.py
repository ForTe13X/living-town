#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_furniture_role.py — 家具语义分化门（S3）。

守的性质，一句话：**架子上摆的东西，得是这间屋子会有的东西。**

由来（R2 交接 docs/69 §五，S3 在像素侧复核）：改前 `shelf` 是**一份画法（带三色书脊的书架）
× 11 个实例 × 8/8 个楼层**。它在图书馆和阿丽卧室是**对的**，在**杂货铺（该是货架）、
工坊（该是工具架）、澡堂（该是毛巾架）、咖啡区（该是杯碟架）是错的**。
这是 docs/51 §二·2「一张贴图 = 五种物件」的同形病，只是载体从贴图换成了程序化分支。

── 判据 ────────────────────────────────────────────────────────────────────
对每张室内帧，把该层**全部 `shelf` 格**的字形像素取出来（几何闭式算，见 `_glyph_px`），
取占比 ≥5% 的颜色作为**字形签名**，两两比 Hausdorff-ΔE(CIE76)：

    d(A,B) = max( max_{a∈A} min_{b∈B} ΔE(a,b),  max_{b∈B} min_{a∈A} ΔE(a,b) )

d 小 ⇔ 两边每一种显眼的颜色在对面都找得到近邻 ⇔ **它们是同一个画法**。

  A. `EXPECT` 标签**不同**的两栋 ⇒ d ≥ `--thresh`（默认 12.0）
  B. `EXPECT` 标签**相同**的两栋 ⇒ d ≤ `--same-tol`（默认 8.0）
  C. **同一间屋里**的多个 `shelf` ⇒ 逐像素完全相同（同帧同光照，不需要容差）
  D. 采样自检：每栋的字形样本数 ≥ `--min-samples`，且签名至少 3 色

B 臂挡的是"**干脆给每个 space id 各挑一个画法**"这种 A 臂照样能过的假修法
（R2 的 B 臂挡的是同一件事的墙面版本，这里照抄那个规格）。
C 臂挡的是更细一档的假修法：**按家具实例哈希**——它连 B 臂都能骗过去。

── ⚠️ `EXPECT` 是什么、不是什么 ────────────────────────────────────────────
它是**这道门的断言本体**：每栋楼的架子【该是哪一类物件】。它**不含任何色值**——
R2 的 `does_not_detect` 已经记过为什么不能把色值抄进判据文件（给同一份真相立第二个副本）。
本表记的是**分组意图**，改 `WorldView._furniture_role()` 的分组而不改这里，门就该红，那正是它的用途。

⚠️ **`library` 与两栋住宅同标"书架"是【蓄意】的，不是漏写**：R2 实测判定图书馆与阿丽卧室
这两处**改前就是对的**，S3 因此让 living / study 两档共用改前那段画法、**逐字节不动**。
⇒ 本门**不要求**图书馆与住宅的架子分得开，而且它**永远不会**要求——
   若将来有人认为藏书空间该有自己的画法，那是一次**有意的**美术决定，改这张表即可。

── 为什么阈值是 12.0 / 8.0（**都是量出来的，而且是在门自己的 fixture 上量的**）──
· 改后异类字形两两 d 的**最小值 29.19**（cafe↔wash），最大 58.36。
· 改前**全部** 20 对异类的 d 落在 **0.00–2.08** —— 那就是"一份画法"的读数。
· B 臂的噪声源是 `_draw_interior_night()` 的**占用暖光**（屋里有人时整层压一层 `X_GLOW_DEEP`，
  `lit = min(0.12, occ*0.04)*0.5`，**正午也画**）。**逐 seed 实测**（home vs home2，tick=600）：
      seed 1  5.65 │ seed 2  2.08 │ seed 3  2.08 │ seed 4  5.65 │ seed 5  3.58 │ seed 6  5.65
  ⚠️ **5.65 是物理上界不是巧合**：`lit` 在 occ≥3 时被 `min()` 钳到 0.12（正午 α=0.06），
     seed 1/4/6 三次读数**逐字节相同**（字形主色都是 `#64482b`）正是钳住了的证据。
  ⚠️ **这条标定纠正了一次差点犯的错**：只在门自己的 seed 3 上量会得到 2.08，
     照抄 R2 的 `same-tol=4.0` 会让本门在 **seed 1/4/6 上零代码变更直接变红**
     —— docs/41 §6 那条"写死的绝对数在别的配置下是什么"，在本门身上是"**换个 seed** 会怎样"。
⇒ 12.0 离异类实测下界 29.19 有 2.4×，离改前上界 2.08 有 5.8×；
   8.0 离占用暖光的**钳位上界** 5.65 有 1.4×。8.0–12.0 之间是本门不表态的区间。
"""
import argparse
import itertools
import json
import math
import os
import sys
from collections import Counter

try:                                    # Windows 控制台默认 GBK，直接 print 中文/✅ 会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

T = 48.0                    # 世界格边长（px），与 WorldView.T 同源
VP = (1280.0, 768.0)        # --shot 的基准视口（docs/41 §6 盲区⑥：不是窗口尺寸）
PAD = (120.0, 240.0)        # Main.gd 的 --shot-fit HUD 余量
INSET = 0.15                # 字形采样窗（格内比例）。见下面 _glyph_px 的注释
MIN_FRAC = 0.05             # 进签名的最小占比

# 每栋楼的架子【该是哪一类物件】。含义与"为什么 library 跟住宅同组"见本文抬头。
EXPECT = {
    "home":    "书架",
    "home2":   "书架",
    "library": "书架",      # 蓄意与住宅同组：R2 判定图书馆改前就是对的，S3 一个像素没动它
    "cafe":    "杯碟架",
    "shop":    "货架",
    "wash":    "毛巾架",
    "work":    "工具架",
}


def srgb_to_lab(c):
    def f(u):
        u /= 255.0
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4
    r, g, b = f(c[0]), f(c[1]), f(c[2])
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = (r * 0.2126 + g * 0.7152 + b * 0.0722)
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def h(t):
        return t ** (1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
    x, y, z = h(x), h(y), h(z)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


def de76(a, b):
    la, lb = srgb_to_lab(a), srgb_to_lab(b)
    return math.sqrt(sum((p - q) ** 2 for p, q in zip(la, lb)))


def hausdorff(A, B):
    return max(max(min(de76(a, b) for b in B) for a in A),
               max(min(de76(a, b) for a in A) for b in B))


def cell_rect(w_tiles, h_tiles, gx, gy, inset):
    """家具格 (gx,gy) 在 `--shot-fit` 帧上的像素矩形。

    几何**闭式算出来**，不是"找一块颜色"——找颜色的判据在被守的东西坏掉时会跟着坏。
    取景公式与 `tools/assert_interior_shell.py:_wall_samples` 同源（同一个 zoom/cam）。
    """
    mw, mh = w_tiles * T, h_tiles * T
    zoom = min((VP[0] - PAD[0]) / mw, (VP[1] - PAD[1]) / mh)
    cam = (mw * 0.5, mh * 0.5)
    sx = lambda wx: (wx - cam[0]) * zoom + VP[0] * 0.5
    sy = lambda wy: (wy - cam[1]) * zoom + VP[1] * 0.5
    return (int(math.ceil(sx((gx + inset) * T))), int(math.ceil(sy((gy + inset) * T))),
            int(math.floor(sx((gx + 1 - inset) * T))), int(math.floor(sy((gy + 1 - inset) * T))))


def _glyph_px(img, b, cells):
    """本层全部 shelf 格的**字形**像素。

    ⚠️ 缩进到 `[0.15,0.85]²` 不是随手取的：整格里有**地板**，而地板早已被 R2 按建筑类型分过档
    ⇒ 拿整格比，量到的是**地板的差异**，与货架无关。本棒第一版的清点脚本正是这么量错的
    （22 对里 18 对"不同"，而那 18 对差的全是地板）。
    `WorldView._draw_shelf` 的五档**全部**铺满 `[0.10,0.90]×[0.05,0.90]` 的背板，
    所以这个窗口里**保证**只有货架自身的笔画——这条前提写在 `_draw_shelf` 的注释里，两边互指。
    """
    out = []
    for gx, gy in cells:
        out += list(img.crop(cell_rect(int(b[2]), int(b[3]), gx, gy, INSET)).getdata())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", help="含 vg_int_<space>.png 的目录")
    ap.add_argument("--game", default=None, help="game/ 目录（默认脚本上一级的 game）")
    ap.add_argument("--thresh", type=float, default=12.0, help="异类必须分开的最小 ΔE")
    ap.add_argument("--same-tol", type=float, default=8.0, help="同类允许的最大 ΔE")
    ap.add_argument("--min-samples", type=int, default=1500, help="每帧字形采样点下限")
    a = ap.parse_args()

    try:
        from PIL import Image, ImageChops
    except ImportError:
        print("[FURNROLE] ❌ 需要 Pillow —— 装不上就没有这道门，不做 SKIP（SKIP 与 PASS 在汇总里都读作没红）")
        return 1

    game = a.game or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
    spaces = json.load(open(os.path.join(game, "data", "spaces.json"), encoding="utf-8"))
    inter = json.load(open(os.path.join(game, "data", "interiors.json"), encoding="utf-8"))

    shots = sorted(f for f in os.listdir(a.out_dir)
                   if f.startswith("vg_int_") and f.endswith(".png"))
    meas, fails = {}, []
    for fn in shots:
        sid = fn[len("vg_int_"):-len(".png")]
        floor = (inter.get(sid) or {}).get("1f")
        if floor is None or sid not in EXPECT:
            continue                       # 只判被 EXPECT 认领、且有 1f 的那几栋
        cells = [(int(f["pos"][0]), int(f["pos"][1]))
                 for f in floor.get("furniture", []) if f.get("slot") == "shelf"]
        if not cells:
            continue
        b = spaces["spaces"][sid]["bounds"]
        img = Image.open(os.path.join(a.out_dir, fn)).convert("RGB")
        px = _glyph_px(img, b, cells)
        # D 臂·采样自检：几何一旦算错，签名就是一个无意义的数，而门会照常"全绿"。
        if len(px) < a.min_samples:
            print("[FURNROLE] ❌ %s：字形采样点只有 %d 个（<%d）—— 采样几何算错了，"
                  "这时候的签名没有意义，门必须红而不是绿" % (fn, len(px), a.min_samples))
            return 1
        n = len(px)
        sig = [rgb for rgb, k in Counter(px).most_common() if k / n >= MIN_FRAC]
        if len(sig) < 3:
            print("[FURNROLE] ❌ %s：字形签名只有 %d 色（<3）—— 采样窗大概率落在了平坦的地板上，"
                  "而不是货架上" % (fn, len(sig)))
            return 1
        meas[sid] = {"sig": sig, "n": n, "cells": cells}
        print("[FURNROLE] %-10s 期望=%-6s %d 格 / %5d px  签名%d 色: %s"
              % (sid, EXPECT[sid], len(cells), n, len(sig),
                 " ".join("#%02x%02x%02x" % c for c in sig)))
        # C 臂：同一间屋里的多个 shelf 必须逐像素相同（同帧同光照 ⇒ 不需要容差）
        if len(cells) >= 2:
            crops = [img.crop(cell_rect(int(b[2]), int(b[3]), gx, gy, INSET)) for gx, gy in cells]
            if len({c.size for c in crops}) == 1:
                for (i, j) in itertools.combinations(range(len(crops)), 2):
                    if ImageChops.difference(crops[i], crops[j]).getbbox(alpha_only=False) is not None:
                        fails.append("同屋 %s 的 shelf#%d 与 shelf#%d 逐像素不同 —— "
                                     "同一间屋里的同一种家具被画成了两样（按实例哈希？）" % (sid, i, j))
                print("           └ C 臂：同屋 %d 格 shelf 逐像素一致 ✅" % len(crops))

    if len(meas) < 2:
        print("[FURNROLE] ❌ 只认出 %d 栋带 shelf 的室内帧（至少要 2 张才谈得上两两比较）" % len(meas))
        return 1

    ids = sorted(meas)
    print("[FURNROLE] %d 栋 / %d 类物件：%s"
          % (len(ids), len({EXPECT[s] for s in ids}), "、".join(sorted({EXPECT[s] for s in ids}))))
    for p, q in itertools.combinations(ids, 2):
        d = hausdorff(meas[p]["sig"], meas[q]["sig"])
        same = EXPECT[p] == EXPECT[q]
        bad = (same and d > a.same_tol) or ((not same) and d < a.thresh)
        if same and d > a.same_tol:
            fails.append("同类 %s(%s) vs %s(%s) ΔE=%.2f > %.2f —— 本该是同一个画法却分开了"
                         "（是不是按 space id 各挑了一个？）" % (p, EXPECT[p], q, EXPECT[q], d, a.same_tol))
        if (not same) and d < a.thresh:
            fails.append("异类 %s(%s) vs %s(%s) ΔE=%.2f < %.2f —— 这两栋的架子分不开"
                         % (p, EXPECT[p], q, EXPECT[q], d, a.thresh))
        print("    %-10s %-10s %-6s ΔE=%6.2f  %s"
              % (p, q, "同类" if same else "异类", d, "❌" if bad else "ok"))

    if fails:
        print("[FURNROLE] ❌ 家具语义分化门 FAIL（%d 条）：" % len(fails))
        for f in fails:
            print("    · " + f)
        return 1
    print("[FURNROLE] ✅ 家具语义分化门 PASS（%d 栋 / %d 类，异类最小 ΔE ≥ %.1f、同类最大 ΔE ≤ %.1f）"
          % (len(ids), len({EXPECT[s] for s in ids}), a.thresh, a.same_tol))
    return 0


if __name__ == "__main__":
    sys.exit(main())
