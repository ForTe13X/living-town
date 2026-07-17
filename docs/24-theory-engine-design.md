# 24 · Theory Engine 设计 — structural micro-social model（v1 规格）

> 承接 docs/22（NPU 决策路径）与 Phase C 复核。定位：把已验证的「引擎决策，模型配音」升级一格为
> **引擎造机会 → 模型提候选解读/响应（仅排序弱先验）→ Theory 引擎裁决 → 模型配音**。
> 不是 DSGE 的代表性主体/理性预期/均衡；是异质居民、局部知识、路径依赖、非均衡的**结构化微观社会模型**。

## 0. 为什么（Phase C + ceiling 的证据）
- teacher 无更优 policy：补上冲突显著性后 teacher 主动处理冲突 7%→88%、回归 logic；「现实 vs 戏剧」是 observation 差。
- 唯一学习窗口很窄：ceiling 分岗——**冒犯方该道歉 recall@5=90%（logic 已对）**，**委屈方小怨气 confront recall@5 仅 55%**。分歧集中在"小别扭该不该当面理论"。
- LLM 排序**非序不变**（置换后 top-5 set-overlap 0.46）→ 作先验必须**权重压低 + 固定候选序**，靠 DSL 规则扛。
- 关键抽象是 `state → social opportunity → character response`，不是 `state → action`——消解"吃饭还是 confront"的伪二选一。

## 1. TheorySnapshot v1（typed，展示串不得作输入）
每 tick 为决策 agent 生成一个只读快照。四类事实，各带出处：

```
OBSERVED   { fact_id, kind, args, known_by:[aid], provenance_event_id, tick }   # Sim 权威事实
DERIVED    { fact_id, kind, args, derived_from:[fact_id], rule_id }             # DSL 确定性推导
AUTHORED   { fact_id, kind, args }                                             # 危机/剧情生命周期/角色规则
PROPOSED   { candidate_id, evidence_fact_ids:[fact_id], mechanism_tags:[str] }  # LLM 弱先验（仅顺序）
```

v1 从现有 Sim 态映射（不新增仿真状态）：
| OBSERVED kind | 源 | 关键字段 |
|---|---|---|
| `grievance` | `Sim.conflicts` | a(委屈方)/b(冒犯方)/severity/status/triggered/escalations |
| `commitment` | `Sim._active_commitments` | a/b/area/deadline |
| `secret_known` | `agent.beliefs[*].secret` | owner/subject/claim/known_by |
| `standing` | `_rel(x,y).standing` | 声誉 sign（REP_GOSSIP_TH=-2） |
| `relationship` | `_rel` | affinity/familiarity/trust |
| `need` | `agent.needs` | 值（危机层用；日常不主导） |
| `faction` | `Sim.factions` | medoid/members |

DERIVED 例：`co_present(A,B)`、`in_private(A,area)`、`unresolved(Conflict)`、`apology_due(A,Conflict)`、`knows_secret_of_rival(A,C)`。
**知识边界内建**：`known_by` 决定该事实能否进入某 agent 的快照——冒犯方在被 confront 前**看不到**委屈方的 grievance（Phase C P0-3 已在 packet 层修，DSL 层用 `known_by` 统一强制）。

## 2. Opportunity（6 类）与 Response intent（约 10）
Drama Director 从快照识别**社会机会**（此刻是否给这条线一个 scene），再展开合法响应集：

| Opportunity | 触发（DERIVED） | 合法 response intents |
|---|---|---|
| `open_grievance` | 委屈方 + unresolved | confront · defer · disengage · deflect |
| `apology_due` | 冒犯方 + confronted | apologize · defer · deflect |
| `secret_stake` | 知秘密 + owner/其对手在场 | confide · leak · guard(=deflect) |
| `pact_need` | 盟友 need 低 | aid · defer |
| `faction_moment` | 同派系 + 外群恶名者在场 | endorse · rally_oust · abstain |
| `reconnect` | 疏远关系 + co-present | greet · give · invite · pass |

**`defer` 是一等动作**：产出 `intention{agent,opportunity,deadline}` 写回 AUTHORED，生成后续机会——"今晚不处理旧怨"合法，但 DRAMA 层保证 arc 不会无限失踪。日常维护动作（吃饭/睡觉…）由 CRISIS/无机会时兜底，不与 response intent 混选。

