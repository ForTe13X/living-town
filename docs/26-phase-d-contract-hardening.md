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

**诚实的局限**（不夸大）：① 这 20 案子样本只覆盖 6 seeds（采样 bug：sorted(key) 是字符串序+截断→挤在低 seed）。
② 本轮 payload 未含 A=A control。③ 单一模型族（Claude）。④ 只做了 conflict。→ **下面 Step 2-scaled 全部补上。**

## Step 2-scaled（DONE）：四类机会 + A=A controls + 铺满 seed
- **采样修复**：四个 builder 的 `sorted(key)[:N]` 是【字符串序+截断】→ 只覆盖少数低 seed；改成【数值 seed 排序 + 等距/轮转抽样】。
  非-conflict 三类加事件窗口去重（每 (seed,agent) 一例）；conflict 从 status×persona 桶（~36 桶→per=1→挤 seed1）改成
  persona 桶（~12 桶→per≥3→桶内按 seed 铺开）。
- **合并盲评**：四类各 22 案（铺满 15/16/22/18 seeds）+ 每类 3-4 个 A=A control，× 镜像 × 2 pass = **380 个独立盲评**，
  统一中性 3 轴 prompt（做法 A/B 自带具体机会）。judge=Claude，独立。

**结果（p_eff = judge 判【激进动作】为该选的概率；cluster-bootstrap by seed）：**

| 机会 | in_character（激进） | appropriate | dramatic | A=A tie率 | 裁决 |
|---|---|---:|---:|---:|---|
| **confront** | 直/莽/爽 **1.000**[1.0,1.0] N28 · 其余 **0.017**[0,0.05] N60 | 0.006 | 1.000 | **1.00** | 默认 defer + 直性子 confront ✓ |
| **leak** | **0.045**[0,0.14] | 0.000 | 0.989 | **1.00** | 默认 guard 守信 ✓ |
| **endorse** | 阿丽(爱八卦) **0.852**[0.75,0.94] N88 | 0.000 | 1.000 | **1.00** | 八卦人设 endorse 例外 ✓ |
| **rally_oust** | **0.091**[0.01,0.20] | 0.000 | 1.000 | **1.00** | 默认 abstain·零例外 ✓ |

**三条强结论：**
1. **四类规则方向全部在 clean comparator 上复现**（一等-passive + 中性 prompt + 铺满 seed）：confront 默认忍/直性子说开、
   leak 默认守信、endorse 只八卦人设、rally 默认置身事外——审计担心的"defer=maintenance 混淆"修掉后没一个垮。
2. **A=A control tie率四类全 1.00** → judge 校准可信（对相同 A/B 一致判平，不是瞎选），大幅抬高结论效力。
3. **三轴是三个不同信号，四类通吃**：appropriate 一律偏 passive(≈0)、dramatic 一律偏 aggressive(≈1)、in_character 才人设相关。
   这正是审计的核心诉求——**分开评才看得清**，且四类都成立。

**🔧 一条被验证、可落地的规则修正：`BLUNT_TRAITS` 欠覆盖。** 直性子 confront 例外不止"耿直(hai)"——莽撞(evy N4)+爽快(tie N8)
在 in_character 上同样一致判 confront（合并 N28、p_eff=1.000、CI[1.0,1.0]），其余人设 0.017。建议 `["耿直"]→["耿直","莽撞","爽快"]`
（改 Sim → 动 digest，需过 S0 CI；这是 Step 3 闭环 A/B 顺带验的第一项）。次要：莽撞(evy) 在 leak/rally 上也偏激进（各 N4，样本小、
存疑）；阿丽的 gossip-leak 本轮没被抽到 secret 案（无 aria secret 样本），是待补的一个缺口。

## Step 3（DONE）：闭环因果 A/B —— 并【否决】了 judge 验过的 BLUNT 扩项
把 6 个门（CHARACTER_DEFER / BLUNT_TRAITS / DRAMA_GOSSIP_LEAK / FACTION_MOB_DEFER / FACTION_ENDORSE_DEFER / SURVIVAL_GATE）
从 const 改 var（配置项，不进 digest、默认不变→CI 逐字节不变）供换档；把 Step-2 验过的 `BLUNT_TRAITS` 扩项
（`["耿直"]→["耿直","莽撞","爽快"]`）先【暂挂上】跑闭环 + S0。`bench/ab_metrics.gd` 在四档 × 12 seeds × 45 天下量下游产出：

| 指标（12seed×45d 均值） | A 逻辑地板(char off) | B CHARACTER(耿直) | C CHARACTER(+莽撞+爽快) | D C@gate22 |
|---|---:|---:|---:|---:|
| need_floor / **饿穿** | 19.4 / **0** | 17.4 / **0** | 17.9 / **0** | 16.2 / **0** |
| confront/局 | **82** | 35 | 44 | 43 |
| rally_oust/局 | **34** | 14 | 14 | 15 |
| 冲突完成率 | **0.89** | 0.38 | 0.45 | 0.45 |
| 悬空弧/局 | **10** | 53 | 50 | 50 |
| drama/天 | **2.58** | 1.09 | 1.29 | 1.28 |
| 事件熵 | 3.06 | 2.79 | 2.79 | 2.78 |

