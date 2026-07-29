#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""deprop_characters.py — 角色去道具 pass（Wave E · E3；裁决见 docs/44 §一）。

把 CC0 素材包 `puny-characters` 的 9 张【奇幻职业】精灵表，改绘成"现代日常小镇居民"，
产物写到 `game/assets/art/pro/`——`Art.gd:77` 的三级回退第一级就是这个目录，**零代码改动即生效**。

## 为什么这个做法是安全的（先量后改，不是先改后看）

实测（tools/ 下跑一次本脚本 --probe 可复现）：把 `Character-Base.png` 的 alpha 当掩膜，
它是**其余 9 张表全部 192 帧的严格子集**——9 张表 × 192 帧，`base AND NOT other` 恒等于 **0 像素**。
⇒ 这个素材包是「一具共用身体 + 在身体【之外】叠画的装束」。所以：

  **out.alpha := other.alpha AND base.alpha**

这一步就把尖帽尖顶、羽毛、牛角、盔缨、披肩、以及攻击行里的法杖/弓/剑**整块**去掉，
而**身体剪影按构造逐字节等于 Character-Base**——不可能把轮廓改糊，这是代数保证不是眼力保证。

## 但只做掩膜会毁掉身份（这是本脚本第二、三步存在的唯一理由）

掩膜后逐像素比对（192 帧全表）：

    Soldier-Blue vs Soldier-Red    原 3898 px 不同 → 掩膜后 **91**
    Soldier-Blue vs Soldier-Yellow 原 3880 px 不同 → 掩膜后 **73**
    Warrior-Blue vs Warrior-Red    原 1544 px 不同 → 掩膜后 **423**

三个 Soldier 的全部身份就是那撮盔缨，两个 Warrior 的全部身份就是那对角——都在剪影之外。
只做掩膜 ⇒ **4 个居民（Soldier-Yellow×2 + Blue + Red）变成同一个灰人**。
所以必须把身份**搬到衣服上**：盔甲灰阶 → 逐角色的布料色阶（docs/44 §一 原话「盔甲改围裙/工作服」）。

布料色阶的构造方式：**保留盔甲灰阶的明度剖面，只换色相与饱和度**
⇒ 明暗结构逐档不变（不会压平成一坨），可分度由色相承担。

## 判据（先在【未改动的树】上跑过，故它有判别力，见 docs/41 §6★）

以"衣服像素的面积加权平均色"为身份色，量 CIEDE2000：
  · 未改动的 4 件现成衣服 vs 世界表面（草/石/广场/四类屋顶墙）最小值 = **11.54**（Mage-Red vs res-roof）
  · 本脚本新造的 5 件，同一口径最小值 = **14.83**，即**都在现成资产已达到的水平之上**
  · 9 件衣服两两之间最差 = **15.06**（Archer-Green vs Soldier-Yellow）
`night-multiply` 被排除在世界表面之外：它是乘色叠加层，不是角色会站在其前面的表面，拿它比衣服没有意义。

## 许可（红线 #4）

源是 CC0（`assets/art/library/puny-characters/LICENSE.txt`，作者 Shade）。CC0 允许修改，
产物为自绘衍生，仍是 CC0。**没有任何生成图参与**（docs/43 §二-R2：AI 出图只能当情绪板，绝不进精灵帧）。
本脚本只做两件事：alpha 掩膜 + 查表换色。**不缩放、不插值、不新增任何一个像素位置。**

用法：
    python tools/deprop_characters.py            # 生成 game/assets/art/pro/*.png
    python tools/deprop_characters.py --probe    # 只跑自检断言，不写文件
