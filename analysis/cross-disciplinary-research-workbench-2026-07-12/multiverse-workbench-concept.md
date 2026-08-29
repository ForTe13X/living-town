# Mechanism Multiverse Workbench：跨学科沙盒研究台

## 1. 产品定位

Mechanism Multiverse Workbench（暂名）是 Living Town 之外的研究控制平面。它复用 Living Town 的 deterministic/headless 能力，但不把论文管理、组合搜索、大规模 artifact 和统计分析塞进 Godot 游戏仓库。

核心问题不是“怎样运行一次模拟”，而是：

1. 某篇研究究竟提出了什么原子 claim？
2. claim 如何映射为可执行机制，映射损失是什么？
3. 哪些机制可以组合、冲突或互为替代理论？
4. 在有限预算下，哪些实验最能区分这些模型？
5. 哪些参数用于校准，哪些场景用于选择，哪些数据被封存用于确认？
6. 结论能否从报告追溯到 source、claim、pack、profile、run 和 event？

因此它更接近一个 **Theory-to-Experiment Compiler + Experiment Operating System**，而不是一个新的游戏 UI。

## 2. 主要用户与用例

| 用户 | 主要任务 |
|---|---|
| 模型开发者 | 把理论构念映射为 pack/bridge，编写机制与验证场景 |
| 领域研究者 | 审核 claim、适用边界、proxy 和可证伪预测 |
| 实验工程师 | 设计组合、干预、seed、预算、停止规则和运行队列 |
| 分析者 | 做敏感性、参数恢复、模型比较、equivalence analysis |
| 游戏设计者 | 比较社会可读性、叙事性、可玩性与性能，而非替代科学指标 |
| 审计者 | 检查 provenance、benchmark 泄漏、版本、许可证和结论措辞 |

首版优先 CLI + machine-readable artifacts + 静态报告，不以图形化拖拽建模为前置条件。

## 3. 端到端闭环

```mermaid
flowchart LR
    A["Source Discovery"] --> B["Source Record"]
    B --> C["Atomic Claims"]
    C --> D["Construct Map"]
    D --> E["Mechanism Card"]
    E --> F["Research Pack"]
    F --> G["Composition Graph"]
    G --> H["ExperimentSpec"]
    H --> I["Locked Run Plan"]
    I --> J["Living Town Headless Runner"]
    J --> K["Immutable Run Bundles"]
    K --> L["Benchmark and Analysis"]
    L --> M["Evidence Records"]
    M --> N["Next Discriminating Experiment"]
    N --> H
```

每个箭头都应是显式 artifact 和 review checkpoint；禁止“LLM 读完论文直接生成启用中的模型代码”。

## 4. 核心 artifacts

### 4.1 `SourceRecord`

```yaml
source_id: doi:...
title: ...
authors: []
publication_date: ...
source_type: paper
retrieved_at: ...
content_hash: ...
license_and_access: ...
review_status: unreviewed
```

网页内容、引用元数据和提取文本分开保存；摘要或二手文章不能静默冒充原始证据。

### 4.2 `AtomicClaim`

```yaml
claim_id: claim.norm.001
statement: ...
claim_type: causal        # descriptive | causal | measurement | boundary
population: ...
context: ...
intervention_or_exposure: ...
outcome: ...
time_horizon: ...
evidence_locator: ...
extractor: human_or_model
review_status: proposed
extraction_confidence: ...   # 仅表示抽取可靠度，不是经验效应或理论可信度
```

一个段落可能包含多个 claim；一个 claim 也可能被多篇研究支持、限制或反驳。不要把 “paper” 当成不可分割证据单位。

### 4.3 `ConstructMap`

它记录论文构念到模拟对象的映射：

```text
source construct
→ operational definition in source
→ Living Town observable/proxy
→ transformation/measurement model
→ lost information
→ scope and assumptions
→ `mapping_confidence`（使用独立 rubric，不与 extraction/posterior 混用）
```

例如论文中的 `trust` 不能因为字段同名就自动映射到 `relationship.trust`。必须说明它是行为测量、问卷潜变量、预期概率还是规范性判断。

### 4.4 `MechanismCard`

```yaml
id: soc.injunctive_norm
sources: []
constructs: []
causal_graph: []
scope_conditions: []
observable_proxies: []
predicted_signatures: []
alternative_explanations: []
falsification_tests: []
known_limitations: []
mapping_review_status: tentative
```

