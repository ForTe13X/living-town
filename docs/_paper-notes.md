# 论文/外部 idea 评估笔记（side discussions）

> 非主线路线图，记录读过的外部论文/想法对本项目是否有用、借哪点、为何 SKIP。供后人查档。

## Warp-Cortex（arXiv:2601.01298v1，单作者 preprint，Warp Research，2026-01）— 对 agent concurrency 助益评估

**论文做什么**：在一张消费级 GPU 上**密集并发**跑很多 LLM 推理线程，给一个主 agent 配一群 System-2 副推理 council。手段：① Singleton 权重共享(O(1) 权重)；② Topological Synapse——TDA witness-complex 把每 agent 的 KV-cache 压成 k 个 landmark token(O(N·k)，98% 压缩)；③ River/Stream CUDA 流并发；④ 验证门(hidden-state cosine 拒劣质思维，θ=0.5)；⑤ Referential Injection(RoPE 虚位把副思维注入主 KV 不打断生成)。实测 100 个 0.5B agent @ 2.2GB VRAM(RTX 4090)。

**结论：对本项目 agent concurrency 基本不适用——优化的是相反的轴。**
- Warp-Cortex = "一个决策者 + 密集并发深推理 council"（认知**密度**）；本项目 = "很多独立 NPC 各自**稀疏**决策，引擎当地板、LLM 是可 ablate 的皮肤"（认知**稀疏**）。并发层对立诉求。
- 其核心实现需**原生 PyTorch/CUDA 模型访问**（改 KV-cache、CUDA streams、hidden-state 门）；本项目栈 = LM Studio(HTTP) + NobodyWho(llama.cpp GDExtension)，取不到这些。采纳=换推理栈=破确定性/破 GDScript/破"无模型可玩" → 落 **SKIP**（同 ECS-Rust）。
- 它的目标 regime（百万 agent / 密集 System-2）正是 docs/10 §F、docs/12 已明确 SKIP 的大 N 过度工程。

**逐条对照**：
| 机制 | 对我们 |
|---|---|
| Singleton 权重共享 | ✅ 已在做（NobodyWho 共享一个 model、LM Studio 一个服务）——**反向印证方向对** |
| CUDA-stream 密集并发 | ❌ 我们要稀疏(MAX_INFLIGHT=2+队列+截止线兜底)，且 Vulkan 不暴露多流并发 decode |
| TDA KV landmark 压缩 | ❌ moot：我们 prompt 短+并发~2+无状态重 prompt(summarize-and-forget)，且需原生 KV 访问 |
| 验证门(cosine) | ↔ 我们有更强**结构版**：合法候选契约，模型根本造不出非法动作，无需 hidden state |
| Cortex Router(regex JIT spawn) | ↔ 已有等价(option==null+未节流 fire 异步决策) |
| Referential Injection | ❌ 需原生连续生成流可注入，HTTP/文本 API 无 |

**可借的 2 点（理念级，非实现）**：
1. *若*将来要让很多 NPC 共享一块常驻"小镇态"KV，"只留 k 个显著 token"是真技术——但需原生 KV 访问(NobodyWho 不暴露)，目前不可落地；我们的无状态短 prompt+记忆流反而更利确定性回放，主动绕开了它要解的问题。
2. River+Streams = "一个决策配一个核查 council"——对 NPC 普通决策杀鸡用牛刀；但对 docs/03 §4 稀有的**导演**调用，配个小 verify-council 提质量是可选未来点（**质量**改进，非 concurrency）。

**论文成熟度**：单作者 preprint；"1000+/百万"是理论外推，实测只到 100 个 0.5B 测**显存**(未测 council 推理质量/延迟/正确性)；其"agent"是推理线程非自主 NPC。打折看。

**最终**：concurrency 已收敛方案(中央优先队列+MAX_INFLIGHT+capability tier+令牌桶+LOD+logic 地板, docs/12 L5)不因这篇改。价值=反向印证"权重共享+稀疏+引擎兜底"方向 + 一个"导演核查 council"可选未来点。
