# -*- coding: utf-8 -*-
"""W1 头条表：把所有臂放在一张表上。逐 seed 展布 + 12-seed 合计 + 覆盖 + #29 前件。"""
import json, io, os, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))

def load(tag):
    p = os.path.join(HERE, "log_%s.txt" % tag)
    return [json.loads(l[len("[W1FUNNEL] "):]) for l in io.open(p, encoding="utf-8", errors="replace")
            if l.startswith("[W1FUNNEL] ")]

ARMS = [
    ("off",      "基线：删掉 craft_credit 键（= V1 之前的树）"),
    ("st0",      "键在，standing=0（写目击者/信念/记忆，不写声誉）"),
    ("st0125",   "standing=+0.125"),
    ("on",       "standing=+0.25  ← 出货"),
    ("st05",     "standing=+0.5"),
    ("stneg",    "standing=−0.25（把好评翻成差评）"),
    ("tmu",      "同一条记录挪给【木匠】(standing=+0.25)"),
    ("tlin",     "同一条记录挪给【面点师】(standing=+0.25)"),
    ("sham401",  "假扰动：craft_credit 全关，obj_dist_penalty 0.400→0.401"),
    ("sham42",   "假扰动：craft_credit 全关，obj_dist_penalty 0.400→0.42"),
    ("sham38",   "假扰动：craft_credit 全关，obj_dist_penalty 0.400→0.38"),
]

base = [r["ev_aid"] for r in load("off")]
print("== N=12 · seeds 1-12 · 60 天 ==（基线 aid 合计 %d）\n" % sum(base))
print("%-9s %5s %6s %7s %6s %8s  %s" % ("臂", "aid和", "相对", "低/高/平", "覆盖", "#29有牙", "说明"))
for tag, desc in ARMS:
    rs = load(tag)
    aid = [r["ev_aid"] for r in rs]
    lo = sum(1 for x, y in zip(base, aid) if y < x)
    hi = sum(1 for x, y in zip(base, aid) if y > x)
    print("%-9s %5d %6.3f %7s %6s %8s  %s" % (
        tag, sum(aid), sum(aid) / float(sum(base)), "%d/%d/%d" % (lo, hi, len(aid) - lo - hi),
        "%d/%d" % (sum(1 for a in aid if a > 0), len(aid)),
        "%d/%d" % (sum(1 for a in aid if a >= 8), len(aid)), desc))
print()
for tag, _ in ARMS:
    print("  %-9s %s" % (tag, [r["ev_aid"] for r in load(tag)]))

print("\n\n== 留出种子（同一次改动，off → on）==")
for lo_tag, hi_tag, label in [("ho_off", "ho_on", "seeds 13-30")]:
    a = [r["ev_aid"] for r in load(lo_tag)]
    b = [r["ev_aid"] for r in load(hi_tag)]
    lo = sum(1 for x, y in zip(a, b) if y < x); hi = sum(1 for x, y in zip(a, b) if y > x)
    print("  %-12s off=%d → on=%d  (%.3f)  低%d/高%d/平%d" % (label, sum(a), sum(b), sum(b) / float(sum(a)), lo, hi, len(a) - lo - hi))
    print("    off %s" % a)
    print("    on  %s" % b)
try:
    s = [r["ev_aid"] for r in load("ship3160")]
    print("  %-12s on=%d 覆盖 %d/%d（对照 = V1 自己的 analysis/v1/heldout_31_60_*.txt：off 170 / on 180，29/30）"
          % ("seeds 31-60", sum(s), sum(1 for a in s if a > 0), len(s)))
except Exception as e:
    print("  seeds 31-60: %s" % e)
try:
    a = [r["ev_aid"] for r in load("ho_off")]
    b = [r["ev_aid"] for r in load("ho_sham42")]
    lo = sum(1 for x, y in zip(a, b) if y < x); hi = sum(1 for x, y in zip(a, b) if y > x)
    print("\n  ★ 假扰动搬到留出种子上（seeds 13-30，obj_dist_penalty 0.42）：%d → %d (%.3f)  低%d/高%d/平%d"
          % (sum(a), sum(b), sum(b) / float(sum(a)), lo, hi, len(a) - lo - hi))
    print("    sham %s" % b)
except Exception as e:
    print("  ho_sham42: %s" % e)
