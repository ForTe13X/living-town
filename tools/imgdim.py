#!/usr/bin/env python3
# 打印若干 PNG 的尺寸（读文件头，无依赖）。用法：python3 /tools/imgdim.py /lib
import os, struct, sys
root = sys.argv[1] if len(sys.argv) > 1 else "/lib"
want = {"Mage-Red.png","Mage-Cyan.png","Archer-Green.png","Archer-Purple.png","Soldier-Blue.png","Soldier-Yellow.png","Warrior-Blue.png","Warrior-Red.png","Character-Base.png","Grass1.png","Grass2.png","Dirt.png","Tree.png","punyworld-overworld-tileset.png","emotes.png","apple_red.png","steak_grilled.png"}
for r, _, fs in os.walk(root):
    for n in fs:
        if n in want and n.lower().endswith(".png"):
            with open(os.path.join(r, n), "rb") as fh:
                b = fh.read(24)
            if b[:8] == b"\x89PNG\r\n\x1a\n":
                w, h = struct.unpack(">II", b[16:24])
                print(f"{w}x{h}  {os.path.relpath(os.path.join(r,n), root)}")
