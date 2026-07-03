# 03 · LLM 集成架构

> 直接继承《小鱼岛》doc 13 的实测成果，并按「准实时多 Agent」推广。
> 核心心法：**LLM 只返回数据、引擎决定是否执行；导演定调、Agent 多数走脚本、模型稀疏异步介入；永远有确定性降级。**

## 1. 三档可插拔后端（复用 22nd，title 处切换）

| 后端 | 端点/机制 | 适用 | 备注 |
|---|---|---|---|
| **`logic`**（默认） | 纯需求/效用脚本，零模型 | 全平台、Web、bench、无 GPU | progressive enhancement 的地板，**永远兜底合法** |
| **`llm`** | OpenAI 兼容 chat：`HTTPRequest → http://127.0.0.1:1234/v1/chat/completions` | LM Studio / Ollama / 远程 API | 同一份代码，改 `base_url` 即切「自带云 key」 |
| **`slm`** | 本地 GGUF：**NobodyWho** GDExtension（扩展内异步 worker+信号） | 完全离线、开箱 | 实测可用，见 §10.2；原生 GBNF/json_schema 约束；**实战需 GPU** |

接口契约（推广自 22nd `ai_candidates/ai_apply/_llm_pick`）：
```
Sim.agent_candidates(agent) -> [合法 option/动作...]      # 引擎枚举，保证合法
AIBackend.decide(agent, candidates, context) -> {intent}  # 模型/脚本在候选里挑 + 台词
Sim.agent_apply(agent, intent)                            # 引擎执行；非法/超时→回退 candidates[0]
```

## 2. 选模型与体积（实测 + 研究）

- **桌面默认**：对话用 **Qwen2.5-3B-Instruct Q4_K_M**（~2.3GB VRAM，~80–200ms/短句，mid GPU）做「环境 NPC 工作马」；命名/故事角色高端机热切 **Qwen2.5-7B Q4**；Steam Deck/低端用 **Gemma2-2B Q4**。
- **中文 + 极省体积场景**（沿用 22nd 结论）：下限是 **Qwen2.5-0.5B（~469–491MB Q4）**，SmolLM2 中文崩；0.5B 适合「短台词/吐槽/在候选里挑」，复杂对话则上 3B+。
- **量化**：Q4_K_M 为生产默认（~75% 显存↓，<1% 质量损）；环境「碎语 bark」可 Q3_K_M，命名角色别低于 Q4。
- **Web**：**不内置模型**，回退 `logic` + 可选远程（同 22nd）。

## 3. 结构化输出（让 NPC 决策可解析、安全）

强弱三档，**首选最强**：
1. **语法约束解码（GBNF）**——`llama-server`/godot-llm 在采样时屏蔽违反语法的 token，输出**不可能非法**。首选。
2. **json_schema / `response_format`**——LM Studio/Ollama 支持，schema 合法 JSON。
3. **function/tool-calling**——NobodyWho 自动从类型派生 GBNF；决策映射到固定动词集时好用。

**NPC 决策 schema（小而枚举化，每字段都费 token）**：
```json
{
  "speech":  "string, ≤2 句",
  "emotion": "neutral|happy|angry|sad|anxious|fond",
  "action":  "idle|move_to|talk|use|give|invite",
  "target":  "string|null",          // 必须是世界树里的合法 id
  "affinity_delta": -3
}
```
`emotion/action` 用 **enum** 让引擎直接 `match`，数值在语法里 clamp；**代码里再校验一遍**，任何不对→回退默认动作。**永不让模型直接 gate 游戏状态。**

## 4. 导演–Agent 分层（让它「可发布」而非 demo）

- **Director（偶发，全局）**：一个很少跑的「编剧」，设定镇上高层意图——谁今天心情差、什么八卦在传、哪个 NPC 该接近玩家、镇子整体情绪。写进一块小**黑板**；这里才是值得花「更聪明/云端」调用的地方。
- **Agent（个体）**：多数时刻跑廉价**需求/效用 FSM**，只在「导演点名 / 玩家触发 / 重要事件」时调一次 LLM。→ LLM 调用数正比于**有意思的事件**，而非 `NPC 数 × 帧数`。
- 学界背书（**Lyfe Agents**）：option-action 分层 + 自监控摘要 + summarize-and-forget，**成本降 ~10–100×** 且保持实时。这正是 indie 需要的比例。

