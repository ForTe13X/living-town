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
WEIGHT_PEN = {"villa": 45, "townhouse": 15, "bakery": 30, "creperie": 30}   # 别让最高最宽的别墅/店铺吃满每一行
# docs/189：可重复的民居/小店（每种封顶 MAX_EACH 栋，同一行相邻两栋不用同一张）
SPRITES = ["cottage", "whitehouse", "townhouse", "villa", "terrace",
           "longere", "ochre", "halftimber", "belleepoque", "bakery", "creperie"]
MAX_EACH = {"bakery": 2, "creperie": 2, "belleepoque": 3}
MAX_DEFAULT = 7
# docs/189：全镇只一座的设施 —— 先于民居落位，各按自己的"最合适的地方"打分挑位
#   score(x, y, w, h) 越小越好；W/H 在 main 里绑定
UNIQUES = [
    ("chapel",    lambda x, y, w, h, W, H: abs(x + w / 2 - 32) + abs(y + h - 21)),        # 离广场最近
    ("bandstand", lambda x, y, w, h, W, H: abs(x + w / 2 - 32) + abs(y + h - 30) * 0.7),  # 广场南边
    ("windmill",  lambda x, y, w, h, W, H: y + min(x, W - x) * 0.5),                      # 镇北缘、远离中轴
    ("netshed",   lambda x, y, w, h, W, H: (W - x) + abs(y - 30) * 0.2),                   # 最靠海的一块地
    ("bakery",    lambda x, y, w, h, W, H: abs(x + w / 2 - 22) + abs(y + h - 23)),         # 住宅区边上、去广场的路口
    ("creperie",  lambda x, y, w, h, W, H: (W - x) * 0.6 + abs(y - 16) * 0.5),             # 北滩后面、海堤步道边
]


def bbox_cells(name):
    im = Image.open(f"{ROOT}game/assets/art/houses/{name}.png").convert("RGBA")
    x0, y0, x1, y1 = im.split()[3].getbbox()
    return max(1, math.ceil((x1 - x0) / T)), max(1, math.ceil((y1 - y0) / T))


def h32(x, y, s):
    v = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
    v = (v ^ (v >> 13)) * 0x5bd1e995 & 0xFFFFFFFF
    return v ^ (v >> 15)


NO_GARDEN = {"chapel", "windmill", "bandstand", "netshed", "bakery", "creperie"}
GARDEN_PROPS = [("veg", 2), ("laundry", 2), ("apple", 1), ("hydrangea", 1), ("barrow", 1)]


