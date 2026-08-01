# -*- coding: utf-8 -*-
"""V1 负对照：key 关（=今天的镇子，逐字节等于改前）vs key 开。逐 seed，不给均值。"""
import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

off = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
on = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
assert [r["seed"] for r in off] == [r["seed"] for r in on]
seeds = [r["seed"] for r in off]

print("seed        ", " ".join("%10d" % s for s in seeds))
print("digest OFF  ", " ".join("%10s" % r["digest"] for r in off))
print("digest ON   ", " ".join("%10s" % r["digest"] for r in on))
print("同 digest 数 ", sum(1 for a, b in zip(off, on) if a["digest"] == b["digest"]), "/", len(seeds))
print()

TOWN = [
    ("standing_pos_pairs", "standing>0 的有向对数"),
    ("standing_neg_pairs", "standing<0 的有向对数"),
    ("standing_min_x1000", "最低 standing ×1000"),
    ("standing_max_x1000", "最高 standing ×1000"),
    ("fam_pairs", "familiarity>0 的有向对数"),
    ("fam_sum_x100", "familiarity 总和 ×100"),
    ("inv5_R1_knowers", "#5 知道 R1 的人数(应≥2)"),
    ("inv16_bad_rep_exists", "#16 前件:存在坏名声"),
    ("inv16_gossip_rep_events", "#16 gossip_rep 事件数"),
    ("inv20_stifled", "#20 停传(变冷)条数(应>0)"),
    ("st_neg_events", "L3 负判次数"),
    ("confide", "confide"), ("betray", "betray"),
    ("endorse", "endorse"), ("aid_accepted", "aid 接受"),
    ("refused_by_bound", "#19 因ε拒谈"),
]
print("%-26s | %s | %s" % ("全镇社会状态", "OFF 逐 seed".ljust(34), "ON 逐 seed"))
print("-" * 100)
for k, label in TOWN:
    a = [r["town"][k] for r in off]
    b = [r["town"][k] for r in on]
    print("%-26s | %-34s | %s" % (label, str(a), str(b)))

print()
print("belief 按前缀（逐 seed 全镇持有条数）")
pres = sorted(set(sum([list(r["town"]["belief_by_prefix"].keys()) for r in off + on], [])))
for p in pres:
    a = [r["town"]["belief_by_prefix"].get(p, 0) for r in off]
    b = [r["town"]["belief_by_prefix"].get(p, 0) for r in on]
    print("  %-8s OFF %-30s ON %s" % (p, str(a), str(b)))

print()
print("== 环卫工那一栏（逐 seed）==")
FLD = [("work_done", "在班完成"), ("ev_produce", "produce事件"),
       ("ev_produce_witnessed", "其中有目击者"), ("ev_produce_witness_slots", "目击人次"),
       ("belief_CR_holders", "CR:环卫工 信念持有者"), ("gossip_of_CR", "CR 被转述次数"),
       ("standing_nonzero", "对他 standing 非零人数"), ("standing_sum_x1000", "对他 standing 总和×1000"),
       ("ev_blamed", "被指责事件"), ("belief_SH_holders", "SH 信念持有者")]
for k, label in FLD:
    a = [r["jobs"]["环卫工"][k] for r in off]
    b = [r["jobs"]["环卫工"][k] for r in on]
    print("  %-24s OFF %-26s ON %s" % (label, str(a), str(b)))

print()
print("== produce 事件全镇口径 ==")
for tag, rs in (("OFF", off), ("ON", on)):
    n = [r["by_type"].get("produce", {}).get("n", 0) for r in rs]
    w = [r["by_type"].get("produce", {}).get("witnessed", 0) for r in rs]
    print("  %-4s n=%s  witnessed=%s" % (tag, n, w))
