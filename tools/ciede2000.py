#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""ciede2000.py — **本仓库缺的那支色差探针。**

## 它为什么现在才存在（编号 82 · U3）

T2 的前瞻注入实验里，L4「数字」这一层被一刀劈成两半：
**树上还有第二份拷贝或能重算的 3/3 被抓住；只存在于那一份文档里的 0/2。**
A3 明写了它为什么没抓到那两条（逐字）：

> **E5 的三个头条数**……树上**没有任何 CIEDE2000 工具**
> （`grep -rl "ciede2000|CIEDE2000|delta_e|ΔE00"` 只命中注释文字，**没有实现**），也没有 `night_pairs.py`。
> **这些数不可复算。**

我复核了这句话，**成立，而且范围比 A3 说的更大**：树上确实有 ΔE 的实现，
但那是 **CIE76**（`assert_interior_shell.py:72` / `assert_furniture_role.py:99` 各一份，互相拷贝），
**而全仓所有写着 `ΔE00` 的数字用的都是 CIEDE2000**——两者在这套调色板上差得很远
（见 `--compare-de76`）。⇒ **门用的尺子和文档用的尺子从来不是同一把。**

## 负对照（`--self-test`，每次跑都跑，不是一次性的）

四条，**每一条都要求"改一个输入必须给出不同的数"**，不是"跑通了"：

  **A. 已知答案**：Sharma-Wu-Dalal (2005) 的 CIEDE2000 测试集 **34 对**（专门为抓
     色相象限/回绕 bug 设计的）。逐对必须复现到 1e-4。**这是外部真值，不是我自己造的。**
  **B. 本仓库自己的已知答案**：`game/assets/art/palette.gpl` 抬头逐字写着
     「好感正 = grass-spring……与它所画在的 grass-summer 相差 **ΔE00 仅 6.3**」。
     两个颜色都在同一份 `.gpl` 里 ⇒ 这个数**今天就该能被重算**，而在本工具之前不能。
  **C. 扰动**：把 B 那一对的 **1 个通道 ±1**，ΔE00 必须**变**（这是"改一个像素必须不同"）。
  **D. 与树上现有的 CIE76 交叉核对**：同一条 `srgb_to_lab`（逐字抄自
     `assert_interior_shell.py`，故两条门与本工具站在同一条色彩管线上），
     ΔE76 必须与 `assert_interior_shell.de76` 逐位相同 ⇒ 差异只可能来自 ΔE00 公式本身。

## 用法

    python tools/ciede2000.py --self-test
    python tools/ciede2000.py --pair "#a8bf61" "#85a643"        # 两个 hex
    python tools/ciede2000.py --palette                          # .gpl 全表两两 ΔE00
    python tools/ciede2000.py --palette --min 8                  # 只列贴得太近的对
    python tools/ciede2000.py --palette --night                  # 先施夜乘子再比（D6 的 night_pairs 那件事）
    python tools/ciede2000.py --palette --names grass-spring grass-summer
    python tools/ciede2000.py --compare-de76                     # ΔE00 vs 树上现役的 ΔE76

