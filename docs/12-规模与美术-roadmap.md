# 12 · 规模（多 NPC）与美术 roadmap

> 2026-06-28。研究型规划（4 视角并行检索前沿 + 结合本项目约束综合），**只规划不实现**。
> 五条红线（每条建议都过）：① 确定性/逐字节回放 + 33 条机检不变量；② 无模型可玩（LLM 是被 ablate 的皮肤）；③ 跑得动中端机/核显甚至纯 CPU；④ 无版权风险；⑤ 复用优先，不重写全栈。

## 0. 一句话结论

**扩 NPC 数量，引擎侧几乎免费**——本项目的确定性引擎每 tick 只做廉价脚本，LLM 调用已被 `_decide_interval`(tier 节流)+`MAX_INFLIGHT`+capability 探针约束为正比于"戏剧事件"而非 N。真正的瓶颈与对策都在三处 O(N²) 热点 + 离屏治理 + 评测可扩展。**美术不是"画更多图"问题，而是"程序化变体"问题**——palette-swap 让视觉数量线性增长而零新增 PNG、零版权风险。两条线通过"离线生产期 vs 运行时确定性"这道边界**可大幅并行**。

> ⚠️ **先治本的隐患（最高优先）**：当前 `Sim._rng_at` 种子 = `seed_base + tick*911 + salt`，**不含 agent_id**。这意味着加一个 NPC 或改候选集，每个 agent 的随机流就漂，N=10 的 digest 永远对不上 N=50，且同 tick 同 salt 的 agent 间有隐藏 RNG 相关（WSC15 经典坑）。**不先修这步，后面任何扩 N 的 digest/回放/bench 都是沙上塔。**

## 1. 杠杆排序（成本×收益×风险，依赖链在前）

