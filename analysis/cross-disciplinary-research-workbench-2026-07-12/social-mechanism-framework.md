# Social Mechanism Framework：内层架构提案

## 1. 目标与边界

目标是把 Living Town 从“持续增加规则的社会模拟器”演进为“可承载多个可竞争机制模型的确定性实验内核”。框架只承诺：

- 理论可以低成本接入、禁用、替换和组合；
- 每次世界变化都可追溯、重放和审计；
- 不同学科保留自己的构念，不被强迫压缩成同一标量；
- 理论解释和世界事实严格隔离；
- 能用定向场景、反事实和多尺度 pattern 检验机制，而不只是观察漂亮故事。

它不承诺找到唯一真实的人类行为模型，也不承诺通过模拟本身完成现实世界因果识别。

## 2. 设计原则

### 2.1 机制平台，而非理论层级

社会学、博弈论、认知 appraisal、社会身份或 psychodynamic lens 都是可版本化的 module/lens/protocol。它们通过同一窄协议协作，不形成“某学科天然支配其他学科”的继承树。

### 2.2 Canonical reality 只有一个写入口

只有 deterministic kernel 可以提交原子世界事务。模块不能直接得到可变 `S`，也不能从 LLM 文本反射式修改字段。

### 2.3 先区分语义，再谈组合

`illegal`、`prohibited` 和 `unpreferred` 必须不同：

- `illegal`：结构上不能提交；
- `prohibited`：可以发生，但违反规则并可能受制裁；
- `unpreferred`：合法且不违规，只是行动者不愿意。

同样，utility、probability、log-odds、hazard、salience、各类 uncertainty 和 narrative cue 不能无单位相加。

### 2.4 明确 upward 与 downward causation

宏观指标可以由个体事件聚合；宏观状态要影响个体时，必须经过可见、可测试的制度/传播 bridge，不允许隐藏的全局乘数。

## 3. 六种“真相”命名空间

| 命名空间 | 内容 | 例子 | 写入权限 |
|---|---|---|---|
| `world_fact` | 已发生且由 Kernel 认证的事件与物质状态 | 转账、到场、公开发言、角色任命 | Kernel only |
| `agent_view` | 角色感知、记忆、信念与不确定性 | “A 听说 B 爽约”，置信度 0.6 | 经观测/学习事务 |
| `normative` | 规则、角色、权利、义务、允许/禁止与制裁 | 租户应按时付租，违反后的程序 | 制度事务 |
| `latent_hypothesis` | 理论模块对不可直接观察构念的假设 | attachment expectation、identity salience | namespaced module state |
| `analytic_projection` | 从事件计算出的研究指标或聚类 | faction projection、中心性、极化、Gini | 只读派生 |
| `narrative` | 台词、内心独白、解释文本和 UI 表达 | LLM 生成的原因描述 | 展示层 only |

强制不变量：

```text
narrative          -X-> world_fact
latent_hypothesis  -X-> world_fact
analytic_projection-X-> world_fact
```

如果一个 hypothesis 要影响行为，它只能产生限幅、带 provenance 的机制 contribution；如果一个 projection 要下行影响个体，它必须经具名 bridge 变成可观察的事件、制度约束或资源变化。

### 3.1 需要进一步拆开的现有概念

派系/群体至少应区分：

1. `community_projection`：算法从关系网络推导出的聚类；
2. `recognized_identity`：NPC 自己知道和认可的身份；
3. `formal_group`：具有加入/退出、角色、资源和决策程序的组织。

Memory 至少应区分：

```text
EpisodeMemory     # 经历或感知，可指向源 event
SemanticBelief    # claim + evidence + belief_confidence
DerivedInsight    # 可重算的确定性推论
NarrativeMemory   # 用于表达的文本，不是认知证据
```

Relationship 不应退化为单一 affinity；可在现有 trust/affinity/resentment/standing 上稀疏扩展 `dependence`、`obligation`、`perceived_status`、`legitimacy`、`uncertainty`，并明确每一维的更新语义。

