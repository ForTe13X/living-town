# R1 · ScaleSupply 日志汇总。**只报展布不报均值**（docs/41 §5）。
# 用法: python analysis/r1/sum.py analysis/r1/base_n12.log [...]
import json, sys, io, os

GOODS = ["口粮", "柴薪", "屋瓦", "豆子", "话本", "整洁"]
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def load(path):
    recs = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.strip()
        if ln.startswith("[SCALE] "):
            recs.append(json.loads(ln[8:]))
    return recs


def rows(recs):
    out = []
    for r in recs:
        g = r["final"]["goods"]
        row = {"seed": r["seed"], "n": r["n_agents"], "inv40": r["inv40_ok"],
               "hard": r["hard_fails"], "soft": r["soft_fails"],
               "starved": r["starved"], "digest": r["digest"],
               "work": r.get("work_by_title", {})}
        for gid in GOODS:
            d = g.get(gid, {})
            row[gid] = (d.get("rate", -1), d.get("shortage_days", -1),
                        d.get("shortage_events", -1), d.get("gated", False))
        out.append(row)
    return out


def report(path):
    recs = load(path)
    if not recs:
        print("!! 无数据: %s" % path)
        return
    rr = rows(recs)
    n = rr[0]["n"]
    print("=" * 100)
    print("%s   N=%d  seeds=%s" % (os.path.basename(path), n, [r["seed"] for r in rr]))
    # 逐 seed 逐货：满足率 / 断供天数
    hdr = "seed | " + " | ".join("%-22s" % g for g in GOODS) + " | 最差货  | #40 | 零缺货货数"
    print(hdr)
    zc_all = []
    shortc_all = []
    for r in rr:
        cells = []
        worst = 9.9
        zc = 0
        sc = 0
        for g in GOODS:
            rate, sd, se, gated = r[g]
            mark = "" if gated else "*"
            cells.append("%5.3f%s d=%-2d e=%-5d" % (rate, mark, sd, se))
            if gated:
                worst = min(worst, rate)
                if sd == 0:
                    zc += 1
                else:
                    sc += 1
        zc_all.append(zc)
        shortc_all.append(sc)
        print("%4d | %s | %6.3f | %s | %d" % (
            r["seed"], " | ".join(cells), worst,
            "绿" if r["inv40"] else "红", zc))
    print("-" * 100)
    print("零缺货货数 逐 seed: %s   → 极值 min=%d (seed %s) max=%d (seed %s)" % (
        zc_all, min(zc_all), [rr[i]["seed"] for i, v in enumerate(zc_all) if v == min(zc_all)],
        max(zc_all), [rr[i]["seed"] for i, v in enumerate(zc_all) if v == max(zc_all)]))
    print("仍会缺货的货数 逐 seed: %s → 极值 min=%d (seed %s) max=%d (seed %s)" % (
        shortc_all, min(shortc_all), [rr[i]["seed"] for i, v in enumerate(shortc_all) if v == min(shortc_all)],
        max(shortc_all), [rr[i]["seed"] for i, v in enumerate(shortc_all) if v == max(shortc_all)]))
    # 逐货：零缺货 seed 数 / 满足率展布
    print("逐货汇总（%d 个 seed）：" % len(rr))
    for g in GOODS:
        rates = sorted(r[g][0] for r in rr)
        sds = [r[g][1] for r in rr]
        zs = sum(1 for r in rr if r[g][1] == 0)
        gated = sum(1 for r in rr if r[g][3])
        print("  %-4s 零缺货 %2d/%2d seed | 断供天数 %2d..%2d | 满足率 %5.3f..%5.3f | gated %d/%d" % (
            g, zs, len(rr), min(sds), max(sds), rates[0], rates[-1], gated, len(rr)))
    hf = [(r["seed"], r["hard"]) for r in rr if r["hard"]]
    sf = [(r["seed"], r["soft"]) for r in rr if r["soft"]]
    print("硬失败: %s" % (hf or "无"))
    print("软失败: %s" % (sf or "无"))
    # 逐岗位在班完成（展布）
    titles = sorted({t for r in rr for t in r["work"]})
    print("逐岗位在班完成次数（min..max over seeds）：")
    for t in titles:
        v = sorted(int(r["work"].get(t, 0)) for r in rr)
        print("  %-6s %s  (min=%d max=%d)" % (t, v, v[0], v[-1]))


for p in sys.argv[1:]:
    report(p)
