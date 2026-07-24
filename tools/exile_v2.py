#!/usr/bin/env python3
"""exile_v2.py — #15v2 分类器（docs/27 路线②的首切片），消费 shadow_trace JSONL。

现 #15 把三件事混成一个数：终态声誉、全程接受率、自选遭遇集。评审判定："残余~5%"多半不是真放逐失败，
而是【极化】(有拥趸的分裂人物) 或【遭遇不足】(稀疏观测) 的指标假象。本脚本对每个 seed 的"最坏声誉者"三态判定：
  consensus_outcast : 零填充镇内声誉(=#15 的 perceived) <= -0.8 且 负向占比>=2/3 且 覆盖率>=0.5   → 真该被放逐
  polarized         : 声誉低但有忠实小圈子(存在强正 dyad)——分裂人物，非共识公敌
  insufficient_expo : 覆盖率<0.5（没几个人对他有意见）→ INCONCLUSIVE，接受率估计不可信
并把接受率拆成【弱关系】(#15a：中立/非好友的 greet/invite) vs【忠实】(#15c：好友)。
真放逐失败 = consensus_outcast 且【弱关系】接受率仍高于镇均；若只是好友在接受 → 极化，不是放逐失败。
用法：python tools/exile_v2.py shadow_trace_42.jsonl [old_fail_seeds]（默认 12,17）
"""
import json, sys
from collections import defaultdict

FRIEND_AFF = 20.0
WEAK_TIE = 0.5
OUTCAST_IMG, OUTCAST_NEG, OUTCAST_COV = -0.8, 0.67, 0.5
COUNTED = {"greet", "give", "gossip", "invite", "gossip_rep"}   # #15 计入的 5 动作
MIN_PROP = 5

def zerofill(r):  # = #15 的 perceived
    return r["img"] * r["cov"]

def load(path):
    by_seed = defaultdict(list)
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line: continue
        r = json.loads(line)
        by_seed[r["seed"]].append(r)
    return by_seed

def analyze_seed(recs):
    # 每个 actor(提议者) 的 5-动作提议
    by_actor = defaultdict(list)
    for r in recs:
        if r["action"] in COUNTED:
            by_actor[r["actor"]].append(r)
    actives = {a: rs for a, rs in by_actor.items() if len(rs) >= MIN_PROP}
    if len(actives) < 2:
        return None
    # 最坏 = 【终态】perceived 最低者（贴 #15 口径：#15 用运行结束时的镇内声誉）。用每 actor 最晚 tick 的记录近似终态。
    def terminal(rs): return max(rs, key=lambda r: r["tick"])
    def perceived(rs): return zerofill(terminal(rs))
    worst = min(actives, key=lambda a: perceived(actives[a]))
    wr = actives[worst]
    tr = terminal(wr)
    p_img, p_cov, p_neg = perceived(wr), tr["cov"], tr["neg"]
    if p_cov < OUTCAST_COV:
        klass = "insufficient_expo"
    elif p_img <= OUTCAST_IMG and p_neg >= OUTCAST_NEG:
        klass = "consensus_outcast"
    elif p_img <= -0.5:
        # 声誉低——查是否有忠实小圈子（存在对他 standing>=1 或 aff>=FRIEND 的接受者）
        loyal = any((r["standing"] >= 1.0 or r["aff"] >= FRIEND_AFF) and r["accepted"] for r in wr)
        klass = "polarized" if loyal else "consensus_outcast"
    else:
        klass = "not_outcast"
    # 老 #15 口径：rw = outcast 的 5 动作接受率；镇均 = 其它 active 的均值(leave-one-out)
    rw = sum(1 for r in wr if r["accepted"]) / len(wr)
    town = [sum(1 for r in rs if r["accepted"]) / len(rs) for a, rs in actives.items() if a != worst]
    town_loo = sum(town) / len(town)
    old_fail = (p_img <= OUTCAST_IMG) and (rw > town_loo + 0.08)
    # #15a 弱关系(中立/非好友的 greet/invite) 接受率 vs 镇内弱关系均值
    def wt(rs): return [r for r in rs if r["action"] in ("greet", "invite") and abs(r["standing"]) <= WEAK_TIE and r["aff"] < FRIEND_AFF]
    wt_out = wt(wr)
    wt_rate = (sum(1 for r in wt_out if r["accepted"]) / len(wt_out)) if wt_out else None
    all_wt = [r for a, rs in actives.items() if a != worst for r in wt(rs)]
    wt_town = (sum(1 for r in all_wt if r["accepted"]) / len(all_wt)) if all_wt else None
    # #15c 忠实支持：好友(aff>=FRIEND)提议数 + 接受
    loyal_props = [r for r in wr if r["aff"] >= FRIEND_AFF]
    # #15v2 判定：只有【共识 outcast】且【弱关系】接受率仍高于镇内弱关系均值+0.08 才算真放逐失败。
    # 极化(有拥趸)/遭遇不足/非 outcast → 不是失败（这正是把"分裂人物"从"放逐失败"里摘出来）。
    v2_fail = (klass == "consensus_outcast" and wt_rate is not None and wt_town is not None
               and wt_rate > wt_town + 0.08)
    return {"worst": worst, "perceived": p_img, "cov": p_cov, "neg": p_neg, "klass": klass,
            "rw": rw, "town_loo": town_loo, "old_fail": old_fail, "v2_fail": v2_fail,
            "wt_n": len(wt_out), "wt_rate": wt_rate, "wt_town": wt_town,
            "loyal_n": len(loyal_props), "loyal_acc": sum(1 for r in loyal_props if r["accepted"])}

