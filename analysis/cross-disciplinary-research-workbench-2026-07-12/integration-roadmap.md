# Living Town 接入与实施路线图

## 1. 路线原则

本路线采用渐进式 strangler pattern：先保存历史证据并修复高风险正确性问题，再切出具名 `baseline_corrected_v1`，随后在外围建立 adapter/trace，最后逐个机制迁移。禁止把已知缺陷冻结成长期正确性目标，禁止大爆炸重写 `Sim.gd`，也不要求游戏产品路线等待完整研究平台。

目标边界：

- Living Town 继续是 canonical simulation runtime；
- multi-verse bench 是独立 control plane；
- 两者以版本化 `RequestedRunSpec/ResolvedRunSpec/RunAttempt/RunBundle` 协议连接；
- 新框架关闭时必须保持具名、pinned-runtime 的 `baseline_corrected_v1`；
- 每一阶段都有独立可验收产物和 rollback 点。

## 2. 前置条件与依赖

在将研究结果视为可信 run 前，应先处理既有评审中的高风险正确性问题：

1. AI 请求持有冻结候选 stable keys、candidate hash、request id 和 world epoch；
2. timeout/cancel/restart/scrub 能真正终止或隔离旧请求；
3. player、model pick、scenario patch 等外生输入进入统一 journal；
4. 候选/事件/快照具有稳定 schema 和 content hash；
5. S0/S5 有稳定公开命令，最好进入 CI；
6. jobs 数据接线等已知机制缺陷不再污染 baseline。

这些事项不阻止先搭 workbench 的 schema/catalog 原型，但阻止把 live-model run 升级为确认性证据。

## 3. 分阶段计划

### Phase 0：保存历史证据、修复切点与契约草案

**目的**：在不改行为的前提下建立可比较基线。

Living Town 交付：

- 将审阅时的行为保存为 `baseline_legacy_evidence`，记录 commit、dirty state、content、Godot version、seed suite 和已知缺陷；
- 修复/隔离异步请求、输入 journal、jobs 等高风险正确性问题后，切出 `baseline_corrected_v1`；每项预期 drift 写入经评审的 manifest；
- 保存 S0、S5、replay 的命令、摘要、event digest 和性能基准；
- 草拟 `RequestedRunSpec v0`、`ResolvedRunSpec v0`、`RunAttempt/RunBundle v0`、`AnalysisSpec/MetricRecord v0` 词汇和 schema；
- 明确哪些输入属于 deterministic state、external input 和 narrative-only output；
- 建立 off-gate fixture：未启用 adapter/module 时逐事件/digest 对拍。

Workbench 交付：

- repo skeleton、ADR、schema package、CLI `validate-spec`；
- SQLite/DuckDB 最小 catalog；
- artifact 路径与 checksum 约定；
- CI 只做 schema、unit、lint 和 deterministic fixture，不依赖 UI。

**Gate P0**

- 同一 `baseline_corrected_v1` command 在 pinned runtime 连跑三次 `result_digest` 一致；
- schema 可以验证成功/失败样例；
- adapter 设计不要求研究台读取 Godot 内部可变对象；
- legacy/corrected baseline artifact 均有 commit/content/runtime hash 和 expected-drift relation。

### Phase 1：只读 Headless Adapter 与 RunBundle

**目的**：先把 Living Town 当黑盒执行器，不迁移现有机制。

建议协议：

```text
multi-verse bench
  → run-spec.json + isolated output directory
Godot --headless --script LabAdapter.gd -- --spec ... --out ...
  → events.jsonl + metrics.jsonl + snapshot + manifest + exit status
```

Adapter 必须：

- 只接受 canonical spec，拒绝未知字段或不兼容版本；
- 创建临时/隔离输出，成功后原子封装 bundle；
- 捕获 stdout/stderr、退出码、超时、崩溃和 incomplete 状态；
- 写出实际使用的 resolved config，而不只复制 requested config；
- 不开启 live backend，除非 spec 明确记录 external input policy；
- 对 event/metric 做 canonical ordering 与 checksum。