### 4.5 `ResearchPack`

可执行实现 + manifest + schema + parameters + scenarios + metrics + invariants + ODD+D card + references。Pack 是版本化研究软件，不等同于理论本身。

### 4.6 `ModelProfile`

```yaml
profile_schema: 1
modules:
  - id: commitment
    version: 2.0.0
  - id: reputation
    version: 1.3.0
bridges:
  - id: public_observation
    version: 1.0.0
parameters: {}
kernel_compatibility: ...
profile_hash: ...
```

`ModelProfile` 是可编辑的组合意图，不是执行锁。Resolver 必须把它解析成不可变 `CompositionLock`；后者记录精确 pack/bridge/source hashes、resolved parameters、arbitration、runtime compatibility 和 canonical lock hash。正式实验只能引用 `CompositionLock`，不能隐式解析 `latest`。

### 4.7 `ExperimentSpec`

```yaml
question: ...
pre_registered_hypotheses: []
baseline_profile: ...
variant_space: ...
scenarios: []
interventions: []
seed_policy: paired
sample_size_or_budget: ...
metrics: []
estimand_spec:
  experimental_unit: scenario_seed_block
  treatment_and_comparator: ...
  outcome_and_metric_version: ...
  target_distribution: ...
  time_window: ...
  contrast_and_weights: ...
  interference_or_exposure_rule: ...
  missing_and_failure_policy: ...
  multiplicity_family: ...
analysis_plan: ...
data_split_policy: ...
stopping_rule: ...
failure_policy: ...
```

### 4.8 Run identity 与 `RunBundle`

模拟请求、执行尝试、因果输出、完整 artifact 和事后分析必须使用不同 identity：

```text
RequestedRunSpec       # 用户/Experiment Planner 的请求
ResolvedRunSpec        # defaults、依赖、版本和配置解析后的 canonical 输入
run_id                 = H(ResolvedRunSpec 的语义字段)
RunAttempt             # 每次 executor 启动、runtime/environment、时间与退出事实
attempt_id             # 唯一执行实例，关联 run_id
result_digest          = H(canonical simulator causal outputs)
RunBundle              # 某 attempt 产生的不可变 artifact 集
bundle_content_id      = H(finalized bundle index + protected file digests)
AnalysisSpec           # metric、estimand、代码/query、输入 bundle set
analysis_id            = H(AnalysisSpec + input bundle IDs)
```

同一 `ResolvedRunSpec` 的重复运行应具有相同 `run_id`；在相同 pinned runtime 中，确定性契约要求 `result_digest` 相同。不同 attempt 的日志、时间和资源使用天然不同，因此不要求 `bundle_content_id` 相同。指标重算产生新的 `analysis_id`，不能改变 simulation `run_id`。

每次运行是不可变目录或对象：

```text
run-manifest.json
inputs.jsonl
events.jsonl
mechanism-trace.jsonl
native-metrics.jsonl     # 仅限 ResolvedRunSpec 中声明的 engine-native observations
final-snapshot
checksums.json
stdout.log / stderr.log
```

事后 `MetricSpec`、统计查询和图表属于独立 Analysis Artifact，引用一个或多个 `bundle_content_id`；修改它们只生成新的 `analysis_id`，不重命名原 simulation run。

### 4.9 `EvidenceRecord`

`EvidenceRecord` 是相对具名 claim/estimand/scope 的 append-only assertion，不使用会互相覆盖的单一状态枚举：

```text
claim_or_hypothesis_id
analysis_id
scope_and_domain
implementation_status
calibration_status
effect_assessment
identifiability_assessment
external_validity_status
evidence_level
equivalence_class_membership
review_status
reviewer + timestamp + supersedes
```

同一机制可以同时是“实现已验证、已校准、与 B 在当前观测下不可区分、在某外部域被反驳”。支持/反驳必须绑定版本、estimand 和适用域；`equivalence class` 是模型间关系，不是 pack 的永久标签。

