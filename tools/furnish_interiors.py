#!/usr/bin/env python
# furnish_interiors.py — docs/193 §三: planned room layouts for the generated interiors.
#
# Replaces the template-dumped furniture of the six generated spaces (home, home2, wash, work, shop,
# library) with hand-planned layouts: real rooms (bedroom / bathroom / kitchen-dining / living corner)
# separated by partition walls, PixelLab furniture sprites, wall decorations, and new affordances
# (toilet, washbasin, bathtub, dining table, sofa, paintings, bookshelf). Also enlarges the bounds of
# those spaces and moves the interior end of their street-door portal.
#
# Furniture entry: {slot, pos:[x,y], size?:[w,h], label?, advertises?}
#   pos is the FRONT-LEFT cell; a size [w,h] footprint covers x..x+w-1, y-h+1..y (it grows up/back).
#   slot "wall" = partition wall cell (blocks nav, drawn as a thin wall); wall-mounted slots sit on row 0.
# This moves the sim golden on purpose (new objects + nav) — the user approved a re-bake (docs/193).
# Validation: every walkable cell is 4-connected to the door; every advertised object has a walkable
# orthogonal neighbour (Sim uses manhattan<=1 to start using an object).
# Usage: python tools/furnish_interiors.py [--check]
import json, os, sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "game", "data")
WALKABLE = {"stairs", "rug", "window"}
PUBLIC_VENUES = {"wash", "library"}   # must match Sim._build_interior_grids WALKABLE_SLOTS


def ad(action, need, amount, duration):
    return [{"action": action, "need": need, "amount": amount, "duration": duration}]


SLEEP = ad("睡觉", "energy", 62, 40)
EAT = ad("吃饭", "hunger", 40, 16)
# docs/193 §七：家里只保留【床 + 沙发（接替旧模板桌子的「歇着」）+ 马桶】三样能用的东西，其余家具只是摆设。
# 实测：把吃/洗/赏画/闲话家常都搬进家里（且数值与外面同一量级）后，居民不再出门——
# 上工归零、镇库全线断链（S0 #40 0/12：produce=40 consume=130），fun/social 触底（#01 11/12 红）。
# 出门的理由必须留在外面：吃在咖啡馆/面包房/可丽饼店的小圆桌上，泡澡在澡堂，看画在澡堂/酒店/咖啡馆/面包房。
REST = ad("歇着", "fun", 28, 18)       # = 旧模板里住宅桌子的那条（沙发接替它），数值不动
TOILET = ad("如厕", "hygiene", 22, 6)
WASH = ad("洗漱", "hygiene", 18, 6)
BATHE = ad("泡澡", "hygiene", 60, 16)
ART = ad("赏画", "fun", 30, 10)
READ = ad("读书", "fun", 30, 20)


def f(slot, x, y, size=None, label=None, adv=None):
    e = {"slot": slot, "pos": [x, y]}
    if size:
        e["size"] = list(size)
    if label:
        e["label"] = label
    if adv:
        e["advertises"] = adv
    return e


def walls(*cells):
    return [f("wall", x, y) for x, y in cells]


# space -> (label, floor material, (w, h), interior door cell, furniture)
LAYOUTS = {
    # 住宅区：合住的一栋——西卧室（两张单人床）、东北浴室（隔墙+门洞）、东南厨房餐厅、西南起居角
    "home": ("一层", "wood", (12, 9), (5, 8), [
        f("window", 2, 0), f("painting_parasol", 5, 0), f("window", 9, 0),
        f("bed", 1, 2, (1, 2), "床", SLEEP), f("plant", 2, 1), f("bed", 3, 2, (1, 2), "床", SLEEP),
        f("dresser", 4, 1), f("wardrobe", 6, 1),
        *walls((7, 1), (7, 2), (7, 3), (7, 4), (9, 4), (10, 4)),
        f("basin", 8, 1), f("toilet", 10, 1, label="马桶", adv=TOILET),
        f("bathtub", 9, 3, (2, 1)),
        f("stove", 10, 5), f("sink", 10, 6),
        f("dining", 8, 7, (2, 2)), f("plant", 10, 7),
        f("sofa", 1, 5, (2, 1), "沙发", REST), f("armchair", 4, 5), f("bookshelf", 6, 5),
        f("rug", 2, 6, (2, 1)), f("lamp", 1, 7), f("plant", 6, 7),
    ]),
    # 民居：一人一户的小屋——双人床、衣柜、角落卫生间、炉灶、小餐桌、扶手椅
    "home2": ("一层", "wood", (9, 7), (4, 6), [
        f("window", 2, 0), f("painting_sea", 4, 0),
        f("bed_double", 1, 2, (2, 2), "床", SLEEP), f("dresser", 3, 1),
        *walls((5, 1), (5, 2), (5, 3)),
        f("toilet", 7, 1, label="马桶", adv=TOILET), f("basin", 7, 2),
        f("lamp", 2, 3),
        f("stove", 1, 5), f("sink", 2, 5), f("bistro", 4, 3),
        f("armchair", 6, 5, label="扶手椅", adv=REST), f("plant", 7, 5),
    ]),
    # 澡堂：西侧两只浴缸、北墙一排洗脸台、东墙两格厕位（隔板），墙上一幅海景
    "wash": ("一层", "stone", (11, 8), (5, 0), [
        f("window", 1, 0), f("painting_sea", 3, 0, label="海景画", adv=ART), f("window", 8, 0),
        f("bathtub", 1, 2, (2, 1), "浴缸", BATHE), f("bathtub", 1, 5, (2, 1), "浴缸", BATHE),
        f("plant", 1, 6), f("shelf", 6, 1),
        f("basin", 7, 1, label="洗脸台", adv=WASH), f("basin", 8, 1, label="洗脸台", adv=WASH),
        f("toilet", 9, 3, label="马桶", adv=TOILET), *walls((9, 4)), f("toilet", 9, 5, label="马桶", adv=TOILET),
        f("bench", 4, 6, (2, 1)), f("plant", 9, 6),
    ]),
    "work": ("一层", "stone", (10, 7), (4, 0), [
        f("window", 2, 0), f("window", 7, 0),
        f("workbench", 1, 2, (2, 1)), f("shelf", 8, 1), f("anvil", 4, 3),
        f("lumber", 1, 5), f("materials", 6, 5), f("plant", 8, 5),
    ]),
    "shop": ("一层", "wood", (9, 7), (4, 6), [
        f("window", 2, 0),
        f("counter", 1, 2), f("grocery", 4, 1), f("grocery", 5, 1), f("grocery", 6, 1), f("grocery", 7, 1),
        f("sacks", 1, 4), f("crate", 2, 4), f("plant", 7, 5),
    ]),
    "library": ("一层", "stone", (9, 7), (4, 6), [   # docs/193 §五：挪到澡堂西邻后街门朝南
        f("painting_parasol", 6, 0),
        f("bookshelf", 1, 1), f("bookshelf", 2, 1, label="书架", adv=READ), f("bookshelf", 6, 1), f("bookshelf", 7, 1),
        f("desk", 2, 4), f("rug", 4, 3), f("desk", 6, 4), f("plant", 3, 1),
        f("lamp", 1, 5), f("armchair", 7, 5),
    ]),
}