**读法：**
1. **CHARACTER 规则确实把镇子变了个活法**（vs 逻辑地板）：对质 ~减半(82→35~44)、公开合围 ~减 60%(34→14)、drama 节拍变缓
   (2.58→1.3/天)、小怨气更多地【搁着不了】（悬空弧 10→50）。这【正是设计意图】——一个"大多数小别扭就让它过去、不机械地逢怨必对质"
   的镇子（Step 2 盲评也说这更 in_character）。
2. **代价是明摆着的、是个旋钮不是 bug**：逻辑地板"完成率 0.89"是因为它逢怨必对质→必道歉→必和解；CHARACTER 让怨气 linger
   （完成率 0.45、50 条悬空）——更真实（真实的怨很多就是拖着），但开着的弧更多。DRAMA 导演(1200 tick 才爆)在 45 天里还没引爆足够多的
   长 linger 怨 → **一条可调线索：想抬完成率就调 DRAMA 爆发节奏**（这是 DRAMA 轴、与 CHARACTER 规则正交）。
3. **#01 无饿穿在【所有】配置下都成立**（starved=0，连 SURVIVAL_GATE=22 也是）→ need-floor 稳。

**🚩 头号结论——闭环【否决】了 judge 验过的 BLUNT 扩项。** ab_metrics 看 C（扩项）像个温和改进（对质 35→44、完成率 +7pp、
need_floor 略升、饿穿 0）；但**同一次 S0 CI 抓出它破了软不变量 #15 涌现放逐（10/12 < 门）**：多两个人设逢怨即对质→更多怨被
引爆和解→没人攒下【持久】坏名声→放逐涌现被抹平（正应验 `DRAMA_ERUPT_SEV` 注释早写下的警告）。**judge 验过 ≠ 能上**——把 BLUNT
【退回仅耿直】后 #15 立即回 12/12、S0 全绿。这正是审计要求"persona 例外必须单独过 CI gate"、也正是要做闭环因果 A/B 的全部意义：
盲评（in_character，N=4/人，样本小）说该扩，闭环（因果、全 12 seed）说不该。**以闭环为准 → 不扩。**

## Step 4：架构 go / no-go（证据齐了）
- **KEEP 简单 typed CHARACTER 规则（仅耿直）。** 两路证据合流：Step 2 说规则 in_character 方向对（四类 + A=A 校准），Step 3 说
  规则在闭环里产出一个可辨、更贴人设、#01 安全、#15 放逐不被抹平的镇子。规则纯 f(persona/state)、零运行时推理。
- **BLUNT 扩项：REJECTED（被闭环否决）。** 判据侧 N=4 的小信号不敌闭环侧的 #15 代价。莽撞/爽快待【更大样本】+ 一个【不抹平 #15
  的 DRAMA 侧做法】再议——不是永久否，是"证据不够 + 有已知副作用，先不上"。
- **NO-GO 重启 GBDT。** 没有证据满足门槛（learned ranker whole-seed held-out 稳定 ≥3-5pp 且闭环无回归）：规则简单、在 judge 与
  closed-loop 两面都验住了，看不到 learned ranker 能赢的缝。LLM 若入场只作 bounded/shadow prior，hard epistemic 规则永远优先。
- **副产品**：6 门变可配置（const→var，digest 中性）→ 以后做 A/B / 设置档 / shadow-mode 都有抓手。留作 DRAMA 轴调参：悬空弧偏高
  → 调 `DRAMA_ERUPT_*` 把长 linger 的要紧怨更多引爆结清（这才是"抬完成率又不抹平 #15"的正解，正交于 CHARACTER）。

**Phase D 收尾**：审计 3 条 P1 全修、语义契约立起、四类机会 clean-comparator 确认性复现、闭环 A/B 给因果证据【并否决了一个 judge
验过的改动】、go/no-go 落定（保仅-耿直规则、BLUNT 扩项被闭环否决、不上 GBDT）。**核心方法论收获：judge preference 与 closed-loop
causality 都要过，缺一不可——本次正是闭环拦下了盲评放行的改动。** 全部在 `phase-d-contract-hardening` 分支。

## Step 3-4（TODO）：闭环 A/B + 架构 go/no-go
- **闭环因果 A/B**：old/new CHARACTER gates × SURVIVAL_GATE 20/24，看 need floor / 社交动作率 / 冲突完成率 / 悬空 arc /
  事件多样性 / 玩家可见 drama cadence。
- **架构 go/no-go（初步倾向，待 A/B 定）**：Step 2 显示**简单 typed 规则已抓住方向**（blunt→confront、else→defer），
  三轴可分离——**没有证据支持重启 GBDT**（审计门：learned ranker 在 whole-seed held-out 上稳定 ≥3-5pp 且闭环无回归，
  才重启）。规则侧唯一待办是**扩 BLUNT_TRAITS**（假设：+莽撞/爽快），且要先在更大样本上过 CI gate。
