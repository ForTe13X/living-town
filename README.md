# 小镇有灵（Living Town）· 像素 LLM 生活模拟

> 工作代号，可改名。一个**像素版「模拟人生」**：一座小镇里住着若干由 **LLM/SLM 驱动**的居民，
> 他们有需求、有记忆、有性格、会规划一天、会彼此交谈并产生**涌现的社会戏剧**。玩家是新搬来的居民，
> 可与 NPC 自由对话、观察并介入他们的生活。

![小镇有灵 · 主视觉](docs/media/cover.png)

**EN TL;DR** — *Living Town*: a pixel life-sim where NPCs are driven by a **deterministic needs/utility + event-sourced social engine**, with a local **LLM/SLM strictly as the renderer** (it only picks from engine-enumerated legal candidates; 12s deadline → automatic rule fallback, the game never blocks). Engineering highlights: **33 machine-checked soak invariants** (knowledge provenance / commitment lifecycle / confront-before-repair / emergent ostracism / secrets never leak into gossip / faction & pact consistency — violation = CI fail), byte-exact replay from any tick, dual-engine regression (Node port ↔ real Godot 4.6.2), and a measured **on-device SLM tier scheduler** (embedded Qwen2.5-1.5B-Q4 ≈ 1–2.5s/decision across consumer GPUs/APUs; capability probe → adaptive deadline → graceful degradation). Demo video: [docs/media/living_town_demo.mp4](docs/media/living_town_demo.mp4). Setup note: LLM weights (`game/models/*.gguf`) and the NobodyWho GDExtension binaries are **not committed** — see [docs/03](docs/03-LLM集成架构.md) / [docs/11](docs/11-LLM部署实测对比与选型.md) for download & wiring; the deterministic `logic` backend runs with **zero** model dependencies.

本目录（`June/26th`）是 **2026-06-26 启动的新项目工作区**，与 `June/22nd` 的《小鱼岛》是**不同项目**，
但**刻意复用其已跑通的研发流水线与本地 LLM 集成**（见下「复用地图」）。

> 主视觉由 GPT-5.5 Pro 生成；游戏内像素精灵用 CC0 免费包（Puny World / Characters，OpenGameArt）。版权与出处见 [docs/09](docs/09-美术资产与版权.md)。

## 一句话状态

🟡 **设计 + 骨架 + M1 社交底座切片**。本仓库目前包含：完整的**现有流水线分析**、**新项目设计**（概念/架构/LLM 集成/参考/路线图）、
一份**独立评审与风险册**（[docs/06](docs/06-评审与风险册.md)，含 GPT-5.5 Pro 交叉评审）、
一个 **Godot 4 工程骨架**（headless 仿真引擎 + 需求/效用 AI + 可插拔 LLM 后端 + 数据驱动内容 + 像素渲染雏形），
以及据评审落地的 **确定性社交底座垂直切片**（Agent↔Agent 的 SocialTransaction + 关系账本 + belief/知识边界 + event log + soak 不变量门，
经 `tools/sim_social_port.mjs` 跨 5 seed/60 天验证，并**已在真 Godot 4.6.2 里跑通**（复用 22nd 镜像、独立容器，determinism + 多 seed 不变量全过）。

此外已落地一层**可玩/可观察的外壳**：CC0 像素美术（地形变体/装饰散布/区域小屋）+ 昼夜光照、时钟与速度档、相机缩放、**回放观察台**（确定性时间轴 scrub + 点选角色看需求/关系/信念/冲突/记忆）、NPC 头顶**对话台词 + emote**、以及玩家↔NPC **自由对话**（输入框 + 回复气泡 + 记忆）。

