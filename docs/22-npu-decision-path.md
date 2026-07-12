# docs/22 · 端上决策加速：两层决策栈（蒸馏 ranker + NPU-LLM）+ 红线对账 + 对抗验证

> 旗舰野心：让**每个 NPC 的决策**在端上快到能实时跑。本文是一次穷举式探索（7 路调研 → 综合 → 对每条承重假设做 3 镜对抗验证，`npu-decision-explore` workflow，29/32 agent、~2.28M token）的落地结论。**自由设计、以 Living Town 自身红线为准**；姊妹 lab `edge-npu-8elite` 仅作参考、不受其框架约束。

## 0. 核心 reframe（4 路独立收敛、码内已核实）
**决策 = 从 N 个合法候选里挑 1 = 闭集 pointwise rank = 分类，不是语言。** 引擎**早已**为每个候选算好特征：`Sim._logic_decide`（`Sim.gd:2079-2091`）字面就是 `argmax(score + _rng_at(i*7+1,who).randf()*0.5)`，每个候选带 `score/kind/action/targeted-need/global-needs/time-phase/relationship/persona` 等 ~55-65 维。把这个「挑一个」路由进 1.5B 语言模型的 prefill，正是 docs/21 端上 **5.2s 暖 / 12.7s 冷**（prefill-bound、decode 仅 ~14%）的根因——**拿语言模型做一件分类的事，是过度杀**。

推论：**~100ms 级决策根本不需要 NPU**。一个蒸馏小 ranker 在游戏本就在用的 CPU 上就是 sub-ms。NPU-LLM 是「开放式推理」的对的工具，不是「提速」的必需品。

## 1. 两层决策栈（叠在不动的 logic 地板上，质量优先排序）

| 层 | 是什么 | 延迟 | 红线 | 状态 |
|---|---|---|---|---|
| **Tier 0**（金标准，不动） | 纯 GDScript 效用引擎 `argmax(score+jitter)`；CI `backend=null`、S0 seed12=`3858030099` 逐字节 | — | 全净 | 已有 |
| **Tier 1**（首发·主力 flavor） | 蒸馏 **tiny ranker**（首选 GBDT 整数分裂表 / 备选 64-64-32-1 MLP ~4-6K 参）跑引擎**已算好**的特征向量 → 候选上 argmax、复用 `_rng_at` 平手。**纯 GDScript 前向、零 .so、自训权重、可整数字节精确** | **sub-ms（CPU）** | **全净** | 待建 |
| **Tier 2**（愿景·NPU flavor，opt-in、**有条件**） | **Qwen2.5-0.5B W4A16** 在 Hexagon HTP v79 上**只跑 prefill**、经 Genie 自定义 sampler 对候选 token-id 做 masked argmax；作为**独立端上 native 服务**，复用现有 localhost `llm` 后端 | ~150-300ms（**未实测**） | 有 blocker（见 §4） | 有条件 |

两层都是现有 `probe/demote/fallback` 门后的 opt-in 后端，整数 pick 均记入 `decision_trace` 供逐字节回放。

## 2. 红线对账（RL1 码内已解决——这是最大 de-risk）
- **RL1 确定性 / 逐字节回放：不被任何一层破坏，且对账机制码里已存在**（对抗验证 CLAIM 1 三镜 SUPPORTED、blocker 级）。`event_digest`（`Sim.gd:1990-1991`）只折 `id:type:actor:target:accepted:subject:tick` 七个**离散**字段——**从不折 logits / say-text / note / witnesses**。故 argmax 一挑出整数 index，所有 NPU/GPU 浮点非确定性**当场被量化掉**。`_record_decision` 记 `{tick,agent,pick:整数,cand_hash}`，`_resolve_replay` 读回整数、返回 `cands[pick]` **而不重推**；候选由纯 GDScript 确定性重建，故事件流与 digest 是 `(seed, trace)` 的纯函数、跨设备无关乎浮点噪声。
  - **两种保证别混**：(a) logic 地板的 **seed-only** 字节精确（CI/soak 断言的、`backend=null`）——模型**永不**进这条；(b) 模型会话的 **seed+trace** 字节精确（走 replay）。
  - **唯一要补的线**：`goto_tick` 须 `load_replay(decision_trace)` 且模型会话保持 `record_decisions=true`，否则时间轴 scrub 会重推而发散（机制已有、自动接线是缺口）。`cand_hash` 守卫让过期 trace 安全降级到 logic 地板、而非污染 digest。
