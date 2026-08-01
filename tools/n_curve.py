#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""V2 · 逐 N 曲线的汇总器（配 tools/n_sweep.py 的原始 jsonl 用）。

**它自己的三条纪律**（docs/41 §5 / §2.5 / S2 编号 73 的那条统一结论）：

  ① **零冻结字面量。** `SUPPLY_FLOOR` / `SUPPLY_MIN_DEMAND` / `SUPPLY_MIN_DAYS` / 上限臂的
     `never_short*2 > gated_n` / `SOFT_RATE` / `soft_threshold` 全部**每次运行现从 .gd 源码解析**，
     解析不到就退出非 0，**不许回落到默认值**。S2 已经证过：打印冻结字面量的臂全过期，
     每次重算并打印的臂至今全准。跑一次 `--show-consts` 就能看见它今天读到了什么、从哪一行读的。

  ② **给展布不给均值。** 每一格默认打印**逐 seed 的全部值**；极值**连并列一起报**。
     任何"均值/中位数"都必须与展布同时出现，不单独出现。

  ③ **判据重算 vs 引擎判决必须对上。** 每条记录都拿本脚本按源码重算的红绿去比
     ScaleSupply 记的 `inv40_ok`（那是引擎里 `Invariants.check_all` 的真判决）。
     对不上 ⇒ 打印并计入 `oracle_mismatch`，`--strict` 下直接退出非 0。
     ⇒ **这一条就是本量具的"负对照"的正面一半**：它保证我没有抄错判据。
     反面一半是 `--selftest`（见下）。

`--selftest`（**负对照，跑出来的**）：在**真实记录**上做四个定向变异，逐条断言汇总器的判决跟着翻：
   ① 把足够多的货的 shortage_days 抹成 0        ⇒ 上限臂必须翻红
   ② 把一种货的 rate 压到 SUPPLY_FLOOR 之下      ⇒ 下限臂必须翻红
   ③ 把一条本来红的上限臂记录的 shortage_days 抬到 1 ⇒ 必须翻绿
   ④ 把 demand 压到 SUPPLY_MIN_DEMAND 之下       ⇒ 该货必须退出判决（gated_n 少 1）
   再加一条**针对纪律①自己**的：把源码常量换掉重算，判决必须跟着动
   （否则说明脚本里还藏着一个冻结字面量）。

用法：
  python tools/n_curve.py --raw analysis/v2/raw [--strict] [--json out.json]
  python tools/n_curve.py --selftest --raw analysis/v2/raw
  python tools/n_curve.py --show-consts
