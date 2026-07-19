#!/usr/bin/env python
# gen_town.py — deterministic 64x48 graybox town (town-world P2-2).
# 5 walled districts (1 authored door each) + open grass + tree/water blocker clusters + central plaza.
# Preserves gameplay EXACTLY: reuses existing object dicts (advertises verbatim), same agents, just
# repositioned onto the bigger map. No RNG — fully deterministic layout. Then audits reachability + ≥2 routes.
# Emits game/data/map.json + agents.json (spawns/homes) + patches spaces.json town bounds.
import json, sys, os
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, "game", "data", *a)

W, H = 64, 48
# COMPACT central cluster (short survival treks — corners starve agents on a 64x48 spread); the wide
# periphery stays explorable wilderness. district: name -> (x, y, w, h, door_side, door-offset-from-origin)
DISTRICTS = {
    "home": (18, 13, 9, 7, "S", 4),
    "cafe": (37, 13, 9, 7, "S", 4),
    "wash": (18, 28, 9, 7, "N", 4),
    "work": (37, 28, 9, 7, "N", 4),
}
# 建筑【类型】→ 驱动分类型外观（住宅/商业/公共/工坊/广场）。纯元数据：进 map.json 的 areas[*].type、
# 不进 blockers/digest（渲染读它分风格；导航不看）。plaza=开放广场（无墙）。
BLD_TYPE = {
    "home": "residential", "cafe": "commercial", "wash": "public", "work": "workshop", "plaza": "plaza",
}
PLAZA = (28, 21, 8, 6)   # open central hub (no walls) — all 4 districts hug it (short survival treks)
# object id -> (district, interior-offset from district origin); interior floor = x 1..w-2, y 1..h-2
OBJ_POS = {
    "bed_1": ("home", (2, 2)), "bed_2": ("home", (5, 3)),
    "stove_1": ("cafe", (2, 2)), "counter_1": ("cafe", (5, 3)),
    "bath_1": ("wash", (3, 3)), "desk_1": ("work", (3, 3)),
    "bench_1": ("plaza", (2, 2)), "arcade_1": ("plaza", (5, 3)),
}
# blocker clusters in the OUTER wilderness — route variety without blocking the central survival paths
CLUSTERS = [
    ("tree",  (2, 18, 7, 30)),    # far-left grove
    ("tree",  (56, 18, 61, 30)),  # far-right grove
    ("water", (28, 2, 35, 6)),    # top pond
    ("water", (28, 42, 35, 46)),  # bottom pond
]

def rect_cells(x, y, w, h):
    for j in range(h):
        for i in range(w):
            yield (x + i, y + j)

def build():
    walls, water, trees = set(), set(), set()   # typed layers (rendering); nav blocks the union
    areas = {}
    doors = {}
    labels = {"home": "住宅区", "cafe": "咖啡馆", "wash": "澡堂", "work": "工坊"}
    for name, (x, y, w, h, side, off) in DISTRICTS.items():
        areas[name] = {"label": labels[name], "rect": [x, y, w, h], "type": BLD_TYPE.get(name, "residential")}
        for i in range(w):
            walls.add((x + i, y)); walls.add((x + i, y + h - 1))
        for j in range(h):
            walls.add((x, y + j)); walls.add((x + w - 1, y + j))
        if side == "S":  d = (x + off, y + h - 1)
        elif side == "N": d = (x + off, y)
        elif side == "W": d = (x, y + off)
        else:             d = (x + w - 1, y + off)
        walls.discard(d)                         # carve the door
        walls.discard((d[0], d[1] - 1)); walls.discard((d[0], d[1] + 1))
        doors[name] = d
    areas["plaza"] = {"label": "广场", "rect": list(PLAZA), "type": "plaza"}   # open, no walls
    for kind, (x0, y0, x1, y1) in CLUSTERS:
        s = water if kind == "water" else trees
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                s.add((x, y))
    return walls, water, trees, areas, doors

def obj_abs(oid):
    dist, (ox, oy) = OBJ_POS[oid]
    if dist == "plaza": bx, by = PLAZA[0], PLAZA[1]
    else: bx, by = DISTRICTS[dist][0], DISTRICTS[dist][1]
    return [bx + ox, by + oy]

def walkable_set(blockers):
    return {(x, y) for x in range(W) for y in range(H) if (x, y) not in blockers}

def reachable_from(start, walk):
    seen = {start}; q = deque([start])
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + dx, cy + dy)
            if n in walk and n not in seen:
                seen.add(n); q.append(n)
    return seen

def shortest(start, goal, walk):
    seen = {start: None}; q = deque([start])
    while q:
        c = q.popleft()
        if c == goal:
            path = []; k = c
            while k is not None: path.append(k); k = seen[k]
            return path[::-1]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dx, c[1] + dy)
            if n in walk and n not in seen:
                seen[n] = c; q.append(n)
    return None