- **RL2 无模型可玩**：结构性完好——默认 `logic`、probe 降级、tick 落空回落 `_logic_decide`。
- **RL3 移动端**：Tier 1 KB 级、零热/尺寸成本；Tier 2 加几十 MB 专有 QNN `.so` + sideload 的 W4A16 bundle（24GB RAM 无压力），prefill-burst（~1 decode token）躲开持续 decode 的热崖，且在 HTP 上不抢 Adreno 渲染预算。
- **RL4 版权**：Tier 1 全净（自训权重 + MIT/BSD/Apache 工具）；**Tier 2 唯一红旗**=专有 QAIRT/Genie/QnnHtp `.so`（见 §4 blocker）；权重 Qwen=Apache 净。**绝不从 Llama/Gemma 输出蒸馏 Tier 1**（其条款禁止用输出改进他模型）——只用 70B voicebank 作者 / Qwen-Apache / logic 地板打标。
- **RL5 复用优先**：Tier 1 复用 voicebank 离线著作 pipeline + 现有特征；Tier 2 复用姊妹 lab 已在本机跑通的 binary + 现有 localhost 异步后端。

## 3. 硅 / runtime 现实（调研核实）
- HTP v79（SM8750）**只经 Qualcomm 自家栈可达**（QNN/QAIRT→Genie，或 QNN delegate 挂 LiteRT/ONNX-RT）。**NNAPI 在 Android 15（我们的 targetSdk 35）已弃、静默回落 CPU=死路**（你以为在 NPU、其实没有）。
- dtype：INT4/INT8/INT16/FP16，**静态量化 + 固定 shape 的预编译 context binary**。LLM 最快=W4A16；分类器最快=INT8 权重+INT16 激活。
- **本机已实测的承重数据点**（edge-npu G3）：65-token、think-off 决策 prompt、4B W4A16、Genie/QAIRT 2.45 → TTFT **58.7 / 60.7ms**（1071-1107 tok/s prefill）。**NPU 是 prefill-强、decode-弱**——与手机 CPU 的短板正好互补，故「只 prefill、~0 decode」的决策是 NPU 的理想负载。
- Adreno 830（llama.cpp OpenCL / MLC / ncnn）：GPU prefill 在骁龙上常仅 CPU 同级，抢 Godot 渲染预算，且 NobodyWho Android 构建本就关了 Vulkan → **仅 fallback 档**。实验性 llama.cpp-Hexagon backend prefill ~35-37 tok/s（300-tok≈9s，不过 8s 门）→ 观望。

## 4. 对抗验证结论（8 条承重假设 × 3 镜）
**站住的（可信）**：`event_digest` 只折离散字段→整数 pick digest-invariant（CLAIM 1，三镜 SUPPORTED）；决策=已算好特征上的 pointwise rank（CLAIM 2 核心 SUPPORTED）；record-and-replay 对账 sound（CLAIM 7 确定性镜 SUPPORTED）；现有异步 `llm` 后端可重指向 localhost NPU 服务（`AIBackend.gd:90` 一个 android 门 + `_fire_http`→127.0.0.1，代码核实）。

**被 REFUTED / 亮红的（真警告）**：
- **CLAIM 6（blocker）**：QAIRT/Genie/libQnnHtp `.so` **专有、非 MIT/Apache/BSD** → 违 RL4 字面；**发行前必须核 Qualcomm 实际再分发条款**。这是 Tier 2 **发行**的真门槛（不挡「测量/spike」）。
- **CLAIM 4（REFUTED）**：**masked argmax 在本机尚未被证**——edge-npu 自己的 STATUS.md 明令「不可宣称 masked 已保证」；只有 unmasked 的 float32 logit 访问 + 字节精确 greedy 被证。masked 决策 E2E 谁都没测（edge-npu 押后到 G4）。
- **CLAIM 5（SUPPORTED）**：那 ~60ms 是 65-tok 单发 TTFT，**不是**我们 ~327-tok prompt 的 masked 决策 E2E p50/p95；~150-300ms 是**外推**。
- **CLAIM 3（SUPPORTED ×3）**：**蒸馏 ranker 质量能否匹配/超过 1.5B 与 logic 地板——无人证过**（docs/21 §4 明确押后）。**这是关键未知，且延迟被解决不代表 flavor 值得**。
- CLAIM 8（UNCERTAIN ×3）：热 / 渲染预算——本机未测（NPU 路未建）。

