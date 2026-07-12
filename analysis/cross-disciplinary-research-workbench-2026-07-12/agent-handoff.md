# 下一位 Agent Handoff

## 1. 任务背景

用户的长期 vision 包含两个相互配合、但应分仓治理的系统：

1. 在 Living Town 内建立 future-proof 的 Social Mechanism Framework；
2. 在独立 `multi-verse-bench` repo 建立跨学科研究台，完成 deep research、机制组合、仿真、benchmark、分析和证据更新。

本目录是设计输入，不是已批准的最终 API，也不是实现完成证明。下一位 agent 应先验证当前代码和 sibling repo 状态，再按小垂直切片推进。

## 2. 当前 Living Town 事实快照

基于 2026-07-12 仓库评审：

- 核心 `game/scripts/Sim.gd` 约 2,423 行，承担大量确定性社会逻辑。
- `game/scripts/SimExtensions.gd` 已有五类 duck-typed extension：Scenario、Candidate、Acceptance、Nightly、ActionExecutor。
- 扩展在 freeze 后稳定排序，是好基础；但 provider 仍可获得完整 Sim 对象，读写边界不够硬。
- `game/bench/Harness.gd` 的 canonical S0 曾通过 12 seeds × 60 days、37 invariants、3/3 deterministic digests。
- `game/bench/CausalHarness.gd` 的三个定向机制 bench 曾通过配置 gate。
- 当前候选 → logic/LLM/SLM pick → canonical effect 的架构方向应保留。
- 已知高风险缺口包括异步候选快照/request epoch、完整 replay/input journal、jobs 数据接线、CI 和 schema/provenance。

完整技术证据见 [`../repository-review-2026-07-12/`](../repository-review-2026-07-12/)。不要假设这些事实在未来 commit 仍然成立；先重新跑状态和测试。

## 3. 建议作为首轮 ADR 输入的默认值

以下是 reviewer 推荐的默认值，不是维护者已经批准的公共 API。下一位 agent 应先把它们写成具名 ADR/contract spike；只有获得批准的项目才进入稳定 baseline：

1. Kernel 是 canonical world 的唯一写入者。
2. 六 namespace 分离：`world_fact/agent_view/normative/latent_hypothesis/analytic_projection/narrative`。
3. Bridge IR 首批概念：`SocialContext/MoveToken/MechanismContribution/EffectPlan`。
4. Research Pack 以小 capability 组合，不以巨型继承基类实现。
5. 新理论从 R0 observer 开始，经 R1 lens、R2 bounded modifier、R3 mechanism、R4 institution 晋级。
6. 所有模块/profile/version/parameter/seed/external input 有稳定 hash 和 provenance。
7. Deep research 自动化只能提议 claim/mapping/mechanism，不能自动接受或激活。
8. `D_dev/D_cal/D_select/D_confirm/D_ood` 必须隔离。
9. 组合空间完整登记，但按信息价值和预算选择性运行。
10. 允许 inconclusive/equivalence class，不强制单一 winner。

## 4. 明确非目标

- 不重写整个 Sim；
- 不先建 Web dashboard、微服务或云集群；
- 不把所有理论放进同一 profile；
- 不让 LLM 直接写状态、接受 claim 或生成确认性结论；
- 不把研究 profile 自动设为游戏默认配置；
- 不把论文全文、大型 run、模型权重或 secrets 放进 Git；
- 不把 psychodynamic hypothesis 当角色事实或真人诊断；
- 不把内部 simulation confirmation 宣称为现实因果验证。

## 5. 建议先读的文件

按顺序：

1. 本目录 [`README.md`](README.md)；
2. [`social-mechanism-framework.md`](social-mechanism-framework.md)；
3. [`multiverse-workbench-concept.md`](multiverse-workbench-concept.md)；
4. [`integration-roadmap.md`](integration-roadmap.md)；
5. [`risks-and-open-questions.md`](risks-and-open-questions.md)；
6. 代码：`game/scripts/SimExtensions.gd`、`game/scripts/Sim.gd`、`game/bench/Harness.gd`、`game/bench/CausalHarness.gd`；
7. 既有 review 的 findings/recommendations/verification。

