#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""W2 · 「这一格该不该进 CI」的三栏同表器：**基准率 · 牙齿 · 逐 seed 分解**。

它不是 `tools/n_curve.py` 的替代品，是它缺的那一半。
`n_curve.py`（V2）回答的是「逐 N 的曲线长什么样」；本脚本回答的是
**「把某一格接进 `ci.sh` 4a，会发生什么」**——而那是三个不同的数：

  ① **基准率**：这一格 60 个 seed 里 `#40` 红几个？把它切成**全部连续 W-seed 滑窗**，
     几个窗口会破软通过率门？（W **不写死**，从 `tools/ci.sh` 的 `CI_POOL_SEEDS` 默认值现读。）
  ② **牙齿**：同一格上，`ci.sh` 4a 自己的负对照①（删 `production.json` 的 `scale` 块）
     红几个 seed？——**这一栏才是"加这一格能多抓到什么"**。
  ③ **逐 seed 分解**：红的那几颗是**哪条臂**（下限↓ / 上限↑）、**哪种货**、深到多少。
     `docs/41 §5`「相关症状 ≠ 独立证据」：两颗红是不是同一件事，只有摊开才看得见。

**三条纪律**（与 `n_curve.py` 同源，不重述理由）：
  · **零冻结字面量**：判据常量全部 `import n_curve` 现读 `.gd` 源码；
    窗口长度 W 与 4a 今天跑的 N 现读 `tools/ci.sh`。读不到 ⇒ 退出非 0，**绝不回落默认值**。
  · **给展布不给均值**：逐 seed 全列；极值**连并列一起报**。
  · **判据重算 vs 引擎判决必须对上**：每条记录都拿重算的红绿去比 `ScaleSupply` 记的 `inv40_ok`。

用法：
  python tools/n_window.py --raw analysis/v2/raw --raw analysis/w2/raw --cell ship@16 --cell ship@24 --cell ship@40
  python tools/n_window.py --raw ... --teeth ship:noscale@16,24,40 --seeds 1-12
  python tools/n_window.py --selftest
  python tools/n_window.py --show-consts
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
import n_curve as NC                                    # noqa: E402  （复用优先：判据只有一份实现）

CI_SH = os.path.join(ROOT, "tools", "ci.sh")


# ── 纪律① 窗口形状也现读，不写死 12 ──────────────────────────────────────────────
def load_ci_shape():
    """从 tools/ci.sh 现读 4a 的默认 N 与默认 seed 段（= CI 那一窗的长度）。"""
    txt = open(CI_SH, encoding="utf-8", errors="replace").read()
    m = re.search(r'POOL_N="\$\{CI_POOL_N:-(\d+)\}";\s*POOL_SEEDS="\$\{CI_POOL_SEEDS:-(\d+)-(\d+)\}"', txt)
    if not m:
        raise SystemExit("读不到 ci.sh 的 `POOL_N=\"${CI_POOL_N:-N}\"; POOL_SEEDS=\"${CI_POOL_SEEDS:-a-b}\"`"
                         " —— 4a 的形状可能变了，拒绝用默认值继续")
    line = txt.count("\n", 0, m.start()) + 1
    lo, hi = int(m.group(2)), int(m.group(3))
    return {"CI_POOL_N": int(m.group(1)), "CI_SEED_LO": lo, "CI_SEED_HI": hi,
            "W": hi - lo + 1, "_src": "tools/ci.sh:%d" % line}


