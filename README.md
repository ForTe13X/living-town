# 小镇有灵 · Living Town

[English](README_EN.md)

像素小镇生活模拟原型。居民有需求、记忆、性格和关系，会赴约、爽约、争执、和解，也会形成声誉与派系。底层是一套确定性的社会引擎；本地 LLM/SLM 只负责把引擎给出的合法候选转成台词和选择。

模型不可用时，游戏仍然运行。断网、超时或非法输出都会自动回退到规则决策，因此接入模型只改变表现层，不改变世界状态的可靠性。

![小镇有灵 · 主视觉](docs/media/cover.png)

## 当前状态

- **确定性社会底座**：打招呼、赠礼、八卦、邀约、对质、道歉、关系账本、知识边界、承诺、冲突和解决流程。关系变化能追溯到事件，因此系统能解释一个居民为什么生气或信任某人。
- **可玩外壳**：昼夜光照、时钟与速度控制、NPC 头顶台词和表情、玩家与 NPC 自由对话、回放观察台。可以在任意 tick 检查居民的需求、信念、关系和冲突。
- **三档 AI 后端**：`logic` 纯规则、`llm` 本地 OpenAI 兼容服务、`slm` 通过 NobodyWho 做嵌入式 GGUF 推理。所有后端运行同一套引擎，并能安全降级。
- **本地推理实测**：Qwen2.5-1.5B-Q4 在测试过的消费级 GPU/APU 机器上约 1-2.5 秒完成一次决策；3B 约 2.9 秒。启动探针按当前机器测得的延迟设置 deadline。

演示视频：

- [主演示，3 分钟，中文旁白 + 中英字幕](docs/media/living_town_demo.mp4)
- [派系与盟约](docs/media/s3_social_demo.mp4)
- [嵌入式 SLM 实机驱动](docs/media/slm_gpu_demo.mp4)

![成片字幕样式](docs/media/shot-05-subtitled-demo.png)

## 工程设计

1. **模型不直接改状态。** 引擎枚举合法候选，模型只返回候选 index 与可选台词。非法输出、超时或服务缺失都会回退到确定性规则。
2. **不变量作为回归门。** 30 天 soak 会检查 35 条社会性质，包括信念来源、承诺结算、道歉流程、声誉影响、私聊秘密边界、金钱守恒和不可透支。完整清单见 [docs/08-测试与验证.md](docs/08-测试与验证.md)。
3. **事件溯源支持回放。** 随机性由 `seed + tick + salt` 派生，不依赖墙钟或全局随机。同一 seed 生成逐字节一致的摘要，回放观察台可从任意 tick 重建世界。
4. **双运行时验证。** Node 端口用于快速迭代，Godot 4.6.2 运行实际游戏外壳。两边通过同一组不变量，把逻辑错误与引擎集成问题分开。

## 快速开始

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

## 目录

```text
game/                  Godot 4 工程：scripts、data、scenes 与测试场景
  scripts/Sim.gd       世界状态、tick、需求/效用 AI、合法候选 API
  scripts/AIBackend.gd 可插拔 AI 后端，处理超时与降级
  scripts/Memory.gd    按 recency、importance、relevance 检索记忆流
tools/                 Node 逻辑端口、soak 脚本、录屏流水线
docs/                  设计、架构、评审、实测与实验记录
```

## 文档

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

## 素材与许可

代码使用 MIT License。像素素材来自 Puny World、Characters 等 CC0 资源包，来源列在 [docs/09-美术资产与版权.md](docs/09-美术资产与版权.md)。封面为 AI 生成。模型权重与 NobodyWho 二进制不随仓库分发，请从上游获取。

部分文档会提到一个上游游戏评测流水线，用于 headless 渲染、自动录屏与 LLM-as-judge 实验；本仓库运行时不依赖该流水线。
