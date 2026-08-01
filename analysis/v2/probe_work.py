#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""V2 诊断：逐岗位【在班完成次数】逐 N 逐臂的展布（中位数 [min..max]），以及社交事件总数。

它回答的是："三条臂改的到底是不是【谁上了几次工】"——若三条臂的上工次数几乎不动，
那么货物侧的差别就必须来自别的地方（腐坏、cap、消耗节奏），而不是"工人更勤快了"。
"""
import collections
import glob
import json
import os
import re
import statistics
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

TITLES = ["面点师", "渔夫", "杂役", "木匠", "咖啡师", "教书先生", "环卫工", "泥瓦匠"]
print("逐岗位在班完成次数：中位数[min..max]（每格 24 seed）")
for arm in sorted(cells):
    for n in sorted(cells[arm]):
        rs = cells[arm][n]
        if len(rs) < 12:
            continue
        parts = []
        for t in TITLES:
            v = [r["work_by_title"].get(t, 0) for r in rs.values()]
            parts.append("%s %d[%d..%d]" % (t, int(statistics.median(v)), min(v), max(v)))
        soc = [r["social_events"] for r in rs.values()]
        print("%-8s N=%-3d %s | social %d[%d..%d]" % (
            arm, n, " ".join(parts), int(statistics.median(soc)), min(soc), max(soc)))
