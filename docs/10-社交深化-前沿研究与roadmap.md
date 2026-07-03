# 10 · 社交深化 · 前沿研究与 roadmap（2026-06-27）

> 来源：一次 6 路并行前沿检索（意见动力学 / 谣言传播 / 合作博弈 / 联盟·机制设计 / LLM 社会模拟架构 / 评测），优先 arXiv（2021–2026），每条机制都按本项目三约束筛过：**确定性引擎为底、6–10 NPC 准实时、必须无模型也能跑**。本文是工程落地导向的取舍 + 分阶段 path + 论证 + 引用。读者具 MAS（consensus / 博弈论）背景，故技术性强。
>
> 现状对接：已实现 SocialTransaction(发起→评估→提交→双方+旁观者视角记忆)、关系账本(affinity/trust/resentment/familiarity + event-id 溯源)、belief/知识边界、承诺系统、冲突生命周期、记忆流、event-sourced 确定性回放(`Sim.goto_tick`)。计划：SocialTransaction 字段化、Topic 对象、类型化反思、扩到 ~15 动作。

---

## 0. 横切原则（贯穿所有取舍，先记牢）

1. **决策确定、表达交给 LLM**：四套架构（PIANO/Concordia/Stanford/AgentSociety）凡把 LLM 放进"决定发生什么"的地方，本项目都保持确定性；LLM 只渲染已提交事务的台词。这天然消除 say-do 不一致。
2. **私有声誉不收敛**：本项目每个 NPC 私有记忆 → 声誉天生分歧。这对戏剧是好事，但**任何硬不变量（任务门、accept/reject）绝不能读"全局声誉"**——它不存在。
3. **概率 → 确定性阈值**：文献里每个 `P(spread)`/转移概率都是回放杀手。一律换成"对账本状态的确定性阈值"；要表观随机就用**种子化 per-event hash**，绝不 live RNG。
4. **小 N 只偷微规则**：6–10 体下，影响力最大化、R0/相变调参、幂律拟合、Shapley/core、hedonic 均衡求解、谣言源检测——全是大 N 渐近 artifact，**跳过**。偷 per-edge 更新规则，别偷宏观现象学。
5. **宽松 + 宽恕**：小 N 噪声会级联成永久世仇。范式选**宽松**的（L3 Simple Standing 而非 Stern Judging L6），并保留宽恕路径（GTFT、trust 滞回）。

---

## A. 意见 × 声誉 × 八卦：合成为一个子系统（最高杠杆）

三块研究在此交汇——这是**先做、杠杆最大**的一坨。把"八卦"从通知系统升级成**社会后果引擎**。

### A1. `standing` + 二阶范式 L3（声誉核）— ADOPT
- **机制**：indirect reciprocity 的二阶范式=对 `{动作}×{对象声誉}` 的 1-bit 查表。**Simple Standing (L3)**：help-good→good、defect-good→bad、**defect-bad→good(正当惩罚)**、help-bad→good。比 image scoring(一阶)强在能区分"正当防卫"与"无故攻击"。引用：leading-eight 在噪声/私有下的稳定性 arXiv:2310.12581 (PNAS 2023)；范式表抽象 arXiv:2408.04549；收敛性 arXiv:2404.10121。
- **落地**：给每个 (观察者→目标) 加 `standing`(good/neutral/bad，或从账本阈值化)。SocialTransaction 提交 / 承诺结算时，旁观者按 L3 表更新（你已有旁观者视角写入）。这把"爽约→resentment"升级为**声誉可读**的边（"X 是出了名的鸽子" vs "X 只鸽该鸽的人"）。
- **陷阱**：**别用 Stern Judging (L6)**——私有/噪声下它是最差范式（arXiv:2404.10121），会放大分歧级联。

