#!/usr/bin/env python3
# slice_all.py — 按 art-deepen workflow 的规格，从 CC0 表切出 emote / object 精灵。容器内运行。
import subprocess, os
def crop(inp, out, w, h, col, row):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-i", inp, "-vf", f"crop={w}:{h}:{col*w}:{row*h}", out],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

EM = "/game/assets/art/library/puny-emotes/emotes.png"                                  # 140x120, 20px cells
OW = "/game/assets/art/library/punyworld-overworld/punyworld-overworld-tileset.png"     # 16px tiles

emotes = {"greet": (3, 1), "give": (0, 3), "gossip": (0, 1), "invite": (2, 5),
          "meet_fulfilled": (2, 3), "meet_broken": (5, 3), "conflict": (6, 1),
          "confront": (3, 2), "apologize_ok": (5, 5), "apologize_no": (0, 4)}
for k, (c, r) in emotes.items():
    crop(EM, f"/game/assets/art/emote/{k}.png", 20, 20, c, r)

objs = {"bath": (4, 30), "counter": (9, 31), "bench": (4, 31), "desk": (8, 31), "arcade": (7, 30)}
for k, (c, r) in objs.items():
    crop(OW, f"/game/assets/art/obj/{k}.png", 16, 16, c, r)

print("sliced", len(emotes), "emotes +", len(objs), "objects")
