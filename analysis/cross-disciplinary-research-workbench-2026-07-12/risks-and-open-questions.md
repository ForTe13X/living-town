# 风险、效度威胁与开放问题

## 1. 总体判断

最大的风险不是“模拟不够复杂”，而是复杂度增长后产生一种不可审计的科学外观：理论名称很多、运行次数很大、图表很漂亮，但构念映射、机制实现、数据分割和结论边界并不可靠。风险治理必须从 artifact/schema/权限开始，而不是报告阶段补一句免责声明。

## 2. 核心风险登记

| ID | 风险 | 影响 | 早期信号 | 缓解/回退 |
|---|---|---|---|---|
| R-01 | Theory soup：不同单位和语义直接加权 | 机制不可解释、参数无意义 | 出现万能 `score`/任意权重 | typed contribution；单位/phase 检查；alternative profiles |
| R-02 | 同名构念误映射 | 论文与实现看似一致、实则不同 | `trust` 等按字段名自动对齐 | ConstructMap、measurement model、领域 review |
| R-03 | 潜变量被当成事实 | 叙事固化偏见，污染行为 | LLM 输出写回 trait/world | 六 namespace、Kernel-only write、R0/R1 限权 |
| R-04 | 宏观投影循环论证 | 模型用自身输出解释自身 | polarization 直接乘行为分 | 显式 downward bridge、滞后、intervention test |
| R-05 | 组合爆炸 | 成本失控、只跑喜欢的组合 | 无 budget/stop rule | 约束图、筛选设计、保留 skipped cells |
| R-06 | Benchmark 泄漏 | 确认结果虚高 | 调参者可查看 confirm 输出 | sealed split、访问日志、用后降级 |
| R-07 | 多重比较/p-hacking | 偶然效果被宣布机制 | 大量 metric 只报告显著者 | 预注册、完整指标、校正/层级模型 |
| R-08 | Equifinality/不可识别 | 不同机制生成同一模式 | 多模型拟合同一终点 | 多 pattern、机制 trace、区分实验、equivalence class |
| R-09 | 参数吸收缺失机制 | 校准好但外推失败 | 参数极端/跨场景漂移 | posterior predictive/OOD、替代结构比较 |
| R-10 | 非确定性泄漏 | 无法 paired comparison | run digest 偶发变化 | keyed RNG、排序、量化、外生 input journal |
| R-11 | 模块调用顺序效应 | 注册顺序决定社会结果 | 相同 pack 不同加载序不同 | registry freeze、phase/order contract、order permutation test |
| R-12 | 迟到 AI 回包污染 | 运行被其他请求改变 | callback 只按 agent id | request id/epoch/token/cancel；确认 run 禁 live AI |
| R-13 | Replay 不完整 | artifact 无法重建 | 玩家/LLM 输入缺失 | authoritative input journal + snapshot/hash |
| R-14 | Schema/version 漂移 | 旧 run 被错误比较 | silent default/missing field | semver、migration、fail closed、compat matrix |
| R-15 | Artifact provenance 断链 | 结论无法审计 | 报告只有 CSV/截图 | content addressing、PROV graph、checksum |
| R-16 | 幸存者偏差 | 只保留成功/漂亮 run | failed run 不入 catalog | 所有计划 cell 与失败状态入账 |
| R-17 | Simulation = reality 过度主张 | 科学信誉与伦理风险 | “证明社会规律”措辞 | 分层 evidence status、外部验证、声明适用域 |
| R-18 | 精神分析/心理标签伤害 | 刻板化或类似诊断 | 永久 trait、无证据内心真相 | hypothesis + `hypothesis_uncertainty` + decay；禁止诊断；R0/R1 default |
| R-19 | 隐私/敏感数据 | 合规和再识别风险 | 原始人类数据进 bundle | 数据分级、最小化、脱敏、访问控制、DPIA |
| R-20 | 版权/许可证污染 | repo 无法公开或发布 | 论文全文/数据/权重入 Git | source metadata 与内容分开、license gate |
| R-21 | 双用途/操控优化 | 研究台用于优化有害社会干预 | 目标函数含操控/极化 | use-policy、风险 review、禁止场景、审计日志 |
| R-22 | 游戏价值与科研指标混淆 | 两边都做不好 | 一个总分决定 game_default | 独立轴/Pareto；单独产品评审 |
| R-23 | 过早平台化 | 架构成本大于已知需求 | UI/微服务先于一个 pilot | CLI-first、三机制 vertical slice、删除无使用抽象 |
| R-24 | 维护者认知负担 | Pack 无人理解、结果不可复核 | manifest/trace 无 owner | owner/reviewer、模板、弃用策略、最小接口 |

