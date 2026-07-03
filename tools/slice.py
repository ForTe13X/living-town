#!/usr/bin/env python3
# slice.py — 像素表切图/网格预览（ffmpeg）。给分析用的网格图 + 实际切出的精灵。
#   grid <in> <out> <cellW> <cellH> <upscale>        # 叠青色网格 + 放大，供人/agent 数格子
#   crop <in> <out> <w> <h> <col> <row> [upscale=1]  # 切出 (col,row) 单元到原生(或放大)png
import sys, subprocess
m = sys.argv[1]
if m == "grid":
    inp, out, cw, ch, up = sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
    vf = f"scale=iw*{up}:ih*{up}:flags=neighbor,drawgrid=w={cw*up}:h={ch*up}:t=1:c=cyan@0.85"
    subprocess.run(["ffmpeg", "-y", "-i", inp, "-vf", vf, out], check=True)
elif m == "crop":
    inp, out, w, h, col, row = sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])
    up = int(sys.argv[8]) if len(sys.argv) > 8 else 1
    vf = f"crop={w}:{h}:{col*w}:{row*h}"
    if up > 1:
        vf += f",scale=iw*{up}:ih*{up}:flags=neighbor"
    subprocess.run(["ffmpeg", "-y", "-i", inp, "-vf", vf, out], check=True)
print("ok")
