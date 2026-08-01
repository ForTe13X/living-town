#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""U1：从 ScaleSupply 的 stdout 日志逐 seed 重算 #40 两条臂 + 零缺货集合。
判据逐字照抄 Invariants.gd（SUPPLY_FLOOR=0.50；上限臂 never_short*2 > gated_n），一个字节没改。
用法：arms.py <label>=<log-or-jsonl> [...]"""
import io, json, sys

FLOOR = 0.50


def load(p):
    rows = []
    for line in io.open(p, encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("[SCALE] "):
            line = line[len("[SCALE] "):]
        elif not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            pass
    return {r["seed"]: r for r in rows}


def arms(r):
    g = [(k, v) for k, v in r["final"]["goods"].items() if v.get("gated")]
    ns = sorted(k for k, v in g if v["shortage_days"] == 0)
    worst = min(g, key=lambda kv: kv[1]["rate"])
    return worst[0], worst[1]["rate"], ns, len(g), worst[1]["rate"] < FLOOR, len(ns) * 2 > len(g)


def main():
    sets = [(a.split("=", 1)[0], load(a.split("=", 1)[1])) for a in sys.argv[1:]]
    for name, D in sets:
        print("=== %s   n=%d ===" % (name, len(D)))
        nlo = nup = 0
        worsts, zs = [], []
        for s in sorted(D):
            wg, wr, ns, ng, a_lo, a_up = arms(D[s])
            nlo += a_lo
            nup += a_up
            worsts.append((s, wr))
            zs.append((s, len(ns)))
            print("  s%-2d 最差货 %-4s %.3f | 零缺 %d/%d {%s} | %s" % (
                s, wg, wr, len(ns), ng, ",".join(ns),
                (("下" if a_lo else "") + ("上" if a_up else "")) or "-"))
        lo = min(v for _, v in worsts)
        hi = max(v for _, v in zs)
        print("  ---- #40 红 %d/%d (下%d 上%d) | 最差货 min %.3f (seed %s) | 零缺货数 max %d (seed %s)" % (
            sum(1 for s in sorted(D) if arms(D[s])[4] or arms(D[s])[5]), len(D), nlo, nup,
            lo, ",".join(str(s) for s, v in worsts if v == lo),
            hi, ",".join(str(s) for s, v in zs if v == hi)))
        goods = {}
        for s in D:
            for k in arms(D[s])[2]:
                goods[k] = goods.get(k, 0) + 1
        print("  ---- 逐货零缺货 seed 数：" + "  ".join("%s %d/%d" % (k, v, len(D)) for k, v in sorted(goods.items(), key=lambda x: -x[1])))
        print()
    if len(sets) >= 2:
        base = sets[0]
        for name, D in sets[1:]:
            same = sum(1 for s in D if s in base[1] and D[s]["digest"] == base[1][s]["digest"])
            print("digest 与 %s 相同：%s %d/%d" % (base[0], name, same, len(D)))


main()
