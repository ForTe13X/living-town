#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""slice_all.py — emote / object / decor 精灵的【配方】。切图部分容器内运行（要 ffmpeg），自绘部分纯 Python。

## 两种配方，一个文件

1. **CC0 切片**（`crop()`）：从 `assets/art/library/` 的 CC0 表按格子裁。obj 3 张 + emote 1 张（`confront`）。
2. **自绘像素**（`GLYPHS` / `SPRITES` + `render_drawn()`）：9 张 emote + 3 张世界精灵，
   每一个像素都写在下面的字符画里。红线 #4 是「CC0 **或自绘**」——这一半走的是"自绘"，不是生成图。

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

## 为什么 obj/bath、obj/arcade、decor/tree_big 也从"切"改成"画"（Wave J · J2）

H1 判前两张「读不出」、第三张「需要重切」。**"重切"这条路我按 I1 的规矩先量了，三张的结论不一样**：

- `obj/bath` 原切 `(4,30)`、`obj/arcade` 原切 `(7,30)`：**两张都没有切错**——四边（左/右/上/下）
  不透明像素**各 0**，正好落在格线上。错的是**题材**：那两格画的是**一口水井**和**一根告示柱**，
  而这个镇子的 `WorldView._draw_landmarks()` 里**已经有**程序化的 `well` 与 `board` 两个地标
  （`board` 就在 `arcade_1` 正下方 2 格：`map.json` `arcade_1=[33,24]`、`board=[33,26]`）。
  ⇒ 症状不是"切歪了"，是"这张 CC0 表里没有浴池、也没有街机"。
  实测：整张表 27×65=1755 格里非空 695 格，其中**自足单格道具**（左/右/上边界不透明像素为 0
  且 ≥20 个不透明像素）**45 格**，逐格看过——0 个浴池、0 个街机，最接近的就是我们正在用的井与告示柱。
- `decor/tree_big` 原切 `(0,7)` 2×2：**这一张确实切错了**，而且可以量：
  右边界 **27/32**、下边界 **29/32** 个不透明像素（= 从别的树冠中间横切过去），
  而把它**包住**的 3×3 区块 `(0,7)-(2,9)` 是自足的（左/右/上 = 0，下 = 10）。
  ⇒ 它是一块 3×3 **区域填充**瓦的碎片。**但重切救不了它**：那块 3×3 画的是"一片林子"不是"一棵树"，
  而整张表里**没有任何一处 2 格高的独立树**——1px 步长扫过全部 404 609 个 32×32 窗口，
  自足的只有 24 个（去重后），每一个都是"两个 1×1 道具上下叠在一起"。表里的树全是 1×1。

⇒ 三张都改为**自绘**，配方是下面 `SPRITES` 里的字符画（与 I1 给 9 张 emote 做的是同一条路）。

## 这份配方与 tools/asset_gate.py 的接口（**改这里之前先读那边**）

`asset_gate.harvest_recipes()` 会
- **exec 本文件**（`__name__="__main__"`）并把 `subprocess.run` 换成探针 ⇒ 采到每一条 ffmpeg `crop`；
- **另外 import 本文件**（`__name__="slice_all"`，靠下面的 `if __name__ == "__main__":` 守卫
  保证 import 无副作用）⇒ 拿到 `GLYPHS` / `SPRITES` / `render_drawn()`，当场重画出那 12 张去比出货文件。

⇒ **不要删掉 `if __name__ == "__main__":` 守卫**（删了 import 就会往磁盘写），
也不要把 `render_drawn()` 改成读文件（它必须是纯函数：门的"重建独立于出货目录"自证靠这一点）。
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

# CC0 切片保留的 obj：counter / bench / desk（H1 真机眼验判 OK，H2 已上门，不动）。
# `bath`(4,30) 与 `arcade`(7,30) 已于 2026-07-30（J2）改为自绘 —— 见文件抬头与下面的 SPRITES。
objs = {"counter": (9, 31), "bench": (4, 31), "desk": (8, 31)}

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


