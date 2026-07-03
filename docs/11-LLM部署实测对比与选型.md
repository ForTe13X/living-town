# 11 · LLM 部署实测对比、选型与 roadmap

> 2026-06-28。基于三路真机实测（见 [docs/03 §10](03-LLM集成架构.md)），用多视角分析综合出**部署决策 + 模型/排队策略 + 架构自适应 + roadmap**。
> 一句话：**离线嵌入式 SLM 在能用 GPU 时是最优解**——但所有亮眼数字绑死在本机这块高端 APU 上，发行必须分档 + 确定性地板兜底。

## 1. 三路实测（头部数据）

| | 路A · LM Studio qwen-3-8b（宿主 GPU） | 路B · 嵌入 1.5B-Q4 / CPU（**容器,伪命题**） | 路C · 嵌入 1.5B-Q4 / **GPU（本机原生）** |
|---|---|---|---|
| 决策 JSON | 4.4s | ~~59s~~（容器畸形；真 CPU 1.5–2.5s，见 §12） | **1.06s** |
| 玩家对话 | 6.5s | ~~42s~~（同上） | **0.24s** |
| 部署 | 需玩家开 LM Studio 服务 | 内置离线 | **内置离线、zero-config** |
| 质量 | 高(8B) | 中(1.5B) | 中(1.5B) |
| 结构化 | parse 抽 JSON（json_schema 长 prompt 卡死） | 原生 GBNF/json_schema | 原生 GBNF/json_schema |

> 路C 实测环境：AMD Ryzen AI Max+ 395 / Radeon 8060S（RDNA3.5、KHR_coopmat、~93GB 统一显存），`gpu_layers=29` 全 offload。
> ⚠️ **路B 的 59s 是 Docker 软渲容器伪命题**——同机原生 CPU 仅 1.48s（40× 差）。真实 CPU/中端机全景见 **§12**。

## 2. 最高价值 INSIGHTS（反直觉优先）

1. **离线嵌入式 SLM 在强 GPU 上反而比宿主 8B 更快**（路C 1.06s < 路A 4.4s）——1.5B≪8B + 进程内零 HTTP。这翻转了"离线=慢"的预设：**没理由让玩家去装 LM Studio**。
2. **真正的约束从来不是显存，而是 12s 截止线下的并发吞吐**——93GB 用不到 15%，但 10 NPC × 单 GPU 串行解码才是天花板。
3. **`MAX_INFLIGHT=2` 在路C(单 GPU)上可能是反优化**——GPU 串行执行，发 2 个只是排队拖长各自 p50；进程内更优解是「队列+1 worker」。（路A 的 HTTP 路才需要 2 路填网络空窗。**需先验证 NobodyWho/llama.cpp 是否有独立 context slot。**）
4. **亚秒 SLM 买到的是「发言频率 + 覆盖率」，绝不是「对世界状态的写权」**——LLM 仍只在引擎枚举的合法候选里 pick，20 条不变量/需求/S1/S2 永远引擎独算。频率可自适应，**权力边界不可自适应**。
5. **～「路B 纯 CPU 59s 永不能进发行链」已被实测推翻（§12）～**：那 59s 是 **Docker 软渲容器伪命题**（同机原生 CPU 仅 1.48s，40× 差）。真实现代 CPU 跑嵌入式 1.5B = **1.5–2.5s，满血可用**；GPU 只快 ~1.5–2× 非必需。**路C 几乎覆盖所有现代机**，logic 兜底只留给真·极弱/老/移动/Web——这是整个分档最大的简化。
6. **显存富裕让「多模型常驻 + 每 NPC 短 KV」成为规避所有已知坑的杠杆**——固定 system 前缀只 prefill 一次常驻 KV、决策只追加增量 token，prompt 变短直接绕开「LM Studio 长 prompt 下 json_schema 卡死」的根因。
7. **路C 的速度反转把蒸馏的卖点从「速度」改成「质量 + prompt 体积」**——1.06s 已达标，蒸馏 ROI 必须由 bench 的质量分证明，否则可能白干。
8. **显存不缺时决策档不该用 Q4**——Q4 省的显存毫无意义，Q5/Q6 直接降低「坏 JSON→兜底」率（JSON 对量化噪声比自然语言更敏感，一个坏 token 就破坏 schema）。