"""
import argparse
import collections
import glob
import json
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
INV = os.path.join(ROOT, "game", "bench", "Invariants.gd")
HARN = os.path.join(ROOT, "game", "bench", "Harness.gd")


# ── 纪律① 现读源码常量 ───────────────────────────────────────────────────────────
def _grep_const(path, name, cast):
    """从 .gd 里现读 `const NAME := <literal>`。读不到 ⇒ 抛，绝不回落默认值。"""
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^\s*const\s+%s\s*:=\s*([0-9.]+)\s*$" % re.escape(name), txt, re.M)
    if not m:
        raise SystemExit("读不到 %s 的 const %s —— 判据可能改名/搬家，拒绝用默认值继续"
                         % (os.path.relpath(path, ROOT), name))
    line = txt.count("\n", 0, m.start()) + 1
    return cast(m.group(1)), "%s:%d" % (os.path.relpath(path, ROOT).replace(os.sep, "/"), line)


def load_consts():
    c = {}
    c["SUPPLY_FLOOR"], c["_src_floor"] = _grep_const(INV, "SUPPLY_FLOOR", float)
    c["SUPPLY_MIN_DEMAND"], c["_src_mind"] = _grep_const(INV, "SUPPLY_MIN_DEMAND", int)
    c["SUPPLY_MIN_DAYS"], c["_src_mindays"] = _grep_const(INV, "SUPPLY_MIN_DAYS", int)
    c["SOFT_RATE"], c["_src_softrate"] = _grep_const(HARN, "SOFT_RATE", float)
    # 上限臂的形状也现读，不写死 "×2 >"
    txt = open(INV, encoding="utf-8", errors="replace").read()
    m = re.search(r"if\s+gated_n\s*>=\s*(\d+)\s+and\s+never_short\.size\(\)\s*\*\s*(\d+)\s*>\s*gated_n", txt)
    if not m:
        raise SystemExit("读不到 #40 上限臂的形状（`gated_n >= K and never_short.size()*M > gated_n`）"
                         " —— 判据可能被改写，拒绝继续")
    c["HIGH_MIN_GATED"] = int(m.group(1))
    c["HIGH_MULT"] = int(m.group(2))
    c["_src_high"] = "game/bench/Invariants.gd:%d" % (txt.count("\n", 0, m.start()) + 1)
    # soft_threshold 的形状（ceil(n*rate) 上限 n-1；n<=1 → 0）也现读，只做存在性校验
    t2 = open(HARN, encoding="utf-8", errors="replace").read()
    if "mini(int(ceil(float(n) * SOFT_RATE)), n - 1)" not in t2:
        raise SystemExit("Harness.soft_threshold 的形状变了 —— 拒绝用旧公式继续")
    return c


def soft_threshold(n, soft_rate):
    if n <= 1:
        return 0
    return min(int(math.ceil(n * soft_rate)), n - 1)


# ── 判据重算（逐字对齐 Invariants.gd #40 的两条臂）────────────────────────────────
def verdict(goods, days_run, c):
    """返回 (gated_ids, never_short_ids, low_ids, arm_low, arm_high)。"""
    gated, never_short, low = [], [], []
    for gid, g in sorted(goods.items()):
        if not g.get("demanded", False):
            continue
        if int(g.get("served", 0)) <= 0:
            continue                       # 实耗=0 → 断链臂管，不进满足率臂
        if int(g.get("demand", 0)) < c["SUPPLY_MIN_DEMAND"] or days_run < c["SUPPLY_MIN_DAYS"]:
            continue
        gated.append(gid)
        if int(g.get("shortage_days", -1)) == 0:
            never_short.append(gid)
        if float(g.get("rate", 1.0)) < c["SUPPLY_FLOOR"]:
            low.append(gid)
    arm_low = len(low) > 0
    arm_high = (len(gated) >= c["HIGH_MIN_GATED"]
                and len(never_short) * c["HIGH_MULT"] > len(gated))
    return gated, never_short, low, arm_low, arm_high


def worst_rate(goods, gated_ids):
    """进判决的货里最差的满足率 + 是哪一种（并列全给）。"""
    if not gated_ids:
        return None, []
    vals = [(float(goods[g]["rate"]), g) for g in gated_ids]
    lo = min(v for v, _ in vals)
    return lo, sorted(g for v, g in vals if v == lo)


# ── 读原始数据 ───────────────────────────────────────────────────────────────────
FNAME = re.compile(r"^(?P<arm>[a-z0-9]+)_n(?P<n>\d+)_s\d+-\d+\.jsonl$")


def load_raw(raw_dir):
    cells = collections.defaultdict(dict)      # (arm, N) -> {seed: rec}
    for p in sorted(glob.glob(os.path.join(raw_dir, "*.jsonl"))):
        m = FNAME.match(os.path.basename(p))
        if not m:
            continue
        arm, n = m.group("arm"), int(m.group("n"))
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if int(r["n_agents"]) != n:
                raise SystemExit("%s: 文件名说 N=%d，记录里 n_agents=%s" % (p, n, r["n_agents"]))
            s = int(r["seed"])
            if s in cells[(arm, n)]:
                raise SystemExit("(arm=%s,N=%d,seed=%d) 出现两次 —— 原始数据被两次运行交织过" % (arm, n, s))
            cells[(arm, n)][s] = r
    return cells


def fmt_ties(vals_by_seed, pick):
    """极值 + 并列的 seed 全报（docs/41：报极值连并列一起报）。"""
    if not vals_by_seed:
        return "—"
    v = pick(vals_by_seed.values())
    ties = sorted(s for s, x in vals_by_seed.items() if x == v)
    return "%.3f (seed %s)" % (v, ",".join(str(s) for s in ties)) if isinstance(v, float) \
        else "%d (seed %s)" % (v, ",".join(str(s) for s in ties))


def analyse(cells, c, strict=False, quiet=False):
    out = {"consts": {k: v for k, v in c.items()}, "cells": {}}
    mismatches = []
    for (arm, n) in sorted(cells, key=lambda k: (k[0], k[1])):
        recs = cells[(arm, n)]
        seeds = sorted(recs)
        rows = {}
        for s in seeds:
            r = recs[s]
            goods = r["final"]["goods"]
            gated, never, low, a_low, a_high = verdict(goods, int(r["final"]["days_run"]), c)
            red = a_low or a_high
            eng_ok = bool(r["inv40_ok"])
            if red == eng_ok:
                # 允许的唯一一种不一致：#40 因【断链】红，而两条满足率臂都绿
                if not (eng_ok is False and red is False):
                    mismatches.append((arm, n, s, red, eng_ok, r.get("inv40_detail", "")))
                else:
                    mismatches.append((arm, n, s, red, eng_ok, "DEADCHAIN? " + str(r.get("inv40_detail", ""))))
            wr, wg = worst_rate(goods, gated)
            rows[s] = {
                "gated_n": len(gated), "never_short": sorted(never), "never_n": len(never),
                "low": low, "arm_low": a_low, "arm_high": a_high, "red": red,
                "worst_rate": wr, "worst_good": wg,
                "hard_fails": r.get("hard_fails", []),
                "soft_fails": r.get("soft_fails", []),
                "digest": r.get("digest"),
                "work_by_title": r.get("work_by_title", {}),
                "social_events": r.get("social_events"),
                "shortage_days": {g: int(x["shortage_days"]) for g, x in goods.items()},
                "rate": {g: float(x["rate"]) for g, x in goods.items()},
                "gated_ids": gated,
            }
        out["cells"]["%s@N%d" % (arm, n)] = {"arm": arm, "n": n, "seeds": seeds, "rows": rows}
    out["oracle_mismatch"] = mismatches
    if mismatches and not quiet:
        print("!!! 判据重算与引擎判决不一致 %d 条：" % len(mismatches))
        for m in mismatches[:20]:
            print("   arm=%s N=%d seed=%d recomputed_red=%s inv40_ok=%s  %s" % m)
    if mismatches and strict:
        sys.exit(1)
    return out


def report(res, c):
    L = []
    ap = L.append
    ap("常量（**现从源码读**，不是本文件里的字面量）：")
    ap("  SUPPLY_FLOOR=%s  ← %s" % (c["SUPPLY_FLOOR"], c["_src_floor"]))
    ap("  SUPPLY_MIN_DEMAND=%s  ← %s" % (c["SUPPLY_MIN_DEMAND"], c["_src_mind"]))
    ap("  SUPPLY_MIN_DAYS=%s  ← %s" % (c["SUPPLY_MIN_DAYS"], c["_src_mindays"]))
    ap("  上限臂 gated_n>=%d and never_short*%d>gated_n  ← %s" % (c["HIGH_MIN_GATED"], c["HIGH_MULT"], c["_src_high"]))
    ap("  SOFT_RATE=%s  ← %s" % (c["SOFT_RATE"], c["_src_softrate"]))
    ap("  判据重算 vs 引擎判决 不一致条数 = %d" % len(res["oracle_mismatch"]))
    ap("")
    arms = sorted({v["arm"] for v in res["cells"].values()})
    Ns = sorted({v["n"] for v in res["cells"].values()})

    for arm in arms:
        ap("=" * 100)
        ap("### 臂 %s" % arm)
        ap("%-4s %-6s | %-28s | %s" % ("N", "红/总", "红的 seed（臂）", "逐 seed 零缺货货数（never_short）"))
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            reds = [s for s in seeds if rows[s]["red"]]
            tag = ",".join("%d%s" % (s, "↑" if rows[s]["arm_high"] else "") + ("↓" if rows[s]["arm_low"] else "")
                           for s in reds) or "—"
            nev = " ".join(str(rows[s]["never_n"]) for s in seeds)
            ap("%-4d %-6s | %-28s | %s" % (n, "%d/%d" % (len(reds), len(seeds)), tag, nev))
        ap("")
        ap("%-4s | %s" % ("N", "逐 seed 最差货满足率"))
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            vals = " ".join(("%.3f" % rows[s]["worst_rate"]) if rows[s]["worst_rate"] is not None else "  -  "
                            for s in seeds)
            wb = {s: rows[s]["worst_rate"] for s in seeds if rows[s]["worst_rate"] is not None}
            ap("%-4d | %s" % (n, vals))
            ap("     | min %s   max %s" % (fmt_ties(wb, min), fmt_ties(wb, max)))
        ap("")
        ap("%-4s | %s" % ("N", "逐货【全年零缺货】的 seed 数"))
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            cnt = collections.Counter()
            for s in seeds:
                for g in rows[s]["never_short"]:
                    cnt[g] += 1
            ap("%-4d | %s" % (n, "  ".join("%s %d/%d" % (g, cnt[g], len(seeds)) for g in sorted(cnt, key=lambda x: -cnt[x]))))
        ap("")
    # 三条臂并排（这是"是不是回归"那个问题的唯一可读形态）
    ap("=" * 100)
    ap("### 三条臂并排：逐 N 的 `#40` 红数（下↓ / 上↑ 分开）")
    ap("%-4s | %s" % ("N", " | ".join("%-22s" % a for a in arms)))
    for n in Ns:
        row = []
        for arm in arms:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                row.append("%-22s" % "—")
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            lo = [s for s in seeds if rows[s]["arm_low"]]
            hi = [s for s in seeds if rows[s]["arm_high"]]
            row.append("%-22s" % ("%d/%d ↓%s ↑%s" % (
                len(set(lo + hi)), len(seeds),
                ",".join(map(str, lo)) or "-", ",".join(map(str, hi)) or "-")))
        ap("%-4d | %s" % (n, " | ".join(row)))
    ap("")
    # 逐货【零缺货】的边际概率 + 上限臂的独立模型
    ap("=" * 100)
    ap("### 上限臂的分解：结构底座（豆子/话本）× 标定四货（口粮/柴薪/屋瓦/整洁）")
    ap("  上限臂要 never_short*%d > gated_n；gated_n=6 时 ⇒ 需要【6 种里 4 种】全年零缺货。" % c["HIGH_MULT"])
    ap("  下面把 6 个货的边际 P(全年零缺货) 逐个列出，再按【彼此独立】算一次 P(ns>=4) 作为零模型。")
    ap("  ⚠ 独立是一个**假设**，不是测量；它在这里的用处是回答'这条曲线的形状用边际概率就能解释吗'。")
    STRUCT = ["豆子", "话本"]
    TOWN = ["口粮", "柴薪", "屋瓦", "整洁"]
    ap("%-6s %-4s %-4s | %-20s | %-30s | %-8s %s" % (
        "arm", "N", "n", "结构底座 P", "标定四货 P", "E[ns]", "P(ns>=4) 实测 / 独立模型"))
    for arm in arms:
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            m = len(seeds)
            if m == 0:
                continue
            p = {}
            for g in STRUCT + TOWN:
                p[g] = sum(1 for s in seeds if g in rows[s]["never_short"]) / float(m)
            tot = 0.0
            gs = STRUCT + TOWN
            for mask in range(1 << len(gs)):
                bits = [(mask >> i) & 1 for i in range(len(gs))]
                if sum(bits) * c["HIGH_MULT"] <= len(gs):
                    continue
                pr = 1.0
                for b, g in zip(bits, gs):
                    pr *= p[g] if b else (1 - p[g])
                tot += pr
            obs = sum(1 for s in seeds if rows[s]["arm_high"]) / float(m)
            ap("%-6s %-4d %-4d | %-20s | %-30s | %-8.2f 实测 %.3f / 模型 %.3f" % (
                arm, n, m,
                " ".join("%s%.2f" % (g, p[g]) for g in STRUCT),
                " ".join("%s%.2f" % (g, p[g]) for g in TOWN),
                sum(p.values()), obs, tot))
    ap("")
    # 12-seed 连续窗口的软门判决（CI 的形状）
    ap("=" * 100)
    ap("### CI 形状：把每一格切成【连续 12 个 seed】的窗口，逐窗口跑 Harness 的软通过率门")
    thr = soft_threshold(12, c["SOFT_RATE"])
    ap("  soft_threshold(12) = %d ⇒ 一个 12-seed 窗口里红 ≥ %d 个就破门" % (thr, 12 - thr + 1))
    ap("%-6s %-4s | %s" % ("arm", "N", "各 12-seed 窗口的红数（窗口起点 seed）"))
    for arm in arms:
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            rows, seeds = cell["rows"], cell["seeds"]
            wins = []
            for i in range(0, len(seeds) - 11):
                w = seeds[i:i + 12]
                r = sum(1 for s in w if rows[s]["red"])
                wins.append("s%d:%d%s" % (w[0], r, "破" if r > 12 - thr else ""))
            ap("%-6s %-4d | %s" % (arm, n, " ".join(wins)))
    ap("")
    # 硬不变量
    ap("### 硬/软不变量的落点（#40 之外的那些 —— 一格 CI 会不会红，不是只由 #40 决定）")
    for arm in arms:
        for n in Ns:
            k = "%s@N%d" % (arm, n)
            if k not in res["cells"]:
                continue
            cell = res["cells"][k]
            hf = {s: cell["rows"][s]["hard_fails"] for s in cell["seeds"] if cell["rows"][s]["hard_fails"]}
            sf = collections.defaultdict(list)
            for s in cell["seeds"]:
                for i in cell["rows"][s]["soft_fails"]:
                    sf[int(i)].append(s)
            bits = []
            if hf:
                bits.append("硬 %s" % hf)
            for i in sorted(sf):
                if i == 40:
                    continue
                bits.append("软 #%d 红 %d 个 seed %s" % (i, len(sf[i]), sf[i]))
            if bits:
                ap("  %-5s N=%-3d %s" % (arm, n, " | ".join(bits)))
    return "\n".join(L)


# ── 负对照 ───────────────────────────────────────────────────────────────────────
def selftest(raw_dir, c):
    cells = load_raw(raw_dir)
    if not cells:
        sys.exit("selftest 需要真实记录（--raw 指向的目录是空的）")
    # 挑一条今天是绿的记录做变异
    base = None
    for key in sorted(cells):
        for s in sorted(cells[key]):
            r = cells[key][s]
            g, nv, lo, al, ah = verdict(r["final"]["goods"], int(r["final"]["days_run"]), c)
            if not (al or ah) and len(g) >= c["HIGH_MIN_GATED"]:
                base = (key, s, r)
                break
        if base:
            break
    if base is None:
        sys.exit("selftest 找不到一条绿的记录当底座")
    (arm, n), sd, r = base
    goods0 = r["final"]["goods"]
    days = int(r["final"]["days_run"])
    g0, nv0, lo0, al0, ah0 = verdict(goods0, days, c)
    print("底座：arm=%s N=%d seed=%d  gated=%d never_short=%d arm_low=%s arm_high=%s"
          % (arm, n, sd, len(g0), len(nv0), al0, ah0))
    ok = True

    def chk(name, cond, extra=""):
        nonlocal ok
        print("  %s %s %s" % ("✅" if cond else "❌", name, extra))
        ok = ok and cond

    # ① 上限臂必须能被推红。**先把全部 gated 货压成"缺过一天"再放开恰好 need 种**，
    #    否则底座上本来就零缺货的那几种会混进来，测的就不是阈值而是"多多益善"。
    need = len(g0) // c["HIGH_MULT"] + 1

    def _with_never(k):
        m = json.loads(json.dumps(goods0))
        for gid in g0:
            m[gid]["shortage_days"] = 1
        for gid in g0[:k]:
            m[gid]["shortage_days"] = 0
        return m

    _, nv1, _, al1, ah1 = verdict(_with_never(need), days, c)
    chk("① 恰好 %d/%d 种货零缺货 ⇒ 上限臂翻红" % (need, len(g0)), ah1 and not al1,
        "(never_short=%d/%d)" % (len(nv1), len(g0)))

    # ② 下限臂必须能被推红
    mut = json.loads(json.dumps(goods0))
    mut[g0[0]]["rate"] = c["SUPPLY_FLOOR"] - 0.001
    _, _, lo2, al2, ah2 = verdict(mut, days, c)
    chk("② 把 %s 的 rate 压到 FLOOR−0.001 ⇒ 下限臂翻红" % g0[0], al2 and lo2 == [g0[0]])
    mut[g0[0]]["rate"] = c["SUPPLY_FLOOR"]
    _, _, _, al2b, _ = verdict(mut, days, c)
    chk("②b rate 恰等于 FLOOR ⇒ **不**红（判据是严格小于）", not al2b)

    # ③ 红的上限臂必须能被推绿 —— 只少一种货就该翻，这是【阈值恰好在哪】的对照
    _, nv3, _, al3, ah3 = verdict(_with_never(need - 1), days, c)
    chk("③ 只少一种（%d/%d 零缺货）⇒ 上限臂翻绿" % (need - 1, len(g0)), not ah3,
        "(never_short=%d/%d)" % (len(nv3), len(g0)))

    # ④ demand 掉到门槛下 ⇒ 退出判决
    mut = json.loads(json.dumps(goods0))
    mut[g0[0]]["demand"] = c["SUPPLY_MIN_DEMAND"] - 1
    g4, _, _, _, _ = verdict(mut, days, c)
    chk("④ 把 %s 的 demand 压到 MIN_DEMAND−1 ⇒ 退出判决" % g0[0], len(g4) == len(g0) - 1)

    # ⑤ **针对纪律①自己**：换掉源码常量，判决必须跟着动（证明脚本里没有藏冻结字面量）
    c2 = dict(c)
    c2["SUPPLY_FLOOR"] = 0.95
    _, _, lo5, al5, _ = verdict(goods0, days, c2)
    chk("⑤ 把 SUPPLY_FLOOR 换成 0.95 ⇒ 同一份数据翻红（判据真的读了常量）", al5, "(低于 0.95 的货：%s)" % lo5)
    c3 = dict(c)
    c3["HIGH_MULT"] = 1
    _, _, _, _, ah6 = verdict(goods0, days, c3)
    chk("⑤b 把上限臂的乘数换成 1（never_short>gated_n）⇒ 恒不成立", not ah6)

    # ⑥ 天数不足 ⇒ 整条臂禁用
    g7, _, _, al7, ah7 = verdict(goods0, c["SUPPLY_MIN_DAYS"] - 1, c)
    chk("⑥ days_run < SUPPLY_MIN_DAYS ⇒ 一种货都不进判决、两条臂都绿", g7 == [] and not al7 and not ah7)

    print("selftest: %s" % ("PASS ✅" if ok else "FAIL ❌"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="analysis/v2/raw")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--json")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--show-consts", action="store_true")
    a = ap.parse_args()
    c = load_consts()
    if a.show_consts:
        for k, v in sorted(c.items()):
            print("%-20s %s" % (k, v))
        return 0
    raw = a.raw if os.path.isabs(a.raw) else os.path.join(ROOT, a.raw)
    if a.selftest:
        return selftest(raw, c)
    cells = load_raw(raw)
    res = analyse(cells, c, strict=a.strict)
    print(report(res, c))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
