#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_tree_stand.py —— 林相点阵门（Wave V · V3）。

守的性质一句话：**一片林子不许是一张盖章点阵，而且拆掉点阵不许把树拆没。**

形状照抄 `tools/assert_interior_shell.py`（R2）与 `tools/assert_furniture_role.py`（S3）：
判据在宿主侧跑、吃已经拍好的帧、阈值是量出来的、几何有自检。

## 为什么要有它

改前实测：`map.json trees` 的 156 格是两块 6x13 的**实心矩形**，而渲染是
【同一张 tree_big x 同一个 veg 乘子 x 同一个亚格偏移】=> 逐格严格周期。
它与 R2 的「八栋楼共用一张写死的住宅皮」、S3 的「11 个货架一份画法」是**同一条病的第三个实例**，
只是载体从室内换到了外景，而外景正是玩家看得最多的那一半画面。

## 两条臂 —— 而 B 臂不是凑数，它挡的是我自己真的踩过的那一次

* **A（点阵）**：林块内部【平移恰好一格】之后的平均逐像素差 P >= `--min-p`。
  盖章点阵 => P 趋近 0（改前实测 0.217-4.470，与同一帧的池塘 0.000 同一个数量级）。
* **B（密度）**：林块内部露出的**地面色**占比 <= `--max-ground`。
  只有 A 臂时，"把树删掉一半"能让 P 大幅上升而**照样过门**。这不是假想：
  本棒第一版用 `draw_texture_rect_region` 的**负源宽**做水平镜像，屏幕上"看起来翻转了"，
  实测却把树吃掉了一大块（地面色 24.66% -> 63.23%），**而 A 臂对它全绿**。
  B 臂就是那次的机器化。

地面色**不写死**，而是从同一帧里现取：在地图上找一块 authored 空地（不在任何 area/树/水/墙里）、
取其中**最均匀**的一块的众数色。=> 四季、昼夜、天气换了，判据跟着换，不需要第二份真相。

## 阈值是量出来的（多 seed / 昼夜 / 跨季，不是单 seed 标定）

docs/74 §四 的教训原话：`visual_gate.sh` 写死 SEED=3，只在 seed 3 上量会得到 2.08，
换到 seed 1/4/6 就是 5.65 => 零代码变更直接变红。所以本门的 P 是在
**3 个时刻 x 6 个 seed x 2 个林块 x 2 个方向 = 72 个读数**上量的：

    条件                改前 P                改后 P
    正午 tick600        0.423 - 4.470        25.790 - 30.006
    夜   tick728        0.217 - 2.244        13.002 - 17.714     <- 夜是最紧的一档
    第15天 tick3480     0.423 - 4.470        25.790 - 35.335
    ----------------------------------------------------------
    全部 72 个          [0.217, 4.470]       [13.002, 35.335]

`--min-p` 默认 **8.0**：离改前上界 4.470 有 1.79x、离改后下界 13.002 有 1.63x。
**它是按【夜】标的，不是按门今天要跑的那格（正午）标的** —— 正午那格两侧余量是 5.8x / 3.2x，
照正午标会得到一个换到夜里就变红的数。8.0-13.0 之间是本门**不表态**的区间。

`--max-ground` 默认 **0.22**，同样是在那 3x6 个帧上量的（地面参考色**逐帧现取** ⇒ 它对
昼夜/季/天气几乎免疫，实测三档读数完全重合）：

    健康：改前 11.6-16.5%   改后 8.0-9.4%
    坏掉：负源宽镜像+全套分化 29.0% / 50.6%     负源宽镜像+全体翻转 69.7% / 95.3%

0.22 距健康上界 16.5% 有 1.33x、距坏掉下界 29.0% 有 1.32x。**这个余量比 A 臂窄，写在这里是因为它就是窄的**：
将来若有人**蓄意**把林块疏开（比如让林子透光），这一臂会先红，而那时候该做的是重新量、重新定，不是抬阈值。

## 怎么接进 CI（本棒**不许碰 `tools/**`**，接线留给合流的人）

1. 把本文件挪到 `tools/assert_tree_stand.py`（与另外两道室内门同目录）。
2. `tools/visual_gate.sh`：在已经起好的那个 Xvfb 上多拍一帧整镇图（**不另起容器**）——
   与室内那两道门共用同一个 Xvfb 正是 S3 的做法：
       godot ... -- --seed "$SEED" --speed 0 --warmup-tick 600 --backend logic \\
                    --shot-fit --shot "$OUTDIR/vg_town.png"
   然后跑：
       python3 tools/assert_tree_stand.py --frame "$OUTDIR/vg_town.png" --map game/data/map.json
   非 0 退出即整体 FAIL（照 `assert_interior_shell.py` 现有的 rc 汇总写法）。