def plan_gardens(lots, bad, W, H):
    """docs/188：每栋一个园子 = 屋后 1-2 行 + 屋两侧各 1 列（能占多少占多少），全部落在【没人站过】的格上。
    园子不压任何房子、任何巷行、别家的园子。南面敞开（屋前就是巷）。"""
    blocked = set(bad)
    for L in lots:
        for yy in range(L["y"], L["y"] + L["h"] + 1):        # 屋身 + 屋前巷行
            for xx in range(L["x"] - 1, L["x"] + L["w"] + 1):
                if yy < L["y"] + L["h"] and not (L["x"] <= xx < L["x"] + L["w"]):
                    continue                                   # 屋身行只占屋宽（两侧留给园子）
                blocked.add((xx, yy))
    out = []
    for i, L in enumerate(lots):
        if L["sprite"] in NO_GARDEN:
            continue                                           # docs/189：教堂/风车/乐亭/网棚/店铺不带私家园子
        x, y, w, h = L["x"], L["y"], L["w"], L["h"]
        free = lambda cs: all(0 <= cx < W and 0 <= cy < H and (cx, cy) not in blocked for cx, cy in cs)
        back = 0
        for k in (2, 1):
            if free([(xx, yy) for yy in range(y - k, y) for xx in range(x - 1, x + w + 1)]):
                back = k
                break
        left = free([(x - 1, yy) for yy in range(y, y + h)])
        right = free([(x + w, yy) for yy in range(y, y + h)])
        if back == 0 and not (left or right):
            continue
        x0 = x - 1 if (left or back) else x
        x1 = x + w + 1 if (right or back) else x + w
        g = {"house": i, "x0": x0, "y0": y - back, "x1": x1, "y1": y + h,
             "back": back, "left": left, "right": right, "wall": h32(x, y, 29) % 3 == 0, "props": []}
        cells = [(xx, yy) for yy in range(y - back, y) for xx in range(x0, x1)]
        if left: cells += [(x - 1, yy) for yy in range(y, y + h)]
        if right: cells += [(x + w, yy) for yy in range(y, y + h)]
        for c in cells:
            blocked.add(c)
        # 园中物：屋后那一行从左往右按 hash 摆（两格的菜畦/晾衣绳、一格的苹果树/绣球/手推车），两侧列放绣球
        if back:
            by = y - 1
            cx = x0 + 1
            while cx < x1 - 1:
                kind, cw = GARDEN_PROPS[h32(cx, by, 41) % len(GARDEN_PROPS)]
                if cx + cw > x1 - 1:
                    kind, cw = "hydrangea", 1
                if h32(cx, by, 43) % 4 != 0:
                    g["props"].append({"kind": kind, "x": cx, "y": by})
                cx += cw
        for side, sx in ((left, x - 1), (right, x + w)):
            if side and h32(sx, y, 47) % 2 == 0:
                g["props"].append({"kind": "hydrangea", "x": sx, "y": y + h - 1})
        out.append(g)
    return out


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
    size = {s: bbox_cells(s) for s in SPRITES + [u[0] for u in UNIQUES]}
    taken = set()
    lots = []
    count = {}

    def take(s, x, y, cw, ch):
        lots.append({"sprite": s, "x": x, "y": y, "w": cw, "h": ch, "flip": h32(x, y, 3) % 2 == 1 and s not in ("bakery", "chapel")})
        count[s] = count.get(s, 0) + 1
        for yy in range(y - 1, y + ch + 1):      # 四周一格间距（屋前留一条巷/小院）
            for xx in range(x - 1, x + cw + 1):
                taken.add((xx, yy))

    # 设施先落：同样只落在对齐的"街"行上（底边 b ≡ ROW-2 mod ROW），按各自打分挑最好的一块
    for name, score in UNIQUES:
        cw, ch = size[name]
        best = None
        for b in range(ROW - 2, H, ROW):
            y = b - ch + 1
            if y < 0:
                continue
            for x in range(0, W - cw + 1):
                cells = [(xx, yy) for yy in range(y, y + ch) for xx in range(x, x + cw)]
                if any(c in grown or c in taken for c in cells):
                    continue
                sc = score(x, y, cw, ch, W, H)
                if best is None or sc < best[0]:
                    best = (sc, x, y)
        if best:
            take(name, best[1], best[2], cw, ch)
    # 按【底边行】扫：屋底对齐到每 ROW 行一条"街"（底边下一行是巷 lane），同一行里高矮不同的房子都能落
    for b in range(ROW - 2, H, ROW):
        prev = None
        for x in range(W):
            order = sorted(SPRITES, key=lambda s: h32(x, b, SPRITES.index(s) + 7) % 100 + WEIGHT_PEN.get(s, 0))
            for s in order:
                if s == prev or count.get(s, 0) >= MAX_EACH.get(s, MAX_DEFAULT):
                    continue                              # 同一行相邻不重样；每种封顶
                cw, ch = size[s]
                y = b - ch + 1
                if y < 0 or x + cw > W:
                    continue
                cells = [(xx, yy) for yy in range(y, y + ch) for xx in range(x, x + cw)]
                if any(c in grown or c in taken for c in cells):
                    continue
                take(s, x, y, cw, ch)
                prev = s
                break
    gardens = plan_gardens(lots, bad, W, H)
    json.dump({"_doc": "docs/186/188 布景民居 + 园子落点（tools/place_houses.py 生成，勿手改）",
               "lots": lots, "gardens": gardens}, open(out, "w", newline="\n"), indent=1)
    print(f"{len(lots)} lots, {len(gardens)} gardens -> {out}")
    g = [["#" if (x, y) in grown else "." for x in range(W)] for y in range(H)]
    for L in lots:
        for yy in range(L["y"], L["y"] + L["h"]):
            for xx in range(L["x"], L["x"] + L["w"]):
                g[yy][xx] = L["sprite"][0].upper()
    print("\n".join("".join(r) for r in g))


if __name__ == "__main__":
    main()
