#!/usr/bin/env python
# relocate_buildings.py — docs/193 §五: pull the three outlying walled buildings (home2, shop, library) in
# from the map corners to sit beside the central districts (user: "building complex and district, more
# close to each other"). gen_town.py placed them "in the far wilderness" on purpose; that choice is reversed
# here, knowingly moving the sim golden (user-approved re-bake).
#
# For each building: the old wall ring leaves walls+blockers, the new ring (minus its door) joins them,
# areas[].rect / doors[] / the street-door portal / buildings.json room rects / agent homes inside follow.
# Refuses to place a ring on trees, water, other walls, areas (+1 margin), objects or agent homes.
# Usage: python tools/relocate_buildings.py [--check]
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "game", "data")
# id -> (new x, new y, door side, door offset along that side)
MOVES = {
    "home2": (11, 14, "S", 3),     # was (9,4): now the west neighbour of 住宅区, one lane (x=17) between
    "shop": (47, 13, "S", 3),      # was (49,5): now the east neighbour of the café, lane x=46
    "library": (11, 29, "S", 3),   # was (9,38): now terraced onto the bath-house's west wall
}


def load(name):
    return json.load(open(os.path.join(D, name), encoding="utf-8"))


def save(name, d):
    with open(os.path.join(D, name), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)
        fh.write("\n")


def ring(x, y, w, h):
    return {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)
            if xx in (x, x + w - 1) or yy in (y, y + h - 1)}


def door_cell(x, y, w, h, side, off):
    return {"S": (x + off, y + h - 1), "N": (x + off, y), "W": (x, y + off), "E": (x + w - 1, y + off)}[side]


def main():
    check = "--check" in sys.argv
    m, spaces, blds, agents = load("map.json"), load("spaces.json"), load("buildings.json"), load("agents.json")
    walls = {tuple(c) for c in m["walls"]}
    blockers = {tuple(c) for c in m["blockers"]}
    trees = {tuple(c) for c in m["trees"]}
    water = {tuple(c) for c in m["water"]}
    homes = {tuple(a[k]) for a in agents["agents"] for k in ("home", "spawn") if a.get(k)}
    objs = {tuple(o["pos"]) for o in m["objects"]}
    old_face = {d["name"]: d["face"] for d in m["doors"]}
    room_rects = {}
    for bid, (nx, ny, side, off) in MOVES.items():
        a = m["areas"][bid]
        ox, oy, w, h = a["rect"]
        dx, dy = nx - ox, ny - oy
        old_ring = ring(ox, oy, w, h)
        walls -= old_ring
        blockers -= old_ring
        new_ring = ring(nx, ny, w, h)
        dc = door_cell(nx, ny, w, h, side, off)
        cells = {(xx, yy) for yy in range(ny, ny + h) for xx in range(nx, nx + w)}
        for oid, oa in m["areas"].items():         # rects may touch (terraced walls), never overlap
            x, y, ww, hh = oa["rect"]
            if oid != bid and cells & {(xx, yy) for yy in range(y, y + hh) for xx in range(x, x + ww)}:
                raise SystemExit(f"{bid}: overlaps area {oid}")
        for name, s in (("trees", trees), ("water", water), ("objects", objs), ("homes", homes)):
            if cells & s:
                raise SystemExit(f"{bid}: new rect hits {name} at {sorted(cells & s)[:4]}")
        outside = {"S": (dc[0], dc[1] + 1), "N": (dc[0], dc[1] - 1), "W": (dc[0] - 1, dc[1]), "E": (dc[0] + 1, dc[1])}[side]
        if outside in blockers or outside in trees or outside in water:
            raise SystemExit(f"{bid}: door {dc} opens onto a blocked cell {outside}")
        walls |= new_ring - {dc}
        blockers |= new_ring - {dc}
        a["rect"] = [nx, ny, w, h]
        for d in m["doors"]:
            if d["name"] == bid:
                d["pos"] = list(dc)
                d["face"] = side
        for p in spaces["portals"]:
            if p.get("kind") == "door" and p["to"]["space"] == bid and p["from"]["space"] == "town":
                p["from"]["pos"] = list(dc)
        old_side = old_face[bid]
        for b in blds["buildings"]:
            if b["id"] == bid:
                for r in b["rooms"]:
                    x, y, rw, rh = r["rect"]
                    y += dy
                    if old_side == "N" and side == "S":
                        y -= 1                     # the entry band moves from the top row to the bottom row
                    room_rects[r["id"]] = [x + dx, y, rw, rh]
        for ag in agents["agents"]:
            for k in ("home", "spawn"):
                p = ag.get(k)
                if p and ox <= p[0] < ox + w and oy <= p[1] < oy + h:
                    ag[k] = [p[0] + dx, p[1] + dy]
        print(f"{bid}: ({ox},{oy}) -> ({nx},{ny}) door {dc} {side}")
    # keep authored order (remaining cells in place, new ring cells appended) so the diff stays readable
    for key, final in (("walls", walls), ("blockers", blockers)):
        kept = [c for c in m[key] if tuple(c) in final]
        have = {tuple(c) for c in kept}
        m[key] = kept + [list(c) for c in sorted(final - have, key=lambda c: (c[1], c[0]))]
    if check:
        return 0
    save("map.json", m); save("spaces.json", spaces); save("agents.json", agents)
    # buildings.json is hand-formatted (one room per line): patch the room rects in place, don't re-dump
    bp = os.path.join(D, "buildings.json")
    txt = open(bp, encoding="utf-8").read()
    for rid, rect in room_rects.items():
        txt, n = re.subn(r'("id": "%s",\s+"rect": )\[[^\]]*\]' % re.escape(rid), lambda mm: mm.group(1) + json.dumps(rect), txt)
        assert n == 1, rid
    open(bp, "w", encoding="utf-8", newline="\n").write(txt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