# ── 自绘世界精灵（J2）──────────────────────────────────────────────────────────────
# 键是 "<出货目录>/<文件名>"。与上面 GLYPHS 分开，只因为**尺寸与用途不同**：
# emote 是 20×20 的浮空气泡，这三张是画在世界层里的 16×16 / 32×32 精灵。
# 这三张各自的调色板都写在自己那一项里（`k` 不再由全局 OUTLINE 兜底 —— 树的描边是绿黑，
# 街机是蓝黑，浴桶是棕黑；共用一个 OUTLINE 会把三张的轮廓压成同一个色）。
#
# **尺寸不是随手挑的，是渲染数学定的**（都从 WorldView.gd 读出来，不是猜的）：
#   obj  (`:2290-2291`)：`OBJ_PX = 48` 世界px，**整格**，不缩放不着色 ⇒ 16×16 源图 = 3 源px/格px。
#   tree (`:2251-2256`)：`dw = w*(T/16)`、**底对齐**、乘 `veg` 季节色 ⇒ 32×32 源图 = 96 世界px 高，
#     站在 48px 的格子上、向上探出一格。而 authored 树格的**间距是 48 世界px = 16 源px**
#     ⇒ **任何一行的半宽超过 8 源px，那一行就会和邻居粘在一起**。旧图（区域填充碎片）
#     四边都是断口 ⇒ 156 格拼出来是一张**没有缝、没有轮廓**的壁纸（`map.json` 的 trees 层是
#     两块实心的 6×13 矩形，我数过：156 格、4-邻居度 88 个 4 / 60 个 3 / 8 个 2）。
#     新图把最宽处压到 ±10.5、并让**上半部**（源行 0-15，也就是不会被前一行的树盖住的那一段）
#     收在 ±8 以内 ⇒ 同一块 6×13 里草地的可见比例从 **0.00% 变成 14.06%**，树与树之间有缝。
SPRITES = {
    # 浴池：木桶 + 水 + 蒸汽。**刻意不给它屋顶和立柱**——那正是 `_draw_landmarks()` 里
    # 程序化 `well` 地标的形状，而旧的 CC0 切片就是一口井，两者在同一屏里撞车。
    "obj/bath": ({
        "k": (48, 34, 26, 255),      # 描边
        "w": (198, 148, 92, 255),    # 桶沿·受光
        "W": (146, 100, 60, 255),    # 桶沿·背光
        "a": (168, 230, 240, 255),   # 水·高光
        "A": (86, 182, 214, 255),    # 水
        "D": (44, 122, 168, 255),    # 水·深
        "s": (236, 244, 246, 255),   # 蒸汽
    }, [
        "................",
        "....s.....s.....",
        ".....s...s......",
        "....s.....s.....",
        "...kkkkkkkkkk...",
        "..kwwwwwwwwwwk..",
        ".kwwAAAAAAAAwwk.",
        ".kwAaaAAAAAAAwk.",
        ".kwAAAAAAAaAAwk.",
        ".kwAAAaAAAAAAwk.",
        ".kwDDDDDDDDDDwk.",
        ".kwWWWWWWWWWWwk.",
        "..kWWWWWWWWWWk..",
        "...kkkkkkkkkk...",
        "....k......k....",
        "....k......k....",
    ]),
    # 游戏机：立式街机柜（招牌灯箱 / 屏幕 / 操作台 / 柜脚）。
    # 旧的 CC0 切片是一根**告示柱**，而 `board` 地标就在它正下方 2 格（`map.json`）。
    # 这张的判别轴是**颜色族**：镇上的 obj 贴图全是棕木，只有它是靛蓝 + 青屏 + 黄招牌。
    "obj/arcade": ({
        "k": (26, 24, 40, 255),      # 描边
        "y": (250, 196, 72, 255),    # 招牌灯箱
        "s": (18, 26, 52, 255),      # 屏幕底
        "c": (92, 214, 226, 255),    # 屏幕·青
        "p": (236, 92, 150, 255),    # 屏幕·品红
        "b": (74, 60, 120, 255),     # 柜体·背光
        "B": (106, 90, 162, 255),    # 柜体·受光
        "r": (226, 68, 68, 255),     # 摇杆球
        "o": (250, 176, 60, 255),    # 按键
    }, [
        "................",
        "....kkkkkkkk....",
        "...kyyyyyyyyk...",
        "...kkkkkkkkkk...",
        "...kBssssssbk...",
        "...kBscpccsbk...",
        "...kBsccpcsbk...",
        "...kBsccccsbk...",
        "...kBssssssbk...",
        "...kkkkkkkkkk...",
        "...kBrBoBoBbk...",
        "...kkkkkkkkkk...",
        "...kBBBBBBBbk...",
        "...kBBBBBBBbk...",
        "...kkkkkkkkkk...",
        "....k......k....",
    ]),
    # 阻挡树：一棵完整的针叶树（树梢 → 四层枝 → 树干 → 地面投影）。
    # 旧图是 3×3 区域填充瓦的 2×2 碎片；这张的每一条边都是自足的（左/右/上 = 0 个不透明像素）。
    # 'g' 是 alpha=51 的地面投影 —— 与同目录 CC0 的 tree_small/tree_big 用的是同一档半透明。
    "decor/tree_big": ({
        "k": (26, 46, 30, 255),      # 描边
        "d": (46, 96, 52, 255),      # 针叶·背光（每层枝下沿）
        "m": (78, 140, 68, 255),     # 针叶·中间调
        "l": (128, 184, 86, 255),    # 针叶·受光（光从左上来）
        "t": (108, 76, 46, 255),     # 树干
        "u": (74, 52, 32, 255),      # 树干·背光
        "g": (0, 0, 0, 51),          # 地面投影（半透明，与 CC0 装饰同档）
    }, [
        "................................",
        "...............kk...............",
        "..............kllk..............",
        "..............kllk..............",
        ".............klmmdk.............",
        ".............klmddk.............",
        "............kllmmmdk............",
        "............klmmmddk............",
        "...........kddddddddk...........",
        "............kllmmmdk............",
        "............klmmmddk............",
        "..........kllmmmmddddk..........",
        "..........klllmmmmdddk..........",
        ".........klllmmmmmddddk.........",
        ".........kddddddddddddk.........",
        "..........klllmmmmdddk..........",
        ".........klllmmmmmddddk.........",
        "........klllmmmmmddddddk........",
        ".......klllllmmmmmmmddddk.......",
        ".......kllllmmmmmmmdddddk.......",
        ".......kddddddddddddddddk.......",
        ".......klllllmmmmmmmddddk.......",
        ".......kllllmmmmmmmdddddk.......",
        ".....kllllmmmmmmmmddddddddk.....",
        ".....kkkkkkkkkttukkkkkkkkkk.....",
        ".............kttukk.............",
        ".............kttukk.............",
        ".............kttukk.............",
        ".............kttukk.............",
        ".............kttukk.............",
        ".........ggggkkkkkkgggg.........",
        "...........gggggggggg...........",
    ]),
}


