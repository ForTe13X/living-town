#!/usr/bin/env python3
"""assert_daynight.py — 「昼夜量具」硬断言（docs/41 §6 盲区④ 的机器化）。

背景：`--shot` 把 `auto_run=false`，而 `_daylight` 此前只在 `_on_tick`/`_after_jump`/`_after_load` 里施加，
      三条路一条都不走 ⇒ **所有静帧一律按正午渲染**，HUD 却老老实实写着「夜」。
      C3 在 `Main.gd:271`（CanvasModulate 建好处）补的那一行是这个项目**所有视觉判断用的尺子**，
      本脚本守的就是那一行。

来源：C3 的 `scratchpad/wave_c/C3/assert_daynight.py`。色停表、取样带、众数色判据**逐字保留**（红线#5）。
C4 改了三处，每一处都是**在合并树上实测出来的**，不是口味：

  ① **去掉 Pillow 依赖。** `tools/ci.sh` 在此之前只用 stdlib，而 GitHub Actions 的 `setup-python`
     给的是裸解释器（**不预装 Pillow**）⇒ 把 PIL 写进 CI 等于给这条门种一个"在别人机器上环境性变红"的雷。
     现在自带 stdlib(zlib) 的 PNG 读取器；有 PIL 就用 PIL。两条路在 C3 留下的 **20 张证据图上
     逐字节给出同一个众数色**（20/20），这是等价性的证据而不是声明。

  ② **★ 基色不再硬编码，改从正午帧【量】出来。** C3 写的是 `GRASS=(133,166,67)`——那是 **C3 自己那棵树**
     上的草地色。合并后 C1 的季节色调把它变成了 **(134,173,79)**（docs/43 §1.2f 表里记着同一个数）。
     ⇒ **照抄 C3 的常数，这道门在合并树上第一次跑就是红的，而画面完全正确**——正是"在别人机器上假红"
     的同一种病，只不过这次"别人"是下一次美术改动。C7 正在再动一次 `WorldView.gd`，这个雷会立刻复发。
     修法是让判据**与美术无关**：色停表在 `tod=0.5` 处**恰好是纯白**（脚本自己断言这一点），
     所以**正午帧的世界主色【就是】未调制的基色**。于是真正被守住的性质是那个**比值**：
         night_modal == quant(noon_modal × _daylight(night_tod))
     基色随便怎么改都不影响它，而"那一行修复被拿掉"会让两帧变成同一个值 ⇒ 第 2、3 条同时炸。

  ③ **★ 量化是 round 不是 int。** C3 写的 `int()` 在 C3 那棵树上**碰巧**与 round 同结果
     （133·0.4242=56.41、166·0.4714=78.25、67·0.7972=53.41，三个小数部分都 <0.5）——**数据没能把这两者分开**。
     合并树把它们分开了：`int()` 给 (56,81,62)，实测是 **(57,82,63)** = `round()`。三通道全差 1。

断言（四条）：
  A0 结构前提：`_daylight(noon_tod)` 必须恰好是 (1,1,1)，否则"正午帧==基色"这个推导不成立。
  A1 夜帧主色 == quant(正午帧主色 × `_daylight(night_tod)`)   ← 期望值由色停表现算，不是魔法数字
  A2 两帧主色必须【不同】—— 挡住"两边一起错成同一个值"的空过（这正是修复前的症状）
  A3 （可选 `--base R,G,B`）正午帧主色 == 给定基色。**默认不开**：Wave C 期间美术还在动，
     把它设成必查等于让美术改动去撞视觉门。想把某一版美术钉死时再显式传。

`--tol N`：**只给没有 pin 死的光栅器用**。容器镜像 `gamecraft-runner:4.6.2` 里 mesa 版本钉死 ⇒ tol=0。
换一个 mesa，软件光栅可能差 1 个 LSB；而本门要挡的回归会让夜帧从 (57,82,63) 跳回 (134,173,79)，
**每通道差 77/91/16** ⇒ tol=4 一分判别力都不损失。

用法: python assert_daynight.py <night.png> <noon.png> [night_tick] [noon_tick] [--tol N] [--base R,G,B]
退出码 0=PASS 1=FAIL 2=用法错
"""
import sys
import zlib
from collections import Counter

