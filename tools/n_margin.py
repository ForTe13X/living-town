#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""AA1 · `bench/x1_margin.gd` 那批 jsonl 的汇总器 —— **硬/软分开报，给展布不给均值**。

**为什么不是 `n_curve.py` 的第 N 个开关**：`n_curve` 读的是 `ScaleSupply` 的记录
（`final.goods` 的逐货满足率），而 `x1_margin` 记的是**另外四样**：五条 need 的**全局地板**、
**最长触底段**、**最长 `social < SURVIVAL_GATE` 段**、社交接受/拒绝分账。两份记录连字段都不重叠
⇒ 硬塞进 `n_curve.verdict()` 只能靠 `if "final" in rec` 这类分叉，那会让**判据长出第二份实现**。
**复用的是它该复用的那一半**：`SOFT_RATE` / `soft_threshold()` 从 `n_curve` 现读，
窗口长度 W 从 `n_window` 现读 `tools/ci.sh` —— 本文件里**没有一个判据常量的字面量**。

**三条纪律**（照抄 `n_curve.py`，不重述理由）：
  ① **零冻结字面量**：`SOFT_RATE` / `soft_threshold` / W / `SURVIVAL_GATE` 全部现读源码，
     读不到 ⇒ 退出非 0，**绝不回落默认值**。`--show-consts` 打印它今天读到了什么、从哪一行读的。
  ② **给展布不给均值**：逐 seed 全列；极值**连并列一起报**；中位数**只与展布同时出现**。
  ③ ★ **硬不变量红进【头条】**：W2 在 [docs/89 §〇④] 抓到过一次——`n_curve` 把硬红放在报告
     最末尾第 224 行，于是 V2 那颗 `neu N=40 seed 13` 的硬红**打印了却没被读到**。
     本文件把硬红放在每一格的第一行，**并且在没有硬红时也显式打印 `硬 0/N`**
     （"没有这一行"与"这一行是 0"在扫读时长得一样）。

⚠ **本文件不是门**：不进 `tools/ci.sh`，不做判决，退出码不影响任何一道门。
   `--selftest` 那一栏说的是"它对自己的输入有多严"，**不是**"它守住了系统的什么性质"。

用法：
  python tools/n_margin.py --raw analysis/aa1/raw_margin
  python tools/n_margin.py --raw ... --json analysis/aa1/margin.json
  python tools/n_margin.py --selftest
  python tools/n_margin.py --show-consts
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import n_curve as NC                                    # noqa: E402  复用优先：判据常量只有一份来源
import n_window as NW                                   # noqa: E402  复用优先：窗口形状现读 ci.sh

SIM = os.path.join(ROOT, "game", "scripts", "Sim.gd")
FNAME = NC.FNAME                                        # 文件名约定与 n_sweep 一致，不另立一套


def load_consts():
    """判据常量全部现读。多读一个 SURVIVAL_GATE —— 「social 锁段」这个量的定义就挂在它上面。"""
    c = {"SOFT_RATE": NC.load_consts()["SOFT_RATE"],
         "_src_softrate": NC.load_consts()["_src_softrate"]}
    txt = open(SIM, encoding="utf-8", errors="replace").read()
    # ⚠ 行尾有注释（`const SURVIVAL_GATE := 36.0     # 任一需求 < 此 → …`），所以不能用 `\s*$` 收尾
    #   —— n_curve 的 `_grep_const` 正是这么写的，拿它去读这一行会读不到。我先撞了一次。
    m = re.search(r"^\s*const\s+SURVIVAL_GATE\s*:=\s*([0-9.]+)\s*(?:#.*)?$", txt, re.M)
    if not m:
        raise SystemExit("读不到 game/scripts/Sim.gd 的 const SURVIVAL_GATE —— "
                         "「最长 social<GATE 段」这个量的定义没了，拒绝用默认值继续")
    c["SURVIVAL_GATE"] = float(m.group(1))
    c["_src_gate"] = "game/scripts/Sim.gd:%d" % (txt.count("\n", 0, m.start()) + 1)
    shape = NW.load_ci_shape()
    c["W"] = shape["W"]
    c["_src_w"] = shape["_src"]
    c["CI_POOL_N"] = shape["CI_POOL_N"]
    return c


