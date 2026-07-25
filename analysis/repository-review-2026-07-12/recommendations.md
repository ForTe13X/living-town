# Recommendations and roadmap

## 目标

下一阶段的目标不应是“再多一个系统”，而应是：

> 一个新玩家可以从干净安装开始，在没有模型的情况下玩 20–40 分钟；能理解自己造成的社会后果；能保存、继续和可靠回看；开启模型后只增加角色感，不降低正确性。

## Phase 0 — 先止血（首个修复批次）

### 1. 统一 AI 请求生命周期

把 decision、chat、reflect、probe 收到一个 scheduler，最小数据结构：

```text
Request {
  world_epoch, request_id, agent_id, kind,
  prompt_tick, prompt_version,
  ordered_candidate_keys, candidate_hash,
  deadline_ms, transport_handle, state
}
```

要求：

- callback 必须同时匹配 epoch + request id，不能只按 NPC id。
- timeout/cancel/error/success 共用一个 finalize 路径；底层 HTTP/SLM worker 必须真正停止并释放。
- restart、scrub、换 NPC 数、换模型、切 backend、benchmark 换 seed 前统一 `cancel_all()`。
- 模型过载时立即走 logic，不让 agent 因等待停止生活。
- 回包按旧候选 stable key 解码，再对当前候选重验；失效就 fallback，不把旧 index 套到新数组。
- 自由对话加 per-agent busy、全局并发上限、取消与错误 fallback。

**验收**

- 人为让 HTTP A 超时，再发 B，A 迟到不能改变 B。
- restart 后所有旧 callback 都被忽略，节点数和 inflight 回到 0。
- ×8 + 12 秒 fake latency 跑 30 天，不出现因模型等待造成的 need 触底。
- 候选在请求期间重排/删除时，模型不会执行另一个动作。

### 2. 修职业接线与合法候选边界

- objects 先转 Dictionary，再注入 `jobs.extra_advertises`。
- `agent_apply` 只接受 candidate stable key；由 Sim 从当前 canonical candidates 取完整 intent。
- 增加 jobs/advertises/action/executor 外键 lint。

**验收**

- 阿丽与阿林的“看摊”在 prompt preview 中出现。
- 短跑中至少完成一次看摊、获得正确职业工资并推进技能。
- 畸形 backend intent（未知 need、duration=0、非法 invite）全部安全 fallback，不报错、不改状态。

### 3. 建最小 CI

第一版只需要一个 3–5 分钟内完成的 workflow：

1. 固定 Godot 4.6.2，项目 import/parse smoke。
2. S0：12 seeds × 60 天、det=3。
3. M2 parse/mock、S4 replay、player agency。
4. JSON parse + schema + 外键 lint。
5. Markdown relative-link check。
6. 检查工作树在 Godot import 后没有意外 diff。

Node 端口有两个可选策略：

- **推荐**：明确为历史/快速分析切片，不再作为 canonical parity gate。
- 若必须保留双运行时：建立相同 seed/data/trace 的语义 parity 测试，并让两端共享生成的规则/fixture，而不是手工复制 1,279 行逻辑。

### 4. 修公开入口与发行阻塞

- README 快速命令换成当前稳定命令；30 天单 seed 只能叫 smoke，不能叫完整门。
- 修 7 个图片引用与缺失的 Android build script 说明。
- 移除 `*.uid/*.import` 的宽泛 ignore，审查后提交必要元数据。
- 换掉 SimHei；补 `THIRD_PARTY_NOTICES.md`。
- 给下载资产、NobodyWho 和模型示例加 URL、版本、SHA256 与许可证字段。

## Phase 1 — 做成可玩的垂直切片（1–2 周）

### 1. 启动时明确三种模式

不要把玩家模式藏在 CLI：

- **观察小镇**：当前 observatory 体验，适合放置/社会显微镜。
- **作为居民入住**：创建玩家，提供移动或点击导航、动作栏与轻目标。
- **开发观测台**：完整状态、性能、trace 与调试控制。

三种模式可以共享 Sim，但 UI 信息密度和输入不同。

### 2. 把“社会显微镜”变成核心玩法

当前项目最独特的不是更多 NPC，而是能解释事情为何发生。把原始账本转成玩家可读的因果卡：

```text
你替阿本说情
  → 可可写下“玩家愿意帮忙”
  → 对玩家信任 +8
  → 第 3 天把秘密告诉玩家
  → 秘密被转述后引发阿丽与阿本的冲突
```

优先做：

- “为什么发生”按钮：展示 3–6 个关键上游事件。
- 未解决承诺、冲突、秘密与居民心愿列表。
- 玩家影响摘要：本日/本周因你发生的变化。
- 轻量委托：撮合、查明传闻、劝和、筹办活动、帮助某人守约。

这会把已有系统直接转化为游戏性，而不需要先扩地图。

### 3. 一局 20–40 分钟的目标结构

建议做一个很小的“灯会周”垂直切片：

- 开场：玩家入住，认识 3 位关键居民。
- 中段：一个约会承诺、一条秘密和一次选举形成交叉冲突。
- 玩家选择：保密/转述、撮合/拆散、支持/反对公共项目。
- 结尾：灯会当天用因果卡总结不同人的关系与镇级结果。