**真实模型推理已实测打通**（2026-06，真机/真模型，详见 [docs/03 §10](docs/03-LLM集成架构.md) + [docs/11 三路对比](docs/11-LLM部署实测对比与选型.md)）：三路实测——`llm`=LM Studio **`qwen-3-8b`**（决策 4.4s/对话 6.5s）、`slm`=NobodyWho 嵌入式（默认 **`Qwen2.5-3B-Q4`**，1.5B 为轻量备选）。**全机型实测（docs/11 §12）**：1.5B 在 395-GPU/395-CPU/8840U-GPU/8840U-CPU 全部 1–2.5s；3B 中端 ~2.9s；连 8B 中端核显都 ~5s——**全在 12s 线内**。**两大反转**：①嵌入式离线 SLM 在能用 GPU 时比宿主 8B 还快；②"纯 CPU 太慢(59s)"是 Docker 软渲伪命题（同机原生 CPU 仅 1.48s），**现代机有无 GPU 都满血**。启动 `capability` 探针测 p50→自适应截止线/太慢自动降 logic。演示见 [docs/media/slm_gpu_demo.mp4](docs/media/slm_gpu_demo.mp4)（真 GPU SLM 驱动游戏）。两条路均保持「引擎稀疏异步介入 + 确定性兜底」。下一步见 [docs/05](docs/05-路线图与里程碑.md)。

**演示**：[docs/media/living_town_demo.mp4](docs/media/living_town_demo.mp4)（231.9s，中文女声旁白 + 中英双语字幕）；截图见 `docs/media/shot-01..10`（早期生活 / 赠礼交谈 / 中段 / 黄昏昼夜 / 字幕 ×2 / 观察台 / 回放回跳 / 视觉总览 / 对话特写）。

## 文档

| 文档 | 内容 |
|---|---|
| [00 现有项目与流水线分析](docs/00-现有项目与流水线分析.md) | 《小鱼岛》研发流水线全解：bench 规格→Agent 生成→Docker 评测→平衡仿真→打包→三档 AI 后端 |
| [01 产品愿景与玩法](docs/01-产品愿景与玩法.md) | 它是什么、核心循环、玩家体验、与《小鱼岛》的异同、范围与不做什么 |
| [02 技术架构-混合仿真](docs/02-技术架构-混合仿真.md) | 确定性需求/效用引擎为底 + LLM 为「声音/导演」；tick/step、记忆流、反思、PIANO 并发模块 |
| [03 LLM 集成架构](docs/03-LLM集成架构.md) | 三档可插拔后端（logic / LM Studio / 内置 SLM）、结构化输出、导演-Agent 分层、成本与降级 |
| [04 参考项目](docs/04-参考项目.md) | Generative Agents / AI Town / Project Sid / Voyager / Lyfe / Mantella / RimWorld / Stardew |
| [05 路线图与里程碑](docs/05-路线图与里程碑.md) | M0 骨架→M1 确定性生活模拟→M2 接 LLM 对话→M3 记忆/反思→M4 涌现社会→打磨/发布 |
| [06 评审与风险册](docs/06-评审与风险册.md) | 7 维多 agent + GPT-5.5 Pro 对抗式评审、排序风险、净新增架构要求 |
| [07 技术文档·社交底座](docs/07-技术文档-社交底座.md) | M1 已实现技术细节：候选契约 / 社交事务 / 关系账本 / 知识边界 / 承诺 / 冲突 / 确定性 / 可视化 / Docker 出片流水线 |
| [08 测试与验证](docs/08-测试与验证.md) | 机检不变量(现 33 条:需求/社交/承诺/冲突/S1 声誉/S2 意见/S3 派系·盟约·秘密)、Node 端口×真 Godot 双阶段、多 seed/确定性、真引擎逼出的 GDScript 坑、复现方式 |
| [09 美术资产与版权](docs/09-美术资产与版权.md) | 混合资产策略：CC0 像素包（Puny World/Characters，含许可出处）+ GPT-5.5 Pro 封面；贴图三级回退、persona→sprite 映射、重获取流程 |
| [10 社交深化·前沿研究与 roadmap](docs/10-社交深化-前沿研究与roadmap.md) | 6 路 arXiv 前沿调研（意见动力学/谣言/合作博弈/联盟·机制/LLM 社会模拟架构/评测）→ 取舍论证 + 分阶段 path（杠杆排序）+ 陷阱清单 + 引用 |
| [11 LLM 部署实测对比与选型](docs/11-LLM部署实测对比与选型.md) | 三路真机实测（LM Studio 8B / 嵌入 SLM CPU / 嵌入 SLM GPU）对比 + 8 条 insights + 分档部署回退链 + 模型尺寸/排队策略 + 按后端能力 tier 自适应架构 + bench-first roadmap + 诚实警示清单 |
| [12 规模与美术 roadmap](docs/12-规模与美术-roadmap.md) | 研究型规划（4 视角检索综合）：扩多 NPC（RNG 地基→空间分区→决策切片→仿真 LOD→评测可扩展→LLM 队列治理）+ 美术（调色板收口→persona palette-swap→程序化丰富度→事件驱动显形→GPT 立绘窄通道）+ 规模×美术交织 + 五红线 + 8 个 quick-wins |
| [13 实验札记 · Experiment Journey](docs/13-实验札记-experiment-journey.md) | 过程中的发现/奇技/翻盘/踩坑/运气，按时间倒序的随手长养日志（类目：serendipity·trick·gotcha·reframe·insight·dead-end）——记"会想讲给另一个工程师听"的东西 |

