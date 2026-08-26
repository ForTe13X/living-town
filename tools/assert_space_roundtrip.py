#!/usr/bin/env python3
"""assert_space_roundtrip.py — 「进店 → 出店」之后那几帧的硬断言（docs/47 §五-E6 的 W7）。

背景一句话：2026-07-28 外部对抗评审说「**没有人看过空间切换之后的任何一帧**」，而真 bug 就活在那里
（docs/46 §二·九-①：`_void_key` 停在旧值 ⇒ 出店后界外层永久空白，全在出货路径上）。
`game/bench/SpaceShot.gd` 负责把三帧拍出来，本脚本负责判。

── 三条判据，以及**为什么必须是三条** ──────────────────────────────────────────
  A 往返不变式：`town_after` 与 `town_before` 在【地图矩形】与【界外带】上必须逐像素相同。
      前提由采集侧断言（出店走 `go_home()`，取景逐字节复位）；世界已冻结 ⇒ 应当**什么都不变**。
      ⚠ A **单独看会空过**：一个什么都不画的构建同样满足它（这正是评审给 `--void-gate` 提的那条
        「有上界没有下界」）。所以必须配 B 与 C。
  B 界外带活着（**下界**）：两张 town 帧的界外带都必须仍然**有纹理** —— 颜色数与标准差都要过线。
      这一条是冲着 A 的空过来的：界外层整个不画时 A 依然绿，B 立刻红。
  C 判别力配对（**证明这次真的走了一趟**）：`interior` 必须与 `town_before` 大不相同。
      没有它，"采集脚本压根没进店"与"进店出店一切正常"在 A/B 上读起来一模一样。
      这与 docs/46 D7 那条「`bbox=None` 必须与『draw 数显著下降』成对报告」是同一条纪律。

── 阈值从哪来（**实测，不是拍的**）──────────────────────────────────────────────
  同一台机器、同一个 docker 镜像、seed=3 warmup-tick=600，修复树 vs 回滚树（回滚 = 把
  `WorldView._draw_void_layer` 顶部那句 `_void_key = _void_cache_key()` 拿掉）：

    指标                          修复树            回滚树
    A 变化像素（全帧）            0.81%（只有日志面板）  59.67%（整帧）
    B 上界外带 distinct/stdev     99 / 29.39        **1 / 0.00**（一块纯色）
    B 下界外带 distinct/stdev     1126 / 31.35      **17 / 2.24**
    C interior vs town_before     98.54%            98.54%（这一条两边都该过，它守的是别的东西）

  ⇒ 阈值取 distinct ≥ 32、stdev ≥ 10：两侧各留约 3 倍余量，而**不是**贴着任一侧的实测值。
    贴着修复树取值会让下一次美术改动假红；贴着回滚树取值会让轻一点的回归漏过。

── 为什么不用 Pillow ────────────────────────────────────────────────────────
  同 `assert_daynight.py` 抬头①：CI 的 python 是裸解释器。这里**复用**它的 stdlib PNG 读取器
  （红线#5 复用优先），不再写第二份 —— 两份 PNG 解码器必然漂移。

用法: python assert_space_roundtrip.py <帧目录>
退出码 0=PASS 1=FAIL 2=用法/文件错
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from assert_daynight import _png_rgb_rows          # noqa: E402  （复用，不重写）

# ── 判据常数（来源见抬头的实测表）────────────────────────────────────────────
MIN_DISTINCT = 32       # 界外带里不同颜色数的下界
MIN_STDEV = 10.0        # 界外带亮度标准差的下界
MIN_INTERIOR_DIFF = 0.20  # interior 与 town_before 至少要有 20% 的像素不同

# ── 界外带取样条（设计坐标 1280x768；x 跟着地图矩形走，y 是写死的 HUD 空白带）──
# 为什么 y 是写死的：顶栏底板与底部时间轴面板的几何长在 `Main.gd` 里，python 这边没有真源可读。
# 所以这两条带取的是**实测量出来的 HUD 空白区**：顶栏底板止于 y≈36、底部面板起于 y≈695
# （改前/改后两张 1280x768 帧上逐行核对过）。若日后 HUD 长到这两条带里，A 会带着一个
# **落在带内的 bbox** 变红 —— 那是一条看得懂的失败，不是静默失效。
BAND_TOP_Y = (44, 116)
BAND_BOT_Y = (652, 690)


def load(path):
    w, h, bpp, rows = _png_rgb_rows(path)
    return w, h, bpp, rows


def px(rows, bpp, x, y):
    r = rows[y]
    i = x * bpp
    return (r[i], r[i + 1], r[i + 2])


def regions(meta_rect, w, h):
    """把设计坐标的矩形换算到本 PNG 的像素坐标。`--resolution` 不改相机取景（docs/41 §6 盲区⑥），
    所以缩放只是 PNG 尺寸 / 1280x768 —— 与 assert_daynight.world_mode 同一套换算。"""
    sx, sy = w / 1280.0, h / 768.0
    mx, my, mw, mh = meta_rect
    out = {}
    out["map"] = (int(mx * sx) + 2, int(my * sy) + 2, int((mx + mw) * sx) - 2, int((my + mh) * sy) - 2)
    out["band_top"] = (int(mx * sx), int(BAND_TOP_Y[0] * sy), int((mx + mw) * sx), int(BAND_TOP_Y[1] * sy))
    out["band_bot"] = (int(mx * sx), int(BAND_BOT_Y[0] * sy), int((mx + mw) * sx), int(BAND_BOT_Y[1] * sy))
    for k, (a, b, c, d) in out.items():
        out[k] = (max(0, a), max(0, b), min(w, c), min(h, d))
    return out


def count_diff(rows1, rows2, bpp, rect):
    a, b, c, d = rect
    n = 0
    first = None
    dmax = 0
    for y in range(b, d):
        r1, r2 = rows1[y], rows2[y]
        for x in range(a, c):
            i = x * bpp
            dv = max(abs(r1[i] - r2[i]), abs(r1[i + 1] - r2[i + 1]), abs(r1[i + 2] - r2[i + 2]))
            if dv:
                n += 1
                dmax = max(dmax, dv)
                if first is None:
                    first = (x, y)
    return n, first, dmax


def band_stats(rows, bpp, rect):
    a, b, c, d = rect
    cols = {}
    s = 0.0
    s2 = 0.0
    n = 0
    for y in range(b, d):
        r = rows[y]
        for x in range(a, c):
            i = x * bpp
            t = (r[i], r[i + 1], r[i + 2])
            cols[t] = cols.get(t, 0) + 1
            v = (t[0] + t[1] + t[2]) / 3.0
            s += v
            s2 += v * v
            n += 1
    if n == 0:
        return 0, 0.0, 0
    m = s / n
    return len(cols), math.sqrt(max(0.0, s2 / n - m * m)), n


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # 同 assert_daynight：Windows 控制台 GBK 会把箭头炸成异常
    except Exception:
        pass
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    try:
        meta = json.load(open(os.path.join(d, "rt_meta.json"), encoding="utf-8"))
    except Exception as e:
        print("  FAIL 读不到 rt_meta.json（采集那一步没跑完？）：%s" % e)
        return 2
    paths = {k: os.path.join(d, "rt_%s.png" % k) for k in ("town_before", "interior", "town_after")}
    for k, p in paths.items():
        if not os.path.exists(p):
            print("  FAIL 缺帧 %s" % p)
            return 2

    before = load(paths["town_before"])
    after = load(paths["town_after"])
    inter = load(paths["interior"])
    w, h, bpp, rb = before
    if (after[0], after[1]) != (w, h) or (inter[0], inter[1]) != (w, h):
        # docs/41 §6 盲区③：画幅问题只体现在 im.size 上，画面里一条黑边都没有 ⇒ 尺寸必须显式比。
        print("  FAIL 三帧尺寸不一致：before=%dx%d after=%dx%d interior=%dx%d"
              % (w, h, after[0], after[1], inter[0], inter[1]))
        return 1
    ra = after[3]
    ri = inter[3]
    print("  帧 %dx%d  mode=%s space=%s tick=%s  cam_same=%s  void_draws: before=%s interior=%s after=%s"
          % (w, h, meta.get("mode"), meta.get("space"), meta.get("tick"), meta.get("cam_same"),
             meta["town_before"].get("void_draws"), meta["interior"].get("void_draws"),
             meta["town_after"].get("void_draws")))

    if not meta.get("cam_same", False):
        print("  FAIL 前提：出店后取景与进店前不同 —— A 判据失去意义（见 [SPACESHOT] 行）")
        return 1

    if meta.get("player_journey", False):
        if meta.get("player_entered") is not True or meta.get("player_returned") is not True:
            print("  FAIL 玩家旅程没有证明真实 player agent 已进仓并返回 town/outdoor")
            return 1

    reg = regions(meta["town_after"]["map_rect_design"], w, h)
    fails = 0

    # ── A 往返不变式 ────────────────────────────────────────────────────────
    a_bad = 0
    for name in ("map", "band_top", "band_bot"):
        n, first, dmax = count_diff(rb, ra, bpp, reg[name])
        area = (reg[name][2] - reg[name][0]) * (reg[name][3] - reg[name][1])
        tag = "PASS" if n == 0 else "FAIL"
        if n:
            a_bad += n
        print("  %s A[%-9s] rect=%s 变化像素=%d/%d (%.3f%%) 首例=%s 最大通道差=%d"
              % (tag, name, reg[name], n, area, 100.0 * n / max(1, area), first, dmax))
    if a_bad:
        print("       ↑ 往返之后画面变了 —— 最可能的机理：界外层缓存键停在旧值 ⇒ 出店时不排重画"
              "（docs/46 §二·九-①）。也可能是某个 `*_built` 缓存跟着旧世界（W6）。")
        fails += 1

    # ── B 界外带活着（下界）──────────────────────────────────────────────────
    for label, rows in (("before", rb), ("after", ra)):
        for name in ("band_top", "band_bot"):
            nc, sd, n = band_stats(rows, bpp, reg[name])
            ok = nc >= MIN_DISTINCT and sd >= MIN_STDEV
            if not ok:
                fails += 1
            print("  %s B[%s/%-9s] n=%d 颜色数=%d(≥%d) 标准差=%.2f(≥%.1f)"
                  % ("PASS" if ok else "FAIL", label, name, n, nc, MIN_DISTINCT, sd, MIN_STDEV))
    # ── C 判别力配对 ────────────────────────────────────────────────────────
    n, first, dmax = count_diff(rb, ri, bpp, (0, 0, w, h))
    frac = n / float(w * h)
    ok = frac >= MIN_INTERIOR_DIFF
    if not ok:
        fails += 1
    print("  %s C[interior] 与 town_before 不同的像素=%.2f%% (≥%.0f%%) —— 证明这一趟真的进过 %s"
          % ("PASS" if ok else "FAIL", 100.0 * frac, 100.0 * MIN_INTERIOR_DIFF, meta.get("space")))
    if not ok:
        print("       ↑ 室内帧与镇上帧几乎一样 ⇒ 要么根本没切过空间，要么切了但世界层没重画"
              "（`Main._portal_click` 不排重画，暂停状态下就是这个症状）⇒ A 是空过的，别信它的绿。")

    print("=== ROUNDTRIP GATE: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
