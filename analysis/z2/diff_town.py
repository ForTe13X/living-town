#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Z2 负对照/前后对照：两份 census jsonl 逐 seed 比。**不给均值**（docs/41 §5）。

用法：python analysis/z2/diff_town.py <A.jsonl> <B.jsonl> [标签A] [标签B]
"""
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

ORDER = ["面点师", "渔夫", "杂役", "木匠", "咖啡师", "教书先生", "环卫工", "泥瓦匠", "商贩"]

A = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
B = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
LA = sys.argv[3] if len(sys.argv) > 3 else "A"
LB = sys.argv[4] if len(sys.argv) > 4 else "B"
assert [r["seed"] for r in A] == [r["seed"] for r in B], "seed 段不同，不可比"
seeds = [r["seed"] for r in A]

print("A = %s (%s)" % (sys.argv[1], LA))
print("B = %s (%s)" % (sys.argv[2], LB))
print("seed: %s" % ",".join(map(str, seeds)))
print()
print("digest %-4s %s" % (LA, " ".join(r["digest"] for r in A)))
print("digest %-4s %s" % (LB, " ".join(r["digest"] for r in B)))
print("逐位相同的 seed 数: %d / %d" % (sum(1 for a, b in zip(A, B) if a["digest"] == b["digest"]), len(seeds)))
print()

TOWN = [
    ("inv5_R1_knowers", "#5 知道 R1 的人数(应≥2)"),
    ("inv16_bad_rep_exists", "#16 前件: 存在坏名声"),
    ("inv16_gossip_rep_events", "#16 gossip_rep 事件数"),
    ("inv20_stifled", "#20 停传(变冷)条数(应>0)"),
    ("aid_accepted", "#29 前件 aid_accepted (<8 则平凡通过)"),
    ("standing_pos_pairs", "standing>0 的有向对数"),
    ("standing_neg_pairs", "standing<0 的有向对数"),
    ("standing_min_x1000", "最低 standing ×1000"),
    ("standing_max_x1000", "最高 standing ×1000"),
    ("st_neg_events", "L3 负判次数"),
    ("confide", "confide"), ("betray", "betray"), ("endorse", "endorse"),
    ("refused_by_bound", "#19 因 ε 拒谈"),
    ("fam_pairs", "familiarity>0 的有向对"),
]
print("== 全镇社会状态（逐 seed）==")
for k, label in TOWN:
    a = [r["town"][k] for r in A]
    b = [r["town"][k] for r in B]
    mark = "" if a == b else "   <== 动了"
    print("  %-32s" % label)
    print("      %-4s %s" % (LA, a))
    print("      %-4s %s%s" % (LB, b, mark))
print()

print("== 逐岗位：produce / 被看见 / CR 信念 / 对他的 standing ==")
FLD = [("ev_produce", "produce 事件"),
       ("ev_produce_witnessed", "其中带目击者"),
       ("ev_produce_witness_slots", "目击人次"),
       ("belief_CR_holders", "CR:<职位> 持有者"),
       ("gossip_of_CR", "CR 被转述"),
       ("standing_nonzero", "对他 standing 非零人数"),
       ("standing_sum_x1000", "对他 standing 总和×1000"),
       ("ev_blamed", "被指责事件"),
       ("belief_SH_holders", "SH 信念持有者")]
for t in ORDER:
    if t not in A[0]["jobs"]:
        continue
    print("-- %s --" % t)
    for k, label in FLD:
        a = [r["jobs"][t][k] for r in A]
        b = [r["jobs"][t][k] for r in B]
        if a == b and k in ("gossip_of_CR", "belief_SH_holders"):
            continue
        print("   %-24s %-4s %s" % (label, LA, a))
        print("   %-24s %-4s %s" % ("", LB, b))
print()

print("== 【零假设/对照臂】每个岗位 bys>0 的逐 seed 抖动 |ΔA→B| ==")
print("%-8s %-40s %-40s %s" % ("岗位", "A: bys>0", "B: bys>0", "|Δ| 逐 seed / max"))
for t in ORDER:
    if t not in A[0]["jobs"]:
        continue
    ga = [r["jobs"][t]["produce_bystanders"]["n"] - r["jobs"][t]["produce_bystanders"]["zero"] for r in A]
    gb = [r["jobs"][t]["produce_bystanders"]["n"] - r["jobs"][t]["produce_bystanders"]["zero"] for r in B]
    d = [abs(x - y) for x, y in zip(ga, gb)]
    if sum(ga) == 0 and sum(gb) == 0:
        continue
    print("%-8s %-40s %-40s %s / max=%d" % (t, ",".join(map(str, ga)), ",".join(map(str, gb)),
                                            ",".join(map(str, d)), max(d)))
