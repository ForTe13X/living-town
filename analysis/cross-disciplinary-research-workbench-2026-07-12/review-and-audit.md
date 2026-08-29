# Living Town 跨学科框架文档独立评审与审计

> 审阅日期：2026-07-12\
> 审阅对象：本目录原有六份文档\
> 审阅性质：只读设计评审；本文件不批准 API，也不表示方案已经实现\
> 变更范围：仅新增本审计文件，未修改六份原文、游戏代码、测试或分支历史

## 1. Verdict

**结论：Conditional Pass（有条件通过）。**

这套文档忠实承接了对话中的两个核心 vision：一是在 Living Town 内建立 future-proof、可组合的 Social Mechanism Framework；二是在独立 `multi-verse-bench` 中建立 deep research → 机制组合 → simulation → benchmark/analysis → evidence update 的研究闭环。两层职责分离、渐进 strangler 路线、允许 inconclusive/equivalence、以及把 fine-tuning 与 verification 分开，方向正确。

文档也基本兼容本次 Living Town 仓库评审所观察到的架构和限制：保留“合法候选 → backend 选择 → canonical effect”主链，复用 S0/S5，承认 `SimExtensions` 的可变 `Sim` 暴露、异步请求生命周期、replay/input journal、jobs 接线、CI 与 schema/provenance 缺口，并明确不做大爆炸重写。

但是，当前文本适合作为 **architecture discovery、ADR 和 schema spike 的输入**，还不适合直接冻结跨仓 API、实现 R2+ 模块或启动确认性 pilot。下列 P1 问题应先形成 ADR/契约修订。

| 审阅维度 | 判断 | 说明 |
|---|---|---|
| 对话 vision 忠实度 | Pass | 两层系统、组合枚举、选择性执行、benchmark、evidence ledger 均有承接 |
| 与当前 Living Town 兼容性 | Conditional Pass | 渐进路线正确，但 legacy extension 与 baseline 迁移仍缺契约 |
| 事实/假设边界 | Conditional Pass | 多数地方标注清楚；“已冻结决策”措辞越过现有批准状态 |
| 科学与伦理边界 | Pass | 构念效度、不可识别、泄漏、心理标签、双用途处理较成熟 |
| 下一位 agent 可执行性 | Partial | Task A 可立即执行；Task B/C 可做 spike，但不应先冻结 schema |
| 链接与文档可导航性 | Pass with one repair | 13 个本地链接均解析；1 个外链在本次检查中不稳定 |

## 2. P0 findings

**无 P0。** 没有发现会要求撤回整套构想、立即停止所有只读/文档工作，或已经造成代码/数据破坏的问题。

## 3. P1 findings

### P1-1：提案被描述成“已确定/已冻结”，决策授权状态不一致

**证据**

- `README.md:4-6` 把目录定义为“设计提案（尚未实现）”。
- `README.md:59-69` 又使用“已确定的设计决策”。
- `agent-handoff.md:26-39` 使用“已冻结的概念决策”，并要求只有 ADR 才能推翻。
- `agent-handoff.md:130` 同时说明接口草案“不要无评审冻结”。

**影响**

用户认可的是总体 vision 和产出文档的动作，并不等于逐字段批准六 namespace、R0-R4、首批 Bridge IR 或每一条默认策略。下一位 agent 可能把 agent 提议误读成维护者已批准的不可变约束，进而跳过产品/领域评审。

**建议修复**

建立一张 decision-status 表，将内容分为：

1. `user-stated vision`：独立研究台、复用 Living Town、多学科组合、simulation/benchmark/analysis；
2. `repo-derived constraint`：当前候选链、S0/S5、已知缺口；
3. `recommended default`：Bridge IR、R0-R4、profiles、Pilot；
4. `open decision`：license、首要用户、平台、预算、数据和确认集治理；
5. `accepted ADR`：只有具名维护者批准后才进入此状态。

在此之前，把“已冻结”改为“建议作为首轮 ADR 默认值”。

### P1-2：Run artifact 词汇和 identity 模型尚未闭合

**证据**

- `integration-roadmap.md:38` 定义 `RunSpec v0 / RunResult v0 / MetricRecord v0`。
- `agent-handoff.md:85` 改为 `RunSpec v0 / RunManifest v0 / MetricRecord v0`。
- `multiverse-workbench-concept.md:163-191` 使用 `RunBundle`，并让 `run_id` 同时包含模拟输入和 `metric_versions`。
- `integration-roadmap.md:36-40` 要求 runtime/content hash，但建议的 `run_id` 没有明确包含 Godot/runtime、resolved dependency graph、pack source hash、dirty-worktree 状态、hash-algorithm version 或 attempt identity。

