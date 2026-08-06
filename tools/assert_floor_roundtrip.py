#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assert_floor_roundtrip.py — 全楼层往返门（AM3 / 编号135，docs/126 §四 把 1F 往返门扩成多楼层）。

守的性质，一句话：**观察者能走完整旅程 —— town→cafe/1f→上楼2f→下楼1f→出门回 town，
逐段落在对的 Floor，2F 那一跳真的换了平面，且走完一圈回到 town/回到 1F 的取景逐像素复位。**

由来（docs/126 §一.3）：现役 `assert_space_roundtrip.py` 只走 `town↔cafe/1f`——**楼梯往返（1f↔2f）无门、
cafe 2F 从没被【往返路径】看过**。本门复用 `game/bench/SpaceShot.gd` 的 `--rt-journey full`（出货路径
`tapped`→`Main._portal_click` 逐段穿门/上下楼），采集 5 帧、逐段断言，并且**零金标**
（Probe 的 active_space/active_floor 是 view-only、不进 digest——AG3 的 R1，`probe_digest_test.sh` 机检）。

── 5 帧（SpaceShot --rt-journey full 拍，本脚本宿主侧判）──────────────────────────────
  rt_town_before.png   出发：town/outdoor
  rt_cafe_1f.png       进店：cafe/1f（街门 portal）
  rt_cafe_2f.png       上楼：cafe/2f（楼梯 portal）
  rt_cafe_1f_back.png  下楼：cafe/1f（楼梯 portal，回到 1f）
  rt_town_after.png    出门：town/outdoor（街门 portal，go_home 复位取景）
  rt_meta.json         每帧的 {space,floor,map_rect_design,cam,zoom,void_draws} + journey/cam_same

── 判据（阈值全部在【未改动真帧】上量出来，两侧留 ~2-3× 余量；docs/122 §四手法）──────────
  L 逐段楼层/空间对（读 meta，Requirement 1）：
      town_before=town · cafe_1f=cafe/1f · cafe_2f=cafe/2f · cafe_1f_back=cafe/1f · town_after=town。
      **这是"某一跳目标 Floor 改错 ⇒ 门必红"的机器化**（与 SpaceShot 侧的逐段断言互为双证——
      采集侧 rc≠0 会先红在 [SPACESHOT] 行，本臂是宿主侧的第二道保险）。
  A1 回程取景一致（Requirement 2）：`town_after` ≡ `town_before`，在地图矩形逐像素相同
      + 界外带仍有纹理（复用现役 MIN_DISTINCT/MIN_STDEV 下界，挡"整层不画也能空过"）；且 meta.cam_same 必真。
  A2 楼梯往返 1F 复位（Requirement 2 的楼梯腿）：`cafe_1f_back` ≡ `cafe_1f` 逐像素相同
      ——下楼回到的那一层，取景与内容都必须原样（同一 Space 同一 Floor、相机由 _portal_click 同式复位）。
  B 2F 与 1F 可分（判别力，Requirement 3）：frac_diff(cafe_2f, cafe_1f) ≥ SEP_MIN（内格区域）。
      **挡"楼梯往返其实没换层 / 两层画成一样"的空过**；负对照 --draw-skip interior_furniture 把两层画空 ⇒ 这条红。
  C 真的进过店（配对判别力）：frac_diff(cafe_1f, town_before) ≥ MIN_INTERIOR_DIFF（全帧）。
      没有它，"采集脚本压根没进店"与"进出一切正常"在 A/L 上读起来一样（同 assert_space_roundtrip 的 C）。

── 为什么阈值是这几个数（都在**未改动树的真帧**上量的，docker gamecraft-runner:4.6.2 软渲 pin）─────
  见文件末 _MEASURED（`--measure` 复现）。A1/A2 是**逐字节相等**（mesa pin ⇒ 同内容同相机 ⇒ 0 差）。

