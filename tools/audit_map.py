#!/usr/bin/env python
# audit_map.py — CI 关卡：直接校验【已提交的】game/data/map.json + agents.json 的导航自洽性。
# 独立于 gen_town.py（后者是生成器）：这里读【落盘数据】→ 抓任何漂移/手改/未重生成导致的地图回归。
# 校验：① typed layers 与 blockers 并集一致；② 全图可达性(BFS)；③ 每个居民 home/spawn 在可达可走格；
#       ④ 每个家具有≥1 可达可走正交邻格(P2-3 交互格必存在，否则饿穿)；⑤ 每个 area 内部可达；
#       ⑥ ≥2 条不相交路线(район对之间，路网冗余)。任一失败 → 退出 1（CI 红）。
import json, sys, os
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, "game", "data", *a)

def load():
    m = json.load(open(p("map.json"), encoding="utf-8"))
    ag = json.load(open(p("agents.json"), encoding="utf-8"))
    return m, ag

def neigh(c):
    x, y = c
    return [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]

def bfs(start, walk):
    seen = {start}; q = deque([start])
    while q:
        for n in neigh(q.popleft()):
            if n in walk and n not in seen:
                seen.add(n); q.append(n)
    return seen

def shortest(a, b, walk):
    prev = {a: None}; q = deque([a])
    while q:
        c = q.popleft()
        if c == b:
            path = []; k = c
            while k is not None: path.append(k); k = prev[k]
            return path[::-1]
        for n in neigh(c):
            if n in walk and n not in prev:
                prev[n] = c; q.append(n)
    return None

def main():
    m, ag = load()
    W, H = int(m["width"]), int(m["height"])
    blk = set((int(x), int(y)) for x, y in m["blockers"])
    fails = []
    # ① typed layers ⊆/= blockers 并集（walls/water/trees 的并集必须恰等于 blockers；否则渲染与导航脱节）
    typed = set()
    for key in ("walls", "water", "trees"):
        for x, y in m.get(key, []):
            typed.add((int(x), int(y)))
    # 地标（well/board）是【可踩装饰】、不进 blockers（挡路会扰动中央生存路径→#01 破）；故不计入并集。
    objcells = set((int(o["pos"][0]), int(o["pos"][1])) for o in m["objects"])
    # blockers = 墙/水/树（家具运行期另加，不在 map.json blockers 里）→ typed 并集应 == blockers
    if typed != blk:
        fails.append("typed layers(walls|water|trees, %d) != blockers(%d): 渲染/导航数据脱节" % (len(typed), len(blk)))
    # 可走集 = 非 blockers 且非家具格（家具运行期阻挡）
    walk = set((x, y) for x in range(W) for y in range(H) if (x, y) not in blk and (x, y) not in objcells)
    # ③ 可达性种子 = 第一个居民 home
    seed = tuple(ag["agents"][0]["home"])
    if seed not in walk:
        print("AUDIT FAIL: seed home %s not walkable" % (seed,)); sys.exit(1)
    reach = bfs(seed, walk)
    # ③ 居民 home/spawn 可达
    for a in ag["agents"]:
        for k in ("home", "spawn"):
            c = tuple(a[k])
            if c not in reach: fails.append("agent %s %s %s 不可达" % (a["id"], k, c))
    # ④ 每个家具有≥1 可达可走正交邻格（交互格）
    for o in m["objects"]:
        c = (int(o["pos"][0]), int(o["pos"][1]))
        if not any(n in reach for n in neigh(c)):
            fails.append("object %s %s 无可达交互格 → 会饿穿" % (o["id"], c))
    # ⑤ 每个 area 内部有可达格
    for aid, a in m.get("areas", {}).items():
        r = a.get("rect", [0, 0, 0, 0])
        interior = [(x, y) for x in range(int(r[0]), int(r[0]) + int(r[2]))
                    for y in range(int(r[1]), int(r[1]) + int(r[3])) if (x, y) in reach]
        if not interior: fails.append("area %s 无可达内部格" % aid)
    # ⑥ ≥2 不相交户外路线：在【门外草地】的出口格之间测冗余（区内单门是刻意的瓶颈，不该算进去）。
    # 门 = 区边框上那个可走缺口；出口 = 门朝区外的可走邻格。删一条路线内部后仍应有第二条不相交路线。
    def door_exit(r):
        x0, y0, bw, bh = int(r[0]), int(r[1]), int(r[2]), int(r[3])
        border = [(x0 + i, y0) for i in range(bw)] + [(x0 + i, y0 + bh - 1) for i in range(bw)] \
               + [(x0, y0 + j) for j in range(bh)] + [(x0 + bw - 1, y0 + j) for j in range(bh)]
        for d in border:
            if d in walk:                                    # 门缺口
                for n in neigh(d):
                    nx, ny = n
                    if n in walk and not (x0 <= nx < x0 + bw and y0 <= ny < y0 + bh):
                        return n                             # 门外草地出口格
        return None
    exits = {}
    for aid, a in m.get("areas", {}).items():
        if aid == "plaza": continue
        e = door_exit(a.get("rect", [0, 0, 0, 0]))
        if e: exits[aid] = e
    pairs = [("home", "work"), ("cafe", "wash"), ("home", "cafe")]
    for a, b in pairs:
        if a not in exits or b not in exits: continue
        sp = shortest(exits[a], exits[b], walk)
        if not sp: fails.append("无路线 %s->%s" % (a, b)); continue
        walk2 = walk - set(sp[1:-1])
        if not shortest(exits[a], exits[b], walk2):
            fails.append("只有一条户外路线 %s->%s（缺冗余）" % (a, b))
    print("audit_map: %dx%d walkable=%d blockers=%d objects=%d agents=%d"
          % (W, H, len(walk), len(blk), len(m["objects"]), len(ag["agents"])))
    if fails:
        print("AUDIT FAIL:"); [print("  -", f) for f in fails[:20]]; sys.exit(1)
    print("AUDIT PASS: typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线")

if __name__ == "__main__":
    main()
