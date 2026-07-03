# 小镇有灵 · Living Town

[中文](#中文) | [English](#english)

## 中文

像素小镇生活模拟原型。居民有需求、记忆、性格和关系，会赴约、爽约、争执、和解，也会形成声誉与派系。底层是一套确定性的社会引擎；本地 LLM/SLM 只负责把引擎给出的合法候选转成台词和选择。

模型不可用时，游戏仍然运行。断网、超时或非法输出都会自动回退到规则决策，因此接入模型只改变表现层，不改变世界状态的可靠性。

![小镇有灵 · 主视觉](docs/media/cover.png)

### 当前状态

- **确定性社会底座**：打招呼、赠礼、八卦、邀约、对质、道歉、关系账本、知识边界、承诺、冲突和解决流程。关系变化能追溯到事件，因此系统能解释一个居民为什么生气或信任某人。
- **可玩外壳**：昼夜光照、时钟与速度控制、NPC 头顶台词和表情、玩家与 NPC 自由对话、回放观察台。可以在任意 tick 检查居民的需求、信念、关系和冲突。
- **三档 AI 后端**：`logic` 纯规则、`llm` 本地 OpenAI 兼容服务、`slm` 通过 NobodyWho 做嵌入式 GGUF 推理。所有后端运行同一套引擎，并能安全降级。
- **本地推理实测**：Qwen2.5-1.5B-Q4 在测试过的消费级 GPU/APU 机器上约 1-2.5 秒完成一次决策；3B 约 2.9 秒。启动探针按当前机器测得的延迟设置 deadline。

演示视频：

- [主演示，3 分钟，中文旁白 + 中英字幕](docs/media/living_town_demo.mp4)
- [派系与盟约](docs/media/s3_social_demo.mp4)
- [嵌入式 SLM 实机驱动](docs/media/slm_gpu_demo.mp4)

![成片字幕样式](docs/media/shot-06-subtitled-demo.png)

### 工程设计

1. **模型不直接改状态。** 引擎枚举合法候选，模型只返回候选 index 与可选台词。非法输出、超时或服务缺失都会回退到确定性规则。
2. **不变量作为回归门。** 30 天 soak 会检查 35 条社会性质，包括信念来源、承诺结算、道歉流程、声誉影响、私聊秘密边界、金钱守恒和不可透支。完整清单见 [docs/08-测试与验证.md](docs/08-测试与验证.md)。
3. **事件溯源支持回放。** 随机性由 `seed + tick + salt` 派生，不依赖墙钟或全局随机。同一 seed 生成逐字节一致的摘要，回放观察台可从任意 tick 重建世界。
4. **双运行时验证。** Node 端口用于快速迭代，Godot 4.6.2 运行实际游戏外壳。两边通过同一组不变量，把逻辑错误与引擎集成问题分开。

### 快速开始

最快验证路径只需要 Node：

```bash
node tools/sim_social_port.mjs --days 30 --seed 20260626 --verbose
```

窗口模式需要 [Godot 4.x](https://godotengine.org/)：

```bash
godot --path game -- --speed 2.0
```

操作：空格暂停，`1/2/3/4` 调速，滚轮缩放，点击居民打开状态，拖动时间轴回放。选中居民后可在底部输入框对话。

CI 可用的 headless soak：

```bash
godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30
```

可选本地模型后端：

- `--backend llm`：启动 LM Studio 或其他 OpenAI 兼容本地服务，默认 `localhost:1234`，并加载指令模型。
- `--backend slm`：把 [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) 放到 `game/addons/nobodywho/`，把 GGUF 权重放到 `game/models/`，例如 Qwen2.5-1.5B-Instruct-Q4_K_M。

接线细节见 [docs/03-LLM集成架构.md](docs/03-LLM集成架构.md)。硬件实测见 [docs/11-LLM部署实测对比与选型.md](docs/11-LLM部署实测对比与选型.md)。

### 目录

```text
game/                  Godot 4 工程：scripts、data、scenes 与测试场景
  scripts/Sim.gd       世界状态、tick、需求/效用 AI、合法候选 API
  scripts/AIBackend.gd 可插拔 AI 后端，处理超时与降级
  scripts/Memory.gd    按 recency、importance、relevance 检索记忆流
tools/                 Node 逻辑端口、soak 脚本、录屏流水线
docs/                  设计、架构、评审、实测与实验记录
```

### 文档

| 文档 | 内容 |
|---|---|
| [01 产品愿景与玩法](docs/01-产品愿景与玩法.md) | 游戏概念、核心循环、不做什么 |
| [02 技术架构](docs/02-技术架构-混合仿真.md) | 确定性引擎 + LLM 表现层 |
| [03 LLM 集成](docs/03-LLM集成架构.md) | 后端、结构化输出、超时与降级 |
| [07 社交底座](docs/07-技术文档-社交底座.md) | 社交事务、关系、信念、承诺与冲突 |
| [08 测试与验证](docs/08-测试与验证.md) | 不变量、双运行时检查与复现方式 |
| [11 部署实测](docs/11-LLM部署实测对比与选型.md) | 多机器、多模型尺寸的延迟数据 |
| [13 实验札记](docs/13-实验札记-experiment-journey.md) | 按时间记录的实验过程 |

其他规划、研究、规模化和移动端可行性记录在 [docs/](docs/) 下。文档主要为中文。

### 素材与许可

代码使用 MIT License。像素素材来自 Puny World、Characters 等 CC0 资源包，来源列在 [docs/09-美术资产与版权.md](docs/09-美术资产与版权.md)。封面为 AI 生成。模型权重与 NobodyWho 二进制不随仓库分发，请从上游获取。

部分文档会提到一个上游游戏评测流水线，用于 headless 渲染、自动录屏与 LLM-as-judge 实验；本仓库运行时不依赖该流水线。

## English

*Living Town* is a pixel life-sim prototype. Residents have needs, memories, personalities, and relationships. They can keep or break appointments, argue, reconcile, build reputations, and form factions. The foundation is a deterministic social engine; a local LLM/SLM only turns engine-enumerated legal choices into dialogue and selection.

The game keeps running when the model is unavailable. Network failures, timeouts, or invalid outputs fall back to rule decisions, so model integration changes presentation rather than state reliability.

![Living Town cover](docs/media/cover.png)

### Current State

- **Deterministic social substrate**: greetings, gifts, gossip, invitations, confrontation, apologies, relationship ledgers, belief boundaries, promises, conflicts, and resolution flow. Relationship changes are linked back to events, so the system can explain why a resident is angry or trusting.
- **Playable shell**: day/night lighting, clock and speed controls, NPC dialogue bubbles and expressions, free player-to-NPC conversation, and a replay observatory for inspecting residents, needs, beliefs, relationships, and conflicts at any tick.
- **Three AI backends**: `logic` for pure rules, `llm` for local OpenAI-compatible services, and `slm` for embedded GGUF inference through NobodyWho. All backends run the same engine and can fall back safely.
- **Measured local inference**: Qwen2.5-1.5B-Q4 through embedded SLM runs in roughly 1-2.5 seconds on tested consumer GPU/APU machines; 3B is around 2.9 seconds. Startup probes set deadlines from the current machine.

Demo videos:

- [Main demo, 3 minutes, Chinese narration with bilingual subtitles](docs/media/living_town_demo.mp4)
- [Factions and alliances](docs/media/s3_social_demo.mp4)
- [Embedded SLM on local hardware](docs/media/slm_gpu_demo.mp4)

![Subtitle style from the rendered demo](docs/media/shot-06-subtitled-demo.png)

### Engineering Design

1. **The model does not mutate state directly.** The engine enumerates legal candidates; the model returns a candidate index and optional dialogue. Invalid output, timeout, or missing service falls back to deterministic rules.
2. **Invariants act as regression gates.** The 30-day soak checks 35 properties of the simulated society, including belief provenance, promise settlement, apology flow, reputation effects, private-channel secrecy, money conservation, and no overdraft. The full list is in [docs/08-测试与验证.md](docs/08-测试与验证.md).
3. **Event sourcing enables replay.** Randomness is derived from `seed + tick + salt`, without wall-clock time or global random state. The same seed produces byte-identical summaries, and the replay observatory rebuilds the world from any tick.
4. **Two runtimes share the same logic.** The Node port gives fast iteration; Godot 4.6.2 runs the actual game shell. Both pass the same invariant suite, separating logic errors from engine integration issues.

### Quick Start

The fastest validation path only needs Node:

```bash
node tools/sim_social_port.mjs --days 30 --seed 20260626 --verbose
```

Windowed mode requires [Godot 4.x](https://godotengine.org/):

```bash
godot --path game -- --speed 2.0
```

Controls: space pauses, `1/2/3/4` changes speed, mouse wheel zooms, clicking a resident opens state, and the timeline scrubs replay. After selecting a resident, type in the bottom input to talk.

Headless soak run for CI:

```bash
godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30
```

Optional local model backends:

- `--backend llm`: start LM Studio or another OpenAI-compatible local service at the default `localhost:1234`, then load an instruction model.
- `--backend slm`: install [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) under `game/addons/nobodywho/` and place a GGUF model, such as Qwen2.5-1.5B-Instruct-Q4_K_M, under `game/models/`.

Integration details are in [docs/03-LLM集成架构.md](docs/03-LLM集成架构.md). Hardware measurements are in [docs/11-LLM部署实测对比与选型.md](docs/11-LLM部署实测对比与选型.md).

### Layout

```text
game/                  Godot 4 project: scripts, data, scenes, and test scenes
  scripts/Sim.gd       World state, ticks, needs/utility AI, legal candidate API
  scripts/AIBackend.gd Pluggable AI backends with timeout and fallback handling
  scripts/Memory.gd    Memory stream retrieval by recency, importance, and relevance
tools/                 Node logic port, soak scripts, recording pipeline
docs/                  Design, architecture, review notes, measurements, and experiments
```

### Documentation

| Document | Contents |
|---|---|
| [01 产品愿景与玩法](docs/01-产品愿景与玩法.md) | Game concept, core loop, and non-goals |
| [02 技术架构](docs/02-技术架构-混合仿真.md) | Deterministic engine with LLM as presentation layer |
| [03 LLM 集成](docs/03-LLM集成架构.md) | Backends, structured output, timeout, and fallback |
| [07 社交底座](docs/07-技术文档-社交底座.md) | Social transactions, relationships, beliefs, promises, and conflicts |
| [08 测试与验证](docs/08-测试与验证.md) | Invariants, dual-runtime checks, and reproduction steps |
| [11 部署实测](docs/11-LLM部署实测对比与选型.md) | Measured latency across machines and model sizes |
| [13 实验札记](docs/13-实验札记-experiment-journey.md) | Chronological experiment notes |

Other planning, research, scaling, and mobile feasibility notes live under [docs/](docs/). Documentation is primarily in Chinese.

### Assets And License

Code is MIT licensed. Pixel assets come from CC0 packs such as Puny World and Characters; sources are listed in [docs/09-美术资产与版权.md](docs/09-美术资产与版权.md). The cover image is AI-generated. Model weights and NobodyWho binaries are not distributed in this repository; fetch them from upstream sources.

Some documents refer to an upstream game-evaluation pipeline for headless rendering, automated recording, and LLM-as-judge experiments. This repository does not depend on that pipeline at runtime.