def audit(blockers, areas, doors, agents, objects):
    walk = walkable_set(blockers)
    home_int = (DISTRICTS["home"][0] + 2, DISTRICTS["home"][1] + 2)   # a home floor cell
    assert home_int in walk, "home interior start not walkable"
    reach = reachable_from(home_int, walk)
    fails = []
    # every agent spawn/home on reachable floor
    for a in agents:
        for key in ("home", "spawn"):
            c = tuple(a[key])
            if c not in reach: fails.append("agent %s %s %s unreachable" % (a["id"], key, c))
    # every object reachable (adjacent walkable-reachable — object cell itself is goal-exempt)
    for o in objects:
        c = tuple(o["pos"]); adj = [(c[0]+dx, c[1]+dy) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))]
        if not any(a in reach for a in adj): fails.append("object %s %s walled off" % (o["id"], c))
    # every district door + centroid reachable
    for name, a in areas.items():
        r = a["rect"]; cen = (r[0] + r[2] // 2, r[1] + r[3] // 2)
        d = doors.get(name)
        if d and d not in reach: fails.append("district %s door %s unreachable" % (name, d))
    # >=2 routes: between door-EXIT cells (on open grass, not the 1-wide door chokepoint) — remove
    # the interior of route-1 and require a disjoint route-2 (real outdoor path diversity).
    OUT = {"S": (0, 1), "N": (0, -1), "W": (-1, 0), "E": (1, 0)}
    def exit_of(name):
        d = doors[name]; dx, dy = OUT[DISTRICTS[name][4]]
        return (d[0] + dx, d[1] + dy)
    pairs = [("home", "work"), ("cafe", "wash"), ("home", "cafe")]
    for a, b in pairs:
        ea, eb = exit_of(a), exit_of(b)
        sp = shortest(ea, eb, walk)
        if not sp: fails.append("no route %s->%s" % (a, b)); continue
        walk2 = walk - set(sp[1:-1])                      # drop interior of route 1
        if not shortest(ea, eb, walk2): fails.append("only ONE route %s->%s (no 2nd)" % (a, b))
    return fails, len(walk)

def main():
    base_map = json.load(open(p("map.json"), encoding="utf-8"))
    id2obj = {o["id"]: o for o in base_map["objects"]}
    walls, water, trees, areas, doors = build()
    blockers = walls | water | trees        # nav blocks the union; the typed layers are for rendering
    # reposition objects (keep everything else — type/advertises — verbatim)
    objects = []
    for oid in OBJ_POS:
        o = dict(id2obj[oid]); o["pos"] = obj_abs(oid); objects.append(o)
    # agents: put every resident's home+spawn on home-district floor cells (deterministic grid)
    ag = json.load(open(p("agents.json"), encoding="utf-8"))
    hx, hy, hw, hh = DISTRICTS["home"][:4]
    floor = [(hx + 1 + (i % (hw - 2)), hy + 1 + (i // (hw - 2)))
             for i in range((hw - 2) * (hh - 2))]
    occupied = {tuple(obj_abs(o)) for o in OBJ_POS if OBJ_POS[o][0] == "home"}
    slots = [c for c in floor if c not in occupied and c not in blockers]
    for i, a in enumerate(ag["agents"]):
        c = slots[i % len(slots)]
        a["home"] = [c[0], c[1]]; a["spawn"] = [c[0], c[1]]
    # audit BEFORE writing
    fails, nwalk = audit(blockers, areas, doors, ag["agents"], objects)
    print("64x48 town: walkable=%d/%d  blockers=%d  objects=%d  agents=%d"
          % (nwalk, W * H, len(blockers), len(objects), len(ag["agents"])))
    if fails:
        print("AUDIT FAIL:"); [print("  -", f) for f in fails[:20]]; sys.exit(1)
    print("AUDIT PASS: all spawns/objects/doors reachable + >=2 routes verified")
    if "--write" not in sys.argv:
        print("(dry-run; pass --write to emit files)"); return
    out = {"width": W, "height": H, "areas": areas,
           "blockers": sorted([list(b) for b in blockers]),   # nav union — _build_nav reads this (unchanged)
           "walls":  sorted([list(b) for b in walls]),        # typed layers for rendering only
           "water":  sorted([list(b) for b in water]),
           "trees":  sorted([list(b) for b in trees]),
           "objects": objects}
    json.dump(out, open(p("map.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump(ag, open(p("agents.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # patch spaces.json town bounds → 64x48 (spaces is a dict keyed by id; bounds_px reads this → camera free-explores whole town)
    sp = json.load(open(p("spaces.json"), encoding="utf-8"))
    if isinstance(sp.get("spaces"), dict) and "town" in sp["spaces"]:
        sp["spaces"]["town"]["bounds"] = [0, 0, W, H]
    json.dump(sp, open(p("spaces.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # buildings.json rooms are authored at OLD 24x16 coords → orphaned on the 64x48 map. Clear for the
    # graybox (base objects cover every need); real multi-floor interiors get re-authored in P3 (café slice).
    bj = json.load(open(p("buildings.json"), encoding="utf-8"))
    bj["buildings"] = []
    json.dump(bj, open(p("buildings.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("WROTE map.json + agents.json + spaces.json + cleared buildings.json (interiors → P3)")

if __name__ == "__main__":
    main()
