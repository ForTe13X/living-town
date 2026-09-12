#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1 主对照：逐 seed 报 #40 的两条臂 + 余量 + 社交事件数 + digest 是否与基线相同。
用法：grid.py <base.jsonl> <var1.jsonl> [var2.jsonl ...]
判据一个字节没改：下限 SUPPLY_FLOOR=0.50；上限 零缺货货数*2 > 进判决货数。"""
import io, json, sys

FLOOR = 0.50


def load(p):
    return {r["seed"]: r for r in (json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip())}


def arms(r):
    g = [(k, v) for k, v in r["final"]["goods"].items() if v.get("gated")]
    ns = [k for k, v in g if v["shortage_days"] == 0]
    worst = min(g, key=lambda kv: kv[1]["rate"])
    a_lo = worst[1]["rate"] < FLOOR
    a_up = len(ns) * 2 > len(g)
    return worst[0], worst[1]["rate"], len(ns), len(g), a_lo, a_up


def name(p):
    return p.split("/")[-1].replace(".jsonl", "")


def main():
    files = sys.argv[1:]
    data = [(name(f), load(f)) for f in files]
    base = data[0][1]
    seeds = sorted(base)
    hdr = "seed |"
    for n, _ in data:
        hdr += " %-26s |" % n
    print(hdr)
    print("     |" + " 最差货 rate  零缺/判 臂    |" * len(data))
    nred = [0] * len(data)
    same_digest = [0] * len(data)
    for s in seeds:
        line = "%4d |" % s
        for i, (n, d) in enumerate(data):
            if s not in d:
                line += " %-26s |" % "-"
                continue
            wg, wr, nz, ng, a_lo, a_up = arms(d[s])
            if a_lo or a_up:
                nred[i] += 1
            if d[s]["digest"] == base[s]["digest"]:
                same_digest[i] += 1
            line += " %-4s %.3f  %d/%d  %-4s |" % (
                wg, wr, nz, ng, ("下" if a_lo else "") + ("上" if a_up else "") or "-")
        print(line)
    print("-" * len(hdr))
    print("配置                        | #40 红 | 最差货 min (并列全报)          | 零缺货货数 max (并列全报) | 社交事件 min..max | digest 与基线同")
    for i, (n, d) in enumerate(data):
        ws = [(s, arms(d[s])[1]) for s in seeds if s in d]
        zs = [(s, arms(d[s])[2]) for s in seeds if s in d]
        lo = min(v for _, v in ws)
        hi = max(v for _, v in zs)
        los = ",".join(str(s) for s, v in ws if v == lo)
        his = ",".join(str(s) for s, v in zs if v == hi)
        soc = [d[s].get("social_events", -1) for s in seeds if s in d]
        print("%-27s | %2d/%2d  | %.3f (seed %-14s) | %d (seed %-14s) | %5d..%5d | %d/%d" % (
            n, nred[i], len(seeds), lo, los, hi, his, min(soc), max(soc), same_digest[i], len(seeds)))


main()