| 级 | 内容 | 为什么这个顺序 |
|---|---|---|
| **L0 地基 ✅ 已实现(2026-06-28)** | per-agent 计数器 RNG 子流：`_rng_at(salt, who)` 种子混入 `who=hash(id)*104729`，4 个 per-agent 调用点(confront/apologize 用发起方、acceptance 用 target、logic_decide 用决策者)都传 agent 维 | 扩 N 唯一真地基；不做则一切 digest/回放跨 N 全废。**实测 S0 8 seed 全过+确定性 3/3**(闭掉 WSC15 同-tick-同-salt 撞流坑) |
| **L1 纯加速 ✅ 已实现(2026-06-28)** | 缓存 `ag["area"]`(移动经 `_move_agent` 刷新)，`_nearby_agents` 去掉 `_area_at` 的 areas 内循环(去 ×areas 因子)；遍历仍按 agents 固定序 | **实测 digest 与 L0 逐字节相同**(零行为变化的纯加速硬证据)。注：全 O(N·k) 倒排桶因 tick 内移动+候选下标影响 jitter 的字节一致性留作扩 N 时做 |
| **L2 摊平 ✅ 已实现(2026-06-28)** | `decide_period`：每 agent 仅在 `tick%P==hash(id)%P` 做重决策；默认 P=1(零行为变化)，P>1 摊平大 N 尖峰 | **实测 N=30 P=4 33/33 全过**；完全可复现 |
| **L3 行为面 ✅ 保守版+激进版已实现(2026-06-30)** | **保守** `lod`：远端(到 `lod_focus` 曼哈顿>`lod_near_radius` 或不在「最近 K」集)决策周期 ×LOD_FAR_MULT(3) 降频；**激进** `lod_aggregate`：远端**完全不跑 option/候选枚举/寻路/社交**，只 `_far_maintain` 被动维持需求(单 agent 成本≈0)。近/远判定支持 `lod_near_cap`=相机周围最近 K 人(小地图比半径可控)。生存覆盖(危机需求不跳决策)+ LOD 饥饿兜底(need<8 就地小补，off 永不触发) 守「无饿穿」硬不变量 | **实测(`bench/LodAblation.gd` 三路 off/保守/激进)**：N=80 cap=12 **保守门+激进门双 PASS**(保守 ΔPI=0.002·Δcasc=0.50·ΔGini=0.015 + 33 全绿；激进省 cand 83% + 硬不变量全绿 + 不饿死)；**N=160 激进门 PASS，cand_calls 每日≈持平(110→121/日) vs off 线性(659→1304/日) → 成本 ∝ 活跃 cohort 而非 N**(冲上百 NPC 的关键)。激进契约=软涌现指标按设计可漂(远端=背景群演) |
| **L4 评测可扩展 ✅ 已实现(2026-06-30)** | (1) **不变量正式两分**：`Invariants.HARD_IDS`(结构/可溯源/边界/生命周期合法=任何 LOD/规模下必为真) vs 软(涌现统计,场景/大N 豁免)；`split_fails()→{hard,soft}` 供激进 LOD 门只查硬。(2) **增量 digest**：`Sim.event_digest` 每事件 O(1) 滚动折叠(FNV 式)→ 不必末尾遍历 event_log 即得全程确定性见证(大规模/长跑友好)，S0 det 校验**批量+增量双摘要**都须一致。(3) **跨种子/规模 CI**：`bench-godot.ps1 -Suite Scale`(N80 双门+N160 激进门) / `-Suite All`(S0+S5+Scale 一键红绿) | **实测 S0 6seed 33/33 全绿 + 双摘要 det 3/3；Scale suite PASS(exit 0)** |
| **L5 LLM 治理 ✅ 令牌桶+老化优先已实现(2026-06-30)** | (1)**令牌桶** `AIBackend.llm_budget`(>0=每 sim-日全镇上限)：`_budget_gate` 窗口对齐+`_fire` 消费+超额 `decide()` 返 `{}` 走引擎地板。(2)**老化+优先** `llm_aging`(默认on)：预算稀缺时不再 FCFS，按 `_priority`=陈旧度(距上次发声的 sim-日数,**无上界→反饿死**)+戏剧显著性(需求危机/卷入未了结冲突) 门控，门槛随当日预算耗尽比例(`used_frac×AGING_GATE`)升高→越紧越只让最陈旧/最戏剧的发声。**只在模型后端，不碰确定性 logic 地板** | **实测 BackendBench mock N=30**：无预算 fired=3093 → budget=40/日 fired=846(封顶，**LLM 调用 ∝ 预算而非 N**)。**硬预算 4/日**对比：aging **off** 声誉 Gini 0.244·从未发声 agent 0.333(FCFS 把部分 NPC 40 天全程噤声) → **on** Gini 0.223·**从未发声=0**(陈旧度兜底,人人终会发声),硬顶恒守+两跑确定。BackendBench 加 `--aging on\|off`+发声公平度量。中央批式队列、远程微批为可选后续 |
| **L6 美术地基 ✅ 调色板变体已实现(2026-07-01)** | 克隆(id=`npc_*`)按 `absi(id.hash())%24` 取确定性色相桶，首次用到时 CPU 绕 HSV 色相环旋转精灵→缓存 ImageTexture 变体(`WorldView._hued_tex`)；命名 6 人(aria..fei)零位移保正典，6 人小镇本层休眠 | **实测真 Godot 渲染 N=48 一帧**：48 个各不相同的居民由 6 张 CC0 精灵派生(teal/紫/品红/蓝/红/黄绿)，零新增 PNG、零版权、确定可复现；与满社会 sim 共存(822 事件/25 冲突/endorse·rally_oust)。见 `docs/media/shot-crowd-palette.png`。**坑**：Godot 4 immediate-mode `_draw()` 无 `draw_set_material`(材质是 per-node 非 per-draw)→ 改 CPU 预烘色相变体纹理。palette.gpl/quantize.py 生产期工序为可选后续 |
| **L7 美术表现力** | 事件驱动"显形"取代始终全开 + 复用已算好的社会量做图层 | 表现力靠"显形时机"而非"图元数量"（RimWorld 实证） |

## 2. 规模线分阶段

| 阶段 | 目标 N | 关键技术 | 复用 | 验收 / 不变量影响 |
|---|---|---|---|---|
| **S-scale-0** RNG 地基 | 仍 6–10（先治本） | per-agent 计数器子流 + 命名 channel；Node 端口 mulberry32 同步换种子构造 | `_rng_at` 全调用点、双跑纪律 | 33 条全绿不变；建立"子集一致性"基线；单独成 PR |
| **S-scale-1** 空间分区 | 仍 6–10（纯加速验证） | tick 开头建 `area→[agents]`桶(桶内 sort(id))；ag 缓存 area 字段仅 pos 变更时更新 | agents 固定遍历序、social_candidates 路径 | **digest 与 S-scale-0 逐字节相同**（"纯加速不改行为"硬证据） |
| **S-scale-2** 决策切片 | 20–30（首次扩 N） | 相位门 `tick%P==hash(id)%P` 才重决策 | `_advance_agent` 决策入口 | step 耗时方差下降；观察 inv15/26/29 接近反转（为 L4 收证据） |
| **S-scale-3** 仿真 LOD | 数十（最大行为面） | near 全保真 / mid 切片+跳步 / far 每 K tick 聚合统计(K×decay+区内 advertise 补需求+`_rng_at` 抽样社交)；档位=到玩家距离确定函数+边界滞回 | option 机制当抽象层级、S3 确定性聚合反思做 far 记忆摘要 | **核心合约：LOD ON/OFF 在固定 N 下 S0 PN/PS + 33 不变量 ablation，证 PI/cascade/Gini 分布不漂（均值差<CI）** |
| **S-scale-4** LLM 队列治理 | 数十~低百 | `_pending`→(LOD+导演+饥饿老化)优先队列、按(priority,id)排序；全镇令牌桶≈1/p50；远程 llm 可选微批(整批一 deadline，超时全批兜底) | `_decide_interval` tier 节流、decision_trace pick 回放 | 离屏 NPC 因老化偶尔发声；**拔模型/限频后 33 条全绿**；LLM 调用不随 N 线性增长 |
| **S-scale-5** 离屏聚合 NPC | 名义低百/全保真几十（仅 interactive） | 背景 NPC 池(人群密度/区域情绪标量)↔靠近时确定性实例化+补历史；far↔far 账本批量统计、记忆 summarize-and-forget | S3 类型化反思=确定性聚合 | **红线：实例化依赖玩家交互→绝不进 soak/回放/bench**；soak 永远跑固定几十真 agent。最后做（实例化最易引入非确定） |

