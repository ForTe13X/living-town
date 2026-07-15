# docs/23 · 端上混合推理构想（CPU / GPU / NPU）— vision

> 状态：**构想（vision only，不立即建）**。作者提的点子："hybrid slm inference on android apk（cpu，gpu，npu）"。
> 本文由一次多路调研 + 独立对抗校验产出（4 路 survey 中 godot-integration 那路 agent 失败，见 §8 缺口）。
> 前置：[docs/22](22-npu-decision-path.md)（NPU 决策路设计 + 真机 118/294ms 实测）、[docs/13](13-实验札记-experiment-journey.md)（decode-bound 实测、真机 ~60s/724%CPU）。

## 1. 结论先行（诚实版）

**三路 hybrid 不值得做；诚实形态是「静态 2 路」——CPU 扛 decode、NPU 扛 prefill，GPU 一格都不赢。**
且**常见路径上，最朴素的基线（CPU ranker + 冻结 voicebank）直接胜出**：它拿到 100% 的决策延迟收益（亚毫秒）、零 `.so`、完全确定、零热/许可/体积风险、常见台词零推理。
**NPU 只在一个窄niche 里挣到位置**：规则真覆盖不到的 **model-hard 决策**（玩家自由文本 / 涌现新局 / 大世界扩容）。**而且**那处的价值仍押在一个「Phase-0 在规则已覆盖态上并没找到」的质量差上——**未被量化**。

## 2. 物理事实（整个构想的地基）

分水岭只有一条，且**不可协商**：

| | prefill | decode |
|---|---|---|
| 性质 | **compute-bound**（算术强度高、一批 token 复用权重） | **memory-bandwidth-bound**（每步一次 KV 读、零复用） |
| 谁能救 | 上算力（NPU 的理想工况） | **没有芯片能救——只有"少吐几个 token"能救** |

叉乘各处理器的形状：

- **NPU（Hexagon HTP v79）**：prefill-**强** / decode-**弱**。
- **CPU（Kryo）**：灵活基线，**decode 赢家**。
- **Adreno-830 GPU**：prefill ≈ CPU 级（Genie ~1600 tok/s vs Adreno ~330）、decode **比 CPU 还差** → **一格都不赢**。

→ 所以这不是"动态路由器"，是**按工况静态切分**（hybrid-by-workload-split）。

## 3. 路由表（构想）

| 工况 | 落到哪 | 为什么 | 兜底 |
|---|---|---|---|
| **闭集决策**（prefill-bound、~0 decode）· **默认** | **CPU** — Tier-1 蒸馏 GBDT ranker，~50 行整数 GDScript 前向过引擎已算好的 ~55-65 维候选特征 → argmax（复用 `_rng_at` 平手） | 决策 = pointwise rank = **分类，不是语言**；特征引擎本来就在算 | Tier-0 logic 地板（canonical） |
| **model-hard 决策**（玩家自由文本/涌现新局/大世界）· **旗舰·opt-in** | **NPU（HTP v79）** — Genie/QAIRT、Qwen2.5-0.5B W4A16、**prefill-only + 候选 token-id 上 masked argmax**，跑成常驻 localhost 原生服务 | prefill-强/decode-弱正好吃「1 次 prefill + ~0 decode」的选号；真机实测 118/294ms | Tier-1 ranker → logic 地板（probe/demote/预算门） |
| **常见台词/玩家闲聊**（decode-bound）· **默认** | **无推理** — 冻结 voicebank（离线 70B 著作、persona+情境键、纯查表） | decode 在三种处理器上都是带宽墙，**换硅片救不了台词** | `_canned_reply` 人设兜底 |
| **动态台词**（仅真·新局）· 稀有 opt-in | **CPU decode**（占大头 2.4-4.9s）+ 可选 NPU 加速那一次 prefill | CPU 赢 decode；NPU 只削掉 ~200ms prefill——**边际收益** | 冻结 voicebank → 罐头 |
| **后台反思/离屏老化**（容忍延迟、可批） | **CPU** 低优先、L5 预算门、离关键路径 | 非玩家可见，压力大时可丢 | 直接丢 / 地板洞察 |
| **Adreno GPU**（任何工况） | **默认不用**——仅 fallback 层 | 一格不赢：prefill 输 NPU、decode 输 CPU，还抢 Godot 渲染预算 | CPU |

## 4. 运行时版图（2026-07 实况）

**★ 最大变化（推翻 docs/22 的一条）**：**llama.cpp 现在一份 build 就能同时上 CPU + Adreno(OpenCL) + Hexagon(HTP v79)**（上游 `docs/backend/snapdragon/`，HTP 库按 v73/v75/v79/v81 运行时选，日志打 "Hexagon Arch version v79"；Llama-3.2-1B Q4_0 实测 ~136 tok/s prefill / ~51 tok/s decode，17/17 层 offload；标注 **experimental**）。docs/22 里"llama.cpp = CPU+OpenCL、无 NPU"**已过时**。
**但**：它的 HTP 后端**并不 license-clean**——`libggml-htp.so` 建在高通 dspqueue 上、build+运行都要 QNN SDK，等于把 docs/22 CLAIM 6 标红的那块**专有 blob 又请回来**（CPU / OpenCL 两条腿仍干净）。

