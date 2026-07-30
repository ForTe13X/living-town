#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""coif_characters.py — 给十位居民各自的轮廓（Wave F · F2；还 docs/48 §一 记下的 E3 的债）。

E3（`deprop_characters.py`）用一次 alpha 掩膜把奇幻行头整块摘掉，代价写在 docs/44 §一·五：
**十张脸的 alpha 全部等于 `Character-Base`** ⇒ 剪影完全相同，辨识只剩衣服颜色。
本脚本把轮廓加回来，加的是**现代小镇的**轮廓（发型 / 帽子 / 胡子），不是奇幻道具。

## 为什么它同样是"运算"而不是"眼力活"（E3 那条代数在这里反着用一遍）

E3 的不变量是 `out.alpha == base.alpha`。于是**本脚本新加的每一个像素，按定义就是
`out.alpha AND NOT base.alpha`**——不用眼睛数，直接算得出来"我加了多少、加在哪"。
两张脸的剪影可分度同样是一个可算的数（12 个可达帧上的 alpha 异或计数），不是印象。

## 三步（每一步都可单独关掉验证）

1. **复位**：把头部带（`top .. top+7`，`top` = 该帧 base 的首个非空行）整块从 `Character-Base` 复制回来。
   这一步是**纯复制、零发明**，但它顺手修掉了 E3 留下的两处退化：
   - 兜帽被掩膜切掉自己的黑描边之后，**头顶那一圈没有描边了**（`Mage-Red` 帧内 y10 直接是 `#770000`）；
   - 兜帽压到 y15 ⇒ **眼睛上半截被布盖住**，出货的脸是一双眯着的 1px 眼。
     复位之后眼睛恢复成 2px，额头（y14）露出来。
2. **戴发**：按每位居民一张 ASCII 模板盖上头发/帽子。模板锚在 `(x_ref, top)`——
   `x_ref` = base 首行的最小 x ⇒ **走路"上下颠"那一帧（col 1 整体上移 1px）自动对齐**，不需要写死行号。
3. **描边**：模板自带 `O`（`#040404`，与身体同一根描边色）。**新加的像素必须自带描边**，
   否则它在浅色地面上会糊掉——这是 32px 下新画东西最容易翻车的地方。

## 只有 12 帧要紧

`WorldView._agent_frame()` 只出 `col 0..3 × row {0,1,3}`（docs/44 §一·五 第 2 条）。
本脚本对**整张表 192 帧**统一施加同一套规则（保持表自洽），但所有度量只报那 12 帧。

## 许可（红线 #4）

源仍是 CC0 的 `puny-characters`（作者 Shade）。本脚本只做**复制 / 查表上色 / 写死坐标的手绘模板**，
不缩放、不插值、**没有任何生成图参与**（docs/43 §二-R2）。产物仍是 CC0 自绘衍生。

用法：
    python tools/coif_characters.py              # 重新生成 game/assets/art/pro/*.png（含 deprop 一步）
    python tools/coif_characters.py --probe      # 只跑断言与度量，不写文件
    python tools/coif_characters.py --metrics    # 断言 + 完整度量表（剪影可分度 / 脸的皮肤边界）
    python tools/coif_characters.py --preview D  # 把改前/改后的 12 帧写成对照图到目录 D
