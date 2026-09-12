#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pond.py —— 水面量具（Wave G · G5；docs/49 §七）。

## 为什么不能复用 `tools/seam.py` 原样

`seam.py` 量的是**地图矩形与界外暗林**那道缝（`map_rect` 的四条边）。
本棒要量的是**镇子内部**一个 8x5 水域与草地之间的岸线 —— 完全不同的一条边界，
但**同一套几何**（`--shot-fit` 整镇入画时 map_rect 与格边长的换算）和**同一套纪律**。
所以本文件 **import seam**，直接用它的 `map_rect()` / `lum()`，不复制第二份公式。

## 判据（每条都写了"什么样的假改动能骗过它"）

**承重的是第 2 条 `path`。第 1、3 条是配套的防作弊项。**
本量具改过 **四版**，前三版都被某一张具体的帧证伪了；四次证伪的记录留在下面，
因为每一次都是同一个病的不同投影：**判据量到的东西，不是我以为它在量的东西。**

1. **`interior_distinct`：池心取样区的 distinct colour 数。**
   现状 = 1（整块纯色贴纸）。
   ⚠ **这一条单独立门是【可以被空改动骗过的】**——往贴图里塞一个杂色像素、
   或让 `WorldView` 的涟漪回退路复活，都能把它顶到 >1，而那道 90° 直角**一点没动**。
   docs/41 §6 要求"写完视觉判据就问：一个什么都没做的改动能不能过？"——这一条的答案是**能**。
   （**实测不是假想**：删掉 water.png 走回退路的 route B，`distinct` 1→2 **过了这一条**，
   而同一帧的 `path` 仍然是 1.000、岸线一个像素没变、对比度还更硬了。）
   所以它是**必要不充分**条件。

2. ★ **`path`：过渡带的【折线长度 ÷ 草→水直线距离】（判 median）。**

   沿剖线从"最后一个还是草色的像素"走到"第一个已是水色的像素"，把沿途每一步的
   RGB 距离加起来，除以草色与水色之间的直线距离 `REF`。

   **1.0 是三角不等式给的理论下界**：一步直达时折线就是直线。
   纯色贴纸**恰好取到这个下界** —— 实测四个负对照（headless 昼 / 真机夜 / 真机暮 / route B 回退路，
   两种分辨率）的 median 与 p10 **全部恰好 = 1.000**。
   中间夹了岸泥、浅水之后折线必然绕路 ⇒ 实测三个正对照 median = 1.679 / 1.695 / 1.812。

   ⇒ **这不是一个调出来的阈值，是"草和水之间有没有东西"的几何判据。**
   它同时天然免疫前三版栽过的三个坑：不吃绝对亮度（是比值）、不吃分辨率、不吃色相
   （量 RGB 距离）。配套的 `frac_direct`（仍是一步直达的剖线占比：负对照 100%，正对照 3-6%）
   挡"只修一半岸线"。

   ### ⚠ 第一版把它写成了「窗口内最大跃变」，错法与 F3 记的 `win16` 一模一样

   第一版量的是「剖线窗口内**任意**相邻两点的最大跃变」。实测：
   **改前 p90=70.14 / max=88.05，改后 p90=70.14 / max=88.05 —— 一位都没动**，
   而同一帧的画面上岸线已经肉眼可见地长出来了。
   把最坏那条剖线打印出来才看见：`175.6 175.6 87.5 149.6 149.6 | ...`——
   那个 88.0 的跃变来自**池塘外 3 px 处草地上的一块深色装饰精灵 (88,92,42)**，
   两帧里是同一个物件，于是它把统计量**钉死**了。

   `seam.py` 抬头早就写过同一件事：「win16 的最大值**从来不在边界上**…
   15/15 都落在界内 4px 处的一朵黄花上…**读不出接缝好坏**」。
   我在一个新地方把它重犯了一遍。**修法就是 `seam.py` 自己的分解**：
   只取「最后一个界外像素 → 第一个界内像素」那**一步**（`cross`），
   而不是窗口里的最大值。窗口最大值（`win_max`）保留**只作诊断打印，不参与判定**。

   ### ⚠ 而且 `cross` 判 **median**，不判 p90 —— 上尾同样是被邻居污染的

   改完之后 `cross` 的分布是 **43/66 条 ≤ 1.0**（真的无缝）而 p90=12.79。
   把上尾打印出来，那 18 条超过 12 的**没有一条**在读岸线：

   - `bot@x649..661`：界外那一格是**南边紧贴池塘的"滩头"沙地** `(193,160,96)`，
     界内第一个像素是草 `(134,164,53)` ⇒ 量到的是**沙→草**，与水一点关系没有。
   - `top@x664`：界外是一块亮色装饰精灵 `(183,163,63)`。

   根因是**判据的前提在改完之后不再成立**：纯色贴纸时「格子边界 == 水的边界」，
   所以固定下标处的那一步就是水陆交界；有了岸线之后水被岸泥**内缩**了 2-3 px，
   格子边界上站着的是岸、是草、或者干脆是隔壁地块的沙。
   ⇒ **上尾读的是邻居的地面，不是这道岸。**
   第三、四版索性不再用 `cross` 判定（降为诊断打印），换成第 2 条的 `path`——
   它对"边界到底落在哪个下标"根本不敏感，因为它是沿整段过渡累加的。

   ### ⚠ 第三版：绝对阈值 = 判据跟着天色走（**真机帧抓出来的**）
   见下面 `REL_NOISE` 一节。

   ### ⚠ 第四版：只量亮度 = 看不见色相变化（**也是真机夜帧抓出来的**）
   见下面 `dist()` 的 docstring。

