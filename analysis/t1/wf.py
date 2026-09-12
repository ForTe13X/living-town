#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T1：t1_workfloor_probe 的汇总。用法：wf.py base.jsonl [var.jsonl]

回答两件事：
  ① 在班的本职广告【赢率】在不同【镇库分档】上有没有差别 —— 这就是"产出侧开不开环"的判据。
  ② 机会去哪儿了：没上台 / 上台输了 / 输给谁。
逐 seed 打印，**不做平均**（docs/41 §5）。
"""
import json, io, sys

FOCUS = ["面点师", "渔夫", "咖啡师", "杂役", "泥瓦匠", "环卫工", "教书先生", "木匠", "商贩"]
BUCK = ["empty", "low", "mid", "high"]


def load(p):
    return [json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip()]


def cell(o, w):
    return "%3d/%4d %5.1f%%" % (w, o, 100.0 * w / o) if o else "      -/-     "


def stock_table(recs, tag):
    print("=== [%s] 在班 offer 的【本职赢率】× 决策时镇库分档（%d seed 汇总）===" % (tag, len(recs)))
    print("岗位   | 空(0 件)       | 低(<=1/4 cap)  | 中(1/4~3/4)    | 高(>3/4 cap)")
    for t in FOCUS:
        tot = {}
        for k in BUCK:
            tot[k] = [0, 0]
        seen = False
        for r in recs:
            b = r["jobs"].get(t)
            if not b:
                continue
            seen = True
            for k in BUCK:
                tot[k][0] += b["off_" + k]
                tot[k][1] += b["win_" + k]
        if not seen:
            continue
        print("%-6s | %s | %s | %s | %s" % (t, cell(*tot["empty"]), cell(*tot["low"]),
                                            cell(*tot["mid"]), cell(*tot["high"])))
    print()


def per_seed(recs, tag):
    print("=== [%s] 逐 seed 逐岗位：在班决策点 / 本职上台 / 赢 / 赢率 / 完成数 ===" % tag)
    for r in sorted(recs, key=lambda x: x["seed"]):
        for t in FOCUS:
            b = r["jobs"].get(t)
            if not b:
                continue
            soc = sum(v for k, v in b["lost_to"].items() if k.startswith("social:"))
            wr = 100.0 * b["win_inshift"] / b["offer_inshift"] if b["offer_inshift"] else 0.0
            print("  s%-3d %-6s dp=%3d off=%3d win=%3d (%5.1f%%) 输给社交 %3d/%3d  完成=%2d"
                  % (r["seed"], t, b["dp_inshift"], b["offer_inshift"], b["win_inshift"],
                     wr, soc, b["loss_inshift"], r["work_by_title"].get(t, 0)))
        print()


def main():
    for p in sys.argv[1:]:
        recs = load(p)
        stock_table(recs, p)
    if len(sys.argv) == 2:
        per_seed(load(sys.argv[1]), sys.argv[1])


main()
