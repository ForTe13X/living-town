#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1：把 #40 的【两条臂】分开报（判据未改动：下限 SUPPLY_FLOOR=0.50；上限 零缺货*2 > 进判决）。
逐 seed，不给均值；极值连并列一起报。用法：arms.py a.jsonl [b.jsonl ...]"""
import json, io, sys

FLOOR = 0.50
JOBS = ["面点师", "渔夫", "咖啡师", "杂役", "木匠", "教书先生", "环卫工", "泥瓦匠"]


def load(p):
    return {r["seed"]: r for r in (json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip())}


def arms(r):
    g = [(k, v) for k, v in r["final"]["goods"].items() if v.get("gated")]
    ns = [k for k, v in g if v["shortage_days"] == 0]
    lo = [(k, v["rate"]) for k, v in g if v["rate"] < FLOOR]
    worst = min(g, key=lambda kv: kv[1]["rate"])
    return worst[0], worst[1]["rate"], len(ns), len(g), ns, bool(lo), len(ns) * 2 > len(g)


def main():
    files = sys.argv[1:]
    data = [(f, load(f)) for f in files]
    seeds = sorted(set(data[0][1]))
    print("seed | " + " | ".join("%-38s" % f.split("/")[-1] for f, _ in data))
    print("     | " + " | ".join("%-38s" % "最差货 rate | 零缺货/进判决 | 下/上臂" for _ in data))
    nred = [0] * len(data)
    for s in seeds:
        cells = []
        for i, (f, d) in enumerate(data):
            if s not in d:
                cells.append("%-38s" % "-")
                continue
            wg, wr, nz, ng, ns, a_lo, a_up = arms(d[s])
            red = a_lo or a_up
            nred[i] += 1 if red else 0
            cells.append("%-4s %.3f | %d/%d | %s%s%-4s" % (
                wg, wr, nz, ng, "下" if a_lo else "-", "上" if a_up else "-",
                " RED" if red else ""))
        print("%4d | %s" % (s, " | ".join(cells)))
    print("-" * 40)
    for i, (f, d) in enumerate(data):
        print("%-40s #40 红 %d/%d" % (f, nred[i], len(seeds)))
    # 逐岗位在班完成 + 社交发起
    print()
    print("=== 逐岗位在班完成（展布 min..max，逐 seed 顺序同上）===")
    for j in JOBS:
        row = []
        for f, d in data:
            v = [d[s]["work_by_title"].get(j, 0) for s in seeds if s in d]
            row.append("%2d..%2d" % (min(v), max(v)))
        print("  %-6s %s" % (j, "   ->   ".join(row)))
    print()
    print("=== 逐动作开用（社交/玩耍/吃饭：本改动有没有把社交挤掉）===")
    acts = set()
    for f, d in data:
        for s in d:
            acts |= set(d[s]["attempts_by_action"])
    for a in sorted(acts):
        row = []
        for f, d in data:
            v = [d[s]["attempts_by_action"].get(a, 0) for s in seeds if s in d]
            row.append("%4d..%4d" % (min(v), max(v)))
        print("  %-5s %s" % (a, "   ->   ".join(row)))
    print()
    print("=== 逐货：满足率展布 / 全年零缺货的 seed 数 ===")
    goods = ["口粮", "柴薪", "屋瓦", "豆子", "话本", "整洁"]
    for g in goods:
        row = []
        for f, d in data:
            rs = [d[s]["final"]["goods"][g]["rate"] for s in seeds if s in d and d[s]["final"]["goods"][g].get("gated")]
            zs = [s for s in seeds if s in d and d[s]["final"]["goods"][g].get("gated") and d[s]["final"]["goods"][g]["shortage_days"] == 0]
            row.append("%.3f..%.3f 零缺%2d" % (min(rs), max(rs), len(zs)) if rs else "-")
        print("  %-4s %s" % (g, "   ->   ".join(row)))


main()