def load_raw(raw_dirs):
    """(arm, N) -> {seed: rec}。同一个三元组从两个地方进来 ⇒ 当场退出并点名两个文件。"""
    cells = collections.defaultdict(dict)
    where = {}
    for raw_dir in raw_dirs:
        d = raw_dir if os.path.isabs(raw_dir) else os.path.join(ROOT, raw_dir)
        for p in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            m = FNAME.match(os.path.basename(p))
            if not m:
                continue
            arm, n = m.group("arm"), int(m.group("n"))
            for ln, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except ValueError as e:
                    sys.exit("%s:%d 不是合法 JSON（%s）—— 多半是那一片还在跑 / 被中断的半行。"
                             "少一个 seed 会把『红 1/60』悄悄变成『红 1/59』" % (p, ln, e))
                if int(r["n_agents"]) != n:
                    sys.exit("%s: 文件名说 N=%d，记录里 n_agents=%s" % (p, n, r["n_agents"]))
                s = int(r["seed"])
                key = (arm, n, s)
                if s in cells[(arm, n)]:
                    sys.exit("(arm=%s,N=%d,seed=%d) 出现两次：\n  %s\n  %s\n"
                             "—— 原始数据被两次运行交织过，或两棵树被拼在一起" % (arm, n, s, where[key], p))
                where[key] = p
                cells[(arm, n)][s] = r
    return cells


def fmt_spread(by_seed, fmt="%.2f"):
    """min / max / 中位 —— **三个一起给**，且极值连并列一起报（docs/41 §5）。"""
    if not by_seed:
        return "—"
    vals = sorted(by_seed.values())
    n = len(vals)
    med = vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2]) / 2.0
    lo, hi = vals[0], vals[-1]
    lo_s = ",".join(str(s) for s in sorted(by_seed) if by_seed[s] == lo)
    hi_s = ",".join(str(s) for s in sorted(by_seed) if by_seed[s] == hi)
    return ("min " + fmt + " (seed %s) .. max " + fmt + " (seed %s)  中位 " + fmt) % (lo, lo_s, hi, hi_s, med)


NEEDS_ORDER = ["social", "hunger", "energy", "hygiene", "fun"]


def analyse(cells, c):
    out = {"consts": {k: v for k, v in c.items()}, "cells": {}}
    for (arm, n) in sorted(cells, key=lambda k: (k[0], k[1])):
        recs = cells[(arm, n)]
        seeds = sorted(recs)
        hard = {s: sorted(int(i) for i in recs[s].get("hard_fails", [])) for s in seeds}
        soft = {s: sorted(int(i) for i in recs[s].get("soft_fails", [])) for s in seeds}
        floors = {nd: {s: float(recs[s]["floors"].get(nd, float("nan"))) for s in seeds}
                  for nd in NEEDS_ORDER}
        lock = {s: int(recs[s].get("max_soclock_run", 0)) for s in seeds}
        starve = {s: int(recs[s].get("max_starve_run", 0)) for s in seeds}
        starved = {s: int(recs[s].get("starved", 0)) for s in seeds}
        # 硬红的展开：哪条 need、哪个人、多少个 need·tick
        hard_detail = {}
        for s in seeds:
            if hard[s]:
                hard_detail[s] = {"ids": hard[s], "starved": starved[s],
                                  "by_need": recs[s].get("by_need", {}),
                                  "agents": recs[s].get("starve_agents", []),
                                  "max_run": starve[s], "key": recs[s].get("max_starve_run_key", "")}
        soft_ids = collections.defaultdict(list)
        for s in seeds:
            for i in soft[s]:
                soft_ids[i].append(s)
        # 滑窗软门（CI 的形状）：W 与 SOFT_RATE 都是现读的
        thr = NC.soft_threshold(c["W"], c["SOFT_RATE"])
        need_red = c["W"] - thr + 1
        wins = []
        for i in range(0, len(seeds) - c["W"] + 1):
            w = seeds[i:i + c["W"]]
            nr = sum(1 for s in w if soft[s])
            nh = sum(1 for s in w if hard[s])
            wins.append({"start": w[0], "soft_red": nr, "hard_red": nh,
                         "broken": (nr >= need_red) or (nh > 0)})
        out["cells"]["%s@N%d" % (arm, n)] = {
            "arm": arm, "n": n, "seeds": seeds,
            "hard": hard, "soft": soft, "hard_detail": hard_detail,
            "soft_ids": {str(k): v for k, v in soft_ids.items()},
            "floors": floors, "lock": lock, "starve_run": starve,
            "digest": {s: recs[s].get("digest") for s in seeds},
            "windows": wins, "need_red": need_red, "soft_threshold": thr,
        }
    return out


