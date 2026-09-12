#!/usr/bin/env python3
"""place_houses.py — 布景民居选址（docs/186）：只落在【多 seed × 多 N 实跑里从没人站过】的空地上。

用法：python tools/place_houses.py <heat.json> [--out game/assets/art/houses/lots.json]
  heat.json 由 game/bench/walk_heat.gd 产出（"x,y" -> 站格次数）。

选址规则（全部离线、确定性；运行时只读 lots.json，Sim 读不到）：
  - 精灵占的整块格矩形（alpha bbox 向上取整）+ 外扩 1 格：heat==0、非墙/水/树、不压任何 area rect（外扩 1）。
  - 离海岸线 ≥ 6 格（沙滩/步道/码头留给海滨层）。
  - 行优先扫描、按 hash 挑精灵、放下即占位 ⇒ 同一份 heat 逐字节同一份 lots。
"""
import json, sys, math
from PIL import Image

ROOT = __file__.rsplit("tools", 1)[0]
T = 48
ROW = 5
WEIGHT_PEN = {"villa": 45, "townhouse": 15}   # 别让最高最宽的别墅吃满每一行
SPRITES = ["cottage", "whitehouse", "townhouse", "villa", "terrace"]


def bbox_cells(name):
    im = Image.open(f"{ROOT}game/assets/art/houses/{name}.png").convert("RGBA")
    x0, y0, x1, y1 = im.split()[3].getbbox()
    return max(1, math.ceil((x1 - x0) / T)), max(1, math.ceil((y1 - y0) / T))


def h32(x, y, s):
    v = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
    v = (v ^ (v >> 13)) * 0x5bd1e995 & 0xFFFFFFFF
    return v ^ (v >> 15)


def main():
    heat = json.load(open(sys.argv[1]))
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else f"{ROOT}game/assets/art/houses/lots.json"
    m = json.load(open(f"{ROOT}game/data/map.json", encoding="utf-8"))
    W, H = m["width"], m["height"]
    bad = set()
    for k, n in heat.items():
        if n > 0:
            x, y = map(int, k.split(","))
            bad.add((x, y))
    for layer in ("walls", "water", "trees", "blockers"):
        for x, y in m[layer]:
            bad.add((x, y))
    for a in m["areas"].values():
        x, y, w, h = a["rect"]
        for yy in range(y - 1, y + h + 1):
            for xx in range(x - 1, x + w + 1):
                bad.add((xx, yy))
    ocean = {}
    for y in range(H):
        x = W - 1
        while x >= 0 and [x, y] in m["water"]:
            x -= 1
        ocean[y] = x + 1
    for y in range(H):
        for x in range(max(0, ocean[y] - 6), W):
            bad.add((x, y))
    # 外扩 1 格：人贴着房子走过也会被压住
    grown = set()
    for (x, y) in bad:
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                grown.add((x + dx, y + dy))
    size = {s: bbox_cells(s) for s in SPRITES}
    taken = set()
    lots = []
    # 按【底边行】扫：屋底对齐到每 ROW 行一条"街"（底边下一行是巷 lane），同一行里高矮不同的房子都能落
    for b in range(ROW - 2, H, ROW):
        for x in range(W):
            order = sorted(SPRITES, key=lambda s: h32(x, b, SPRITES.index(s) + 7) % 100 + WEIGHT_PEN.get(s, 0))
            for s in order:
                cw, ch = size[s]
                y = b - ch + 1
                if y < 0 or x + cw > W:
                    continue
                cells = [(xx, yy) for yy in range(y, y + ch) for xx in range(x, x + cw)]
                if any(c in grown or c in taken for c in cells):
                    continue
                lots.append({"sprite": s, "x": x, "y": y, "w": cw, "h": ch, "flip": h32(x, y, 3) % 2 == 1})
                for yy in range(y - 1, y + ch + 1):      # 四周一格间距（屋前留一条巷/小院）
                    for xx in range(x - 1, x + cw + 1):
                        taken.add((xx, yy))
                break
    json.dump({"_doc": "docs/186 布景民居落点（tools/place_houses.py 生成，勿手改）", "lots": lots}, open(out, "w"), indent=1)
    print(f"{len(lots)} lots -> {out}")
    g = [["#" if (x, y) in grown else "." for x in range(W)] for y in range(H)]
    for L in lots:
        for yy in range(L["y"], L["y"] + L["h"]):
            for xx in range(L["x"], L["x"] + L["w"]):
                g[yy][xx] = {"cottage":"C","whitehouse":"W","townhouse":"N","villa":"V","terrace":"R"}[L["sprite"]]
    print("\n".join("".join(r) for r in g))


if __name__ == "__main__":
    main()
