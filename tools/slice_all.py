#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_all.py — emote / object 精灵的【配方】。切图部分容器内运行（要 ffmpeg），自绘部分纯 Python。

## 两种配方，一个文件

1. **CC0 切片**（`crop()`）：从 `assets/art/library/` 的 CC0 表按格子裁。obj 5 张 + emote 1 张（`confront`）。
2. **自绘像素**（`GLYPHS` + `render_glyph()`）：9 张 emote 的每一个像素都写在下面的字符画里。
   红线 #4 是「CC0 **或自绘**」——这一半走的是"自绘"，不是生成图。

## 为什么 9 张 emote 从"切"改成"画"（Wave I · I1，docs/53 §一）

H1 在真机上量到：10 张 emote 里 **9 张是同一个白气泡**，45 对两两差中位数 24/400，
最近的一对 `conflict`/`invite` 只差 **6/400**（我复现，逐格相同）。

**这不是选错了格子。** 我把整张 `puny-emotes.png`（7×6，38 个非空格）两两量了一遍：
```
全表 703 对：min=2  median=24  max=118
36 个"气泡型"格子（不透明>90）彼此：min=2  median=22  max=38
从全表里挑分得最开的 10 个格子（贪心+局部搜索）：min=14/400
```
⇒ **换格子的天花板是 14/400**，而且那 10 个里仍有 4 对并列在 14。
这张 CC0 表的全部内容就是"同一个白气泡里换 2-4 个像素的脸"——**素材本身没有可分性可挑**。
所以出货改为自绘：每张换一个**轮廓族**（手/盒/三点/箭头/心/裂心/爆星/环/叉），颜色只是第二通道。

`confront`（那个「!」）**不动**：它是 10 张里唯一与其余都 ≥93 的，H1 真机眼验判 OK，H2 已上门。
动它等于把一张已眼验通过的图重新变成未眼验的。

## 这份配方与 tools/asset_gate.py 的接口（**改这里之前先读那边**）

`asset_gate.harvest_recipes()` 会
- **exec 本文件**（`__name__="__main__"`）并把 `subprocess.run` 换成探针 ⇒ 采到每一条 ffmpeg `crop`；
- **另外 import 本文件**（`__name__="slice_all"`，靠下面的 `if __name__ == "__main__":` 守卫
  保证 import 无副作用）⇒ 拿到 `GLYPHS` / `render_glyph()`，当场重画出 9 张 emote 去比出货文件。

