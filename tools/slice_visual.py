#!/usr/bin/env python3
# slice_visual.py — 按 visual-tiles workflow 规格，从 overworld tileset 切地形/装饰（显式像素，支持多格）。
# （建筑那三张已于 2026-07-30 删除，见文件末尾。）
import subprocess, os
OW = "/game/assets/art/library/punyworld-overworld/punyworld-overworld-tileset.png"
T = 16
def tile(out, col, row, wt=1, ht=1):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-i", OW, "-vf", f"crop={wt*T}:{ht*T}:{col*T}:{row*T}", out],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
B = "/game/assets/art"
# 地形（16x16 满铺）
tile(f"{B}/terrain/grass_a.png", 0, 0)
tile(f"{B}/terrain/grass_b.png", 1, 0)
tile(f"{B}/terrain/grass_flowers.png", 2, 0)
tile(f"{B}/terrain/dirt.png", 11, 1)
tile(f"{B}/terrain/water.png", 18, 11)
# 装饰
tile(f"{B}/decor/tree_small.png", 8, 7)
tile(f"{B}/decor/tree_big.png", 0, 7, 2, 2)
tile(f"{B}/decor/bush.png", 0, 26)
tile(f"{B}/decor/flower_red.png", 2, 27)
tile(f"{B}/decor/flower_yellow.png", 2, 26)
tile(f"{B}/decor/rock.png", 1, 26)
tile(f"{B}/decor/stump.png", 1, 27)
tile(f"{B}/decor/mushroom.png", 1, 31)
# ── 建筑（区域地标）—— I2 2026-07-30 删除 ────────────────────────────────────────────────
# 原来这里有三行：
#     tile(f"{B}/building/hut.png",   6, 26)          # 1x1 完整小屋
#     tile(f"{B}/building/house.png", 4, 33, 1, 4)    # 窄房（teal 顶）
#     tile(f"{B}/building/shop.png", 12, 26, 2, 4)    # 双开间大屋（地标）
# 三张 png 与 `Art.building_tex()` 一并删了，理由见 docs/09 §1.1：消费者 `841d4c4`（2026-07-15）
# 就删掉了，那条 commit 把"每个区角一张 1 格 hut"列为用户报的「比例失调」头号成因
# （1 格贴图 = 1 格居民）；替代品是 WorldView 里**程序化**画的建筑，不用贴图。
# 另两张更不能用：`house`(1x4) / `shop`(2x4) 是从图集竖着切下来的**多格条带**，四边都是断口
# ——与 H1 判 decor/tree_big「需要重切」是同一种病。
# ⚠️ **别把这三行加回来**：`tools/asset_gate.py` 的 `check_deleted()` 会红（它就是为了拦这件事写的）。
#    真要做建筑贴图，先读 841d4c4，再把尺度问题解决掉，然后走"新素材必须显式进 GATED"那条路。
print("sliced terrain+decor")