"""
import os
import sys
import colorsys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "game", "assets", "art", "library",
                   "puny-characters", "Puny-Characters")
DST = os.path.join(ROOT, "game", "assets", "art", "pro")
BASE = "Character-Base"          # 唯一没有职业道具的一张；同时是 WorldView 的空 sprite 回退皮

# ── 1. 前额扣饰（Mage 与 Archer 共用同一组 hex，实测逐值相同）────────────────
# 位置：帧内 y10..y13 正中，约 12 px/帧。它是兜帽上的金属搭扣 + 金边，属奇幻装饰。
# 处置：并进各自长袍自己的色阶 ⇒ 兜帽变成一块干净的布，不是"挖了个洞"。
CIRCLET = {
    "#433416": "dark", "#6e6c68": "base", "#866114": "base",
    "#bfb7a6": "mid",  "#c8c1b3": "mid",
}
ROBE = {   # 每张表自己的长袍色阶（由同族两张表的逐像素差集反推，见模块 docstring）
    "Mage-Red":      {"dark": "#46000a", "base": "#770000", "mid": "#b60000", "light": "#ff2d2d"},
    "Mage-Cyan":     {"dark": "#002e27", "base": "#004f43", "mid": "#007966", "light": "#00b49d"},
    "Archer-Green":  {"dark": "#303600", "base": "#455000", "mid": "#627105", "light": "#8b9e0f"},
    "Archer-Purple": {"dark": "#2d0931", "base": "#4c1751", "mid": "#78277b", "light": "#cc2ac7"},
}

# ── 2. 掩膜后仍留在剪影【之内】的道具残根（牛角根 / 盔缨根）──────────────────
# 不清掉的话，Warrior 额角会留两点青绿、Soldier 头顶留一撮暗色，是纯粹的脏点。
# 先并进盔甲灰阶，第 3 步再随盔甲一起变成布料 ⇒ 与周围完全同料。
PROP_ROOT = {
    "Warrior-Blue":   {"#002e27": "#363636", "#004b3f": "#4d4c4b", "#007966": "#7d7b76", "#00b49d": "#a29e96"},
    "Warrior-Red":    {"#290505": "#363636", "#520c0c": "#4d4c4b", "#ae0000": "#7d7b76", "#ff1515": "#a29e96"},
    "Soldier-Blue":   {"#00332f": "#4d4c4b", "#005355": "#7d7b76", "#007d89": "#a29e96"},
    "Soldier-Red":    {"#46000a": "#4d4c4b", "#770000": "#7d7b76", "#b60000": "#a29e96"},
    "Soldier-Yellow": {"#422200": "#4d4c4b", "#7c5500": "#7d7b76", "#c6a900": "#a29e96"},
}

# ── 3. 盔甲灰阶 → 布料色阶（暗→亮 6 档）──────────────────────────────────────
ARMOUR = ["#1e1e1e", "#363636", "#4d4c4b", "#7d7b76", "#a29e96", "#bebbb5"]
# (色相°, 饱和度, 明度偏移, 说明)。饱和度上限 0.56：再高就不是便服是荧光背心了。
FABRIC = {
    "Warrior-Blue":   (218, 0.50,  0.00, "靛蓝工装（原身份=青蓝牛角，移到衣服并推离 Mage-Cyan 的青）"),
    "Warrior-Red":    (24,  0.30, -0.02, "赭褐皮围裙"),
    "Soldier-Blue":   (336, 0.30,  0.05, "藕紫衬衫"),
    "Soldier-Red":    (126, 0.40,  0.04, "草绿工服（让出暖色区：Mage-Red 与 Warrior-Red 已在那儿）"),
    # 压暗 0.02 是【一笔交易不是纯赚】：脸/衣对比 15.48→18.16、离世界表面 17.91→22.47，
    # 代价是与 Archer-Green 的可分度 15.06→12.67（仍高于现成资产自己的地板 11.54）。
    "Soldier-Yellow": (44,  0.52, -0.02, "芥黄工服（原身份=金羽，色相原样留用）"),
}
SAT_SHAPE = (1.10, 1.07, 1.01, 0.80, 0.62, 0.46)   # 暗档更饱和、亮档收敛，像织物不像塑料

SHEETS = list(ROBE) + list(FABRIC)


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fabric_ramp(hue, sat, lshift):
    """保留 ARMOUR 的明度剖面，只换色相/饱和度。"""
    out = []
    for a, m in zip(ARMOUR, SAT_SHAPE):
        r, g, b = (c / 255.0 for c in _hex(a))
        _, l, _ = colorsys.rgb_to_hls(r, g, b)
        l = max(0.0, min(1.0, l + lshift))
        r2, g2, b2 = colorsys.hls_to_rgb(hue / 360.0, l, max(0.0, min(1.0, sat * m)))
        out.append(tuple(int(round(c * 255)) for c in (r2, g2, b2)))
    return out


def build_lut(sheet):
    """返回 {源RGB: 目标RGB}。查表换色，逐像素独立，与姿势/帧号无关。"""
    lut = {}
    if sheet in ROBE:
        for src, tier in CIRCLET.items():
            lut[_hex(src)] = _hex(ROBE[sheet][tier])
    if sheet in FABRIC:
        ramp = fabric_ramp(*FABRIC[sheet][:3])
        grey2fab = {_hex(a): f for a, f in zip(ARMOUR, ramp)}
        for src, grey in PROP_ROOT[sheet].items():
            lut[_hex(src)] = grey2fab[_hex(grey)]      # 道具残根 → 灰 → 布料，一步到位
        lut.update(grey2fab)
    return lut


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def deprop(sheet, base_alpha):
    """掩膜 + 查表换色。返回 (图, 统计)。"""
    im = load(sheet)
    px = im.load()
    W, H = im.size
    lut = build_lut(sheet)
    masked = recoloured = 0
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a and not base_alpha[x][y]:
                px[x, y] = (0, 0, 0, 0)                # ← 道具：整块去掉
                masked += 1
                continue
            if a:
                t = lut.get((r, g, b))
                if t is not None:
                    px[x, y] = (t[0], t[1], t[2], a)
                    recoloured += 1
    return im, masked, recoloured


def main():
    probe = "--probe" in sys.argv
    base = load(BASE)
    ba = base.load()
    alpha = [[ba[x, y][3] > 0 for y in range(base.size[1])] for x in range(base.size[0])]

    # 自检 A：Character-Base 的 alpha 必须是每张表的严格子集，否则整个方法失效
    for s in SHEETS:
        im = load(s)
        p = im.load()
        bad = sum(1 for y in range(im.size[1]) for x in range(im.size[0])
                  if alpha[x][y] and p[x, y][3] == 0)
        assert bad == 0, "%s: Character-Base 有 %d 个像素不在它里面 —— 掩膜法不成立，停" % (s, bad)
    print("✅ 自检A：Character-Base 剪影是全部 %d 张表的严格子集（0 例外）" % len(SHEETS))

    if not probe:
        os.makedirs(DST, exist_ok=True)
    results = {}
    for s in SHEETS:
        im, masked, rec = deprop(s, alpha)
        results[s] = im
        note = FABRIC[s][3] if s in FABRIC else "长袍留用，仅去前额扣饰"
        print("  %-16s 去道具 %5d px  换色 %5d px   %s" % (s, masked, rec, note))
        if not probe:
            im.save(os.path.join(DST, s + ".png"))

    # 自检 B：产物的 alpha 必须逐字节等于 Character-Base ⇒ 身体轮廓不可能被改坏
    for s, im in results.items():
        p = im.load()
        diff = sum(1 for y in range(im.size[1]) for x in range(im.size[0])
                   if (p[x, y][3] > 0) != alpha[x][y])
        assert diff == 0, "%s: 产物剪影与 Character-Base 差 %d px" % (s, diff)
    print("✅ 自检B：9 张产物的剪影逐像素等于 Character-Base（身体轮廓零损伤）")

    # 自检 C：同族不再撞脸（掩膜后 Soldier 只差 73-91 px，换布料后必须拉开）
    import itertools
    for grp in (["Soldier-Blue", "Soldier-Red", "Soldier-Yellow"], ["Warrior-Blue", "Warrior-Red"]):
        for a, b in itertools.combinations(grp, 2):
            pa, pb = results[a].load(), results[b].load()
            n = sum(1 for y in range(256) for x in range(768) if pa[x, y] != pb[x, y])
            assert n > 3000, "%s vs %s 只差 %d px —— 身份没救回来" % (a, b, n)
            print("  ✅ %-15s vs %-15s 差 %5d px" % (a, b, n))

    if probe:
        print("\n(--probe：只跑断言，未写文件)")
    else:
        print("\n写出 %d 张 → %s" % (len(results), os.path.relpath(DST, ROOT)))


if __name__ == "__main__":
    main()