## 演示

[`docs/media/living_town_demo.mp4`](docs/media/living_town_demo.mp4) —— 181s，柔和中文女声旁白 + 中英双语字幕；展示零模型确定性社交底座（社交事务 / 关系 / 承诺 / 冲突生命周期）跑通。截图见 [`docs/media/`](docs/media)。

![成片字幕样式](docs/media/shot-06-subtitled-demo.png)

**S3 社交深化演示**：[`docs/media/s3_social_demo.mp4`](docs/media/s3_social_demo.mp4)（faction 场景：观点派系脚环 / 互助盟约青线 / endorse·rally_oust·背叛气泡）+ [`shot-s3-factions.png`](docs/media/shot-s3-factions.png)。**真 3B/GPU 嵌入式 SLM 驱动**：[`docs/media/slm_gpu_demo.mp4`](docs/media/slm_gpu_demo.mp4)。

## 工程骨架

- Godot 4 工程：[game/](game)（`project.godot` + `scripts/` + `data/`）
- 入口/屏幕管理：[game/scripts/Main.gd](game/scripts/Main.gd)
- **headless 仿真引擎**（autoload `Sim`）：[game/scripts/Sim.gd](game/scripts/Sim.gd) —— 全部世界/Agent 状态、tick、需求/效用 AI、`agent_candidates()/agent_apply()` 合法候选接口
- **可插拔 LLM 后端**（autoload `AIBackend`）：[game/scripts/AIBackend.gd](game/scripts/AIBackend.gd) —— `logic | llm | slm` 三档，引擎永远兜底合法
- **记忆流**：[game/scripts/Memory.gd](game/scripts/Memory.gd) —— recency+importance+relevance 检索 + summarize-and-forget
- 像素渲染（纯订阅者）：[game/scripts/WorldView.gd](game/scripts/WorldView.gd)
- 数据驱动内容：[game/data/](game/data)（agents / personas / needs / actions / map）

## 复用地图（reuse from `June/22nd`）

新项目**不重建**以下设施，直接复用 22nd 的成果：

