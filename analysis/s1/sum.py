#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""S1 汇总：从 ScaleSupply 的 jsonl 出展布（**不给均值**，极值连并列一起报）。"""
import json, io, sys, collections

GOODS = ["口粮", "柴薪", "屋瓦", "豆子", "话本", "整洁"]


def load(p):
    out = []
    for ln in io.open(p, encoding="utf-8"):
        ln = ln.strip()
        if ln:
            out.append(json.loads(ln))
    return out


def worst(rec):
    """进判决(gated)的货里满足率最低的那个 -> (rate, good)"""
    best = None
    for g, gg in rec["final"]["goods"].items():
        if not gg.get("gated"):
            continue
        if best is None or gg["rate"] < best[0]:
            best = (gg["rate"], g)
    return best if best else (-1.0, "-")


def zero_short(rec):
    """全年零缺货的【进判决】货数 + 名单"""
    ns = [g for g, gg in rec["final"]["goods"].items()
          if gg.get("gated") and gg["shortage_days"] == 0]
    ng = [g for g, gg in rec["final"]["goods"].items() if gg.get("gated")]
    return ns, ng


def extremes(pairs):
    """pairs = [(seed, val)] -> 'min V (seeds ...) · max V (seeds ...)'，并列全报"""
    vs = [v for _, v in pairs]
    lo, hi = min(vs), max(vs)
    ls = [str(s) for s, v in pairs if v == lo]
    hs = [str(s) for s, v in pairs if v == hi]
    return "min %s (seed %s) · max %s (seed %s)" % (lo, ",".join(ls), hi, ",".join(hs))


def main(paths):
    for p in paths:
        recs = load(p)
        if not recs:
            continue
        print("=" * 96)
        print("%s   N=%d  %d seed × %d 天" % (p, recs[0]["n_agents"], len(recs), recs[0]["days"]))
        print("=" * 96)
        print("seed | 最差货(rate)      | 零缺货货数/进判决 | 零缺货名单                | #40 | soft/hard")
        wp, zp = [], []
        for r in sorted(recs, key=lambda x: x["seed"]):
            w, wg = worst(r)
            ns, ng = zero_short(r)
            wp.append((r["seed"], round(w, 3)))
            zp.append((r["seed"], len(ns)))
            print("%4d | %-6s %-10s | %d/%d              | %-24s | %-5s | %s %s" % (
                r["seed"], "%.3f" % w, wg, len(ns), len(ng), ",".join(ns) or "-",
                "绿" if r["inv40_ok"] else "红", r["soft_fails"], r["hard_fails"]))
        print("-" * 96)
        print("最差货满足率展布: %s" % extremes(wp))
        print("  逐 seed: %s" % " ".join("%.3f" % v for _, v in wp))
        print("零缺货货数展布: %s" % extremes(zp))
        print("  逐 seed: %s" % " ".join(str(v) for _, v in zp))
        red = [r["seed"] for r in recs if not r["inv40_ok"]]
        print("#40 红的 seed: %s   (共 %d/%d)" % (red or "-", len(red), len(recs)))
        # 逐货：全年零缺货的 seed 数 + 满足率展布
        print("-" * 96)
        print("逐货 | 零缺货 seed 数 | 满足率 min..max | 需求 min..max | 断供天数 min..max")
        for g in GOODS:
            vals = [(r["seed"], r["final"]["goods"][g]) for r in recs if g in r["final"]["goods"]]
            if not vals:
                continue
            gated = [(s, gg) for s, gg in vals if gg.get("gated")]
            if not gated:
                print("%-4s | (未进判决)" % g)
                continue
            zs = [s for s, gg in gated if gg["shortage_days"] == 0]
            rs = [gg["rate"] for _, gg in gated]
            ds = [gg["demand"] for _, gg in gated]
            sd = [gg["shortage_days"] for _, gg in gated]
            print("%-4s | %2d/%2d          | %.3f..%.3f   | %d..%d      | %d..%d" % (
                g, len(zs), len(gated), min(rs), max(rs), min(ds), max(ds), min(sd), max(sd)))
        # 逐动作开用
        print("-" * 96)
        acts = collections.defaultdict(list)
        for r in recs:
            for a, n in r["attempts_by_action"].items():
                acts[a].append((r["seed"], n))
        print("逐动作开用(展布): " + " · ".join(
            "%s %d..%d" % (a, min(v for _, v in xs), max(v for _, v in xs))
            for a, xs in sorted(acts.items(), key=lambda kv: -max(v for _, v in kv[1]))))
        # 逐岗位在班完成
        jobs = collections.defaultdict(list)
        for r in recs:
            for t, n in r["work_by_title"].items():
                jobs[t].append((r["seed"], n))
        print("逐岗位在班完成(展布): " + " · ".join(
            "%s %d..%d" % (t, min(v for _, v in xs), max(v for _, v in xs))
            for t, xs in sorted(jobs.items())))
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
