#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""V2 诊断：上限臂的独立零模型（全 6 货 vs 只用 4 货），以及 gated_n 是否恒为 6。"""
import collections
import glob
import itertools
import json
import os
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "analysis/v2/snap2"
FN = re.compile(r"^([a-z0-9]+)_n(\d+)_s\d+-\d+\.jsonl$")
cells = collections.defaultdict(lambda: collections.defaultdict(dict))
for p in glob.glob(os.path.join(SRC, "*.jsonl")):
    m = FN.match(os.path.basename(p))
    if not m:
        continue
    for line in open(p, encoding="utf-8"):
        if line.strip():
            r = json.loads(line)
            cells[m.group(1)][int(m.group(2))][r["seed"]] = r

ALL6 = ["豆子", "话本", "口粮", "柴薪", "屋瓦", "整洁"]
FOUR = ["豆子", "话本", "屋瓦", "整洁"]

gn = collections.Counter()
for arm in cells:
    for n in cells[arm]:
        for r in cells[arm][n].values():
            gn[sum(1 for g in r["final"]["goods"].values() if g["gated"])] += 1
print("gated_n 在整张网格上的分布：", dict(gn))
hb = min(r["final"]["goods"]["话本"]["demand"] for arm in cells for n in cells[arm] for r in cells[arm][n].values())
print("话本 demand 的全网格最小值：", hb)
print()


def model(p, goods, need):
    tot = 0.0
    for bits in itertools.product([0, 1], repeat=len(goods)):
        if sum(bits) < need:
            continue
        pr = 1.0
        for b, g in zip(bits, goods):
            pr *= p[g] if b else (1 - p[g])
        tot += pr
    return tot


print("%-6s %-4s %-6s %-10s %-10s %s" % ("arm", "N", "n", "模型(6货)", "模型(4货)", "实测 P(上限臂)"))
for arm in sorted(cells):
    for n in sorted(cells[arm]):
        rs = cells[arm][n]
        m = len(rs)
        if m < 12:
            continue
        p = {}
        for g in ALL6:
            p[g] = sum(1 for r in rs.values()
                       if r["final"]["goods"][g]["gated"] and r["final"]["goods"][g]["shortage_days"] == 0) / float(m)
        obs = 0
        for r in rs.values():
            gd = r["final"]["goods"]
            gated = [k for k, v in gd.items() if v["gated"]]
            ns = [k for k in gated if gd[k]["shortage_days"] == 0]
            if len(gated) >= 3 and len(ns) * 2 > len(gated):
                obs += 1
        print("%-6s %-4d %-6d %-10.4f %-10.4f %d/%d = %.3f" % (
            arm, n, m, model(p, ALL6, 4), model(p, FOUR, 4), obs, m, obs / float(m)))