## 3. 科学效度威胁

### 3.1 构念效度

NPC 字段只是 operationalization，不是现实构念本身。每个结论必须附：来源定义、模拟 proxy、无法表达的部分、适用人群/场景和独立 rubric 下的 `mapping_confidence`。它不能与 `extraction_confidence`、经验测量误差、posterior probability 或 reviewer judgment 混用。

### 3.2 内部效度

即使 paired seed 出现差异，也要确认唯一变化是目标 intervention；模块依赖、RNG 调用、候选排序、metric 版本和失败重试都可能成为混杂。Run manifest 应记录 resolved dependency graph 和实际执行路径。

### 3.3 统计结论效度

Agent/run 数量大不意味着独立样本多。seed、场景、网络和同一世界内事件具有层级相关性；报告必须说明分析单位，避免把每个 NPC-tick 当独立 observation。

### 3.4 外部效度

Living Town 是小镇型、游戏化、有限行动空间的模型。跨人口规模、网络拓扑、资源稀缺、制度和时间尺度的 OOD 结果应单独报告；通过内部 bench 不能自动外推到现实社会政策。

### 3.5 机制可识别性

同一宏观合作率可能来自互惠、惩罚、选择性退出或网络重连。必须预声明中介轨迹和时间 signature，而不是只看终点。不可识别时保留模型集合。

### 3.6 实现效度

“理论不工作”也可能是 adapter、schema 或 pack bug。先做 synthetic truth/parameter recovery、positive/negative controls，再解释模型比较。

## 4. 伦理与表达边界

### 4.1 人类研究与真实数据

一旦引入访谈、问卷、行为日志或玩家 telemetry，应独立评估同意、用途限制、数据保留、撤回、未成年人、跨境和再识别风险。该平台设计本身不构成人类研究伦理审批。

### 4.2 心理与精神分析模块

- 只允许“模型在给定证据下的竞争性假设”，不允许角色或真人的本质判断；
- hypothesis 有 evidence、counterevidence、具名 `hypothesis_uncertainty`、decay 和 validity scope；LLM 自报 confidence 不得自动影响机制权重；
- LLM 生成的解释必须标注为 narrative/interpretation；
- 不使用临床诊断名称作为未经验证的 gameplay trait；
- 如接入真实用户数据，默认禁止此类推断，除非经过专门伦理/法律评审。

### 4.3 社会干预与双用途

研究群体极化、规范制裁、影响网络或脆弱性时，要审查结果是否能直接转化为操控、歧视或针对性压迫优化。Workbench 应能限制 pack/scenario 的导出和运行权限，而非默认全部公开。

## 5. 技术开放问题与建议默认值

| 问题 | 建议默认值 | 何时重新决策 |
|---|---|---|
| 独立 repo 还是 monorepo | 独立 `multi-verse-bench` repo | 有多个共版本 pack 且发布成本明显过高 |
| Pack 放在哪里 | 首版放 workbench 内 `packs/`，接口稳定后再拆 | 至少两个独立维护团队出现 |
| Catalog | SQLite 或 DuckDB 单机 | 并发写入/远程团队成为真实瓶颈 |
| Artifact store | 本地 content-addressed 目录 + 可配置 URI | 大规模远程 executor 上线 |
| Orchestrator | Python CLI | 需要浏览器协作 UI 或长期服务 |
| 配置格式 | canonical JSON 作执行真相，YAML 只作 authoring | schema/round-trip 经验表明需调整 |
| IPC | 文件协议 + process exit | 单 run 启动开销成为测得瓶颈 |
| 远程执行 | 不进 MVP | 本地 pilot 稳定且有明确预算 |
| Graph database | 不进 MVP；关系表/JSON 足够 | provenance 查询确实无法维护 |
| 浮点策略 | 贡献量化并记录 rounding | 精度损失被 benchmark 证实不可接受 |
| Research Pack 语言 | runtime-facing 能力先用 GDScript；分析用 Python | 安全沙箱或跨语言性能有实际需求 |
| LLM in confirmation | 默认禁用；只回放冻结 pick/input | 专门研究 LLM 且能固定模型/输出 |
| 总体排名 | 不提供；输出 Pareto/适用域 | 永不默认，产品可另定义局部 utility |
| 自动晋级模块 | 禁止 | 保持人类签署 gate |

