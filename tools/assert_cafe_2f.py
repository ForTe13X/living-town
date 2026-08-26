#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_cafe_2f.py — cafe 二楼像素门（AM1 / 编号133，docs/126 §一.2 补的那条空缺）。

守的性质，一句话：**"多楼层纵切"里，cafe 的 2F 必须真被渲染出家具、而且要和 1F 分得开。**

由来（docs/126 §一.2 实测）：`visual_gate.sh` 的室内壳采集**写死 `--probe-floor 1f`**，
7 栋楼只拍 1f ⇒ **cafe 2F（阿丽居所——"多楼层"这四个字的全部意义）从没有任何一帧被任何门看过。**
本门补拍 cafe 2F 并判：非空(真有家具) + 与 1F 可分，并自带**真渲染负对照**。

── 三帧（visual_gate.sh --shoot 拍，本脚本宿主侧判）──────────────────────────────
  vg_cafe2f.png       cafe 2F（被判帧）
  vg_int_cafe.png     cafe 1F（= 现役壳门那张同参数，复用不另渲）
  vg_cafe2f_bare.png  cafe 2F + `--draw-skip interior_furniture`（**家具被跳掉的空 2F**）

── 判据（几何闭式，取景公式与 assert_interior_shell._wall_samples 同源）──────────────
对 cafe(8×6) 的**内格区域**（x∈[1,6]、y∈[1,4]，剔除外墙一圈）量：
  · frac_diff(a,b) = 该区域内**逐像素 max 通道差 > DTOL** 的像素占比；
  · colors(f)      = 该区域内 //Q 量化去噪后的判别色数。
判据（阈值全部**量出来**，见 --measure 与文件末实测）：
  A. **2F 非空(真有家具)**：frac_diff(vg_cafe2f, vg_cafe2f_bare) ≥ FURN_MIN
     ——2F 与它自己的**空版**要差得够多；若 2F 被渲成空，则它==bare、frac→0 ⇒ 判红。
     ★这一条【就是】"2F 渲染弄空 ⇒ 门红" 的机器化，且**每次 CI 都跑**（负对照在判据内部，不是一次性 selftest）。
  B. **2F 与 1F 可分**：frac_diff(vg_cafe2f, vg_int_cafe) ≥ SEP_MIN
     ——2F=床/衣柜/梳妆镜/相片墙 vs 1F=吧台/甜点柜/吧凳/菜单牌，两张真不同的布局；
       挡"楼梯往返没换层 / 两层画成一样"的空过。
  C. **有牙自证(色数落差)**：colors(vg_cafe2f) − colors(vg_cafe2f_bare) ≥ COLOR_GAP
     ——空 2F 的判别色数必须**明显更低**，证明 bare 真是"更空的一帧"、负对照有区分度。

── 为什么阈值是这几个数（都在**未改动树的真帧**上量的，docs/122 §四手法）────────────
_MEASURED（docker gamecraft-runner:4.6.2 软渲 pin，seed3 tick600，本仓库当前 cafe 布局）：
  frac_diff(2F,bare)=0.129 · frac_diff(2F,1F)=0.230 · colors(2F)=35 · colors(bare)=17（gap 18）。
阈值各留 ~2× 余量、两侧都不贴实测值：FURN_MIN 0.06 · SEP_MIN 0.10 · COLOR_GAP 8。

── 本门【不】守什么（docs/41 §2.5）─────────────────────────────────────────────
· 只看 cafe 一栋的 2F（别的楼没有 2f，不测）。· 关系/存在判据，**不检查颜色对不对**
  （色值真源留在 WorldView.gd 不抄进判据——R2 记过为什么）。· 只看内格区域整体，不逐件家具。