胜负不是传统分数，而是 2–3 个可读结局与一张“你改变了什么”报告。

### 4. 输入、移动端与可访问性

低成本顺序：

1. 使用 InputMap，不再直接匹配物理 keycode。
2. 恢复按钮 focus，支持键盘/手柄导航。
3. 增加 UI scale、字号和高对比设置。
4. 玩家动作做成可点击 action bar；移动可用点击目标或虚拟摇杆。
5. 模型导入使用系统文件选择器或 app-specific storage，移除全盘文件管理默认权限。

### 5. 最小音频层

先不要做昂贵 TTS。少量可再发行的环境与事件声音就能显著提高生活感：

- 清晨/夜晚环境循环
- 脚步、门、礼物、争执、和解、节日提示
- 重要事件与因果卡的轻提示音

## Phase 2 — 存档与真实回放（1–2 周，可与 Phase 1 并行）

### 1. 明确权威数据

建议存档由以下部分组成：

```text
SaveHeader { schema_version, game_version, content_hash, created_at }
Snapshot   { tick, deterministic world state }
InputLog   { player actions, model picks, scenario patches, settings changes }
Meta       { display name, playtime, thumbnail, backend provenance }
```

`event_log` 是审计输出，不应单独充当恢复输入。模型自由文本可以保存用于展示，但决定世界状态的是 candidate stable key。

### 2. 快照 + 增量重放

- 每 1–2 个游戏日保存轻量快照。
- scrub 先载最近快照，再重放外部输入到目标 tick。
- replay 期间禁止 live backend、音频副作用和逐 tick HUD 更新。
- 所有 candidate identity 使用有序完整 hash；跨版本不匹配时明确报告 drift，绝不静默套旧 index。

### 3. 回放模式的诚实分层

- `Replay exact`：同版本 + 同 content hash + 完整 input log，可精确回放。
- `Replay migrated`：迁移后尽力重放，显示 drift 数量。
- `What-if`：故意移除玩家/模型输入的平行世界，作为玩法功能而不是冒充原历史。

现有“无玩家介入的平行世界”其实可以保留，但应改名为 What-if。

## Phase 3 — 可维护架构与内容生态（2–6 周，渐进进行）

### 1. 不做大爆炸重写

保持 digest/bench 为安全网，按热路径拆：

1. `RequestScheduler`（AI lifecycle）
2. `CommitmentSystem` + active/id indexes
3. `ReplayStore` + snapshots/input log
4. `Economy/JobsSystem`
5. `SocialSystem`
6. `WorldState/WorldPatch`

Sim 最终只负责稳定阶段顺序。每次迁移只动一个系统，并冻结基线 digest 或明确记录预期变化。

### 2. 从 Dictionary 走向明确 schema

不必一次改成复杂 class hierarchy；先做 typed accessors 与 schema validator：

- Agent/Relationship/Candidate/Event/Commitment 的必填字段与范围。
- JSON Schema + cross-file ID checks。
- 数据包的 `schema_version`、兼容区间和 content hash。
- “新增 NPC / 职业 / 节日 / 建筑 / 场景”的最小示例。

### 3. 解决固定名单顺序偏差

先量化再改：按 agent id 统计首发社交率、候选命中与接受率。若顺序效应明显，可采用：

- tick/seed 驱动的稳定轮转；或
- 两阶段 tick：从只读快照收集 intents，再统一仲裁/提交。

任何改变都必须跑 S0、S5 与新的公平性指标，避免为“理论公平”破坏现有社会动态。

## Phase 4 — 模型价值验证，而不是先做模型发行

NPU/ranker 研究可以继续作为 lab，但产品主线应先回答：语言到底让游戏更好了吗？

建议盲测三档：

- logic pick + frozen voice
- distilled ranker pick + frozen voice
- LLM/SLM pick + frozen voice 或自然 voice

指标不要只看 teacher-match 或毫秒数，还要看：

- 玩家能否区分角色
- 故事是否更可读、更一致
- 玩家是否更愿意回访某位 NPC
- 错动作、超时、重复台词和 replay drift
- 每 30 分钟耗电、内存与模型等待造成的 gameplay disruption

只有模型带来稳定、可感知的玩家收益，才继续 Tier 2/NPU 发行集成。否则把模型保留为 opt-in flavor，logic/ranker 作为主路径。

## 建议暂缓的工作

- 在垂直切片完成前继续扩 NPC 数与地图尺寸。
- 在存档/回放未闭环前继续增加更多外部非确定输入。
- 在模型价值 A/B 未证明前投入商店级 NPU runtime 打包。
- 大爆炸式拆 `Sim.gd`。
- 再写一份“当前状态”文档；应先建立唯一 Current Status 索引。

## 90 天结果定义

如果按以上顺序推进，90 天后理想交付不是“系统更多”，而是：

- 干净 clone 能自动测试和导出。
- 公开验证命令全部绿色。
- 无发行权利不明的字体/资产。
- 玩家从 UI 选择模式并完成一局灯会周。
- 能保存/读取，scrub 不跨局污染。
- live model 迟到、超时、切换和重启都有确定行为。
- 玩家能看到一条由自己触发的、可解释的社会因果链。
- 是否继续投入 ranker/NPU 有真实玩家数据支撑。