| 运行时 | 够到哪几个 | 许可 | 对我们的用处 |
|---|---|---|---|
| **QNN/QAIRT（+Genie 跑 LLM）** | **CPU+GPU+NPU**（三个 backend `.so`，唯一真·三路调度器） | 专有 | 旗舰 NPU 腿（已在真机验过） |
| **llama.cpp** | **CPU+GPU+NPU**（一份 build；NPU=experimental 且拖专有 blob） | MIT（NPU 腿除外） | 现役 CPU 腿（NobodyWho 就是它）；NPU 腿观望 |
| ONNX Runtime + QNN EP | CPU+NPU（LLM）；GPU 仅 preview/CV | permissive | 备选 |
| MNN | CPU+GPU（LLM）；**NPU 仅 CV 模型** | Apache-2.0 | 不解决决策上 NPU |
| MLC-LLM/TVM | CPU+GPU（无 NPU） | Apache-2.0 | — |
| ExecuTorch | CPU+NPU（无统一 GPU LLM 路） | BSD | 备选 |

## 5. 红线：确定性**早已在代码里中和**（最大的去风险，非愿景是实证）

对抗校验判定 **SUPPORTED（blocker 级）**：把决策路由到 NPU / GPU / CPU **不可能动 digest**——因为浮点非确定性在引擎里已被量化掉：

- `event_digest`（`Sim.gd:1990-1991`）**只折 7 个离散字段**（`id:type:actor:target:accepted:subject:tick`）——**从不折 logits / say 文本**；
- **argmax 把任何浮点路径塌成一个整数下标**；
- `_record_decision` 存 `{tick, agent, pick:int, cand_hash}`；`_resolve_replay` 读回那个整数、返回 `cands[pick]`。

→ 我先前设想的"record-and-replay 调和"**本来就在代码里**。RL2（无模型可玩）也自然成立：Tier-0 logic 地板恒在、`backend=null`。

## 6. 接入路径（reuse-first，新面最小）

1. **Tier-1 ranker = 新 `ranker` 后端**：纯 GDScript ~50 行整数前向，权重当**数据**发（`utility.json`/`voicebank.json` 的路子），塞在现成 `probe_capability`/demote/L5 预算门**后面**，pick 记进 decision_trace。**零 `.so`、零导出改动。**
2. **旗舰 `npu` 后端**：**复用已有的异步 localhost 机器**——`AIBackend.gd` 早有 `llm` 后端打 `HTTPRequest → 127.0.0.1`（`_fire_http`），且**本会话刚建的 `(epoch,req_id)+候选快照` 生命周期正好是它需要的协议**；NPU 侧把姊妹 lab 已在**这台手机上跑通**的 `genie-t2t-run` 起成常驻服务即可。

## 7. 分阶段（每步都可停）

| 阶段 | 状态 | 交付 |
|---|---|---|
| **P0 质量 bake-off** | **✅ 已做** | 蒸馏机制证成（tiny ranker 复现教师 57.6%）；但教师在规则已覆盖态上**平淡 need-greedy、logic 胜** |
| **P1 出 Tier-1 CPU ranker** | ⭐ **下一步（最小最干净）** | `ranker` 后端 + 权重数据 + 门后接线 + trace |
| **P2 NPU 真机 spike** | **✅ 首轮已做** | 真实 ~327-tok 候选 prompt 上 HTP：118ms 典型 / 294ms 最坏 |
| **P3 Tier-2 NPU-LLM** | ⏳ **条件触发** | 仅当 (a) model-hard 上真出现对地板的质量差 **且** (b) masked-argmax E2E 在真机跑通 |
| **P4 统一 llama.cpp Snapdragon** | 🔭 观望 | 若其 Hexagon 后端成熟且打平/超过 Genie 的 118/294ms，则合并成一份 MIT build |

## 8. 诚实边界与缺口

- **NPU 决策延迟（118/294ms）已在真机证实；但 masked-argmax 的端到端**（护栏采样真正生效）**尚未在真机跑通**（对抗判定：mixed）。
- **model-hard 的质量差未量化**——这正是评审 Phase-4「盲测三档、看玩家价值」要回答的，也是 P3 的开关。
- **能耗**：NPU 那一腿把电耗抬 22-51%（8-Gen3 数），只为在 2.4-4.9s 的台词里省 ~200ms prefill → 台词上 NPU **不划算**。
- **调研缺口**：4 路 survey 中 godot-integration 那路 agent 失败（schema retry 超限），本文 §6 的接入判断由其余 3 路 + 现有代码推得，未经独立复核。

## 9. 一句话

> **别造三路路由器。** 造「**CPU ranker + 冻结 voicebank**」这条又快又确定又零依赖的默认路；把 **NPU 留给规则真的够不到的那一小撮 model-hard 决策**，并且**先证明那里真有质量差**再动手。GPU 这条腿，除非将来出现「既非纯 prefill、又非小 decode」的中批量工况，否则**永远不必接**。
