#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Z2 · 铺开判据的那张矩阵：每个岗位 × 每一格，「不豁免的 seed 里 bys>0 的最小值」（= 余量）。

余量 = 0  ⇒ 那一格里至少有一个 seed 会让 #41 直接红（产出 ≥ CRAFT_MIN_WORKS 而一次都没被看见）。
「豁免」= 该 seed 的 produce < CRAFT_MIN_WORKS(5)，#41 跳过该职位。

用法：python analysis/z2/margin_matrix.py
"""
import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["面点师", "咖啡师", "教书先生", "环卫工", "泥瓦匠", "杂役", "木匠", "渔夫", "商贩"]
MIN_WORKS = 5

GRIDS = [
    ("改前 N12 s1-12 60天", "census_before_1_12.jsonl"),
    ("改前 N12 s13-60 60天", "census_before_13_60.jsonl"),
    ("改前 N16 s1-12 60天", "census_before_n16_1_12.jsonl"),
    ("零假设臂 N12 s1-12 60天", "census_null_1_12.jsonl"),
    ("改前 N12 s1-12 30天", "census_before_d30.jsonl"),
    ("改前 N12 s1-12 20天", "census_before_d20.jsonl"),
    ("★改后 N12 s1-12 60天", "census_after_1_12.jsonl"),
    ("★改后 N16 s1-12 60天", "census_after_n16_1_12.jsonl"),
]


def margin(rows, t):
    live = []
    for r in rows:
        j = r["jobs"].get(t)
        if j is None:
            continue
        b = j["produce_bystanders"]
        p = int(j["ev_produce"])
        if p >= MIN_WORKS:
            live.append(int(b["n"]) - int(b["zero"]))
    if not live:
        return None
    return min(live)


data = {}
for label, fn in GRIDS:
    path = os.path.join(HERE, fn)
    if not os.path.exists(path):
        continue
    data[label] = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]

labels = list(data.keys())
print("余量 = 「不豁免的 seed 里 bys>0 的最小值」；`—` = 该格所有 seed 都豁免（产出 < %d）" % MIN_WORKS)
print()
print("%-8s" % "岗位" + "".join("%-24s" % l for l in labels) + "  改前六格取最小")
for t in ORDER:
    cells = []
    pre = []
    for l in labels:
        m = margin(data[l], t)
        cells.append("—" if m is None else str(m))
        if not l.startswith("★") and m is not None:
            pre.append(m)
    print("%-8s" % t + "".join("%-24s" % c for c in cells) + "  " + (str(min(pre)) if pre else "—"))