def _render(pal, rows, who, outline=None):
    """字符画 → (w, h, [RGBA 元组...])。**纯函数：不读文件、不看环境、无随机。**"""
    h = len(rows)
    w = len(rows[0])
    if any(len(r) != w for r in rows):
        raise ValueError("%s: 字符画行宽不齐（%s）" % (who, sorted({len(r) for r in rows})))
    lut = {".": (0, 0, 0, 0)}
    if outline is not None:
        lut["k"] = outline
    lut.update(pal)
    px = []
    for r in rows:
        for ch in r:
            if ch not in lut:
                raise ValueError("%s: 字符 %r 不在调色板里" % (who, ch))
            px.append(lut[ch])
    return w, h, px


def render_glyph(name):
    """自绘 emote（20×20，`k` 用全局 OUTLINE）。保留独立入口：I1 的 9 张一个像素都不该动。"""
    pal, rows = GLYPHS[name]
    return _render(pal, rows, name, OUTLINE)


def render_drawn(key):
    """按 "<目录>/<文件名>" 重画任意一张自绘资产。

    asset_gate 的"重建独立于出货目录"自证依赖它是纯函数——重画出来的东西不能有任何一位
    来自 `game/assets/art/`，否则判据退化成 x→x。
    """
    if key in SPRITES:
        pal, rows = SPRITES[key]
        return _render(pal, rows, key)
    d, n = key.split("/", 1)
    if d == "emote" and n in GLYPHS:
        return render_glyph(n)
    raise KeyError("没有名叫 %r 的自绘配方（GLYPHS/SPRITES 里都没有）" % key)


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


def write_drawn(key, out_path):
    w, h, px = render_drawn(key)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(encode_png(w, h, px))


# ── 只在"当配方跑"时才写盘。import 本文件必须零副作用（asset_gate 靠 import 拿 render_drawn）──
if __name__ == "__main__":
    # `ASSET_GATE_HARVEST` 由 asset_gate.harvest_recipes() 预置进 exec 的 globals。
    # 它**只关掉写盘**，不关掉 crop —— 采配方要的正是那几条被拦下的 ffmpeg 命令。
    # 没有这个开关的话：门自己跑一遍就会把它正要判的 12 个出货文件覆盖掉（判据退化成 x→x），
    # 而且 `/game/...` 在宿主机上根本不存在 ⇒ 门会直接抛 FileNotFoundError 而不是判红。
    _HARVEST = bool(globals().get("ASSET_GATE_HARVEST"))
    OUT = sys.argv[1] if (len(sys.argv) > 1 and not sys.argv[1].startswith("-")) else "/game"
    for k, (c, r) in emotes.items():
        crop(EM, f"{OUT}/assets/art/emote/{k}.png", 20, 20, c, r)
    for k, (c, r) in objs.items():
        crop(OW, f"{OUT}/assets/art/obj/{k}.png", 16, 16, c, r)
    _drawn = ["emote/%s" % k for k in GLYPHS] + list(SPRITES)
    if not _HARVEST:
        for key in _drawn:
            write_drawn(key, f"{OUT}/assets/art/{key}.png")
    print("sliced", len(emotes), "emotes +", len(objs), "objects; drew",
          0 if _HARVEST else len(_drawn), "sprites")