## 3. 部署建议（分档回退链）

> **默认 = 路C 嵌入式 SLM·GPU（zero-config、随包 ~1GB、离线）；启动按 Vulkan+显存探测自适应 `gpu_layers` 分档；无 GPU/Web/Deck 不达标时即时落确定性 logic（绝不上纯 CPU 路B）；路A·8B 仅作发烧友显式开启的「高质量模式」。**

| 档 | 目标机 | 后端 | 决策延迟 | 退化表现 |
|---|---|---|---|---|
| **S 强机** | 大显存 iGPU/独显(Vulkan) | 路C 全 offload | ~1s | 满血：LLM 台词+导演 |
| **B 中端 GPU** | Radeon 780M 级核显(RDNA3 12CU) | 路C 1.5B 全量 | **~1.3s（780M 实测✅）** | 满血：LLM 在线 |
| **B′ 中端纯 CPU** | 现代多核 CPU（无可用 GPU offload） | **路C 1.5B 跑 CPU** | **~1.5–2.5s（Zen4/Zen5 实测✅）** | 满血：LLM 在线 |
| **L 极弱/老/移动** | 老旧低核 CPU / Vulkan 不可用且 CPU 太弱 | 直接 logic | 即时 | 纯确定性，无 LLM 台词 |
| **W Web** | 浏览器/WASM | 强制 logic（不内置模型） | 即时 | 纯确定性、小体积 |

> **重大修正（见 §12 实测）**：旧版以为"纯 CPU 太慢(59s) → 弱机必落 logic"。实测推翻——那 59s 是 **Docker 软渲容器伪命题**；真实现代 CPU 跑嵌入式 1.5B 仅 **1.5–2.5s**，照样满血。故新增 **B′ 纯 CPU 档**：**绝大多数现代机（有无独显/核显都行）都能跑路C**，logic 兜底只留给真·极弱/老/移动/Web。

回退链 `路C全offload → 路C降配 → logic地板`；路A 不进自动链（仅 localhost LM Studio 在线时可灰度选）。**安全性来自「引擎=地板」：每一档退化游戏仍完整可玩。**
分发：基础包内置 1.5B（~1GB，模型作独立可校验资产便于热替换）；路A/8B 走可选指引不进包；Web 剥离模型。隐私/离线（100% 本地、对话不出机、零账号/零云成本）作核心卖点。

## 4. 模型尺寸 / 排队（强机 profile —— 仅开发机/发烧友档）

> ⚠️ 本节配置建立在 93GB 显存 + 71.5 字/s 的 8060S 上，**对普通玩家不可外推**，是 R&D 机配置不是发行默认。发行准绳以 §3 分档为准。

- **决策主力 3B-Q5/Q6**（~2–3GB，决策 ~2s，10 NPC 负载 ~53%，sweet spot）；起步可留 1.5B 但**用 Q5 不用 Q4**。
- **对话主力 7B-Q5**（chat() 无 deadline）；兜底/意图分类 0.5B-Q5。14B/30B-Q4 仅作 chat 慢档/离线批量生成背景，**严禁进 12s 决策路**。
- **中央推理队列**：单进程内调度器、三模型预加载常驻（零 load/unload）；每 NPC 一个常驻 KV 槽（社交状态+记忆摘要）→ prompt 短；两级优先级（玩家 chat 高优先可抢占 / NPC 决策低优先可丢弃）；全决策走 GBNF 强约束。
- **7B 当决策模型只在「开 batch 聚合 或 砍 NPC≤6 或 拉长决策间隔」后才成立**（单次 4.8s 达标但 0.5 req/s 稳态会逼近 2 路上限）。**batch 是否可行取决于 NobodyWho 是否暴露真 batch API——未验证，先做 spike。**

## 5. 架构自适应（按后端能力 tier）

