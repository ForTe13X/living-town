#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_interior_shell.py — 室内外壳类型门（R2 / docs/69）。

守的性质，一句话：**进屋之后，这栋楼还得是这栋楼。**

由来（实测，docs/69 §一）：改前七栋楼八个楼层的室内墙是**同一条写死的配方**——
`WorldView._interior_wall()` 的第一个参数是 `sg`，函数体一次都没用过它，墙主面写死
`P_RES_FOOT`（住宅暖石灰）。于是澡堂/图书馆/工坊在**外面**是灰蓝石墙、暖灰石墙
（`BLD_PAL`，按 `map.json areas[].type` 分好了），**一进门全变成住宅暖木墙**。
八个楼层的墙两两 ΔE = 0.00，一对都分不开。

── 判据 ────────────────────────────────────────────────────────────────────
对每张室内帧，量出**墙主面的众数色**（几何见 `_wall_samples`，不是找色块），然后：
  A. `areas[].type` **不同**的两栋 ⇒ ΔE(CIE76) ≥ `--thresh`（默认 8.0）
  B. `areas[].type` **相同**的两栋 ⇒ ΔE ≤ `--same-tol`（默认 4.0）
B 臂不是凑数：它挡的是"干脆给每栋楼随机挑个色"这种**看起来也能过 A 臂**的修法——
本仓库要的是"室内跟着建筑类型走"，不是"每栋不一样就行"。

── 为什么阈值是这两个数（都是量出来的，不是拍的）──────────────────────────
· 改后四类墙主面两两 ΔE 的**最小值 15.43**（public↔workshop），最大 30.54。
· 唯一的同类内噪声源是 `_draw_interior_night()` 的**占用暖光**：屋里有人时整层压一层
  `X_GLOW_DEEP` α≈0.02，实测把墙从 `#836a48` 推到 `#886d49`（≤5/3/1 通道，ΔE ≈ 2.1）。
  它在正午也会画（`lit = min(0.12, occ*0.04)*0.5 > 0.001`），**所以不能靠"拍正午"绕开**。
⇒ 8.0 与 4.0 各自离真实分布有 ~2 倍余量，两侧都不贴边。

── ⚠️ 本门【不】守什么（docs/41 §2.5，逐条都是跑出来的，不是想出来的）─────────
见 docs/69 §三的 `does_not_detect` 全文。最要紧的三条：
  · 它**不检查颜色对不对**，只检查"分得开/该相同的相同"。把四类的色值整体换一套
    （哪怕换成四种荧光色）照样全绿——它是**关系判据**，不是**取值判据**。
    没做成取值判据是**蓄意**的：BLD_PAL 的真源在 `WorldView.gd`，把色值抄进本文件
    等于给同一份真相立第二个副本，而本仓库已经因为这种抄写吃过亏。
  · 它只看**墙**。地板、家具、夜光一个都不在判据里。
    **实测**：把地板整个塌回写死的住宅木地板（澡堂 `#96a5ab`→`#c8a273`，肉眼一眼看穿）
    ⇒ 本门 10/10 全绿、exit 0。
  · 它只看**被拍到的那几栋**——即 `$OUT` 里存在的 `vg_int_<space>.png`，
    由 `visual_gate.sh` 的 `INT_SPACES` 决定（默认 home/cafe/wash/work/library）。
    `shop` / `home2` / `cafe` 的 2f 不在里面 ⇒ 它们单独回归，本门一声不吭。