建议以图谱方式连接 Entity/Activity/Agent，可参考 [W3C PROV-O](https://www.w3.org/TR/prov-o/)，但首版可先用关系表实现，无需立即部署 graph database。

## 5. Deep Research ingestion

### 5.1 自动化可以做什么

- 基于预先登记的检索式发现候选原始研究、数据和 replication；
- 去重 DOI/版本，建立 citation graph；
- 从全文提出 atomic claims、scope conditions、measurements 和争议点；
- 对齐相似构念，提示同名异义和异名同义；
- 草拟 MechanismCard、ODD+D、测试场景和替代理论；
- 检查引用是否真的支持报告中的措辞；
- 持续监控新研究并提出“需要重新审核”的影响范围。

### 5.2 自动化不能拥有的权限

- 不能把 correlation 自动标记为 causal；
- 不能替领域审阅者接受 claim 或 construct mapping；
- 不能把作者的解释等同于已识别机制；
- 不能在没有 review 的情况下激活 R2+ 模块；
- 不能用 simulation fit 反向宣布现实理论已证实；
- 不能把受版权限制的全文未经许可打包进公开 artifact。

### 5.3 建议的 ingestion gate

```text
G0 source identity/provenance
G1 claim extraction review
G2 construct/measurement mapping review
G3 mechanism and alternatives review
G4 implementation and unit verification
G5 experiment pre-registration/freeze
```

每一 gate 留下 reviewer、timestamp、版本、decision 和 unresolved objections；模型输出只是候选，不是 reviewer 身份。

## 6. 组合空间：登记全部，选择性执行

不确定性至少分五层：

1. **结构**：启用哪些机制/bridge；
2. **参数**：机制参数范围与 prior；
3. **随机**：seed；
4. **场景**：人口、网络、资源、制度和冲击；
5. **观测**：proxy、measurement noise 和 metric 定义。

Composition Graph 记录：

```text
requires(A, B)
conflicts(A, C)
alternative(A, D)
compose_on_edge(A, E, rule)
valid_only_if(A, scope)
```

系统应给每个可能 cell 一个状态，即便没有执行：

```text
eligible | invalid_by_constraint | queued | running | complete |
failed | cancelled | skipped_by_budget | dominated | archived
```

### 6.1 执行策略

| 阶段 | 建议方法 | 目的 |
|---|---|---|
| 基线 | baseline、single-add、leave-one-out | 检查单机制与必要性 |
| 离散交互筛选 | pairwise、fractional factorial、covering design | 避免全组合爆炸 |
| 连续参数筛选 | Latin hypercube、Morris | 找重要参数与非线性 |
| 全局敏感性 | Sobol first/total order | 分解主效应和交互 |
| 昂贵校准 | ABC/SBI/Bayesian optimization | 估计 posterior/可行区域 |
| 多样解搜索 | Pareto、MAP-Elites | 保存不同机制风格而非单一赢家 |
| 最终确认 | sealed scenarios + fresh seeds | 防止搜索泄漏 |

原则：**enumerate the hypothesis space; selectively execute the informative cells**。搜索算法必须记录为何没有运行某个 cell，防止 survivor bias。

## 7. 调试、校准、选择、确认隔离

```text
D_dev      实现调试、指标开发、探索性可视化
D_cal      固定结构后的参数校准
D_select   比较机制结构和 profile
D_confirm  冻结的确认性 benchmark
D_ood      未见人口、网络、制度、冲击和时间尺度
```

动作词必须准确：

- `verify`：实现是否忠实执行机制和 invariants；
- `calibrate`：固定结构后估计参数；
- `select`：在多个结构之间比较；
- `train/fine-tune`：训练策略、ranker 或语言模型；
- `validate`：相对外部数据/现实 pattern 的适用程度；
- `confirm`：在未暴露的冻结 benchmark 上重复预声明结论。

一旦通过结果查看、prompt engineering、metric 调整或参数搜索使用过 `D_confirm`，它就自动降级为开发数据；必须建立新的确认集。Fine-tuning 绝不能接触 sealed confirmation artifacts。

## 8. Benchmark 与分析

不要生成一个总排行榜。至少并列五条轴：

| 轴 | 指标示例 |
|---|---|
| Engineering | determinism、replay drift、invariant、runtime、memory |
| Mechanism | 触发率、中介链、方向、延迟、dose-response、placebo |
| Emergence | micro/dyad/network/institution/macro patterns |
| External | calibration、held-out prediction、跨情境复现 |
| Game value | 可理解性、故事差异、玩家 agency、性能与干扰 |

输出 Pareto front 和适用域，不把真实性、趣味性和算力成本任意线性相加。

### 8.1 Mechanism Trace

关键决策必须可回答：

```text
当时 actor 能知道什么？
有哪些合法 move？
每个机制贡献了什么、单位是什么？
哪条 norm/role/game phase 生效？
为何仲裁出该行动？
提交了哪些 EffectPlan op？
谁观察到结果并如何学习？
哪些后续事件支持或反驳预测？
```

Trace 既是 debug 工具，也是 mechanism recovery、edge ablation 和替代理论区分的基础；它不能只是一段不可解析的自然语言。

### 8.2 不可识别是有效结果

若 A/B 在现有场景和指标下不可区分，输出：

```text
equivalence_class: [A, B]
evidence: current experiments
next_experiment: maximizes predicted divergence
```

禁止因为产品需要排名就虚构显著差异。Workbench 可以用 expected information gain 或简化启发式推荐下一个区分实验，但推荐仍需人类冻结 ExperimentSpec。

## 9. 建议系统边界

```text
living-town/             Godot 游戏、确定性 Kernel、headless adapter
multi-verse-bench/       研究控制平面、catalog、planner、runner、analysis
research-packs/          可独立版本化或由 workbench 管理的 packs
artifact-store/          大型运行结果，不进入普通 Git 历史
```

最小技术组合：

```text
Python CLI/orchestrator
  → RequestedRunSpec → canonical ResolvedRunSpec
Godot headless Living Town adapter
  → JSONL events/traces + Parquet metrics
SQLite or DuckDB catalog
  → notebook/static HTML or Markdown report
```

首版不需要消息队列、Kubernetes、图数据库、微服务或复杂 Web UI。Local runner 能稳定地产生可重复 bundle 后，再抽象 executor 支持多机/云端。

## 10. 最小可信 Pilot

### 10.1 研究问题

公开违约是否通过第三方声誉与规范制裁，提高后续守约率？

### 10.2 三个二元机制

- A：commitment consequences；
- B：gossip/reputation；
- C：norm enforcement。

运行完整 `2³ = 8` 结构组合，保持相同场景与 paired seed block。不要在 pilot 阶段引入 identity、attachment 或 LLM choice，以减少替代解释。

### 10.3 场景与控制

- positive：违约被第三方看见，存在未来重复互动；
- negative：没有违约；
- placebo：发生不相关公开事件；
- observability intervention：相同行为公开 vs 私密；
- enforcement intervention：制裁规则存在 vs 不存在；
- synthetic truth：人为指定生成机制，用于测试 recovery，而非现实结论。

### 10.4 指标

- micro：未来守约/修复概率、决策 contribution；
- dyad：信任、义务、退出和修复轨迹；
- network：消息传播、第三方关系更新、桥接结构；
- macro：长期合作率、制裁频率、系统稳定性；
- engineering：digest、trace completeness、runtime。

### 10.5 Pilot 验收

- 8 个 profile 都能 content-address、运行、重放和比较；
- 同一 paired seed 的唯一结构差异来自 A/B/C 开关；
- 每个对比在解封前锁定 `EstimandSpec`：实验单位、目标分布、时间窗、contrast/weights、network interference/exposure、缺失/失败和多重比较规则；
- negative/placebo 不错误产生目标 causal signature；
- synthetic truth recovery 在预声明容差内；
- 报告显示主效应、交互、置信区间/分布及失败 run，不只显示平均数；
- `D_confirm` 在分析计划冻结前不可见；
- 结论可追溯到 claim → pack → profile → experiment → run → trace/metric。

## 11. Workbench 非目标

- 自动生产“社会科学真理”或 universal theory score；
- 用 agent 数量和运行次数替代外部效度；
- 自动发表、自动接受引用或自动给人类贴心理标签；
- 首版进行自由文本 agent-to-agent LLM 社会模拟；
- 把所有原始论文、模型权重和运行结果提交进 Git；
- 在没有成本、停止规则和失败策略的情况下无限搜索组合；
- 为了 dashboard 牺牲 provenance 和命令行可重现性。

## 12. 长期能力（不属于 MVP）

- 主动学习/贝叶斯实验设计，推荐信息量最大的下一批实验；
- 多 fidelity runner，以近似模型筛选、canonical kernel 确认；
- simulation-based inference 与 posterior predictive checks；
- MAP-Elites 保存“平等 × 合作 × 冲突”等行为区域的多种代表模型；
- 可审阅的自动 literature monitoring 与 claim impact analysis；
- 团队签名、artifact attestation、远程 executor 和预算治理；
- 游戏 A/B 与研究指标联结，但始终保持两类结论分离。