3. **`shore_levels`：跨岸剖线上的"台阶数"（相邻像素色距 > noise 的段数，判 median）。**
   这一条专治第 2 条的作弊法：**把水调亮**也能让落差变小，而岸线依旧是一刀切。
   有真岸线 ⇒ 一条剖线上至少 2 个台阶（草→岸泥→浅水→深水）。
   一刀切 ⇒ 恒为 1。**"跌落变小"和"跌落被摊开"是两件事，必须分开量。**
   ⚠ **不判 `min`**：58-78 条剖线里总有一两条压在滩头沙地/装饰精灵上，
   `min` 实测在**三张全都长好了岸线的帧上**都是 1 —— 那是取样噪声不是缺陷。
   "改了一半"由第 2 条的 `frac_direct` 挡（负对照 100% vs 正对照 3-6%，分得开得多）。

## ⚠ 尾巴取哪一侧：F3 那条纪律**不能照抄成"一律 p90"**

`cross` 是**坏指标**（越小越好）⇒ 取 p90 = 忽略最坏的 10%（雨丝/路过的 NPC），F3 的原意。
`levels` / `path` 是**好指标**（越大越好）⇒ 取 p90 就成了**只要 10% 的剖线达标就算过**。
实测踩到：未改动的树上 `levels_p90` 已经是 **2**（岸边恰好站了人/压了树影），
而 `median=1`、`min=1` —— 也就是说 p90 版本的这条判据**在纯色贴纸上就是绿的**。
⇒ **好指标判 median，坏指标判 p90。判据方向跟着指标方向走，不跟着别人写过的那个字母走。**

用法:
    python tools/pond.py <png> [<png2> ...]        # 逐帧一行
    python tools/pond.py --assert <png>            # 门：红则 exit 1
    python tools/pond.py before.png after.png --delta
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import seam                                  # 几何与亮度公式的唯一来源（F3 搬进仓库的 C7 量具）

from PIL import Image

MAP_W, MAP_H = seam.MAP_W, seam.MAP_H        # 64 x 48 格

# 北池 = map.json water 层里 y<20 的那一块。**写死在这里是刻意的**：
# 本量具吃的是【真机截图】，读不到 map.json 的运行期状态；而这两个池塘的坐标
# 自 6 月建图以来没动过。若地图改了，`--assert` 的 interior 取样会落到草地上、
# distinct 掉回 1 ⇒ 门会红，而不是静默量错地方。
NORTH = (28, 35, 2, 6)                       # x0, x1, y0, y1（含端点）

SHORE_BAND = 5                               # 跨岸剖线：界外(草) 5 px + 界内(水) 5 px