Workbench 同期实现：

- `run`, `inspect`, `compare`, `reproduce` 四个 CLI；
- 本地串行 executor 与并发上限；
- content-addressed RunBundle；
- 失败 run 同样入 catalog，禁止只保留成功结果。

**Gate P1**

- 从空 catalog 运行同一 spec 两次，得到相同 semantic digest；
- 任一 bundle 可由 manifest 单独重建命令；
- kill/timeout 后不会把半成品标为 complete；
- 当前 S0/S5 能作为 legacy benchmark 被导入，不改变其判定。

### Phase 2：Mechanism Trace 与只读 Research Pack

**目的**：先观察再干预。

Living Town：

- 定义 `ReadOnlyContext` 和只读 event projection；
- 引入 `ModuleManifest`、capability registry 和 freeze/validation；
- 支持 R0 `Observer/MetricProvider/InvariantProvider`；
- 输出 typed `mechanism-trace.jsonl`；
- 将修复前历史行为标记为 `baseline_legacy_evidence`，将正式 off-gate 目标标记为 `baseline_corrected_v1`，即使尚未模块化。

Workbench：

- Research Pack registry、manifest validator；
- MechanismCard、ConstructMap、ODD+D card 模板；
- trace viewer 先做静态表/报告，不急于 Web UI；
- module off-gate、RNG non-consumption 和 namespace tests。

**Gate P2**

- R0 pack 能从 event 派生 metric，但不能改变任何 world digest；
- 未声明字段访问在测试中失败；
- trace 能回答 actor view、合法候选、选择和 effect cause；
- pack 卸载后无 schema/state 残留。

### 3.1 Legacy `SimExtensions` 迁移与隔离矩阵

新 registry 不能与拥有完整 `Sim` 写权的旧 extension 永久并存而假装已经隔离。过渡规则如下：

| Legacy seam | 当前风险 | 目标 capability | 过渡 lane | 退出证据 |
|---|---|---|---|---|
| `ScenarioProvider` | 可直接修改完整状态 | versioned `ScenarioProvider` 产生受控 `ScenarioIntervention` | 仅 trusted baseline/discovery | 白名单 delta、journal、paired fixture |
| `CandidateProvider` | 可读完整状态并产生不稳定候选 | read-only context → stable `MoveToken` | shadow adapter | candidate/order/off-gate 等价 |
| `AcceptanceModifier` | 任意 score 与执行顺序 | typed `MechanismContribution` | shadow ledger 后再 active | unit/phase/bounds、paired counterfactual |
| `NightlyHook` | 调度顺序和直写旁路 | `ScheduledSystemCause` → `StateDelta` | trusted transitional lane | phase DAG、event/replay、无直写 |
| `ActionExecutor` | 最大写旁路，依赖作者自记 event | `EffectCompiler` → Kernel executor | 仅 legacy baseline；research profile 禁止 | atomic ops/invariants、mutation test、迁移后停用 |

Registry freeze 后禁止新增 legacy registration；research profile 不得调用持有完整 `Sim` 的 legacy provider。每迁移一个 seam 都先 shadow 对拍、再做 off-gate/expected-drift review，最后才删除旧入口。

### Phase 3：Bridge IR 与受限行为贡献

**目的**：引入 `SocialContext`、`MoveToken`、`MechanismContribution`、`EffectPlan`，但先不迁移复杂制度。

工作项：

- typed schema + validators；
- contribution ledger、单位/phase 检查和限幅；
- per-module keyed RNG；
- stable candidate token 与异步 backend revision/hash 校验；
- EffectPlan 只由 Kernel executor 提交；
- R1/R2 权限与 profile 开关；
- paired counterfactual harness。

选择一个低风险机制做 shadow run：新 pipeline 计算结果但不接管行为，逐 decision 与现有内建路径对拍。任何差异必须分类为 bug、预期设计变化或非确定性泄漏。

