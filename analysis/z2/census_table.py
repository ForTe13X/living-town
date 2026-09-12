#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Z2 · 逐岗位「产出被看见」清点表（docs/41 §5：逐 seed 给展布，探针外也不做平均）。

输入：`game/bench/v1_social_census.gd` 的 jsonl（**不重写探针**，docs/99 §二 明令）。
量的是三列，而它们不是同一件事：
  produce     该岗位这一局写出了几条 produce 事件
  bys>0       其中【产出那一刻身边有人】的条数   ← 铺开之后「被看见」的**上界**
  witnessed   事件上真的带了目击者的条数         ← 改前只有环卫工非零

★第一件事是【校准量具】：对已经开着 craft_credit 的岗位，`bys>0` 与 `witnessed`
  必须逐 seed 相等（人次也必须相等）。相等 ⇒ V1 在探针文件头声明的"同量级估计"
  在这一格上其实**逐条精确** ⇒ 才有资格拿 `bys>0` 去预测别的岗位。

★第二件事是【余量】：#41 的判据面是"produce >= CRAFT_MIN_WORKS(5) 的 seed 必须至少
  被看见一次"。所以要报的不是平均在场人数（V1 报的那一列），而是
  **每个 seed 上"至少有一个人在场"的产出条数的【最小值】**——铺开的余量就是这个数。

用法：python analysis/z2/census_table.py <a.jsonl> [<b.jsonl> ...]
"""
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

ORDER = ["面点师", "渔夫", "杂役", "木匠", "咖啡师", "教书先生", "环卫工", "泥瓦匠", "商贩"]
MIN_WORKS = 5          # Invariants.CRAFT_MIN_WORKS（豁免线）


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def cols(rows, t):
    prod, bys, wit, slots, holder = [], [], [], [], ""
    for r in rows:
        j = r["jobs"].get(t)
        if j is None:
            continue
        holder = j["holder"]
        b = j["produce_bystanders"]
        prod.append(int(j["ev_produce"]))
        bys.append(int(b["n"]) - int(b["zero"]))
        wit.append(int(j["ev_produce_witnessed"]))
        slots.append(int(b["sum"]))
    return holder, prod, bys, wit, slots


def table(rows, label):
    print("=" * 110)
    print("## %s   n=%d seed: %s" % (label, len(rows), ",".join(str(r["seed"]) for r in rows)))
    print("=" * 110)
    print("%-7s %-5s %9s %8s %8s %9s %9s %9s   %s" % (
        "岗位", "持有", "Σproduce", "Σbys>0", "Σ人次", "bys>0率", "min(p)", "★余量", "会红的 seed（p>=5 且 bys>0==0）"))
    for t in ORDER:
        holder, prod, bys, wit, slots = cols(rows, t)
        if not prod:
            continue
        pairs = list(zip([r["seed"] for r in rows], prod, bys))
        live = [(s, p, b) for (s, p, b) in pairs if p >= MIN_WORKS]
        red = [s for (s, p, b) in live if b == 0]
        margin = min([b for (_s, _p, b) in live]) if live else -1
        rate = (float(sum(bys)) / sum(prod)) if sum(prod) else 0.0
        print("%-7s %-5s %9d %8d %8d %9.2f %9d %9s   %s" % (
            t, holder, sum(prod), sum(bys), sum(slots), rate, min(prod),
            ("n/a" if margin < 0 else str(margin)),
            ("—" if not red else "%d 个: %s" % (len(red), ",".join(map(str, red))))))
    print()
    print("-- 逐 seed 展布（produce / bys>0；* = 该 seed 产出 < %d，#41 豁免）--" % MIN_WORKS)
    for t in ORDER:
        holder, prod, bys, wit, slots = cols(rows, t)
        if not prod or sum(prod) == 0:
            continue
        cells = []
        for p, b in zip(prod, bys):
            cells.append("%d/%d%s" % (p, b, "*" if p < MIN_WORKS else ""))
        print("%-7s %-5s %s" % (t, holder, " ".join(cells)))
    print()


def calib(rows, label):
    print("-- 量具校准（%s）：已开 craft_credit 的岗位，bys>0 与 witnessed 是否逐 seed 相等 --" % label)
    any_on = False
    ok = True
    for t in ORDER:
        holder, prod, bys, wit, slots = cols(rows, t)
        if not prod or sum(wit) == 0:
            continue
        any_on = True
        wslots = []
        for r in rows:
            j = r["jobs"].get(t)
            if j is not None:
                wslots.append(int(j["ev_produce_witness_slots"]))
        bad = [(r["seed"], b, w, s, ws) for r, b, w, s, ws in zip(rows, bys, wit, slots, wslots)
               if b != w or s != ws]
        print("   %-7s bys>0 = %s" % (t, ",".join(map(str, bys))))
        print("   %-7s wit   = %s" % ("", ",".join(map(str, wit))))
        print("   %-7s 人次估 = %s" % ("", ",".join(map(str, slots))))
        print("   %-7s 人次实 = %s" % ("", ",".join(map(str, wslots))))
        if bad:
            ok = False
            print("      ★不符: %s" % bad)
    if not any_on:
        print("   （这一格没有任何岗位开着 craft_credit —— 无法校准）")
    else:
        print("   => %s" % ("逐 seed 逐位相同 ⇒ 估计量在这一格上是精确的"
                            if ok else "★有不符 ⇒ 估计量只能当上界读"))
    print()


def leaks(rows, label):
    print("-- confide / leak / betray 的真世界条数（%s）--" % label)
    c = [int(r["by_type"].get("confide", {}).get("n", 0)) for r in rows]
    lk = [int(r["by_type"].get("leak", {}).get("n", 0)) for r in rows]
    bt = [int(r["by_type"].get("betray", {}).get("n", 0)) for r in rows]
    print("   confide 逐 seed: %s   （合计 %d）" % (",".join(map(str, c)), sum(c)))
    print("   leak    逐 seed: %s   （合计 %d）" % (",".join(map(str, lk)), sum(lk)))
    print("   betray  逐 seed: %s   （合计 %d）" % (",".join(map(str, bt)), sum(bt)))
    print()


def digests(rows, label):
    print("digest(%s):" % label)
    print("   " + " ".join(r["digest"] for r in rows))
    print()


if __name__ == "__main__":
    for p in sys.argv[1:]:
        rs = load(p)
        table(rs, p)
        calib(rs, p)
        leaks(rs, p)
        digests(rs, p)