### A2. gossip = 声誉传播 + 意见同步（τ 旋钮）— ADOPT（keystone）
- **机制**：leading-eight 的稳定性证明假设**公共**声誉；私有下大多失效（arXiv:2310.12581）。修复=把 gossip 做成显式可调的同步器。gossip 时长参数 **τ** 从 τ=0(纯私有，合作不稳)单调插值到 τ→∞(公共，L3 稳定)；**宽松范式在更低 τ 即恢复合作**(L3≈0.98 vs L6≈0.5)。引用：arXiv:2409.05551 (Murase & Hilbe, PNAS 2024)；最小 gossip 量 + "单一八卦源≈随机两两"等价 arXiv:2312.10821 (Plotkin, PNAS 2024)。
- **落地**：把已有 talk/claim 传播升级为一等**声誉同步步**——交谈后交换对第三方的 standing token、向一致靠拢（信任源采纳 / 近期多数）。**τ=gossip 率**当设计旋钮：低=多戏剧/小圈子/积怨持久，高=紧密小镇共识。"单一源等价"意味着可用一个**八卦中枢**（公告板 / 一个长舌 NPC）廉价拿到同样共识数学——完美适配 6–10 体。
- **验证背书**：gossip 驱动的 indirect reciprocity 在 **4–10 体**(你的尺度)即达 ~100% 合作并**放逐惯犯**；无 gossip 则崩到 ~0%（arXiv:2602.07777 ALIGN, 2025；arXiv:2412.10270 Donor Game）。
- **陷阱**：合作结论**要求诚实 gossip**；一旦引入说谎 NPC，一阶声誉崩（需二阶评估）。先做诚实确定性 gossip，撒谎当后期显式 trait + 门控。

### A3. 谣言"变冷"：Maki-Thompson 抑制规则 — ADOPT
- **机制**：每 (NPC,claim) 三态 ignorant/spreader/stifler。spreader 遇已知者→发起方转 stifler（Maki-Thompson 比 Daley-Kendall 更省）。谣言因**饱和**而非遗忘停止传播。引用：arXiv:2507.07914、arXiv:2508.07099 (2025)。
- **落地**：在 belief 存储上加 `spread_state`。Gossip 事务：spreader→ignorant 则对方学到并转 spreader；双方已知则发起方(=事务 proposer)转 stifler。免费得到"新八卦涟漪扩散→变common knowledge后没人再提"的生活质感，零 RNG。
- **陷阱**：经典结论~20% 永不听说；N=8 方差巨大（可能 2 跳后只覆盖 3/8）——这是**特性**，但**别暴露"X% 知晓"调参**，小 N 下像 bug。

### A4. 接受门 + 第三方声誉写入 — ADOPT（结构，非数学）
- **机制**：接收者**是否接受**一条 claim 取决于知识水平/来源信任（arXiv:2303.14213）；关系强度 + 立场兼容加权传播、且**听到会改自己对第三方的立场**（RA-ICM arXiv:2403.06385）。
- **落地**：在"A 告诉 B claim C"与"B 写入/转发"之间插**确定性接受谓词**：`accept = trust(B→A)≥τ AND NOT 与 B 亲历记忆矛盾 AND 无更高 provenance 反证`（亲历>传闻，你已有 provenance 排序）。低信任源 → 存为"B 听 A 说 C"(弱归因 belief)而非"C 为真"。**第三方声誉写入**=听到"Carol 鸽了 Dave"就降 B 对 Carol 的 affinity（gossip 事务 event-id 溯源）——这就是你问的"声誉从传播中形成"。
- **陷阱**：立场随对立源漂移在小 N 不稳（单个唱反调者几 tick 翻全镇）→ **按源信任门控、每 tick delta 封顶**；只让**亲历**全量定声誉，**gossip** 打折+衰减。

> **A 区整体 build order**：`spread_state`+Maki-Thompson(A3) → 接受门(A4) → `standing`+L3(A1) → gossip 同步 τ + 第三方声誉写入(A2/A4)。产出：涟漪-变冷的八卦 + 声誉门控的事务接受 → **涌现放逐/洗白**，LLM 只负责把 standing 口吻化。

---

## B. 博弈论 grounding：把承诺/信任/结盟变成有依据的确定性规则

