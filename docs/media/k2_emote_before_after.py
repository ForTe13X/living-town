#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 docs/media/k2_emote_before_after.png（README 里那张表情前后对照图）。

    在【仓库根目录】跑：  python docs/media/k2_emote_before_after.py

它和这张图放在一起，是为了让图**可重建**——本仓库对"没有配方的图"的态度写在
`tools/asset_gate.py` 抬头。⚠️ 但请注意：**这是文档插图，不是美术资产**，
它不出货、不进任何一道门；出货像素归 CI 步骤 2d 的 `asset_gate.py` 管。

数据全部来自已提交的产物，无手工数字：
  · 「改前」= `git show cf2ea99~1:game/assets/art/emote/*.png`（I1 那一棒之前的出货像素）
  · 「改后」= 当前出货 `game/assets/art/emote/*.png`
  · 28 px = tools/asset_gate.DISTINCT_RENDER_PX（40 EMOTE_PX × 0.45 LABEL_MIN_ZOOM × 1.583 真机缩放）
  · 草地底色 = tools/asset_gate.GRASS
"""
import subprocess, io, sys
from PIL import Image, ImageDraw

sys.path.insert(0, "tools")
from asset_gate import DISTINCT_RENDER_PX as PX, GRASS  # noqa: E402

NAMES = ["greet", "give", "gossip", "invite", "meet_fulfilled",
         "meet_broken", "conflict", "apologize_ok", "apologize_no", "confront"]
OLD_REF = "cf2ea99~1"          # I1 之前那一棵树
BIG = 8                        # 「给读者看」的放大倍数


def old_png(name):
    raw = subprocess.check_output(
        ["git", "show", "%s:game/assets/art/emote/%s.png" % (OLD_REF, name)])
    return Image.open(io.BytesIO(raw)).convert("RGBA")


def new_png(name):
    return Image.open("game/assets/art/emote/%s.png" % name).convert("RGBA")


def on_grass(img, px):
    """按 WorldView 的方式合成：NEAREST 缩到上屏尺寸，压在草地色上。"""
    bg = Image.new("RGBA", (px, px), GRASS + (255,))
    bg.alpha_composite(img.resize((px, px), Image.NEAREST))
    return bg


def strip(imgs, px, gap):
    w = len(imgs) * (px + gap) + gap
    out = Image.new("RGBA", (w, px + 2 * gap), (0, 0, 0, 0))
    for i, im in enumerate(imgs):
        out.alpha_composite(im, (gap + i * (px + gap), gap))
    return out


# 两档：① 玩家能看到的最小尺寸 28 px；② 8x 给读者看
# 标题只用 ASCII —— PIL 的内建位图字体没有 CJK 字形，写中文会渲成豆腐块。
SMALL, LARGE = PX, 20 * BIG   # 源图 20x20 ⇒ 8x = 160
GAP, PAD, HDR, LBL = 10, 24, 30, 26

BANDS = [
    ("BEFORE   shipped pixels before I1 (git %s)   -   %d device px = the smallest size a player ever sees"
     % (OLD_REF, SMALL), old_png, SMALL),
    ("BEFORE   the same ten at %dx   -   nine of the ten are one and the same white bubble" % BIG,
     old_png, LARGE),
    ("AFTER    shipped pixels today   -   the same %d device px" % SMALL, new_png, SMALL),
    ("AFTER    the same ten at %dx   -   ten different outline families "
     "(hand / box / three dots / arrow / heart / broken heart / burst / ! / tick / cross)" % BIG,
     new_png, LARGE),
]

cols = len(NAMES)
w = PAD * 2 + cols * LARGE + (cols - 1) * GAP
h = PAD * 2 + sum(HDR + px + 6 + LBL for _, _, px in BANDS)
canvas = Image.new("RGBA", (w, h), (34, 38, 34, 255))
d = ImageDraw.Draw(canvas)

y = PAD
for title, getter, px in BANDS:
    d.text((PAD, y), title, fill=(220, 220, 210, 255))
    y += HDR
    for i, n in enumerate(NAMES):
        x = PAD + i * (LARGE + GAP) + (LARGE - px) // 2
        canvas.alpha_composite(on_grass(getter(n), px), (x, y))
    y += px + 6
    for i, n in enumerate(NAMES):
        d.text((PAD + i * (LARGE + GAP), y), n, fill=(150, 155, 150, 255))
    y += LBL

canvas.convert("RGB").save("docs/media/k2_emote_before_after.png")
print("wrote docs/media/k2_emote_before_after.png  %dx%d" % canvas.size)