TICKS_PER_DAY = 240

# Main.gd:_daylight 的色停表（夜蓝→晨暖→白昼→暮橙→夜蓝）——改 Main.gd 的表就要同步改这里，
# 这正是我们要的：色调是"蓄意的视觉契约"，动它必须是显式动作。
STOPS = [
    (0.00, (0.42, 0.47, 0.80)), (0.24, (0.45, 0.48, 0.78)),
    (0.30, (1.00, 0.86, 0.72)), (0.38, (1.00, 1.00, 1.00)),
    (0.68, (1.00, 1.00, 1.00)), (0.78, (1.00, 0.80, 0.62)),
    (0.86, (0.50, 0.52, 0.82)), (1.00, (0.42, 0.47, 0.80)),
]


def daylight(tod):
    for (a0, ac), (b0, bc) in zip(STOPS, STOPS[1:]):
        if a0 <= tod <= b0:
            f = (tod - a0) / max(1e-4, b0 - a0)
            return tuple(ac[i] + (bc[i] - ac[i]) * f for i in range(3))
    return (1.0, 1.0, 1.0)


def modulated(base, tod):
    """Godot 的 CanvasModulate 在 canvas_items/gl_compatibility 下是分量乘法 + 四舍五入。
    （`round` 而不是 `int`：见抬头 ③，合并树上三通道全差 1 把这两者分开了。）"""
    m = daylight(tod)
    return tuple(int(round(base[i] * m[i])) for i in range(3))


