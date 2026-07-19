# 26 · Phase D — Contract Hardening（合同硬化）

起因：一次外部审计（见 conversation review, HEAD daf4791 时）指出四类社交机会的 vertical slices 是**行为策略校准成功**，
不是完整 Theory Engine；且原始 teacher-vs-logic **未在 clean packet 上直接裁决**。审计给了 3 条 P1 代码问题 + 一个
四步 Phase D。本文件记录 Phase D 的执行与结论。**所有 Phase D 工作在 `phase-d-contract-hardening` 分支上，不直接 push master。**

## 3 条 P1 全部经代码核实为真（不是 rubber-stamp）
1. **defer 对照项语义不成立** —— 四个 judge builder 里 defer/abstain/guard 都取"最高分非攻击动作"，可能是睡觉/吃饭/寒暄
   → 测的是"攻击 vs 日常动作 base rate"，不是同一机会下的"对质 vs 明确延期"。
2. **confronted age 起点错** —— `log_decisions.gd` 里 age 恒从 `triggered` 算，但冒犯方文案说"对峙至今约 N tick" →
   夸大了对峙后的拖延时长。
3. **secret guard 非 candidate-specific + fail-open** —— `theory_engine.py` 的 `hard_secret_ok` 只要"有任一未授权秘密在场"
   就禁，且全禁后回退 `logic_id` 可能重选禁行动作、并被 stats 静默丢弃。

## Step 1（DONE）：语义契约 + 3 P1 修复（commit e328354 + 后续）
- **一等 ResponseIntent（全四个 builder）**：defer/guard/abstain 改成【针对同一机会的对称结构化意图描述】
  （confront↔明确按下不表、leak↔守口如瓶、endorse↔不掺和、rally↔不参与围攻），只在攻击动作确为合法候选时入样 →
  judge 评的是【选择】不是台词文采。
- **confronted age**：冒犯方从 `confronted` tick 起算、委屈方从 `triggered` 起算。
- **secret guard**：绑定候选自己的 subject + fail-closed（无法识别/未知秘密→禁；回退绝不重选禁行动作，改选最优安全候选）。
- **中性化 packet**：去掉心结行里"（超过 22 才算难释怀）"的判据暗示（defer-prime）。
- 纯 bench 侧（log_decisions 是只读导出器）→ 不动 Sim / digest。

## Step 2（DONE）：确认性对质评测 —— clean comparator 上直接裁决
- **新数据**：30 seeds × 45 days = 120,316 decisions（`--packet`，中性化后），事件窗口去重（每个 心结×阶段 只留一例
  → 案例独立、可按 seed cluster-bootstrap）。
- **评审**：20 案（含耿直老海 6 案）× 镜像翻转 × 2 独立 pass = **80 个独立盲评**，**中性 prompt（无 defer-prime）**，
  **in_character / appropriate / dramatic 三轴分别评**（judge=Claude，独立，绝不让 teacher 自评）。

**结果（p_eff = judge 判 confront 为该选的概率；<0.5 = 偏 defer）：**

| 轴 | 耿直老海(blunt) | 其余人设 | 读法 |
|---|---:|---:|---|
| **in_character** | **1.000** [1.00,1.00] | **0.143** [0.00,0.25] | 人设相关：直性子→当面说开、其余→按下不表 |
| **appropriate** | 0.000 | 0.027 | "更明智得体"普遍偏 defer——连老海也是（in-character≠appropriate） |
| **dramatic** | 1.000 | 1.000 | "更有戏"普遍偏 confront（dramatic≠其它两轴） |

**三个关键结论：**
1. **方向在 clean comparator 上成立**：CHARACTER 规则（默认 defer + 直性子 confront）经中性、一等-defer、三轴分离的盲评
   复现——非直性子 in-character 偏 defer（p_eff 0.143 ≈ 86% defer），直性子老海一致 confront（1.000）。审计担心的
   "confront-vs-maintenance 混淆"修掉后，方向没垮。
2. **三轴确实是三个不同信号**（审计的核心诉求）：in_character 人设相关、appropriate 普遍偏忍让、dramatic 普遍偏对峙。
   把它们**分开评**才看得清——旧版把 in-character+appropriate 揉成一句"更像也更合适"，是会互相污染的。
3. **🔍 新发现：直性子例外可能不止"耿直"**。evy(莽撞) 与 tie(爽快/护短) 的 in_character 也一致判 confront（p_eff=1.0）——
   当前 `BLUNT_TRAITS := ["耿直"]` 欠覆盖。**但每人 N=4，是假设不是定论**，需更大样本（closed-loop / 更大 judge run）确认。

**诚实的局限**（不夸大）：① 这 20 案子样本只覆盖 6 seeds（CI 偏宽；预注册门 CI 下界>0.55 需 30-50 seeds 的更大 judge run）。
② 本轮 payload 未含 A=A control（tie 校准未测；镜像翻转仍在，位置偏置有控）。③ 单一模型族（Claude）；审计建议再加
第二模型族或人工抽审。④ 只做了 conflict 这一类；secret/endorse/faction 的一等-defer builder 已改好，但确认性 judge 未跑。

## Step 3-4（TODO）：闭环 A/B + 架构 go/no-go
- **闭环因果 A/B**：old/new CHARACTER gates × SURVIVAL_GATE 20/24，看 need floor / 社交动作率 / 冲突完成率 / 悬空 arc /
  事件多样性 / 玩家可见 drama cadence。
- **架构 go/no-go（初步倾向，待 A/B 定）**：Step 2 显示**简单 typed 规则已抓住方向**（blunt→confront、else→defer），
  三轴可分离——**没有证据支持重启 GBDT**（审计门：learned ranker 在 whole-seed held-out 上稳定 ≥3-5pp 且闭环无回归，
  才重启）。规则侧唯一待办是**扩 BLUNT_TRAITS**（假设：+莽撞/爽快），且要先在更大样本上过 CI gate。