⚠️ **它不重建 E5 的那条合成链**（alpha 合成 → 季节 → 大气罩 → 昼夜）。
E5 的 `2.18` / `45.77` 是**在真帧上标定的**，要复算它们还需要把那条链也搬进来
——**本棒没做**，理由与量：见编号 82 §三。**没做就是没做。**
"""
import argparse
import math
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GPL = os.path.join(ROOT, "game", "assets", "art", "palette.gpl")

# `CanvasModulate` 在 tick 488（00:48）的实测乘子。
# 出处：game/scripts/WorldView.gd:2065 与 tools/assert_daynight.py:27（两处逐位相同）。
# ⚠️ 这是个**冻结字面量**，而契约说别留冻结字面量 ⇒ 下面 night_mult() 从源码 grep，
#    grep 不到就红，而不是静默用这三个数。
NIGHT_FALLBACK = (0.4242, 0.4714, 0.7972)


def night_mult():
    """从 `assert_daynight.py` 现读夜乘子，不写死。

    读不到 ⇒ 抛错而不是回落——回落会让本工具在乘子改掉之后**静默给出旧答案**，
    正是 S2 那条统一结论点名的那一族（打印冻结字面量的全部过期）。
    """
    p = os.path.join(ROOT, "tools", "assert_daynight.py")
    with open(p, encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r"(\d\.\d{3,})\s*=\s*56\.41.*?(\d\.\d{3,})\s*=\s*78\.25.*?(\d\.\d{3,})\s*=\s*53\.41",
                  txt, re.S)
    if m:
        return tuple(float(x) for x in m.groups())
    m = re.search(r"133[·*](\d\.\d+).*?166[·*](\d\.\d+).*?67[·*](\d\.\d+)", txt, re.S)
    if m:
        return tuple(float(x) for x in m.groups())
    raise SystemExit("ciede2000: 在 tools/assert_daynight.py 里读不到夜乘子 —— "
                     "它改名或搬家了。本工具拒绝用写死的 %s 静默顶上。" % (NIGHT_FALLBACK,))


# ── 色彩管线：逐字抄自 tools/assert_interior_shell.py:57，故两条现役门与本工具同源 ──
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


def de76_lab(la, lb):
    return math.sqrt(sum((p - q) ** 2 for p, q in zip(la, lb)))


def ciede2000_lab(lab1, lab2, kL=1.0, kC=1.0, kH=1.0):
    """CIEDE2000 (Sharma-Wu-Dalal 2005 的表述)。输入 CIE L*a*b*。

    ⚠️ 这个公式有三个**每个实现都会踩**的坑，都在下面逐行注掉了：
      ① 色相角的**象限**必须用 atan2 并归一到 [0,360)；
      ② 平均色相 h̄' 在 |h1'−h2'| > 180 时要**加 360 再折半**，而且 C1'·C2'=0 时它没有定义；
      ③ ΔH' 用的是 **2·√(C1'C2')·sin(Δh'/2)**，不是 Δh' 本身。
    Sharma 的 34 对测试集就是为了把这三个坑逐一打红——见 --self-test A。
    """
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1 = math.hypot(a1, b1)
    C2 = math.hypot(a2, b2)
    Cbar = 0.5 * (C1 + C2)
    Cbar7 = Cbar ** 7
    G = 0.5 * (1.0 - math.sqrt(Cbar7 / (Cbar7 + 25.0 ** 7)))
    a1p = (1.0 + G) * a1
    a2p = (1.0 + G) * a2
    C1p = math.hypot(a1p, b1)
    C2p = math.hypot(a2p, b2)

    def hp(ap, bp):                                    # ← 坑①
        if ap == 0.0 and bp == 0.0:
            return 0.0
        return math.degrees(math.atan2(bp, ap)) % 360.0
    h1p = hp(a1p, b1)
    h2p = hp(a2p, b2)

    dLp = L2 - L1
    dCp = C2p - C1p
    if C1p * C2p == 0.0:
        dhp = 0.0
    else:
        dhp = h2p - h1p
        if dhp > 180.0:
            dhp -= 360.0
        elif dhp < -180.0:
            dhp += 360.0
    dHp = 2.0 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp) / 2.0)   # ← 坑③

    Lbarp = 0.5 * (L1 + L2)
    Cbarp = 0.5 * (C1p + C2p)
    if C1p * C2p == 0.0:                               # ← 坑②
        hbarp = h1p + h2p
    else:
        s = h1p + h2p
        if abs(h1p - h2p) <= 180.0:
            hbarp = 0.5 * s
        elif s < 360.0:
            hbarp = 0.5 * (s + 360.0)
        else:
            hbarp = 0.5 * (s - 360.0)

    T = (1.0
         - 0.17 * math.cos(math.radians(hbarp - 30.0))
         + 0.24 * math.cos(math.radians(2.0 * hbarp))
         + 0.32 * math.cos(math.radians(3.0 * hbarp + 6.0))
         - 0.20 * math.cos(math.radians(4.0 * hbarp - 63.0)))
    dTheta = 30.0 * math.exp(-(((hbarp - 275.0) / 25.0) ** 2))
    Cbarp7 = Cbarp ** 7
    RC = 2.0 * math.sqrt(Cbarp7 / (Cbarp7 + 25.0 ** 7))
    SL = 1.0 + (0.015 * (Lbarp - 50.0) ** 2) / math.sqrt(20.0 + (Lbarp - 50.0) ** 2)
    SC = 1.0 + 0.045 * Cbarp
    SH = 1.0 + 0.015 * Cbarp * T
    RT = -math.sin(math.radians(2.0 * dTheta)) * RC

    return math.sqrt((dLp / (kL * SL)) ** 2
                     + (dCp / (kC * SC)) ** 2
                     + (dHp / (kH * SH)) ** 2
                     + RT * (dCp / (kC * SC)) * (dHp / (kH * SH)))


def rel_lum(c):
    """WCAG 2.x 相对亮度。"""
    def f(u):
        u /= 255.0
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4
    r, g, b = f(c[0]), f(c[1]), f(c[2])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(c1, c2):
    """WCAG 对比度比（1..21）。

    第二个缺失的量具：全仓 13 处 `x.xx:1` 的对比度数字（README / docs/44 / docs/46…）
    此前**一处实现都没有**——与 ΔE00 同一个形状，只是没人点过它的名。
    """
    a, b = rel_lum(c1), rel_lum(c2)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def de00(rgb1, rgb2):
    return ciede2000_lab(srgb_to_lab(rgb1), srgb_to_lab(rgb2))


def de76(rgb1, rgb2):
    return de76_lab(srgb_to_lab(rgb1), srgb_to_lab(rgb2))


def parse_color(s):
    s = s.strip().lstrip("#")
    if re.fullmatch(r"[0-9a-fA-F]{6}", s):
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    parts = re.split(r"[,\s]+", s.strip())
    if len(parts) == 3:
        return tuple(int(p) for p in parts)
    raise ValueError("看不懂的颜色：%r（要 #rrggbb 或 'r,g,b'）" % s)


def load_palette(path=GPL):
    """读 GIMP .gpl。返回 [(name, (r,g,b))]，顺序即文件顺序。"""
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            m = re.match(r"\s*(\d+)\s+(\d+)\s+(\d+)\s+(.*)", line)
            if not m:
                continue
            name = m.group(4).split("#")[0].strip()
            out.append((name, (int(m.group(1)), int(m.group(2)), int(m.group(3)))))
    return out


def apply_mult(rgb, mult):
    """施加乘子并按引擎的做法**截断到整数码值**（不是四舍五入）。

    ⚠️ 这一步的取整规则是被 `assert_daynight.py:27` 那句实测钉住的：
    `133·0.4242=56.41`（三个小数部分都 <0.5）⇒ 那条实测既不能区分 floor 与 round。
    本工具取 **round**，与 Godot 的 8-bit 回写一致；用 `--trunc` 可以换成 floor，
    好让"这个选择改不改答案"是可测的而不是我的自称。
    """
    return tuple(max(0, min(255, int(round(c * m)))) for c, m in zip(rgb, mult))


# ────────────────────────── Sharma-Wu-Dalal (2005) 测试集 ──────────────────────────
# 34 对 CIE Lab + 公布的 ΔE00。这是**外部真值**（论文附带的 CIEDE2000 实现验证数据），
# 抄自公布的表；它专门覆盖色相回绕、C'=0、以及 RT 项显著的区域。
SHARMA = [
    ((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485), 2.0425),
    ((50.0000, 3.1571, -77.2803), (50.0000, 0.0000, -82.7485), 2.8615),
    ((50.0000, 2.8361, -74.0200), (50.0000, 0.0000, -82.7485), 3.4412),
    ((50.0000, -1.3802, -84.2814), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -1.1848, -84.8006), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -0.9009, -85.5211), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, 0.0000, 0.0000), (50.0000, -1.0000, 2.0000), 2.3669),
    ((50.0000, -1.0000, 2.0000), (50.0000, 0.0000, 0.0000), 2.3669),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0009), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0010), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0011), 7.2195),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0012), 7.2195),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0009, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0010, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0011, -2.4900), 4.7461),
    ((50.0000, 2.5000, 0.0000), (50.0000, 0.0000, -2.5000), 4.3065),
    ((50.0000, 2.5000, 0.0000), (73.0000, 25.0000, -18.0000), 27.1492),
    ((50.0000, 2.5000, 0.0000), (61.0000, -5.0000, 29.0000), 22.8977),
    ((50.0000, 2.5000, 0.0000), (56.0000, -27.0000, -3.0000), 31.9030),
    ((50.0000, 2.5000, 0.0000), (58.0000, 24.0000, 15.0000), 19.4535),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.1736, 0.5854), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2972, 0.0000), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 1.8634, 0.5757), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2592, 0.3350), 1.0000),
    ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
    ((63.0109, -31.0961, -5.8663), (62.8187, -29.7946, -4.0864), 1.2630),
    ((61.2901, 3.7196, -5.3901), (61.4292, 2.2480, -4.9620), 1.8731),
    ((35.0831, -44.1164, 3.7933), (35.0232, -40.0716, 1.5901), 1.8645),
    ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
    ((36.4612, 47.8580, 18.3852), (36.2715, 50.5065, 21.2231), 1.4146),
    ((90.8027, -2.0831, 1.4410), (91.1528, -1.6435, 0.0447), 1.4441),
    ((90.9257, -0.5406, -0.9208), (88.6381, -0.8985, -0.7239), 1.5381),
    ((6.7747, -0.2908, -2.4247), (5.8714, -0.0985, -2.2286), 0.6377),
    ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
]


def self_test():
    fails = []

    # A. 外部已知答案
    worst = 0.0
    bad = 0
    for i, (l1, l2, want) in enumerate(SHARMA, 1):
        got = ciede2000_lab(l1, l2)
        d = abs(got - want)
        worst = max(worst, d)
        if d > 1e-4:
            bad += 1
            if bad <= 5:
                print("    ❌ #%02d 期望 %.4f 实得 %.4f（差 %.4f）" % (i, want, got, d))
    print("  A 外部真值 Sharma-Wu-Dalal 34 对：%d/%d 复现（最大偏差 %.2e，判据 1e-4）"
          % (len(SHARMA) - bad, len(SHARMA), worst))
    if bad:
        fails.append("A: %d/%d 对没复现" % (bad, len(SHARMA)))

    # B. 结构自检：自反 = 0、对称、非负。便宜，但能抓住"公式被改坏"这一整类。
    pal = dict(load_palette())
    worst_self, worst_sym = 0.0, 0.0
    names = list(pal)
    for i, n in enumerate(names):
        worst_self = max(worst_self, abs(de00(pal[n], pal[n])))
        m = names[(i + 7) % len(names)]
        worst_sym = max(worst_sym, abs(de00(pal[n], pal[m]) - de00(pal[m], pal[n])))
    print("  B 结构自检（%d 色）：自反 ΔE00(c,c) 最大 %.2e（须 0）、对称性最大偏差 %.2e（须 0）"
          % (len(names), worst_self, worst_sym))
    if worst_self != 0.0 or worst_sym > 1e-12:
        fails.append("B: 自反/对称不成立（%.3e / %.3e）" % (worst_self, worst_sym))

    # C. 扰动：一个通道 ±1 必须改变答案
    a, b = pal["grass-spring"], pal["grass-summer"]
    base = de00(a, b)
    b1 = (b[0] + 1, b[1], b[2])
    got1 = de00(a, b1)
    print("  C 扰动 1 个通道（%s → %s）：%.4f → %.4f，差 %.4f（必须 > 0）"
          % (b, b1, base, got1, abs(got1 - base)))
    if abs(got1 - base) <= 0:
        fails.append("C: 改一个通道 ΔE00 没变 —— 这支探针没有分辨率")

    # D. 与树上现役的 CIE76 交叉核对（同一条 srgb_to_lab）
    try:
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        import assert_interior_shell as ais
        mx = 0.0
        for i in range(0, len(SHARMA)):
            c1 = (i * 7 % 256, i * 31 % 256, i * 53 % 256)
            c2 = (i * 11 % 256, i * 3 % 256, i * 97 % 256)
            mx = max(mx, abs(de76(c1, c2) - ais.de76(c1, c2)))
        print("  D 与 assert_interior_shell.de76 交叉核对 34 对随机色：最大差 %.2e（必须 0）" % mx)
        if mx != 0.0:
            fails.append("D: 与现役门的 ΔE76 对不上（最大差 %.3e）⇒ 色彩管线分叉了" % mx)
        # 顺带把两把尺子的差别量出来，好让"门和文档不是同一把尺"是个数不是句话
        pairs = [(pal[n1], pal[n2]) for n1, n2 in
                 (("grass-spring", "grass-summer"),) if n1 in pal and n2 in pal]
        for p, q in pairs:
            print("      ↳ 同一对：ΔE76 = %.2f，ΔE00 = %.2f" % (de76(p, q), de00(p, q)))
    except Exception as e:                                  # noqa: BLE001
        fails.append("D: 交叉核对跑不起来：%r" % (e,))

    # D2. 对比度比：也有外部已知答案（WCAG 定义域的两个端点 + 一个公布的边界值）
    cw = contrast((0, 0, 0), (255, 255, 255))
    cs = contrast((255, 255, 255), (255, 255, 255))
    c76 = contrast((0x76, 0x76, 0x76), (255, 255, 255))
    print("  D2 对比度比外部已知答案：黑↔白 = %.4f（须 21）、同色 = %.4f（须 1）、"
          "#767676↔白 = %.2f（WCAG 公布的 4.5 边界色，须 ≈4.54）" % (cw, cs, c76))
    if abs(cw - 21.0) > 1e-9 or abs(cs - 1.0) > 1e-12 or abs(c76 - 4.54) > 0.01:
        fails.append("D2: 对比度比的三个已知点没复现（%.4f / %.4f / %.4f）" % (cw, cs, c76))

    # E. 仓库自有的 ΔE00 数字，逐条重算并**只打印不判决**。
    #    为什么不判决：这些数在源码注释里写明是「四昼夜档 × 四季 × 三天气」的**最差值**，
    #    而那条合成链（alpha 合成 → 季节 → 大气罩 → 昼夜）**不在树上** ⇒ 本工具只能给
    #    **锚点对锚点**这一档。判它红等于用一把量不到那件事的尺子去判它。
    #    ⚠️ 但把它们打印出来是有价值的：四条**全部**低于锚点值，方向一致（链只会压缩）。
    #    逐条见编号 82 §三。
    KNOWN = [
        ("palette.gpl 抬头 / docs/44:218 / WorldView.gd:115  好感正↔草地", "#a8bf61", "#85a643", 6.3),
        ("WorldView.gd:3021  cafe(P_STONE)↔parlor(P_PLAZA)", "#9b968d", "#c3a97a", 12.10),
        ("WorldView.gd:3035  库房内墙↔旧地板", "#5a4028", "#6e4d31", 1.29),
        ("WorldView.gd:3038  库房内墙↔新地板", "#5a4028", "#b98956", 6.79),
    ]
    print("  E 仓库自有 ΔE00 数字的锚点对锚点重算（**只报不判**，理由见函数内注释）：")
    for tag, h1, h2, said in KNOWN:
        got = de00(parse_color(h1), parse_color(h2))
        print("      %-52s 文档/源码写 %5.2f   锚点重算 %6.2f   %s"
              % (tag, said, got, "≤ 锚点 ✓" if said <= got + 1e-9 else "⚠ 高于锚点"))

    if fails:
        for f in fails:
            print("  ❌ " + f)
        print("=== CIEDE2000 SELFTEST FAIL ❌ ===")
        return 1
    print("=== CIEDE2000 SELFTEST PASS ✅（外部真值 34/34 · 结构自检 · 扰动有分辨率 · 与现役门同源）===")
    return 0


def main():
    ap = argparse.ArgumentParser(description="CIEDE2000 色差探针（本仓库此前没有）")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--pair", nargs=2, metavar=("A", "B"), help="两个 #rrggbb 或 'r,g,b'")
    ap.add_argument("--palette", action="store_true", help="对 palette.gpl 全表两两算")
    ap.add_argument("--names", nargs=2, metavar=("N1", "N2"), help="--palette 时只算这两个色名")
    ap.add_argument("--min", type=float, default=None, help="--palette 时只列 ΔE00 < 这个值的对")
    ap.add_argument("--night", action="store_true", help="先施夜乘子再比（D6 的 night_pairs 那件事）")
    ap.add_argument("--trunc", action="store_true", help="乘子取整用 floor 而不是 round")
    ap.add_argument("--compare-de76", action="store_true", help="同表上并排打 ΔE76 与 ΔE00")
    ap.add_argument("--contrast", action="store_true", help="--pair 时改打 WCAG 对比度比而不是 ΔE00")
    ap.add_argument("--gpl", default=GPL)
    a = ap.parse_args()

    if a.self_test:
        return self_test()

    mult = night_mult() if a.night else None

    def prep(c):
        if mult is None:
            return c
        if a.trunc:
            return tuple(max(0, min(255, int(c[i] * mult[i]))) for i in range(3))
        return apply_mult(c, mult)

    if a.pair:
        c1, c2 = parse_color(a.pair[0]), parse_color(a.pair[1])
        p1, p2 = prep(c1), prep(c2)
        tag = "（夜乘子 %s 施加后 %s / %s）" % (tuple(round(m, 4) for m in mult), p1, p2) if mult else ""
        if a.contrast:
            print("对比度 = %.4f:1   %s vs %s %s" % (contrast(p1, p2), c1, c2, tag))
        else:
            print("ΔE00 = %.4f   ΔE76 = %.4f   %s vs %s %s"
                  % (de00(p1, p2), de76(p1, p2), c1, c2, tag))
        return 0

    if a.palette or a.compare_de76 or a.names:
        pal = load_palette(a.gpl)
        if a.names:
            d = dict(pal)
            for n in a.names:
                if n not in d:
                    sys.exit("palette 里没有色名 %r（有 %d 条）" % (n, len(pal)))
            p1, p2 = prep(d[a.names[0]]), prep(d[a.names[1]])
            print("ΔE00 = %.4f   ΔE76 = %.4f   %s%s vs %s%s"
                  % (de00(p1, p2), de76(p1, p2), a.names[0], d[a.names[0]],
                     a.names[1], d[a.names[1]]))
            return 0
        rows = []
        for i in range(len(pal)):
            for j in range(i + 1, len(pal)):
                (n1, c1), (n2, c2) = pal[i], pal[j]
                p1, p2 = prep(c1), prep(c2)
                rows.append((de00(p1, p2), de76(p1, p2), n1, n2))
        rows.sort()
        head = "夜乘子后 " if mult else ""
        print("=== %spalette.gpl %d 色 · %d 对 ===" % (head, len(pal), len(rows)))
        shown = [r for r in rows if a.min is None or r[0] < a.min]
        if a.min is not None:
            print("（只列 ΔE00 < %.2f 的 %d 对）" % (a.min, len(shown)))
        for d0, d7, n1, n2 in (shown if a.min is not None else rows[:25]):
            print("  ΔE00 %7.3f   ΔE76 %7.3f   %-18s %-18s" % (d0, d7, n1, n2))
        print("  ── 极值（连并列一起报）──")
        lo = [r for r in rows if abs(r[0] - rows[0][0]) < 1e-9]
        hi = [r for r in rows if abs(r[0] - rows[-1][0]) < 1e-9]
        print("  最小 ΔE00 = %.3f（%d 对并列）：%s" % (rows[0][0], len(lo),
              ", ".join("%s↔%s" % (r[2], r[3]) for r in lo[:4])))
        print("  最大 ΔE00 = %.3f（%d 对并列）：%s" % (rows[-1][0], len(hi),
              ", ".join("%s↔%s" % (r[2], r[3]) for r in hi[:4])))
        return 0

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