**影响**

同一次世界模拟换一个事后 metric 可能得到不同 `run_id`；反过来，相同输入在不同 Godot/OS/pack binary 下又可能碰到同一个 ID。缓存、重放、失败重试、跨环境 drift 和 analysis provenance 都会变得含混。

**建议修复**

在写 JSON Schema 前冻结一个最小词汇表，并至少拆成：

```text
RequestedRunSpec     # 用户请求
ResolvedRunSpec      # defaults、依赖、版本和路径解析后的 canonical 输入
spec_id              # 仅由 ResolvedRunSpec 的语义字段生成
RunAttempt           # executor、runtime/environment、attempt、start/end、exit/failure
execution_id         # spec_id + executable/runtime/environment identity + attempt policy
RunBundle            # attempt 产生的不可变输出集合
bundle_hash          # 对实际 bundle 内容求 hash
AnalysisSpec         # metrics、estimand、代码和数据选择
analysis_id          # AnalysisSpec + input bundle set
EvidenceRecord       # 指向 analysis_id，不冒充 simulation identity
```

同时明确绝对路径、wall clock 不进入 `spec_id`，但 runtime fingerprint 和实际 resolved dependency 必须进入 execution provenance。

### P1-3：状态写入与 cause 模型不能覆盖当前所有系统变化

**证据**

- `social-mechanism-framework.md:21-23` 声明 Kernel 是唯一写入口。
- `social-mechanism-framework.md:41-48` 又给 `agent_view`、`normative` 和 `latent_hypothesis` 分配不同写入描述。
- `social-mechanism-framework.md:211-215` 的 `LearningRule` / `OutcomeInterpreter` 暗示模块状态可更新，但没有规定更新是否也必须生成 Kernel-validated delta/event。
- `social-mechanism-framework.md:378-380` 要求每个世界变更都能定位到“合法 candidate”。当前 Living Town 还有 need decay、nightly hook、weather/生命周期和系统调度变化，它们不天然来自 actor candidate。

**影响**

如果模块能直接写 namespaced state，replay、permission 和 provenance 会出现旁路；如果所有变化都强制伪装成 candidate，又会扭曲当前调度模型并制造虚假 actor causality。

**建议修复**

定义统一的 `CauseEnvelope` 和 state transition contract：

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

所有持久状态变更仍由 Kernel/受控 state-store executor 原子应用并写 event；模块只返回 delta proposal。可完全由事件重建的 projection 不写 snapshot，不可重建状态必须有 schema/migration。把验收措辞从“每个变更有 candidate”改成“每个变更有合法 CauseEnvelope”。

### P1-4：Bridge IR 仍有 escape hatch 和内部 schema 矛盾

**证据**

- `social-mechanism-framework.md:118-136` 的 `MechanismContribution` 没有 `phase` 字段，但组合规则要求相同 `kind + unit + phase`。
- `social-mechanism-framework.md:220-241` 的示例 manifest 标为 `integration_level: R0`，却声明 `emits: [log_odds_contribution]`；R0 是只读 observer，尚不应产生可执行行为贡献。
- `social-mechanism-framework.md:138-159` 的 `EffectPlan` 包含通用 `ApplyWorldPatch`，足以绕过“窄而有类型”的 op 边界；`rollback_policy` 由谁决定也不明确。
- `social-mechanism-framework.md:85-98` 的 `participant_views` 可能让 actor-facing evaluator 看到其他参与者的私有视图，`allowed_capabilities` 作为字段本身不能构成权限执行。

**影响**

下一位 agent 无法无歧义地生成 schema；更严重的是，通用 patch 和 participant-view 泄漏会直接破坏 Kernel-only write 与 epistemic boundary。

**建议修复**

- 给 contribution 增加明确 `evaluation_phase`、`aggregation_semantics` 和 active/shadow 状态；R0 只能输出 `shadow_contribution` 或 analysis artifact。
- 从一般 Research Pack 权限中移除 `ApplyWorldPatch`；如确有需要，将其限制为 pre-run/具名 research intervention、白名单 namespace、独立 capability 和审计事件。
- 原子性和 rollback 由 Kernel transaction contract 决定，不由任意模块提供策略。
- 按调用 principal 生成最小化 context；其他 actor 的 view 只提供显式授权的 public projection/ref，不能传完整对象。