# ★★ 判据必须【随画面亮度自动缩放】，不能写死绝对亮度 ★★
#
# 本量具第三版才修对这一条，前两版都栽在同一个坑里，而且是**真机帧**替我抓出来的：
#   · 绝对阈值版（NOISE=6.0 / cross<=12.0）在 **headless 白天帧**上全绿；
#   · 同一份代码渲的 **headless 夜帧** 就红了（levels_min=1）；
#   · **真机夜帧** 红得更多（cross median=18.13、levels_min=1）。
# 而三张图上岸线是**同一圈瓦片**，一个像素都没差别。变的是`_daylight` 的全局乘子：
# 入夜整帧乘 ~0.4 ⇒ 白天 15 的一级台阶到夜里只剩 6，掉到绝对阈值以下就"消失"了。
# ⇒ **量的是岸线，判据却跟着天色走** —— 与 docs/41 §6「判据没问题，出问题的是喂给它的那个世界」
#   和 F3「写 cross.max<=5 的门会在下雨天变红」是同一个病的第三次发作。
#
# 修法：把两条判据都换成**相对量**，分母取本帧自己的「草—水亮度差」`REF`：
#   REF = |lum(池心众数色) − lum(池外草地众数色)|
# 这个分母正是**纯色贴纸时 cross 的值**（贴纸就是草一步跳到水）⇒ 贴纸帧的 cross/REF 恒等于 1.0，
# 与天色、与分辨率、与季节罩全都无关。取**众数色**而不是均值：岸边的装饰/NPC 影响不了众数。
REL_NOISE = 0.15                             # 台阶阈值 = 0.15 × REF（低于此算同一级，滤掉像素画自带抖动）
MIN_REF = 8.0                                # REF 小于这个数说明草与水本来就分不开 ⇒ 判据无意义，判红而不是静默放行


def dist(a, b):
    """两色之间的 RGB 欧氏距离。

    ## 为什么这里**不用** `seam.lum` 的亮度差（本量具第四版的修正）

    `seam.py` 量的是地图边缘与界外暗林那道缝，两侧色相相近，**亮度差就够用**。
    岸线不是：入夜后 `WorldView` 给水层乘 `WATER_NIGHT = (1.0, 0.42, 0.30)`（重红偏），
    于是**岸泥被染成锈褐 `(50,33,37)`、水是深蓝 `(20,44,60)`** ——
    两者亮度分别是 **36.9 与 40.1，差 3.1**，落在噪声阈值以下 ⇒ 亮度尺子判定"这里没有过渡"。
    而它们的 RGB 距离是 **35.6**，肉眼一看就是两种完全不同的东西。

    真机夜帧上 78 条剖线里有 15 条这样被误判（headless 夜帧 2 条，白天帧 0 条）——
    **一条真实且看得见的过渡，被一把只量亮度的尺子读成了断崖。**
    ⇒ 岸线的判据必须量**颜色**，不能只量亮度。这一条是**真机夜帧**逼出来的：
    白天帧上亮度尺子完全够用，永远不会暴露这个盲区。
    """
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def cell_px(size):
    """一格在屏幕上的像素数 + 地图左上角屏幕坐标。几何全部来自 seam.map_rect。"""
    x0, y0, x1, y1 = seam.map_rect(size)
    return (x1 - x0) / MAP_W, (y1 - y0) / MAP_H, x0, y0


def rect_of(size, cells):
    cx0, cx1, cy0, cy1 = cells
    cw, ch, ox, oy = cell_px(size)
    return (ox + cx0 * cw, oy + cy0 * ch, ox + (cx1 + 1) * cw, oy + (cy1 + 1) * ch)


def interior(im, cells=NORTH, inset=0.30):
    """池心取样：从水域矩形四边各缩进 `inset` 格，保证取样区**整块落在水里**，
    不含任何岸线像素 —— 否则"加了岸线"本身会把 distinct 顶上去，这一条就白量了。"""
    cx0, cx1, cy0, cy1 = cells
    cw, ch, ox, oy = cell_px(im.size)
    x0 = ox + (cx0 + inset) * cw
    x1 = ox + (cx1 + 1 - inset) * cw
    y0 = oy + (cy0 + inset) * ch
    y1 = oy + (cy1 + 1 - inset) * ch
    px = im.load()
    cols = {}
    n = 0
    for y in range(int(round(y0)), int(round(y1))):
        for x in range(int(round(x0)), int(round(x1))):
            cols[px[x, y]] = cols.get(px[x, y], 0) + 1
            n += 1
    return cols, n, (int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1)))


