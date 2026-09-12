#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""V2 诊断：上限臂在整张网格里到底响过几次、每次用的是哪四种货。"""
import collections
import glob
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
    arm, n = m.group(1), int(m.group(2))
    for line in open(p, encoding="utf-8"):
        if line.strip():
            r = json.loads(line)
            cells[arm][n][r["seed"]] = r

print("全网格里【上限臂】响过的所有局（arm,N,seed）+ 它用的是哪几种货：")
tot = 0
for arm in sorted(cells):
    for n in sorted(cells[arm]):
        for s, r in sorted(cells[arm][n].items()):
            tot += 1
            g = r["final"]["goods"]
            gated = [k for k, v in g.items() if v["gated"]]
            ns = [k for k in gated if g[k]["shortage_days"] == 0]
            if len(gated) >= 3 and len(ns) * 2 > len(gated):
                print("  arm=%-8s N=%-3d seed=%-3d gated=%d never_short=%s" % (arm, n, s, len(gated), ns))
print("（网格共 %d 局）" % tot)

print()
for good in ("柴薪", "口粮", "屋瓦", "整洁"):
    hit = []
    for arm in sorted(cells):
        for n in sorted(cells[arm]):
            for s, r in sorted(cells[arm][n].items()):
                g = r["final"]["goods"][good]
                if g["gated"] and g["shortage_days"] == 0:
                    hit.append("%s@N%d/s%d" % (arm, n, s))
    print("%s 全年零缺货：%d / %d 局   %s" % (good, len(hit), tot, hit if len(hit) <= 12 else hit[:12] + ["..."]))
