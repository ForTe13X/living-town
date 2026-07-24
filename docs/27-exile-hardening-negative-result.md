# exile-hardening —— 负结果 + 双 AI 评审校正（#15 涌现放逐）

分支 `exile-hardening`（不合入 master）。这是一次结构性尝试：让「涌现放逐」#15 在住户搬进室内私宅、人群夜间分散后仍咬得住。**结论：两个接受机制干预都被否决；但原先"#15 残余 ~5% 不可约"的措辞是【过度外推】，已按评审校正。**

## 做了什么
两个 gated lever（默认 0 = 行为等价；gates 开启时同 seed 两跑 digest 一致 4/4），扫 seeds 1-42 × 60 天：
- **Lever A `EXILE_NEED_DAMP`**：按 responder 对 actor 的强负【二元】standing 抑制 greet/invite 孤独项。结果=纯搅动：base #15=2/42[12,17]；damp0.6=3/42[5,11,28]；damp1.0=2/42[18,30]。修好目标 seed，别处冒新的，失败率不降，无回归也无收益。
- **Lever B `IMAGE_SCORE_K`**（image-score 全局声誉）：接受里加 `K*min(0, town_image(actor))`。结果=有害：img-k4=5/42 + 硬不变量 #01 无饿穿在 seed27 失败；img-k8=4/42 + #01[25,32,33] + #05 谣言传播[12,19]；img-k12=4/42 + #05[5,19]。#15 反而更差，且击穿硬红线。

诊断(bench/find_exile.gd)：基线 #15 失败很边缘(seed12 超门 +0.022，seed17 +0.062)，疑似【分裂声誉】：outcast 既有恨他的人(把 perceived 拉到 <=-0.8)，又有中立/正向的忠实小圈子无条件接受(把 rw 拉高)。

## 双 AI 对抗性评审（GPT-5 Pro 思考 21m + Codex desktop 全仓核验 ~20m，两者独立收敛）
**共识：不合入是对的；但"任何接受机制都不可约/无解"是过度外推，"irreducible"这个词必须删掉。** 关键发现（已核对代码属实）：

1. **Lever A 的负结果有效，但外推无效**：`_need_boost` 对 standing>=0 的 responder【原样返回】——恰恰放过了诊断出的"中立/友好者无条件接受"这条致因链；且 #15 汇集 5 个动作(greet/give/gossip/invite/gossip_rep)而 A 只改 2 个。所以只证明了"对已经负的二元再加抑制无净收益"，没证明"responder 侧干预不可行"。
2. **Lever B 否决的是这个实现，不是 image-score 本身**：`_town_image()` 只对【已建关系】求均值，而不变量的 `perceived` 用 `_rel()`【auto-create 零填充】所有缺失 dyad（已核实 `_rel` 确实会建 key）。于是稀疏观测下 B 的 image 比不变量口径【负得多】（一个 -3 + 十个缺失：不变量看到 -0.27，B 看到 -3.0）——**B 根本没在测它声称的全镇 image**，是"已建 dyad 负值放大器"。此外 B 还：把 responder 自己的 standing 【双计】（`_town_image` 含 responder + 又单独加 `st`）；作用于【所有动作】而非仅 greet/invite；对【任意负 image】触发而非仅强 outcast<=-0.8；不覆盖硬性格短路(爱八卦)；量级过大(K8=-24/K12=-36 vs 最强局部 -18)。机理上 B 还会压低【全镇均值】，而 outcast 的忠实好友因高好感/派系仍接受→ 差距反而拉大 → #15 更差。
3. **分裂声誉是【强假说】不是【已证因果】**：`find_exile.gd` 用【终态】standing + 【全程 60 天】接受率，没记录每次决策【当时】的 standing/need/affinity/action。"+2 好友 11/11 接受"= 一个【终态 +2】的人接受了 11 次历史提议，未证明这 11 次决策时他就是 +2、就是 greet/invite。
4. **"不可约 ~5%"统计上不成立**：2/42=4.8%，95% Wilson 区间约 1.3%–15.8%，42 个 seed 立不起"稳定 5% 地板"。且软门是【固定 1-flip】(soft_min=seeds-1)不是失败率门：1/12=8.3%、1/42=2.4%、1/100=1% —— 同一"1-flip"在不同 panel 大小对应完全不同的隐含可接受率，本身就有设计矛盾。
5. **#15 指标本身口径混乱**（评审一致认为：改指标比改机制更诚实）：混了三个不可比人群（声誉=全员终态 / 遭遇=谁恰好收到提议 / 比较=各自自选遭遇集）；终态声誉 vs 全程接受（时间错配）；5 动作混池；均值无法区分"共识公敌"与"分裂派系领袖"；自选遭遇 + 重复 dyad 伪重复（seed17：21 次决策只有 2 个 responder，有效覆盖 2/11）；min 5 提议(4/5 vs 3/5 差 20pp)；镇均含最坏者(该用 leave-one-out)；**不变量非只读**——`perceived` 走 `_rel()` 会 mutate 状态（当前 Harness 在算完 digest 后才 check，故不污染门；但"观测改历史"是真隐患）。