**明确 SKIP**（过度工程/破红线）：Project Sid 文明涌现（低百仍是小 N，假精度）、ECS/Bevy-Rust 全栈重写、Ray/MQTT 分布式、GPU compute shader 跑需求、TileMapLayer/.tres（headless 无编辑器）、slm 后端微批、概率式 LOD 切换（live RNG 是回放杀手）。

## 3. 美术线分阶段

| 阶段 | 供给方式 | 一致性手法 | 复用/版权 |
|---|---|---|---|
| **A-art-0** 调色板收口 | 抽 32–48 色主调色板 `palette.gpl` + `tools/quantize.py`(PIL 最近邻量化,确定性)；所有切图/pro 覆盖/GPT 图过这道；硬编码 Color 改从 palette 取 | 单一调色板真相 + 可选统一外轮廓 | Art 三级回退不动，仅生产期收口；纯工序零风险 |
| **A-art-1** persona→palette-swap | personas.json 加 palette 字段(复用已存在 persona.color 当种子)+`palette_swap.gdshader`；sprite 拆 {base,palette_swap,accessory} | 同 base+同主调色板天然统一；persona.color+traits 确定性 hash→唯一外观 | **6 个 CC0 槽→任意数量确定性变体，NPC 扩到 20–40 不增 PNG**；派生资产无风险 |
| **A-art-2** 程序化场景丰富度 | 现有 `_hash` 散布+`_draw` 家具加调色板/密度/季节变体 | 都过 A-art-0 同 palette；季节=palette 整体微移 hue/sat | 沿用 `_decor_built` 缓存；零资产零风险 |
| **A-art-3** 事件驱动"显形" | 关系连线/脚环/盟约线默认弱化，仅选中 ego-network/跨阈翻转脉冲/持续冲突显形 | 表现力靠显形时机非图元数量 | 纯显示层读 Sim 现状态；零回放影响。S-scale-3 出现数十 NPC 后才必要 |
| **A-art-4** 社会戏剧图层+氛围 | standing→名牌色边/星-裂纹、放逐→灰环、attitude→冷暖点、谣言变冷→涟漪变灰、派系重组→脚环渐变、盟约破裂→断线动画；mood=账本 delta 确定函数→idle 微动+名牌色温；PI 高→镇色偏冷+季节调色板 | 全读 Sim 现有确定性字段、零新模型 | 显示层叠加，回退链不动；确定性日程/状态函数可回放（禁 LLM 情绪栈） |
| **A-art-5** GPT-5.5 立绘窄通道 | `character_bible.md` 锁 6 persona styleDNA+reference image(image-to-image)；落 `assets/art/pro/` 走最高级回退，**仅对话框头像、绝不进精灵帧**；出图过 A-art-0 量化 | 固定 styleDNA+reference+量化进同色系 | 纯 AI 输出无版权(US Copyright Office 2025)；离线人工、静态落盘；发布前按当时 OpenAI 条款+字体 OFL+逐目录 LICENSE 复核 |

## 4. 规模 × 美术 三处硬交织

1. **规模→美术供给压力被 palette-swap 卸掉**：A-art-1 应在 S-scale-2（首次扩 N）之前/同期就绪，否则扩 N 时撞色/缺图成伪瓶颈。
2. **LOD 档与显示显形门控同源**：同一个"到玩家距离"确定性函数既驱动仿真 LOD（far 不跑 option）又驱动可视化 LOD（far 不画关系线）——省 CPU 又省 draw；far 背景人群（S-scale-5 标量）对应 A-art-2 程序化人群，靠近实例化时 palette-swap 即时派生。
3. **事件驱动显形与评测同源（所见即所测）**：A-art-3/4 读的 standing/attitudes/spread_state/faction/pacts 正是 L4 不变量/Metrics 已算好的量——画出来的戏剧就是机检的戏剧，不引第二套真相、只读不写。
4. **离线生产 vs 运行时确定性边界**：美术永不引入运行时随机（quantize/立绘是构建期、palette-swap 输入是静态数据、mood/天气是状态函数/确定性日程）→ L0(RNG) 与 A-art-0/1 可同时开工。