把后端字符串升级为**实测画像 tier**：启动 5-shot 探针测 `p50_decide_ms` → `classify()`（`<1.5s→T3 / <6s→T2 / <15s→T1 / else→T0`），换硬件自动归位，不写死后端名。所有参数从 tier 派生：

| 参数 | 派生 | T3(路C) | T2(路A) | T1(路B) | T0(logic) |
|---|---|---|---|---|---|
| DEADLINE_MS | `clamp(6×p50,1500,12000)` | ~3000–5000 | 12000 | 12000 | N/A |
| MAX_INFLIGHT | 单GPU=1 / HTTP=2 | **1**(待验证) | 2 | 1 | N/A |
| 决策间隔/NPC | 反比 p50 | 2–4s | 15–30s | 按需 | ∞ |
| 全镇令牌桶 | ≈1/p50 | ~0.9/s | 低 | 极低 | 0 |
| Director tick | 越快越密 | 5–10s | 30–60s | 按需 | 规则脚本 |
| prompt 缓存 | — | GPU KV 复用前缀 | 服务端 prefix cache | — | — |
| 状态桶缓存 TTL | — | 5–10s | 30–120s(主力提速) | 分钟级 | =policy table |

**冻结红线（与 tier 无关，硬编码 + CI 守）**：① 候选永远引擎枚举，LLM 只 pick；② 20 条不变量/需求/S1/S2 引擎独算，LLM 输出**不得**作其输入；③ 三态 `_wait/{}/intent` 不变；④ **CI 跑 T0-only 回归，拔掉模型必须完整可玩**。
**确定性回放**：LLM 输出当外部 input 记进 `event_log`（`picked` + `cand_hash` + `model_id/prompt_ver/seed/temp` 溯源），引擎主体保持纯确定；双模式 `REPLAY_DETERMINISTIC`（不调模型、放 `picked`、CI 用）/ `REPLAY_LIVE`（重调、标记非确定）；回放断言 `picked ∈ candidates`，否则记 drift + 兜底。

## 6. Roadmap 下一步（杠杆排序）

1. **L1 — Causal Bench**：纯 GDScript 复用确定性引擎、零新依赖。**为什么先做**：没有它，"换后端/换模型/蒸馏"全是盲改；且路C 已基本解决速度，下阶段真问题是**质量与机制正确性的可回归性**。
   - **S0 ✅ 已实现（2026-06-28）**：`bench/Invariants.gd`（20 条不变量抽成单一真相源，sim_soak 与 Harness 共用）+ `bench/Harness.gd`（跨 seed 网格 + 真确定性校验 + JSONL + 红绿门 + nonzero 退出）。实测 **12 seed × 60 天，20/20 全过、确定性 3/3、GATE PASS**——比原单 seed soak 多了跨种子保证。跑法 `tools/bench-godot.ps1`。
   - **S5 ✅ 已实现（2026-06-28）**：`bench/Metrics.gd`（PI 极化 / cascade 谣言级联 / Gini 接纳不平等 + 结果检测器）+ `bench/CausalHarness.gd`（同 seed 同初态、对目标只翻转一个干预位 do(X 高/低)/control，跑确定性轨迹对比；输出 base/do(高)/do(低)/**ACE**/PS/PN + 指标基线；ACE≥0.30 为因果显著门）。跑法 `tools/bench-godot.ps1 -Suite S5`。实测 8 seed×40 天 **GATE PASS**，并挖出真机制洞见：
     - **standing→放逐 ACE=1.00（PS 7/7、PN 1/1）**：持续坏名声对放逐既必要又充分；但**一次性坏名声会被引擎"每3天向0漂移"的 GTFT 宽恕冲掉 → 放逐是暂态的**（这正是 bench 的价值：量化出"宽恕让放逐不持久"）。
     - **开放(xi)→观点迁移 ACE=0.75**：FJ 易感度是观点是否随大流的强因。
     - **trust→投资 ACE=0.62（PN 5/5、PS 0/3）**：高 trust 是投资的**必要非充分**条件——拦截 trust 全挡投资，但单加 trust 不够（还需机会/礼物）。
     - 系统指标基线：PI≈0.24、cascade≈2.75、Gini≈0.075（换后端/改机制后这些应稳定，作回归参照）。
   - **S5 后端矩阵 ✅ 已实现（2026-06-28）**：`bench/BackendBench.gd`+`scenes/backend_bench.tscn`（scene 模式，autoload 可用）+ AIBackend 加合法率埋点 `stats{fired,landed,bad_parse,timeout}`。跑选定后端×seed 网格，量**合法率/截止线命中率 + PI/cascade/Gini + 采样真台词**。logic/mock 容器跑、slm 本机原生 `--gpu` 跑。实测矩阵：

     | 后端 | 网格 | 合法率 | 截止线命中 | PI | cascade | Gini |
     |---|---|---|---|---|---|---|
     | logic | 4s×40d | —(无模型) | — | 0.240 | 2.75 | 0.078 |
     | mock | 4s×40d | 97.1% | 99.9% | 0.280 | 1.75 | 0.026 |
     | slm·GPU | 1s×8d* | **99.6%** | 99.2% | —* | —* | —* |

     *slm 为短网格(量合法率/口吻用)，宏观不可与上比。**关键发现**：(a) **合法率 ~97–99.6% 的损失主因不是模型错误而是「异步陈旧」**——决策延迟期间候选集变了→pick 过期→兜底（mock 也有 ~3%）；GBNF 已保证结构。可优化点：resolve 时对**最新**候选重校验/重映射。(b) **异步管线本身轻微扰动宏观**（mock cascade 2.75→1.75、Gini 降）——与决策质量无关，源自时序/陈旧；4 seed 噪声大，需更多 seed 分离。
