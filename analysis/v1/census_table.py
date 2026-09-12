# -*- coding: utf-8 -*-
"""V1 清点表：把 v1_social_census.gd 的 jsonl 折成逐 seed 展布（不给均值，给 min..max 与逐 seed 列）。"""
import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

path = sys.argv[1] if len(sys.argv) > 1 else "analysis/v1/census_before.jsonl"
recs = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
seeds = [r["seed"] for r in recs]
titles = sorted(recs[0]["jobs"].keys(), key=lambda t: -recs[0]["jobs"][t]["work_done"])

def col(t, k):
    out = []
    for r in recs:
        v = r["jobs"][t]
        for part in k.split("."):
            v = v[part] if isinstance(v, dict) else v
        out.append(v)
    return out

def rng(v):
    return "%d..%d" % (min(v), max(v)) if min(v) != max(v) else str(min(v))

print("seeds =", seeds, " days =", recs[0]["days"], " N =", recs[0]["n_agents"])
print("digests =", [r["digest"] for r in recs])
print()
hdr = ["岗位", "持有人", "动作", "产物", "被指责的货", "在班完成", "produce事件",
       "produce被看见", "工资事件被看见", "产出时在场人数(和/次数)", "在场0人的次数",
       "被指责事件", "被指责有目击", "SH信念持有者", "SH被转述", "对他standing非零人数"]
print(" | ".join(hdr))
print(" | ".join(["---"] * len(hdr)))
for t in titles:
    r0 = recs[0]["jobs"][t]
    by = [r["jobs"][t]["produce_bystanders"] for r in recs]
    tot_n = sum(b["n"] for b in by)
    tot_sum = sum(b["sum"] for b in by)
    tot_zero = sum(b["zero"] for b in by)
    row = [t, r0["holder"], r0["action"], r0["produces"] or "—",
           ",".join(r0["blame_for"]) or "—",
           rng(col(t, "work_done")),
           rng(col(t, "ev_produce")),
           rng(col(t, "ev_produce_witnessed")),
           rng(col(t, "ev_wage_witnessed")),
           "%d/%d = %.2f人" % (tot_sum, tot_n, (tot_sum / tot_n) if tot_n else 0),
           str(tot_zero),
           rng(col(t, "ev_blamed")),
           rng(col(t, "ev_blamed_witnessed")),
           rng(col(t, "belief_SH_holders")),
           rng(col(t, "gossip_of_SH")),
           rng(col(t, "standing_nonzero"))]
    print(" | ".join(str(x) for x in row))

print()
print("== event_log 按类型（逐 seed 求和，witnessed = witnesses 非空的条数）==")
agg = {}
for r in recs:
    for ty, e in r["by_type"].items():
        a = agg.setdefault(ty, [0, 0])
        a[0] += e["n"]; a[1] += e["witnessed"]
for ty in sorted(agg, key=lambda x: -agg[x][0]):
    n, w = agg[ty]
    print("  %-12s n=%-6d witnessed=%-6d (%.0f%%)" % (ty, n, w, 100.0 * w / n))
print()
print("SH via 分布：")
for t in titles:
    vias = {}
    for r in recs:
        for k, v in r["jobs"][t]["belief_SH_via"].items():
            vias[k] = vias.get(k, 0) + v
    if vias:
        print("  %s: %s" % (t, vias))
