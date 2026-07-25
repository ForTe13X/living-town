# Living Town

[中文](README.md) · [Documentation index](docs/README.md)

[![CI](https://github.com/ForTe13X/living-town/actions/workflows/ci.yml/badge.svg)](https://github.com/ForTe13X/living-town/actions/workflows/ci.yml)

*Living Town* is a pixel life-sim prototype. Residents have needs, memories, personalities, and relationships. They can keep or break appointments, argue, reconcile, build reputations, and form factions. The foundation is a deterministic social engine; a local LLM/SLM only turns engine-enumerated legal choices into dialogue and selection.

The game keeps running when the model is unavailable. Network failures, timeouts, or invalid outputs fall back to rule decisions, so model integration changes presentation rather than state reliability.

![Living Town · live demo](docs/media/town_demo.gif)

> Recorded on a physical Android device (`logic` backend): after nightfall, residents keep appointments, chat, spread gossip, and fall out — every step driven by the same deterministic social engine.

![Living Town cover](docs/media/cover.png)

## Current State

The **world and social systems** below all ship, and each has a CI gate behind it — the ones citing an invariant number are guarded by [`game/bench/Invariants.gd`](game/bench/Invariants.gd), the rest by the data lint, map audit, and 6 integration scenes in `tools/ci.sh`. The last three entries (shell, backends, inference latency) are measurements, not invariants.

- **Deterministic social substrate**: greetings, gifts, gossip, invitations, confrontation, apologies, relationship ledgers, belief boundaries, promises, conflicts, and resolution flow. Relationship changes are linked back to events, so the system can explain why a resident is angry or trusting.
- **A generated town**: a 64×48 grid with 8 districts where **walkability is authoritative data** and pathfinding is a deterministic A\*. `tools/audit_map.py` is a CI gate built for exactly this — it checks typed-layer consistency, full reachability, that every piece of furniture has a reachable interaction tile, and that districts have ≥2 distinct routes.
- **Multi-floor interiors**: all seven buildings have data-driven interiors (`game/data/interiors.json`); residents actually walk in, go upstairs, and go home to sleep. Not a backdrop.
- **Jobs, shifts and wages**: `game/data/jobs.json` + `skills.json`, with skill level feeding wages.
- **A money economy**: prices, wages, a town treasury, a poverty line. Guarded by **hard** invariants #34 (money conservation) and #35 (non-negative balances, no overdraft).
- **Weather and seasons**: types and utility multipliers in `game/data/weather.json`.
- **Festivals**: world objects spawn and despawn on schedule; hard invariant #36 guards pairing with no residue.
- **Elections**: periodic votes; hard invariant #37 guards tally consistency.
- **An emergent social layer**: reputation and gossip cascades, opinion factions, mutual-aid pacts (with GTFT forgiveness and free-rider dissolution), and secrets that get confided, leaked, and betrayed.
- **Playable shell**: day/night lighting, clock and speed controls, NPC dialogue bubbles and expressions, free player-to-NPC conversation, and a replay observatory for inspecting residents, needs, beliefs, relationships, and conflicts at any tick.
- **Three AI backends**: `logic` for pure rules, `llm` for local OpenAI-compatible services, and `slm` for embedded GGUF inference through NobodyWho. All backends run the same engine and can fall back safely.
- **Measured local inference**: Qwen2.5-1.5B-Q4 through embedded SLM runs in roughly 1-2.5 seconds on tested consumer GPU/APU machines; 3B is around 2.9 seconds. Startup probes set deadlines from the current machine.

**What is not there yet** (see [docs/05](docs/05-路线图与里程碑.md)): the game is **completely silent** (no audio of any kind); on a phone it can be watched but not played (all 7 player verbs are keyboard-only); the five most dramatic social event types currently **never reach the event log**; and the warm half of the social sim runs cold (a default month-long run produces 2 dates, 0 pacts, 0 aid).

Demo videos, newest build first:

- [New systems tour: economy / weather / festivals / elections](docs/media/new_systems_demo.mp4) (2:25)
- [World systems: map, pathfinding, districts](docs/media/world_systems_demo.mp4) (0:35)
- [Elections](docs/media/election_demo.mp4) (1:35)
- [Multi-floor interiors, stage 2](docs/media/interior_stage2_demo.mp4) (1:10)
- [Interior rooms](docs/media/interior_rooms_demo.mp4) (0:25)
- [A 70B model as the director layer](docs/media/director_70b_demo.mp4) (1:06)
- [Player agency](docs/media/player_agency_demo.mp4) (0:30)

![Current build: the Town Chronicle](docs/media/town_chronicle.gif)

> Desktop capture (`logic` backend, [full 0:60 clip](docs/media/town_chronicle_demo.mp4)). Bottom-left is the **Town Chronicle**: what the engine does is split into "big news" and "recent", written as prose (`苏琴 rallied 1 person to pressure 可可`) instead of printing raw event enum ids. That panel previously could only narrate greetings; betrayals, pacts, elections, grudges and reconciliations now surface on their own.

Older clips, kept for history (they look noticeably different from the current build):
[main demo, 3:52, Chinese narration with bilingual subtitles](docs/media/living_town_demo.mp4) ·
[factions and alliances](docs/media/s3_social_demo.mp4) ·
[embedded SLM on desktop](docs/media/slm_gpu_demo.mp4) ·
[SLM voice](docs/media/voice_gpu_demo.mp4)

## Technical Highlights & Innovations

**1. Deterministic and observation-independent: how the town lives does not depend on where you look.**
The decision logic uses no wall-clock time and no global random — all randomness is stably derived from `seed + tick + salt(+agent)` (never wall-clock or a global RNG). The same seed is byte-identical, and the replay observatory reconstructs the world exactly from any tick. A stronger red line: **rendering may follow the camera, but the simulation LOD that decides *who* gets simulated in detail must not depend on it** — otherwise the same save viewed differently would replay a different history. This observation-independence runs through the whole engine.

**2. An observation-independent aggregate LOD (the focus of this stage).**
Scaling the town to hundreds of residents means reducing fidelity for distant ones; the hard part is that a conventional LOD keyed on camera distance would make history depend on the observation path, breaking the determinism red line above. So the full-detail cohort is chosen entirely from committed simulation state (who is doing work / a stateless rotation / near the player), never from the camera (the one older conservative branch that dims by camera radius is bench-diagnostic only, not shipped). It passes six checks: byte-identical when off, **camera-path invariance** (5 fixed `lod_focus` values → one digest), deterministic across save/load and fresh-vs-restart, hard invariants at scale, honest cost, and a liveness floor — of which camera-path invariance and determinism are wired into CI as permanent gates.
> Stated honestly: this is an **observation-independent prototype**, not "hundreds of NPCs delivered." Microsecond profiling on a real phone showed the two dominant costs are **the sim tick (~64ms) and per-agent/social drawing (~60ms)** — together roughly ¾ of the frame — with the rest being per-frame overhead and a small amount of static redraw. The LOD only cuts the sim-tick part, so it is not a sufficient fix; the other half needs render culling. The methodological lesson (in [docs/33](docs/33-viewer-independent-lod-delivery.md)): **don't infer the bottleneck, instrument and measure it** — I misjudged the single bottleneck three times; even then, while writing this up I still mislabeled the un-measured third as "static redraw," and only caught the over-attribution because the whole N=12 frame is just 11ms.

**3. Decision and expression are decoupled: the model never mutates world state.**
The engine enumerates legal candidates; the model only reads candidates and context and returns one candidate index plus optional dialogue. The world advances purely through the deterministic engine — the model never writes state directly. Invalid output, timeout, or a missing model all fall back safely to rules. The presentation layer is swappable (canned lines / local SLM / cloud LLM) without changing the reliability of the world.

**4. Emergent social dynamics.**
Gossip spreads third-party reputation → consensus forms → it can escalate into collective avoidance; disagreement crystallizes into factions; mutual-aid pacts carry GTFT-style forgiveness. None of this is scripted — it emerges from rule interactions, and every step traces back to a concrete event, so the system can explain why a resident is angry or trusts someone.

**5. Invariant regression gates plus a shadow counterfactual probe.**
A 30-day soak checks 37 social invariants (belief provenance, promise settlement, money conservation, private-channel secrecy, and more) — **23 hard and 14 soft**, split in [`game/bench/Invariants.gd`](game/bench/Invariants.gd) under `HARD_IDS`. Going further, a "shadow probe" measures — **without changing the trajectory** — exactly which decisions an intervention flips, turning "does this mechanism actually matter" from anecdote into a number.
> Stated honestly: **#15 "emergent ostracism" is a known-leaky metric and is reported, not gated** — it picks the worst-reputation resident from *final* standing but computes their acceptance rate over the *entire* log, which is temporal leakage. After the leak was fixed, #15v2 came back INCONCLUSIVE on all 126 seeds, so the conclusion was to **add no mechanism** and not to gate on it. Full chain in [docs/31](docs/31-15-resolution.md).

**6. On-device SLM: from a 16GB leak to a phone that actually produces decisions.**
On a physical Redmagic 8 Elite (Android 15), `backend=slm` used to mean **40 fired, 0 succeeded**, with Native Heap climbing `3 → 7.5 → 16GB` until OOM.
- **The root cause was not the one it looked like.** The first conclusion — "specific to Adreno GPU Vulkan" — **was falsified by my own follow-up test**: it had only exercised the minimal smoke path. A bench that drives the real in-game decision path segfaulted on desktop AMD Vulkan too, with a panic that said it plainly: `access to instance after it has been freed`. The real cause was **a fresh worker per decision, freed while still in flight** (use-after-free). Fast desktop model → the free beats the callback → crash; slow phone → the worker can't be released → leak. **One bug, two faces.**
- **The fix**: one pooled, persistent worker; serial; never freed mid-flight; late callbacks invalidated by epoch. **Re-verified on the device under full load**: Native Heap peaks at 3.2GB during load then settles to a **flat 217MB**, across 13 sim-days, **zero crashes**, 88-91 FPS.
- **Then it reversed a second time**: the remaining "phone produces no decisions" was **not a hang either — it was slowness**. Only latency telemetry could tell them apart. A device A/B showed in-flight decode under full load at **~16-20s on the Adreno GPU** (the renderer and inference contend for the same GPU) versus **~3-8s warm on the 8 Elite CPU**. So **Android now defaults to CPU inference**, and on-device decisions finally land.
- **The honest denominator**: what can be claimed is that **of the SLM calls that were fired**, most now land inside the deadline (merged-build device run: 22 fired, 13 landed, **0 timeouts**). What must **not** be claimed is "2/3 of NPC decisions on the phone are SLM-driven" — that is landed/**fired**, a convenient denominator. The worker is strictly serial and is itself the town-wide throughput ceiling, so **the share of all town decisions driven by the on-device model has not been measured**.
- **The cost, stated**: with CPU inference active, FPS drops from 88 to 34-46. The bottleneck is now **output quality, not latency** — the 1.5B occasionally returns prose instead of a bare index, which the fail-closed parser rejects before falling back to logic.

Full write-up and all measurement tables in [docs/34](docs/34-slm-device-hang-leak.md); APK build in [docs/18](docs/18-android-apk-build.md).
> These device numbers come from a single handset (Redmagic 8 Elite / Snapdragon 8 Elite / Android 15). This is not a cross-device benchmark.

## Engineering Design

1. **The model does not mutate state directly.** The engine enumerates legal candidates; the model returns a candidate index and optional dialogue. Invalid output, timeout, or missing service falls back to deterministic rules.
2. **Invariants act as regression gates.** The 30-day soak checks 37 properties of the simulated society, including belief provenance, promise settlement, apology flow, reputation effects, private-channel secrecy, money conservation, and no overdraft. **The authoritative list is the code**: [`game/bench/Invariants.gd`](game/bench/Invariants.gd) (each check carries an id, a name, and a failure detail string). Methodology in [docs/08](docs/08-测试与验证.md).
3. **Event sourcing enables replay.** Randomness is derived from `seed + tick + salt`, without wall-clock time or global random state. The same seed produces byte-identical summaries, and the replay observatory rebuilds the world from any tick.
4. **Godot is the authority; the Node port is a historical cross-check.** [`tools/sim_social_port.mjs`](tools/sim_social_port.mjs) mirrors the M1-S3 social core for second-scale iteration and self-checks **33 assertions** (corresponding to engine invariants #1-#33). It genuinely did establish that the logic is robust to the RNG implementation — the port uses mulberry32, Godot uses `RandomNumberGenerator`, the numbers differ and the properties hold on both sides.
   But **it is not the current gate**, and the specifics matter: it has **no coverage** of #34-#37 (money conservation, non-negative currency, festival pairing, election tally), it is **not byte-comparable** with Godot, it is **not invoked by `tools/ci.sh`**, it has **not been updated** since the 2026-07-03 initial public snapshot, and **it is currently red on some seeds** (`--seed 20260626 --days 30` exits 1; seeds 1 and 42 still pass 33/33). Line-by-line comparison in [docs/08 §1](docs/08-测试与验证.md). **There is exactly one regression gate, and it is on the Godot side.**

## Quick Start

Requires [Godot 4.6+](https://godotengine.org/) (the project declares `config/features = 4.6`; CI pins 4.6.2).

**Run the whole gate** — the same script GitHub Actions runs:

```bash
GODOT=/path/to/godot bash tools/ci.sh
```

Seven steps: data lint, map audit, markdown link lint, Godot parse smoke, the S0 invariant gate (37 invariants × 12 seeds × 60 days plus a determinism double-run), the LOD observation-independence gate, and 6 integration scenes. Any red step exits 1.

Windowed mode:

```bash
godot --path game -- --speed 2.0
```

Controls: space pauses, `1/2/3/4` changes speed, mouse wheel zooms, clicking a resident opens state, and the timeline scrubs replay. After selecting a resident, type in the bottom input to talk.

Detailed single-seed headless soak (per-event, per-invariant):

```bash
godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30
```

The Node port (historical cross-check, **not a gate**, currently red on some seeds — see Engineering Design item 4):

```bash
node tools/sim_social_port.mjs --days 30 --seed 1
```

Optional local model backends:

- `--backend llm`: start LM Studio or another OpenAI-compatible local service at the default `localhost:1234`, then load an instruction model.
- `--backend slm`: install [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) under `game/addons/nobodywho/` and place a GGUF model, such as Qwen2.5-1.5B-Instruct-Q4_K_M, under `game/models/`.

Integration details are in [docs/03-LLM集成架构.md](docs/03-LLM集成架构.md). Hardware measurements are in [docs/11-LLM部署实测对比与选型.md](docs/11-LLM部署实测对比与选型.md). Android packaging is in [docs/18](docs/18-android-apk-build.md).

## Layout

```text
game/                  Godot 4 project: scripts, data, scenes, and test scenes
  scripts/Sim.gd       World state, ticks, needs/utility AI, legal candidate API
  scripts/AIBackend.gd Pluggable AI backends with timeout and fallback handling
  scripts/Memory.gd    Memory stream retrieval by recency, importance, and relevance
  bench/               Single source of truth for invariants, S0 grid harness, LOD gate
tools/                 CI script, data/map/link linters, Node logic port, recording pipeline
bench/bakeoff/         Offline distillation bake-off and Theory Engine prototype (Python, not wired into the game loop)
docs/                  Design, architecture, review notes, measurements, and experiments (index: docs/README.md)
```

## Documentation

| Document | Contents |
|---|---|
| [01 产品愿景与玩法](docs/01-产品愿景与玩法.md) | Game concept, core loop, and non-goals |
| [02 技术架构](docs/02-技术架构-混合仿真.md) | Deterministic engine with LLM as presentation layer |
| [03 LLM 集成](docs/03-LLM集成架构.md) | Backends, structured output, timeout, and fallback |
| [07 社交底座](docs/07-技术文档-社交底座.md) | Social transactions, relationships, beliefs, promises, and conflicts |
| [08 测试与验证](docs/08-测试与验证.md) | The invariant gate, hard/soft split, a runtime-coverage comparison, and reproduction steps |
| [11 部署实测](docs/11-LLM部署实测对比与选型.md) | Measured latency across machines and model sizes |
| [13 实验札记](docs/13-实验札记-experiment-journey.md) | A 995-line process journal: findings, tricks, traps — **and retracted conclusions** |
| [18 Android APK build](docs/18-android-apk-build.md) | Building an arm64 APK with an on-device SLM for Snapdragon 8 Elite |
| [31 #15 resolution](docs/31-15-resolution.md) | A residual that looked like a mechanism defect, proven to be a measurement artifact → add nothing |
| [33 Viewer-independent LOD](docs/33-viewer-independent-lod-delivery.md) | An LOD where the camera never feeds the sim, plus the "don't infer the bottleneck, instrument it" lesson |
| [34 On-device SLM hang and leak](docs/34-slm-device-hang-leak.md) | 16GB native leak → use-after-free → pooled worker → device GPU/CPU A/B → CPU by default on Android |
| [`bench/bakeoff/README.md`](bench/bakeoff/README.md) | A 3-command reproducible distillation bake-off plus two honest negative results |

**A themed index of all 33 numbered documents is in [docs/README.md](docs/README.md).** Documentation is primarily in Chinese.

## Assets And License

Code is MIT licensed. Pixel assets come from CC0 packs such as Puny World and Characters; sources are listed in [docs/09-美术资产与版权.md](docs/09-美术资产与版权.md). The cover image is AI-generated. Model weights and NobodyWho binaries are not distributed in this repository; fetch them from upstream sources.

Some documents refer to an upstream game-evaluation pipeline for headless rendering, automated recording, and LLM-as-judge experiments. This repository does not depend on that pipeline at runtime.