2. **L2 — Prompt 工程触顶 ✅（2026-06-28）**：用 BackendBench 量化路C 1.5B 的 gap 并做了一轮 before/after。**结论：合法率已到顶（GBNF 保证结构，prompt 提不动），真 gap 是人设深度/grounding。** 一轮改进（system prompt 加「只用中文不夹英文 + 贴合人设与当下处境、避免泛泛天气寒暄」）实测：合法率 **98.5%→99.6%**、**中英混（"plaza"）消失**、grounding 明显改善（阿丽提"咖啡馆又热闹"、老邓"小子你今天又在船上干啥"、可可"我得赶紧画下来"，从前全是泛泛晒太阳）。**残余 gap = 偶尔泛化重复 + 自指混淆 = 1.5B 天花板** → 正是 L3 蒸馏/换 3B 该买的（再次印证「速度已达标，蒸馏买质量」）。
3. **L3 — 蒸馏/微调 ✅ 管线已搭并小批验证（2026-06-28）**：
   - **✅ 已采纳零训练方案：默认升 3B（2026-06-28）**：`AIBackend.slm_model_path` 已改为 `qwen2.5-3b-instruct-q4_k_m.gguf`（~2GB 已入 `game/models/`，1.5B 保留为轻量备选）。395 GPU 实测经 capability 探针 `tier=fast p50=557ms`、3.40B 正常加载落地。中端 780M ~2.9s、质量肉眼优于 1.5B（§12.2b）。**蒸馏只在「要 1.5B 的速度/体积 + 接近 3B/8B 质量」（如 Steam Deck/移动/极致包体）时才值得。**
   - **蒸馏管线（已落地，端到端验证）**：① `bench/DistillDump.gd`（scene，跑真 sim 导出去重后的真实决策上下文 sys+user+候选，实测导 120 条）→ ② `tools/distill_label.py`（teacher=本机/LAN 8B 打 label，过 `pick∈[0,n)` 合法校验，写 SFT 数据集；**实测 8840U-8B 打 15 条合法率 100%**）→ ③ `tools/distill_train.md`（QLoRA→merge→`convert_hf_to_gguf`→`llama-quantize` Q4_K_M→接 NobodyWho 的完整配方 + bench 验收门）。
   - **买的是质量 + prompt 体积，不是速度**（速度路C 已达标）。⚠️ AMD ROCm 在 Windows 训练支持弱 → 训练阶段建议 Linux(ROCm/CUDA) 或一次性云 GPU（一次性离线成本，运行时仍 100% 本地）。
   - L4 路B CPU 优化：**不做**（§12 已证真实 CPU 1.5–2.5s 够用，弱机才走 logic）。