── 本门【不】守什么（docs/41 §2.5）─────────────────────────────────────────────────
· 颜色对不对一概不管（关系判据，色值真源留在 WorldView.gd 不抄进判据）。· 只 cafe 一栋有 2f，只测它。
· 只 seed3 一个 warmup-tick、晴天、软渲 docker 非真机。· 只看地图矩形/内格区域取样，不逐件家具。
· **不守 Probe 换层是否 view-only**——那是 R1 的 `probe_digest_test.sh` 的活（本门 view-only、零金标）。

用法: python assert_floor_roundtrip.py <帧目录> [--measure]
退出码 0=PASS 1=FAIL 2=用法/文件错
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# 复用现役解码器 + 几何 + 界外带下界常数（红线#5 复用优先——两份 PNG 解码器/换算必漂）。
from assert_space_roundtrip import (          # noqa: E402
    load, regions, count_diff, band_stats, MIN_DISTINCT, MIN_STDEV, MIN_INTERIOR_DIFF,
)

# ── 判据常数（来源见抬头 + 文件末实测）────────────────────────────────────────────
# SEP_MIN 取【绿帧 0.1767 与 负对照 0.0276 的几何均值】0.070 —— 两侧各 ~2.5× 余量，不贴任一侧
# （贴绿侧 0.17 ⇒ 下次 2F 美术微调假红；贴红侧 0.03 ⇒ 轻一点的"两层画太像"漏过）。docs/122 §四手法。
SEP_MIN = 0.07          # B: 2F 与 1F 内格区域变化占比下界

FRAMES = ("town_before", "cafe_1f", "cafe_2f", "cafe_1f_back", "town_after")
# 每帧期望的 (space, floor)；floor=None 表示不校（town 的 floor 恒 outdoor，不是本门的重点）
EXPECT = {
    "town_before":  ("town", None),
    "cafe_1f":      ("cafe", "1f"),
    "cafe_2f":      ("cafe", "2f"),
    "cafe_1f_back": ("cafe", "1f"),
    "town_after":   ("town", None),
}


