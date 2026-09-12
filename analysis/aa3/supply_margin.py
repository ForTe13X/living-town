# -*- coding: utf-8 -*-
"""AA3 · #40 的【连续余量】而不是红数（docs/103 §四：红数不是判据，要对着零假设臂用连续余量判）。

四条臂（seeds 31-60 × 60 天 × N=12，全部由 game/bench/aa3_vendor_census.gd 同一支探针出）：
  ablate  = 摘掉 trade_credit 键（= 改前，同一棵树）
  null    = ablate + `utility.obj_dist_penalty` 0.400→0.401（语义为零的扰动）
  st0     = 出货树，但 trade_credit.standing = 0.0（只写目击者/信念/记忆，不动声誉）
  ship    = 出货树（standing = 0.5）

两条连续量对应 #40 的两条臂：
  上限臂「缺货绝迹」→ 全年零缺货的货数（越多越糟；判据是"多数不缺"）
  下限臂「长期供不应求」→ 逐货 produced/consumed 的最小值（SUPPLY_FLOOR = 0.50）
"""
import io, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SP = (r"C:/Users/yp/AppData/Local/Temp/claude/E--Documents-Dev-June-26th/"
      r"4ab4ceee-f2b5-4791-b52a-1f1d70c374f4/scratchpad")
ARMS = [
    ("ablate(改前)", os.path.join(SP, "ab_3160.jsonl")),
    ("null(零假设)", os.path.join(SP, "null_3160.jsonl")),
    ("st0(standing=0)", os.path.join(SP, "st0_3160.jsonl")),
    ("ship(standing=0.5)", os.path.join(HERE, "ship_3160.jsonl")),
]


def load(p):
    return [json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip()]


def main():
    w = io.open(os.path.join(HERE, "supply_margin.txt"), "w", encoding="utf-8")
    data = {}
    for name, p in ARMS:
        if not os.path.exists(p):
            w.write("%s <缺 %s>\n" % (name, p))
            continue
        data[name] = {r["seed"]: r for r in load(p)}
    goods = sorted({g for d in data.values() for r in d.values() for g in r["prod_consumed"]})
    w.write("货物集合：%s\n\n" % ", ".join(goods))
    w.write("seed | " + " | ".join("%-18s" % n for n in data) + "\n")
    w.write("     | " + " | ".join("零缺货货数/最差满足率  " for _ in data) + "\n")
    agg = {n: {"zero": [], "worst": []} for n in data}
    for sd in sorted(next(iter(data.values())).keys()):
        cells = []
        for n, d in data.items():
            r = d[sd]
            cons = r["prod_consumed"]
            short = r["prod_short"]
            prod = r["prod_produced"]
            zero = sum(1 for g in goods if int(cons.get(g, 0)) > 0 and int(short.get(g, 0)) == 0)
            ratios = [float(prod.get(g, 0)) / float(cons[g]) for g in goods
                      if int(cons.get(g, 0)) > 0]
            worst = min(ratios) if ratios else 1.0
            agg[n]["zero"].append(zero)
            agg[n]["worst"].append(worst)
            cells.append("%d / %.3f            " % (zero, worst))
        w.write("%4d | " % sd + " | ".join(c[:18] for c in cells) + "\n")
    w.write("\n=== 展布（不给均值，给区间与逐 seed 的极值；并列一起报）===\n")
    for n in data:
        z = agg[n]["zero"]
        o = agg[n]["worst"]
        seeds = sorted(next(iter(data.values())).keys())
        zmax = max(z)
        omin = min(o)
        w.write("%-20s 零缺货货数 min=%d max=%d（max 出现在 seed %s）；"
                "最差满足率 min=%.3f（seed %s） max=%.3f  ；零缺货≥4 的 seed 数=%d\n"
                % (n, min(z), zmax,
                   ",".join(str(seeds[i]) for i, v in enumerate(z) if v == zmax),
                   omin, ",".join(str(seeds[i]) for i, v in enumerate(o) if v == omin),
                   max(o), sum(1 for v in z if v >= 4)))
    w.close()


if __name__ == "__main__":
    main()
