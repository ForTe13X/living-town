#!/usr/bin/env python3
"""shadow_analyze.py — 反事实分析 shadow_trace.jsonl（docs/27 路线①的消费端）。

在【同一批提议 + 同一状态】上，直接算某个假想 lever 会翻转哪些接受决策——绕过确定性仿真的轨迹搅动
（正是这条混淆让 exile-hardening 的两个 lever 无法解释）。并按"是否命中真该放逐的决策 vs 附带伤害"分类。

用法：godot ... Harness.gd -- --shadow-dump trace.jsonl ; 然后 python tools/shadow_analyze.py trace.jsonl
每条 trace：{seed,tick,action,actor,target,accepted,hard,margin,standing,aff,need,fac,jitter,img,cov,neg}
  margin   = sum - threshold（>0 即接受，硬短路 hard=true 除外）
  standing = responder 对 actor 的二元 standing；img = actor 镇内综合声誉(已建 dyad 均值)；cov = 覆盖率；neg = 负向占比
"""
import json, sys

FRIEND_AFF = 20.0     # aff >= 此 视为好友（保护忠实小圈子，别误伤）
WEAK_TIE = 0.5        # |standing| <= 此 视为中立/弱关系（诊断出的过度接受群体）
OUTCAST_IMG = -0.8    # 零填充镇内声誉 <= 此 视为共识型被放逐（该被放逐的决策）
OUTCAST_NEG = 0.67    # 负向占比 >= 此（2/3 的人讨厌他）
OUTCAST_COV = 0.5     # 覆盖率 >= 此（足够多人对他有意见，非稀疏）

def zerofill_img(r):  # 零填充口径(与 #15 不变量一致) = 已建均值 * 覆盖率
    return r["img"] * r["cov"]

def is_consensus_outcast(r):
    return zerofill_img(r) <= OUTCAST_IMG and r["neg"] >= OUTCAST_NEG and r["cov"] >= OUTCAST_COV

def need_term(r):  # greet/invite 的孤独项系数
    return (100.0 - r["need"]) * (0.4 if r["action"] not in ("invite",) else 0.35)

# ── 假想 lever：给定一条决策，返回 margin 变化量 delta（None=不作用于此决策）──
def lever_A(r, d=1.0):   # EXILE_NEED_DAMP：抑制 greet/invite 孤独项，仅 responder 二元 standing<0
    if r["action"] not in ("greet", "invite") or r["standing"] >= 0.0: return None
    return need_term(r) * (-d * min(1.0, -r["standing"] / 3.0))

def lever_B_impl(r, k=8.0):   # 变体B（原实现口径：已建-dyad 均值 img）——全动作、任意负 img
    if r["img"] >= 0.0: return None
    return k * min(0.0, r["img"])

def lever_B_zerofill(r, k=8.0):   # 变体B（GPT-5 Pro 说的正确零填充口径）
    zi = zerofill_img(r)
    if zi >= 0.0: return None
    return k * min(0.0, zi)

def lever_targeted(r, P=12.0):   # GPT-5 Pro 的定向 lever：仅 greet/invite + 弱关系 + 非好友 + 共识 outcast
    if r["action"] not in ("greet", "invite"): return None
    if abs(r["standing"]) > WEAK_TIE or r["aff"] >= FRIEND_AFF: return None
    if not is_consensus_outcast(r): return None
    return -P

LEVERS = {"A(damp1.0)": lever_A, "B_impl(k8)": lever_B_impl,
          "B_zerofill(k8)": lever_B_zerofill, "targeted(P12)": lever_targeted}

def classify(r):
    # 一条【本应放逐】的决策 = 共识 outcast 的 greet/invite 被中立/弱关系者接受（正是 #15 想咬住的）
    tgt = (r["action"] in ("greet", "invite") and is_consensus_outcast(r)
           and abs(r["standing"]) <= WEAK_TIE and r["aff"] < FRIEND_AFF)
    return "on_target" if tgt else "collateral"

def main(path):
    recs = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    nonhard = [r for r in recs if not r["hard"]]
    outcast_targets = [r for r in nonhard if classify(r) == "on_target"]
    accepted_targets = [r for r in outcast_targets if r["accepted"]]
    print("trace: %d decisions (%d non-hard). '本应放逐'目标决策(共识outcast的弱关系greet/invite): %d, 其中被接受 %d"
          % (len(recs), len(nonhard), len(outcast_targets), len(accepted_targets)))
    print("  → #15 的病灶就是这 %d 个'被接受的本应放逐'决策。理想 lever：翻掉它们，别碰别的。\n" % len(accepted_targets))
    print("%-16s | %8s | %8s | %10s | %10s | %s" % ("lever", "applies", "flips", "on_target", "collateral", "精准率"))
    print("-" * 78)
    for name, fn in LEVERS.items():
        applies = flips = ft = fc = 0
        for r in nonhard:
            d = fn(r)
            if d is None: continue
            applies += 1
            new_margin = r["margin"] + d
            # 翻转 = 原接受(margin>0)现被拒(new<=0)
            if r["accepted"] and new_margin <= 0.0:
                flips += 1
                if classify(r) == "on_target": ft += 1
                else: fc += 1
        prec = (100.0 * ft / flips) if flips else 0.0
        print("%-16s | %8d | %8d | %10d | %10d | %5.0f%%" % (name, applies, flips, ft, fc, prec))
    print("\n精准率 = on_target / flips：定向 lever 应接近满分且 flips 覆盖上面的病灶；A 应几乎不 on_target（放过中立者）；")
    print("B 应低精准（全动作+误伤好友/非 outcast）。这把'2 个 lever 失败'量化成了'各自翻错了哪些决策'。")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "shadow_trace.jsonl")