· 软渲染 docker（镜像 pin 死 mesa）；非真机。· 不判 1F 往返不变式（那是 assert_space_roundtrip 的活）。
"""
import argparse
import math
import os
import sys
from collections import Counter

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

T = 48.0
VP = (1280.0, 768.0)
PAD = (120.0, 240.0)
Q = 24            # 量化桶宽（每通道）：把 1-LSB 级软渲噪声并进同桶，家具的显著色仍分得开
DTOL = 28         # 逐像素"算不同"的 max 通道差阈值


def _region(w_tiles, h_tiles):
    """cafe 内格 [1,w-2]×[1,h-2] 在 --shot-fit 帧上的像素矩形（剔除外墙一圈）。"""
    mw, mh = w_tiles * T, h_tiles * T
    zoom = min((VP[0] - PAD[0]) / mw, (VP[1] - PAD[1]) / mh)
    cam = (mw * 0.5, mh * 0.5)
    sx = lambda wx: (wx - cam[0]) * zoom + VP[0] * 0.5
    sy = lambda wy: (wy - cam[1]) * zoom + VP[1] * 0.5
    return (int(math.ceil(sx(1 * T))), int(math.ceil(sy(1 * T))),
            int(math.floor(sx((w_tiles - 1) * T))), int(math.floor(sy((h_tiles - 1) * T))))


def _px(img, rect):
    return list(img.crop(rect).convert("RGB").getdata())


def colors(img, rect):
    return len(Counter((r // Q, g // Q, b // Q) for r, g, b in _px(img, rect)))


def frac_diff(a, b, rect):
    pa, pb = _px(a, rect), _px(b, rect)
    n = min(len(pa), len(pb))
    d = sum(1 for i in range(n)
            if max(abs(pa[i][0] - pb[i][0]), abs(pa[i][1] - pb[i][1]), abs(pa[i][2] - pb[i][2])) > DTOL)
    return d / max(1, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", help="含 vg_cafe2f.png / vg_cafe2f_bare.png / vg_int_cafe.png 的目录")
    ap.add_argument("--furn-min", type=float, default=0.06, help="A: 2F vs 空2F 变化像素占比下限")
    ap.add_argument("--sep-min", type=float, default=0.10, help="B: 2F vs 1F 变化像素占比下限")
    ap.add_argument("--color-gap", type=int, default=8, help="C: colors(2F) − colors(空2F) 下限")
    ap.add_argument("--measure", action="store_true", help="只打印实测量，用于标阈值")
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("[CAFE2F] ❌ 需要 Pillow —— 装不上就没有这道门，不做 SKIP（SKIP 与 PASS 在汇总里都读作没红）")
        return 1

    def _open(name):
        p = os.path.join(a.out_dir, name)
        if not os.path.exists(p):
            print("[CAFE2F] ❌ 缺帧 %s（visual_gate --shoot 没拍出来？）" % name)
            sys.exit(1)
        return Image.open(p).convert("RGB")

    f2, f1, fb = _open("vg_cafe2f.png"), _open("vg_int_cafe.png"), _open("vg_cafe2f_bare.png")
    rect = _region(8, 6)
    npx = (rect[2] - rect[0]) * (rect[3] - rect[1])

    furn = frac_diff(f2, fb, rect)
    sep = frac_diff(f2, f1, rect)
    c2, cb = colors(f2, rect), colors(fb, rect)
    gap = c2 - cb

    print("[CAFE2F] 内格区域 %s（~%d px）  Q=%d  DTOL=%d" % (rect, npx, Q, DTOL))
    print("[CAFE2F]   A 2F↔空2F 变化占比 = %.4f (门槛 ≥ %.4f)  ← 非空/负对照" % (furn, a.furn_min))
    print("[CAFE2F]   B 2F↔1F   变化占比 = %.4f (门槛 ≥ %.4f)  ← 楼层可分" % (sep, a.sep_min))
    print("[CAFE2F]   C 色数 2F=%d 空2F=%d 落差=%d (门槛 ≥ %d)  ← 有牙自证" % (c2, cb, gap, a.color_gap))

    if a.measure:
        return 0

    fails = []
    if furn < a.furn_min:
        fails.append("A 2F 非空破：2F↔空2F 变化占比 %.4f < %.4f —— 2F 没渲出家具（渲成空房了）"
                     % (furn, a.furn_min))
    if sep < a.sep_min:
        fails.append("B 2F↔1F 可分破：变化占比 %.4f < %.4f —— 两层画得太像（楼梯往返没换层？）"
                     % (sep, a.sep_min))
    if gap < a.color_gap:
        fails.append("C 门无牙：2F 与空2F 的色数落差 %d < %d —— 负对照没区分度，'2F 渲成空'拦不住"
                     % (gap, a.color_gap))

    if fails:
        print("[CAFE2F] ❌ cafe 2F 像素门 FAIL（%d 条）：" % len(fails))
        for f in fails:
            print("    · " + f)
        return 1
    print("[CAFE2F] ✅ cafe 2F 像素门 PASS（非空 %.3f≥%.3f；与1F可分 %.3f≥%.3f；色数落差 %d≥%d ⇒ 空2F 会判红=有牙）"
          % (furn, a.furn_min, sep, a.sep_min, gap, a.color_gap))
    return 0


if __name__ == "__main__":
    sys.exit(main())