### P1-5：缺少现有 `SimExtensions` 到新 registry 的迁移/隔离矩阵

**证据**

- `README.md:43-52` 正确指出当前五类 extension 可获得完整 Sim，权限边界不足。
- `integration-roadmap.md:92-139` 随后直接引入新的 manifest/registry/Bridge IR，但没有逐一说明 `ScenarioProvider`、`CandidateProvider`、`AcceptanceModifier`、`NightlyHook`、`ActionExecutor` 如何兼容、封装、限制或退役。

**影响**

即使新 registry 很严格，旧 `ActionExecutor`/hook 仍可能成为可变 `S` 的永久旁路；或者实现者为了消除旁路一次性重写 extension，违反渐进路线。

**建议修复**

增加 legacy seam matrix，至少记录：当前读写面、调用 phase、determinism 风险、目标 capability、过渡 adapter、允许 profile、deprecation gate。建议：

- 旧 extension 仅允许 `baseline_current`/trusted transitional lane；
- registry freeze 后禁止新增 legacy registration；
- research profile 不得调用拥有完整 `Sim` 的 legacy provider；
- 每迁移一个 seam 都做 shadow equivalence 和 off-gate；
- 最后才删除直写入口。

### P1-6：冻结 baseline 与修复已知缺陷的切点不明确

**证据**

- `integration-roadmap.md:17-26` 把 async lifecycle、journal、schema、S0/S5 CI 和 jobs 缺陷列为可信 run 的前置条件。
- `integration-roadmap.md:30-54` 又要求 Phase 0 先选 canonical baseline commit、保存 digest 并建立 byte-identical off-gate。
- `README.md:98` 和 `social-mechanism-framework.md:378` 将“当前 baseline”作为长期逐字节比较对象。

**影响**

若先冻结，jobs 等已知错误会变成受保护行为；若先修复，当前 digest 必然变化。异步修复、candidate identity 和输入 journal 也可能改变 trace/schema。没有明确 cut policy，off-gate 会在第一个正确性修复时失去含义。

**建议修复**

选择并记录一种策略：

1. 先修高风险正确性问题，再切 `baseline_corrected_v1`；或
2. 同时保存 `baseline_legacy_bug_compatible` 与 `baseline_corrected_v1`，每次有审阅过的 expected drift manifest。

任何验收都引用具名 baseline ID、commit/content/runtime，而不是漂移的“当前版本”。把跨平台 byte-identical 与同平台 pinned-runtime determinism 分开定义。

### P1-7：`EvidenceRecord` 单一状态枚举混合了正交维度

**证据**

`multiverse-workbench-concept.md:193-207` 把 `implementation_verified`、`calibrated`、`externally_validated`、`equivalent_to_other_model`、`contradicted` 等放入一个状态列表。

**影响**

一个机制可以同时“实现已验证、已校准、与 B 不可区分、在某外部域被反驳”。单状态机会覆盖历史或迫使实现者制造含混优先级，无法精确表达用户要求的 verification/fine-tune/evidence 演化。

**建议修复**

将 EvidenceRecord 改成多轴、append-only assertion：

```text
implementation_status
calibration_status
comparison_status
external_validity_status
review_status
scope/domain
claim_or_hypothesis_id
analysis_id
reviewer + timestamp + supersedes
```

“支持/反驳”必须相对于具名 claim、estimand、适用域和版本，不能成为 pack 的永久全局标签。

## 4. P2 findings

### P2-1：Pilot 还缺确认性实验所需的最小统计契约

`ExperimentSpec` 有 `analysis_plan`、budget 和 stopping rule，但尚未强制列出 estimand、分析单位、层级/聚类结构、精度或 power 目标、排除规则、缺失/失败 run 处理、多重比较族和 effect-size 容差。`agent-handoff.md` 的 Task D 可以负责补齐；在它完成前，三机制方案只能称 pilot design，不能称 preregistered confirmation。

### P2-2：方法名称较多，方法选择依据和 reference ledger 仍偏薄

文档列出 Morris、Sobol、ABC/SBI、Bayesian optimization、MAP-Elites、fractional factorial 等，但没有给出首个 pilot 为什么选择/不选择某方法、样本预算前提、失败模式和原始/权威引用。对于“deep research + 前沿研究”的 vision，建议新增 versioned reference ledger；不要因方法流行就默认适用。

