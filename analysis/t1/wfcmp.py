#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1：改前/改后的【本职赢率 × 决策时镇库分档】对照，**限定同一批 seed**。
用法：wfcmp.py base.jsonl var.jsonl [seed,seed,...]"""
import io, json, sys

FOCUS = ["面点师", "渔夫", "咖啡师", "杂役", "木匠", "教书先生", "环卫工", "泥瓦匠"]
BUCK = [("empty", "空(0 件)"), ("low", "低(<=1/4)"), ("mid", "中(1/4~3/4)"), ("high", "高(>3/4)")]


def load(p):
    return {r["seed"]: r for r in (json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip())}


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    seeds = sorted(set(a) & set(b))
    if len(sys.argv) > 3:
        seeds = [int(x) for x in sys.argv[3].split(",")]
    print("同一批 seed = %s（n=%d）" % (seeds, len(seeds)))
    print()
    print("岗位   | 分档        |   改前 赢/上台  赢率  |   改后 赢/上台  赢率")
    for t in FOCUS:
        for k, lbl in BUCK:
            oa = sum(a[s]["jobs"][t]["off_" + k] for s in seeds)
            wa = sum(a[s]["jobs"][t]["win_" + k] for s in seeds)
            ob = sum(b[s]["jobs"][t]["off_" + k] for s in seeds)
            wb = sum(b[s]["jobs"][t]["win_" + k] for s in seeds)
            f = lambda w, o: ("%3d/%4d %6.1f%%" % (w, o, 100.0 * w / o)) if o else "  -/   -      "
            print("%-6s | %-11s | %s | %s" % (t if k == "empty" else "", lbl, f(wa, oa), f(wb, ob)))
        print("       |")
    print()
    print("=== 逐 seed：完成数 与 终态库存 ===")
    for s in seeds:
        wa = a[s]["work_by_title"]; wb = b[s]["work_by_title"]
        ks = sorted(set(wa) | set(wb))
        print("  seed %2d 完成数  改前 %s" % (s, " ".join("%s=%d" % (k, wa.get(k, 0)) for k in ks)))
        print("          %s改后 %s" % (" " * 7, " ".join("%s=%d" % (k, wb.get(k, 0)) for k in ks)))


main()