## 4. Bridge IR

Bridge IR 是跨学科共享的“机制中间表示”，不是大而全的社会本体。第一版只冻结必要字段和版本规则。

### 4.1 `SocialContext`

```text
SocialContext {
  schema_version,
  tick, phase, scenario_id,
  actor_view,
  public_participant_refs,
  place, roles, recognized_groups,
  institution_context,
  public_channel, private_channel,
  time_scale,
  allowed_capabilities
}
```

`actor_view` 只能包含该角色在当前 tick 合法可知的内容。其他参与者只暴露调用 principal 被授权的 public projection/ref，不能传完整 `participant_views`；研究员视角另走 `AnalyticContext`。`allowed_capabilities` 只是可审计声明，实际权限必须由调用方构造最小 context 并在 executor 强制执行。

### 4.2 `MoveToken` / `Candidate`

```text
MoveToken {
  stable_key,
  protocol_id, protocol_version,
  revision,
  actor_id, participant_ids,
  preconditions,
  observability,
  intended_effect_kinds,
  valid_from, valid_until,
  canonical_hash
}
```

异步 backend 只能返回 `stable_key + revision/hash`，Kernel 再对当前世界重新验证；禁止用旧数组 index 解释迟到回包。

### 4.3 `MechanismContribution`

```text
MechanismContribution {
  module_id, module_version,
  construct_id,
  candidate_key,
  kind,            # constraint | utility | log_odds | hazard | salience | cue
  unit,
  evaluation_phase,
  aggregation_semantics,
  activation,      # shadow | active
  value,
  bound,
  model_uncertainty,
  evidence_event_ids,
  assumptions,
  explanation_key
}
```

组合器只能按声明的 `kind + unit + evaluation_phase + aggregation_semantics` 合并。R0 只能产生 `activation: shadow` 的分析记录，不能进入选择仲裁。`model_uncertainty` 不能复用 LLM 自报 confidence；证据抽取置信、构念映射置信、经验不确定度、posterior 和 reviewer judgment 必须使用不同字段与量表。每项保留独立 ledger；即使最终得到一个选择，也能回答各机制贡献了什么。

### 4.4 `EffectPlan`

```text
EffectPlan {
  plan_id, caused_by,
  precondition_hash,
  atomic_ops: [
    TransferAsset,
    RelationDelta,
    BeliefUpdate,
    CreateOrSettleCommitment,
    AssignOrRemoveRole,
    PublishSignal,
    RecordNormStatus
  ],
  observation_policy
}
```

模块只“编译”计划；Kernel 校验 ID、范围、守恒、权限和前置条件后统一提交，原子性与 rollback 由 Kernel transaction contract 决定。未知 op 或 schema version 必须 fail closed。一般 Research Pack 不拥有通用 `ApplyWorldPatch`；确有需要的 world patch 只能作为 pre-run、白名单 namespace 的具名 `ScenarioIntervention`，使用独立 capability、双重校验和审计事件。

### 4.5 `CauseEnvelope` 与 `StateDelta`

并非所有合法变化都来自 NPC candidate。需求衰减、天气、生命周期、迁移和外生输入必须拥有真实 cause 类型，而不是伪装成 actor 行为：

```text
CauseEnvelope = CandidateCause
              | ScheduledSystemCause
              | ExternalInputCause
              | ScenarioInterventionCause
              | MigrationCause

StateDelta = WorldDelta
           | AgentViewDelta
           | NormativeDelta
           | ModuleStateDelta
```

所有持久 `StateDelta` 都由 Kernel 或受控 state-store executor 原子应用并写 versioned event；模块只能返回 proposal。完全可由事件重建的 analytic projection 不进入权威 snapshot；不可重建的 module state 必须声明 schema、migration 和 cause provenance。