def load_raw_dirs(dirs):
    """多目录版 load_raw：(arm,N,seed) 全局唯一，重复即退出（原始数据被两次运行交织过）。"""
    cells = collections.defaultdict(dict)
    origin = {}
    for d in dirs:
        d = d if os.path.isabs(d) else os.path.join(ROOT, d)
        for p in sorted(glob.glob(os.path.join(d, "*.jsonl"))):
            m = NC.FNAME.match(os.path.basename(p))
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
                    # 半行 = 那一片还在跑，或者被中断了。**当场点名退出**，不静默跳过：
                    # 少一个 seed 会让"红 1/60"这种数悄悄变成"红 1/59"，而没有人会发现。
                    raise SystemExit("%s:%d 不是合法 JSON（%s）—— 这一片多半还在跑或被中断了；"
                                     "先把 n_sweep 跑完再汇总" % (p, ln, e))
                if int(r["n_agents"]) != n:
                    raise SystemExit("%s: 文件名说 N=%d，记录里 n_agents=%s" % (p, n, r["n_agents"]))
                s = int(r["seed"])
                if s in cells[(arm, n)]:
                    raise SystemExit("(arm=%s,N=%d,seed=%d) 出现两次：%s 与 %s"
                                     % (arm, n, s, origin[(arm, n, s)], p))
                cells[(arm, n)][s] = r
                origin[(arm, n, s)] = p
    return cells


def rows_of(recs, c):
    """逐 seed 重算 #40 的两条臂。返回 {seed: row}，并统计与引擎判决的不一致条数。"""
    rows, mism = {}, []
    for s in sorted(recs):
        r = recs[s]
        goods = r["final"]["goods"]
        gated, never, low, al, ah = NC.verdict(goods, int(r["final"]["days_run"]), c)
        red = al or ah
        if red == bool(r["inv40_ok"]):
            mism.append((s, red, bool(r["inv40_ok"]), r.get("inv40_detail", "")))
        wr, wg = NC.worst_rate(goods, gated)
        rows[s] = {"gated": gated, "never": never, "low": low, "arm_low": al, "arm_high": ah,
                   "red": red, "worst_rate": wr, "worst_good": wg,
                   "rate": {g: float(x["rate"]) for g, x in goods.items()},
                   "sdays": {g: int(x["shortage_days"]) for g, x in goods.items()},
                   "days_run": int(r["final"]["days_run"]),
                   "hard_fails": r.get("hard_fails", []),
                   "work": r.get("work_by_title", {}) or {},
                   "social": r.get("social_events"),
                   "digest": r.get("digest")}
    return rows, mism


def windows(seeds, rows, W, thr):
    """全部连续 W-seed 窗口 ⇒ [(起点 seed, 红数, 是否破门)]。破门条件 = 红数 > W - soft_threshold(W)。"""
    out = []
    allow = W - thr                     # 允许的最大红数
    for i in range(0, len(seeds) - W + 1):
        w = seeds[i:i + W]
        red = sum(1 for s in w if rows[s]["red"])
        out.append((w[0], red, red > allow))
    return out


def ties(pairs, pick):
    """极值 + 并列的 seed 全给（docs/41：报极值连并列一起报）。"""
    if not pairs:
        return "—"
    v = pick(x for _, x in pairs)
    who = sorted(s for s, x in pairs if x == v)
    return "%.3f (seed %s)" % (v, ",".join(map(str, who)))


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    if n == 0:
        return None
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2.0