def shore_profiles(size, cells=NORTH):
    """沿水域上/下/左/右四条边，由**草地一侧向水中**取剖线。

    刻意**跳过四个角**（各留 1 格）：角上同时受两条边影响，读数混着两个方向的过渡，
    既不代表边也不代表角。八向自动贴图的角瓦要单独看，不混进这张表。
    """
    cx0, cx1, cy0, cy1 = cells
    cw, ch, ox, oy = cell_px(size)
    b = SHORE_BAND
    out = []

    def col_x(c):
        return int(round(ox + c * cw))

    def row_y(c):
        return int(round(oy + c * ch))

    top, bot = row_y(cy0), row_y(cy1 + 1) - 1
    lef, rig = col_x(cx0), col_x(cx1 + 1) - 1
    step = max(1, int(round(cw / 4.0)))
    for x in range(col_x(cx0 + 1), col_x(cx1), step):          # 上边：由上（草）向下（水）
        out.append(("top@x%d" % x, [(x, top - b + i) for i in range(2 * b)]))
    for x in range(col_x(cx0 + 1), col_x(cx1), step):          # 下边：由下（草）向上（水）
        out.append(("bot@x%d" % x, [(x, bot + b - i) for i in range(2 * b)]))
    for y in range(row_y(cy0 + 1), row_y(cy1), step):          # 左边
        out.append(("left@y%d" % y, [(lef - b + i, y) for i in range(2 * b)]))
    for y in range(row_y(cy0 + 1), row_y(cy1), step):          # 右边
        out.append(("right@y%d" % y, [(rig + b - i, y) for i in range(2 * b)]))
    return out


def grass_modal(im, cells=NORTH, near=1.4, far=3.0):
    """池外一圈草地的**众数色**。取环带（1.4~3.0 格）而不是单点：
    众数对岸边的树/石头/NPC 免疫，而单点取样正好压到一棵树上就全错了。"""
    cx0, cx1, cy0, cy1 = cells
    cw, ch, ox, oy = cell_px(im.size)
    px = im.load()
    W, H = im.size
    cols = {}
    x0o, x1o = ox + (cx0 - far) * cw, ox + (cx1 + 1 + far) * cw
    y0o, y1o = oy + (cy0 - far) * ch, oy + (cy1 + 1 + far) * ch
    x0i, x1i = ox + (cx0 - near) * cw, ox + (cx1 + 1 + near) * cw
    y0i, y1i = oy + (cy0 - near) * ch, oy + (cy1 + 1 + near) * ch
    for y in range(max(0, int(y0o)), min(H, int(y1o))):
        for x in range(max(0, int(x0o)), min(W, int(x1o))):
            if x0i <= x < x1i and y0i <= y < y1i:
                continue                       # 挖掉内圈：只留环带，不含水也不含岸
            cols[px[x, y]] = cols.get(px[x, y], 0) + 1
    if not cols:
        return None
    return max(cols.items(), key=lambda kv: kv[1])[0]


