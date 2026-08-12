#!/usr/bin/env python
# audit_map.py — CI 关卡：直接校验【已提交的】game/data/map.json + agents.json 的导航自洽性。
# 独立于 gen_town.py（后者是生成器）：这里读【落盘数据】→ 抓任何漂移/手改/未重生成导致的地图回归。
# 校验：① typed layers 与 blockers 并集一致；② 全图可达性(BFS)；③ 每个居民 home/spawn 在可达可走格；
#       ④ 每个家具有≥1 可达可走正交邻格(P2-3 交互格必存在，否则饿穿)；⑤ 每个 area 内部可达；
#       ⑥ ≥2 条不相交路线(район对之间，路网冗余)；⑦ 节日对象(festivals.json，可选)坐标合法；
#       ⑧ F1 工位(production.json 的 worksites，可选)：区域归属正确 + 坐标合法 + 有可达交互格 +
#          放上去之后【全图仍连通】；⑨ 工位/产出/岗位三方外键闭合。
#       任一失败 → 退出 1（CI 红）。
import json, sys, os
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def p(*a): return os.path.join(ROOT, "game", "data", *a)

def _opt(name):
    """按契约【可选】的数据文件：缺失即空 dict，绝不报错（缺文件=该子系统关闭=引擎逐字节不变）。
    解析错误不在这里兜：步骤 1 的 lint_data.py 先跑，JSON 语法问题在那儿就红了。"""
    fp = p(name)
    return json.load(open(fp, encoding="utf-8")) if os.path.exists(fp) else {}

