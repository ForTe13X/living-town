#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1：逐 seed 前后对照表（markdown）。用法：table.py <off> <on> <lo> <hi>"""
import io, json, sys

FLOOR = 0.50


def load(p):
    D = {}
    for line in io.open(p, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("[SCALE] "):
            line = line[8:]
        elif not line.startswith("{"):
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        D[r["seed"]] = r
    return D


def arms(r):
    g = [(k, v) for k, v in r["final"]["goods"].items() if v.get("gated")]
    ns = [k for k, v in g if v["shortage_days"] == 0]
    w = min(g, key=lambda kv: kv[1]["rate"])
    return w[0], w[1]["rate"], len(ns), len(g), w[1]["rate"] < FLOOR, len(ns) * 2 > len(g)


off, on = load(sys.argv[1]), load(sys.argv[2])
lo, hi = int(sys.argv[3]), int(sys.argv[4])
print("| seed | 改前 最差货 | 零缺/判 | 臂 | 改后 最差货 | 零缺/判 | 臂 |")
print("|---|---|---|---|---|---|---|")
ro, rn = [], []
for s in range(lo, hi + 1):
    if s not in off or s not in on:
        continue
    a = arms(off[s]); b = arms(on[s])
    if a[4] or a[5]: ro.append(s)
    if b[4] or b[5]: rn.append(s)
    def arm(x): return (("下" if x[4] else "") + ("上" if x[5] else "")) or "—"
    print("| %d | %s %.3f | %d/%d | %s | %s %.3f | %d/%d | %s |" % (
        s, a[0], a[1], a[2], a[3], arm(a), b[0], b[1], b[2], b[3], arm(b)))
n = sum(1 for s in range(lo, hi + 1) if s in off and s in on)
print("| **#40 红** | | | **%s → %d/%d** | | | **%s → %d/%d** |" % (
    ro or "无", len(ro), n, rn or "无", len(rn), n))
