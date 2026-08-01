#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S1：两份 ScaleSupply jsonl 的逐项对照（同 seed 段）。用法：cmp.py base.jsonl var.jsonl [seeds]"""
import json, io, sys

GOODS = ["口粮", "柴薪", "屋瓦", "豆子", "话本", "整洁"]
JOBS = ["面点师", "渔夫", "杂役", "木匠", "咖啡师", "教书先生", "环卫工", "泥瓦匠"]


def L(p):
    return {r["seed"]: r for r in (json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip())}


def main():
    base, var = L(sys.argv[1]), L(sys.argv[2])
    seeds = sorted(set(base) & set(var))
    if len(sys.argv) > 3:
        seeds = [int(x) for x in sys.argv[3].split(",")]
    print("对照 seeds=%s   基线=%s   变体=%s" % (seeds, sys.argv[1], sys.argv[2]))
    print("\n=== 逐岗位【在班完成】（供给侧有没有被顺手改动）===")
    for j in JOBS:
        print("  %-5s %s -> %s" % (j, [base[s]["work_by_title"].get(j, 0) for s in seeds],
                                   [var[s]["work_by_title"].get(j, 0) for s in seeds]))
    print("\n=== 逐货：满足率 / 产出件数 / 需求件数 / 断供天数 ===")
    for g in GOODS:
        b = [base[s]["final"]["goods"][g] for s in seeds]
        v = [var[s]["final"]["goods"][g] for s in seeds]
        print("  %-4s rate %s -> %s" % (g, ["%.3f" % x["rate"] for x in b], ["%.3f" % x["rate"] for x in v]))
        print("       产 %s -> %s | 需 %s -> %s | 断供天 %s -> %s" % (
            [x["produced"] for x in b], [x["produced"] for x in v],
            [x["demand"] for x in b], [x["demand"] for x in v],
            [x["shortage_days"] for x in b], [x["shortage_days"] for x in v]))
    print("\n=== 逐动作开用 ===")
    acts = set()
    for s in seeds:
        acts |= set(base[s]["attempts_by_action"]) | set(var[s]["attempts_by_action"])
    for a in sorted(acts):
        print("  %-5s %s -> %s" % (a, [base[s]["attempts_by_action"].get(a, 0) for s in seeds],
                                   [var[s]["attempts_by_action"].get(a, 0) for s in seeds]))
    print("\n=== 事件数 / 饿穿 / 硬软门 / digest ===")
    for s in seeds:
        print("  s%-3d events %5d -> %5d | starved %d -> %d | hard %s -> %s | soft %s -> %s | digest %s -> %s" % (
            s, base[s]["events"], var[s]["events"], base[s]["starved"], var[s]["starved"],
            base[s]["hard_fails"], var[s]["hard_fails"], base[s]["soft_fails"], var[s]["soft_fails"],
            base[s]["digest"], var[s]["digest"]))
    print("\n=== 最差货 ===")
    for s in seeds:
        def w(r):
            return min((gg["rate"], k) for k, gg in r["final"]["goods"].items() if gg["gated"])
        wb, wv = w(base[s]), w(var[s])
        print("  s%-3d %.3f(%s) -> %.3f(%s)" % (s, wb[0], wb[1], wv[0], wv[1]))


main()