**Gate P3**

- shadow path 对选定 seed suite 逐 decision 一致；
- dormant R2 pack 不抽 RNG、不改变排序；
- 越权 EffectPlan、过期 MoveToken、未知 op 全部 fail closed；
- contribution ledger 可机器解析并重建仲裁输入。

### Phase 4：第一个纵向协议——Election GameSpec

**目的**：验证 typed protocol 可以表达已有多阶段制度。

为什么先选 election：

- 参与者、候选人、角色、公开信息和聚合规则相对明确；
- 现有 S0 已覆盖 election invariants；
- 适合验证制度规则与个人偏好的分离；
- 比 attachment/identity 更少潜变量，便于定位差异。

步骤：

1. 记录当前 election 的 phase/action/aggregation/effects；
2. 写 `ElectionGameSpec v0`，先 shadow；
3. 对拍候选资格、投票、结果、角色变更和事件；
4. 只在固定 profile/feature flag 下接管；
5. 扩展场景测试信息不对称、弃权、平票与无合法候选；
6. 对迁移前后跑 S0/S5/replay 和 digest diff。

**Gate P4**

- baseline profile 行为等价；
- 新 profile 可更换投票制度而不改 Kernel；
- 规则、NPC 知晓、合法性判断与实际执行有独立 trace；
- snapshot/replay 覆盖进行中的 election protocol state。

### Phase 5：Commitment Contract 与三机制 Pilot

**目的**：完成 workbench 的第一个科学闭环。

先把 invite/accept/meet/breach/repair 表达为 typed contract protocol：proposal → acceptance → obligation → settlement/breach → observation/repair。随后接入：

- A：commitment consequences；
- B：gossip/reputation；
- C：norm enforcement。

Workbench 实现完整 `2³` profile 枚举、paired seed blocks、positive/negative/placebo、synthetic truth recovery、冻结确认集和多轴报告。

**Gate P5**

- 满足 [`multiverse-workbench-concept.md`](multiverse-workbench-concept.md) 的 Pilot 验收；
- 能显示主效应和交互，保留完整失败/中止 run；
- A/B 不可区分时能输出 equivalence class；
- 报告的每个数字带 metric version、run set 和 analysis code hash。

### Phase 6：Institution/Norm/Role 与 Research Pack 生态

**目的**：将 jobs/rent/festival/factions 等逐个迁移为显式制度或投影。

推荐顺序：

1. role/position registry；
2. normative namespace 和 sanction procedure；
3. jobs/rent 作为 contract/market protocol；
4. festival public-goods GameSpec；
5. faction 拆为 projection/recognized identity/formal group；
6. macro-to-micro bridge registry。

每次只迁移一条纵向链，并保留 legacy profile 直到 equivalence/expected drift 被审阅。

### Phase 7：跨学科扩展

按风险等级推进：

1. social identity R0 → R1 → 小幅 R2；
2. power/dependence R0 → bargaining protocol；
3. appraisal R0/R1 → bounded action tendency；
4. attachment/psychodynamic R0/R1，默认不进入 R2；
5. 只有在独立辨别场景、参数恢复和 game value 测试后才提升权限。

## 4. 两个 repo 的职责矩阵

| 能力 | Living Town | Multi-verse Bench |
|---|---:|---:|
| 世界状态与 canonical effects | Owner | 不写 |
| 合法候选、protocol runtime | Owner | 配置/引用 |
| 模块 capability enforcement | Owner | 静态预检 |
| headless execution adapter | Owner | 调用 |
| Run identity/schema | 共同版本 | Owner |
| 组合枚举和实验设计 | 不负责 | Owner |
| artifact catalog/store | 只输出 | Owner |
| calibration/model selection | 不负责 | Owner |
| deep research/evidence ledger | 不负责 | Owner |
| 游戏 UI/叙事体验 | Owner | 仅导入研究结果 |
| 科学/产品报告 | 提供 trace | Owner |