def report(res, c):
    L = []
    ap = L.append
    ap("常量（**现从源码读**，本文件里没有字面量）：")
    ap("  SOFT_RATE=%s  ← %s" % (c["SOFT_RATE"], c["_src_softrate"]))
    ap("  SURVIVAL_GATE=%s  ← %s" % (c["SURVIVAL_GATE"], c["_src_gate"]))
    ap("  窗口长度 W=%d（= ci.sh 4a 的默认 seed 段长）· 4a 今天跑的 N=%d  ← %s"
       % (c["W"], c["CI_POOL_N"], c["_src_w"]))
    ap("")
    keys = sorted(res["cells"], key=lambda k: (res["cells"][k]["arm"], res["cells"][k]["n"]))

    # ── ★ 头条：硬不变量。放第一行，且【没有硬红时也显式打印 0】 ──────────────────
    ap("=" * 104)
    ap("### ★ 头条：硬不变量（docs/89 §〇④：n_curve 把这一栏放在第 224 行，于是一颗硬红被打印了却没被读到）")
    for k in keys:
        cell = res["cells"][k]
        seeds, hd = cell["seeds"], cell["hard_detail"]
        ap("  %-10s 硬红 %d/%d %s" % (k, len(hd), len(seeds),
                                      ("← " + ", ".join("seed %d %s" % (s, hd[s]["ids"]) for s in sorted(hd))) if hd else "（这一格没有硬红）"))
        for s in sorted(hd):
            d = hd[s]
            ap("        seed %-3d 硬 %s · 触底 need·tick=%d · 逐 need=%s · 涉及 %d 人%s · 最长连续触底 %d tick (%s)"
               % (s, d["ids"], d["starved"], d["by_need"], len(d["agents"]), d["agents"], d["max_run"], d["key"]))
    ap("")

    # ── 软不变量，与硬分开 ──────────────────────────────────────────────────────
    ap("=" * 104)
    ap("### 软不变量（**与上面那一栏分开报**：docs/89 §五 实测过一格『软门 12/12 全绿而门照样红』）")
    for k in keys:
        cell = res["cells"][k]
        seeds = cell["seeds"]
        nred = sum(1 for s in seeds if cell["soft"][s])
        bits = []
        for i in sorted(cell["soft_ids"], key=lambda x: int(x)):
            v = cell["soft_ids"][i]
            bits.append("#%s 红 %d 个 seed %s" % (i, len(v), v))
        ap("  %-10s 软红 %d/%d  %s" % (k, nred, len(seeds), " | ".join(bits) or "（这一格没有软红）"))
    ap("")

    # ── 逐 seed 的连续余量（红绿计数在这一族上没有统计功效 —— X1/Y1 各证过一次）─────
    ap("=" * 104)
    ap("### 连续余量（★ 判据用这一栏，不用红绿计数：X1/Y1/Z2 三次实测，语义为零的扰动能消掉硬红）")
    ap("  `social` 全局地板（所有 agent × 所有 tick 的最小值）")
    for k in keys:
        cell = res["cells"][k]
        ap("  %-10s %s" % (k, fmt_spread(cell["floors"]["social"])))
    ap("")
    ap("  最长「social < %g」连续段（tick；这是那个自锁的【停留时长】，红只是它长到把 social 拖到 0 的那一次）"
       % c["SURVIVAL_GATE"])
    for k in keys:
        cell = res["cells"][k]
        ap("  %-10s %s" % (k, fmt_spread(cell["lock"], "%d")))
    ap("")
    for nd in NEEDS_ORDER[1:]:
        ap("  `%s` 全局地板" % nd)
        for k in keys:
            cell = res["cells"][k]
            ap("  %-10s %s" % (k, fmt_spread(cell["floors"][nd])))
        ap("")

    # ── 逐 seed 全列（展布，不给均值）──────────────────────────────────────────
    ap("=" * 104)
    ap("### 逐 seed 全列（**不给均值**）：social 地板 / 最长 social 锁段 / 硬 / 软")
    for k in keys:
        cell = res["cells"][k]
        ap("--- %s ---" % k)
        ap("%-5s %-9s %-7s %-10s %s" % ("seed", "social地板", "锁段", "硬", "软"))
        for s in cell["seeds"]:
            ap("%-5d %-9.2f %-7d %-10s %s"
               % (s, cell["floors"]["social"][s], cell["lock"][s],
                  (str(cell["hard"][s]) if cell["hard"][s] else "-"),
                  (str(cell["soft"][s]) if cell["soft"][s] else "-")))
        ap("")

    # ── CI 的形状：滑窗 ────────────────────────────────────────────────────────
    ap("=" * 104)
    ap("### CI 形状：把每一格切成【连续 %d 个 seed】的窗口" % c["W"])
    ap("  soft_threshold(%d) = %d ⇒ 一个窗口里软红 ≥ %d 个就破门；**任何一颗硬红单独就破门**"
       % (c["W"], res["cells"][keys[0]]["soft_threshold"] if keys else 0,
          res["cells"][keys[0]]["need_red"] if keys else 0))
    for k in keys:
        cell = res["cells"][k]
        nb = sum(1 for w in cell["windows"] if w["broken"])
        ap("  %-10s 破门窗口 %d/%d" % (k, nb, len(cell["windows"])))
        ap("        逐窗口 软红: %s" % " ".join(str(w["soft_red"]) for w in cell["windows"]))
        ap("        逐窗口 硬红: %s" % " ".join(str(w["hard_red"]) for w in cell["windows"]))
    return "\n".join(L)