# ── stdlib PNG 读取（无 Pillow 时的地板）────────────────────────────────────
# 只支持 Godot `Image.save_png` 实际会吐的形状：bit_depth=8、color_type∈{2 RGB, 6 RGBA}、interlace=0。
# 碰到别的形状**直接抛**，绝不猜——猜错会得到一个"看起来能跑"的错误众数色。
def _png_rgb_rows(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s: 不是 PNG" % path)
    pos, idat, ihdr = 8, [], None
    while pos + 8 <= len(data):
        ln = int.from_bytes(data[pos:pos + 4], "big")
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            ihdr = body
        elif typ == b"IDAT":
            idat.append(body)
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if ihdr is None:
        raise ValueError("%s: 缺 IHDR" % path)
    w = int.from_bytes(ihdr[0:4], "big")
    h = int.from_bytes(ihdr[4:8], "big")
    depth, ctype, interlace = ihdr[8], ihdr[9], ihdr[12]
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        raise ValueError("%s: 不支持的 PNG 形状 depth=%d color_type=%d interlace=%d"
                         % (path, depth, ctype, interlace))
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
    for _y in range(h):
        ft = raw[p]; p += 1
        cur = bytearray(raw[p:p + stride]); p += stride
        if ft == 1:      # Sub
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 0xFF
        elif ft == 2:    # Up
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 0xFF
        elif ft == 3:    # Average
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:    # Paeth
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                cur[i] = (cur[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 0xFF
        elif ft != 0:
            raise ValueError("%s: 未知 filter %d" % (path, ft))
        rows.append(cur)
        prev = cur
    return w, h, bpp, rows


def world_mode(path):
    """世界区众数色：只取一条不含任何 HUD 的横带（设计坐标 x∈[60,960) y∈[60,420)）。"""
    try:
        from PIL import Image                       # 有 PIL 就走 PIL（与 stdlib 路 20/20 逐字节同结果）
        im = Image.open(path).convert("RGB")
        w, h = im.size
        sx, sy = w / 1280.0, h / 768.0
        band = im.crop((int(60 * sx), int(60 * sy), int(960 * sx), int(420 * sy)))
        return im.size, Counter(band.getdata()).most_common(1)[0][0]
    except ImportError:
        pass
    w, h, bpp, rows = _png_rgb_rows(path)
    sx, sy = w / 1280.0, h / 768.0
    x0, y0, x1, y1 = int(60 * sx), int(60 * sy), int(960 * sx), int(420 * sy)
    cnt = Counter()
    for y in range(y0, min(y1, h)):
        r = rows[y]
        for x in range(x0, min(x1, w)):
            i = x * bpp
            cnt[(r[i], r[i + 1], r[i + 2])] += 1
    return (w, h), cnt.most_common(1)[0][0]


def main():
    # CI 日志编码地板（实测踩到两次）：
    #  ① Windows 控制台默认 GBK，`⇒`(U+21D2) 编不出来 ⇒ print 直接抛 UnicodeEncodeError，
    #     于是**一道内容通过的门会因为一个箭头而变红**——正是本门最不该犯的错；
    #  ② 就算不抛，python 按 GBK 写、而 ci.sh 的 echo 按 UTF-8 写，同一个 tee 出来的日志里两种编码混着，
    #     中文全是乱码。这里统一钉成 UTF-8（Linux 上本来就是），errors="replace" 兜底永不抛。
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    argv = list(sys.argv[1:])
    tol, base = 0, None
    if "--tol" in argv:
        i = argv.index("--tol"); tol = int(argv[i + 1]); del argv[i:i + 2]
    if "--base" in argv:
        i = argv.index("--base")
        base = tuple(int(v) for v in argv[i + 1].split(",")); del argv[i:i + 2]
    if len(argv) < 2:
        print(__doc__)
        return 2
    night_png, noon_png = argv[0], argv[1]
    nt = int(argv[2]) if len(argv) > 2 else 488
    dt = int(argv[3]) if len(argv) > 3 else 600

    n_tod = (nt % TICKS_PER_DAY) / TICKS_PER_DAY
    d_tod = (dt % TICKS_PER_DAY) / TICKS_PER_DAY
    fails = 0

    # A0 · 结构前提：正午必须落在色停表的纯白区，否则"正午帧==未调制基色"这个推导不成立。
    dm = daylight(d_tod)
    if any(abs(c - 1.0) > 1e-9 for c in dm):
        print("  FAIL A0 正午 tick=%d (tod=%.4f) 的 _daylight=%s 不是纯白 —— 本量具的推导前提不成立，"
              "请换一个落在 [0.38,0.68] 的 tick" % (dt, d_tod, tuple(round(c, 4) for c in dm)))
        return 1
    noon_size, noon_c = world_mode(noon_png)
    print("  base  正午帧世界主色 = %s  im.size=%s  (tod=%.4f => _daylight 恰为纯白 => 它【就是】未调制基色)"
          % (noon_c, noon_size, d_tod))

    # A1 · 夜帧 == quant(基色 × _daylight(night_tod))，期望值由色停表现算
    night_size, night_c = world_mode(night_png)
    want = modulated(noon_c, n_tod)
    dev = max(abs(night_c[i] - want[i]) for i in range(3))
    ok = dev <= tol
    fails += 0 if ok else 1
    print("  %s A1 夜帧  tick=%d tod=%.4f  im.size=%s  world_mode=%s  expect=%s  dmax=%d (tol=%d)"
          % ("PASS" if ok else "FAIL", nt, n_tod, night_size, night_c, want, dev, tol))

    # A2 · 两帧必须不同（修复前的症状就是它们相同）
    if night_c == noon_c:
        print("  FAIL A2 夜/昼两帧世界主色相同 %s —— 昼夜量具坏了（Main.gd 的 _modulate 首帧上色被拿掉了？）"
              % (night_c,))
        fails += 1
    else:
        print("  PASS A2 夜 %s != 昼 %s" % (night_c, noon_c))

    # A3 · 可选：把某一版美术的基色钉死
    if base is not None:
        d2 = max(abs(noon_c[i] - base[i]) for i in range(3))
        if d2 <= tol:
            print("  PASS A3 正午基色 == %s" % (base,))
        else:
            print("  FAIL A3 正午基色 %s != 指定基色 %s (dmax=%d, tol=%d)" % (noon_c, base, d2, tol))
            fails += 1

    print("=== DAYNIGHT GATE: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
