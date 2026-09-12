#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把人工判卷表汇成【逐层】结果 + Wilson 区间。**不打合并值**（要显式 --pool）。

输入 TSV 列（制表符分隔，`#` 开头为注释）：
    arm  id  stratum  verdict  evidence  cost_actual  note
    verdict ∈ {HIT, PARTIAL, MISS}   —— 判据见 analysis/t2/PREREG.md 第一节
    evidence ∈ {ls, grep, read, xref, rerun, reason, -}
"""
import sys, math, collections

sys.stdout.reconfigure(encoding="utf-8")


def wilson(k, n, z=1.96):
    if n <= 0:
        return (0.0, 1.0)
    p = k / n
    d = 1.0 + z * z / n
    c = p + z * z / (2 * n)
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, (c - h) / d), min(1.0, (c + h) / d))


rows = []
for ln in open(sys.argv[1], encoding="utf-8"):
    ln = ln.rstrip("\n")
    if not ln.strip() or ln.lstrip().startswith("#"):
        continue
    f = ln.split("\t")
    while len(f) < 7:
        f.append("")
    rows.append(dict(arm=f[0].strip(), id=f[1].strip(), stratum=f[2].strip(),
                     verdict=f[3].strip().upper(), evidence=f[4].strip(),
                     cost=f[5].strip(), note=f[6].strip()))

ARMS_MAIN = {"A1", "A2", "A3"}


def table(sel, title):
    sub = [r for r in rows if sel(r)]
    if not sub:
        return
    print("\n### %s   （n=%d）" % (title, len(sub)))
    print("%-10s %-7s %-22s %-7s %-22s" % ("层", "HIT", "Wilson95 (主口径)", "+PART", "Wilson95 (上界口径)"))
    for s in sorted(set(r["stratum"] for r in sub)):
        g = [r for r in sub if r["stratum"] == s]
        n = len(g)
        k = sum(1 for r in g if r["verdict"] == "HIT")
        kp = sum(1 for r in g if r["verdict"] in ("HIT", "PARTIAL"))
        lo, hi = wilson(k, n)
        lo2, hi2 = wilson(kp, n)
        print("%-10s %-7s [%.3f, %.3f]        %-7s [%.3f, %.3f]"
              % (s, "%d/%d" % (k, n), lo, hi, "%d/%d" % (kp, n), lo2, hi2))


print("=" * 92)
print("T2 前瞻注入 · 逐层结果（判据：analysis/t2/PREREG.md；**不合并层**）")
print("=" * 92)
table(lambda r: r["arm"] in ARMS_MAIN, "主臂 A1+A2+A3（明写要交 §4、只读、隔离副本）")
for a in sorted(set(r["arm"] for r in rows)):
    table(lambda r, a=a: r["arm"] == a, "单臂 %s" % a)

print("\n### 证据类（每条 HIT 是靠什么抓到的）")
ev = collections.Counter(r["evidence"] for r in rows if r["verdict"] == "HIT")
tot = sum(ev.values()) or 1
for e, n in ev.most_common():
    print("  %-8s %3d  (%4.1f%%)" % (e or "-", n, 100.0 * n / tot))
print("  ⚠ `xref`（靠另一份文档交叉引用）单列：抓到它不证明棒子有能力核验，")
print("     只证明这个仓库把同一个数抄在了两个地方。")

print("\n### 标签成本 vs 实测最便宜路径")
cc = collections.Counter((r["stratum"], r["cost"]) for r in rows if r["arm"] in ARMS_MAIN)
for s in sorted(set(k[0] for k in cc)):
    print("  %-10s %s" % (s, "  ".join("%s×%d" % (c, n) for (ss, c), n in sorted(cc.items()) if ss == s)))

if "--pool" in sys.argv:
    sub = [r for r in rows if r["arm"] in ARMS_MAIN]
    k = sum(1 for r in sub if r["verdict"] == "HIT")
    lo, hi = wilson(k, len(sub))
    print("\n⚠ 合并值（你要了才打）：%d/%d  Wilson95 = [%.3f, %.3f]" % (k, len(sub), lo, hi))
    print("  ⚠ 它没有意义：便宜的那一层会把它抬上去。这正是 docs/50 §八 那个 30/30 犯的错。")
