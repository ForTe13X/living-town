#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""R12 ③：往两个提交锚的 _meta.rebake_history 各补一条（日期 + 为什么）。
标准 note 字段每次烘都会被覆盖，rebake_history 不会（docs/41 §3-3）。"""
import io, json

NOTE = (
    "2026-08-01 Wave U · U1 把 T1 的镇库回拉（production.stock_pull）【打开】⇒ 世界轨迹【蓄意】移动"
    "（docs/79 §一 / docs/47 R12）。"
    "为什么：#40 的红在 60 个 seed 上是基率不是特例（docs/72），根因是产出侧【开环】"
    "——Sim._object_candidates 给工位广告打分时一项都不读 town_stock，空仓与满仓的分数逐位相同（docs/76）。"
    "T1 做出了机制但键没进出货数据，因为打开它会把 ci.sh 4a（N=16）顶红。"
    "U1 找到的原因不是 T1 猜的那个（『6 个货位有 2 个被豆子/话本永久占着』——在 N=16 上豆子只占 7/12，"
    "而且用干预证伪了：把那两种货的产量砍到真的会缺，key 开着时红格数一个都没少），"
    "而是 T1 §9.2 自己推出来的那条约束没有任何固定的 lo 能满足："
    "work_pull_mult(N)·lo/den < 1 要对所有 N 成立就得 lo<=66。"
    "改动：Sim._object_candidates 里【人口项与库存项不叠加】（wp_applied 时把 stock_pull 乘子除以 work_pull_mult）"
    "⇒ 合成的工作吸引力乘子恒为 [lo/den, hi/den]、与 N 无关；"
    "并把 production.json 的 stock_pull{hi:110, lo:90, den:100} 写进出货数据。"
    "★N=12 上 work_pull_mult 恒为 1.0 ⇒ U1 那四行一条指令都不多跑 ⇒ 与只开 T1 的键【逐字节相同】"
    "（隔离副本实测 seeds 1-12 12/12 + seeds 13-60 48/48 digest 相同）。"
    "★摘掉 production.stock_pull 键 ⇒ 整条机制关闭、逐字节回到 Wave T 末（缺数据即零扰动）。"
    "★hi==lo==den ⇒ f≡1.0 逐位（零假设对照）。"
    "验收（门自己的判决行，全部多 seed 网格）："
    "--seeds 49-60 PASS ✅ #40 12/12（未改动的树上这一格是 FAIL ❌，docs/72 §1.3）；"
    "--seeds 13-30 PASS ✅ 18/18；--seeds 31-60 PASS ✅ 29/30（首违 seed 44 豆子 0.50）；"
    "4a（N=16 seeds 1-12）PASS ✅ 12/12，零缺货货数 max 回到 3（= 未改动树的余量）、最差货 min 0.627（未改动树 0.556）。"
    "硬不变量：12/12 · 18/18 · 30/30 · 12/12(N=16) 全绿，饿穿 0。"
    "剩余边界（两条，都据实记在 docs/80）：①seed 44 豆子 0.495 仍低于 SUPPLY_FLOOR 0.005（软门过，T1 自定的 0/48 未达标）；"
    "②N=24 seeds 1-12 从 0/12 回归到 2/12（ci.sh 今天不跑这一格；而 N=60 seeds 1-6 从 4/6 改善到 0/6）。"
    "判据一个字节没动（Invariants.gd 未改），SUPPLY_FLOOR/SUPPLY_MIN_DEMAND/SUPPLY_MIN_DAYS 与软通过率门均未放宽。"
)

for p in ["game/bench/golden_digests.json", "game/bench/modelpath_anchor.json"]:
    d = json.load(io.open(p, encoding="utf-8"))
    m = d.setdefault("_meta", {})
    h = m.setdefault("rebake_history", [])
    if not any(s.startswith("2026-08-01 Wave U · U1") for s in h):
        h.append(NOTE)
    io.open(p, "w", encoding="utf-8", newline="\n").write(
        json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print("%s  rebake_history 条数 = %d" % (p, len(h)))
