"""Y1 aggregation — continuous margins, per-seed spreads, and the decisive test:
every arm is judged AGAINST THE NULL ARM (obj_dist_penalty 0.400->0.401), not against
red counts.  X1 measured that "the reds went away" is true of any large enough
perturbation at a 2/60 base rate.
"""
import io, json, os, sys
from math import comb

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = HERE + "/out"
BLOCKS = ["1-12", "49-60"]


def load(arm, n=40, blocks=None):
    """-> {(block, seed): record}"""
    res = {}
    for b in (blocks or BLOCKS):
        p = "%s/%s_n%d_s%s.txt" % (OUT, arm, n, b)
        if not os.path.exists(p):
            continue
        for l in io.open(p, encoding="utf-8"):
            if l.startswith("[X1M] "):
                r = json.loads(l[6:])
                res[(b, r["seed"])] = r
    return res


def med(v):
    v = sorted(v)
    if not v:
        return float("nan")
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2.0


def binom_p_one_sided(k, n):
    """P(X >= k) under fair coin, X~Bin(n,1/2)."""
    if n == 0:
        return float("nan")
    return sum(comb(n, i) for i in range(k, n + 1)) / float(2 ** n)


def sign_test(a, b, key, higher_is_better=True):
    """paired per-seed: how often arm a beats arm b."""
    win = lose = tie = 0
    for k in sorted(set(a) & set(b)):
        va, vb = key(a[k]), key(b[k])
        if va == vb:
            tie += 1
        elif (va > vb) == higher_is_better:
            win += 1
        else:
            lose += 1
    n = win + lose
    p = binom_p_one_sided(max(win, lose), n) if n else float("nan")
    return win, lose, tie, p


F_SOC = lambda r: r["floors"]["social"]
F_LOCK = lambda r: r["max_soclock_run"]
F_AREA = lambda r: r["soclock_ticks"]


def row(name, d, base, null):
    if not d:
        return None
    ks = sorted(d)
    soc = [F_SOC(d[k]) for k in ks]
    lock = [F_LOCK(d[k]) for k in ks]
    area = [F_AREA(d[k]) for k in ks]
    same = sum(1 for k in ks if base and k in base and base[k]["digest"] == d[k]["digest"])
    hard = [("%s/s%d" % k) for k in ks if d[k]["hard_fails"]]
    # other-need floors: the safety half of the isolation claim
    others = {}
    for nd in ("hunger", "energy", "hygiene", "fun"):
        v = [d[k]["floors"][nd] for k in ks]
        others[nd] = (min(v), med(v))
    others["events"] = (min(d[k]["events"] for k in ks), med([d[k]["events"] for k in ks]))
    others["starved"] = (sum(1 for k in ks if d[k]["starved"]), med([d[k]["starved"] for k in ks]))
    out = dict(
        arm=name, n=len(ks), same=same, hard=hard,
        soc=(min(soc), max(soc), med(soc)),
        lock=(min(lock), max(lock), med(lock)),
        area=(min(area), max(area), med(area)),
        others=others, per_seed={("%s/s%d" % k): (F_SOC(d[k]), F_LOCK(d[k])) for k in ks},
    )
    if base:
        out["vs_base"] = sign_test(d, base, F_SOC)
    if null:
        out["vs_null_soc"] = sign_test(d, null, F_SOC)
        out["vs_null_lock"] = sign_test(d, null, F_LOCK, higher_is_better=False)
    return out


def main():
    arms = sys.argv[1:] or ["base", "null", "bsoc_05", "bsoc_10", "bsoc_15",
                            "bsoc_20", "bsoc_30", "ball_10", "bnon_10"]
    data = {a: load(a) for a in arms}
    base, null = data.get("base", {}), data.get("null", {})
    print("=" * 132)
    print("%-9s %3s %5s %-11s %-26s %-24s %-22s" % (
        "arm", "n", "同摘", "硬#01红", "social地板 min..max(中位)",
        "最长锁段 min..max(中位)", "锁面积 min..max(中位)"))
    print("=" * 132)
    rows = {}
    for a in arms:
        r = row(a, data[a], base if a != "base" else None, null if a != "null" else None)
        if not r:
            print("%-9s  (no data)" % a)
            continue
        rows[a] = r
        print("%-9s %3d %5d %-11s %6.2f..%6.2f (%6.2f)   %4d..%4d (%5.1f)     %5d..%5d (%6.1f)" % (
            a, r["n"], r["same"], (",".join(r["hard"]) or "无"),
            r["soc"][0], r["soc"][1], r["soc"][2],
            r["lock"][0], r["lock"][1], r["lock"][2],
            r["area"][0], r["area"][1], r["area"][2]))
    print()
    print("--- 逐 seed 配对符号检验（★判据：对着【零假设臂 null】判，不看红数）---")
    print("%-9s | %-28s | %-28s | %s" % (
        "arm", "vs base  social地板 好/坏/平 (p)", "vs NULL  social地板 好/坏/平 (p)",
        "vs NULL  最长锁段 好/坏/平 (p)"))
    for a in arms:
        r = rows.get(a)
        if not r:
            continue
        vb = r.get("vs_base")
        vn = r.get("vs_null_soc")
        vl = r.get("vs_null_lock")
        f = lambda t: ("%2d/%2d/%2d  p=%.4f" % t) if t else "        —        "
        print("%-9s | %-28s | %-28s | %s" % (a, f(vb), f(vn), f(vl)))
    print()
    print("--- 其它 need 的全局地板 min(中位) ——隔离的安全那一半 + 触底 seed 数 + 事件量 ---")
    print("%-9s %-15s %-15s %-15s %-15s %-8s %s" % (
        "arm", "hunger", "energy", "hygiene", "fun", "触底seed", "事件 min(中位)"))
    for a in arms:
        r = rows.get(a)
        if not r:
            continue
        o = r["others"]
        f = lambda t: "%6.2f(%6.2f)" % t
        print("%-9s %-15s %-15s %-15s %-15s %-8d %d(%d)" % (
            a, f(o["hunger"]), f(o["energy"]), f(o["hygiene"]), f(o["fun"]),
            o["starved"][0], o["events"][0], o["events"][1]))
    print()
    print("--- 逐 seed 明细 (social地板 / 最长锁段) ---")
    keys = sorted(set().union(*[set(rows[a]["per_seed"]) for a in rows])) if rows else []
    hdr = "%-10s" % "seed"
    for a in arms:
        if a in rows:
            hdr += "%-16s" % a
    print(hdr)
    for k in keys:
        line = "%-10s" % k
        for a in arms:
            if a not in rows:
                continue
            v = rows[a]["per_seed"].get(k)
            line += "%-16s" % (("%.2f/%d" % v) if v else "-")
        print(line)


if __name__ == "__main__":
    main()