# The café is hand-authored (docs/69 AM1 gates read it): only dress its back wall (row 0 is wall, so this
# never touches nav) and widen the 1F bar to the 2-cell counter sprite (its right cell already holds the
# espresso machine, which is blocked anyway).
CAFE_WALL = {
    "1f": [f("painting_sea", 3, 0, label="海景画", adv=ART), f("window", 6, 0)],
    "2f": [f("window", 4, 0), f("painting_parasol", 5, 0)],
}


def dress_cafe(interiors):
    for fl, extra in CAFE_WALL.items():
        furn = interiors["cafe"][fl]["furniture"]
        furn[:] = [e for e in furn if not (e["pos"][1] == 0 and e["slot"] in ("window", "painting_sea", "painting_parasol"))]
        furn.extend(extra)
    for e in interiors["cafe"]["1f"]["furniture"]:
        if e["slot"] == "counter":
            e["size"] = [2, 1]


def cells(e):
    x, y = e["pos"]
    w, h = e.get("size", [1, 1])
    return [(x + i, y - j) for i in range(w) for j in range(h)]


def validate(sid, size, door, furn):
    w, h = size
    blocked = set()
    for x in range(w):
        for y in range(h):
            if x in (0, w - 1) or y in (0, h - 1):
                blocked.add((x, y))
    blocked.discard(tuple(door))
    occupied = {}
    for e in furn:
        for c in cells(e):
            if not (0 <= c[0] < w and 0 <= c[1] < h):
                raise SystemExit(f"{sid}: {e['slot']} cell {c} outside {size}")
            on_wall = c[1] == 0
            if e["slot"] not in WALKABLE and not on_wall:
                if c in occupied:
                    raise SystemExit(f"{sid}: {e['slot']} overlaps {occupied[c]} at {c}")
                occupied[c] = e["slot"]
                blocked.add(c)
    if tuple(door) in occupied:
        raise SystemExit(f"{sid}: door cell blocked")
    seen, q = {tuple(door)}, deque([tuple(door)])
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + dx, cy + dy)
            if 0 <= n[0] < w and 0 <= n[1] < h and n not in blocked and n not in seen:
                seen.add(n); q.append(n)
    free = {(x, y) for x in range(w) for y in range(h) if (x, y) not in blocked}
    if free - seen:
        raise SystemExit(f"{sid}: unreachable walkable cells {sorted(free - seen)}")
    for e in furn:
        if e.get("advertises"):
            x, y = e["pos"]
            if not any((x + dx, y + dy) in seen for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                raise SystemExit(f"{sid}: {e['slot']}@{e['pos']} has no reachable neighbour")
    return len(seen)


def main():
    check = "--check" in sys.argv
    ip, sp = os.path.join(DATA, "interiors.json"), os.path.join(DATA, "spaces.json")
    interiors = json.load(open(ip, encoding="utf-8"))
    spaces = json.load(open(sp, encoding="utf-8"))
    for sid, (label, floor, size, door, furn) in LAYOUTS.items():
        n = validate(sid, size, door, furn)
        print(f"{sid:8s} {size[0]}x{size[1]} door={door} pieces={len(furn)} walkable={n}")
        interiors[sid] = {"1f": {"label": label, "floor": floor, "furniture": furn}}
        spaces["spaces"][sid]["bounds"] = [0, 0, size[0], size[1]]
        if sid in PUBLIC_VENUES:                         # docs/193 §六：镇上居民会为 need 出门来这里（Sim A2 行程）
            spaces["spaces"][sid]["public_venue"] = True
        for p in spaces["portals"]:
            if p.get("kind") == "door" and p["to"]["space"] == sid:
                p["to"]["pos"] = list(door)
    dress_cafe(interiors)
    if check:
        return 0
    for path, d in ((ip, interiors), (sp, spaces)):
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