### P2-3：一个外部文献链接不稳定

本次 GET 检查中，`social-mechanism-framework.md:182` 的 Harvard `littman94markov.pdf` 返回 302 到 archive 后超时；其余 7 个外链返回 HTTP 200。建议换成出版方页面（例如论文的 ScienceDirect proceedings 页面）或稳定 DOI/作者页面，并保留题名、作者、年份，避免仅依赖课程镜像。

### P2-4：MVP 缺少量化的工程预算/SLO

路线给出阶段和大致迭代，但没有给 trace overhead、单 run 最大 wall time、artifact 大小、catalog 增长、并发上限、失败重试次数和磁盘回收的默认阈值。建议在 Phase 0/1 为这些值建立可修改 budget，而不是等大规模组合后再治理。

### P2-5：不可信 pack 的默认拒绝正确，但执行边界仍需落成契约

风险文档指出 MVP 拒绝不可信任意代码，这是正确默认。还应明确 trusted-pack allowlist、无网络/最小文件权限、子进程资源限制、secret redaction、依赖锁定和供应链扫描。即使 MVP 只本地运行，也不能把“本地”当成安全边界。

### P2-6：`confidence` 尚无统一语义

`AtomicClaim`、ConstructMap 和 latent hypotheses 都使用 confidence，但没有区分 extraction confidence、mapping confidence、empirical uncertainty、posterior probability 与 reviewer judgment。建议使用不同字段/量表和 calibration rubric；不得让 LLM 自报 confidence 自动影响机制权重。

## 5. Strengths

1. **两层架构清楚。** Living Town 保持 canonical runtime，Workbench 负责研究控制平面，避免把文献、编排和大 artifact 塞进 Godot。
2. **没有建立万能理论。** 机制竞争、profile、alternative/excludes 和 equivalence class 与用户的跨学科 vision 相符，同时避免 theory soup。
3. **事实边界成熟。** world fact、agent view、normative、latent hypothesis、analytic projection、narrative 的分离，尤其适合限制 LLM 和 psychodynamic interpretation。
4. **保留现有项目优势。** 合法候选、canonical effect、deterministic digest、S0/S5 和渐进 shadow migration 都被明确保留。
5. **研究方法意识较强。** 文档区分 verify/calibrate/select/train/validate/confirm，承认 benchmark 泄漏、equifinality、层级依赖和 external validity。
6. **风险与伦理覆盖完整。** `risks-and-open-questions.md` 不只是免责声明，而是给出早期信号、缓解和停止条件。
7. **非目标明确。** CLI-first、无大爆炸重写、无自动真理/自动晋级、无单一总分，能有效控制过早平台化。
8. **Handoff 已有可执行骨架。** Task A-D 都有动作和 DoD，且明确未来命令不代表当前可用命令。

## 6. Handoff readiness

| 工作 | 当前可否开始 | 条件 |
|---|---|---|
| Task A：仓库与基线只读审计 | **可以立即开始** | 使用独立 worktree/branch；重新跑而非引用历史结果 |
| Task B：Run schema/black-box adapter spike | **可以做探索性 spike** | 先处理 P1-1、P1-2；schema 不标记 stable |
| Task C：R0 trace spike | **可以做设计/只读 prototype** | 先明确 P1-3、P1-4、P1-5；不得打开 legacy 写旁路 |
| Task D：Pilot 预注册草案 | **可以开始** | 补 P2-1；不得查看/生成所谓 confirmation 结果 |
| R2+ behavior module | **暂不就绪** | P1 全部有 ADR、off-gate 和权限测试后再进入 |
| Election/Commitment 正式迁移 | **暂不就绪** | baseline cut、cause/state contract、legacy seam matrix 先闭合 |
| 确认性跨学科结论 | **不就绪** | reproducibility、sealed split、synthetic recovery 和治理均未实现 |

因此，下一位 agent 最安全的首个动作是 Task A，加一个 **contract vocabulary ADR**；不是直接在 `Sim.gd` 中实现 `EffectPlan`。

## 7. 建议修复顺序

### 修复批次 A：允许 schema spike

1. 增加 decision-status matrix，去掉未授权的“已冻结”措辞。
2. 统一 RunSpec/ResolvedSpec/Attempt/Bundle/Analysis/Evidence 词汇和 ID。
3. 定义 pinned-runtime determinism 与跨环境 drift 的边界。

### 修复批次 B：允许 R0/trace spike