def describe_cell(arm, n, recs, c, shape, verbose=True):
    seeds = sorted(recs)
    rows, mism = rows_of(recs, c)
    W, thr = shape["W"], NC.soft_threshold(shape["W"], c["SOFT_RATE"])
    wins = windows(seeds, rows, W, thr)
    reds = [s for s in seeds if rows[s]["red"]]
    wr = [(s, rows[s]["worst_rate"]) for s in seeds if rows[s]["worst_rate"] is not None]
    ci_seg = [s for s in seeds if shape["CI_SEED_LO"] <= s <= shape["CI_SEED_HI"]]
    ci_red = [s for s in ci_seg if rows[s]["red"]]
    out = {
        "arm": arm, "n": n, "seeds": seeds, "rows": rows, "mismatch": mism,
        "reds": reds, "wins": wins,
        "win_break": [w for w in wins if w[2]],
        "worst": wr,
        "ci_seg": ci_seg, "ci_red": ci_red,
        "ci_break": (len(ci_seg) == W and len(ci_red) > W - thr),
    }
    if not verbose:
        return out
    L = []
    L.append("─" * 112)
    L.append("### %s @ N=%d   seeds=%d..%d (%d 个)   window W=%d ← %s   soft_threshold(%d)=%d ⇒ 红 ≥%d 破门"
             % (arm, n, seeds[0], seeds[-1], len(seeds), W, shape["_src"], W, thr, W - thr + 1))
    L.append("  判据重算 vs 引擎判决 不一致条数 = %d" % len(mism))
    L.append("  `#40` 红 %d/%d：%s" % (len(reds), len(seeds),
             ", ".join("seed %d%s%s(%s %.3f, 断供 %d/%d 天)" % (
                 s, "↓" if rows[s]["arm_low"] else "", "↑" if rows[s]["arm_high"] else "",
                 ",".join(rows[s]["low"]) if rows[s]["arm_low"] else "缺货绝迹:" + ",".join(rows[s]["never"]),
                 rows[s]["worst_rate"], min(rows[s]["sdays"][g] for g in (rows[s]["low"] or rows[s]["gated"])),
                 rows[s]["days_run"]) for s in reds) or "—"))
    L.append("  硬不变量红的 seed：%s" % ({s: rows[s]["hard_fails"] for s in seeds if rows[s]["hard_fails"]} or "无"))
    L.append("  最差货满足率：min %s   max %s   中位 %.3f" % (
        ties(wr, min), ties(wr, max), median([x for _, x in wr])))
    L.append("  %d-seed 滑窗 %d 个，破门 %d 个：%s" % (
        W, len(wins), len(out["win_break"]),
        " ".join("s%d:%d破" % (a, b) for a, b, k in wins if k) or "—"))
    L.append("  CI 那一窗（seeds %d-%d）：红 %d ⇒ **%s**" % (
        shape["CI_SEED_LO"], shape["CI_SEED_HI"], len(ci_red), "破门 ❌" if out["ci_break"] else "过 ✅"))
    cnt = collections.Counter()
    for s in seeds:
        for g in rows[s]["never"]:
            cnt[g] += 1
    L.append("  逐货【全年零缺货】的 seed 数：%s" % "  ".join(
        "%s %d/%d" % (g, cnt[g], len(seeds)) for g in sorted(cnt, key=lambda x: -cnt[x])))
    lowcnt = collections.Counter()
    for s in seeds:
        for g in rows[s]["low"]:
            lowcnt[g] += 1
    L.append("  逐货【跌破下限】的 seed 数：%s" % ("  ".join(
        "%s %d/%d" % (g, lowcnt[g], len(seeds)) for g in sorted(lowcnt, key=lambda x: -lowcnt[x])) or "无"))
    out["text"] = "\n".join(L)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", action="append", default=[])
    ap.add_argument("--cell", action="append", default=[], help="arm@N，可重复")
    ap.add_argument("--teeth", action="append", default=[],
                    help="base:mutant@N1,N2,... —— 同一 seed 段上两条臂的红数对照")
    ap.add_argument("--seeds", default=None, help="牙齿那一栏用哪一段 seed（默认取 ci.sh 的 CI_POOL_SEEDS）")
    ap.add_argument("--per-seed", action="store_true", help="额外打印逐 seed 的六货明细")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--show-consts", action="store_true")
    a = ap.parse_args()

    c = NC.load_consts()
    shape = load_ci_shape()
    if a.show_consts:
        for k, v in sorted(c.items()):
            print("%-20s %s" % (k, v))
        for k, v in sorted(shape.items()):
            print("%-20s %s" % (k, v))
        print("%-20s %s" % ("soft_threshold(W)", NC.soft_threshold(shape["W"], c["SOFT_RATE"])))
        return 0
    if a.selftest:
        return selftest(c, shape)
    if not a.raw:
        a.raw = ["analysis/v2/raw"]

    cells = load_raw_dirs(a.raw)
    print("常量（**现读源码**）：SUPPLY_FLOOR=%s ← %s | SUPPLY_MIN_DEMAND=%s | SUPPLY_MIN_DAYS=%s | "
          "上限臂 gated_n>=%d and never_short*%d>gated_n ← %s | SOFT_RATE=%s ← %s"
          % (c["SUPPLY_FLOOR"], c["_src_floor"], c["SUPPLY_MIN_DEMAND"], c["SUPPLY_MIN_DAYS"],
             c["HIGH_MIN_GATED"], c["HIGH_MULT"], c["_src_high"], c["SOFT_RATE"], c["_src_softrate"]))
    print("CI 4a 今天的形状（**现读 %s**）：N=%d  seeds=%d-%d  ⇒ 窗口长度 W=%d"
          % (shape["_src"], shape["CI_POOL_N"], shape["CI_SEED_LO"], shape["CI_SEED_HI"], shape["W"]))
    print("目录：%s   共 %d 格" % (", ".join(a.raw), len(cells)))

    want = []
    for spec in a.cell:
        arm, n = spec.split("@")
        want.append((arm, int(n)))
    if not want:
        want = sorted(cells)

    done, total_mism = {}, 0
    for key in want:
        if key not in cells:
            print("!!! 没有 %s@N%d 的数据" % key)
            continue
        d = describe_cell(key[0], key[1], cells[key], c, shape)
        done[key] = d
        total_mism += len(d["mismatch"])
        print(d["text"])
        if a.per_seed:
            goods = sorted({g for s in d["seeds"] for g in d["rows"][s]["rate"]})
            print("  %-5s %-4s | %s" % ("seed", "红", "  ".join("%-14s" % g for g in goods)))
            for s in d["seeds"]:
                r = d["rows"][s]
                cellsx = []
                for g in goods:
                    mk = "↓" if g in r["low"] else ("0" if g in r["never"] else " ")
                    cellsx.append("%-14s" % ("%s%.3f/%d" % (mk, r["rate"].get(g, float("nan")), r["sdays"].get(g, -1))))
                print("  %-5d %-4s | %s" % (s, ("%s%s" % ("↓" if r["arm_low"] else "", "↑" if r["arm_high"] else "")) or "", "  ".join(cellsx)))

    # ── 牙齿 ────────────────────────────────────────────────────────────────────
    for spec in a.teeth:
        pair, ns = spec.split("@")
        base_arm, mut_arm = pair.split(":")
        if a.seeds:
            lo, hi = (int(x) for x in a.seeds.split("-"))
        else:
            lo, hi = shape["CI_SEED_LO"], shape["CI_SEED_HI"]
        seg = list(range(lo, hi + 1))
        print("─" * 112)
        print("### 牙齿：`%s`（基线） vs `%s`（变异体）  seeds %d-%d" % (base_arm, mut_arm, lo, hi))
        print("%-5s | %-24s | %-24s | %s" % ("N", "基线 红/总（哪几个 seed）", "变异体 红/总（哪几个 seed）", "判决"))
        for n in (int(x) for x in ns.split(",")):
            line = []
            for arm in (base_arm, mut_arm):
                if (arm, n) not in cells:
                    line.append(None)
                    continue
                recs = {s: r for s, r in cells[(arm, n)].items() if s in seg}
                if sorted(recs) != seg:
                    line.append(("缺 seed %s" % sorted(set(seg) - set(recs)), None, None))
                    continue
                rows, _ = rows_of(recs, c)
                reds = [s for s in seg if rows[s]["red"]]
                thr = NC.soft_threshold(len(seg), c["SOFT_RATE"])
                brk = len(reds) > len(seg) - thr
                deep = sorted(((rows[s]["worst_rate"], s, ",".join(rows[s]["worst_good"])) for s in seg
                               if rows[s]["worst_rate"] is not None))[:1]
                line.append(("%d/%d (%s)" % (len(reds), len(seg), ",".join(map(str, reds)) or "—"), brk, deep))
            if line[0] is None or line[1] is None:
                print("%-5d | %s" % (n, "数据不全：%s" % ["有" if x else "无" for x in line]))
                continue
            verdict = "变异体破门 ⇒ 这一格【有牙】" if (line[1][1] and not line[0][1]) else (
                "两侧都破门 ⇒ 分不开（基线本身就红）" if line[1][1] and line[0][1] else
                "变异体也不破门 ⇒ 这一格对该变异体【没牙】")
            print("%-5d | %-24s | %-24s | %s" % (n, line[0][0], line[1][0], verdict))
            for tag, x in (("基线", line[0]), ("变异体", line[1])):
                if x[2]:
                    v, s, g = x[2][0]
                    print("      %s 最深的一条：%s %.3f (seed %d)" % (tag, g, v, s))

    if total_mism:
        print("!!! 判据重算与引擎判决不一致 %d 条" % total_mism)
        if a.strict:
            return 1
    return 0