## 7. 关键警示与待办（诚实清单）

- **～「395 是高端特例、中端未测」已部分解决（§12）～**：中端 Radeon 780M（GPU 1.31s / CPU 2.46s）+ 395 原生 CPU（1.48s）均已实测，§3 档位不再是空中楼阁。**仍待测：Steam Deck（RDNA2 + 其 Vulkan 栈）+ 真·老旧低核 CPU 找 logic 兜底的下界**。§4 的 3B/7B/batch 激进配置仍仅限开发机。
- **MAX_INFLIGHT 现有=2 与 arch 建议=1（单 GPU）冲突**：需实测 NobodyWho 是否有独立 context slot 再定夺。
- **batch 聚合被当成救 7B 的免费午餐，但 NobodyWho 是否支持真 batch 未验证**：先做可行性 spike。
- **DEADLINE 压到 3000ms 偏乐观**：忽略 Vulkan 冷启/冷 KV/模型切换尾延；保守起步 4000–5000ms，按实测尾延收紧。
- **模型热更新/版本漂移**：SLM 换版会破坏 REPLAY_LIVE 与玩家存档预期，需兼容策略。
- **首次加载体验**：~1GB 权重 prefill 的首启延迟/进度反馈未设计，弱机可能劝退。
- **Steam Deck 落点**：保守发行默认档 L(logic) + 「启用实验性本地 AI」设置项，等实测再放开。
- **异步陈旧（bench 实测出的可优化点）**：~2–3% 决策因「fire→resolve 期间候选集变化」而 pick 过期→兜底（mock/slm 都有）。优化：resolve 时拿**最新** `agent_candidates()` 重校验/重映射 pick，或对候选集做语义键而非下标；能把合法率从 ~98% 再抬向 ~100%。

> 演示：[docs/media/slm_gpu_demo.mp4](media/slm_gpu_demo.mp4)（20s，路C 真·嵌入式 GPU SLM 驱动游戏，气泡"阿本，我来啦！"为 SLM 生成的上下文台词）。

## 12. 中端机 / 纯 CPU 实测复盘（2026-06-28）—— 分档结论大反转

> 用户提供的 **Ryzen 7 8840U / Radeon 780M（RDNA3 12CU，32G）** 接局域网，经 LM Studio（同 llama.cpp Vulkan 引擎，tok/s≈嵌入式路C）实测；并在 395 本机原生跑嵌入式 NobodyWho 纯 CPU 对照。探针 `tools/lan_tier_probe.py`。

### 12.1 嵌入式 1.5B-Q4 全机型延迟全景

| 机器 | 算力 | 模式 | 决策 | 对话 | ≤12s |
|---|---|---|---|---|---|
| 395 开发机 | Radeon 8060S 40CU | GPU 原生(NobodyWho) | **1.06s** | 0.24s | ✅ |
| 395 | Zen5 16核 | **CPU 原生(NobodyWho)** | **1.48s** | 0.62s | ✅ |
| 8840U 中端 | Radeon 780M 12CU | GPU(LM Studio) | **1.31s** | 0.80s | ✅ |
| 8840U 中端 | Zen4 8核 | **CPU(LM Studio)** | **2.46s** | 1.21s | ✅ |
| ~~395 容器~~ | 32 vCPU 软渲 | CPU(NobodyWho) | ~~**59s**~~ | ~~42s~~ | ❌ 伪命题 |

### 12.2 三条硬结论（推翻旧分档）