## 5. 异步 tick / 批处理 / 缓存（成本与延迟）

- **异步**：全程 `HTTPRequest`/sidecar fire-and-forget + 完成回调；NPC 等模型时继续脚本行为；`thinking` 标志防重排。**主线程绝不 `await`。**
- **队列别洪泛**：单机本地服是串行的；维护**优先级队列**（玩家面对的 NPC > 近玩家 > 离屏），**最多 1–2 个在飞**，过载丢低优。
- **狠缓存**：环境 bark 预生成复用；`(persona + 状态桶) → 决策` 记忆化；**prompt 缓存**（共享 system prompt 的 KV 复用，只重算每-NPC 尾巴）。
- **暖机**：开局打一发 dummy 请求付冷载（1–3s）；`OLLAMA_KEEP_ALIVE`/`llama-server` 常驻别卸载。
- **流式**：玩家面对的对话 `stream:true`，首词即现，藏住后续延迟（配「思考中…」气泡动画）。

## 6. 确定性降级（安全网，本作的命脉）

每条 LLM 路径都备好脚本答案：模型**缺失**（玩家没装/禁用）、**超时**（>~400ms deadline）、**报错**——NPC 静默改用 **utility-AI/FSM/罐头台词**。
做法：派发即起计时器，先到先用脚本动作，丢弃迟到的模型回复（或留到下次交互）。
→ 这让 LLM NPC 成为**渐进增强**：**没有任何模型，游戏也是一个完整可玩的脚本生活模拟**（与 22nd 同姿态，先把脚本 AI 做好做平衡，再叠 LLM）。

## 7. grounding（廉价地把 LLM 钉在世界状态上）

- **模板化 prompt**，分固定段：`PERSONA`（静态，可 prompt-cache）+ `WORLD/RULES`（静态）+ `NOW`（紧凑当下：时段/位置/与玩家好感/近期事件/导演意图）+ `MEMORIES`（top-k 检索）+ `SCHEMA`。`NOW` 只放几行 KV——生活模拟绝大多数状态与某次决策无关。
- **记忆：summarize-and-forget**（Lyfe）——每个 NPC 滚动**短摘要** + 少量**显著长期记忆**，其余遗忘 → 上下文长度（与成本）**永久有界**，与游玩时长无关。
- **检索从简**——小世界用 **recency + importance + relevance 的算术打分**（Stanford 配方，无需 embedding）；记忆库变大才加一个**小型本地 embed 模型**（sidecar，cosine top-k）。只注入 top 3–5 条。
- **状态分桶**（好感→友好/中立/敌对；时间→晨/昼/夜）让很多具体情境映射到同一 prompt，命中决策缓存。

## 8. 要不要微调 / 蒸馏（决策顺序，取自研究）

1. **先 prompt 工程**（性价比最高）：紧 system prompt（人设 + 世界规则 + 硬长度 + 2–3 条 in-character few-shot + 强制 JSON），多数 NPC 到此为止。
2. **蒸馏**（prompt 触顶后）：用大模型（云端 Claude/GPT，**开发期离线跑一次**）按你的 schema 与口吻生成上千条 `(状态→决策 JSON)` 与对话样本，训练小学生模型 → 把世界口吻与 JSON 格式**烤进 SLM**，**运行时零成本**。
3. **QLoRA 是上面的实现手段**（4-bit base + 可训练 adapter，单卡）；锁格式遵从/拒答/口吻。出 GGUF 即发。避免全量微调。
4. **陷阱（22nd 已警示）**：别把模型微调成模仿启发式最优 play——只会得到又慢又有损的拷贝；强度永远交给引擎，模型只管「合法结构 + 性格声音」。

