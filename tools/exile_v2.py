#!/usr/bin/env python3
"""exile_v2.py — #15v2 分类器（docs/30 metric card 冻结版；修掉时间泄漏）。

评审 P1：旧版用【终态】声誉选最坏者、却用【全程】接受率——有时间泄漏（outcast 身份是终态、接受可能发生在他还没成
outcast 时）。本版改用 shadow_trace 里【每条决策当时】记录的 img/cov/neg（同期快照），只在 actor 的【共识 outcast 窗口内】
计其弱关系接受——无终态选择、无全程聚合。阈值全部冻结于 docs/30（held-out 上不许改）。

判定：FAIL ⟺ 某 actor 在其共识 outcast 窗口内、对【中立/非好友】的 greet/invite 接受率 > 镇内【非 outcast】弱关系均值 + 0.08，
且该窗口弱关系 evaluable 决策 >= MIN_WT（否则该 actor 记 INCONCLUSIVE）。seed 判 FAIL(任一 actor FAIL) / PASS / INCONCLUSIVE(无 evaluable)。
用法：python tools/exile_v2.py trace.jsonl [old_fail_seeds]
"""
import json, sys
from collections import defaultdict

# ── 冻结阈值（docs/30；held-out 上不许改）──
FRIEND_AFF, WEAK_TIE = 20.0, 0.5
OUTCAST_IMG, OUTCAST_NEG, OUTCAST_COV = -0.8, 0.67, 0.5
MARGIN, MIN_WT, MIN_PROP = 0.08, 8, 5
COUNTED = {"greet", "give", "gossip", "invite", "gossip_rep"}

def zerofill(r):                 # = #15 的 perceived（零填充镇内声誉）
    return r["img"] * r["cov"]
def is_outcast_rec(r):           # 这条决策【发生当时】proposer 是否共识 outcast（同期快照，无泄漏）
    return zerofill(r) <= OUTCAST_IMG and r["neg"] >= OUTCAST_NEG and r["cov"] >= OUTCAST_COV
def is_wt_gi(r):                 # 弱关系(中立/非好友) 的 greet/invite
    return r["action"] in ("greet", "invite") and abs(r["standing"]) <= WEAK_TIE and r["aff"] < FRIEND_AFF
def rate(rs):
    return (sum(1 for r in rs if r["accepted"]) / len(rs)) if rs else None

def analyze_seed(recs):
    # 镇内【非 outcast 状态】的弱关系 greet/invite 接受率 = 正常基线
    town_wt = [r for r in recs if is_wt_gi(r) and not is_outcast_rec(r)]
    by_actor = defaultdict(list)
    for r in recs:
        if r["action"] in COUNTED:
            by_actor[r["actor"]].append(r)
    evaluable = []   # {actor, perc, n, dyads, rate, town, fail}
    for actor, rs in by_actor.items():
        if len(rs) < MIN_PROP:
            continue
        wt_out = [r for r in rs if is_wt_gi(r) and is_outcast_rec(r)]   # 窗口内弱关系 gi
        if len(wt_out) < MIN_WT:
            continue   # 该 actor 不够 evaluable → 不计 FAIL/PASS
        r_out = rate(wt_out)
        town_loo = [r for r in town_wt if r["actor"] != actor]
        r_town = rate(town_loo)
        dyads = len(set(r["target"] for r in wt_out))
        perc = sorted(zerofill(r) for r in wt_out)[len(wt_out)//2]
        fail = r_town is not None and r_out > r_town + MARGIN
        evaluable.append({"actor": actor, "perc": perc, "n": len(wt_out), "dyads": dyads,
                          "rate": r_out, "town": r_town, "fail": fail})
    if not evaluable:
        return {"verdict": "INCONCLUSIVE", "evaluable": []}
    fails = [e for e in evaluable if e["fail"]]
    return {"verdict": "FAIL" if fails else "PASS", "evaluable": evaluable, "fails": fails}

def main(path, old_fails):
    by_seed = defaultdict(list)
    for l in open(path, encoding="utf-8"):
        if l.strip():
            r = json.loads(l); by_seed[r["seed"]].append(r)
    tally = {"FAIL": [], "PASS": [], "INCONCLUSIVE": []}
    print("seed | verdict      | evaluable outcasts (actor perc n dyads: rate/town)")
    print("-" * 96)
    for seed in sorted(by_seed):
        a = analyze_seed(by_seed[seed])
        tally[a["verdict"]].append(seed)
        star = " <old-FAIL" if seed in old_fails else ""
        detail = "; ".join("%s %+.2f n%d d%d: %.2f/%.2f%s"
                           % (e["actor"], e["perc"], e["n"], e["dyads"], e["rate"], e["town"],
                              " FAIL" if e["fail"] else "") for e in a["evaluable"]) or "(none evaluable)"
        print("%4d | %-12s | %s%s" % (seed, a["verdict"], detail, star))
    n = sum(len(v) for v in tally.values())
    print("\n#15v2（修泄漏·窗口内口径）跨 %d seed：FAIL %d %s | PASS %d | INCONCLUSIVE %d"
          % (n, len(tally["FAIL"]), tally["FAIL"], len(tally["PASS"]), len(tally["INCONCLUSIVE"])))
    print("旧 #15 fail %s → 本版：%s" % (sorted(old_fails),
          {s: ("FAIL" if s in tally["FAIL"] else "PASS" if s in tally["PASS"] else "INCONCLUSIVE") for s in sorted(old_fails)}))
    # 停止条件体检（docs/30）：FAIL 是否只靠少数 dyad
    thin = [(s, e["actor"], e["dyads"]) for s in tally["FAIL"] for e in analyze_seed(by_seed[s])["fails"] if e["dyads"] < 3]
    if thin:
        print("⚠ 停止条件：以下 FAIL 只由 <3 个不同 dyad 支撑(伪重复嫌疑)：%s" % thin)
    print("解读：修掉时间泄漏后若 12/35 的 FAIL 消失、或多数 INCONCLUSIVE → 残余是泄漏/尺度假象(docs/30 停止条件)。")

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "shadow_trace_42.jsonl"
    fails = set(int(x) for x in sys.argv[2].split(",")) if len(sys.argv) > 2 else {12, 17}
    main(path, fails)