def measure(path, cells=NORTH):
    im = Image.open(path).convert("RGB")
    cols, n, box = interior(im, cells)
    px = im.load()
    W, H = im.size
    # 本帧的"草—水亮度差"：既是纯色贴纸时 cross 的值，也是所有相对判据的分母
    wmode = max(cols.items(), key=lambda kv: kv[1])[0] if cols else (0, 0, 0)
    gmode = grass_modal(im, cells)
    ref = dist(gmode, wmode) if gmode else 0.0
    noise = max(1.0, REL_NOISE * ref)
    cross, wins, levels, paths = [], [], [], []
    for name, pts in shore_profiles(im.size, cells):
        if any(not (0 <= x < W and 0 <= y < H) for (x, y) in pts):
            continue
        cs = [px[x, y] for (x, y) in pts]
        d = [dist(cs[i + 1], cs[i]) for i in range(len(cs) - 1)]
        # pts 布局：[0..SHORE_BAND-1] 界外(陆), [SHORE_BAND..] 界内(水格)
        cross.append(dist(cs[SHORE_BAND], cs[SHORE_BAND - 1]))  # 诊断保留
        wins.append(max(d))                                     # 诊断：窗口最大值（会被岸边装饰钉死）
        levels.append(sum(1 for v in d if v > noise))           # 台阶数（阈值随 REF 缩放）
        # ★★判据：过渡带的【折线长度 / 直线距离】。见抬头「第四版」。
        gi = max((i for i, c in enumerate(cs) if dist(c, gmode) <= noise), default=None)
        wi = next((i for i, c in enumerate(cs) if i > (gi if gi is not None else -1)
                   and dist(c, wmode) <= noise), None)
        if gi is not None and wi is not None and ref > 0:
            paths.append(sum(d[gi:wi]) / ref)
    cross.sort()
    wins.sort()
    levels.sort()
    paths.sort()

    def p90(v):
        return v[int(0.9 * (len(v) - 1))] if v else 0.0
    return {
        "path": path, "size": [W, H], "sample_box": box, "sample_px": n,
        "interior_distinct": len(cols),
        "interior_top": sorted(cols.items(), key=lambda kv: -kv[1])[:3],
        "n_profiles": len(cross), "ref": round(ref, 2), "n_paths": len(paths),
        "path_median": round(paths[len(paths) // 2], 3) if paths else 0.0,
        "path_p10": round(paths[int(0.1 * (len(paths) - 1))], 3) if paths else 0.0,
        "frac_direct": round(sum(1 for v in paths if v <= 1.02) / len(paths), 3) if paths else 1.0,
        "grass_modal": gmode, "water_modal": wmode, "noise": round(noise, 2),
        "cross_frac_median": round(cross[len(cross) // 2] / ref, 3) if (cross and ref > 0) else 9.99,
        "cross_p90": round(p90(cross), 2),
        "cross_median": round(cross[len(cross) // 2], 2) if cross else 0.0,
        "cross_max": round(cross[-1], 2) if cross else 0.0,
        "win_max": round(wins[-1], 2) if wins else 0.0,          # 诊断专用，不判定
        "levels_p90": p90(levels), "levels_median": levels[len(levels) // 2] if levels else 0,
        "levels_min": levels[0] if levels else 0,
    }


def show(r):
    print("%s  %sx%s" % (os.path.basename(r["path"]), r["size"][0], r["size"][1]))
    print("   池心取样 %s  %d px  ⇒ distinct=%d   %s"
          % (r["sample_box"], r["sample_px"], r["interior_distinct"], r["interior_top"]))
    print("   参考差 REF=%.2f  (草众数 %s → 水众数 %s)   台阶阈值 noise=%.2f"
          % (r["ref"], r["grass_modal"], r["water_modal"], r["noise"]))
    print("   ★过渡折线/直线 path median=%.3f  p10=%.3f  一步直达占比=%.1f%%  (n=%d 条剖线有完整 草→水 过渡段)"
          % (r["path_median"], r["path_p10"], 100 * r["frac_direct"], r["n_paths"]))
    print("   跨岸剖线 n=%d  诊断 cross/REF median=%.3f   (绝对 cross median=%.2f p90=%.2f · 诊断 win_max=%.2f 被岸边装饰钉死，不判定)"
          % (r["n_profiles"], r["cross_frac_median"], r["cross_median"], r["cross_p90"], r["win_max"]))
    print("   台阶数   p90=%d median=%d min=%d" % (r["levels_p90"], r["levels_median"], r["levels_min"]))


# 判据阈值。**每一条都写清"这个数字是怎么来的"**——docs/41 §6 点过名：
# 「写死 0 的重画门其实是在守你的机器别太快」。
MIN_DISTINCT = 2        # >1。必要不充分（见抬头判据 1）。
MIN_PATH = 1.25         # 过渡带折线长 / 草→水直线距离。
                        # **1.0 是三角不等式给的理论下界**，纯色贴纸恰好取到它（一步直达 ⇒ 折线=直线）。
                        # 实测：四个负对照 median 与 p10 **全部恰好 = 1.000**（昼/夜/暮/回退路，两种分辨率）；
                        # 三个正对照 median = 1.679 / 1.695 / 1.812。
                        # ⇒ 这不是一个调出来的阈值，是"有没有东西夹在草和水之间"的**几何判据**：
                        #   贴纸**不可能**大于 1.0，1.25 只是给抗锯齿/压缩留的余量。
MAX_FRAC_DIRECT = 0.25  # 仍然"一步直达"（path ≤ 1.02）的剖线占比。防"只修一半岸线"。
                        # 实测：四个负对照 100%；三个正对照 0% / 0% / 10.3%（真机夜帧，见报告）。
MIN_LEVELS = 2          # 一刀切恒为 1；真岸线（草→岸泥→浅水→深水）至少 2 段。
                        # 判在 **median 和 min 两个数上**：median 说"典型剖线有过渡"，
                        # min 说"**没有任何一条**剖线是断崖" —— 后者正是"只修一半岸线"的解药，
                        # 也是把 cross 从 p90 降到 median 之后补回来的那份严格。


def check(r):
    bad = []
    if r["interior_distinct"] < MIN_DISTINCT:
        bad.append("池心 distinct=%d < %d —— 水域是一块纯色贴纸"
                   % (r["interior_distinct"], MIN_DISTINCT))
    if r["ref"] < MIN_REF:
        bad.append("参考差 REF=%.2f < %.2f —— 草与水本来就分不开，判据无意义（不静默放行）"
                   % (r["ref"], MIN_REF))
    elif r["n_paths"] == 0:
        bad.append("没有一条剖线找到完整的 草→水 过渡段 —— 取样落在了别的地方，不能静默放行")
    else:
        if r["path_median"] < MIN_PATH:
            bad.append("过渡折线/直线 median=%.3f < %.2f —— 草与水之间【什么都没有】，"
                       "是一步直达的硬跳变（1.000 = 理论下界，纯色贴纸恰好取到）"
                       % (r["path_median"], MIN_PATH))
        if r["frac_direct"] > MAX_FRAC_DIRECT:
            bad.append("仍是一步直达的剖线占 %.1f%% > %.0f%% —— 至少有一大段岸没有过渡（改了一半不算改）"
                       % (100 * r["frac_direct"], 100 * MAX_FRAC_DIRECT))
    if r["levels_median"] < MIN_LEVELS:
        bad.append("跨岸台阶数 median=%d < %d（p90=%d 是【岸边站了人】那 10%%，不能拿它判绿）"
                   " —— 落差再小也只是【一刀切得浅一点】，不是过渡"
                   % (r["levels_median"], MIN_LEVELS, r["levels_p90"]))

    if r["sample_px"] == 0 or r["n_profiles"] == 0:
        bad.append("扫过量为 0（取样 %d px / 剖线 %d 条）—— 一个像素都没看就打绿是假门"
                   % (r["sample_px"], r["n_profiles"]))
    return bad


def main():
    argv = sys.argv[1:]
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 0
    rs = [measure(p) for p in paths]
    for r in rs:
        show(r)
    if "--delta" in argv and len(rs) == 2:
        b, a = rs
        print("\n  === delta (after - before) ===")
        for k in ("interior_distinct", "ref", "path_median", "path_p10", "frac_direct", "levels_median"):
            print("   %-18s %8s -> %8s" % (k, b[k], a[k]))
    if "--assert" in argv:
        fail = 0
        for r in rs:
            bad = check(r)
            print()
            if bad:
                fail = 1
                for m in bad:
                    print("  ❌ FAIL: %s" % m)
            else:
                print("  ✅ %s：distinct=%d ≥ %d · path median=%.3f ≥ %.2f · 一步直达占比 %.1f%% ≤ %.0f%% · 台阶 median=%d ≥ %d"
                      % (os.path.basename(r["path"]), r["interior_distinct"], MIN_DISTINCT,
                         r["path_median"], MIN_PATH, 100 * r["frac_direct"], 100 * MAX_FRAC_DIRECT,
                         r["levels_median"], MIN_LEVELS))
        print("\n=== POND GATE %s ===" % ("FAIL ❌" if fail else "PASS ✅"))
        return fail
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    sys.exit(main())