| 设施 | 位置（22nd） | 如何复用 |
|---|---|---|
| Docker 评测流水线 | `../22nd/pipeline/`（`gc.ps1` + `docker-compose.yml` + Dockerfile，Godot 4.6.2 + Xvfb+ffmpeg+xdotool） | 把本工程放进 `pipeline/games/<name>/`，或在 26th 建薄封装指向同容器 |
| 零依赖静态服 | `../22nd/pipeline/serve.js` | 原样复用，托管 HTML5/wasm 构建（已处理 wasm/pck MIME + Range） |
| HTML5 导出配方 | `package.sh`：`godot --headless --import` → `--export-release "Web"` | 同配方；首跑下 ~1.25GB 导出模板 |
| **本地 LLM 集成** | `../22nd` doc 13 + `Game.gd` 的 `ai_backend = logic\|llm\|slm` | **最关键复用**：LM Studio OpenAI 兼容 HTTP（实测选 `qwen-3-8b`）；嵌入式 SLM 实测落到 **NobodyWho**（非 22nd 设想的 godot-llm/GDLlama）；引擎兜底合法。详见 [docs/03 §10](docs/03-LLM集成架构.md) |
| LLM-as-judge | `pipeline` 的多模态评审（LM Studio qwen3-vl，可切 Claude/GPT-5.5） | 复用为「这个生活模拟看起来/表现对不对」的自动 reward 回路 |
| 平衡自走子范式 | `Game.gd`/`sim.gd`（`--headless --script ... -- --games N`） | 同范式跑 headless 经济/需求 soak 仿真 |
| 美术三级回退 | `Art.pick: pro/png > png > svg` + `manifest.json` | 同机制：先占位像素图，后零代码换正式像素美术 |

详见 [docs/00-现有项目与流水线分析.md](docs/00-现有项目与流水线分析.md)。

## 快速上手（规划中）

```powershell
# 窗口模式（带时钟/昼夜/速度档/回放观察台）：
godot --path game -- --speed 2.0
#   操作：空格暂停 · 1/2/3/4 速度 · 滚轮/± 缩放 · Tab/点居民 查看状态 · 拖时间轴/[ ]跳天/, . 单步 回放
#   对话：选中居民→底部输入框打字 Enter 发送（C 键快捷打招呼）；NPC 回复经 LLM/mock/人设罐头
#   接 LLM：开 LM Studio(:1234 载 qwen-3-8b)后 `--backend llm`；内置 GGUF(NobodyWho)则 `--backend slm`；`--backend mock` 免模型验证异步链路
godot --path game -- --backend llm --speed 2.0

# M2 异步接线自测（parse glue + mock 异步链路，需 autoload 故跑场景）：
godot --headless --path game res://scenes/m2_test.tscn

# 真模型实测（详见 docs/03 §10）——llm：先开 LM Studio 载 qwen-3-8b-instruct：
docker run --rm --add-host host.docker.internal:host-gateway -v "<abs>/game:/game" `
  gamecraft-runner:4.6.2 godot --headless --path /game res://scenes/llm_live_test.tscn
# slm：嵌入式 NobodyWho（需 game/addons/nobodywho + game/models/*.gguf + 建 gamecraft-slm:24，见 tools/slm.Dockerfile）：
docker run --rm -v "<abs>/game:/game" gamecraft-slm:24 godot --headless --path /game res://scenes/slm_live_test.tscn

# 或 headless 跑仿真 + 社交不变量门（任一断言失败 → 退出码 1，可当 bench build_check）：
godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30

# 在真 Godot 里跑 soak（复用《小鱼岛》22nd 已构建的镜像，起独立一次性容器，不碰 22nd 的 pipeline/容器）：
./tools/soak-godot.ps1 -Days 30 -Seed 20260626   # 退出码 0=不变量全过 / 1=失败
# 等价手动：docker run --rm -v "<abs>/game:/game" gamecraft-runner:4.6.2 \
#   bash -lc "godot --headless --path /game --script res://scripts/sim_soak.gd -- --days 30"

# 无 Docker/无 Godot 时：用 Node 端口验证同一套逻辑与 7 条不变量（读同一份 game/data/*.json）：
node tools/sim_social_port.mjs --days 30 [--seed 20260626] [--verbose]

# 接本地 LLM 对话：开 LM Studio（OpenAI 兼容，localhost:1234），title 切到 "LM Studio" 后端
```

> 模型 ID / 价格 / 接口以官方为准；接 Anthropic/Claude 时请查 `/claude-api`。