def main(path, old_fails):
    by_seed = load(path)
    print("seed | worst  | perc  cov  neg | class            | old#15 | rw/town(LOO) | weak-tie acc/town | loyalN")
    print("-" * 108)
    recl = {"consensus_outcast": 0, "polarized": 0, "insufficient_expo": 0, "not_outcast": 0}
    old_fail_klass = defaultdict(list)
    old_fails_all = []; v2_fails_all = []
    for seed in sorted(by_seed):
        a = analyze_seed(by_seed[seed])
        if a is None: continue
        recl[a["klass"]] += 1
        if a["old_fail"]: old_fails_all.append(seed)
        if a["v2_fail"]: v2_fails_all.append(seed)
        of = ("FAIL" if a["old_fail"] else "ok") + ("/v2FAIL" if a["v2_fail"] else "")
        wt = ("%s/%s" % (("%.2f" % a["wt_rate"]) if a["wt_rate"] is not None else "-",
                          ("%.2f" % a["wt_town"]) if a["wt_town"] is not None else "-"))
        star = " <old-FAIL" if seed in old_fails else ""
        print("%4d | %-6s | %+.2f %.2f %.2f | %-16s | %-6s | %.2f / %.2f | %s (n=%d) | %d(acc%d)%s"
              % (seed, a["worst"], a["perceived"], a["cov"], a["neg"], a["klass"], of,
                 a["rw"], a["town_loo"], wt, a["wt_n"], a["loyal_n"], a["loyal_acc"], star))
        if seed in old_fails:
            old_fail_klass[a["klass"]].append(seed)
    print("\n三态重分类跨 %d seed：%s" % (sum(recl.values()), recl))
    print("旧 #15(本脚本复算) 失败 seed: %s  (%d/%d)" % (old_fails_all, len(old_fails_all), sum(recl.values())))
    print("#15v2 失败 seed(共识outcast且弱关系仍过度接受): %s  (%d/%d)" % (v2_fails_all, len(v2_fails_all), sum(recl.values())))
    print("旧标记 old-FAIL 的 seed %s 在 #15v2 下归类：%s" % (old_fails, dict(old_fail_klass)))
    print("解读：#15v2 把'分裂人物(polarized)'从失败里摘出，只留'共识 outcast 仍被中立者过度接受'的真失败——")
    print("      这才是该咬住的放逐；据此可判残余到底是指标假象、还是真需要定向机制。")
    print("\n⚠ 现状与限制（评审 P1，未冻结）：")
    print("  1) 时间泄漏：用【终态】声誉选最坏者，却用【全程】接受率/弱关系率——outcast 身份是终态、接受发生在他还没成 outcast 时也被算进。")
    print("     正解=日级【事前】快照，只在 outcast 窗口内计接受（本切片用终态近似，隐患见 docs/30）。")
    print("  2) cov 恒 1.0（12 人密镇）→ insufficient_expo 从不触发；遭遇代表性要到规模/分散后才生效。")
    print("  3) 阈值(FRIEND_AFF/WEAK_TIE/neg/margin)是【看过 12/17/35 后】写的 → 有 overfit 嫌疑；弱关系样本 n≈15-19 偏小。")
    print("  ⇒ #15v2 现为【诊断指标，非冻结、非 gate】。须先按 docs/30 的 metric card 预注册语义+停止条件，再在【全新 seed 43-126】确认。")

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "shadow_trace_42.jsonl"
    fails = set(int(x) for x in sys.argv[2].split(",")) if len(sys.argv) > 2 else {12, 17}
    main(path, fails)