## 9. 最小落地默认（可直接抄）

- **引擎**：桌面 godot-llm/NobodyWho 内置 GGUF（或玩家自备 LM Studio）；Web 回退 `logic`。
- **模型**：Qwen2.5-3B Q4_K_M 默认对话；0.5B 用于碎语/在候选里挑；7B 给命名角色。
- **传输**：Godot `HTTPRequest` → `/v1/chat/completions`，`request_completed` 异步，JSON 解析下主线程。
- **输出**：语法/schema 约束、enum、代码再校验。
- **控制**：导演偶发定调；Agent = 效用 FSM + 稀疏 LLM；并发 1–2；优先队列 + 每-NPC 冷却；`max_tokens≈80`。
- **韧性**：开机暖机、keep-alive、~400ms deadline → 确定性脚本降级；无模型也能玩。
- **grounding**：PERSONA/WORLD/NOW/MEMORIES 模板 + summarize-and-forget + recency/importance 检索 + 状态桶缓存。

> 接 Claude/Anthropic API 时，模型 ID/价格/接口以官方为准——用 `/claude-api` 查，勿凭记忆。

---

## 10. 实测复盘（2026-06，真机/真模型）

> 测试床：Docker 内 Godot 4.6.2 headless。场景 `res://scenes/llm_live_test.tscn`（连宿主 LM Studio，经 `host.docker.internal:1234`）、`res://scenes/slm_live_test.tscn` 与 `res://scenes/slm_backend_test.tscn`（嵌入式 NobodyWho）。

### 10.1 `llm` 后端（LM Studio，OpenAI 兼容）— **主集成路径，已打通**

- **选型结论**：**`qwen-3-8b-instruct` + `/no_think`，且不发 `response_format` json_schema**。
- 两条实测教训（都反直觉，已写进 `AIBackend.gd` 注释）：
  1. **必须加 `/no_think`**。Qwen3 是推理模型；不加时它把 `max_tokens` 烧在思考上，`content` 返回空、~37s `finish=length`。决策与对话两条 prompt 都要加。
  2. **不要叠 json_schema 受限解码**。短 prompt 能过，但**长 prompt（9 候选 + 全上下文）会卡死只吐 `{`**（~14s 截断）。改为：`/no_think` 压思考 + `parse_decision` 抽第一个 `{…}` 子串，最稳。
- **实测延迟/质量**（qwen-3-8b，本地）：决策 JSON **~4.4s**（`{"pick":3,"speech":"…","emotion":"happy","affinity_delta":2}`，解析正确、在角色）；玩家自由对话 **~4.6–6.5s**（满人设中文）。端到端 `backend=llm` 真实时跑，LLM 决策确实异步落地，引擎兜底其余。
- `MAX_TOKENS` 由 80 提到 **128**（决策 JSON 含中文台词约 80–120 字符，80 token 会截断台词）。

### 10.2 `slm` 后端（嵌入式 NobodyWho + 本地 GGUF）— **离线选项，已验证可用**

