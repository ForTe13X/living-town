# R1 · 上限臂候选判据的【判别力】对照：逐 log 报每个候选统计量的逐 seed 展布 + 极值（连并列一起报）。
# 用法: python analysis/r1/disc.py <log> [<log> ...]
import json, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def load(path):
    out = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.strip()
        if ln.startswith("[SCALE] "):
            out.append(json.loads(ln[8:]))
    return out


def stats(r):
    g = r["final"]["goods"]
    rates, zc, sd_tot = [], 0, 0
    for gid, d in g.items():
        if not d.get("gated"):
            continue
        rates.append(d["rate"])
        sd_tot += d["shortage_days"]
        if d["shortage_days"] == 0:
            zc += 1
    rates.sort()
    n = len(rates)
    if n == 0:
        return None
    return {
        "n_gated": n,
        "zc": zc,                                   # 全年零缺货的货数
        "z99": sum(1 for x in rates if x >= 0.99),  # 满足率 ≥0.99 的货数
        "worst": rates[0],                          # 最差货（现有下限臂判的那个量）
        "w2": rates[1] if n > 1 else rates[0],      # 次差货
        "med": rates[n // 2],                       # 中位货
        "sd_tot": sd_tot,                           # 全镇断供天数合计（6 货相加）
        "sd_min": min(d["shortage_days"] for d in g.values() if d.get("gated")),
    }


def report(path):
    recs = load(path)
    if not recs:
        print("!! 无数据 %s" % path)
        return
    rows = [(r["seed"], stats(r), r["inv40_ok"]) for r in recs]
    rows = [x for x in rows if x[1]]
    n = recs[0]["n_agents"]
    print("=" * 96)
    print("%-28s N=%-3d seeds=%s   #40现状: %s" % (
        os.path.basename(path), n, [s for s, _, _ in rows],
        "全绿" if all(k for _, _, k in rows) else
        "红 seed " + str([s for s, _, k in rows if not k])))
    # R1 上限臂的判决：zc*2 > n_gated 且 n_gated>=3
    up = [(s, st["zc"] * 2 > st["n_gated"] and st["n_gated"] >= 3) for s, st, _ in rows]
    red = [s for s, v in up if v]
    print("  上限臂判决: %s   (红 %d/%d)" % (
        ("绿" if not red else "红 seed " + str(red)), len(red), len(up)))
    for key, fmt in [("n_gated", "%d"), ("zc", "%d"), ("z99", "%d"), ("worst", "%.3f"), ("w2", "%.3f"),
                     ("med", "%.3f"), ("sd_tot", "%d"), ("sd_min", "%d")]:
        vals = [st[key] for _, st, _ in rows]
        lo, hi = min(vals), max(vals)
        lo_s = [s for (s, st, _) in rows if st[key] == lo]
        hi_s = [s for (s, st, _) in rows if st[key] == hi]
        print("  %-6s %s   min=%s(seed %s) max=%s(seed %s)" % (
            key, " ".join(fmt % v for v in vals), fmt % lo, lo_s, fmt % hi, hi_s))


for p in sys.argv[1:]:
    report(p)