## 5. 分阶段 roadmap（质量优先——先用便宜干净的 Tier 1 回答「语言推理是否值」，再决定贵的 Tier 2）
- **Phase 0 · 质量对拍 + 免费 CPU 赢（离线、无设备，最枢纽最便宜）**
  - (a) **对拍**：logic 地板多 seed 跑、记每个决策点 `{persona,needs,ctx,候选+特征+score}`（仿真便宜确定性、百万态零成本、**过采样危机/冲突稀有态**）→ 采 10-50K 态、同一 70B（voicebank 作者）打「入戏 index」标 → 蒸 GBDT(LightGBM/MIT) 或 MLP(PyTorch/BSD) → **留出集评**：ranker 对 70B 教师的命中率、是否超 1.5B 的 pick、**并挂守恒不变量**（记 2026-07-05 克隆秘密把决策分布挪动→炸掉 #34 money 守恒的教训）。**这个实验决定 Tier 2 是否值得建。**
  - (b) **今天就拿的免费赢**：给现 NobodyWho CPU 路加 1-char GBNF mask（`root ::= [0-9A-Z]`）+ prompt-cache → 零新依赖、当下就保证合法决策。
- **Phase 1 · 出 Tier 1 蒸馏 ranker**：`ranker` 后端（GBDT 整数 eval，~50 行 GDScript 前向），probe/demote 门后 opt-in、pick 记 trace、权重当 data 发（如 `utility.json`/`voicebank.json`）；**真机录一段 sub-ms flavored 决策 clip**（record-on-stage-change）。零 .so、零 export 改动。
- **Phase 2 · NPU-LLM 手机 spike（≈edge-npu G4）+ 审计**：把姊妹 lab 已构建的 `genie-t2t-run` + Qwen2.5-0.5B W4A16 QNN bundle 推上机，喂 **Living Town 真实 ~327-tok 候选 prompt**（逐字、think-off、fail-closed HTP 断言防静默回落）、`--profile ×2` → **本机本 prompt 的真 masked 决策 p50/p95**；并出 QNN v79 `.so` 集的确切 APK/尺寸 + QAIRT 再分发许可对 RL4 的书面裁决。近零新代码、约半天。
- **Phase 3 · Tier 2 opt-in NPU-LLM（有条件：Phase 0 存在质量缺口 ∧ Phase 2 延迟+许可双过）**：`npu` 后端=Genie masked-sampler 服务经现 localhost 后端接入、android 门翻转、`goto_tick` 接 `load_replay`。

## 6. 诚实边界（别外推）
- **枢纽未知是质量、不是延迟**：两层都能解延迟；「语言推理是否比特征 rank 更好」在真 trace 上无人测——Phase 0 先答。
- **本 prompt 的 masked 决策 E2E 谁都没测**；旗舰 60ms 是短 prompt 单发外推。
- **QAIRT/Genie 专有 .so 再分发条款未核**——Tier 2 发行前唯一真 RL4-adjacent 门槛。
- Android :npu 独立进程能否在长会话/低内存下常驻（不靠不可靠的 `OS.create_process`）未证。
- tokenizer 契约须对**实际发的**模型/bundle 重验（G3 只对该 Qwen bundle 验了 0-9/A-Z 单 token）。
- 持续多 NPC 决策节奏下的 HTP 热节流本机未测。

## 7. 结论
**决策=分类不是语言**（edge-npu「决策≠生成」的下一刀），故：**(1) 今天就能上的是 Tier 1 蒸馏 CPU ranker**——sub-ms、红线全净、复用 voicebank playbook、零设备风险；**(2) 确定性红线不是障碍**（码内已把浮点噪声关在 digest 之外）；**(3) NPU-LLM 是旗舰、且在本机独一无二地被 de-risk**（float logit 访问 + 字节精确 greedy 已证、60ms TTFT 已实测），但它是**开放式推理**的对的工具、非提速必需，且有**两个未清 blocker**（专有 .so 许可、masked-E2E 未测）。**最诚实的一句**：想让端上决策又快又聪明，先离线对拍证明「语言到底值不值」+ 白拿 CPU ranker，同时把 NPU 手机 spike 的**真数字**测出来——三者都便宜，之后再用真数据决定要不要建 Tier 2。旗舰野心不变、但按风险与成本正确排序上它。