3. `tools/ci.sh` 第 6 步抬头的门数 +1，并把"林相"加进那行总判文案。

⚠️ 接线的人请注意：`visual_gate.sh` 现在写死 `SEED=3`、正午。本门的阈值**已经按夜标过**，
所以就算将来把 fixture 换成夜里也不会假红；反过来，若有人把 `--min-p` 提到 13 以上，
它会在夜里变红 —— 那个数是**改后**的下界，不是余量。
"""
import argparse
import json
import sys
from collections import Counter

try:
    from PIL import Image, ImageChops
except ImportError:
    print("[TREESTAND] 需要 Pillow（与另外两道视觉门同一个依赖）", file=sys.stderr)
    sys.exit(1)


# ── --shot-fit 的取景几何 ────────────────────────────────────────────────────
# docs/41 §6 盲区⑥：**不许按窗口尺寸算地图矩形**。canvas_items 拉伸下基准视口恒为 1280x768，
# zoom = min((1280,768) - HOME_PAD(120,240)) / (W*48, H*48)；本地图 64x48 => 528/2304
# => 1 格 = 11 基准像素、原点 (288,120)。实拍的帧再乘 实际宽/1280。
# 这两个数与 docs/69 §二 实测的室内 bbox 起点 (288,120) 逐字相符 —— 那是一次独立的交叉验证。
BASE_W, BASE_H = 1280.0, 768.0
PAD_X, PAD_Y = 120.0, 240.0
TILE_WORLD = 48.0


def geometry(im, map_w, map_h):
    zoom = min((BASE_W - PAD_X) / (map_w * TILE_WORLD), (BASE_H - PAD_Y) / (map_h * TILE_WORLD))
    tile = TILE_WORLD * zoom
    ox = BASE_W * 0.5 - map_w * TILE_WORLD * 0.5 * zoom
    oy = BASE_H * 0.5 - map_h * TILE_WORLD * 0.5 * zoom
    s = im.width / BASE_W
    return tile * s, ox * s, oy * s, s


def crop_tiles(im, g, tx, ty, tw, th):
    tile, ox, oy, _ = g
    return im.crop((int(round(ox + tx * tile)), int(round(oy + ty * tile)),
                    int(round(ox + (tx + tw) * tile)), int(round(oy + (ty + th) * tile))))


def periodicity(im, g, tx, ty, tw, th):
    """一格周期性残差：区域与它自己【平移恰好一格】的平均 |Δ|（RGB 再平均）。"""
    out = []
    for dx, dy in ((0, 1), (1, 0)):
        a = crop_tiles(im, g, tx, ty, tw - dx, th - dy)
        b = crop_tiles(im, g, tx + dx, ty + dy, tw - dx, th - dy)
        d = list(ImageChops.difference(a, b).getdata())
        out.append(sum(sum(t) for t in d) / (3.0 * len(d)))
    return out


def stands(trees):
    """把树格切成连通的矩形林块（按 x 断开；本地图是两块实心 6x13）。"""
    xs = sorted(set(x for x, _ in trees))
    ys = sorted(set(y for _, y in trees))
    blocks, cur = [], [xs[0]]
    for p, q in zip(xs, xs[1:]):
        if q == p + 1:
            cur.append(q)
        else:
            blocks.append(cur); cur = [q]
    blocks.append(cur)
    out = []
    for bx in blocks:
        by = sorted(set(y for x, y in trees if x in bx))
        out.append((bx[0], by[0], len(bx), len(by)))
    return out


def ground_color(im, g, m, occupied):
    """从同一帧里现取「地面色」：在 authored 空地上找**最均匀**的一块，取它的众数色。

    不写死颜色的理由与 R2/S3 一样：色值的真源在 `WorldView.gd`，抄进判据文件等于立第二个副本。
    这里更进一步 —— 四季/昼夜/天气都会乘这个色，写死的任何值都活不过一次换季。
    """
    best = None
    K = 3
    for ty in range(0, int(m["height"]) - K):
        for tx in range(0, int(m["width"]) - K):
            if any((tx + i, ty + j) in occupied for i in range(K) for j in range(K)):
                continue
            c = crop_tiles(im, g, tx, ty, K, K)
            cnt = Counter(c.getdata())
            top, n = cnt.most_common(1)[0]
            frac = n / float(c.width * c.height)
            if best is None or frac > best[0]:
                best = (frac, top, (tx, ty))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frame", required=True)
    ap.add_argument("--map", required=True)
    ap.add_argument("--min-p", type=float, default=8.0)
    ap.add_argument("--max-ground", type=float, default=0.22)
    ap.add_argument("--min-samples", type=int, default=2000)
    a = ap.parse_args()

    m = json.load(open(a.map, encoding="utf-8"))
    trees = [tuple(c) for c in m.get("trees", [])]
    im = Image.open(a.frame).convert("RGB")
    g = geometry(im, int(m["width"]), int(m["height"]))
    errs, notes = [], []

    # ── C 臂：采样自检（先跑；几何算错时另外两条臂的数字没有意义）─────────────
    # 防的是最难看的那种失效：取景公式错 => 采样点全落在别处 => 门照常全绿。
    # R2 的自证④是同一件事，只是它量的是"墙面采样点有几个"。
    if im.width % int(BASE_W) != 0 or im.height % int(BASE_H) != 0:
        errs.append("帧尺寸 %dx%d 不是基准 1280x768 的整数倍 —— 取景公式不适用，拒绝给判决"
                    % (im.width, im.height))
    if not trees:
        errs.append("map.json 里一棵 authored 树都没有 —— 本门的输入没了，这【不是】通过")
    if errs:
        for e in errs:
            print("[TREESTAND] ❌ " + e)
        return 1

    occupied = set(trees)
    for aid, ar in m.get("areas", {}).items():
        r = ar.get("rect", [0, 0, 0, 0])
        for i in range(int(r[2])):
            for j in range(int(r[3])):
                occupied.add((int(r[0]) + i, int(r[1]) + j))
    for key in ("water", "walls", "blockers"):
        for c in m.get(key, []):
            occupied.add((int(c[0]), int(c[1])))

    gc = ground_color(im, g, m, occupied)
    if gc is None:
        errs.append("找不到任何一块 3x3 的 authored 空地 —— B 臂无从标定")
    else:
        print("[TREESTAND] 地面参考色 = #%02x%02x%02x（取自空地格 %s，块内占比 %.1f%%）"
              % (gc[1][0], gc[1][1], gc[1][2], gc[2], 100 * gc[0]))

    for bi, (bx, by, bw, bh) in enumerate(stands(trees), 1):
        if bw < 3 or bh < 3:
            notes.append("林块%d 只有 %dx%d 格，内部不足 1x1 —— **跳过，且这不是通过**" % (bi, bw, bh))
            continue
        tx, ty, tw, th = bx + 1, by + 1, bw - 2, bh - 2
        reg = crop_tiles(im, g, tx, ty, tw, th)
        npx = reg.width * reg.height
        if npx < a.min_samples:
            errs.append("林块%d 内部采样点只有 %d（< %d）—— 取景可能算错" % (bi, npx, a.min_samples))
            continue
        pv, ph = periodicity(im, g, tx, ty, tw, th)
        gf = 0.0
        if gc is not None:
            gf = sum(1 for p in reg.getdata() if p == gc[1]) / float(npx)
        print("[TREESTAND] 林块%d 格(%d,%d %dx%d) 内部(%dx%d, %d px)  P竖=%6.3f P横=%6.3f  地面色占比=%.1f%%"
              % (bi, bx, by, bw, bh, tw, th, npx, pv, ph, 100 * gf))
        if pv < a.min_p:
            errs.append("林块%d 竖向周期残差 P=%.3f < %.2f —— 这片林子是【逐格盖章】的" % (bi, pv, a.min_p))
        if ph < a.min_p:
            errs.append("林块%d 横向周期残差 P=%.3f < %.2f —— 这片林子是【逐格盖章】的" % (bi, ph, a.min_p))
        if gc is not None and gf > a.max_ground:
            errs.append("林块%d 露出的地面色占 %.1f%% > %.1f%% —— 点阵是拆了，树也拆没了"
                        % (bi, 100 * gf, 100 * a.max_ground))

    for n in notes:
        print("[TREESTAND] ⚠️  " + n)
    if errs:
        for e in errs:
            print("[TREESTAND] ❌ " + e)
        print("[TREESTAND] ❌ 林相点阵门 FAIL（%d 条）" % len(errs))
        return 1
    print("[TREESTAND] ✅ 林相点阵门 PASS（P >= %.2f 且 地面色 <= %.0f%%）" % (a.min_p, 100 * a.max_ground))
    return 0


if __name__ == "__main__":
    sys.exit(main())