1. **「纯 CPU 太慢(59s)」是 Docker 软渲容器畸形，不是真相**：同机同引擎同模型，**容器 59s vs 原生 CPU 1.48s = 40× 差**（32 vCPU 线程超订 + llvmpipe 环境干扰）。真实现代 CPU 跑嵌入式 1.5B = **1.5–2.5s**。
2. **GPU 非必需、只是加速**：中端机 GPU(1.31s) vs CPU(2.46s) 仅 ~1.9×；高端 395 GPU(1.06s) vs CPU(1.48s) 仅 ~1.4×。**有无 GPU 都远在 12s 线内、都满血可用**——GPU 不再是「能玩/不能玩」的门，只是「更省电/更密集决策」的优化。
3. **分档大幅坍缩**：旧版 S(GPU)/B(降配)/L(无GPU落logic) → 新版基本只有两档：**现代机（2018 年后多核 CPU，有无独显/核显皆可）→ 路C 嵌入式 1.5B（1–2.5s）**；**仅真·极弱/老旧低核 CPU / 移动 / Web → logic 兜底**。"需 GPU"门删除。

### 12.2b 中端机「尺寸→延迟」曲线（8840U / 780M / 8G VRAM，单次决策）

| 模型 | 决策 | 对话 | ≤12s | 质量 |
|---|---|---|---|---|
| 1.5B-Q4 | ~1.3s* | 0.8s | ✅ | 中 |
| **3B-Q4** | **2.9s** (13.3 tok/s) | 1.1s | ✅ | 良（明显更 grounded："去试试那家新开的烤串摊子"） |
| 8B(qwen3)-Q4 | 5.0s (8.9 tok/s) | 2.7s | ✅ | 优（"哎呀小芸！你传夜市的事可真热闹，快说说详情！"） |

\*本轮 1.5B 读数 6.5s 是三模型同载挤 8G VRAM 的争用（被挤去 CPU/冷载）非真值；单独干净载时 1.3s。**复测多模型务必逐个载、避免 VRAM 争用污染读数。**

**结论补充**：**连 8B 在中端核显都 ~5s 跑进 12s 线** → 决策模型尺寸在现代机上**不再受延迟约束（≤8B 都行）**，真约束变成 **VRAM（8B-Q4 ~5–6GB）+ 多 NPC 并发吞吐**。**3B-Q4 是中端甜点**（~2.9s、质量比 1.5B 肉眼可见更好）——**默认从 1.5B 升 3B 是零训练的质量升级**，可能让 L3 蒸馏不再紧迫（详见 §6 L3 触发条件）。

### 12.3 对发行的影响

- **路C 默认 + 内置 1.5B** 的适用面比想象大得多：几乎所有现代 PC（台式/笔记本，核显甚至纯 CPU）都能开箱满血，不必检测 GPU。启动探测从「有没有 Vulkan」简化为「测一发 `p50_decide_ms`，<~5s 就用路C，否则 logic」（即 §5 的 capability-tier 探针，但门槛从硬件特征改为实测延迟，更稳）。
  - **✅ 已实装（2026-06-28）**：`AIBackend.probe_capability()` 启动测 2 发暖决策→`tier`(fast<1.5s/host<6s/slow<15s)+自适应 `deadline_ms=clamp(6×p50,3000,12000)`，`p50>8000ms` 自动降 `backend=logic`。Main 启动 backend=slm/llm 时 await 探测。395 GPU 实测 `tier=fast p50=378ms deadline=3000ms`。
  - **✅ tier→发言密度也已接（2026-06-28）**：`_decide_interval()` 按档定「每 agent 两次 LLM 决策最小 sim-时间间隔」(fast=1/host=½日/slow=1日)，距上次 LLM 不够久就直接走引擎(省 fire+超时)。实测 mock 4800tick×6agent：**fast fired=838 → host 211(−75%) → slow 114(−86%)**，被节流的决策由引擎地板兜住。即 docs/11 §5「亚秒红利用在覆盖率、慢档退稀疏」落地。
- **仍保留** 12s 截止线兜底 + logic 地板 + tier 自适应决策频率（GPU 档可更密）。
- **待补**：Steam Deck（RDNA2 + 其 Vulkan/Proton 栈，需单独实测）；真·老旧/低核 CPU 的 logic 兜底下界（找到「决策 >~5s 该退 logic」的机型分界）。