- **扩展**：[NobodyWho](https://github.com/nobodywho-ooo/nobodywho) `nobodywho-godot-v9.4.0`（`compatibility_minimum=4.5`，Godot 4.6.2 可加载）。装在 `game/addons/nobodywho/`。
- **模型**：`Qwen2.5-1.5B-Instruct-Q4_K_M`（~1.04GiB），放 `game/models/`。
- **加载三道坎（已全部解决，记录以备复现）**：
  1. **`.godot/extension_list.cfg` 必须存在**并列出 `res://addons/nobodywho/nobodywho.gdextension`——headless 直接 `--path` 不会自动生成，否则扩展根本不加载。
  2. **`.so` 链接 `libvulkan.so.1`**（llama.cpp Vulkan 后端）——软渲容器需装 `libvulkan1` loader（无设备 → llama.cpp 回退 CPU）。
  3. **`.so` 需 `GLIBC_2.38`**（`libstdc++` 仅需 `GLIBCXX_3.4.30`，22.04 已满足）——基础镜像 Ubuntu 22.04(glibc 2.35) 不够，**专门建 `gamecraft-slm:24`（Ubuntu 24.04 + libvulkan1 + 拷入 godot 二进制）**。
- **NobodyWho API（本版自省确认）**：`NobodyWhoModel{model_path, use_gpu_if_available}`；`NobodyWhoChat{model_node, system_prompt, allow_thinking, context_length}`，方法 `start_worker()`→`ask(msg)`（`say` 已弃用），信号 `response_finished(response)`/`response_updated(token)`/`worker_failed(error)`；**原生结构化输出** `set_sampler_preset_constrain_with_json_schema / _grammar / _regex`（注意：须在 `start_worker()` **之后**设才生效）。
- **实测延迟/质量（容器纯 CPU，32 核但 NobodyWho CPU 后端未优化）**：决策 JSON **~59s**（json_schema 约束生效、JSON 合法、解析成功）；自由对话 **~42–64s**（在角色、有创意，如即兴编出"时光倒流咖啡馆"）。**质量对 1.5B 可用，但 CPU 延迟 ~1 字/s 不实用——实战须 GPU(Vulkan)**（`use_gpu_if_available=true`，真机有设备时数量级提速）。
- **与实时截止线的交互（正确行为）**：`DEADLINE_MS=12000` < CPU 生成 40–60s → 容器 CPU 下 `decide()` 必然超时返回 `{}` → 引擎兜底 logic（已加超时清理：`_finish` 停止+释放仍在跑的 worker，防慢机堆积）。GPU 下生成 <1.1s ≪ 12s → `decide()` 稳定落地 SLM 意图。`chat()`（玩家对话，不设 deadline）正常返回。
- **GPU 实测（本机原生 Windows，AMD Ryzen AI Max+ 395 / Radeon 8060S，见 §10.5）**：`use_gpu_if_available=true` → `ggml_vulkan: AMD Radeon(TM) 8060S Graphics (AMD proprietary driver) | matrix cores: KHR_coopmat`，**全 29 层 offload**、93GB 统一显存。**决策 JSON ~1.06s(71.5 字/s)、自由对话 ~0.24s(138.7 字/s)** —— 相对容器 CPU **决策 ~56× / 对话 ~178× 提速**，且**比 LM Studio 的 8B 还快**（1.5B≪8B + 进程内无 HTTP）。**这把"嵌入式离线 SLM"从"功能可用但太慢"翻盘为最佳选项之一。**

### 10.3 选型矩阵（三路实测）

| 维度 | `llm` LM Studio qwen-3-8b (宿主 GPU) | `slm` 嵌入 1.5B-Q4 / CPU(容器) | `slm` 嵌入 1.5B-Q4 / **GPU(本机原生)** |
|---|---|---|---|
| 部署 | 需玩家开 LM Studio 服务 | 完全内置离线 | **完全内置离线** |
| 决策延迟 | ~4.4s | ~59s | **~1.06s** |
| 对话延迟 | ~4.6–6.5s | ~42–64s | **~0.24s** |
| 质量 | 高（8B） | 中（1.5B） | 中（1.5B，可升 3B/7B） |
| 结构化 | parse_decision 抽 JSON（json_schema 不可靠） | **原生 GBNF/json_schema** | **原生 GBNF/json_schema** |
| 体积 | 0（外置） | 扩展 65MB + 模型 ~1GB | 扩展 65MB + 模型 ~1GB |
| 结论 | 通用/换大模型方便；需外部服务 | 仅功能/确定性验证（太慢） | **本机首选**：最快、离线、无服务依赖 |

### 10.4 复现命令

```powershell
# llm：连宿主 LM Studio（需先启动并加载 qwen-3-8b-instruct）
docker run --rm --add-host host.docker.internal:host-gateway -v "E:/Documents/Dev/June/26th/game:/game" `
  gamecraft-runner:4.6.2 godot --headless --path /game res://scenes/llm_live_test.tscn

# slm：嵌入式 NobodyWho（需 gamecraft-slm:24 镜像 + game/addons/nobodywho + game/models/*.gguf）
docker run --rm -v "E:/Documents/Dev/June/26th/game:/game" `
  gamecraft-slm:24 godot --headless --path /game res://scenes/slm_live_test.tscn
```
> `gamecraft-slm:24` 配方见 `tools/`（Ubuntu 24.04 + `libvulkan1`/`libgomp1` + 多阶段拷 `/opt/godot/godot`）。模型/扩展为大文件，勿入库。

### 10.5 能否用 Docker 接本机 GPU 给嵌入式 SLM 提速？（实测：AMD Ryzen AI Max+ 395 / Radeon 8060S）

**结论：经 Docker(WSL2) 把 AMD GPU 喂给容器内嵌入式 SLM（NobodyWho=Vulkan-only）当前不可行；GPU 提速请走原生 Windows 或 LM Studio。**

实测链路（WSL2 + Docker Desktop）：
- `/dev/dxg`（WSL 的 GPU 半虚拟设备）+ `/usr/lib/wsl/lib`（`libd3d12core.so`/`libdxcore.so`）**可注入容器**：`docker run --device=/dev/dxg -v /usr/lib/wsl:/usr/lib/wsl`，并把 `/usr/lib/wsl/lib` 加进 `LD_LIBRARY_PATH`。
- 但 WSL **没有** `/dev/dri/amdgpu` DRM 节点 → Mesa 的真 AMD Vulkan 驱动 **RADV 无法用**；`vulkaninfo` 只枚举到 `llvmpipe`(CPU)。
- WSL 下唯一的 Vulkan 路径是 Mesa **Dozen(dzn)**（Vulkan→D3D12）——但 **Ubuntu 24.04 的 `mesa-vulkan-drivers` 不含 `libvulkan_dzn.so`**（ICD 只有 radeon/intel/lvp/nouveau…），仓库也无单独 dzn 包（dzn 是 `microsoft-experimental`，需从源码编译 Mesa 才有）。即便编出 dzn，llama.cpp 的 `ggml-vulkan` 对 dzn 的特性支持也不可靠。
- ROCm 路径对 NobodyWho 无意义：NobodyWho 的 .so 链 `libvulkan`、走 Vulkan 而非 HIP/ROCm。

**那 395 这块强 APU 怎么用上**（RDNA3.5 + 大统一内存，跑 LLM 很合适）：
1. **`llm` 后端（LM Studio）已经能吃 GPU**：在 LM Studio 里开 GPU offload，宿主原生用 Vulkan/ROCm 跑——实测 qwen-3-8b 决策 ~4.4s。
2. **嵌入式 `slm` 走 GPU = 已实测验证（本机原生 Windows）✅**：下 Godot 4.6.2 win64 + 把 NobodyWho 的 `…pc-windows-msvc-release.dll` 放进 addon + `.gdextension` 加 windows 条目，`use_gpu_if_available=true` → AMD Windows 驱动一等 Vulkan 直接吃 8060S（`gpu_layers=29` 全 offload、93GB 统一显存、KHR_coopmat）。**决策 ~1.06s / 对话 ~0.24s，比 Docker CPU 快 ~56×/178×、比 LM Studio 8B 还快。**
3. Docker 仅适合 `slm` 的**功能/确定性验证**（CPU，慢但正确），不适合 GPU 提速。

**复现（本机原生 GPU SLM 实测）**：
```powershell
# 用 Godot 4.6.2 win64 的 console 版捕获 stdout；--gpu 经 user-args 传给 slm_live_test
& "<解压路径>\Godot_v4.6.2-stable_win64_console.exe" --headless --path "E:\Documents\Dev\June\26th\game" `
  "res://scenes/slm_live_test.tscn" -- --gpu
```
> 前置：`game/addons/nobodywho/` 含 windows dll、`.gdextension` 有 windows 条目、`game/.godot/extension_list.cfg` 存在、`game/models/*.gguf` 就位。