### B1. Generous Tit-for-Tat（承诺/冲突的宽恕）— ADOPT（GTFT，弃完整 ZD）
- **机制**：重复博弈里 generous ZD/GTFT 战胜勒索者；GTFT=复制对方上步但以固定概率宽恕一次背叛。引用：arXiv:1304.7205 (Stewart & Plotkin, PNAS 2013)。
- **落地**：你的承诺(赴约/爽约/resentment)与冲突生命周期**已是 contrite-TFT + 宽恕路径**。只需把宽恕显式化：每关系一个整数计数 + 固定"宽恕预算"（如 3 次鸽 1 次 / familiarity 高时宽恕），防一次噪声爽约就螺旋成永久世仇。
- **陷阱**：弃完整 ZD（无穷期、连续概率，对玩家零可读、小 N 崩）。只取"宽容胜勒索"的教训。

### B2. 条件投资 trust 门（涌现联盟/放逐）— ADOPT
- **机制**：信任博弈里"仅当评估可信度超阈才投资"的条件投资者能**与可信者结盟、清出不可信者，无需惩罚系统**。引用：arXiv:2208.12953 (2022)。
- **落地**：`trust` 字段当**投资门**：NPC 仅在 `trust[target]≥θ` 时进入有代价/脆弱的互动（借东西、吐露秘密、共同承诺）。互惠者涨 trust→更多投资；爽约者跌破 θ→被冻结=涌现内群体，无需全局惩罚。比 affinity 更干净的"A 会不会依赖 B"经济学原语。
- **陷阱**：硬阈值在 6–10 体易把小镇锁进单一冻结小圈 → 加**滞回 / trust 缓慢衰减**让被排除者能重新赢回（接 B1 宽恕）。