## 3. 规则分层（局部对数线性权重；越上层越硬）
```text
HARD       知识/权限/物理合法性——不可学习、一票否决
CRISIS     need<NEED_CRISIS(15)、硬 deadline
DRAMA      opportunity 必须推进或【显式 defer】；arc stage / cooldown
CHARACTER  traits、关系、记忆、appraisal(OCC: goal-congruence/blame/controllability)
STRATEGIC  对方可能响应、联盟与声誉后果
LLM_PRIOR  max_weight 0.75；仅 dcg(rank)；固定候选序（ceiling: set-overlap 0.46）
```
示例（Datalog/Horn + 软权重）：
```text
hard   protected_secret:  forbid leak(A,_,S) | confide(A,_,S)
                          if secret(S) and not disclosure_authorized(A,S)
drama  progress_conflict: prefer non-defer(Intent, Conflict)   w=+1.2
                          if opportunity(open_grievance,Conflict) and not explicitly_deferred(Conflict)
char   petty_grievance:   prefer defer(A,Conflict)             w=+0.9
                          if opportunity(open_grievance,Conflict) and severity(Conflict) < 10
char   avoidant:          prefer defer(A,_)                    w=+0.8   if trait(A,conflict_avoidant)>=0.7
strat  bad_standing:      prefer confront(A,B)                 w=+0.4   if standing(A,B) <= REP_GOSSIP_TH
llm    proposal_prior:    prefer Intent by 0.75*dcg(rank(Intent))
```
> `petty_grievance` 正是 ceiling 指出的窄缝：小 severity 时 CHARACTER 层把 defer 抬到与 DRAMA 的 confront 竞争——**这条软规则的权重就是要学/校准的核心参数**。apology_due 一侧 logic 已 90% 对，规则可直接硬编。

## 4. LLM 提案契约（严格）
```json
{ "proposals": [ { "candidate_id": "c1a2b3c",
                   "evidence_fact_ids": ["grievance:g17","trait:hai:direct"],
                   "mechanism_tags": ["repair","directness"] } ] }
```
只用**顺序**；不报概率、不造事实、不排除引擎候选、不写状态。因与 DSL 同源证据，**LLM_PRIOR 不作独立概率再相乘**（否则重复计人格/关系证据）。查询时**固定候选序**（消 0.46 位置偏置）；证据 id 不在快照内 → 该提案作废（fail-closed）。

## 5. 裁决 = 确定性 MAP
`score(intent) = Σ layer_weight · rule_fire`，argmax；平手用 stable-key 字典序确定性打破。
- 纯函数 of TheorySnapshot：**无 RNG / 无 Time** → 与红线兼容，S0 逐字节。
- 复用现有请求生命周期：LLM 提案带 `(world_epoch, req_id)` + 候选快照；过载/回放/低置信 → **logic 兜底**（不干等）。
- 出动作后 **stable-key 再验证**（在当前候选里重找，没了走 logic）→ `Sim.agent_apply`。

## 6. 后端选型（v1）
`Typed Datalog/Horn + 局部对数线性软规则 + 生命周期状态机 + 确定性 MAP`。
保留 MLN 的"逻辑结构 + 软权重 + 可学"，但避免全局 grounding（实时偏重）与"无动作效用语义"。仅当离线证明**全 MLN/PSL 相对 weighted-DSL 多买 3–5pp**才升级；连续 soft-truth 需求出现再看 PSL（凸 MAP）。跨学科（BDI/OCC/社会学/博弈论/精神分析低置信假设）一律桥成统一 `Signal` 喂进 CHARACTER/STRATEGIC，不直接选动作。

## 7. 离线对照（step 5，喂 judge 前的门）
同一批 held-out seeds、单案例、固定候选序，比较：
`logic · GBDT · DSL-only · LLM-first-valid · DSL+LLM-prior · (MLN/PSL) · oracle-topK`
指标：对 oracle 的 top-1、recall@K、arc 推进率、defer 合理率、secret 边界 0 泄漏、replay 确定性。
**只有 packet+稳定性过门后**才上独立 Claude blind judge，且 `in-character` 与 `dramatic/interesting` **分开评**（永不让 teacher 自评）。最后 30–50 seeds closed-loop：arc completion、dangling conflicts、causal invariants、宏观漂移。

## 8. 现状 / 下一步
- ✅ TheorySnapshot 种子：`log_decisions.gd` 已产 typed `grievances`（row 级）。P0-1..4 已修验。
- ⏭ v1 落地顺序：`TheorySnapshot` 全字段导出（+ known_by 强制）→ opportunity/intent 枚举 → 15–30 条 weighted 规则 + MAP（GDScript 侧 or 先离线 Python 原型）→ 离线对照 → judge。
- 数据纪律：`salience_probe_v0` 隔离，不进 judge/训练；judge workflow 已建、暂 park。
