# 小镇有灵 · Living Town

一个像素小镇生活模拟:居民有需求、有记忆、有性格,会赴约也会爽约,会吵架、和解、拉帮结派。
底层是一套**确定性社会引擎**,大模型只负责"说话"——决策永远出自引擎枚举的合法选项,模型挑一个并配上台词。
断网、模型超时、机器太慢,游戏照常运行。

![小镇有灵 · 主视觉](docs/media/cover.png)

**EN** — *Living Town* is a pixel life-sim where NPC behavior comes from a deterministic needs/utility engine with an event-sourced social layer; a local LLM/SLM only "renders" decisions by picking from engine-enumerated legal candidates (with an automatic rule fallback on timeout, so the game never blocks). The social substrate is regression-gated by **35 machine-checked invariants** over 30-day soak runs, replays byte-exactly from any tick, and runs the same logic in two engines (a Node port and real Godot 4.6.2). An embedded quantized SLM (Qwen2.5-1.5B-Q4) decides in **1–2.5 s** on consumer GPUs/APUs.

## 现在做到了什么

- **确定性社会底座**:社交事务(打招呼/赠礼/八卦/邀约/对质/道歉)、关系账本、信念与知识边界、承诺与冲突的完整生命周期。每条关系变化都指向真实事件,可以回答"她为什么生他的气"。
- **可玩外壳**:昼夜光照、时钟与速度档、NPC 头顶台词和表情、玩家与 NPC 自由对话、回放观察台(拖时间轴回看任意时刻,点开任何居民看需求/关系/信念/冲突)。
- **三档 AI 后端**:`logic`(纯规则,零模型依赖)/ `llm`(LM Studio 等本地 OpenAI 兼容服务)/ `slm`(NobodyWho 嵌入式 GGUF,进程内推理)。三档跑同一套引擎,随时切换。
- **真机实测**:嵌入式 1.5B-Q4 在多台消费级机器(核显/APU/CPU)上决策延迟 1–2.5 s;3B 约 2.9 s。启动时探针实测延迟,自动定截止线,超时降级规则——**永不卡帧**。

演示视频:[主演示(3 分钟,中文旁白+双语字幕)](docs/media/living_town_demo.mp4) ·
[派系与盟约](docs/media/s3_social_demo.mp4) ·
[嵌入式 SLM 实机驱动](docs/media/slm_gpu_demo.mp4)

![成片字幕样式](docs/media/shot-06-subtitled-demo.png)

## 为什么值得一看(工程侧)

1. **模型不碰状态**。引擎枚举合法候选,模型只返回一个序号加一句台词;非法输出、超时、断网都落回规则决策。这让"接不接模型"变成纯粹的体验差异,而不是稳定性风险。
2. **35 条机检不变量当回归门**。不断言具体数值,断言这个小社会必须成立的性质:每条学到的信念必须能溯源到对应事件;过期承诺必须被结算;和解必须先有对质、且有被接受的道歉;坏名声者的社交接受率必须真的降下来(放逐是涌现的,不是写死的);秘密只走私聊渠道,绝不混进普通八卦;镇上的钱总量守恒、任何人不可透支。跑 30 天 soak,任何一条违反,进程以非零退出。清单见 [docs/08](docs/08-测试与验证.md)。
3. **事件溯源 + 字节级重放**。全部随机数由 `seed + tick + salt` 派生,不用时钟和全局随机;同一 seed 双跑摘要逐字节一致,可以从任意 tick 重建世界(回放观察台就建在这上面)。
4. **双引擎验证**。同一套社会逻辑在 Node 端口(秒级迭代)和真 Godot 4.6.2 里各跑一遍,同一组不变量两边都过——逻辑错误和引擎坑分开抓。

## 快速开始

最快的验证不需要装任何东西(有 Node 即可):

```bash
# 跑 30 天社会模拟 + 全部不变量检查(退出码 0 = 全过)
node tools/sim_social_port.mjs --days 30 --seed 20260626 --verbose
```

窗口模式(需要 [Godot 4.x](https://godotengine.org/)):

```bash
godot --path game -- --speed 2.0
# 空格暂停 · 1/2/3/4 调速 · 滚轮缩放 · 点击居民看状态 · 拖时间轴回放
# 选中居民后在底部输入框打字对话
```

headless 跑 soak 门(CI 可用):

```bash
godot --headless --path game --script res://scripts/sim_soak.gd -- --days 30
```

接本地模型(可选,不接也完整可玩):

- `--backend llm`:先启动 LM Studio(或任何 OpenAI 兼容服务,默认 `localhost:1234`),载入一个指令模型(实测用 qwen-3-8b);
- `--backend slm`:嵌入式推理。需自行下载两样东西(体积原因未入库):[NobodyWho](https://github.com/nobodywho-ooo/nobodywho) GDExtension 放入 `game/addons/nobodywho/`,GGUF 权重(如 Qwen2.5-1.5B-Instruct-Q4_K_M)放入 `game/models/`。接线细节见 [docs/03](docs/03-LLM集成架构.md)、机型实测数据见 [docs/11](docs/11-LLM部署实测对比与选型.md)。

## 仓库结构

```
game/            Godot 4 工程(scripts/ 引擎与后端,data/ 数据驱动内容,scenes/ 测试场景)
  scripts/Sim.gd         仿真引擎:世界状态、tick、需求/效用 AI、合法候选接口
  scripts/AIBackend.gd   三档可插拔 AI 后端,超时/非法输出自动降级
  scripts/Memory.gd      记忆流:recency + importance + relevance 检索
tools/           Node 逻辑端口、soak 脚本、录屏出片流水线
docs/            设计、架构、评审、实测与实验札记(见下)
```

## 文档

| 文档 | 内容 |
|---|---|
| [01 产品愿景与玩法](docs/01-产品愿景与玩法.md) | 这是个什么游戏,核心循环,不做什么 |
| [02 技术架构](docs/02-技术架构-混合仿真.md) | 确定性引擎为底、LLM 为"声音"的混合仿真 |
| [03 LLM 集成](docs/03-LLM集成架构.md) | 三档后端、结构化输出、超时与降级 |
| [07 社交底座](docs/07-技术文档-社交底座.md) | 社交事务/关系账本/知识边界/承诺/冲突的实现 |
| [08 测试与验证](docs/08-测试与验证.md) | 33 条不变量清单、双引擎验证、复现方式 |
| [11 部署实测](docs/11-LLM部署实测对比与选型.md) | 各机型/各模型档位的真机延迟数据与选型 |
| [13 实验札记](docs/13-实验札记-experiment-journey.md) | 踩坑、翻盘与运气,按时间倒序 |

其余(愿景评审、前沿调研、规模化设计、手机可行性等)见 [docs/](docs/) 目录。文档为中文。

## 素材与许可

代码 MIT。像素素材来自 CC0 免费包(Puny World / Characters 等,出处清单见 [docs/09](docs/09-美术资产与版权.md));封面为 AI 生成。模型权重与 NobodyWho 二进制不随仓库分发,请从上游获取。

> 项目脱胎于作者此前一个 Godot 游戏评测流水线项目(headless 渲染/自动录屏/LLM-as-judge),部分文档提及该流水线时以"上游流水线"指代;本仓库自身不依赖它。