# ── 负对照（docs/41 §2.5：`does_not_detect` 必须是跑出来的；而 detects 也一样）────────
def selftest(c):
    ok = [True]

    def chk(name, cond, extra=""):
        print("  %s %s %s" % ("✅" if cond else "❌", name, extra))
        ok[0] = ok[0] and cond

    def mk(n, seeds, hard=(), soft=(), floor=20.0, lock=100):
        cells = collections.defaultdict(dict)
        for s in seeds:
            cells[("ship", n)][s] = {
                "seed": s, "n_agents": n, "days": 60,
                "hard_fails": list(hard.get(s, [])) if isinstance(hard, dict) else ([1] if s in hard else []),
                "soft_fails": list(soft.get(s, [])) if isinstance(soft, dict) else ([40] if s in soft else []),
                "floors": {nd: floor for nd in NEEDS_ORDER},
                "max_soclock_run": lock, "max_starve_run": 0, "starved": 0,
                "by_need": {}, "starve_agents": [], "digest": "0",
            }
        return cells

    W = c["W"]
    all60 = list(range(1, 61))

    # ① 全绿 ⇒ 0 个窗口破门（= 「一个什么都不做的改动能不能通过它」）
    r = analyse(mk(40, all60), c)["cells"]["ship@N40"]
    chk("① 60 seed 全绿 ⇒ 0 个窗口破门", sum(1 for w in r["windows"] if w["broken"]) == 0,
        "(窗口数 %d)" % len(r["windows"]))

    # 期望值一律**现算**，不写死。⚠ 这一条是被自己的第一版打脸打出来的：
    #   我先把 ②b 写成"恰好 W 个"、③ 写成"恰好 W 个"，两条都 ❌（实得 11 与 8）。
    #   正确的形状是 ①相邻两颗只被 W−1 个窗口同时吃下；②靠边的 seed 会被左边界截断。
    #   **想出来的那一版读起来和真的一模一样** —— docs/89 §6.2 ⑤c 记过同一件事。
    def n_windows_covering(seeds_red):
        """含至少一个红 seed 的窗口数（窗口起点 1..60−W+1），现算。"""
        return sum(1 for i in range(1, 60 - W + 2)
                   if any(i <= s <= i + W - 1 for s in seeds_red))

    def n_windows_covering_k(seeds_red, k):
        """含 ≥k 个红 seed 的窗口数，现算。"""
        return sum(1 for i in range(1, 60 - W + 2)
                   if sum(1 for s in seeds_red if i <= s <= i + W - 1) >= k)

    # ② 一颗【孤立】的软红 ⇒ 0 个破门（软门容得下 1 个）；两颗【相邻】的 ⇒ 被同一窗吃下的那些破
    r = analyse(mk(40, all60, soft=[30]), c)["cells"]["ship@N40"]
    chk("② 一颗孤立软红 ⇒ 0 个破门（软门在 W=%d 上容 %d 个）" % (W, r["need_red"] - 1),
        sum(1 for w in r["windows"] if w["broken"]) == 0)
    exp = n_windows_covering_k([30, 31], 2)
    r = analyse(mk(40, all60, soft=[30, 31]), c)["cells"]["ship@N40"]
    nb = sum(1 for w in r["windows"] if w["broken"])
    chk("② b 两颗相邻软红(30,31) ⇒ %d 个破门（= W−1，不是 W）" % exp, nb == exp, "(实得 %d)" % nb)

    # ③ ★ 一颗【硬】红单独就破门 —— 软门再宽也管不到它（docs/89 §五 实测过这个形状：
    #    `N=40 seeds 49-60` 软门 12/12 全绿，而 S0 GATE 照样 FAIL，红在硬 #01）
    exp = n_windows_covering([30])
    r = analyse(mk(40, all60, hard=[30]), c)["cells"]["ship@N40"]
    nb = sum(1 for w in r["windows"] if w["broken"])
    chk("③ 一颗孤立【硬】红(内点 seed 30) ⇒ %d 个破门（软门对它不适用）" % exp, nb == exp, "(实得 %d)" % nb)
    exp = n_windows_covering([8])
    r = analyse(mk(40, all60, hard=[8]), c)["cells"]["ship@N40"]
    nb = sum(1 for w in r["windows"] if w["broken"])
    chk("③ b 靠左边界的硬红(seed 8) ⇒ %d 个破门（被边界截断，不是 W）" % exp, nb == exp, "(实得 %d)" % nb)

    # ④ 硬红必须进头条那一栏，而不是被折进"红了几个"
    txt = report(analyse(mk(40, all60, hard=[8]), c), c)
    head = txt.split("### 软不变量")[0]
    chk("④ 硬红出现在【头条】那一节里", "seed 8" in head and "硬红 1/60" in head)
    txt0 = report(analyse(mk(40, all60), c), c)
    chk("④ b 没有硬红时也显式打印 `硬红 0/60`（『没有这一行』与『这一行是 0』扫读时长得一样）",
        "硬红 0/60" in txt0)

    # ⑤ ★ 针对纪律①自己：换掉现读的常量，判决必须跟着动（证明脚本里没藏冻结字面量）
    c2 = dict(c); c2["SOFT_RATE"] = 0.50
    r2 = analyse(mk(40, all60, soft=[30, 31]), c2)["cells"]["ship@N40"]
    chk("⑤ SOFT_RATE 0.90→0.50 ⇒ 相邻两颗软红不再破门（常量真的被读了）",
        sum(1 for w in r2["windows"] if w["broken"]) == 0,
        "(need_red %d→%d)" % (r["need_red"], r2["need_red"]))
    c3 = dict(c); c3["W"] = 24
    r3 = analyse(mk(40, all60, soft=[30]), c3)["cells"]["ship@N40"]
    chk("⑤ b W=12→24 ⇒ 窗口数跟着变（W 真的被读了）", len(r3["windows"]) == 60 - 24 + 1,
        "(实得 %d)" % len(r3["windows"]))

    # ⑥ 展布：极值连并列一起报，且中位数不单独出现
    cells = mk(40, [1, 2, 3], floor=20.0)
    cells[("ship", 40)][2]["floors"]["social"] = 5.0
    cells[("ship", 40)][3]["floors"]["social"] = 5.0
    s = fmt_spread(analyse(cells, c)["cells"]["ship@N40"]["floors"]["social"])
    chk("⑥ 极值并列全报（两个 seed 同为最小 ⇒ 都点名）", "seed 2,3" in s, "→ %s" % s)

    # ⑦ seed 少于 W ⇒ 0 个窗口，而不是把"全红"读成"0 个破门"
    r = analyse(mk(40, list(range(1, W)), soft=list(range(1, W))), c)["cells"]["ship@N40"]
    chk("⑦ seed 数 < W ⇒ 窗口数 = 0（不把不足一窗读成『没破门』）", len(r["windows"]) == 0)

    # ⑧ 同一个 (arm,N,seed) 从两处进来 ⇒ 当场退出（跨树拼接的第一道拦网）
    import tempfile
    d1, d2 = tempfile.mkdtemp(), tempfile.mkdtemp()
    rec = {"seed": 1, "n_agents": 40, "days": 60, "hard_fails": [], "soft_fails": [],
           "floors": {n: 20.0 for n in NEEDS_ORDER}, "max_soclock_run": 1,
           "max_starve_run": 0, "starved": 0, "by_need": {}, "starve_agents": [], "digest": "0"}
    for d in (d1, d2):
        open(os.path.join(d, "ship_n40_s1-1.jsonl"), "w", encoding="utf-8").write(json.dumps(rec) + "\n")
    try:
        load_raw([d1, d2])
        chk("⑧ 同一个 (arm,N,seed) 从两个目录进来 ⇒ 退出", False)
    except SystemExit as e:
        chk("⑧ 同一个 (arm,N,seed) 从两个目录进来 ⇒ 退出并点名两个文件",
            "出现两次" in str(e) and d1.replace("\\", "/") in str(e).replace("\\", "/"))

    # ⑨ 半行 JSON（那一片还在跑 / 被中断）⇒ 点名文件与行号退出，不静默跳过
    d3 = tempfile.mkdtemp()
    open(os.path.join(d3, "ship_n40_s1-2.jsonl"), "w", encoding="utf-8").write(
        json.dumps(rec) + "\n" + '{"seed": 2, "n_ag')
    try:
        load_raw([d3])
        chk("⑨ 半行 JSON ⇒ 退出", False)
    except SystemExit as e:
        chk("⑨ 半行 JSON ⇒ 点名文件与行号退出（少一个 seed 会把 1/60 悄悄变成 1/59）",
            ":2" in str(e) and "不是合法 JSON" in str(e))

    print("selftest: %s" % ("PASS ✅" if ok[0] else "FAIL ❌"))
    return 0 if ok[0] else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", action="append", default=[])
    ap.add_argument("--json")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--show-consts", action="store_true")
    a = ap.parse_args()
    c = load_consts()
    if a.show_consts:
        for k, v in sorted(c.items()):
            print("%-20s %s" % (k, v))
        return 0
    if a.selftest:
        return selftest(c)
    if not a.raw:
        a.raw = ["analysis/aa1/raw_margin"]
    cells = load_raw(a.raw)
    if not cells:
        sys.exit("--raw 指向的目录里没有 *.jsonl")
    res = analyse(cells, c)
    print(report(res, c))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
