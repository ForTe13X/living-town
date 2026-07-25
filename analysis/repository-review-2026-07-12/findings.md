# Detailed findings

## 分级说明

- **R0 — Release blocker**：不一定导致当前开发构建崩溃，但在公开发行前必须解决。
- **P1 — High**：会破坏核心语义、跨局一致性、主要玩法或 live-model 稳定性，应在继续扩功能前修。
- **P2 — Medium**：已经确认的正确性、性能、工程或用户体验缺口，应进入近期计划。
- **P3 — Low / design debt**：不会立即阻塞原型，但会持续放大维护和产品化成本。

“确认”表示可以从代码路径、现有数据或本轮实测直接复核；“风险”表示触发后果依赖运行环境或真实模型，报告会明确标注。

## R0 — 发行阻塞项

### R0-1：仓库内置 SimHei 字体没有可再发行证明

**证据**

- [`docs/09-美术资产与版权.md:54`](../../docs/09-美术资产与版权.md#L54) 明确写明 `game/assets/fonts/cjk.ttf` 来自本机 Windows SimHei，并要求正式发布前替换。
- 根 [`LICENSE:15-18`](../../LICENSE#L15-L18) 说明了像素资产、封面和 NobodyWho，但没有为该字体授予任何权利。
- 字体文件约 9.7 MB，已经被 Git 跟踪并会进入 `export_filter="all_resources"` 的 Android 包。

**影响**

当前开发和测试可继续，但在 GitHub release、商店包或公开试玩发行前，应把它视为阻塞项，而不是普通美术 TODO。

**建议**

换成明确允许嵌入/再发行的 CJK 字体（例如 OFL 字体），保存许可证全文与来源，生成 `THIRD_PARTY_NOTICES.md`，并在实际导出包中复核字体替换成功。

### R0-2：发行闭环缺少存档、依赖清单和可复现构建

**证据**

- [`Sim.export_trace()`](../../game/scripts/Sim.gd#L677-L683) 只有开发导出，没有 import/load、schema version 或迁移。
- `tools/bench-godot.ps1` 与 `tools/slm.Dockerfile` 依赖仓库外已有的 `gamecraft-runner:4.6.2` 镜像。
- 唯一 export preset 是 Android；版本仍为 `1.0/code=1`，图标为空，且 `export_filter="all_resources"`。

**影响**

生活模拟没有可恢复存档，不适合公开承诺持续游玩；新贡献者也无法只靠仓库稳定复现完整测试和发行包。

**建议**

公开试玩前至少完成：最小存档/load、依赖/模型/二进制 manifest、固定 Godot 版本、可从干净 runner 执行的桌面或 Web 导出，以及一份 release checklist。

## P1 — 核心正确性与稳定性

### P1-1：异步模型回包用“新候选集”解释旧编号

**确认。**

**证据**

- [`AIBackend.decide()`](../../game/scripts/AIBackend.gd#L304-L335) 每个等待 tick 都接收 Sim 当前重新枚举的 candidates。
- [`_fire()`](../../game/scripts/AIBackend.gd#L400-L415) 的 pending 只保存 deadline、raw、ready 和 HTTP 句柄，没有保存 prompt 对应的候选快照、稳定 key 或 hash。
- prompt 在请求发起时构建，但响应就绪后 `parse_decision(raw, candidates)` 使用的是当前 tick 的 candidates。

等待期间需求、位置、talking 状态、节日对象、承诺和候选排序都可能变化。结果仍可能是“当前合法动作”，但不是模型看到并选择的动作，直接破坏 say-do 一致性、决策可解释性与训练数据可信度。

**修复建议**

每个请求记录：`world_epoch`、`request_id`、`prompt_tick`、有序候选 stable keys、候选完整 hash 与 prompt version。回包先按旧快照解析出 stable key，再对当前 canonical candidates 重验；目标已失效就丢弃并 logic fallback 或重新询问。

### P1-2：HTTP 超时不取消真实请求，迟到回包可污染下一次请求

**确认。**

**证据**

- [`_finish()`](../../game/scripts/AIBackend.gd#L342-L352) 只停止/释放 `slm_chat`，没有对 pending 中保存的 HTTPRequest 调 `cancel_request()` 或 `queue_free()`。
- [`_fire_http()` 回调](../../game/scripts/AIBackend.gd#L428-L455) 只检查 `_pending.has(id)`，没有校验 request id、HTTP 节点身份或 world epoch。
- 请求立即失败时只把 pending 标成空 raw，HTTP 节点也没有立即释放。

场景：A 请求超时，逻辑把 `_inflight` 减回；同 NPC 发起 B；A 后来返回，回调发现该 NPC 又有 pending，于是把 A 的 raw 写进 B。与此同时，旧 socket 已不计入 `MAX_INFLIGHT`，真实请求数可以超过名义上限。

**修复建议**

统一 decision/chat/reflect/probe 的 request object；完成、失败、取消和超时只走一个 finalize 路径。超时必须取消底层请求、断开 callback、释放节点；callback 必须匹配 `(world_epoch, request_id)`。

### P1-3：重开、scrub、改 NPC 数会让 AI 状态跨局污染

**确认。**

**证据**

- [`Main._apply_npc()`](../../game/scripts/Main.gd#L457-L474) 直接 `Sim.start_new()`，没有先取消 AI pending。
- [`Main._scrub_to_x()`](../../game/scripts/Main.gd#L847-L851) 直接进入 `goto_tick()`。
- [`Sim.goto_tick()`](../../game/scripts/Sim.gd#L656-L676) 重建 Sim，却没有重置 AIBackend、禁用 live backend 或建立新 world epoch。

保留 id 的 NPC 可收到旧世界回包；被删除的 clone 不会再进入 `decide()` 完成清理，可能永久占用 pending/inflight。`reset_stats()` 也只是清字典和计数，不会取消真实节点。

**修复建议**

增加 `AIBackend.cancel_all(reason, next_epoch)`，所有 restart、scrub、切后端、换模型和 benchmark seed 切换都必须先调用；Sim start/replay 使用显式 run epoch。

### P1-4：live backend 拥塞与高倍速叠加时，等待决策的居民可能持续空等

**确认代码路径；实际频率依赖真实推理延迟。**

**证据**

- [`Sim.tick()`](../../game/scripts/Sim.gd#L685-L707) 每 tick 先衰减需求。
- pending 中或 `_inflight >= MAX_INFLIGHT` 时，[`AIBackend.decide()`](../../game/scripts/AIBackend.gd#L304-L341) 返回 `_wait`，Sim 不执行 logic fallback。
- UI 支持 8 倍速度；deadline 最低 3 秒、最高 12 秒。

当前 `MAX_INFLIGHT=2` 时，进入决策边界且受并发上限阻塞的居民不是走 logic，而是继续等待。8 倍速度下，3 秒约推进 300 个 sim tick；`hunger` 每 tick 衰减 0.28，足以从常见初始值降到 0。

**修复建议**

把模型变成非阻塞 suggestion：过载立即走 logic；仅在请求所属 agent 状态仍有效时采用回包。可以选择“先 logic 行动、模型只改 voice”，或在下一决策边界应用模型结果。不要用墙钟等待冻结 agent 行为。

### P1-5：职业 `extra_advertises` 注入顺序错误，“看摊”不可达

**确认，并由数据与运行结果交叉验证。**

**证据**

- [`Sim._load_data():249-261`](../../game/scripts/Sim.gd#L249-L261) 注入职业动作时，`world["objects"]` 仍是 JSON Array，却用 `world["objects"].has("counter_1")` 按字符串 id 查询。
- 对象到后面才转成 `id → object` Dictionary。
- `_jobs_injected=true` 在失败前已经设置，阻止重试。
- [`jobs.json:4-13`](../../game/data/jobs.json#L4-L13) 中阿丽与阿林依赖 `counter_1` 的“看摊”；30 天诊断里两者对应技能保持 Lv0。

**影响**

文档已经把职业、差异工资和技能进展标为落地，但其中一条主要职业链实际是死路径。

**修复建议**

先把 objects 转为 Dictionary 再注入，或在 Array 中按 `o.id` 查找。增加内容 lint：每个 `job.action` 必须至少由一个 advertise 提供；每个职业在定向短跑中必须出现候选并能完成一次。

### P1-6：时间轴只在纯 logic、无玩家干预的窄条件下可信

**确认。**

**证据**

- 窗口启动把 live [`AIBackend` 注入 Sim](../../game/scripts/Main.gd#L110)。
- [`goto_tick()`](../../game/scripts/Sim.gd#L656-L676) 只保存 `auto_run`，随后 `start_new()` 并紧循环 tick；没有暂时将 backend 设为 replay/logic，也没有自动装载 decision trace。
- 同一函数注释明确承认玩家历史动作不回放，得到的是“无玩家介入的平行世界”。
- `record_decisions` 默认关闭，生产 Main 没有启用；只有 S4 测试手动 set replay。
- 每次鼠标移动都可能从 tick 0 重演，且 replay tick 仍发送 UI signal。

**影响**

README 的“从任意 tick 重建世界”只对 logic、无玩家输入的运行成立。live model、玩家关系、承诺和记忆都可能在 scrub 后与原历史不同。

**修复建议**

短期把 UI 和 README 标成 `logic-only replay`，live/player 模式禁用或明确提示平行世界。长期把玩家输入、模型 pick、场景补丁和设置变更统一写入 versioned journal，并每 N tick 保存快照；scrub 使用快照 + 输入重放，禁用逐 tick UI 更新。

## P2 — 近期工程问题

### P2-1：candidate hash 无法保护按下标回放

**确认。**

[`_cand_hash()`](../../game/scripts/Sim.gd#L2383-L2388) 先排序且只哈希 `action/partner/subject`，遗漏 `kind/target/need/amount/duration`。候选重排时 hash 不变，而 [`_resolve_replay()`](../../game/scripts/Sim.gd#L2404-L2411) 仍按旧 index 读取当前数组；多张床这类同 action、不同 target 的替换也无法检测。

应定义稳定、完整、有序的 candidate identity；trace 记录 stable key，回放按 key 找候选，不按脆弱下标。

### P2-2：`agent_apply()` 没有真正守住合法候选边界

**确认。**

[`_apply_object()`](../../game/scripts/Sim.gd#L1134-L1147) 只检查 target 存在，随后信任 intent 中的 need/amount/duration；`dur_total=0` 会在推进时除零，未知 need 会索引失败。[`_apply_social()`](../../game/scripts/Sim.gd#L1150-L1164) 也不重新验证 action、subject、库存、叠约或当前对象状态。

内建 parser 通常复制候选，因此普通 logic 路安全；但可插拔 backend、陈旧回包和扩展会绕过这个假设。最稳的 API 是只接收 candidate key，让 Sim 从 fresh canonical candidate 中取整条对象并在 commit 前重验。

### P2-3：闭集解析会把自然语言首字母当成编号

**确认。**

[`parse_decision()`](../../game/scripts/AIBackend.gd#L356-L386) 扫描前六字符中第一个 `0-9/A-Z`。候选足够多时，`The answer is 2` 会先把 `T` 解释为候选 29；`I choose A` 会把 `I` 当候选 18，而不是失败。

应只接受 trim 后完整单字符响应（或严格封装格式），再做 JSON fallback；任何 prose 都应 fail closed。

### P2-4：scriptwriter 的关系字段 schema 与核心约束冲突

**确认。**

核心 `standing` 上限是 ±3；scriptwriter prompt 却声明 ±100，validator 又对所有关系字段统一 clamp ±100，`DataScenarioProvider` 随后直接赋值。生成场景可在开局绕过领域约束。

应建立字段级 schema：例如 standing `[-3,3]`、resentment `[0,100]`、trust/affinity `[-100,100]`，并让 provider 共享同一个 validator。

### P2-5：README 验证、专项测试与当前内容已经漂移

**确认并实跑。**

- [`README.md:35-53`](../../README.md#L35-L53) 的 Node 30 天命令失败 #5/#8/#20；Godot 30 天命令失败 #8。
- 60 天、12 seed 的正式 S0 门全部通过，说明问题是公开门定义与当前统计窗口不一致，而不是核心全面损坏。
- [`player_agency_test.gd:43-46`](../../game/scripts/player_agency_test.gd#L43-L46) 仍硬编码 6 NPC + 玩家 = 7；当前是 12 NPC + 玩家 = 13，测试因此退出 1，其余断言通过。
- 仓库没有 `.github/workflows`。

建议将 S0 作为唯一 canonical 门；README 使用短 smoke（只检查启动/退出码）或明确用 60 天。Node 端口要么建立 parity contract，要么降级为“历史/分析切片”，不要继续宣称共享同一逻辑。

### P2-6：Godot 4.6 需要的 `.uid` 与 `.import` 被全局忽略

**确认。**

[`.gitignore:16-18`](../../.gitignore#L16-L18) 忽略全部 `*.import` 与 `*.uid`；本机导入后在 `game/` 下可见 715 个 `.import` 和 38 个 `.uid`，跟踪数均为 0。

Godot 官方明确要求将 4.4+ 的 `.uid` 提交版本控制；4.6 import 文档也要求提交相邻的 `<asset>.import` 元数据：[UID changes coming to Godot 4.4](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)，[Godot 4.6 import process](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/import_process.html)。

应移除宽泛 ignore，重新导入并审查生成文件，然后在 CI 干净 clone 上验证无 fallback UID warning、无意外 import diff。

### P2-7：`Sim.gd` 是 God Object，固定执行顺序也是隐藏实验变量

**固定顺序代码路径已确认；实际公平性影响尚未量化。**

`Sim.gd` 2,423 行，拥有需求、社会、承诺、冲突、秘密、派系、经济、世界、LOD、回放等多数领域。Agent 是大量动态键组成的 Dictionary；AI、UI 和 scenario provider 又直接访问 Sim 私有字段/函数。

每 tick 按 agents JSON 固定顺序立即衰减和提交，先执行者能先占用 talking 对象，名单顺序因此成为隐藏社会优势变量。确定性保住了，但公平性/实验外部效度受影响。

应逐步拆成薄 scheduler + typed stores/systems；若改两阶段 intent/commit，必须以冻结 digest 和因果 bench 保护现有语义。执行顺序可用稳定 id 或 seed/tick 轮转，避免永久名单优势。

### P2-8：append-only 历史仍在热路径

**确认。**

虽然承诺结算引入 `_active_commitments`，但 [`_attend_candidates()`](../../game/scripts/Sim.gd#L1108-L1122)、[`_find_commitment()`](../../game/scripts/Sim.gd#L1519-L1524) 与 WorldView 每帧仍扫描全历史 commitments；冲突和 UI 也有类似全量扫描。`goto_tick()` 还始终从 0 重演。

长局成本会随历史线性增长。应维护 active set、id index、按 agent read model 和周期快照；审计历史与运行热数据分开。

### P2-9：不可信文本可注入 BBCode，外部模型数据边界也不透明

**确认。**

HUD RichTextLabel 开启 BBCode，玩家输入与 LLM 回复未经 escape 就拼入日志。`[color]`、`[url]` 等输入可伪造界面。远程 endpoint 可从 CLI 指向任意 HTTP 地址，玩家文本与近期记忆会被发送；UI 没有远程数据提示。

统一 escape BBCode；若正式支持远程服务，只允许 HTTPS、显式显示数据去向，并从安全配置读取 token。默认 localhost 风险较低，但不能把“通常本地”当安全边界。

### P2-10：Android 权限与模型导入方式不适合发行默认值

**确认配置，商店影响需在发布渠道再次核对。**

[`export_presets.cfg:61`](../../game/export_presets.cfg#L61) 请求 `MANAGE_EXTERNAL_STORAGE`，只是为了扫描 Documents/Download 中的 GGUF。权限范围远大于读取一个用户选择文件，会增加安装信任与审核风险。

优先采用系统文件选择器或 app-specific storage；模型导入后复制到 app 私有目录并记录 hash，不要默认申请全盘文件管理。

### P2-11：文档链接、当前状态与构建说明发生漂移

**确认。**

- 7 个失效图片引用：[`README.md:24`](../../README.md#L24)、[`README_EN.md:24`](../../README_EN.md#L24)、[`docs/07-技术文档-社交底座.md:8,110,128,141`](../../docs/07-技术文档-社交底座.md#L8)、[`docs/08-测试与验证.md:76`](../../docs/08-测试与验证.md#L76)。
- [`docs/18-android-apk-build.md:19`](../../docs/18-android-apk-build.md#L19) 引用不存在的 `tools/build_android.ps1`。
- README 写 35 条不变量，当前 Harness 运行 37 条。
- 历史文档同时保留不同阶段的“当前结论”，没有 Current / Design / Experiment / Historical 标签。

建议增加 `docs/README.md` 作为唯一当前索引，历史实验保留但明确状态；CI 执行相对链接检查。

### P2-12：资产获取与仓库体积存在供应链和协作成本

**确认。**

- `tools/fetch_assets.py` 从固定 URL 下载但没有 SHA256，且对远程 zip 直接 `extractall()`，缺少 path traversal 检查。
- Git pack 约 100.6 MiB，最大的跟踪对象主要是演示 MP4/GIF；没有 `.gitattributes` 或 Git LFS 策略。
- Docker base 与 apt 包没有 digest/lock，NobodyWho 也没有统一版本、URL、hash、许可矩阵。

建议给每个下载物固定 hash，安全解包；二进制演示迁移到 GitHub release/LFS，README 保留轻量 GIF/封面；生成 `dependencies.lock.yml` 与 `THIRD_PARTY_NOTICES.md`。

## P3 — 产品化与维护债

### P3-1：记忆 relevance 已实现但生产调用基本传空标签

`Memory.retrieve()` 支持 recency + importance + relevance，但自由对话、prompt 与夜间反思多传空 tags，当前实际主要是 recency/importance。应把人物、地点、动作、关系和话题 tags 接入，并给长期记忆做 retrieval quality 测试。

### P3-2：主场景与 UI 全由 935 行脚本手工构建

`Main.tscn` 几乎只有根节点；HUD、设置、观察台、输入、demo、回放和启动都集中在 `Main.gd`。这会妨碍响应式布局、组件测试和编辑器协作。逐步拆成独立 `.tscn`/Control 组件，并把开发 observatory 与玩家 HUD 分层。

### P3-3：扩展 `freeze()` 只排序，不真正冻结

`SimExtensions.freeze()` 后仍可 register，没有重复 id、接口契约或 frozen guard。错误 provider 会到 dispatch 才崩，运行时注册还可能改变 replay 顺序。应验证接口、拒绝重复/冻结后修改，并给扩展只读 SimulationContext。

### P3-4：英文 README 不等于英文产品，可访问性和音频也未成层

UI 与内容大量硬编码中文；输入使用物理 keycode 而非 InputMap，按钮多为 `FOCUS_NONE`，固定 1280×768/12–14px 文本在手机上偏小；仓库也几乎没有游戏内音频。

建议从 InputMap、焦点导航、UI scale、点击动作栏、`tr()` 和少量环境/事件音效开始。这些对“治愈、低压、会生活的小镇”的感知收益，很可能高于再增加一个模拟子系统。

## 未列为缺陷的事实

- S0 12 seed × 60 天与 S5 因果门本轮均通过；确定性地板整体健康。
- S4 replay 在同版本、同数据、显式注入 trace 的测试场景中通过；问题是生产接线和跨版本 candidate identity，而不是该测试本身作假。
- `.godot/`、模型权重、原生 NobodyWho 二进制、keystore 与 `build/` 被忽略是合理的；问题只在额外忽略 `.uid/.import` 和缺少可复现安装说明。
- 本轮没有发现被提交的真实 API token、release keystore 或模型权重。