## 5. 风险与缓解（按概率×杀伤）

- **R1 跳过 L0 直接扩 N（最致命，且静默）**：bench 仍显绿但实际不可复现。→ L0 设硬前置门；S-scale-1 用"digest 逐字节不变"客观证据。
- **R2 小 N 守护在 N≈20–30 静默反转（比红更危险）**：inv15/26/29 变永过/永不过空门，仍显绿却不再检查。→ S-scale-2 主动观察；L4 把涌现/统计类转跨种子 CI 门、退役硬阈值；结构/守恒类绝不统计化。
- **R3 LOD 改变涌现指标却被当"正常波动"**：→ 强制 LOD ON/OFF 跨种子 ablation，门=均值差<CI；档位滞回；先单独验 far 抽样确定性回归再叠 mid。
- **R4 微批一项拖垮整批/prompt 互污染**：→ 仅远程 llm、整批一 deadline 超时全批兜底、逐项独立 parse 校验、回放走 decision_trace 下标；slm 不微批。
- **R5 仿真档与显示档不同源（看见的人≠在算的人）**：→ 单一"到玩家距离"函数同驱两者。
- **R6 美术风格混搭**：→ 缺槽优先同作者 PunyWorld，否则程序化兜底；所有来源（含 GPT）强制过 A-art-0 量化。
- **R7 全局预算自适应(T6)泄漏进 bench**：读墙钟破回放。→ 断言 `scenario!=""` 才启用，bench 固定 N+P+全保真。
- **R8 实例化背景 NPC 引入非确定**：→ 只在 interactive，soak/回放永跑固定真 agent，放最后做。

## 6. 即刻可做的 quick-wins（各 ≤1 天，低成本高回报）

1. ~~`_nearby_agents` 改 `area→[agents]` 桶查询~~ ✅ L1 已做（缓存 `ag["area"]`，digest 逐字节不变）。
2. ~~决策相位门 `phase=hash(id)%P`~~ ✅ L2 已做（`decide_period`，默认 1 零行为变化）。
3. ~~`Invariants.digest` 全量 hash → `_log_event` 增量滚动哈希~~ ✅ L4 已做（`Sim.event_digest`，O(1)/事件，S0 det 双摘要校验）。
4. `CausalHarness` 改用已存在的 `goto_tick` 做 checkpoint 分叉、只重跑注入后半段（省约一半算力，goto_tick 已实现却未复用）。
5. 建 `assets/art/palette.gpl` + `tools/quantize.py`；`_draw_bed/_draw_stove` 硬编码 Color 改从 palette 取（生产期工序，零运行时影响）。
6. personas.json 加 palette 字段 + 挂 `palette_swap.gdshader`（6 个 CC0 槽即刻派生确定性变体，不必等扩 N）。
7. `slice_visual.py` 硬编码 (col,row) 切图规格抽成 spec JSON（一次性脚本→可复现资产录入 SOP）。
8. `_draw_relationship_lines` 加 selected/recently-changed 门控（默认弱化常驻连线，缓解 >10 体连线糊成一团）。

## 7. 关键参考

Lyfe Agents (arXiv:2310.02172, option-action+summarize-and-forget, 10–100× 降本)、Affordable Generative Agents (arXiv:2402.02053)、Project Sid/PIANO (arXiv:2411.00114, 多 agent tick 调度模板;文明涌现 SKIP)、Generative Agents (arXiv:2304.03442, 记忆/反思=离屏成本有界)、a16z AI Town、Voyager (arXiv:2305.16291, 技能库复用免 LLM)；工程对标 The Sims off-lot townie、RimWorld 区域休眠、RTS 时间切片 AI。palette-swap: HeartoLazor/KoBeWi gdshader。本项目 docs：02/03 §4-6/10 §C·§F/11。

> 总览：**先治 RNG 地基(L0) → 纯加速(L1) → 摊平(L2) → LOD 行为面(L3,需 ablation) → 评测可扩展(L4 横切) → LLM 治理(L5)**；美术 **A-art-0 调色板收口 + A-art-1 palette-swap** 与 L0 并行起步，表现力(A-art-3/4)依赖规模线产出的社会状态、与评测同源。每步 sim_soak 多 seed + Node×真 Godot 双跑 + S0 PN/PS 分叉验过再叠下一步，绝不一次引入多变量。
