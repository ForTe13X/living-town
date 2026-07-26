#!/usr/bin/env python
# audit_map.py — CI 关卡：直接校验【已提交的】game/data/map.json + agents.json 的导航自洽性。
# 独立于 gen_town.py（后者是生成器）：这里读【落盘数据】→ 抓任何漂移/手改/未重生成导致的地图回归。
# 校验：① typed layers 与 blockers 并集一致；② 全图可达性(BFS)；③ 每个居民 home/spawn 在可达可走格；
#       ④ 每个家具有≥1 可达可走正交邻格(P2-3 交互格必存在，否则饿穿)；⑤ 每个 area 内部可达；
#       ⑥ ≥2 条不相交路线(район对之间，路网冗余)；⑦ 节日对象(festivals.json，可选)坐标合法。
#       任一失败 → 退出 1（CI 红）。
import json, sys, os
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, "game", "data", *a)

def load():
    m = json.load(open(p("map.json"), encoding="utf-8"))
    ag = json.load(open(p("agents.json"), encoding="utf-8"))
    # festivals.json 按契约是【可选】的（缺文件=无节日=引擎逐字节不变，Sim.gd:2416）→ 缺失即空 dict，绝不报错。
    # 解析错误不在这里兜：步骤 1 的 lint_data.py 先跑，JSON 语法问题在那儿就红了。
    fp = p("festivals.json")
    fe = json.load(open(fp, encoding="utf-8")) if os.path.exists(fp) else {}
    return m, ag, fe

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
    m, ag, fe = load()
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
    # ⑦ 节日对象（festivals.json，按契约可选）：此前【零 CI 覆盖】——B17 实测灯会长期坐在 [12,7]（home2 屋内）而全绿。
    # 节日对象经 spawn_object 进 world.objects，于是和家具受同一条到位判据约束（Sim.gd:1241 曼哈顿≤1 才 use）
    # → 没有可达交互格 = 当天 advertise 空转、没人够得着。故沿用④的三条同规校验。
    # 与家具的差别只在阻挡：_build_nav(Sim.gd:2882) 显式跳过 fest_/civic_，节日对象【不进 _blocked】、堵不死谁；
    # 它那格本身可走，而 BFS 只能经邻格进来 → ①③过关时"格自身可达"与"≥1 可达邻格"等价，④的写法直接成立。
    # id 是运行期才生成的（fest_名_day_序），落盘数据里没有 → 用 "节日名 obj#序" 定位。
    objby = dict(((int(o["pos"][0]), int(o["pos"][1])), o["id"]) for o in m["objects"])
    lmby = dict(((int(l["pos"][0]), int(l["pos"][1])), l.get("type", "landmark"))
                for l in m.get("landmarks", []))
    nfest = 0
    fdefs = fe.get("festivals", {}) if isinstance(fe, dict) else {}
    if not isinstance(fdefs, dict):
        fails.append("festivals.json 的 festivals 非法（应为对象）: %r" % (fdefs,)); fdefs = {}
    for fname in sorted(fdefs.keys()):
        objs = fdefs[fname].get("objects", []) if isinstance(fdefs[fname], dict) else None
        if not isinstance(objs, list):
            fails.append("festival %s objects 非法（应为数组）: %r" % (fname, objs)); continue
        for i, od in enumerate(objs):
            nfest += 1
            if not isinstance(od, dict):
                fails.append("festival %s obj#%d 非法（应为对象）: %r" % (fname, i, od)); continue
            pos = od.get("pos")
            # 先验形状再 int()：手改的 "12,7" / null / 三元组会让 int() 抛栈，那样 CI 虽也红但读不出错在哪。
            if not (isinstance(pos, (list, tuple)) and len(pos) == 2
                    and all(isinstance(v, (int, float)) for v in pos)):
                fails.append("festival %s obj#%d pos 缺失/非法（应为 [x,y]）: %r" % (fname, i, pos)); continue
            c = (int(pos[0]), int(pos[1]))
            if not (0 <= c[0] < W and 0 <= c[1] < H):
                fails.append("festival %s obj#%d %s 出界 (%dx%d)" % (fname, i, c, W, H)); continue
            if c in blk:
                fails.append("festival %s obj#%d %s 落在 blockers 上（墙/水/树）" % (fname, i, c))
            if c in objby:
                fails.append("festival %s obj#%d %s 与家具 %s 同格" % (fname, i, c, objby[c]))
            if c in lmby:
                fails.append("festival %s obj#%d %s 与地标 %s 同格" % (fname, i, c, lmby[c]))
            if not any(n in reach for n in neigh(c)):
                fails.append("festival %s obj#%d %s 无可达交互格 → 节日当天没人够得着" % (fname, i, c))
    print("audit_map: %dx%d walkable=%d blockers=%d objects=%d agents=%d festival-objects=%d"
          % (W, H, len(walk), len(blk), len(m["objects"]), len(ag["agents"]), nfest))
    if fails:
        print("AUDIT FAIL:"); [print("  -", f) for f in fails[:20]]; sys.exit(1)
    print("AUDIT PASS: typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线 + 节日对象合法")

if __name__ == "__main__":
    main()