⇒ **不要删掉 `if __name__ == "__main__":` 守卫**（删了 import 就会往磁盘写），
也不要把 `render_glyph()` 改成读文件（它必须是纯函数：门的"重建独立于出货目录"自证靠这一点）。
"""
import os
import struct
import subprocess
import sys
import zlib


def crop(inp, out, w, h, col, row):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-i", inp, "-vf", f"crop={w}:{h}:{col*w}:{row*h}", out],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


EM = "/game/assets/art/library/puny-emotes/emotes.png"                                  # 140x120, 20px cells
OW = "/game/assets/art/library/punyworld-overworld/punyworld-overworld-tileset.png"     # 16px tiles

# CC0 切片保留的 emote：只剩 confront（H1 判 OK、H2 已上门，不动）
emotes = {"confront": (3, 2)}

objs = {"bath": (4, 30), "counter": (9, 31), "bench": (4, 31), "desk": (8, 31), "arcade": (7, 30)}

# ── 自绘像素表情 ───────────────────────────────────────────────────────────────────
# 每张 20×20（与 CC0 那批同尺寸；`WorldView.gd:2739` 把整张贴图拉进 EMOTE_PX=40 世界px 的方框，
# 所以尺寸只影响"源像素密度"，不影响屏幕占位）。
#
# 设计约束来自渲染尺度，不是源尺度（docs/53 §一·3 点名的那一格）：
#   `WorldView.gd:525` texture_filter = TEXTURE_FILTER_NEAREST
#   `WorldView.gd:14`  EMOTE_PX = 40 世界px
#   `WorldView.gd:2665` LABEL_MIN_ZOOM = 0.45 以下整块不画
#   ⇒ 最小可见尺寸 = 40 × 0.45 × 1.583(真机缩放) ≈ **28 设备px**，即 1.4 源px/设备px。
#   在 28px 上，**2-4 个像素的差别是不存在的**——旧图 9 张就死在这里。
#   所以判据放在"轮廓"上：每张换一个外形族，且把有效面积从旧图的 ~12×13 提到 ~16×18。
#
# 字符表：'.' 透明；'k' 描边（深）；其余字母见每张自己的调色板。
OUTLINE = (28, 26, 38, 255)

GLYPHS = {
    # 招呼：举起的手（三指 + 拇指 + 掌）—— 轮廓族「带缺口的团块」
    "greet": ({"a": (247, 183, 49, 255)}, [
        "....................",
        "....................",
        "......kk.kk.kk......",
        ".....kaakaakaak.....",
        ".....kaakaakaak.....",
        ".....kaakaakaak.....",
        ".....kaaaaaaaaak....",
        "..kk.kaaaaaaaaak....",
        ".kaakkaaaaaaaaak....",
        ".kaaaaaaaaaaaaak....",
        ".kaaaaaaaaaaaaak....",
        "..kaaaaaaaaaaaak....",
        "...kaaaaaaaaaaak....",
        "....kaaaaaaaaak.....",
        ".....kaaaaaaak......",
        "......kaaaaak.......",
        ".......kkkkk........",
        "....................",
        "....................",
        "....................",
    ]),
    # 赠予：礼盒 + 蝴蝶结 —— 轮廓族「矩形」
    "give": ({"a": (216, 74, 58, 255), "b": (250, 204, 84, 255)}, [
        "....................",
        "....................",
        "....................",
        "......kk..kk........",
        ".....kbbkkbbk.......",
        ".....kbbbbbbk.......",
        "......kbbbbk........",
        "..kkkkkkbbkkkkkkkk..",
        "..kaaaakbbkaaaaaak..",
        "..kaaaakbbkaaaaaak..",
        "..kaaaakbbkaaaaaak..",
        "..kbbbbbbbbbbbbbbk..",
        "..kaaaakbbkaaaaaak..",
        "..kaaaakbbkaaaaaak..",
        "..kaaaakbbkaaaaaak..",
        "..kaaaakbbkaaaaaak..",
        "..kkkkkkkkkkkkkkkk..",
        "....................",
        "....................",
        "....................",
    ]),
    # 八卦：三个越传越大的点 —— 轮廓族「三块互不相连」（全表唯一的断开形）
    "gossip": ({"a": (163, 102, 224, 255)}, [
        "....................",
        ".............kkkkk..",
        "............kaaaaak.",
        "...........kaaaaaaak",
        "...........kaaaaaaak",
        "...........kaaaaaaak",
        "...........kaaaaaaak",
        "...........kaaaaaaak",
        "............kaaaaak.",
        ".............kkkkk..",
        "......kkkkk.........",
        ".....kaaaaak........",
        ".....kaaaaak........",
        ".....kaaaaak........",
        ".....kaaaaak........",
        ".kkk.kaaaaak........",
        "kaaak.kkkkk.........",
        "kaaak...............",
        "kaaak...............",
        ".kkk................",
    ]),
    # 邀约：粗箭头 —— 轮廓族「横杆 + 三角」
    "invite": ({"a": (77, 191, 84, 255)}, [
        "....................",
        "....................",
        ".........kk.........",
        ".........kak........",
        ".........kaak.......",
        ".........kaaak......",
        "..kkkkkkkkaaaak.....",
        "..kaaaaaaaaaaaak....",
        "..kaaaaaaaaaaaaak...",
        "..kaaaaaaaaaaaaaak..",
        "..kaaaaaaaaaaaaak...",
        "..kaaaaaaaaaaaak....",
        "..kkkkkkkkaaaak.....",
        ".........kaaak......",
        ".........kaak.......",
        ".........kak........",
        ".........kk.........",
        "....................",
        "....................",
        "....................",
    ]),
    # 如约赴会：完整的心 —— 轮廓族「心」
    # ⚠ 顶部凹口深 **3 行**、两瓣各自再高 1 行：第一版只深 1 行，28px 眼验下心顶读成平的、
    #    整体像块盾牌。这是纯眼验驱动的改动——两两像素指标在这一步几乎没动。
    "meet_fulfilled": ({"a": (240, 92, 140, 255)}, [
        "....................",
        "...kkkkkk..kkkkkk...",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaaaaaaaaaaak..",
        "..kaaaaaaaaaaaaaak..",
        "...kaaaaaaaaaaaak...",
        "....kaaaaaaaaaak....",
        ".....kaaaaaaaak.....",
        "......kaaaaaak......",
        ".......kaaaak.......",
        "........kaak........",
        ".........kk.........",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
    ]),
    # 失约：同一颗心，从中间裂开 —— 轮廓族「心，但断开」
    # ⚠ 第一版把两半推得太开、各自收成一个尖，28px 下读成"两只翅膀"而不是"裂开的心"。
    #    现在裂缝只有 1 px 宽并且左右抖动 ⇒ 两半仍然合成一颗心的外形，只是中间有道缝。
    # ⚠ 颜色**必须比 meet_fulfilled 暗一大截**，这不是审美问题。原先用 (124,146,184)，
    #    亮度 143.8 与玫瑰色 141.7 **几乎相同** ⇒ 这一对是全表唯一"轮廓同族 + 亮度同档"的，
    #    实测把颜色压成灰度之后，它们在 28px 上的差 **5.87**，比旧那批白气泡的最差对(5.74)还差。
    #    现在 (78,96,130) 亮度 94.5，灰度差回到 22.9。**这一格是量出来的，不是看出来的。**
    "meet_broken": ({"a": (78, 96, 130, 255)}, [
        "....................",
        "...kkkkkk..kkkkkk...",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaaakkaaaaaak..",
        "..kaaaaak.kaaaaaak..",
        "..kaaaaaak.kaaaaak..",
        "...kaaaak.kaaaaak...",
        "....kaaaak.kaaak....",
        ".....kaaak.kaak.....",
        "......kaak.kak......",
        ".......kak.kk.......",
        "........kk..........",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
    ]),
    # 冲突：碰撞爆星 —— 轮廓族「带尖刺的星」
    # ⚠ 第一版的四条斜刺**整条都是 'k'（描边色）**，于是在屏幕上渲成四粒深色碎屑而不是橙色的刺
    #    —— 这一条任何两两像素指标都报不出来（它只看"差多少像素"，不看"看起来是什么"），
    #    是 28px 眼验看出来的。现在斜刺是 k-a-k 三像素宽，有芯。
    "conflict": ({"a": (255, 132, 26, 255)}, [
        "....................",
        ".........kk.........",
        "........kaak........",
        "..kk....kaak....kk..",
        "..kak...kaak...kak..",
        "...kak..kaak..kak...",
        "....kkkkkaakkkkk....",
        "....kaaaaaaaaaak....",
        "..kkkaaaaaaaaaakkk..",
        "..kaaaaaaaaaaaaaak..",
        "..kkkaaaaaaaaaakkk..",
        "....kaaaaaaaaaak....",
        "....kkkkkaakkkkk....",
        "...kak..kaak..kak...",
        "..kak...kaak...kak..",
        "..kk....kaak....kk..",
        "........kaak........",
        ".........kk.........",
        "....................",
        "....................",
    ]),
    # 道歉被接受：粗对钩 —— 轮廓族「单条对角 + 短折返」
    # ⚠ 这里试过 4 个候选并按实测选（不是按好看选）。两个扣在一起的环语义更贴"和解"，
    #    但**环在渲染尺度上会塌**：孔径 4 源px → 模糊+错位之后洞消失，整体退化成一条横杠，
    #    与 `invite` 的箭杆撞车 —— 分类器上 90 个 apologize_ok 探针错了 48 个。
    #    细对钩解决了错认（99.1%）但覆盖面积太小，于是在 M1 上贴近 `confront`（那个小白「!」）：134→114。
    #    **加粗之后两头都拿到了**：M1 地板回到 134，top-1 99.1%。覆盖面积是这里的关键自由度。
    "apologize_ok": ({"a": (56, 193, 190, 255)}, [
        "....................",
        "...............kkkk.",
        "..............kaaak.",
        ".............kaaaak.",
        "............kaaaak..",
        "...........kaaaak...",
        "..........kaaaak....",
        ".kkk.....kaaaak.....",
        "kaaak...kaaaak......",
        "kaaaak.kaaaak.......",
        "kaaaaaaaaaak........",
        ".kaaaaaaaaak........",
        "..kaaaaaaaak........",
        "...kaaaaaak.........",
        "....kaaaak..........",
        ".....kaak...........",
        "......kk............",
        "....................",
        "....................",
        "....................",
    ]),
    # 道歉被拒：粗叉 —— 轮廓族「两条对角」
    "apologize_no": ({"a": (198, 38, 66, 255)}, [
        "....................",
        "....................",
        "....................",
        "..kkk........kkk....",
        ".kaaak......kaaak...",
        ".kaaaak....kaaaak...",
        "..kaaaak..kaaaak....",
        "...kaaaaaaaaaak.....",
        "....kaaaaaaaak......",
        ".....kaaaaaak.......",
        ".....kaaaaaak.......",
        "....kaaaaaaaak......",
        "...kaaaaaaaaaak.....",
        "..kaaaak..kaaaak....",
        ".kaaaak....kaaaak...",
        ".kaaak......kaaak...",
        "..kkk........kkk....",
        "....................",
        "....................",
        "....................",
    ]),
}


def render_glyph(name):
    """把字符画渲染成 (w, h, [RGBA 元组...])。**纯函数：不读文件、不看环境、无随机。**

    asset_gate 的"重建独立于出货目录"自证依赖这一点——它重画出来的东西不能有任何一位
    来自 `game/assets/art/emote/`，否则判据退化成 x→x。
    """
    pal, rows = GLYPHS[name]
    h = len(rows)
    w = len(rows[0])
    if any(len(r) != w for r in rows):
        raise ValueError("%s: 字符画行宽不齐（%s）" % (name, sorted({len(r) for r in rows})))
    lut = {".": (0, 0, 0, 0), "k": OUTLINE}
    lut.update(pal)
    px = []
    for r in rows:
        for ch in r:
            if ch not in lut:
                raise ValueError("%s: 字符 %r 不在调色板里" % (name, ch))
            px.append(lut[ch])
    return w, h, px


def encode_png(w, h, px):
    """最小 PNG 编码器（RGBA8）。刻意不依赖 Pillow —— 切图容器里只有 ffmpeg。"""
    raw = bytearray()
    for y in range(h):
        raw.append(0)                      # filter type 0
        for x in range(w):
            raw.extend(px[y * w + x])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def write_glyph(name, out_path):
    w, h, px = render_glyph(name)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(encode_png(w, h, px))


# ── 只在"当配方跑"时才写盘。import 本文件必须零副作用（asset_gate 靠 import 拿 render_glyph）──
if __name__ == "__main__":
    # `ASSET_GATE_HARVEST` 由 asset_gate.harvest_recipes() 预置进 exec 的 globals。
    # 它**只关掉写盘**，不关掉 crop —— 采配方要的正是那几条被拦下的 ffmpeg 命令。
    # 没有这个开关的话：门自己跑一遍就会把它正要判的 9 个出货文件覆盖掉（判据退化成 x→x），
    # 而且 `/game/...` 在宿主机上根本不存在 ⇒ 门会直接抛 FileNotFoundError 而不是判红。
    _HARVEST = bool(globals().get("ASSET_GATE_HARVEST"))
    OUT = sys.argv[1] if (len(sys.argv) > 1 and not sys.argv[1].startswith("-")) else "/game"
    for k, (c, r) in emotes.items():
        crop(EM, f"{OUT}/assets/art/emote/{k}.png", 20, 20, c, r)
    for k, (c, r) in objs.items():
        crop(OW, f"{OUT}/assets/art/obj/{k}.png", 16, 16, c, r)
    if not _HARVEST:
        for k in GLYPHS:
            write_glyph(k, f"{OUT}/assets/art/emote/{k}.png")
    print("sliced", len(emotes), "emotes +", len(objs), "objects; drew",
          0 if _HARVEST else len(GLYPHS), "emotes")