## 真正该走的路（评审给的方向，优先于继续�+机制）
1. **先建 shadow 反事实探针**：把 `_acceptance_rule` 概念上拆出 `_acceptance_margin()`（返回数值 margin + 硬规则原因，无 mutation/无额外 RNG）；每次 baseline 提议记 bench-only 遥测（动作/双方/当时 need/当时二元 standing+affinity/派系/jitter/阈值/全员 image+覆盖率/硬accept原因/baseline margin/各 lever 反事实 margin）。**只 commit baseline 结果，lever 分数纯观测**——直接量"同样的提议与状态下，lever 会翻哪些决策"，把"lever 改了目标决策"与"世界后续演化好不好"分开。遥测走 side-channel，绝不进权威 event_log。
2. **#15v2**：日级【事前】快照 + 三态(PASS/FAIL/INCONCLUSIVE)；拆成 #15a 弱关系接受(仅 greet/invite、排除盟约/强好友、leave-one-out 镇均、要求多个不同 responder)、#15b 网络放逐(入向提议数/不同非盟友提议者/无非盟友社交时长)、#15c 忠实支持与极化(好友/派系接受单列)。再加【遭遇代表性】：`encounter_image - town_image` 大且 coverage 低 → 判 INCONCLUSIVE（seed17 正是：100% 接受只来自 18% 的可能 responder）。防"事后改指标"：旧 #15 保留 shadow、先写语义理由、不在 seed12/17 上调参、用全新 held-out seed。
3. **最佳 responder 侧候选**：consensus-gated 弱关系冷淡——仅中立/弱关系(|standing|<=0.5、affinity<FRIEND、非同派系/盟约)、仅 greet/invite、仅在 actor【持续、广泛】负声誉后、penalty 封顶、固定分母+排除 responder+滞回。更好是做成【认识论】的（靠 gossip_rep 多源独立传到才冷淡）而非上帝视角——与本项目"知识边界"哲学一致。保留忠实好友这个社交安全阀，既是好戏剧也是 #15 与 #01（社交需求会因普遍拒绝自锁饿穿）能共存的关键。
4. **别强迫 outcast 去遇到恨他的人**（那是刷统计、且方向反了：放逐应【减少】自愿共处）。若要动 movement，正解是修接触模型：`_area_key` 现在把整层 home/1f 当一个全连接房间(7 个住户夜里挤成一团)，应改"同封闭房间/耳畔半径"，并给白天公共场所(工坊/咖啡馆/市集/广场)做混合——独立于 #15 单独测。

## 处置
- **master：两个 lever 都不合入**（评审一致）。
- **branch：保留为负结果**，结论按上校正——"EXILE_NEED_DAMP 无配对净收益且没打中致因；IMAGE_SCORE_K 这个实现用了已建-dyad-only 的 image、无封顶全动作惩罚、既压低镇均又保不住忠友、还击穿 #01；两者都不 ship。这些实验【不足以】证明不可约。#15 现口径把终态声誉当全程行为、混池动作、把极化误当共识放逐、无视遭遇偏差——机制再动之前，先修指标与事前遥测。"
- 代码侧本轮小加固：`find_exile.gd` 加 `--image-k` 复现 B；`_town_image`/gate 变量加"实现有已知口径缺陷，见本 doc"的注释；gate 参数 fail-closed 夹取。**shadow 遥测 + #15v2 + targeted epistemic lever + 接触模型**列为后续独立工作。

_评审通道：GPT-5 Pro（web，21m38s 思考）+ Codex desktop（全仓 git fetch+核验，~20m，只读）。两者独立收敛于同一判断。_