## 6. 第一批建议任务

### Task A：仓库与基线审计

**动作**

- 记录 Living Town 当前 branch/commit/status、Godot version、content hash；
- 重新运行最小 S0/S5/replay，不沿用文档中的历史结果；
- 检查 `multi-verse-bench` repo 是否已创建及已有文档/ADR；
- 建立两个 repo 的 compatibility note。

**DoD**

- 没有修改当前用户工作 branch；
- 命令、退出码、环境和 digest 进入 verification log；
- 明确 current fact 与本目录 proposal 的差异。

### Task B：协议 spike（不改变行为）

**动作**

- 在 workbench 侧先统一并草拟 `RequestedRunSpec/ResolvedRunSpec`、`RunAttempt/RunBundle`、`AnalysisSpec/MetricRecord` v0 JSON Schema；
- 准备 valid/invalid fixtures 和 canonical JSON/hash 规则；
- 用手工或最薄 adapter 运行一个固定 seed 的 Living Town headless command；
- 产出完整/失败两个 RunBundle 样例。

**DoD**

- schema 验证在 CI 可跑；
- `run_id` 不依赖 map key 顺序、绝对工作目录、wall clock 或事后 metric；`result_digest`、`bundle_content_id`、`analysis_id` 分别计算；
- failed/timeout bundle 不被标记 complete；
- manifest 足以重建确切命令和输入。

### Task C：R0 只读 trace spike

**动作**

- 不改当前行为，定义一次 decision 的只读 trace；
- trace 至少含 tick/phase、actor-view ref、ordered candidate keys、selected key、effect/event refs、module/profile provenance；
- 加开关并证明关闭时 digest 不变；
- 如果开启 trace 也不应改变世界 digest，只改变输出 artifact。

**DoD**

- off-gate 通过多个固定 seed；
- trace schema 有 validator；
- 隐私边界：actor context 不意外包含 omniscient state；
- 无 live LLM 也能完整产生 trace。

### Task D：三机制 Pilot 设计预注册

**动作**

- 将 commitment/reputation/norm enforcement 写成三个 MechanismCards；
- 明确 causal graph、替代解释、positive/negative/placebo 和 mediator；
- 设计 8 个 profile 与 paired seed blocks；
- 在运行前冻结 metric、分析计划、预算和 stopping rule；
- 冻结 `EstimandSpec`：实验单位、treatment/comparator、target distribution、time window、contrast/weights、network interference/exposure、缺失/失败、多重比较和最小有意义效应；
- 先做 synthetic truth recovery。

**DoD**

- 所有组合 cell 均登记；
- calibration/select/confirm split 可审计；
- 报告允许 no-effect、equivalent、inconclusive；
- 不在 pilot 混入 identity、attachment 或 LLM behavior。

## 7. 接口草案（仅供 spike，不要无评审冻结）

```text
interface Observer:
  manifest() -> ModuleManifest
  observe(ReadOnlyEventContext) -> DerivedFacts

interface CandidateProvider:
  candidates(SocialContext) -> MoveTokens

interface ContributionProvider:
  contribute(SocialContext, MoveToken) -> MechanismContributions

interface EffectCompiler:
  compile(SocialContext, AcceptedMove) -> EffectPlan

interface MetricProvider:
  accumulate(ReadOnlyEventContext) -> MetricUpdates
  finalize(RunContext) -> MetricRecords
```

关键约束：

- provider 输入为 immutable/read-only projection，不是 `Sim`；
- `EffectCompiler` 无提交权限；
- Kernel executor 重新校验 token revision、precondition hash 和 op invariants；
- capability 未在 manifest 声明则不能被调用；
- 模块的 RNG 由 Kernel 按 namespace/key 提供，不允许自建 wall-clock seed。
- 首个可运行阶段只接受声明式 pack，或经过 code review、随固定 simulator build 交付的 trusted code；manifest capability 不是 OS sandbox，动态不可信 plugin 不进入该 spike。

