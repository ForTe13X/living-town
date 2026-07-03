#!/usr/bin/env python3
# slice_visual.py — 按 visual-tiles workflow 规格，从 overworld tileset 切地形/装饰/建筑（显式像素，支持多格）。
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
# 建筑（区域地标）
tile(f"{B}/building/hut.png", 6, 26)           # 1x1 完整小屋
tile(f"{B}/building/house.png", 4, 33, 1, 4)   # 窄房（teal 顶）
tile(f"{B}/building/shop.png", 12, 26, 2, 4)   # 双开间大屋（地标）
print("sliced terrain+decor+buildings")