def load():
    m = json.load(open(p("map.json"), encoding="utf-8"))
    ag = json.load(open(p("agents.json"), encoding="utf-8"))
    return (m, ag, _opt("festivals.json"), _opt("production.json"), _opt("jobs.json"),
            _opt("interiors.json"), _opt("logistics.json"), _opt("spaces.json"))

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
    m, ag, fe, pr, jb, it, lo, sp = load()
    W, H = int(m["width"]), int(m["height"])
    blk = set((int(x), int(y)) for x, y in m["blockers"])
    fails = []
    # ⑧ F1 工位（docs/48 §一-F1）：production.json 的 worksites 在【运行期】由 Sim._compile_worksites
    #    编译成 town 平面上的真家具 —— 也就是说它们和 map.json 里手写的家具受【完全相同】的导航约束
    #    （Sim.gd:1288 曼哈顿≤1 才 use、_build_nav 把它们那格标成 blocked）。
    #    此前这道门只看 map.json，于是"工位写在别的文件里"= 零 CI 覆盖，正是 B17 灯会那一课的重演。
    #    ★这里有一条 map.json 的家具【没有】的规则：**区域归属**。docs/43 §1.2b 记过本门抓不到
    #      「合法但语义不对」；对工位来说"语义不对"是可判定的——木匠的工作台落在澡堂区里，坐标合法、
    #      可达性合法、渲染也没问题，但分工的空间落点整个是假的。故 area 必须与坐标实际所在的区相符。
    #      Sim._compile_worksites 里有同一条运行期校验（落 push_error → ci.sh 的 scan 判红），
    #      两道门口径必须一致：改这里就要同步改那里。
    ws_raw = pr.get("worksites", []) if isinstance(pr, dict) else []
    if not isinstance(ws_raw, list):
        fails.append("production.worksites 非法（应为数组）: %r" % (ws_raw,)); ws_raw = []
    ws = list(ws_raw)
    # P1-a：有广告位的 logistics node 与 production worksite 在运行时都是阻挡、可交互 world object。
    ws += [n for n in (lo.get("nodes", []) if isinstance(lo, dict) else [])
           if isinstance(n, dict) and isinstance(n.get("advertises"), list) and n.get("advertises")]
    wscells = {}          # (x,y) -> worksite id（放上去之后要一起进 blockers 与交互格校验）
    for i, w in enumerate(ws):
        if not isinstance(w, dict):
            fails.append("worksite #%d 非法（应为对象）: %r" % (i, w)); continue
        wid = str(w.get("id", ""))
        pos = w.get("pos")
        if not wid:
            fails.append("worksite #%d 缺 id" % i); continue
        # 先验形状再 int()：手改的 "12,7" / null / 三元组会让 int() 抛栈，那样 CI 虽也红但读不出错在哪。
        if not (isinstance(pos, (list, tuple)) and len(pos) == 2
                and all(isinstance(v, (int, float)) for v in pos)):
            fails.append("worksite %s pos 缺失/非法（应为 [x,y]）: %r" % (wid, pos)); continue
        c = (int(pos[0]), int(pos[1]))
        if not (0 <= c[0] < W and 0 <= c[1] < H):
            fails.append("worksite %s %s 出界 (%dx%d)" % (wid, c, W, H)); continue
        if c in wscells:
            fails.append("worksite %s 与 %s 同格 %s" % (wid, wscells[c], c)); continue
        wscells[c] = wid
        adv = w.get("advertises", [])
        if not isinstance(adv, list) or not adv:
            fails.append("worksite %s 无 advertises → 它不会产生任何候选，等于没造" % wid)
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

    # P1-c East Ocean physical contract.  Carrier 是 ready manifest 的纯 View 投影，但它的
    # authored berth / route / node 仍必须和地图、物流、affiliate 跨文件闭合。渔台则必须
    # 独立留在 north_pier；两个码头不能靠著者序重叠来“碰巧”通过 area_at。
    carriers = lo.get("carriers", []) if isinstance(lo, dict) else []
    if not isinstance(carriers, list):
        fails.append("logistics.carriers 非法（应为数组）: %r" % (carriers,)); carriers = []
    ocean = set((x, y) for x in range(60, 64) for y in range(0, 48))
    water = set((int(x), int(y)) for x, y in m.get("water", []))
    trees = set((int(x), int(y)) for x, y in m.get("trees", []))
    if not ocean.issubset(water) or trees & ocean:
        fails.append("East Ocean 必须精确占 x60..63×y0..47，且树不得与海域重叠")
    if len(water) != 272 or len(trees) != 130 or len(blk) != 569:
        fails.append("East Ocean typed 数量漂移：water=%d(需272) trees=%d(需130) blockers=%d(需569)"
                     % (len(water), len(trees), len(blk)))
    areas = m.get("areas", {})
    dock = areas.get("dock", {})
    north_pier = areas.get("north_pier", {})
    if (not isinstance(dock, dict) or dock.get("rect") != [56, 7, 4, 2]
            or dock.get("facing") != "east" or dock.get("berth") != [60, 8]
            or dock.get("route_id") != "east_ocean" or dock.get("population_anchor") is not False):
        fails.append("dock 物理锚必须是 rect[56,7,4,2]/east/berth[60,8]/east_ocean/population_anchor=false")
    if (not isinstance(north_pier, dict) or north_pier.get("rect") != [30, 7, 4, 2]
            or north_pier.get("type") != "plaza" or north_pier.get("population_anchor") is not True):
        fails.append("north_pier 必须唯一为 rect[30,7,4,2]/plaza/population_anchor=true")
    def rect_cells(a):
        r = a.get("rect", []) if isinstance(a, dict) else []
        if not (isinstance(r, list) and len(r) == 4):
            return set()
        return set((x, y) for x in range(int(r[0]), int(r[0]) + int(r[2]))
                   for y in range(int(r[1]), int(r[1]) + int(r[3])))
    north_cells = rect_cells(north_pier)
    for aid, area in areas.items():
        if aid != "north_pier" and north_cells & rect_cells(area):
            fails.append("north_pier 与 area '%s' 重叠；area_at 不能依赖著者序消歧" % aid)
    if north_cells & blk or not set((x, 6) for x in range(30, 34)).issubset(water):
        fails.append("north_pier 四格必须全为陆地非 blocker，且北邻 [30..33,6] 必须全为水")
    population_projection = []
    for aid, area in areas.items():
        if not isinstance(area, dict):
            fails.append("area '%s' 非对象，人口 anchor fail-closed" % aid); continue
        if "population_anchor" in area and type(area.get("population_anchor")) is not bool:
            fails.append("area '%s'.population_anchor 必须为 bool，不能靠 truthiness" % aid); continue
        if area.get("population_anchor", True) is False:
            continue
        r = area.get("rect", [])
        if not (isinstance(r, list) and len(r) == 4):
            fails.append("area '%s' rect 非法，人口 anchor fail-closed" % aid); continue
        population_projection.append((str(aid), [int(r[0]) + int(r[2]) // 2, int(r[1]) + int(r[3]) // 2]))
    frozen_population_projection = [
        ("home", [22, 16]), ("cafe", [41, 16]), ("wash", [22, 31]),
        ("work", [41, 31]), ("home2", [12, 6]), ("shop", [52, 8]),
        ("library", [12, 41]), ("plaza", [32, 24]), ("north_pier", [32, 8]),
    ]
    if population_projection != frozen_population_projection:
        fails.append("扩容 anchor ID/顺序/质心必须逐项冻结；got=%r" % population_projection)
    nodes = [n for n in lo.get("nodes", []) if isinstance(n, dict) and n.get("id") == "port_dock"]
    if len(nodes) != 1 or nodes[0].get("pos") != [59, 8] or nodes[0].get("area") != "dock":
        fails.append("port_dock 必须唯一落在 East Ocean 西邻陆格 [59,8] / area=dock")
    lanes = [q for q in lo.get("import_lanes", []) if isinstance(q, dict)]
    if not lanes or any(q.get("route_id") != "east_ocean" or q.get("node") != "port_dock" for q in lanes):
        fails.append("所有 import lane 必须闭合到 east_ocean/port_dock")
    # carriers=[] 是合法 View off-gate；只有声明存在时才校验 projection 记录本身。
    if carriers:
        if len(carriers) != 1 or not isinstance(carriers[0], dict):
            fails.append("首片只允许一个 authored carrier projection")
        else:
            c = carriers[0]
            if (c.get("route_id") != "east_ocean" or c.get("node") != "port_dock"
                    or c.get("berth") != [60, 8] or c.get("facing") != "west"):
                fails.append("carrier 必须闭合到 east_ocean/port_dock/berth[60,8]/west")
    tao = [a for a in ag.get("affiliates", []) if isinstance(a, dict) and a.get("id") == "tao"]
    if len(tao) != 1 or tao[0].get("home") != [58, 8] or tao[0].get("spawn") != [58, 8]:
        fails.append("Tao home/spawn 必须冻结在 East Ocean dock[58,8]")
    piers = [w for w in (pr.get("worksites", []) if isinstance(pr, dict) else [])
             if isinstance(w, dict) and w.get("id") == "bench_pier"]
    if len(piers) != 1 or piers[0].get("pos") != [31, 7] or piers[0].get("area") != "north_pier":
        fails.append("bench_pier 必须唯一冻结在 north_pier 陆格 [31,7]")
    logistics_refs = []
    for section in ("nodes", "import_lanes", "export_lanes", "carriers"):
        for rec in lo.get(section, []):
            if isinstance(rec, dict) and any(rec.get(k) == "north_pier" for k in ("area", "node", "route_id")):
                logistics_refs.append("%s:%s" % (section, rec.get("id", rec.get("good", "?"))))
    if logistics_refs:
        fails.append("north_pier 只承载渔业，不得被 logistics route/node/carrier 引用：%r" % logistics_refs)
    if (59, 8) in blk or (58, 8) in blk or (60, 8) not in water:
        fails.append("Tao/port 必须是 East dock 陆地可走格，carrier berth 必须是水格")
    # P1-i 玩家空间：东港外门必须落在 dock 可走陆格，内门必须落在 9x6 货仓右墙缺口；
    # interiors 只允许纯展示家具（首片不能藉室内悄悄新增经济候选）。
    spaces = sp.get("spaces", {}) if isinstance(sp, dict) else {}
    warehouse = spaces.get("port_warehouse", {}) if isinstance(spaces, dict) else {}
    if (not isinstance(warehouse, dict) or warehouse.get("kind") != "interior"
            or warehouse.get("bounds") != [0, 0, 9, 6] or warehouse.get("floors") != ["1f"]
            or warehouse.get("default_floor") != "1f"):
        fails.append("port_warehouse 必须冻结为 interior bounds[0,0,9,6]/1f")
    portals = sp.get("portals", []) if isinstance(sp, dict) else []
    whdoors = [x for x in portals if isinstance(x, dict) and x.get("id") == "p_port_warehouse_door"]
    expected_from = {"space": "town", "floor": "outdoor", "pos": [57, 8]}
    expected_to = {"space": "port_warehouse", "floor": "1f", "pos": [8, 3]}
    if (len(whdoors) != 1 or whdoors[0].get("kind") != "door"
            or whdoors[0].get("from") != expected_from or whdoors[0].get("to") != expected_to
            or whdoors[0].get("bidirectional") is not True or whdoors[0].get("access") != "public"):
        fails.append("东港货仓门必须唯一闭合 town[57,8]↔port_warehouse[8,3] 且双向/public")
    dock_cells = rect_cells(dock)
    if (57, 8) not in dock_cells or (57, 8) in blk or (57, 8) in wscells or (57, 8) in objcells:
        fails.append("东港货仓外门 [57,8] 必须是 dock 内无碰撞可走格")
    whfloor = (it.get("port_warehouse", {}) if isinstance(it, dict) else {}).get("1f", {})
    furn = whfloor.get("furniture", []) if isinstance(whfloor, dict) else []
    if (not isinstance(whfloor, dict) or whfloor.get("floor") != "stone" or not isinstance(furn, list)
            or not furn or any(not isinstance(x, dict) or x.get("advertises") for x in furn)):
        fails.append("port_warehouse/1f 必须有 stone 纯展示家具且不得 advertises")
    # ⑧ 工位与既有家具/地标/墙水树不得同格 —— 同格 = 一个对象被静默盖住或一格被两次占用。
    lm0 = dict(((int(l["pos"][0]), int(l["pos"][1])), l.get("type", "landmark")) for l in m.get("landmarks", []))
    objby0 = dict(((int(o["pos"][0]), int(o["pos"][1])), o["id"]) for o in m["objects"])
    for c, wid in wscells.items():
        if c in blk:
            fails.append("worksite %s %s 落在 blockers 上（墙/水/树）" % (wid, c))
        if c in objby0:
            fails.append("worksite %s %s 与家具 %s 同格" % (wid, c, objby0[c]))
        if c in lm0:
            fails.append("worksite %s %s 与地标 %s 同格" % (wid, c, lm0[c]))
    # 可走集 = 非 blockers 且非家具格（家具运行期阻挡）。★工位【必须】算进来：
    # Sim._build_nav 对 world.objects 一视同仁地标 blocked，工位来自哪个 json 文件它并不知道。
    # 只查 map.json 的家具 = 在一张比运行期【更宽松】的图上做可达性证明，那种绿是假的。
    walk = set((x, y) for x in range(W) for y in range(H)
               if (x, y) not in blk and (x, y) not in objcells and (x, y) not in wscells)
    # ③ 可达性种子 = 第一个居民 home
    seed = tuple(ag["agents"][0]["home"])
    if seed not in walk:
        print("AUDIT FAIL: seed home %s not walkable" % (seed,)); sys.exit(1)
    reach = bfs(seed, walk)
    # ③ 居民 home/spawn 可达
    all_agents = list(ag.get("agents", [])) + list(ag.get("affiliates", []))
    for a in all_agents:
        for k in ("home", "spawn"):
            c = tuple(a[k])
            if c not in reach: fails.append("agent %s %s %s 不可达" % (a["id"], k, c))
    # ④ 每个家具有≥1 可达可走正交邻格（交互格）
    for o in m["objects"]:
        c = (int(o["pos"][0]), int(o["pos"][1]))
        if not any(n in reach for n in neigh(c)):
            fails.append("object %s %s 无可达交互格 → 会饿穿" % (o["id"], c))
    # ④' 工位同规：没有可达交互格 = 那个岗位的人【永远到不了自己的工位】，
    #     而它的动作又是他唯一的本职动作 ⇒ 产出恒零、#40 活性门会红，但要到跑完 60 天才知道。这里立刻红。
    for c, wid in wscells.items():
        if not any(n in reach for n in neigh(c)):
            fails.append("worksite %s %s 无可达交互格 → 该岗位永远上不了工" % (wid, c))
    # ④'' 放上工位之后全图仍连通：每个工位都是一个新的阻挡格，一格放错就能把某个区切成孤岛。
    if len(reach) != len(walk):
        fails.append("放上 %d 个工位后有 %d 个可走格与主连通块失联（工位挡死了某条唯一通路）"
                     % (len(wscells), len(walk) - len(reach)))
    # ⑤ 每个 area 内部有可达格
    for aid, a in m.get("areas", {}).items():
        r = a.get("rect", [0, 0, 0, 0])
        interior = [(x, y) for x in range(int(r[0]), int(r[0]) + int(r[2]))
                    for y in range(int(r[1]), int(r[1]) + int(r[3])) if (x, y) in reach]
        if not interior: fails.append("area %s 无可达内部格" % aid)

    # ⑧ 区域归属（本门此前【没有】的那条规则，docs/43 §1.2b 点名的"合法但语义不对"）：
    #    工位申报的 area 必须就是它坐标实际落进的那个区。木匠的工作台放在澡堂区里坐标合法、可达合法、
    #    渲染也没问题 —— 但"分工要有地方发生"这句话整个是假的，而上面 ①-⑥ 一条都不会红。
    #    area_at 与 Sim._area_at(Sim.gd) 同源：areas 按【文件书写序】首个命中。
    def area_at(c):
        for aid, a in m.get("areas", {}).items():
            r = a.get("rect", [0, 0, 0, 0])
            if int(r[0]) <= c[0] < int(r[0]) + int(r[2]) and int(r[1]) <= c[1] < int(r[1]) + int(r[3]):
                return aid
        return ""
    for i, w in enumerate(ws):
        if not isinstance(w, dict): continue
        pos = w.get("pos")
        if not (isinstance(pos, (list, tuple)) and len(pos) == 2
                and all(isinstance(v, (int, float)) for v in pos)): continue
        wid, c = str(w.get("id", "")), (int(pos[0]), int(pos[1]))
        real, decl = area_at(c), str(w.get("area", ""))
        if real == "":
            fails.append("worksite %s %s 不在任何 area 内（Sim._compile_worksites 会跳过它 → 该岗位没有工位）" % (wid, c))
        elif decl and decl != real:
            fails.append("worksite %s %s 申报 area='%s' 实际落在 '%s' —— 合法但语义不对" % (wid, c, decl, real))

    # ⑨ 工位 / 岗位 / 产出 三方外键闭合。跨 production.json × jobs.json × map.json 对账，
    #    抓的是"每一件都合法、合起来不成立"那一类：工位挂着一个没人担任的职位、
    #    或持有人的【有效动作】跟工位广告位的动作对不上（⇒ 他站在自己的工位前，_wage_for/_produce_for
    #    双双不认，工资按零工价发、货一件不产，而 60 天跑完只表现为"这个岗位好像不太干活"）。
    if isinstance(pr, dict) and pr:
        titles = {}                                   # title -> holder agent id（jobs.json 优先，与 Sim._merge_prod_jobs 同序同规）
        eff_action = {}                               # title -> 有效动作（job_action 覆盖后）
        merged = dict(jb.get("jobs", {}) if isinstance(jb, dict) else {})
        prod_titles = set()                           # production.json 【自己引入/改写】的职位（见下面 ⑨-末 的门）
        for aid2, j in (pr.get("jobs", {}) if isinstance(pr.get("jobs"), dict) else {}).items():
            if isinstance(j, dict) and aid2 not in merged:
                merged[aid2] = j
                prod_titles.add(str(j.get("title", "")))
        agent_ids = set(a.get("id") for a in all_agents)
        ov = pr.get("job_action", {}) if isinstance(pr.get("job_action"), dict) else {}
        for aid2, j in merged.items():
            if not isinstance(j, dict): continue
            if aid2 not in agent_ids:
                fails.append("岗位挂在不存在的居民 '%s' 上" % aid2); continue
            t = str(j.get("title", ""))
            titles.setdefault(t, aid2)                # 首个命中 = Sim._holder_of_title 的口径
            eff_action.setdefault(t, str(ov.get(t, j.get("action", ""))))
        for t in ov:
            if t.startswith("_"): continue
            if t not in titles: fails.append("job_action 覆盖了一个不存在的职位 '%s'" % t)
        for t, rec in (pr.get("produce", {}) if isinstance(pr.get("produce"), dict) else {}).items():
            if t.startswith("_"): continue
            if t not in titles: fails.append("produce 申报了一个没人担任的职位 '%s' → 该货永远没人产" % t)
            # ★E4d-A 双形状：produce[t] 可为多货 list of {good,amount,inputs?} 或单货 dict。逐条校验每件货 ∈ goods。
            #   单货 dict → [dict] → 单次循环 → 逐字节回改前（同一条 fail 文案/顺序）。按列表著者序遍历。
            for pcr in (rec if isinstance(rec, list) else [rec]):
                if isinstance(pcr, dict) and str(pcr.get("good", "")) not in pr.get("goods", {}):
                    fails.append("produce['%s'] 的货 '%s' 未在 goods 里申报" % (t, pcr.get("good")))
        for a2, rec in (pr.get("consume", {}) if isinstance(pr.get("consume"), dict) else {}).items():
            if a2.startswith("_"): continue
            # ★E4a 双形状：consume[a2] 可为多货 list of {good,amount} 或单货 dict。逐条校验每件货 ∈ goods。
            #   单货 dict → [dict] → 单次循环 → 逐字节回改前（同一条 fail 文案/顺序）。按列表著者序遍历。
            for cr in (rec if isinstance(rec, list) else [rec]):
                if isinstance(cr, dict) and str(cr.get("good", "")) not in pr.get("goods", {}):
                    fails.append("consume['%s'] 的货 '%s' 未在 goods 里申报" % (a2, cr.get("good")))
        for g, gd in (pr.get("goods", {}) if isinstance(pr.get("goods"), dict) else {}).items():
            b = str(gd.get("blame", "")) if isinstance(gd, dict) else ""
            if b and b not in titles:
                fails.append("goods['%s'].blame 指向没人担任的职位 '%s' → 缺货时怪不到任何人" % (g, b))
        wsact = set()
        for w in ws:
            if not isinstance(w, dict): continue
            for a3 in (w.get("advertises", []) if isinstance(w.get("advertises"), list) else []):
                if not isinstance(a3, dict): continue
                act, t = str(a3.get("action", "")), str(a3.get("job", ""))
                wsact.add(act)
                if not t: continue
                if t not in titles:
                    fails.append("worksite %s 的广告位 '%s' 挂在没人担任的职位 '%s' 上 → 这个工位没有人看得见"
                                 % (w.get("id"), act, t))
                elif eff_action.get(t) != act:
                    fails.append("worksite %s：职位 '%s' 的有效动作是 '%s'，工位广告的却是 '%s' —— "
                                 "他站在自己的工位前也不算上工（工资走零工价、一件货都不产）"
                                 % (w.get("id"), t, eff_action.get(t), act))
        # ★ 门的口径：production.json 【自己引入或改写】动作的那些职位（job_action 覆盖的 + production.jobs 新建的）。
        #   F3 实测的洞：原口径只有 `t in ov`（= 只有 job_action 覆盖过的）⇒ **production.jobs 新建的岗位豁免**。
        #   负对照（scratch 副本上逐条跑，见 F3 回执）：删 ws_workbench(木匠∈job_action) 红、删 ws_bakeboard(面点师∈job_action) 红，
        #   而删 ws_sweepcart(环卫工∈production.jobs) **绿**、只删 ws_stall 上『摆摊/商贩』那一条广告位也 **绿**
        #   —— 后两个正是 F1 新建的岗位，恰恰是这条规则最该守住的那两个。
        #   （整个删掉 ws_stall 会红，但红的是 vendor.action '赶集' 那条别的规则 ⇒ 属于**被别的规则偶然遮住**，不是本条起了作用。）
        # ★ 为什么【不是】"对所有职位都查"（派棒者给的方向，F3 实测证伪）：
        #   杂役/渔夫/教书先生的动作是『做活』、咖啡师是『看摊』，它们的满足者是**普通地图家具**
        #   （`desk_1` 在 map.json、`看摊` 在 interiors.json），根本不是 worksite ⇒ 对所有职位都查会让**干净的树立刻变红**。
        #   真正"该管的"是这一条不变量：**production.json 自己造出来的动作，它的满足者也只能是 production.json 自己的工位。**
        #   ⇒ 后来的棒若在 `production.jobs` 里加一个由普通家具满足的岗位，这条会误报——那时该做的是把满足者的全集
        #   （map.json + interiors.json + worksites）都收进来，而**不是**把这道门再关小。
        # ── R1（docs/68 §六）：把上面那句"那时该做的"**现在**做掉，而不是等到它误报 ──────────────
        #   上一段末尾自己写着：正确的修法是把满足者的全集（map.json + interiors.json + worksites）都收进来。
        #   本棒把它收齐了，于是这条规则可以对【所有】职位查，而不只是 production.json 自己造的那些。
        #   为什么现在做：docs/58 §四② 点名的『看摊』正是那个漏网的——**咖啡师是九个岗位里唯一一个
        #   本职动作不由 worksite 满足的**（它由 map.json 的 counter_1 + jobs.json.extra_advertises 注入，
        #   另有 interiors.json 咖啡吧台一份），所以 `gated` 收不到它 ⇒ 今天把那条广告位删掉，**审计全绿**。
        #   ⚠ 两条规则**都要留着，而且强弱不同**（这不是把旧的换掉）：
        #     · `t in gated` ⇒ 满足者必须是 **production.json 自己的 worksite**（强，F3 定的）；
        #     · 其余职位  ⇒ 满足者可以是**全镇任何一个会广告这个动作的对象/家具**（弱，本条新加）。
        #   负对照（隔离副本，逐条实测，见 docs/68 §六）：删掉 jobs.json.extra_advertises 里那条『看摊』
        #   ⇒ 本条红并指名咖啡师；未改动的树上本条绿（无假红）。
        adv_actions = set()
        for o5 in (m.get("objects", []) if isinstance(m.get("objects"), list) else []):
            if not isinstance(o5, dict): continue
            for a5 in (o5.get("advertises", []) if isinstance(o5.get("advertises"), list) else []):
                if isinstance(a5, dict): adv_actions.add(str(a5.get("action", "")))
        for ea in ((jb.get("extra_advertises", []) if isinstance(jb, dict) else []) or []):
            if isinstance(ea, dict): adv_actions.add(str(ea.get("action", "")))
        # interiors.json：带 advertises 的室内家具（Sim._compile_interiors 会把它们编译成 world 对象）
        for _sp, _floors in (it.items() if isinstance(it, dict) else []):
            if not isinstance(_floors, dict): continue
            for _fl, _fd in _floors.items():
                if not isinstance(_fd, dict): continue
                for fu in (_fd.get("furniture", []) if isinstance(_fd.get("furniture"), list) else []):
                    if not isinstance(fu, dict): continue
                    for a6 in (fu.get("advertises", []) if isinstance(fu.get("advertises"), list) else []):
                        if isinstance(a6, dict): adv_actions.add(str(a6.get("action", "")))
        satisfied = adv_actions | wsact
        gated = set(t for t in ov if not str(t).startswith("_")) | prod_titles
        for t, act in eff_action.items():
            if t in gated and act not in wsact:
                fails.append("职位 '%s' 的动作是 '%s'，却没有任何工位广告它 → 这个岗位再也无处上工" % (t, act))
            elif t not in gated and act not in satisfied:
                fails.append("职位 '%s' 的动作是 '%s'，全镇没有任何对象/家具广告它 → 这个岗位无处上工"
                             " (查过 map.objects + interiors 家具 + jobs.extra_advertises + production.worksites)" % (t, act))
        vd = pr.get("vendor", {}) if isinstance(pr.get("vendor"), dict) else {}
        if vd:
            if str(vd.get("title", "")) not in titles:
                fails.append("vendor.title '%s' 没人担任 → 摊位对外那条广告位恒关" % vd.get("title"))
            if str(vd.get("action", "")) not in wsact:
                fails.append("vendor.action '%s' 没有任何工位广告它 → 全镇买不到东西" % vd.get("action"))
        cl = pr.get("cleanliness", {}) if isinstance(pr.get("cleanliness"), dict) else {}
        if cl:
            g = str(cl.get("good", ""))
            gd = pr.get("goods", {}).get(g, {})
            if not isinstance(gd, dict) or int(gd.get("cap", 0)) <= 0:
                fails.append("cleanliness.good '%s' 未申报或 cap<=0 → 效用乘子恒 1.0（机制静默关闭）" % g)
            for aid3 in (cl.get("areas", []) if isinstance(cl.get("areas"), list) else []):
                if str(aid3) not in m.get("areas", {}):
                    fails.append("cleanliness.areas 里的 '%s' 不是一个 area" % aid3)

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
    objby.update(wscells)                    # 工位与家具在运行期是同一类对象 → 节日撞它同样是撞家具
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
    print("audit_map: %dx%d walkable=%d blockers=%d objects=%d worksites=%d agents=%d festival-objects=%d"
          % (W, H, len(walk), len(blk), len(m["objects"]), len(wscells), len(all_agents), nfest))
    if fails:
        print("AUDIT FAIL:"); [print("  -", f) for f in fails[:20]]; sys.exit(1)
    print("AUDIT PASS: typed-layers 一致 + 全可达 + 每家具/工位有交互格 + 工位区域归属正确 + "
          "工位/岗位/产出外键闭合 + ≥2 路线 + 节日对象合法")

if __name__ == "__main__":
    main()