## 5. Interaction Protocol / GameSpec

选举、邀请、租赁、谈判、公共品和联盟不应各自发明状态机；用 typed protocol 描述：

```text
GameSpec {
  id, version,
  participants, positions, roles,
  information_structure,
  phases, action_space,
  simultaneous_or_sequential,
  response_graph,
  payoff_dimensions,
  observation_and_witness_rule,
  decision_or_aggregation_rule,
  enforcement_and_sanction,
  settlement_effects,
  repetition_and_learning_policy
}
```

它与 Ostrom/IAD 的 action situation（参与者、位置、行动、信息、控制、结果、成本收益）相容，也能表达重复博弈和制度程序。参考：[IAD Framework](https://ostromworkshop.indiana.edu/courses-teaching/teaching-tools/iad-framework/index.html)、[Littman 1994 Markov games](https://doi.org/10.1016/B978-1-55860-335-6.50027-1)。

规范建议表达为：

```text
Norm {
  scope, condition,
  deontic: must | may | must_not,
  target_action,
  role_or_actor,
  observability,
  expected_sanction,
  legitimacy,
  adoption_state,
  source_institution
}
```

并分开纸面规则、NPC 是否知道、预期他人是否遵守、自己是否认为正当、实际执行和制裁。可借鉴 [Crawford & Ostrom 的制度语法](https://www.cambridge.org/core/journals/american-political-science-review/article/grammar-of-institutions/7D37CD3BC5ED2D9FD57D2EE292958F47)，但不应照搬为唯一内部本体。

## 6. Research Pack 与能力接口

避免一个要求所有理论实现几十个空方法的巨型 `SocialModule`。Registry 接受小能力：

- `Observer / FeatureExtractor`：event/snapshot → derived fact；
- `CandidateProvider`：context → candidates；
- `ProtocolProvider`：注册 GameSpec；
- `AppraisalProvider`：context/event → appraisal dimensions；
- `PayoffProvider`：candidate → 多维 payoff contribution；
- `StrategyProvider`：在合法 move 中提出选择分布；
- `AcceptancePolicy`：响应/拒绝/协商；
- `LearningRule`：从 observation 更新 belief/strategy state；
- `OutcomeInterpreter`：把结果转成模块自己的 observation；
- `EffectCompiler`：proposal → typed EffectPlan；
- `MetricProvider`、`InvariantProvider`、`ScenarioProvider`。

Manifest 最小字段：

```yaml
id: soc.norm_expectation
version: 0.1.0
api_version: 1
theory_family: sociology
epistemic_mode: mechanism       # observer | lens | presentation | mechanism
integration_level: R0
reads: [agent_view, normative]
emits: [shadow_contribution]
phases: [decision_evaluation]
rng_namespace: soc.norm_expectation
requires: []
conflicts: []
composition: alternative        # compose | alternative | excludes
state_schema: 1
migration: rebuild_from_events
parameters: []
time_scales: [interaction, day]
scope_conditions: []
assumptions: []
references: []
falsification_scenarios: []
```

Registry 必须在开局前 freeze，检查唯一 ID、semver/API 兼容、依赖环、读写权限、冲突、阶段顺序和 RNG namespace。Manifest 缺字段或声明不一致应拒绝实验，而不是静默 fallback。

首个可运行阶段不把 manifest 当作安全 sandbox。Pack 仅允许两种信任形态：声明式 data/config；或经过 code review、随固定 simulator build 交付的 trusted code。动态加载的不可信 GDScript/Python/native plugin 必须后置到独立 threat model、进程/网络/文件/secret/resource 隔离与 abuse tests 通过之后。

## 7. 决策组合管线

推荐固定语义阶段：

```text
constitutive rules
→ protocol legality
→ deontic/norm status
→ goals and motive vector
→ strategic expectations/payoffs
→ bounded arbitration
→ validated EffectPlan
→ observation, appraisal and learning
```

可以为 motive 提供少量跨模块维度，如 `survival/security/affiliation/autonomy/status/obligation/care/curiosity/threat`，但这只是协商层，不要求所有学科把自己的构念消解到这些维度。模块特有的 annotation 保留在自己的 namespace。

当两个模型解释同一 causal edge 时必须声明：

- `compose`：明确组合规则与单位；
- `alternative`：属于竞争模型，不在同一 profile 同时启用；
- `excludes`：状态或前提矛盾，Registry 拒绝组合。

## 8. Micro / meso / macro bridge

| 层级 | 一等对象 | 典型机制 |
|---|---|---|
| micro | belief、need、appraisal、strategy | 注意、选择、学习 |
| dyad | relationship vector、commitment、dependency | 互惠、信任、债务、重复互动 |
| group/network | identity、coalition、diffusion、network position | 同群偏好、桥接、规范传播 |
| institution | role、rule、decision procedure、sanction | 选举、市场、租赁、集体行动 |
| macro | inequality、polarization、legitimacy、culture pattern | 统计投影与制度反馈 |

宏观下行只能通过显式机制，例如：

```text
high inequality projection
→ tax institution changes eligibility/rate
→ public rule announcement event
→ agents observe with unequal reach
→ belief, legitimacy and strategy contributions
```

不能直接把 `inequality` 写入每个 NPC 的 happiness。

## 9. 跨学科落点

### 9.1 社会身份

- R0：计算 recognized membership、identity salience、同/异群互动指标；
- R1：解释合作或排斥候选；
- R2：在身份确实被情境激活时，对合作/背书产生限幅 contribution；
- 验证：跨群桥接率、homophily、不同公开/私密情境下的差异，及替代网络机制比较。

### 9.2 公共品与博弈论

Festival fund 可成为首个公共品 `GameSpec`：贡献可公开或私密，允许搭便车、二阶制裁、声誉与重复学习。机制与经济、派系、规范、选举通过 protocol/event 相连，而不是互相直接改内部字段。

### 9.3 Appraisal

优先用动态 appraisal 连接事件和行动倾向：`goal_congruence/certainty/agency/controllability/coping_capacity/norm_compatibility`。它比永久 personality label 更易与定向场景验证，也适合驱动记忆显著性和表达。参考：[Scherer 的 component process model 概述](https://pmc.ncbi.nlm.nih.gov/articles/PMC2781886/)。

### 9.4 Attachment / psychodynamic lens

只把“某关系中的可依赖预期”“接近—被拒绝—回避模式”“冲突或 defense hypothesis”作为带置信度、证据和替代解释的 namespaced hypothesis：

```text
RelationalExpectation {
  subject, toward,
  expectation_kind,
  posterior_or_confidence,
  supporting_events,
  contradicting_events,
  decay,
  validity_scope
}
```

先接 R0/R1，只影响分析和叙事；要进入 R2，必须相对更简单 appraisal baseline 产生可区分预测，且效果限幅、可关闭、可被后续安全互动反证。禁止临床标签、真人诊断和“无意识真相”式 canonical fact。

### 9.5 权力与依赖

权力不应等同 standing。可从住房、工作、稀缺资源控制、关系依赖、网络中介位置和制度角色推导可测试的 bargaining position，并观察其如何影响可接受选项、退出成本和制裁可信度。

## 10. 接入风险等级

| 等级 | 权限 | 晋级条件 |
|---|---|---|
| R0 Observer | 只读事件/快照，输出指标 | schema、determinism、projection test |
| R1 Lens | 解释、台词、UI，不改选择 | provenance、privacy、叙事不写回 |
| R2 Bounded Modifier | 限幅影响 salience/score/acceptance | paired counterfactual、敏感性、替代模型比较 |
| R3 Mechanism | 新 protocol/candidate/effect | invariants、replay、机制恢复、迁移 |
| R4 Institution | 宏观反馈、角色、规则和制裁 | 多尺度验证、长期稳定性、治理审计 |

所有新 pack 从 R0 开始；晋级是版本化变更，不能在同一版本悄悄增加写权限。

## 11. Determinism、版本与审计

- RNG key 建议：`seed/module_id/mechanism_instance/event_or_tick/actor_id/draw_name`；禁止 global RNG、wall clock 和调用顺序隐式消耗。
- dormant module 必须不抽样、不插入候选、不改变排序。
- 所有 map/set 在 hash、序列化和仲裁前 canonical sort。
- 浮点 contribution 使用量化/定点约定，并固定 rounding。
- Event 记录 `module_id/version/config_hash/parent_event_ids/plan_id`。
- Snapshot 记录 kernel、content、profile 和 schema hash；跨版本必须显式 migrate 或报告 drift。
- 模块状态 namespaced；尽量由事件重建，无法重建的状态必须有 migration。
- 外生输入（玩家、LLM pick、scenario patch、research intervention）进入 input journal。
- 同时行动优先使用 frozen snapshot + intent collection + phase barrier，减少 agent 遍历顺序偏差。

## 12. 验证阶梯

1. **V0 结构验证**：schema、权限、守恒、determinism、off-gate。
2. **V1 定向单元场景**：机制在必要/充分条件下触发，negative/placebo 不触发。
3. **V2 配对反事实**：固定 seed，只改变一个机制或干预，检查 effect direction、mediator 和 latency。
4. **V3 多尺度 pattern**：同时匹配 micro、dyad、network、institution、macro 多个预先声明的 pattern，避免只拟合一个终点。
5. **V4 敏感性与识别性**：参数恢复、结构替代、equivalence class、Morris/Sobol 或其他适当方法。
6. **V5 外部/产品验证**：held-out data/scenarios、玩家可理解性与游戏价值；二者不能互相替代。

现有 S0 可承接 V0，S5 可承接 V1/V2；它们应被扩展而非替换。模型文档建议采用 [ODD 2020](https://pubs.usgs.gov/publication/70209554) 与面向人类决策的 [ODD+D](https://www.stockholmresilience.org/publications/publications/2013-12-09-describing-human-decisions-in-agent-based-models---odd---d-an-extension-of-the-odd-protocol.html)。多 pattern 验证可参考 [Grimm 等的 pattern-oriented modeling](https://pubmed.ncbi.nlm.nih.gov/16284171/)。

## 13. 建议 profiles

```text
baseline_legacy_evidence  # 保存审阅时的历史行为，只作证据，不保护已知缺陷
baseline_corrected_v1     # 高风险正确性问题修复后切出的正式 off-gate 基线
game_default              # 经产品验证的稳定组合
strategic_institutions    # GameSpec + roles + norms + learning
identity_and_networks     # recognized identity + diffusion
psychodynamic_narrative   # R0/R1，不拥有世界写权
research_candidate_X      # 明确实验性，不进入默认游戏
```

## 14. 框架验收标准

- 禁用所有新模块时，指定 seeds 在 pinned runtime 下与具名 `baseline_corrected_v1` 的 event digest 逐字节一致；跨平台不可比较时必须显式报告 drift/tolerance。
- 未声明 capability 的模块无法读取或写入相应 namespace。
- 任一持久状态变更都能定位到合法 `CauseEnvelope`、`StateDelta/EffectPlan`、module/profile version 和 cause events。
- 任一 LLM/narrative 输出都不能越过 Kernel 验证产生世界事实。
- 两个竞争理论可以在不改 Kernel 的情况下组成两个 profile 并做 paired run。
- 同一 contribution ledger 能解释“哪些机制、按何单位、在何阶段”影响一次选择。
- macro projection 不能隐式写回；每个 downward bridge 有自己的 scenario、metric 和 invariant。
- Research Pack 能被完全卸载，且不留下 RNG、schema 或 snapshot 污染。