## 8. 建议目录契约

Workbench 首版可以是：

```text
multi-verse-bench/
  README.md
  docs/
    feasibility.md
    architecture.md
    implementation-plan.md
    PRD.md
    IPD.md
    ADR/
  schemas/
    run-spec.schema.json
    run-manifest.schema.json
    metric-record.schema.json
  src/multiverse_bench/
    catalog/
    executor/
    artifacts/
    experiments/
    analysis/
    research/
  packs/
  fixtures/
  tests/
```

这只是合理默认；若 sibling repo 已有结构，优先复用并写 ADR，而不是为匹配本文强制重排。

## 9. Code review / audit 关注点

### Living Town PR

- 是否默认关闭且 baseline digest 等价？
- 是否新增任何 extension 直接写 `S`？若是，应拒绝或明确仅为过渡层。
- candidate 是否使用 stable key/revision/hash，而非 index？
- RNG 是否按 module/purpose keyed，禁用模块是否不消耗抽样？
- trace 是否泄漏角色不可知信息？
- EffectPlan 是否 fail closed、原子、守恒并带 provenance？
- replay 是否记录所有外生输入和 profile/version？
- schema/migration/兼容失败是否显式？

### Workbench PR

- 同一 spec/hash 是否真正意味着同一 resolved experiment？
- 是否把绝对路径、时间戳等不稳定字段错误纳入 semantic identity？
- failed/cancelled/skipped cells 是否完整保留？
- 是否存在确认集泄漏或自动调参后仍称 confirmation？
- 报告能否追溯到完整 run set 和 analysis code hash？
- 是否只展示平均数而隐藏分布、交互和失败？
- 外部 source/license/privacy 是否有记录？
- 是否引入尚无真实需求的基础设施复杂度？

## 10. 推荐验证命令形态

实际路径和参数需按当前 repo 更新；以下是目标形态，不保证已经存在：

```powershell
# Living Town baseline（先记录 legacy evidence，正式 gate 使用 corrected baseline ID）
godot --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3
godot --headless --path game --script res://bench/CausalHarness.gd -- --seeds 1-8 --days 40

# Future adapter
godot --headless --path game --script res://lab/LabAdapter.gd -- --spec run-spec.json --out run-output

# Future workbench
multiverse-bench validate run-spec.json
multiverse-bench run run-spec.json
multiverse-bench inspect <run-id>
multiverse-bench reproduce <run-id>
multiverse-bench compare <experiment-id>
```

不要把“文档展示的未来命令”写成当前可用命令；实现后必须在干净 clone/CI 证明。

## 11. 决策前需要询问用户/维护者

- Workbench 的首要用户和发布形态；
- 开源许可证、是否允许 private packs；
- 可接受计算预算和支持平台；
- 是否会使用真实人类/玩家数据；
- 研究结果进入 game_default 的审批流程；
- 确认性 benchmark 的保管人与访问策略。
- `baseline_corrected_v1` 的切点、expected-drift manifest 审批人和 pinned runtime。

这些问题不阻止 schema/black-box runner spike，但会影响 PRD/IPD 和治理设计，不能由 agent 静默替用户决定。

## 12. Handoff 验收

下一位 agent 接手后，应能够：

- 用本目录复述“内层机制框架”和“外层研究台”的职责差异；
- 明确哪些是当前实现、哪些是 proposal；
- 不触碰用户当前 Living Town branch 即可开始独立 worktree/PR；
- 选择 Task A/B/C 中一个小切片，给出变更范围、验证和 rollback；
- 不在未解决 reproducibility/off-gate 前扩大理论数量；
- 对任何研究结论保留 provenance、适用边界和 inconclusive 可能性。