def frac_over(rows1, rows2, bpp, rect):
    """rect 内 max 通道差≠0 的像素占比（mesa pin ⇒ 判别用；同内容=0，异内容≫阈值）。"""
    n, _first, _dmax = count_diff(rows1, rows2, bpp, rect)
    a, b, c, d = rect
    area = max(1, (c - a) * (d - b))
    return n / float(area), n, area


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # 同 assert_daynight：Windows GBK 会把箭头炸成异常
    except Exception:
        pass
    measure = "--measure" in sys.argv[1:]
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    d = args[0]

    try:
        meta = json.load(open(os.path.join(d, "rt_meta.json"), encoding="utf-8"))
    except Exception as e:
        print("  FAIL 读不到 rt_meta.json（采集那一步没跑完？）：%s" % e)
        return 2
    if str(meta.get("journey")) != "full":
        print("  FAIL rt_meta.journey=%s（本门要 full 旅程；simple 帧请交给 assert_space_roundtrip.py）"
              % meta.get("journey"))
        return 2

    paths = {k: os.path.join(d, "rt_%s.png" % k) for k in FRAMES}
    for k, p in paths.items():
        if not os.path.exists(p):
            print("  FAIL 缺帧 %s（journey full 应有 5 帧）" % p)
            return 2

    img = {k: load(paths[k]) for k in FRAMES}   # (w,h,bpp,rows)
    w, h, bpp, _ = img["town_before"]
    for k in FRAMES:
        if (img[k][0], img[k][1]) != (w, h):
            # docs/41 §6 盲区③：画幅问题只体现在 im.size 上，画面里一条黑边都没有 ⇒ 尺寸必须显式比。
            print("  FAIL 帧尺寸不一致：town_before=%dx%d %s=%dx%d" % (w, h, k, img[k][0], img[k][1]))
            return 1
    rows = {k: img[k][3] for k in FRAMES}

    print("  帧 %dx%d  journey=%s mode=%s tick=%s cam_same=%s"
          % (w, h, meta.get("journey"), meta.get("mode"), meta.get("tick"), meta.get("cam_same")))
    for k in FRAMES:
        fm = meta.get(k, {})
        print("    %-13s space=%-6s floor=%-8s void_draws=%s"
              % (k, fm.get("space"), fm.get("floor"), fm.get("void_draws")))

    # 几何：town 用 town_after 的矩形（go_home 复位后的取景）；内格用 cafe_1f 的矩形（cafe_1f/2f/back 同一 Space 同相机 ⇒ 同矩形）
    reg_town = regions(meta["town_after"]["map_rect_design"], w, h)
    reg_cafe = regions(meta["cafe_1f"]["map_rect_design"], w, h)

    if measure:
        b_frac, bn, ba = frac_over(rows["cafe_2f"], rows["cafe_1f"], bpp, reg_cafe["map"])
        c_frac, cn, ca = frac_over(rows["cafe_1f"], rows["town_before"], bpp, (0, 0, w, h))
        a1n, _f, _m = count_diff(rows["town_after"], rows["town_before"], bpp, reg_town["map"])
        a2n, _f2, _m2 = count_diff(rows["cafe_1f_back"], rows["cafe_1f"], bpp, reg_cafe["map"])
        print("  [MEASURE] A1 town_after↔before map 变化像素=%d（应 0）" % a1n)
        print("  [MEASURE] A2 cafe_1f_back↔cafe_1f map 变化像素=%d（应 0）" % a2n)
        print("  [MEASURE] B  2F↔1F 内格 frac=%.4f (%d/%d)" % (b_frac, bn, ba))
        print("  [MEASURE] C  cafe_1f↔town_before 全帧 frac=%.4f (%d/%d)" % (c_frac, cn, ca))
        return 0

    fails = 0

    # ── L 逐段楼层/空间对（Requirement 1）────────────────────────────────────────
    l_bad = 0
    for k in FRAMES:
        want_sp, want_fl = EXPECT[k]
        fm = meta.get(k, {})
        got_sp, got_fl = str(fm.get("space")), str(fm.get("floor"))
        ok = (got_sp == want_sp) and (want_fl is None or got_fl == want_fl)
        if not ok:
            l_bad += 1
        print("  %s L[%-13s] space=%s(应%s) floor=%s(应%s)"
              % ("PASS" if ok else "FAIL", k, got_sp, want_sp, got_fl, want_fl if want_fl else "*"))
    if l_bad:
        print("       ↑ 有一段没落在对的 Space/Floor —— 楼梯/街门 portal 的目标层不对，或采集没走完整旅程"
              "（采集侧 [SPACESHOT] 行会先报同一件事）。")
        fails += 1
    if not meta.get("cam_same", False):
        print("  FAIL A1 前提：出门回 town 后取景与出发时不同 —— 回程取景不一致（见 [SPACESHOT] 行）")
        fails += 1

    # ── A1 回程取景一致：town_after ≡ town_before（Requirement 2）──────────────────
    a1_bad = 0
    for name in ("map", "band_top", "band_bot"):
        n, first, dmax = count_diff(rows["town_after"], rows["town_before"], bpp, reg_town[name])
        area = (reg_town[name][2] - reg_town[name][0]) * (reg_town[name][3] - reg_town[name][1])
        if n:
            a1_bad += n
        print("  %s A1[%-9s] 变化像素=%d/%d (%.3f%%) 首例=%s 最大通道差=%d"
              % ("PASS" if n == 0 else "FAIL", name, n, area, 100.0 * n / max(1, area), first, dmax))
    if a1_bad:
        print("       ↑ 走完一圈回 town 画面变了 —— 回程取景没复位 / 界外层缓存键停在旧值（docs/46 §二·九-①）。")
        fails += 1
    # 界外带活着（下界，挡 A1 的空过）
    for name in ("band_top", "band_bot"):
        nc, sd, n = band_stats(rows["town_after"], bpp, reg_town[name])
        ok = nc >= MIN_DISTINCT and sd >= MIN_STDEV
        if not ok:
            fails += 1
        print("  %s A1B[%-9s] 颜色数=%d(≥%d) 标准差=%.2f(≥%.1f)"
              % ("PASS" if ok else "FAIL", name, nc, MIN_DISTINCT, sd, MIN_STDEV))

    # ── A2 楼梯往返 1F 复位：cafe_1f_back ≡ cafe_1f（Requirement 2 楼梯腿）──────────
    n, first, dmax = count_diff(rows["cafe_1f_back"], rows["cafe_1f"], bpp, reg_cafe["map"])
    area = (reg_cafe["map"][2] - reg_cafe["map"][0]) * (reg_cafe["map"][3] - reg_cafe["map"][1])
    ok = (n == 0)
    if not ok:
        fails += 1
    print("  %s A2[cafe_1f 往返] 下楼回到的 1F 与进店 1F 变化像素=%d/%d (%.3f%%) 首例=%s 最大通道差=%d"
          % ("PASS" if ok else "FAIL", n, area, 100.0 * n / max(1, area), first, dmax))
    if not ok:
        print("       ↑ 楼梯往返之后 1F 帧变了 —— 下楼取景没复位，或 1F 内容被 2F 污染。")

    # ── B 2F 与 1F 可分（Requirement 3）──────────────────────────────────────────
    b_frac, bn, ba = frac_over(rows["cafe_2f"], rows["cafe_1f"], bpp, reg_cafe["map"])
    ok = b_frac >= SEP_MIN
    if not ok:
        fails += 1
    print("  %s B[2F↔1F] 内格变化占比=%.4f (≥%.2f) (%d/%d) —— 2F 那一跳真的换了平面"
          % ("PASS" if ok else "FAIL", b_frac, SEP_MIN, bn, ba))
    if not ok:
        print("       ↑ 2F 与 1F 画得太像 ⇒ 楼梯往返没换层 / 两层画成一样（--draw-skip interior_furniture 会命中这条）。")

    # ── C 真的进过店（配对判别力）────────────────────────────────────────────────
    c_frac, cn, ca = frac_over(rows["cafe_1f"], rows["town_before"], bpp, (0, 0, w, h))
    ok = c_frac >= MIN_INTERIOR_DIFF
    if not ok:
        fails += 1
    print("  %s C[cafe_1f↔town] 全帧变化占比=%.4f (≥%.2f) —— 证明这一趟真的进过 cafe"
          % ("PASS" if ok else "FAIL", c_frac, MIN_INTERIOR_DIFF, ))
    if not ok:
        print("       ↑ 室内帧与镇上帧几乎一样 ⇒ 要么没切过空间，要么切了世界层没重画 ⇒ A/L 的绿别信。")

    print("=== FLOOR ROUNDTRIP GATE: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 1 if fails else 0


# ── 实测（docker gamecraft-runner:4.6.2 软渲 pin，seed3 tick600，本仓库当前 cafe 布局；--measure 复现）──
# 2026-08-07 AM3 首次真跑（Mesa 23.2.1 llvmpipe，tol=0 逐字节）：
_MEASURED = {
    "A1_town_after_vs_before_map_diff_px": 0,      # 逐字节相等（go_home 复位取景 + 世界冻结）
    "A2_cafe_1f_back_vs_cafe_1f_map_diff_px": 0,   # 逐字节相等（楼梯往返 1F 复位；同 Space 同 Floor 同相机）
    "B_2f_vs_1f_innerframe_frac": 0.1767,          # 绿帧：2F/1F 内格变化占比
    "B_2f_vs_1f_frac_negctl_skipfurn": 0.0276,     # 负对照 --draw-skip interior_furniture（两层家具都不画）
    "B_2f_vs_1f_frac_negctl_wrongfloor": 0.0000,   # 负对照 楼梯 to.floor=1f（"2F"帧其实是 1F ⇒ 与 1F 全同）
    "C_cafe_1f_vs_town_frac": 0.9832,              # 真进过店
    # 判决：SEP_MIN=0.07 ⇒ 绿 0.1767(2.5×) PASS · 两个负对照 0.0276/0.0000 FAIL（有牙）。
}


if __name__ == "__main__":
    sys.exit(main())