协议版本必须由兼容矩阵管理；两边不能从相对路径隐式读取对方源码。

## 5. 工作流与分支纪律

- Living Town 的框架接入使用独立 `codex/...` 或 feature branch；每个 PR 只完成一个垂直切片。
- Workbench 使用自己的 repo/issue/ADR；submodule/monorepo 决策推迟到有真实 pack 后。
- 大型 RunBundle、论文全文、模型权重和 secrets 不进 Git。
- Golden fixtures 要小、可许可再分发、版本固定；大规模 artifacts 只存 manifest/checksum/URI。
- Schema 变更先发布兼容期和 migration，再删除旧版本。
- 研究结果不得自动修改 `game_default` profile；需要独立产品评审。

## 6. 测试矩阵

| 级别 | 必须检查 |
|---|---|
| Unit | schema、hash、排序、unit composition、permission、RNG key |
| Contract | Requested/Resolved spec、Attempt/Bundle compatibility、invalid inputs、timeout/partial bundle |
| Golden | baseline digest、candidate token、EffectPlan commit、trace |
| Mechanism | positive/negative/placebo、mediator、latency、dose-response |
| Counterfactual | paired seed、single intervention、off-gate |
| Recovery | synthetic parameter/structure truth |
| Statistical | multiple comparison、uncertainty、sensitivity、identifiability |
| Migration | snapshot/profile/pack schema upgrade and rollback |
| Product | game_default performance、explanation、player agency |

任何确认性报告都要显示：运行总数、失败/排除数、排除原因、seed policy、版本 hashes、预声明指标与事后探索指标。

## 7. 建议的首批 backlog

### Living Town

1. ADR：Kernel-only world writes 与六 namespace。
2. 定义 Requested/Resolved spec、attempt/result/bundle/analysis identity 与 canonical JSON/hash。
3. 统一外生 input journal 与 AI request epoch/token。
4. 只读 `LabAdapter.gd` 与 RunBundle writer。
5. R0 registry/manifest validator。
6. mechanism trace schema。
7. `baseline_legacy_evidence`、`baseline_corrected_v1` 与 expected-drift suite。
8. Election shadow GameSpec spike。

### Workbench

1. repo scaffold、license/security/contribution policy。
2. artifact schemas + JSON Schema fixtures。
3. local executor + catalog + content addressing。
4. CLI validate/run/inspect/reproduce/compare。
5. factorial profile enumerator + paired seed planner。
6. static report with failures and provenance。
7. MechanismCard/ConstructMap/ODD+D templates。
8. sealed split and benchmark access policy。

## 8. 时间盒建议

以下是顺序和风险控制，不是未经团队估算的承诺：

- **Spike A（数日）**：Requested/Resolved spec、Attempt/Bundle schema 与手工 adapter proof；
- **Internal Alpha（约 1–2 个迭代的待估范围）**：稳定 black-box runner/catalog/reproduce；
- **Spike B**：R0 observer + trace + off-gate；
- **Credible Pilot entry**：Bridge IR shadow path + election 对拍；
- **Pilot**：commitment/reputation/norm 三机制实验；
- **扩展期**：制度和跨学科 packs，按证据晋级。

若 Phase 1 的 black-box reproducibility 尚未稳定，不进入自动组合搜索；若 Phase 3 off-gate 失败，不允许任何 R2 模块进入确认性实验。

## 9. 完成定义

路线完成不以“文档、类和 UI 数量”判断，而以以下能力判断：

- 一个新研究 claim 能走完 source → mapping → pack → profile → experiment → run → evidence；
- 不改 Kernel 即可比较至少两个竞争 mechanism profiles；
- 任一 run 可按 manifest 重现并解释差异；
- calibration、selection、confirmation 的 artifact 和访问策略可审计；
- 研究 profile 与 game_default 解耦；
- 系统能诚实报告失败、不可识别、适用边界和待区分实验。