# ── 负对照（docs/41 §2.5：这一栏必须是【跑出来的】）────────────────────────────────
def _fake(seeds, red_at):
    """造一格合成记录：red_at 里的 seed 通过把 口粮 rate 压到 FLOOR 之下变红，其余全绿。
    ⚠️ 走的是**真判据** NC.verdict，不是"我说它红它就红"——否则测的是我的字典，不是判据。"""
    out = {}
    for s in seeds:
        goods = {}
        for i, g in enumerate(["口粮", "柴薪", "屋瓦", "整洁", "豆子", "话本"]):
            goods[g] = {"demanded": True, "served": 100, "demand": 1000,
                        "shortage_days": 5, "rate": 0.8}
        if s in red_at:
            goods["口粮"]["rate"] = 0.1
        out[s] = {"seed": s, "n_agents": 40, "days": 60, "inv40_ok": s not in red_at,
                  "final": {"days_run": 60, "goods": goods}}
    return out


def selftest(c, shape):
    ok = [True]

    def chk(name, cond, extra=""):
        print("  %s %s %s" % ("✅" if cond else "❌", name, extra))
        ok[0] = ok[0] and cond

    W = shape["W"]
    thr = NC.soft_threshold(W, c["SOFT_RATE"])
    allow = W - thr
    print("形状：W=%d（现读 %s）  soft_threshold(%d)=%d ⇒ 一窗里红 ≥%d 破门"
          % (W, shape["_src"], W, thr, allow + 1))
    seeds = list(range(1, 61))

    # ① 零红 ⇒ 一个窗口都不破。**这是「一个什么都不做的改动能不能通过它」那一问**。
    rows, _ = rows_of(_fake(seeds, set()), c)
    w0 = windows(seeds, rows, W, thr)
    chk("① 60 个 seed 全绿 ⇒ %d 个窗口 0 个破门" % len(w0),
        len(w0) == 60 - W + 1 and sum(1 for x in w0 if x[2]) == 0)

    # ② 一颗孤立的红 ⇒ 任何窗口都吃不下第二颗 ⇒ 0 个破门（V2 在 N=16 seed 31 上量到的正是这个形状）
    rows, _ = rows_of(_fake(seeds, {31}), c)
    w1 = windows(seeds, rows, W, thr)
    chk("② 只有 seed 31 一颗红 ⇒ 0 个窗口破门（孤立的红吃不满配额）",
        sum(1 for x in w1 if x[2]) == 0)

    # ③ 两颗**相邻**的红 ⇒ 恰好 W 个窗口同时含着它们（V2 在 N=24 seed 9,10 上量到 9 个，
    #    因为 s1..s9 才是合法起点：seed 9 要在窗口里 ⇒ 起点 ≤9，且起点 ≥1）
    rows, _ = rows_of(_fake(seeds, {9, 10}), c)
    w2 = windows(seeds, rows, W, thr)
    brk = [x[0] for x in w2 if x[2]]
    exp = [s for s in range(1, 61 - W + 1) if s <= 9 and s + W - 1 >= 10]
    chk("③ seed 9,10 两颗相邻 ⇒ 破门窗口 = %s" % exp, brk == exp, "(实得 %s)" % brk)

    # ④ 两颗**隔开 W 以上**的红 ⇒ 一个窗口都不破（同样是 2/60，而 CI 风险完全不同）
    rows, _ = rows_of(_fake(seeds, {5, 5 + W}), c)
    w3 = windows(seeds, rows, W, thr)
    chk("④ seed 5 与 seed %d（间距 %d ≥ W）⇒ 0 个窗口破门 —— **和 ③ 同为 2/60，风险却相反**"
        % (5 + W, W), sum(1 for x in w3 if x[2]) == 0)

    # ⑤ 针对纪律①自己：把 SOFT_RATE 换掉，破门阈值必须跟着动。
    #   ⚠️ 方向必须**往松**试，不能往紧试 —— 见 ⑤c：W=12 时这道门已经顶在 `n-1` 的天花板上。
    #   （本条的第一版写的正是"往紧试"，selftest 当场把它判红，我才去量了 ⑤c 那条平台。）
    c2 = dict(c)
    c2["SOFT_RATE"] = 0.75
    thr2 = NC.soft_threshold(W, c2["SOFT_RATE"])
    rows, _ = rows_of(_fake(seeds, {9, 10}), c)
    w4 = windows(seeds, rows, W, thr2)
    chk("⑤ SOFT_RATE 0.90→0.75 ⇒ soft_threshold %d→%d（允许 %d 红）⇒ 相邻两颗红不再破门"
        % (thr, thr2, W - thr2), thr2 < thr and sum(1 for x in w4 if x[2]) == 0)

    # ⑤c **量出来的边界**：W=12 时 soft_threshold 顶在 `mini(…, n-1)` 的天花板上 ⇒
    #   SOFT_RATE 在一整段区间里改了等于没改，**这道软门在 12-seed 窗口上无法再收紧**。
    #   （docs/41 §2.5：`does_not_detect` 必须是跑出来的。这一条就是跑出来的。）
    plateau = [r / 100.0 for r in range(50, 101) if NC.soft_threshold(W, r / 100.0) == thr]
    chk("⑤c SOFT_RATE ∈ [%.2f, %.2f] 全部给出 soft_threshold=%d ⇒ **W=%d 上这道门已顶到 n−1，"
        "调高 SOFT_RATE 收不紧它**（今天的 %.2f 落在这段里）"
        % (min(plateau), max(plateau), thr, W, c["SOFT_RATE"]),
        len(plateau) > 5 and thr == W - 1 and c["SOFT_RATE"] in plateau)

    # ⑤b 针对纪律①自己：把 SUPPLY_FLOOR 换掉，红绿必须跟着翻（证明红是判据算的，不是我写的）
    c3 = dict(c)
    c3["SUPPLY_FLOOR"] = 0.9
    rows3, _ = rows_of(_fake(seeds, set()), c3)
    chk("⑤b SUPPLY_FLOOR 0.5→0.9 ⇒ 本来全绿的 60 个 seed 全红（rate=0.8 落在两者之间）",
        all(rows3[s]["red"] for s in seeds))

    # ⑥ 窗口数：seeds 少于 W ⇒ 一个窗口都没有（别静默给出一个空表当"0 个破门"）
    few = list(range(1, W))
    rowsf, _ = rows_of(_fake(few, set(few)), c)
    chk("⑥ 只有 %d 个 seed（< W=%d）⇒ 0 个窗口（而不是把'全红'读成'0 个破门'）"
        % (len(few), W), len(windows(few, rowsf, W, thr)) == 0)

    # ⑦ 引擎判决不一致必须被抓到：把 inv40_ok 撒谎成 True
    lying = _fake(seeds, {7})
    lying[7]["inv40_ok"] = True
    _, mism = rows_of(lying, c)
    chk("⑦ 记录里 inv40_ok 与重算判决对不上 ⇒ 计入 mismatch", len(mism) == 1 and mism[0][0] == 7)

    # ⑧ (arm,N,seed) 重复必须当场退出（用真目录做，不是 monkeypatch）
    dup_ok = False
    try:
        load_raw_dirs(["analysis/v2/raw", "analysis/v2/raw"])
    except SystemExit as e:
        dup_ok = "出现两次" in str(e)
    chk("⑧ 同一个目录传两遍 ⇒ (arm,N,seed) 重复，当场退出非 0", dup_ok)

    print("selftest: %s" % ("PASS ✅" if ok[0] else "FAIL ❌"))
    return 0 if ok[0] else 1


if __name__ == "__main__":
    sys.exit(main())