4. 定义 `CauseEnvelope + StateDelta`，保证持久状态无旁路。
5. 修正 Bridge IR：phase、shadow/active、context privacy、原子事务；限制 `ApplyWorldPatch`。
6. 增加现有五类 `SimExtensions` 的迁移/隔离矩阵。
7. 选择具名 baseline cut 策略。

### 修复批次 C：允许首个 Pilot

8. 把 EvidenceRecord 改为多轴 append-only assertion。
9. 完成 pilot estimand/analysis unit/budget/stopping/multiplicity/failure policy。
10. 增加 trusted-pack policy、工程预算和 reference ledger。
11. 修复不稳定外链并在 CI 加 Markdown relative-link check。

## 8. Audit evidence

本次检查包括：

- 完整阅读 `README.md`、`social-mechanism-framework.md`、`multiverse-workbench-concept.md`、`integration-roadmap.md`、`risks-and-open-questions.md`、`agent-handoff.md`；
- 与 `analysis/repository-review-2026-07-12/` 中的 README、findings、recommendations 和 verification 交叉核对；
- 检查 Markdown code fence 数量，六份原文均成对闭合；
- 解析 13 个本地 Markdown 链接，目标均存在；
- 对 8 个外部链接执行有限时 GET：7 个 HTTP 200，Littman 课程镜像出现 archive redirect/timeout；
- 未重新执行 Godot S0/S5；本文对测试结果只采用原报告的“2026-07-12 曾通过”历史措辞，不把它当当前状态证明。

## 9. Final audit statement

这组六份文档已经足以让另一位 agent **理解 vision、避免错误的大爆炸实现，并开始只读基线审计和契约探索**。它尚不足以让 agent 把建议字段直接当成稳定公共 API。完成 P1 修订后，可以升级为“implementation-ready design baseline”；完成 Phase 1-3 的实际验证后，才能升级为“research-run capable”；只有 sealed confirmation 与外部效度流程落地后，才可讨论“evidence-producing platform”。

## 10. Post-review remediation note

本节记录评审后的文档整改，不删除或改写上面的原始 findings，也不代表维护者批准了 API。

| Finding | 文档级处置 | 残余条件 |
|---|---|---|
| P1-1 decision authority | README 增加 user vision / repo constraint / recommended default / open decision / accepted ADR 矩阵；handoff 将“已冻结”改为首轮 ADR 默认值 | 具名维护者仍需批准 ADR |
| P1-2 run identity | 统一 Requested/Resolved RunSpec、`run_id`、RunAttempt/`attempt_id`、`result_digest`、RunBundle/`bundle_content_id`、AnalysisSpec/`analysis_id` | Schema、canonical golden vectors 与 runtime evidence 尚待 spike |
| P1-3 cause/state writes | 增加 `CauseEnvelope` 与 `StateDelta`；candidate、scheduled system、external input、intervention、migration 分开；所有持久写经受控 executor/event | 需要 permission/mutation/replay tests |
| P1-4 Bridge escape hatches | Contribution 增 evaluation phase/aggregation/shadow-active；R0 只产 shadow；移除一般 `ApplyWorldPatch`；participant context 最小化；rollback 归 Kernel | 需要 Schema、context privacy 和 capability enforcement tests |
| P1-5 legacy seams | Roadmap 增加五类 `SimExtensions` 的风险、目标 capability、过渡 lane 和退出证据矩阵 | 每个 seam 仍需 shadow/off-gate 迁移 |
| P1-6 baseline cut | 采用 `baseline_legacy_evidence` + 高风险修复后的 `baseline_corrected_v1`，用 expected-drift manifest 连接；区分 pinned-runtime 与跨平台 drift | 当前 HEAD 尚未重新跑基线 |
| P1-7 EvidenceRecord | 改为相对 claim/estimand/scope 的多轴 append-only assertion，equivalence class 独立 | Schema、迁移和 decision rules 尚待实现 |

同时补充了 Pilot `EstimandSpec` 必填项、trusted/data-only Pack 默认、confidence/uncertainty 字段语义，并将不稳定的 Littman 课程镜像替换为 DOI。

整改后机械检查：本目录本地链接无断链、Markdown fences 成对、未发现 UTF-8 replacement character，原六文档中不再残留“已冻结”、`baseline_current`、旧 RunResult 命名或 R0 active contribution。当前 verdict 仍为 **Conditional Pass for handoff and contract discovery**；实现和稳定 API 仍需具名 ADR 与运行证据。
