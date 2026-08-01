#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1：满仓白干的量。申报批量 × 在班完成次数 = 应产；event_log 记的 produce = 真入账。
差额 = 撞 cap 当场丢掉的那一部分（_stock_move: applied = min(delta, cap - cur)）。逐 seed，不给均值。"""
import json, io, sys

PROD = json.load(io.open("game/data/production.json", encoding="utf-8"))["produce"]
GOOD2JOB = {}
for t, r in PROD.items():
    GOOD2JOB.setdefault(r["good"], []).append((t, r["amount"]))


def load(paths):
    out = {}
    for p in paths:
        for ln in io.open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                r = json.loads(ln)
                out[r["seed"]] = r
    return out


def main():
    recs = load(sys.argv[1:])
    print("货   | seed 数 | 应产(申报×在班完成) min..max | 真入账 min..max | 丢弃占比 min..max")
    for g, jobs in GOOD2JOB.items():
        rows = []
        for s in sorted(recs):
            r = recs[s]
            w = r["work_by_title"]
            declared = sum(w.get(t, 0) * a for t, a in jobs)
            actual = r["final"]["goods"][g]["produced"]
            if declared > 0:
                rows.append((s, declared, actual, 1.0 - actual / declared))
        if not rows:
            continue
        ds = [x[3] for x in rows]
        lo = min(ds); hi = max(ds)
        los = ",".join(str(x[0]) for x in rows if x[3] == lo)
        his = ",".join(str(x[0]) for x in rows if x[3] == hi)
        print("%-4s | %2d | %5d..%5d | %5d..%5d | %.1f%%(seed %s) .. %.1f%%(seed %s)" % (
            g, len(rows), min(x[1] for x in rows), max(x[1] for x in rows),
            min(x[2] for x in rows), max(x[2] for x in rows),
            100 * lo, los, 100 * hi, his))


main()
