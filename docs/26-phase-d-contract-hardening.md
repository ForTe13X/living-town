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
- **合并盲评**：四类各 22 案（=**88 个底层案例**，铺满 15/16/22/18 seeds）+ 每类 3-4 个 A=A control，× 镜像 × 2 同模型 pass
  = 380 次判定。**注意：单位是【案例】不是【判定】——不是"380 个独立样本"，是 88 案各 4 次相关判定（同一 Claude）。**
  统一中性 3 轴 prompt（做法 A/B 自带具体机会）。judge=Claude，独立于 teacher。
  **镜像一致率（同案不论 A/B 位置是否同判，in_character）：conflict 95% / secret 100% / faction 95% / endorse 82%**
  —— endorse 的位置稳健性最弱，其 0.852 要打折看。

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

**🔧 一条【假设】：`BLUNT_TRAITS` 可能欠覆盖——但信号很薄，且 Step 3 已否决（见下）。** 莽撞(evy)+爽快(tie) 的 in_character 也判
confront——**但底层案例只有 evy=1、tie=2 个**（judgment 计数 N4/N8 是 ×镜像×2pass 撑起来的、不是独立样本）。1–2 个案例不足以改规则；
Step 3 闭环 A/B 更把这个扩项【否决】了（破 #15，见下）。**结论：不扩，仅保耿直。**

**⚠️ 采样缺臂（审计正确指出，诚实记录，别当已验证）：**
- **endorse 只有阿丽**：本 packet 里 267 个 endorse-候选案例【全是 aria】——CHARACTER 规则在【候选生成层】就对非-八卦人设压掉了
  endorse 候选，别人根本不会面对这个机会。所以"非-八卦默认 abstain"没被 judge 验（无案可判）；要验得跑一版【规则关】的 packet。
  报告的 endorse=0.852 是 aria-only。
- **secret 没有阿丽**：aria 在本 packet 里【0 个 secret-stake 案例】（她的 leak 是 DRAMA 加权、很罕见）。所以阿丽的 gossip-leak 例外
  也没被验；要验得专门抓 aria-leak 时刻（如 find_betray 的 seed2@11145）建案。报告的 leak=0.045 是 aria 除外。
- **evy 在 leak/rally 也偏激进**各 N4（底层各 1 案），样本太小、存疑。

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

## Step 5（DONE）：DRAMA 节拍调参——抬完成率、不抹平 #15（先量后调）
A/B 里 CHARACTER 的冲突完成率只有 0.38、悬空弧 ~53，看着像"啥都没解决"。**没有盲调 DRAMA 引爆**（那会像 BLUNT 扩项一样抹平 #15），
先给 `ab_metrics` 加了【按严重度拆分 + 宽恕诊断】再量：

| 诊断（CHARACTER，默认 DRAMA） | 值 | 读法 |
|---|---:|---|
| comp_severe（够戏、该被引爆） | **0.877** | DRAMA 导演其实很勤——严重怨 88% 都结清了 |
| comp_small（小怨、该淡着保 #15） | 0.168 | 小怨本就该拖着（占 70%）→ 拉低总完成率是【设计】 |
| faded_pct（怨气已衰到触发线下、其实早原谅了） | **0.30** | 30% 悬空其实"气早消了、只是没标终态"——虚高的悬空 |

**结论：不该引爆更多、该把"宽恕落地"。** 加一个终态 **`faded`**：夜间把 simmering/lingering 里【委屈方怨气已衰到 CONFLICT_TRIGGER 下】
的怨归档成 faded（纯重标签，`DRAMA_FORGIVE_FADE` 开关、const→var 可 A/B）。它**不引爆、不动 resentment/standing**——靠【持久坏名声】
的 #15 一分不受影响；只把早已消气的怨从悬空弧挪走。

| fade off→on（CHARACTER,12s×45d） | completion | comp_small | dangling | need_floor/starved |
|---|---:|---:|---:|---:|
| off | 0.379 | 0.168 | 52.8 | 17.4 / **0** |
| **on** | **0.891** | 0.912 | 15.3 | 16.9 / **0** |

**完成率 0.38→0.89（靠宽恕落地、非多对质）、悬空砍 71%。关键验证——full S0：#15 涌现放逐【仍 12/12】**（连同 #01/#05/#08/#11/#17
全 12/12、det 3/3）。这正是要的"抬完成率又不抹平 #15"：因为 fade 只归档【真·被原谅】(怨气衰没了)的怨，而【持续被冒犯/被八卦】的人怨气
不衰→不 fade→坏名声留着→放逐涌现照旧。**同样的方法论纪律：先量(发现 30% 虚悬空 + severe 已 0.88)、选对杠杆(落地宽恕 ≠ 多引爆)、
再对 #15 验证（BLUNT 扩项正是这步没过）。** 存于 `DRAMA_FORGIVE_FADE`（默认 on）。

## 未闭合 / 明确不在本 PR 范围（审计正确指出）
- **不是 clean teacher-vs-logic 裁决**：Phase D 只在盲评上比【构造的 aggressive/passive intent】，**没有重跑 Nemotron teacher**。
  成立的结论是"没证据重启 GBDT"，**不成立**的是"teacher 已被否证"。
- **Theory Engine 仍未真正进 runtime**：语义契约是【评测层】的一等 defer；runtime 仍是手写 gates，尚无真正的一等
  `Opportunity → ResponseIntent → deadline/transition/trace`。这是后续里程碑、不是本 PR 声称完成的东西。
- **两个采样臂结构性缺失**（非"没抽到"）：endorse 候选只对 aria 生成、secret 无 aria 案 —— 见 §Step 2-scaled 的缺臂说明，
  要补得跑规则关 packet / 抓 aria-leak 时刻的专门实验。
- 可复现证据包见 `bench/bakeoff/phase_d_repro/`（命令 + SHA + tasks + 380 verdicts + A/B log；638 MiB 原始 packet 只留 SHA）。
