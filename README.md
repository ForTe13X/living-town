# 小镇有灵 · Living Town

像素小镇生活模拟原型。居民有需求、记忆、性格和关系，会赴约、爽约、争执、和解，也会形成声誉与派系。底层是一套确定性的社会引擎；本地 LLM/SLM 只负责把引擎给出的合法候选转成台词和选择。

模型不可用时，游戏仍然运行。断网、超时或非法输出都会自动回退到规则决策，因此接入模型只改变表现层，不改变世界状态的可靠性。

![小镇有灵 · 主视觉](docs/media/cover.png)

**English summary**: *Living Town* is a pixel life-sim whose NPC behavior comes from a deterministic needs/utility engine and an event-sourced social layer. A local LLM/SLM can pick from engine-enumerated legal actions and render dialogue, while a rule fallback keeps the simulation non-blocking. The same social substrate is checked by 35 machine-verifiable invariants over 30-day soak runs, replays byte-exactly from any tick, and runs in both a Node port and Godot 4.6.2.

## Current State

- **Deterministic social substrate**: greetings, gifts, gossip, invitations, confrontation, apologies, relationship ledgers, belief boundaries, promises, conflicts, and resolution flow. Relationship changes are linked back to events, so the system can explain why a resident is angry or trusting.
- **Playable shell**: day/night lighting, clock and speed controls, NPC dialogue bubbles and expressions, player-to-NPC free conversation, and a replay observatory for inspecting residents, needs, beliefs, relationships, and conflicts at any tick.
- **Three AI backends**: `logic` for pure rules, `llm` for local OpenAI-compatible services such as LM Studio, and `slm` for embedded GGUF inference through NobodyWho. All backends run the same engine and can fall back safely.
- **Measured local inference**: Qwen2.5-1.5B-Q4 through embedded SLM runs in roughly 1-2.5 seconds on tested consumer GPU/APU machines; 3B is around 2.9 seconds. Startup probes set deadlines from the current machine instead of assuming fixed latency.

Demo videos:

- [Main demo, 3 minutes, Chinese narration with bilingual subtitles](docs/media/living_town_demo.mp4)
- [Factions and alliances](docs/media/s3_social_demo.mp4)
- [Embedded SLM on local hardware](docs/media/slm_gpu_demo.mp4)

![成片字幕样式](docs/media/shot-06-subtitled-demo.png)

## Engineering Design

1. **The model does not mutate state directly.** The engine enumerates legal candidates; the model returns a candidate index and optional dialogue. Invalid output, timeout, or missing service falls back to deterministic rules.
2. **Invariants act as regression gates.** The 30-day soak checks 35 properties of the simulated society, including belief provenance, promise settlement, apology flow, reputation effects, private-channel secrecy, money conservation, and no overdraft. The full list is in [docs/08-测试与验证.md](docs/08-测试与验证.md).
3. **Event sourcing enables replay.** Randomness is derived from `seed + tick + salt`, without wall-clock time or global random state. The same seed produces byte-identical summaries, and the replay observatory rebuilds the world from any tick.
4. **Two runtimes share the same logic.** The Node port gives fast iteration; Godot 4.6.2 runs the actual game shell. Both pass the same invariant suite, separating logic errors from engine integration issues.

## Quick Start

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

## Repository Layout

```text
game/                  Godot 4 project: scripts, data, scenes, and test scenes
  scripts/Sim.gd       World state, ticks, needs/utility AI, legal candidate API
  scripts/AIBackend.gd Pluggable AI backends with timeout and fallback handling
  scripts/Memory.gd    Memory stream retrieval by recency, importance, and relevance
tools/                 Node logic port, soak scripts, recording pipeline
docs/                  Design, architecture, review notes, measurements, and experiments
```

## Documentation

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

## Assets And License

Code is MIT licensed. Pixel assets come from CC0 packs such as Puny World and Characters; sources are listed in [docs/09-美术资产与版权.md](docs/09-美术资产与版权.md). The cover image is AI-generated. Model weights and NobodyWho binaries are not distributed in this repository; fetch them from their upstream sources.

Some documents refer to an upstream game-evaluation pipeline for headless rendering, automated recording, and LLM-as-judge experiments. This repository does not depend on that pipeline at runtime.