## 6. 尚需团队回答的产品问题

1. Workbench 的第一用户是项目维护者、外部研究者，还是游戏设计者？优先级决定 UX 与治理。
2. 预期发布形态是开源工具、内部研究平台、论文 companion artifact，还是商业设计工具？
3. 哪些数据和 Research Packs 可以公开？是否允许不可再分发数据只保存派生指标？
4. game_default 是否允许由 research profile 自动建议，还是只能人工采纳？建议只能人工采纳。
5. 对“现实有效”的最低证据门槛是什么？项目内部 confirmation 应避免使用这一措辞。
6. 计算预算和最大实验墙钟时间是多少？没有预算无法选择组合设计。
7. 目标支持 Windows only 还是跨平台 headless？这影响 runner/container 和 artifact path。
8. 是否需要多人签署 claim/pack/experiment？MVP 可单 reviewer，但 schema 应保留 reviewer list。
9. 研究台是否支持 private packs/secrets？若支持，artifact sharing 和 cache key 需要隔离。
10. 长期是否允许用户上传任意代码 pack？若允许，需要进程隔离、资源限制和供应链安全；MVP 应拒绝不可信代码。

## 7. 审计清单

### Research ingestion

- [ ] 引用指向原始/权威来源，版本和 retrieval date 明确。
- [ ] 每个 causal claim 与描述性/相关 claim 区分。
- [ ] 构念定义、measurement 和 Living Town proxy 显式记录。
- [ ] 替代理论、反例、适用边界和不确定性没有被遗漏。
- [ ] 自动提取结果经过具名 reviewer。

### Mechanism implementation

- [ ] ModuleManifest 完整，权限与实际访问一致。
- [ ] positive/negative/placebo 和 synthetic truth 测试存在。
- [ ] off-gate 与 dormant RNG gate 通过。
- [ ] EffectPlan 由 Kernel 校验和提交。
- [ ] trace 包含 module/version/config/cause/evidence。
- [ ] snapshot/replay/migration 覆盖模块状态。

### Experiment design

- [ ] question、hypothesis、metric、sample/budget 和 stopping rule 预先冻结。
- [ ] `D_dev/D_cal/D_select/D_confirm/D_ood` 无泄漏。
- [ ] paired seed 与唯一 intervention 差异可证明。
- [ ] 所有计划 cell、失败、中止和排除原因入账。
- [ ] 多重比较、层级依赖和不确定性处理明确。
- [ ] equivalence/inconclusive 是允许的结果。

### Reporting

- [ ] 报告区分 implementation verification、simulation evidence 和 external validation。
- [ ] 结论措辞不超过证据状态与适用域。
- [ ] 不用单一分数掩盖科学、工程、游戏和成本权衡。
- [ ] 每张表/图可回溯到 run set、analysis code 和 metric version。
- [ ] 失败 run 和结果变化没有被静默过滤。
- [ ] psychodynamic/identity 等敏感解释不被陈述为事实或诊断。

### Security/IP

- [ ] secrets、真实个人数据、受限全文、模型权重不进入 Git/公开 bundle。
- [ ] source/data/code/model 的许可证分别记录。
- [ ] 不可信 pack 不在宿主进程任意执行。
- [ ] artifact 有 checksum、访问策略和删除/保留规则。

## 8. 暂停/停止条件

满足任一条件时应停止扩大模型空间，先修基础：

- baseline/off-gate 在同环境仍不稳定；
- run 无法从 manifest 重现，或失败 artifact 被覆盖；
- confirmation split 已泄漏但报告仍把它当确认结果；
- construct mapping 没有 reviewer，却进入 R2+；
- 多个 pack 通过共享可变 state 或加载顺序隐式耦合；
- 搜索预算、停止规则或失败策略缺失；
- 报告把 simulation behavior 写成现实人群事实；
- 敏感数据、版权或双用途问题没有 owner；
- 平台工程连续扩张但第一个三机制 pilot 仍未完成。