"""
import argparse
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


def _wall_samples(img, w_tiles, h_tiles, skip_cells):
    """墙主面的采样点集合。

    几何**闭式算出来**，不是"找一块颜色"——找颜色的判据在被守的东西坏掉时会跟着坏。
    `--shot-fit`（Main.gd）的取景：zoom = min((VP-PAD)/世界尺寸)，相机对准 bounds 中心。
    只取**左右两列**外墙：上排被楼层标签 `draw_string` 压着，下排常是门。
    每格只取纵向 [0.35T, 0.80T] 那一段——上面 24% 是顶棱高光、下面 14% 是墙脚暗边。
    """
    mw, mh = w_tiles * T, h_tiles * T
    zoom = min((VP[0] - PAD[0]) / mw, (VP[1] - PAD[1]) / mh)
    cam = (mw * 0.5, mh * 0.5)

    def sx(wx):
        return (wx - cam[0]) * zoom + VP[0] * 0.5

    def sy(wy):
        return (wy - cam[1]) * zoom + VP[1] * 0.5

    px = img.load()
    W, H = img.size
    out = []
    for gx in (0, w_tiles - 1):
        for gy in range(1, h_tiles - 1):
            if (gx, gy) in skip_cells:
                continue
            x0, x1 = sx(gx * T + 0.20 * T), sx(gx * T + 0.80 * T)
            y0, y1 = sy(gy * T + 0.35 * T), sy(gy * T + 0.80 * T)
            for yy in range(int(math.ceil(y0)), int(math.floor(y1))):
                for xx in range(int(math.ceil(x0)), int(math.floor(x1))):
                    if 0 <= xx < W and 0 <= yy < H:
                        out.append(px[xx, yy][:3])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", help="含 vg_int_<space>.png 的目录")
    ap.add_argument("--game", default=None, help="game/ 目录（默认脚本上一级的 game）")
    ap.add_argument("--thresh", type=float, default=8.0, help="异类必须分开的最小 ΔE")
    ap.add_argument("--same-tol", type=float, default=4.0, help="同类允许的最大 ΔE")
    ap.add_argument("--min-samples", type=int, default=2000, help="每帧墙面采样点下限")
    a = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("[INTSHELL] ❌ 需要 Pillow —— 装不上就没有这道门，不做 SKIP（SKIP 与 PASS 在汇总里都读作没红）")
        return 1

    game = a.game or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
    spaces = json.load(open(os.path.join(game, "data", "spaces.json"), encoding="utf-8"))
    areas = json.load(open(os.path.join(game, "data", "map.json"), encoding="utf-8")).get("areas", {})

    # portal 端点 → 采样时跳过（门那格不画墙）。从数据读而不是写死"门都在上下排"：
    # 今天确实都在上下排，但那是数据的现状，不是判据该依赖的前提。
    portal_cells = {}
    for p in spaces.get("portals", []):
        for side in ("from", "to"):
            e = p.get(side, {})
            sid, pos = e.get("space"), e.get("pos")
            if sid and pos:
                portal_cells.setdefault(sid, set()).add((int(pos[0]), int(pos[1])))

    shots = sorted(f for f in os.listdir(a.out_dir)
                   if f.startswith("vg_int_") and f.endswith(".png"))
    if len(shots) < 2:
        print("[INTSHELL] ❌ 只找到 %d 张室内帧（至少要 2 张才谈得上两两比较）" % len(shots))
        return 1

    meas = {}
    for fn in shots:
        sid = fn[len("vg_int_"):-len(".png")]
        sp = spaces.get("spaces", {}).get(sid)
        if sp is None:
            print("[INTSHELL] ❌ %s：spaces.json 里没有 space '%s'" % (fn, sid))
            return 1
        b = sp["bounds"]
        img = Image.open(os.path.join(a.out_dir, fn)).convert("RGB")
        samples = _wall_samples(img, int(b[2]), int(b[3]), portal_cells.get(sid, set()))
        # 判别力自检：采样几何一旦算错，众数就是一个无意义的数，而门会照常"全绿"。
        if len(samples) < a.min_samples:
            print("[INTSHELL] ❌ %s：墙面采样点只有 %d 个（<%d）—— 采样几何算错了，"
                  "这时候的众数色没有意义，门必须红而不是绿" % (fn, len(samples), a.min_samples))
            return 1
        modal, n = Counter(samples).most_common(1)[0]
        typ = str(areas.get(sid, {}).get("type", "?"))
        meas[sid] = {"typ": typ, "rgb": modal, "n": n, "tot": len(samples)}
        print("[INTSHELL] %-10s type=%-12s 墙主面众数=#%02x%02x%02x  (%d/%d 采样点)"
              % (sid, typ, modal[0], modal[1], modal[2], n, len(samples)))

    types = sorted(set(v["typ"] for v in meas.values()))
    print("[INTSHELL] %d 栋 / %d 类：%s" % (len(meas), len(types), ", ".join(types)))

    fails = []
    ids = sorted(meas)
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            p, q = meas[ids[i]], meas[ids[j]]
            d = de76(p["rgb"], q["rgb"])
            same = p["typ"] == q["typ"]
            if same and d > a.same_tol:
                fails.append("同类 %s(%s) vs %s(%s) ΔE=%.2f > %.2f —— 室内墙没有跟着"
                             "【建筑类型】走（是不是按楼各挑了一个色？）"
                             % (ids[i], p["typ"], ids[j], q["typ"], d, a.same_tol))
            if (not same) and d < a.thresh:
                fails.append("异类 %s(%s) vs %s(%s) ΔE=%.2f < %.2f —— 这两类的室内墙分不开"
                             % (ids[i], p["typ"], ids[j], q["typ"], d, a.thresh))
            print("    %-10s %-10s %-6s ΔE=%6.2f  %s"
                  % (ids[i], ids[j], "同类" if same else "异类", d,
                     "ok" if not (same and d > a.same_tol) and not ((not same) and d < a.thresh) else "❌"))

    if fails:
        print("[INTSHELL] ❌ 室内外壳类型门 FAIL（%d 条）：" % len(fails))
        for f in fails:
            print("    · " + f)
        return 1
    print("[INTSHELL] ✅ 室内外壳类型门 PASS（%d 栋 / %d 类，异类最小 ΔE ≥ %.1f、同类最大 ΔE ≤ %.1f）"
          % (len(meas), len(types), a.thresh, a.same_tol))
    return 0


if __name__ == "__main__":
    sys.exit(main())
