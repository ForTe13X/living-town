# #15 涌现放逐 · 结案：残余是指标假象，held-out 确认，不加机制

分支 `shadow-instrumentation`。历经"两个机制 lever 否决 → 双 AI 评审 → shadow 反事实探针 → #15v2 → 修时间泄漏 → held-out 确认"，
#15 残余问题**结案**：**它从来不是真的放逐没咬住，而是度量混淆**。按 docs/30 预注册协议，冻结阈值、在【全新未见 seed】上确认。

## 决定性证据（冻结口径，held-out 未参与设计）
| 集 | seed 数 | #15v2 判定 | outcast-窗口占比 | 单 outcast 窗口内弱关系 greet/invite 最大数 |
|---|---|---|---|---|
| dev (1-42) | 42 | **42/42 INCONCLUSIVE** | 3.3% | 6（< 门槛 8） |
| held-out (43-126) | 84 | **84/84 INCONCLUSIVE** | 4.0% | 7（< 门槛 8） |

**126/126 seed 全 INCONCLUSIVE。** 命中预注册停止条件 #1（多数 INCONCLUSIVE）+ #3（修事前窗口后 12/17/35 的 FAIL 消失）。

## 为什么老 #15 会"失败~5%"
老 #15 用【终态】声誉判定谁是 outcast，却用【全程】接受率算 rw——**时间泄漏**：把此人【还没成公敌时】的接受也算进了 rw。
修正成【每决策当时的同期声誉快照 + 只在共识 outcast 窗口内计接受】后：共识-outcast 状态本就罕见（占决策 ~3-4%）、且发生得晚，
一个 12 人密镇在 60 天里，任何单个 outcast 在其【真·公敌窗口内】遇到的【中立弱关系】greet/invite 最多 6-7 次，**够不到统计可评的 8 次**。
即：**这个尺度的小镇根本不产生足够的"共识放逐"接触去评判放逐是否咬住**——老 #15 flag 的"失败"是早期接受泄漏 + 自选遭遇 + 终态口径混出来的假象。

## 结论与处置
- **#15 残余无需机制**：两个被否的 lever（EXILE_NEED_DAMP / IMAGE_SCORE_K）当初是在"修一个不存在的失败"；`shadow_analyze.py` 也已量化它们没瞄准病灶（A 0% / B 2% on_target）。
- **#15v2（修泄漏版）= 正确诊断指标**：在当前尺度它诚实地报 INCONCLUSIVE（数据不足以判），而非假阳 FAIL。保留为 `tools/exile_v2.py` 诊断工具，**不作 CI gate**（样本不足）。
- **shadow 探针 = 可复用测量地基**：`_acceptance_margin`（逐字节一致重构）+ shadow_trace 侧信道 + `--shadow-dump` + 反事实分析器，适用于将来任何"某社会机制干预会翻哪些决策"的问题，绕过确定性仿真轨迹搅动。
- **规模洞察**：共识放逐要能被度量/涌现，需要更大/更分散的镇（更多 agent、公共场所混合、更长时程）——这是将来"扩容"路线才谈得上的现象，不是 12 人镇的边缘 bug。

## 方法论收获（这条弯路值得）
双 AI 对抗评审 + 预注册 metric card + held-out 确认，把一个"看着像 5% 残余失败、想加机制去修"的直觉，一路证伪成"度量假象"。
**没有这套（反事实探针 + 事前窗口 + 冻结阈值 + held-out），我会去修一个不存在的问题**（就像最初那两个 lever）。见 docs/27-30 全链，[[project-15-metric-repair]]、[[feedback-adversarial-external-review]]。

_dev+held-out 共 126 seed × 60 天，frozen #15v2；双评审 GPT-5 Pro + Codex desktop。master 代码一行未动（全在本分支）。_
