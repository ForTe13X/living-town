# -*- coding: utf-8 -*-
"""AA3 · 消费侧「被看见」的余量矩阵。

口径逐字照抄 docs/101（Z2）§一.3：
  余量 = 在这一格里，"成交次数 >= 豁免线" 的每个 seed 上，
         "该口径下有见证者的成交条数" 的【最小值】。
豁免线沿用 Invariants.CRAFT_MIN_WORKS = 5（若某 seed 成交 < 5 ⇒ 该 seed 记 '—'，不参与取最小）。
输出逐 seed 展布，不做任何平均（docs/41 §5）。
"""
import io, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MINW = 5
GRIDS = [
    ("N12 s1-12 60d",   "g1_n12_s1_12_d60.jsonl"),
    ("N12 s13-36 60d",  "g2a_n12_s13_36_d60.jsonl"),
    ("N12 s37-60 60d",  "g2b_n12_s37_60_d60.jsonl"),
    ("N16 s1-12 60d",   "g3_n16_s1_12_d60.jsonl"),
    ("零假设 s1-12 60d", "g4_null_n12_s1_12_d60.jsonl"),
    ("N12 s1-12 30d",   "g5_n12_s1_12_d30.jsonl"),
    ("零假设 s1-12 30d", "g5n_null_n12_s1_12_d30.jsonl"),
    ("N12 s1-12 20d",   "g6_n12_s1_12_d20.jsonl"),
    ("零假设 s1-12 20d", "g6n_null_n12_s1_12_d20.jsonl"),
]
DEFS = [
    ("D1 买家(钱真到手)", "D1_buyer"),
    ("D2 商贩在场",       "D2_vendor_here"),
    ("D3 旁人在场",       "D3_bystander"),
    ("D4 商贩+旁人",      "D4_both"),
    ("D5 付了钱+有旁人",  "D5_paid_bystander"),
]


def load(fn):
    p = os.path.join(HERE, fn)
    if not os.path.exists(p):
        return []
    out = []
    for line in io.open(p, encoding="utf-8"):
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


def main():
    w = io.open(os.path.join(HERE, "margin.txt"), "w", encoding="utf-8")

    def P(s=""):
        # 只写文件、不 print：Windows 控制台是 GBK，'⇒' 会 UnicodeEncodeError 把整份汇总打断
        w.write(s + "\n")

    P("=== AA3 · 消费侧清点（逐 seed，不给均值）· 豁免线 deals >= %d ===" % MINW)
    allmin = {k: [] for _, k in DEFS}
    for gname, fn in GRIDS:
        recs = load(fn)
        if not recs:
            P("%-16s  <缺文件 %s>" % (gname, fn))
            continue
        P("")
        P("── %s ── (%d 局)" % (gname, len(recs)))
        P("seed  deals  免费  自买  D1买家  D2商贩在场  D3旁人  D4两者  在场人次  在场0人  买家数")
        for r in recs:
            P("%4d %6d %5d %5d %7d %11d %7d %7d %9d %8d %7d" % (
                r["seed"], r["deals"], r["meals_free"], r["self_buy"],
                r["D1_buyer"], r["D2_vendor_here"], r["D3_bystander"], r["D4_both"],
                r["near_sum"], r["near_zero"], r["distinct_buyers"]))
        line = []
        for dname, key in DEFS:
            vals = [r[key] for r in recs if r["deals"] >= MINW]
            if not vals:
                line.append("%s=—" % dname)
                continue
            m = min(vals)
            allmin[key].append((gname, m))
            ties = [r["seed"] for r in recs if r["deals"] >= MINW and r[key] == m]
            line.append("%s 余量=%d (seed %s)" % (dname, m, ",".join(str(s) for s in ties)))
        P("  " + " ｜ ".join(line))
        exempt = [r["seed"] for r in recs if r["deals"] < MINW]
        P("  豁免(deals<%d)的 seed: %s" % (MINW, exempt if exempt else "无"))

    P("")
    P("=== 六格取最小（判定用的那一个数）===")
    P("口径                 逐格余量" )
    for dname, key in DEFS:
        per = allmin[key]
        if not per:
            P("%-18s  —" % dname)
            continue
        mn = min(v for _, v in per)
        where = [g for g, v in per if v == mn]
        P("%-18s  %s  ⇒ 最小 %d（%s）" % (
            dname, "  ".join("%s:%d" % (g.split()[0] + g.split()[-1], v) for g, v in per),
            mn, ", ".join(where)))

    # 分母与结构性数字
    P("")
    P("=== 结构性比例（全部逐 seed 汇总，标注展布）===")
    for gname, fn in GRIDS:
        recs = load(fn)
        if not recs:
            continue
        d = sum(r["deals"] for r in recs)
        if d == 0:
            continue
        P("%-16s deals=%d  免费=%d(%.0f%%)  自买=%d(%.0f%%)  D1=%d(%.0f%%)  D2=%d(%.0f%%)  D3=%d(%.0f%%)  "
          "赶集/(赶集+吃饭)=%.1f%%  pay带目击=%d" % (
              gname, d,
              sum(r["meals_free"] for r in recs), 100.0 * sum(r["meals_free"] for r in recs) / d,
              sum(r["self_buy"] for r in recs), 100.0 * sum(r["self_buy"] for r in recs) / d,
              sum(r["D1_buyer"] for r in recs), 100.0 * sum(r["D1_buyer"] for r in recs) / d,
              sum(r["D2_vendor_here"] for r in recs), 100.0 * sum(r["D2_vendor_here"] for r in recs) / d,
              sum(r["D3_bystander"] for r in recs), 100.0 * sum(r["D3_bystander"] for r in recs) / d,
              100.0 * sum(r["attempts_market"] for r in recs)
              / max(1, sum(r["attempts_market"] + r["attempts_eat"] for r in recs)),
              sum(r["pay_events_witnessed"] for r in recs)))
    w.close()


if __name__ == "__main__":
    main()
