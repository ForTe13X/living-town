# #15v2 Metric Card（预注册 · 冻结于看 held-out 之前）

分支 `shadow-instrumentation`。本卡在**只看过 dev seed 1-42、未看 held-out 43-126** 时写下，用于防止"看着结果调指标"的 overfit。
双 AI 评审（GPT-5 Pro + Codex desktop）确认路线（先修指标+建反事实探针），但要求：**先预注册语义 + 阈值 + 停止条件，修掉时间泄漏，再上 held-out**。#15v2 现为【诊断指标，非冻结门、非 CI gate】。

## 冻结定义（held-out 上不再改）
对每 seed，取一个 outcast，评其社会是否真放逐了他：
- **outcast 识别（须修）**：应按【每日事前快照】——每天用【昨日】的镇内声誉判定谁是 outcast，只在其 outcast 窗口内计其接受事件。*当前 `tools/exile_v2.py` 是终态近似（用终态选最坏者 + 全程接受率），有时间泄漏，held-out 前必须换成日级事前快照。*
- **三态**：`consensus_outcast`（perceived=零填充镇内声誉 ≤ **-0.8** 且 负向占比 ≥ **2/3** 且 覆盖率 ≥ **0.5**）/ `polarized`（声誉低但有忠实小圈子）/ `insufficient_expo`（覆盖率 < 0.5 → **INCONCLUSIVE**）/ `not_outcast`。
- **#15a 弱关系口径**：仅对 `consensus_outcast`，算其【中立/非好友】（|standing| ≤ **0.5**，affinity < **20**）的 **greet/invite** 接受率 vs 镇内弱关系均值（leave-one-out）。
- **判定**：**FAIL ⟺ consensus_outcast 且 弱关系接受率 > 镇内弱关系均值 + 0.08**。polarized / insufficient_expo / not_outcast 一律**非失败**。
- **小样本门**：某 outcast 的弱关系 evaluable 决策 < **8** → 该 seed 记 **INCONCLUSIVE**（不计 FAIL/PASS）。

## 阈值来源（诚实声明）
上面的数字（-0.8 / 2/3 / 0.5 / 0.5 / 20 / +0.08 / min-8）是在 **dev seed 1-42** 上、**看过老失败 seed 12/17/35 之后**定的 → 有 overfit 风险。held-out 43-126 上**一个都不许再调**；若要调，视为新一轮 dev，须重开 held-out。

## 评估协议
1. **dev（已做）**：1-42。观察：老 #15 fail {12,17} → #15v2 fail {12,35}（摘极化假阳 17、捞回被稀释真阳 35）。
2. **修泄漏（待做，held-out 前）**：把终态近似换成日级事前快照 + outcast 窗口内计接受（需在 shadow_trace 里加每决策【当日事前】的 actor 声誉快照，或在 Sim 里每日落一次声誉快照）。
3. **freeze**：本卡即冻结点。
4. **confirm（待做）**：全新 seed **43-126**（84 个，未看过）跑一次，报 FAIL / PASS / INCONCLUSIVE 三态分布 + 每个 FAIL 的证据（是几个不同 dyad 支撑、是否有玩家可见后果）。

## 预注册停止条件（命中任一 → #15v2 仅作诊断，**不为这个边缘软不变量加机制**）
- held-out 上**大多数**候选 outcast 落 **INCONCLUSIVE**（说明这个小密镇尺度下"共识放逐"本就罕见）；
- FAIL **只由一两个重复 dyad** 支撑（伪重复，非真群体性放逐）；
- 修掉事前窗口泄漏后 **seed 12/35 的 FAIL 消失**（说明原 FAIL 是时间泄漏假象）；
- 即便存在局部弱关系 acceptance excess，**没有玩家可见后果**（社会触达/邀请/网络位置都不受影响）→ 不值得为它动机制。

## 只有全部通过才进机制
唯有 held-out 上**稳定复现**"共识 outcast 被中立弱关系过度接受、且有可见后果"，才进入 targeted lever 的**闭环** A/B（用 `shadow_analyze.py` 已验证的 targeted 骨架，closed-loop + held-out，而非 post-hoc oracle 对齐）。否则本条到此为止，诚实收尾。

_评审：GPT-5 Pro（web）+ Codex desktop（全仓核验）。本卡落实 Codex"先冻结 metric card + 预注册停止条件、修时间泄漏、再上 held-out"的处方。_