### B3. 联盟=单遍确定性贪心（弃均衡求解）— ADOPT（启发式），SKIP（均衡/Shapley）
- **机制**：hedonic/ASHG 里 agent 只在乎自己在哪个联盟，加性可分 = **你的两两 affinity 求和**。但 Nash 稳定**常不存在**（随机 ASHG 下存在概率→0）、判定 NP 完全、best-response 路径依赖（回放隐患）。可救的是**高概率输出 individually-&-contractually-Nash-stable 划分的高效确定性算法**。引用：arXiv:2406.01373、arXiv:2312.09119；NP-hard arXiv:1212.2236。
- **落地**：每夜按**固定 NPC 顺序单遍**：每人加入"summed-affinity 最高且群体不否决(contractual)"的现有群。一遍 O(N·#groups)，无迭代、不追不动点。输出"这周谁跟谁混"，非证明的均衡。
- **陷阱**：N=10 可暴力枚举 Bell(10)≈11.6 万划分，但**别**——陷阱是"稳定划分"这个概念本身（不存在/难证/序依赖），不是算力。**SKIP Shapley/core**：生活模拟没有自然的特征函数 v(S)，硬造=假精度；扁平或 affinity 比例分账更诚实且便宜 100×。

---

## C. 架构：M2/M3 接 LLM 时的"反转"（你的厚世界 + 薄 LLM）

> 你的确定性引擎已比这些系统的"环境"更厚——它们把 LLM 焊到薄世界上；你要把薄 LLM 贴到厚世界上。每条都按"无模型/6–10 体/准实时/可复现"过滤。

### C1. PIANO 认知控制器 + 瓶颈，**反转** — ADOPT（最高优先）
- **机制**：PIANO 用单一 CC 经信息瓶颈定高层决策并**广播**下游，消除 say-do 不一致（说"好的"却去 explore）。引用：arXiv:2411.00114 (Project Sid, Altera 2024)。
- **反转落地**：**你的确定性引擎就是 CC**——它已经(经 SocialTransaction evaluate→commit)决定了"发生什么"。LLM 严格是下游 **Talking 模块**，只渲染与已提交记录一致的台词。瓶颈=你确定性组装的小固定 render 上下文(本事务 + top-k 记忆 + 关系摘要)。**say-do 一致免费**（LLM 从不决定动作，故无法矛盾）；无模型则同结构走模板。
- **陷阱**：别让 LLM 生成文本**反向**泄出新承诺("明天见")当真相——那从另一头重开 say-do 缺口。LLM 输出非权威；若要对话创造义务，**回灌确定性 SocialTransaction validator**(propose→evaluate)，绝不直接信。

### C2. Concordia 组件接缝：可换 Acting 组件 = 你的"LLM 可选" — ADOPT（接缝，弃 GM-LLM）
- **机制**：Concordia 的 Game Master 拥有世界、裁定动作、校验 grounded 变量；2.0 把 GM 也做成组件，可"全 LLM 自由 ↔ 全硬编码护栏"任意之间。Context 组件(并行喂)→ 单 Acting 组件(出一个动作)。引用：arXiv:2312.03664、arXiv:2507.08892。
- **落地**：**你的引擎=GM**；"字段化 SocialTransaction(preconditions/effects)"=硬编码裁定的 GM 组件。把 LLM 做成**可换的 Acting 组件**，与规则选择器同接口背后——"换掉 Acting 组件、保留同一套 Context 组件"。这就是"LLM 可选"的类型签名。
- **陷阱**：Concordia 用 LLM-GM 解析自由文本动作——你**绝不能**(毁确定性)。LLM 可**提议**一个受约束的 typed 动作(限你 ~15 动作词表)，但引擎**裁决**。

### C3. Stanford 检索(recency·importance·relevance) + 反思 — ADOPT（确定性打分），反思**门控**
- **机制**：记忆流按 recency(指数衰减)+importance(LLM 评)+relevance(embedding cos) 取 top-k；反思周期性把记忆合成更高层洞察。引用：arXiv:2304.03442。
- **落地**：检索打分**确定性化**——recency 平凡；relevance 用便宜的 tag 重叠或预算 embedding(非 live LLM)；**importance 写入期按事件类型定**(confront/reconcile 高、idle greeting 低)，别 LLM 评分。反思=你计划的**类型化反思**：**确定性聚合**("7 天 3 次爽约→派生 resentment 节点，event-id 溯源")，LLM 只措辞。
- **陷阱**：Stanford 反思是 LLM 写**新记忆节点且当事实**=信念洗白 + 回放隐患；近实时 8 体 LLM 反思还烧钱。**importance 用 LLM 评分**是要 skip 的具体点。

### C4. AgentSociety 需求层级 → SocialTransaction 提议触发器 — ADOPT（仅 needs→trigger）
- **机制**：Maslow 式需求层级驱动"Need→Plan→Behavior"链；数值子模型(引力模型)刻意减少 LLM 开销。引用：arXiv:2502.08691。
- **落地**：用需求向量(social/esteem/belonging 每 tick 衰减/补充)当**确定性动机源**，决定"何时想发起一次社交"=触发 SocialTransaction 提议。给 Sims 式可读性。
- **陷阱**：Ray/MQTT/agent-groups/引力模型是**1 万体的纯规模机器**，8 体有害。情绪栈(LLM 更新)不回放——要心情就做成"近期账本 delta 的确定性函数"。

---

## D. 评测：你的确定性回放给了别人没有的东西——**精确配对反事实**

> 2024–2026 工作几乎都在评"台词可信度"(LLM-judge)，文献自己已点名这是核心失败。你应转向因果/行为指标。全部归结为**固定种子下对 event log 的查询**——整个 bench 在**无模型**配置下跑，LLM 成了被 ablate 的变量。

### D1. PN/PS 因果指标（头牌）— ADOPT
- **机制**：必要性概率 `PN=1−p₀/p₁`、充分性 `PS=1−(1−p₁)/(1−p₀)`（外生性+单调性下闭式），p₁/p₀=有/无干预的结果率。引用：arXiv:2604.03920 (2026)。
- **落地**：完美契合 `Sim.goto_tick` event-sourced 回放：固定种子跑到 checkpoint，**分叉成只差一个开关的配对运行**(resentment 衰减 ON/OFF、"Bob 爽约 vs 赴约")。结果 Y=event log 的行为事件(N tick 内是否 Confront / 是否和解 / belief 是否到 ≥k 人)。M 个种子算 PN/PS → 把冲突/承诺系统变成**可测因果机制**("爽约对对质的必要性 73%、充分性仅 24%")。
- **陷阱**：反身社会系统**单调性会破**(一次道歉和解 A 却激怒旁观 C)→ PN/PS 退化为**下界**；永远同时报原始 (p₁,p₀)。

### D2. 涌现指标 + 行为 ground-truth — ADOPT（PI/cascade/Gini/扩散/赴约率），SKIP 幂律
- **机制**：极化指数 `PI=1−H/H_max`(意见分布熵)；级联 size/depth/breadth；交互 Gini；以及 Stanford 的"持有 belief 的 agent 比例(T)""被邀者赴约比例"。引用：arXiv:2603.23884、arXiv:2304.03442。
- **落地**：belief/知识边界**就是级联引擎**——每 claim 记传播树→直接算 size/depth/breadth。PI(对"对 Bob 的 affinity"分布)=一数"小镇是否在对 Bob 极化"。Gini(交互计数)=戏剧是否集中在一个 NPC(hub)。
- **陷阱**：N=10 幂律 α 无意义(需数百节点)→ SKIP。PI/cascade 在小 N 噪声大→ **≥20 种子平均的轨迹**，绝非单次端点。

### D3. ablation 设计 + 确定性 director + 有效性合约 — ADOPT
- **ablation**(arXiv:2304.03442)：A/B 关掉自己的系统(反思/resentment/知识边界 ON/OFF)，证明各自实质改变 D2 指标="每组件有贡献"的稳健性证据。
- **确定性 soft-director**(arXiv:2407.01093 IBSEN 的控制旋钮，弃每回合重生的 LLM-director)：规则策略在 beat 边界微调 precondition/effect 权重(久无戏剧则抬 Confront 倾向 / 播种 Topic 谣言)；"目标达成?"=对 event log 的纯谓词。指标=**objective-completion 率 + time-to-objective**。
- **有效性合约**(Springer/PMC12627210，35 篇综述：15/35 仅靠人/LLM 评判=不足且循环)：①目的对齐(评账本是否按协议动，别评台词美)；②稳健性(≥20 种子分布)；③硬不变量(**无 provenance 的 belief=0** 自动检查)。小 N 别假装对齐真实人类数据，替换成"复现具名小群社会心理规律"(平衡理论三元组、互惠)。

---

## E. 分阶段 roadmap / path（杠杆排序 + 依赖）

> 原则：先做**复用现有数据、纯确定性、杠杆最大**的；Topic 对象是若干项的前置；评测可**现在就起步**（`goto_tick` 已具备分叉能力）。

| 阶段 | 内容 | 依赖 | 为何这个顺序 |
|---|---|---|---|
| **S0（即刻，横切）** | 评测脚手架雏形：扩 `sim_soak`→ PN/PS 配对分叉(用 `goto_tick`) + 不变量(无 provenance 的 belief=0) + 涌现指标(PI/cascade/Gini) | 现有回放 | 后续每步都要它度量"是否真有提升"；零新系统 |
| **S1（最高杠杆）** | `standing`+L3 二阶范式(A1) + gossip 声誉同步 τ(A2) + 第三方声誉写入(A4) + GTFT 宽恕(B1) + 条件投资 trust 门(B2) | 现有账本/事务/承诺/冲突 | 把已有 gossip/trust/承诺/冲突**升级成声誉驱动的社会后果引擎**：涌现放逐/洗白/联盟，且不级联世仇。几乎全复用现有数据，纯确定性 |
| **S2** | Topic 对象 → 每(NPC,Topic) attitude：FJ+固执度(A 区 §1) + Deffuant 有界信任门(A §2) + Maki-Thompson 抑制(A3) + 接受门(A4) | Topic 对象(计划中) | 意见演化/持久分歧/意见小圈 + 八卦变冷 + provenance 拒斥。Topic 一到位就解锁 |
| **S3** | 联盟单遍贪心(B3) + 需求层级→提议触发(C4) + 类型化反思=确定性聚合(C3) | S1 的 affinity/standing | 可见的朋友圈/派系 + Sims 式动机可读性 + 有界记忆 |
| **S4（M2/M3 接模型）** | PIANO 反转：LLM=下游 Talking(C1) + Concordia 可换 Acting 接缝(C2) + 检索确定性打分(C3)；LLM 输出**记入 event log 当外部输入**以保回放 | M2 已接的 chat/decide | 真模型上线时保 say-do 一致 + 回放安全；LLM 始终是被 ablate 的皮肤 |
| **S5（评测成熟）** | causal bench + 确定性 director + ablation 套件 + 有效性合约 → 接 22nd pipeline 当 living-town bench task | S0 + 各系统 | 把"涌现戏剧"变成可复现自动评测，闭合 22nd"自评估工厂"范式 |

**"先做哪个杠杆最大"= S1**（声誉×八卦×宽恕）：单点把现有四个系统(gossip/trust/承诺/冲突)从机械边升级成有戏剧后果的社会引擎，且几乎不引入新数据结构。S0 与它并行起步。

> **S1 已实现并验证（2026-06-27）**：`relationships.standing`(L3 Simple Standing 二阶范式：守约/和解=help+、爽约/拒绝/对质否认=defect− 含"教训坏人正当"分支) + `gossip_rep` 第三方坏名声传播(信任源采纳) + `_acceptance_rule` 读 standing(涌现放逐) + 每日 `resentment` 衰减 & 名声向 0 漂移(GTFT 宽恕/无永久污名) + give/invite 的条件投资 `trust≥INVEST_TRUST` 门。`sim_soak` 增 4 条不变量(14 standing 分化 / 15 涌现放逐[守护:仅恶名者 perceived≤−0.8 时断言,对比镇均,避小 N 噪声] / 16 gossip_rep 传播>0 / 17 坏名声形成且可恢复)。Node 端口 8 seed + 真 Godot 多 seed 全过 17 条、双跑确定。观察台面板显示 `名±N`。**坑**：把"最坏名声被接受率<最好"当硬断言在小 N 会因微弱 standing 的 affinity/need 噪声反转(正是本文 §F 警示)→ 改为只在真恶名者出现时断言、且对比镇均。

> **S2 已实现并验证（2026-06-27）**：Topic 对象 → 每(NPC,话题) `attitudes`/`attitude0`(天生立场,确定性 hash) + `xi`(易感度)/`eps`(信任带)由性格定。机制：**Friedkin-Johnsen**(`_fj_update`：朝对方靠拢×trust·familiarity 权重，固执度 1−ξ 锚定天生立场→持久分歧不坍缩成 DeGroot 单一共识；高 resentment→**背离**signed) + **Deffuant 有界信任**(新动作 `discuss` 挑 ε 内最大分歧话题；`_acceptance_rule` 软门 `(eps−diff)*30+...`，差太大→拒谈计 `refused_by_bound`) + **Maki-Thompson 谣言变冷**(接触中遇 K 个已知者→变 stifler，`_unspread_belief` 跳过 stifled→谣言自然停传)。sim_soak 增不变量 18(观点演化不坍缩:话题跨度>0.3且有变动)/19(有界信任:discuss>0且拒谈>0)/20(谣言变冷:stifler>0)，inv10 改查累积负向后果(怨气按 GTFT 衰减,末态可为 0)，inv16 改条件式(有坏名声才要求传播)。**Node 端口 12 seed + 真 Godot 4 seed @60天 全过 20 条、双跑确定**。观察台面板显示每话题观点 `±N.NN`。**坑**：① discuss 初版评分输给 greet→从不触发(观点不演化)；且初版挑"最大分歧"正是有界信任最易拒谈的→Deffuant 悖论。修：挑 ε 内最大分歧 + 适度评分。② over-boost discuss 把 gossip_rep 挤没→给 gossip_rep 升"示警"优先级。③ MT 止传改变轨迹→某些 seed 35 天内无冲突/gossip_rep，故 canonical 测用 60 天。

> **S3 已实现并验证（2026-06-28，三机制全做）**：先用 4-agent 并行 workflow 产出代码级规格+综合总纲，再按"共享守卫→秘密→派系→盟约"逐步实现，每步 soak 绿。
> ① **观点派系**：每夜 `_recompute_factions()` 从 `attitudes` 单遍贪心(sorted id,确定性)派生 `faction` 标签(对齐=≥2 话题同号且 |Δ|<FACTION_BAND；非显式 join，观点漂移则派系重组)；`_acceptance_rule` 加 `_faction_term` ±FACTION_ACCEPT_K(内群易接/跨群难=放逐加剧)；新候选 `endorse`(派系内对外群恶名者统一口径,standing 靠拢两步) + `rally_oust`(同派系协同施压,**只对在该支持者眼中 standing<0 或有冲突的 o 降名声=L3 不冤枉好人**)。
> ② **互助盟约**：夜间 `_form_pacts_greedy()`(双向 trust≥12+familiarity≥6+complementSeen≥3 门) + `aid` 按需互助补对方低 need + `_record_aid` 双边记账；`_dissolve_freeriders()`(净失衡 gap≥4 + 连续 streak≥2 + 成熟 exchanges≥3，GTFT 一次回报清 streak)；复用 commitment/give/trust/L3/冲突，pact 只加权 invite/attend 不另立承诺类型。
> ③ **秘密信息博弈**：belief 加 `secret/owner/confidedBy`；`confide`(仅 owner 向高 trust+aff 者吐露→双向 trust+8) / `leak`(被托付者外传=背叛→对**每个直接 teller**(只记直接上游防链式误判) trust 崩−40/aff 崩−30/L3 名声罚/`_bump_resentment` 14>触发冲突)；`_unspread_belief` 跳 secret 走专道。
> **跨机制守卫 `_adjust_standing`**：单 tick 每(观察者→对象)standing 总移动封顶 ±2，`_judge_actor`/endorse/oust/betray 全经它防叠穿。**社交底座累计 33 条机检不变量**(原 20 + 秘密 21-24 + 派系 25-28 + 盟约 29-33，均含小N守护)。Node 端口(`tools/sim_social_port.mjs --scenario faction|betray|freerider`)4 场景 + 真 Godot(`sim_soak --scenario`)4 场景全过 33 条 + S0 网格 8 seed/确定性 3/3 双跑一致。**坑**：拒绝路径 affinity 漏 clamp(betray 场景暴露越界,已修)；定向场景会扭曲关系/致饿穿→inv1/5/18/19/26 在非空场景豁免(场景压力非 bug)；pactKey 须可在种子前调用。**S3 可视化 + S4 也已落地（2026-06-28）**：
> **S3 可视化**：WorldView 画同派系同色脚环 + active pact 青色双线🤝 + confide/leak/betray/endorse/rally_oust/aid/pact 罐头台词气泡；观察台面板加 派系/互助盟约(给N收N)/秘密(自有·被托付) 段。真 Godot 录屏验证（`docs/media/s3_social_demo.mp4` faction 场景 + `shot-s3-factions.png`）。
> **S4（接模型 say-do 一致 + 确定性回放）**：say-do 一致由"台词绑定所选候选"天然保证。`Sim.decision_trace` 把落地的模型决策(pick 下标 + cand_hash，不记 prompt/思维链)记为**外部输入**；`set_replay()` 按"tick:agent"+per-agent 指针**还原异步思考延迟时机**回放，绕过模型；`_resolve_replay` cand_hash 一致→按下标精确取候选，否则 drift 计数 + logic 兜底（永不静默损坏）。`scenes/s4_replay_test.tscn`：mock 记录→无后端回放→**确定性窗口逐字节 digest 一致、drift=0**（机制证实）。残留：mock 异步(MAX_INFLIGHT 争用)在 ~200 tick 后有 social-coupling 微漂，cand_hash 检出并优雅兜底（events 不冻结）；**生产回放根仍是确定性 event_log**（`goto_tick` 对纯 logic 已逐字节可复现）。LLM 始终是被 ablate 的皮肤：拔掉模型→回放/soak 全绿。下一步 S5(causal bench 接 22nd) 或根因排查 async 漂移做到全程逐字节。

---

## F. 不要做 / 陷阱清单（小 N + 确定性 + 私有声誉）

- ❌ **Stern Judging (L6)**、image scoring 一阶范式——私有/噪声下不稳、世仇级联。用 **L3 Simple Standing**。
- ❌ **任何 P(spread)/转移概率**进主逻辑——回放杀手。换确定性阈值 / 种子化 hash。
- ❌ **影响力最大化 / 种子选择 / R0·相变调参 / 幂律拟合 / 谣言源检测**——大 N artifact，N=8 无意义。
- ❌ **Shapley / core / hedonic 均衡求解**——v(S) 无自然定义=假精度；解常不存在/为空/序依赖。用单遍贪心 + 扁平分账。
- ❌ **硬阈值无滞回**(ε、trust θ)——小 N 脆裂(一调翻全镇 / 锁死单一小圈)。软化 + 滞回 + 宽恕。
- ❌ **LLM 进决策路径 / LLM 评 importance / LLM-GM 裁定 / LLM 反思写事实**——毁确定性与回放。LLM 只渲染；其输出**记为 event** 再回放。
- ❌ **让 LLM 对话直接创造承诺**——回灌 validator。
- ❌ **追求涌现文明(角色分工/宪法/迷因传播)**——纯规模现象(30–500 体)，8 体只得轶事 + 全是脚手架。
- ❌ **暴露"X% 知晓"等大 N 调参旋钮**给玩家——小 N 下像 bug。
- ❌ **LLM-judge 评台词**当主评测——循环、不足。用因果/行为指标，≥20 种子平均；PN/PS 单调性破时当下界并附原始 (p₁,p₀)。

---

## G. 关键 arXiv 引用

**意见动力学/谣言**：Friedkin-Johnsen & 综述 arXiv:2511.00401；签名 FJ(IEEE TAC 2025)；Deffuant 收敛 (Automatica 2020)；HK arXiv:2111.14291；LLM 意见动力学(只能加偏才极化) arXiv:2311.09618；Maki-Thompson arXiv:2507.07914 / 2508.07099；知识水平接受门 arXiv:2303.14213；RA-ICM arXiv:2403.06385。
**博弈/声誉**：leading-eight 私有噪声稳定性 arXiv:2310.12581 (PNAS 2023)；意见同步 τ arXiv:2409.05551 (PNAS 2024)；gossip 最小量/单源等价 arXiv:2312.10821 (PNAS 2024)；generous ZD arXiv:1304.7205 (PNAS 2013)；条件投资信任博弈 arXiv:2208.12953；范式表/公平合作 arXiv:2408.04549；声誉收敛 arXiv:2404.10121；ASHG 随机稳定性 arXiv:2406.01373 / 2312.09119；ALIGN gossip indirect reciprocity(4–10 体) arXiv:2602.07777；Donor Game 文化演化 arXiv:2412.10270；LLM 联盟谈判模板 arXiv:2402.11712。
**LLM 社会模拟架构**：Project Sid/PIANO arXiv:2411.00114；Concordia arXiv:2312.03664 / 2.0 arXiv:2507.08892；Generative Agents arXiv:2304.03442；AgentSociety arXiv:2502.08691。
**评测**：PN/PS 反事实 arXiv:2604.03920；生成社会模拟有效性综述 PMC12627210；POSIM 涌现指标 arXiv:2603.23884；IBSEN director arXiv:2407.01093；LLM agent 评测综述 arXiv:2507.21504。

> 检索说明：本表为 6 路并行 agent 的 WebSearch+WebFetch 结果综合；arXiv 编号以官方为准（个别 2026 编号为检索期 preprint，引用前请核对）。