"""
import os
import sys
import itertools

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

try:                                    # Windows 控制台默认 GBK，直接 print 中文/✅ 会 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import deprop_characters as dp          # 复用 E3 的掩膜 + 换色，不复制它的逻辑

ROOT = dp.ROOT
DST = dp.DST
BASE = dp.BASE
SHEETS = dp.SHEETS

FRAME = 32
COLS_USED = (0, 1, 2, 3)
ROWS_USED = (0, 1, 3)              # idle / 横走 / 上走；row2 与 col>=4 渲染器到不了

OUTLINE = (0x04, 0x04, 0x04)       # 身体自己的描边色，新东西必须用同一根

# ── 发色阶（暗/中/亮）。全部是自然发色；不用纯黑——夜间乘子之后纯黑会和描边并成一坨 ─────
HAIR = {
    "black":    ("#15151c", "#26263a", "#3d3d55"),
    "darkbrown":("#241610", "#3d2618", "#5d3b24"),
    "chestnut": ("#2e1a10", "#54301c", "#7d4a2b"),
    "ginger":   ("#3d1c0c", "#7a3b16", "#b06a2c"),
    "grey":     ("#3a3a3c", "#6e6e6e", "#a0a09c"),
    "flaxen":   ("#5a3d18", "#96702e", "#cba24e"),
}

# ── 模板坐标系 ────────────────────────────────────────────────────────────────
# 每行 16 列 → x = x_ref-5 .. x_ref+10（标准帧 x_ref=13 ⇒ x=8..23）
# 行 0..12   → y = top-5 .. top+7    （标准帧 top=10 ⇒ y=5..17）
# 符号：'.' 不动  'O' 描边  'K' 发暗  'H' 发中  'L' 发亮
#       'C' 布暗  'M' 布中  'N' 布亮（帽子用本人衣服的色阶，读起来才是同一个人的东西）
#       '_' 抹成透明（平头削掉圆角）
STAMP_X0 = -5
STAMP_Y0 = -5

# base 头部（标准帧）供对照：
#   y10 x13..18 / y11 x12..19 / y12..15 x11..20 / y16 x12..19 / y17 x11..20
# 头发盖 y10..y13，y14 留作额头，y15/y16 是眼睛，y17 是脸颊。

STYLES = {
    # 阿丽（咖啡馆老板）：侧马尾。发团把头顶抬高 1px，尾巴从右耳后挂下（与头之间隔一列描边，
    # 否则它读成"帽子的护耳"而不是头发——第一版就是这么翻的车）。
    "Mage-Red": ("black", """
    ................
    ................
    ................
    ................
    .....OOOOOO.....
    ....OKHHHHKO....
    ...OKHLLHHHKO...
    ...OHHHHHHHHKO..
    ...OKHHHHHHKOKHO
    ....O......O.KHO
    .............KHO
    .............OOO
    ................
    """),

    # 可可（画家）：贝雷帽——扁圆、整体向左歪出 2px。帽子用她自己的青绿色阶，亚麻发从帽下露出来。
    # 第一版在帽顶多画了一个 2px 的黑尖，实测读成"天线"，已删。
    "Mage-Cyan": ("flaxen", """
    ................
    ................
    ................
    ...OMMO.........
    ..OMNNMMMMO.....
    ..OCMMMMMMMCO...
    ...OCMMMMMMCO...
    ...OKHHHHHHKO...
    ...OKHHHHHHKO...
    ....O......O....
    ................
    ................
    ................
    """),

    # 小薇（学生）：双马尾。发团先外扩到 x10/x21，两撮再从那儿【向外撇出去】到 x8/x23 并收口。
    # 改过两次，两次都是被量出来的：
    #  ① 第一版挂在 y12..15、与眼同高 ⇒ 读成"护耳"；下移一格 + 收口之后才是辫子。
    #  ② 第二版贴着头挂 ⇒ 与阿菲的齐肩短发只差 98px（全场最小对）。往外撇两列之后是 246px。
    "Archer-Green": ("darkbrown", """
    ................
    ................
    ................
    ................
    .....OOOOOO.....
    ....OKHHHHKO....
    ...OKHHLLHHKO...
    ..OKHHHHHHHHKO..
    OKHOKHHHHHHKOHKO
    OKHO........OHKO
    OKHO........OHKO
    .OO..........OO.
    ................
    """),

    # 阿菲 / 苏琴（医生、琴师）：齐肩短发——两侧垂到下颌 y15..17，
    # 是**唯一一个在下半部扩轮廓**的发型，因此和所有"头顶做文章"的款不会撞。
    "Archer-Purple": ("black", """
    ................
    ................
    ................
    ................
    .....OOOOOO.....
    ....OKHHHHKO....
    ...OKHHLLHHKO...
    ..OKHHHHHHHHKO..
    ..OKHO....OKHO..
    ..OKH......HKO..
    ..OKH......HKO..
    ..OKH......HKO..
    ..OOO......OOO..
    """),

    # 阿本（工坊木匠）：鸭舌帽——**平顶方肩 + 只朝一侧伸出的帽舌**。
    # 帽舌做成单侧是刻意的：第一版是左右对称的一圈檐，和老海的雨帽在 2× 下读起来是同一顶帽子。
    "Warrior-Blue": ("darkbrown", """
    ................
    ................
    ................
    ................
    ....OOOOOOOO....
    ...OMMMMMMMMO...
    ...OMMMMMMMMO...
    ...OCCCCCCCCCMO.
    ...OCCCCCCCCCMMO
    ............OOOO
    ................
    ................
    ................
    """),

    # 阿林（面点铺师傅）：头巾——右上角一个 2×2 的结顶出去。姜黄头发从巾下露一排。
    "Warrior-Red": ("ginger", """
    ................
    ................
    ................
    ...........OO...
    .....OOOOOOMMO..
    ....OMNNNNMMMO..
    ...OMNNNNNNMO...
    ...OCMMMMMMCO...
    ...OKHHHHHHKO...
    ....O......O....
    ................
    ................
    ................
    """),

    # 老海（渔夫）：宽檐雨帽——全场最宽的轮廓（y12 达 14px，头本身只有 10px）。
    "Soldier-Blue": ("grey", """
    ................
    ................
    ................
    .....OOOOOO.....
    ....OMMMMMMO....
    ...OMMMMMMMMO...
    ..OCMMMMMMMMCO..
    .OCMMMMMMMMMMCO.
    .OOOOOOOOOOOOOO.
    ................
    ................
    ................
    ................
    """),

    # 沈书（教书先生）：发髻——最小的一个轮廓，但它站在正中最高处，任何缩放档都读得出。
    # ⚠️ 第一版是 2px 宽 × 3px 高的尖顶，实测读成【尖帽/冰淇淋筒】而不是发髻，正是 docs/44 §一
    # 要淘汰的那种东西。改成 4px 宽 × 2px 高的圆钮，底下压一条描边当发带。
    "Soldier-Red": ("black", """
    ................
    ......OOOO......
    .....OKHLKO.....
    .....OKHHKO.....
    .....OOOOOO.....
    ....OKHHHHKO....
    ...OKHHLLHHKO...
    ...OHHHHHHHHO...
    ...OKHHHHHHKO...
    ....O......O....
    ................
    ................
    ................
    """),

    # 老邓 / 铁牛（退休船长、铁匠）：针织毛线帽——全场**最高**的一顶（顶到 y8，比谁都高两格），
    # 而且是**直筒的**：第二版给它加了一圈外翻的帽口，实测在 2× 下和老海的宽檐雨帽读成同一顶帽子
    # （两者都变成"上窄下宽"）。直筒 ⇒ 它占的是"高"这条轴，老海占"宽"，两条轴才不互相吃。
    # 这一张被两个人共用（docs/44 §一 记过），所以取一个两边都说得通的东西。
    # ⚠️ 这一格换过一次：先画的是**络腮胡**（想占"往下颌扩轮廓"这条唯一没人用的轴），
    #    实测读成【一副灰色面罩 + 一条眼缝】而不是胡子——y17 是眼睛以下**唯一**一行脸，
    #    整行盖住就没有脸了。更要紧的是它暴露了一条结构约束，见模块 docstring「只有头带是稳的」。
    "Soldier-Yellow": ("grey", """
    ................
    ................
    ................
    .....OOOOOO.....
    ....ONNNNNNO....
    ...OMMMMMMMMO...
    ...OMMMMMMMMO...
    ...OCCCCCCCCO...
    ...OKHHHHHHKO...
    ....O......O....
    ................
    ................
    ................
    """),

    # 阿梅（裁缝）：蓬松波浪短发——发量把头两侧各撑出 1-2px，顶上留一个缺口做"不规则"。
    # ⚠️ 这一张同时是 WorldView.FALLBACK_SPRITE（玩家空 sprite 回退皮），见 README。
    # 第一版画成三个 2px 高的独立凸起，实测读成"角"，已改成连续发量 + 一个缺口。
    "Character-Base": ("chestnut", """
    ................
    ................
    ................
    ................
    ....OOO.OOO.....
    ...OKHHHHHHKO...
    ..OKHHLLHHHHKO..
    ..OKHHHHHHHHKO..
    ...OKHHHHHHKO...
    ....O......O....
    ................
    ................
    ................
    """),
}


# ── 工具 ─────────────────────────────────────────────────────────────────────
def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def parse_stamp(text):
    """'...' 多行字符串 → {(dx, dy): 符号}，dx/dy 相对 (x_ref, top)。"""
    out = {}
    lines = [ln.strip() for ln in text.strip("\n").split("\n")]
    for j, ln in enumerate(lines):
        for i, ch in enumerate(ln):
            if ch != ".":
                out[(STAMP_X0 + i, STAMP_Y0 + j)] = ch
    return out


def cloth_ramp(sheet):
    """该表自己的布料色阶 → (暗, 中, 亮)。ROBE 与 FABRIC 两族口径不同，这里统一成三档。"""
    if sheet in dp.ROBE:
        r = dp.ROBE[sheet]                       # 取 base/mid/light 而不是 dark/base/mid：
        return _rgb(r["base"]), _rgb(r["mid"]), _rgb(r["light"])   # 长袍的 dark 档太暗，做帽子会糊成黑块
    if sheet in dp.FABRIC:
        ramp = dp.fabric_ramp(*dp.FABRIC[sheet][:3])
        return ramp[1], ramp[3], ramp[4]
    return (60, 60, 60), (120, 120, 120), (180, 180, 180)   # Character-Base 没有衣服


def frame_anchor(base_px, col, row):
    """返回该帧 base 的 (x_ref, top)；空帧返回 None。"""
    ox, oy = col * FRAME, row * FRAME
    for y in range(FRAME):
        xs = [x for x in range(FRAME) if base_px[ox + x, oy + y][3] > 0]
        if xs:
            return min(xs), y
    return None


def coif_frame(out_px, base_px, col, row, stamp, hair, cloth, restore_rows=8):
    """对单帧：① 头部带从 base 复位 ② 盖模板。返回 (复位像素数, 新增 alpha 像素数)。"""
    a = frame_anchor(base_px, col, row)
    if a is None:
        return 0, 0
    x_ref, top = a
    ox, oy = col * FRAME, row * FRAME

    # ① 复位：头部带 top..top+restore_rows-1，x 窗口取 base 首行 ±4（标准帧 = x9..x22，含整个头）
    restored = 0
    for dy in range(restore_rows):
        y = top + dy
        if y >= FRAME:
            break
        for x in range(max(0, x_ref - 4), min(FRAME, x_ref + 10)):
            src = base_px[ox + x, oy + y]
            if out_px[ox + x, oy + y] != src:
                out_px[ox + x, oy + y] = src
                restored += 1

    # ② 盖模板
    pal = {"O": OUTLINE, "K": hair[0], "H": hair[1], "L": hair[2],
           "C": cloth[0], "M": cloth[1], "N": cloth[2]}
    added = 0
    for (dx, dy), ch in stamp.items():
        x, y = x_ref + dx, top + dy
        if not (0 <= x < FRAME and 0 <= y < FRAME):
            continue
        was = out_px[ox + x, oy + y][3] > 0
        if ch == "_":
            out_px[ox + x, oy + y] = (0, 0, 0, 0)
            if was:
                added -= 1
            continue
        c = pal[ch]
        out_px[ox + x, oy + y] = (c[0], c[1], c[2], 255)
        if not was:
            added += 1
    return restored, added


def build(sheet, base_img):
    """deprop（E3）→ coif（本棒）。返回成品 Image。"""
    base_px = base_img.load()
    if sheet == BASE:
        im = base_img.copy()
    else:
        alpha = [[base_px[x, y][3] > 0 for y in range(base_img.size[1])]
                 for x in range(base_img.size[0])]
        im, _, _ = dp.deprop(sheet, alpha)
    px = im.load()
    hname, text = STYLES[sheet]
    hair = tuple(_rgb(c) for c in HAIR[hname])
    cloth = cloth_ramp(sheet)
    stamp = parse_stamp(text)
    W, H = im.size
    tot_r = tot_a = 0
    for row in range(H // FRAME):
        for col in range(W // FRAME):
            r, a = coif_frame(px, base_px, col, row, stamp, hair, cloth)
            tot_r += r
            tot_a += a
    return im, tot_r, tot_a


# ── 度量 ─────────────────────────────────────────────────────────────────────
def used_pixels():
    """12 个可达帧的 (x, y) 全集。"""
    for row in ROWS_USED:
        for col in COLS_USED:
            for y in range(FRAME):
                for x in range(FRAME):
                    yield col * FRAME + x, row * FRAME + y


USED = None


def alpha_set(im):
    px = im.load()
    return {(x, y) for (x, y) in USED if px[x, y][3] > 0}


def silhouette_diff(a, b):
    return len(alpha_set(a) ^ alpha_set(b))


def face_skin_edge(im):
    """脸上的皮肤边界像素数（E3 用的同一口径：皮肤色且四邻中有非皮肤）。
    只数**眼睛所在行及其上下各 3 行**的头部窗口，避免把手/小腿的皮肤算进"脸"。"""
    px = im.load()
    skin = {(0xf7, 0xd0, 0x99), (0xfa, 0xe7, 0xb5), (0xf6, 0xa9, 0x54),
            (0xd9, 0x7f, 0x40), (0xaa, 0x5a, 0x33), (0x84, 0x48, 0x2a)}
    n = 0
    for row in ROWS_USED:
        for col in COLS_USED:
            ox, oy = col * FRAME, row * FRAME
            for y in range(8, 20):
                for x in range(8, 24):
                    p = px[ox + x, oy + y]
                    if p[3] == 0 or p[:3] not in skin:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        q = px[ox + x + dx, oy + y + dy]
                        if q[3] == 0 or q[:3] not in skin:
                            n += 1
                            break
    return n


def main():
    global USED
    USED = list(used_pixels())
    probe = "--probe" in sys.argv or "--metrics" in sys.argv
    metrics = "--metrics" in sys.argv
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)
        probe = True

    base_img = dp.load(BASE)
    # ⚠️ "改前"必须**重新算出来**，不能读 `pro/` 里的文件：那个目录一旦被本脚本写过，
    #    "改前"就变成了"改后"，整张对照表静默退化成 x → x。第一版就是读文件的，
    #    写完文件再跑 --metrics 时十行全变成 "294 → 294"。
    #    这里改成走 E3 自己的管线重建基线（Character-Base 取 library/ 原样），
    #    于是判据**在任何时刻、任何工作区状态下都能复跑**，与 git 状态无关。
    balpha = [[base_img.load()[x, y][3] > 0 for y in range(base_img.size[1])]
              for x in range(base_img.size[0])]
    before = {BASE: base_img.copy()}
    for s in SHEETS:
        before[s] = dp.deprop(s, balpha)[0]

    after = {}
    print("表                 复位px   新增alpha px   发色      风格")
    for s in STYLES:
        im, r, a = build(s, base_img)
        after[s] = im
        print("  %-16s %6d  %8d      %-10s" % (s, r, a, STYLES[s][0]))

    # 断言 A：每张表的新增像素 = out.alpha AND NOT base.alpha，必须 > 0（真的加了轮廓）
    base_alpha = alpha_set(base_img)
    for s, im in after.items():
        added = alpha_set(im) - base_alpha
        assert len(added) > 0, "%s：可达帧上一个像素都没加，轮廓没变" % s
    print("✅ A：10 张表在 12 个可达帧上都有 alpha 外扩（相对 Character-Base）")

    # 断言 B：任意两张表的剪影可分度 —— 这是本棒的头条数字
    pairs = []
    for a, b in itertools.combinations(sorted(after), 2):
        pairs.append((silhouette_diff(after[a], after[b]), a, b))
    pairs.sort()
    print("✅ B：剪影两两可分度 最小 %d px（%s vs %s）  中位 %d  最大 %d"
          % (pairs[0][0], pairs[0][1], pairs[0][2], pairs[len(pairs) // 2][0], pairs[-1][0]))
    assert pairs[0][0] > 0, "有两张表剪影完全相同"

    if metrics:
        # ★ 判据先在【未改动的树】上跑一遍（docs/41 §6）。这里**不写死**"改前是 0"，而是当场量出来：
        #    写死的那一版曾经以断言的形式出现在报告里，而它当时没有被任何代码算过。
        b0 = [silhouette_diff(before[a], before[b])
              for a, b in itertools.combinations(sorted(after), 2)]
        print("\n★ 未改动的树上跑同一判据：%d 对，最小 %d 最大 %d ⇒ %s"
              % (len(b0), min(b0), max(b0),
                 "恒为 0，判据有判别力" if max(b0) == 0 else "非 0 ⇒ 判据被污染，停下来查"))
        print("\n── 剪影可分度（12 可达帧 alpha 异或）──")
        for n, a, b in pairs:
            print("   %5d  %-16s %s" % (n, a, b))
        print("\n── 脸的皮肤边界像素（12 可达帧；越大 = 脸露得越多/越有结构）──")
        for s in sorted(after):
            print("   %-16s 改前 %4d → 改后 %4d" % (s, face_skin_edge(before[s]), face_skin_edge(after[s])))

    if preview:
        _write_preview(before, after, preview)

    if probe:
        print("\n(--probe：未写文件)")
    else:
        os.makedirs(DST, exist_ok=True)
        for s, im in after.items():
            im.save(os.path.join(DST, s + ".png"))
        print("\n写出 %d 张 → %s" % (len(after), os.path.relpath(DST, ROOT)))


def _write_preview(before, after, outdir, zoom=10):
    """改前/改后各 12 帧并排，供 R10 眼验。"""
    names = sorted(after)
    cell = FRAME * zoom
    for tag, d in (("before", before), ("after", after)):
        img = Image.new("RGBA", (cell * 12, cell * len(names)), (40, 40, 48, 255))
        for si, nm in enumerate(names):
            k = 0
            for row in ROWS_USED:
                for col in COLS_USED:
                    f = d[nm].crop((col * FRAME, row * FRAME,
                                    col * FRAME + FRAME, row * FRAME + FRAME))
                    img.alpha_composite(f.resize((cell, cell), Image.NEAREST), (k * cell, si * cell))
                    k += 1
        img.save(os.path.join(outdir, "coif_%s.png" % tag))
    print("预览写到 %s" % outdir)


if __name__ == "__main__":
    main()
