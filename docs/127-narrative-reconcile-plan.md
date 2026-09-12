# 127 · 叙事子系统 reconcile 立项方案（AH1 只读调研棒）

> 作者：AH1 叙事 reconcile 只读调研棒（隔离 worktree）。**本文是立项材料，不是执行。**
> 目标：让用户/协调者能决定"叙事怎么并、并哪些、哪层先并、哪层 gated 在 S18"。
> 只读，不合并、不实现。本棒只写这一个文件。
>
> 基线（实测于 2026-08-06）：
> - trunk = `origin/integration/batons` HEAD `3da64b6`（本棒已 ff 到它）。
> - narrative = `origin/codex/narrative` HEAD `c107296`（只 `git show`/`git diff` 读，从不 checkout）。
> - merge-base = `dae2fbe`（2026-08-02 12:46）。narrative 从这里分叉，加了 60 path/8193 行；trunk 从这里前进，改了 84 path。
> - **两侧文件交集 = 0**（本棒独立复核，`comm -12` 为空，与 Codex §三.8 收敛）。
> 前置阅读：`docs/41` §0.8/§0.7/红线、`docs/113` §〇/§一/§三、`docs/116`（AD2 事件结果模型）、`docs/62`、`docs/47`（R12）、`docs/107@codex/narrative`（叙事 20 棒计划）。

---

## 〇、三条要先纠正协调者/路线图的实测（照 docs/41 §4）

协调者的任务书与 `docs/113` §〇 有三处坐标/断言，本棒实读后不成立，先纠正——它们改变整个方案的形状：

### 更正 1：**"两边都动了 `docs/README.md`/`docs/05` 的语义" 不成立**（这不是双向冲突，是单向漂移）

`docs/113` §〇 与本棒任务书都写"两边都动 `docs/README.md`/`docs/05` 的语义 ⇒ 语义 reconcile"。**实测 blob 哈希**：

| 文件 | merge-base `dae2fbe` | trunk `integration/batons` | narrative `codex/narrative` |
|---|---|---|---|
| `docs/README.md` | `7a9a5da` | **`7a9a5da`（与 merge-base 逐字节相同）** | `c57c83c`（改了） |
| `docs/05` | `7bbdc30` | **`7bbdc30`（与 merge-base 逐字节相同）** | `a5d2e54`（改了） |

⇒ **trunk 自 merge-base 起【从未碰过】这两个文件**，只有 narrative 改了。原因：trunk 已把路线图维护迁到 `docs/113`（"维护者：主集成会话"），`docs/05` §A 自己写"权威计划是当波的编号文档，不是本 §A"——于是 trunk 让 `docs/05` 冻在 `dae2fbe`。**根 `README.md`（项目根，非 `docs/README.md`）两侧相对 merge-base 也都没动**（不在任一侧 diff 里）。

**这把 reconcile 的性质从"合并两份打架的编辑"降级成"narrative 单方面编辑了两个 trunk 冻结的文件"**——没有文本冲突，真正的问题是 narrative 那两份编辑相对 trunk 的**当前真实状态**是不是仍然对。见 §四。

### 更正 2：**"~60 path / 8k+ 行" 高估了要审的代码面**（8k 里只有 ~1460 行是生产代码）

8193 行按类型拆开（本棒 `git diff --numstat` 实测）：

| 类型 | 文件数 | 新增行 | 说明 |
|---|---:|---:|---|
| 生产视图 GDScript | 5 | **1460** | 全部只读、NOT_SIM（见 §三） |
| GDScript 测试 | 4 | 1136 | 独立 scene 测试，喂合成态 |
| Godot 场景 `.tscn` | 4 | 24 | 测试壳 |
| 提交的 JSON fixtures/receipt | 3 | 1904 | S16 committed trace + 来源回执 |
| 评审媒体 + 验证/渲染工具（`analysis/narrative_visual/**`） | 36 | 3455 文本 + 14 个二进制（~1.45 MB） | png/mp4/py/ps1/manifest/report |
| 外部 lab CI 基线证据（`analysis/nlab_baseline/**`） | 5 | ~1160 | union 基线全绿回执 |
| 文档 | 3 | 159 | `docs/05`/`107`/`README` |

⇒ **要"吞入"的真代码只有 5 个 `.gd`（1460 行）**，其余是测试、提交 fixture、评审媒体、验证工具、CI 证据。而且**可执行的叙事引擎（reducer/ledger/replay/epistemics，即 20 棒里的 S01–S05/S07–S12）根本不在 `codex/narrative` 里**——它在**独立外部 lab 仓** `E:/Documents/Dev/living-town-narrative-lab`（`docs/107@codex/narrative` §一注明）。`codex/narrative` 只是那套引擎**朝主仓的只读投影+视图子集**。"别整支吞入 8k 行"方向对，但实际代码面比听上去小得多、且**全是只读**。

### 更正 3：**叙事当前【不消费】Sim 的 event/relationship schema**（它消费自定义的合成 schema）

任务书问题 5 假设叙事"消费哪些 event/relationship schema（`accepted`/`witnesses`/关系/信念字段）"。**实测：今天一个都不消费。** 5 个视图组件全部消费 narrative **自己定义**的 S06 十字段 snapshot 与 S16 committed-trace schema（见 §五 Tier-1），这两套都标 `"simulation": "NOT_SIM"`、`"production_gate": false`。**Sim schema 的耦合要到 S14（真实 actor 只读投影）与 S18（写侧）才发生**——那才是要冻结的接口面（§五 Tier-2）。这个事实正是"先并层可以零 schema-freeze 风险地先并"的根据。

---

## 一、60-path 分类表（代码子系统 vs 评审媒体/分析产物）

| # | 类别 | 路径（前缀） | 文件数 | 进 trunk？ | 依据 |
|---|---|---|---:|---|---|
| A | **生产视图代码**（只读） | `game/scripts/narrative/{NarrativeGlyphs,NarrativeViewContract,RolePOVCard,WebMazeGraph}.gd` + `game/narrative_lab/s16/scripts/S16Compositor.gd` | 5 | **是（先并层）** | 只读、NOT_SIM、零金标（§三） |
| B | **GDScript 测试 + 场景** | `game/scripts/narrative/tests/*.gd`（2）、`game/scenes/narrative/*.tscn`（2）、`game/narrative_lab/s16/tests/*.gd`（2）、`game/narrative_lab/s16/scenes/*.tscn`（2） | 8 | **是（先并层）**，但需接 CI 门 | 独立 scene 测试，喂合成态；**当前无 CI 接线**（§二·门） |
| C | **提交的 fixtures** | `game/narrative_lab/s16/fixtures/{s16_compositor_projection,source_receipt}.json`、`game/narrative_lab/s16/.gitattributes` | 3 | **是（先并层）**，随 A/B | committed trace，SHA256 锚死、fail-closed 加载 |
| D | **评审媒体 + 验证/渲染工具** | `analysis/narrative_visual/{s13,s16,s17}/**` + `v0_contract.txt` | 36 | **默认不进 trunk** | 14 个二进制（~1.45 MB）+ py/ps1 验证器 + manifest；是评审产物不是出货码（§二·媒体政策） |
| E | **外部 lab CI 基线证据** | `analysis/nlab_baseline/**` | 5 | **默认不进 trunk** | `9bad1f4` union 全绿回执；一次性证据，非活门 |
| F | **文档** | `docs/05`、`docs/107@codex/narrative`、`docs/README.md` | 3 | **是（语义 reconcile 后）** | 见 §四 |

合计 5+8+3+36+5+3 = **60**。分类口径：**A/B/C 落在 `game/**` 会被 Godot `--import` 加载/被测试运行 ⇒ 是"进代码树"的东西；D/E 落在 `analysis/**` 是评审产物**。

---

## 二、可分层合并的边界——先并层 / 后置层

Codex：**叙事自己的生产门仍 NO-GO（S18 未裁决）**，所以别整支吞。`docs/107@codex/narrative` 把这条写得更精确：它的**内部停止线是 S12 promotion audit**，而**S18 gates 的是 Sim 【写侧】**（"未经 S18 与新一轮 R12 brief，不开唯一的 Sim 写侧棒"）。只读主仓组件（S06/S13/S16/S17）**不 gated 在 S18 上**——只有写侧 gated。这就是分层线。

### 先并层（可先开只读 PR）——带读码证据 + R1 零金标判断

| 组件 | 文件 | 读码证据（为什么能先并） | R1 |
|---|---|---|---|
| **S06 只读投影边界** | `NarrativeViewContract.gd`（288） | `class_name ... extends RefCounted`，**全 static 纯函数**；输入是一个 `pre_state: Dictionary`，输出角色过滤后的**ID+时钟+状态枚举** snapshot；显式注释"claim prose / receipt bodies / fragment bodies / the global ledger **never cross the boundary**"；强制 epistemic locality（角色只见自己 visible 的 node/edge/fragment/receipt）。**零 `Sim.`、零 `randi/randf/randomize`、零 `Time.*`、零写世界态。** | 零金标 |
| **S13 glyph 绘制** | `NarrativeGlyphs.gd`（117） | 纯 `static func draw_glyph(canvas, kind, bounds...)`，只 `draw_colored_polygon`/`draw_line`/`draw_circle`。纯 `_draw` 几何，无状态、无 RNG。 | 零金标 |
| **S13 maze 视图** | `WebMazeGraph.gd`（148） | `extends Control`，只读 view；`set_snapshot()` 先 `_shape_errors()` **fail-closed 拒任何多余键**，再 `snapshot.duplicate(true)` 防御拷贝、`queue_redraw()`。`snapshot_fingerprint()` 用**字符串拼接**（非 `String.hash`）。只画，不写。 | 零金标 |
| **S13 POV 卡** | `RolePOVCard.gd`（115） | 同 `WebMazeGraph`：`extends Control`，消费同一 10 字段 snapshot，fail-closed，只画 Label+glyph。 | 零金标 |
| **S16 只读合成器** | `S16Compositor.gd`（792） | 头注释"**Fail-closed, read-only compositor** ... **never owns simulation state and never writes trace data back to disk**"。唯一 I/O 是**读**一个 committed fixture：`FileAccess.file_exists` → `get_sha256` 比对 `FIXTURE_SHA256`（不符即 `_render_failure`）→ `open(READ)`；再校 `schema=="living-town-s16-compositor-projection/v1"`、`authority=="projection_only"`、`mode=="READ_ONLY_COMMITTED_TRACE"`。**无 `ResourceSaver`/`save_png`/写回；无 RNG/`Time.*`/`OS.*`。** 发 `action_dispatched` 信号但不写世界态。 | 零金标 |
| **测试+场景** | 类别 B 8 文件 | `s13_visual_test.gd`：`extends Node`，"projects one **synthetic** authority state through S06, renders only the ten-field snapshots, measures real pixels"，带 `HIDDEN_*_DO_NOT_RENDER` 常量做**隐藏文本零泄漏**负控 + `_negative_control` 臂。**喂合成态，不起 Sim。** | 零金标 |
| **committed fixtures** | 类别 C 3 文件 | `source_receipt.json` 自陈 `"simulation":"NOT_SIM"`、`"production_gate":false`、`"authority":"projection_only"`。数据来自外部 lab（`lab_commit 1a195e0`），非 Sim。 | 零金标 |

**先并层为什么整体零金标（结构证明，不止逐文件）**：
- narrative **触碰的既有 sim/金标文件 = 0**（本棒 grep 60-path 列表：无 `Sim.gd`/`Invariants`/`Harness`/`game/bench`/`game/data`/`autoload`/`project.godot`）。全部是**新目录下的新文件**。
- 无 autoload 注册、无 `project.godot` 改动 ⇒ 这些 `.gd` **不在 Sim/Harness/DetGate 的任何执行路径上**，S0 网格评分时永不加载。
- `class_name` 无冲突（trunk 无同名 `NarrativeGlyphs/NarrativeViewContract/RolePOVCard/WebMazeGraph/S16Compositor`，本棒 grep 确认）⇒ 不撞 Godot 全局类注册。

### 后置层（gated，必须后置）——带证据

| 部分 | 出处 | 为什么必须后置 | gate |
|---|---|---|---|
| **S14 真实 actor/space/portal 只读投影** | `docs/107@codex/narrative` §二 S14 | 它第一次**读真实 Sim 态**（actor/space/portal）投影给 maze。虽仍只读、要求"投影前后主 digest 相同"，但它**耦合 Sim 关系/空间 schema**（§五 Tier-2），而那些字段 trunk 在飞（AD2/AG1/state_projection 未定）。 | 需 §五 Tier-2 冻结 |
| **S18 integration RFC** | `docs/107@codex/narrative` §二 S18 + §三 9 条 | 把时间/移动/收据/存档/回放/hash/迁移**逐项拍 accepted/rejected/replaced**。这是**架构级设计** ⇒ 触发 `docs/41` §0.8（外部对抗评审 + 多棒），**用户拍板**。 | §0.8 + 用户 |
| **唯一 Sim 写侧棒** | `docs/107@codex/narrative` §三末 | 真正把叙事结果写回 Sim（custody/receipt/edge 进 digest）。**动金标** ⇒ 走完整 `docs/47` R12（双烘 + 留出种子 + `rebake_history`）。 | S18 + R12 + 用户 |
| **storylets 内容扩张（S09–S11、S15，32–36 篇）** | `docs/107@codex/narrative` §二 | `docs/113` §三"在其上做 storylets"。内容依赖 schema 冻结，且大多仍在外部 lab，`codex/narrative` 里没有。 | schema 冻结后 |

---

## 三、确定性红线（R1）——先并层零金标的证明方法

**判定**：先并层（类别 A/B/C）**碰 `Sim.gd` 仿真态 = 无、碰金标路 = 无、碰 RNG = 无**。证据：
- 60-path 列表对既有 sim/金标文件命中 **0**（上 §二）。
- 5 个 `.gd` 全文 grep `randi|randf|randomize|Time\.|String\.hash|Sim\.|event_log|beliefs|attitudes|save_game|autoload|ResourceSaver`：**唯一命中是一个 UI 节点名 `permanent_not_sim_accent`**（S16 banner 里字面写着"不是 sim"的装饰条）。无一处真调用。
- `S16Compositor` 唯一 `FileAccess` 用法是**读** committed fixture 并 SHA256 fail-closed；无任何写。

**怎么证（照本仓规格：自造 A/B + 留出种子 + 三锚）**——这是先并层 PR 回执必须带的：
1. **三锚 A/B**：在 trunk 冻结 SHA 上跑 `GODOT=... bash tools/ci.sh` 第 4 步（S0 门：12 seed × 60 天），记三锚——**golden digest（12/12）、DetGate scenario digest（16/16）、逐 tick 前缀链**——**加入 narrative 文件前 / 后各一次**，断言三锚逐字节相同。因文件对 Sim 惰性，digest 不可能动；A/B 把"不会动"从假设变成实测。
2. **留出种子**：`--seeds 13-30 --days 60` 改前/改后各跑，两侧数字都报（`docs/41` §3.4）。
3. **负控（证 A/B 有牙）**：先并层不含任何能动 digest 的 Sim 改动，所以"改后=改前"必须配一个**已知能动 digest 的对照**才有意义——引用现成的 BackendGate/DetGate 负控（它们证明真 Sim 改动会红），说明本层的"零位移"不是因为门瞎。
4. **import/parse 预飞**（`docs/41` §1 的坑）：**先单独跑 3 个 narrative 测试 scene + `ci.sh` 第 3 步 `--import`**，确认新 `.gd` 都 parse 通过、测试 headless PASS——**bench/scene 的 parse error 会让 CI 永远挂住而不是变红**，必须在跑全量前排掉。

**一个必须写清的边界（不是金标位移，别误判）**：加入 `game/scripts/narrative/*.gd` 会改变 `game/scripts/` **子树哈希**。`docs/113` §六："`game/scripts/`+`game/data/` 逐字节相同是【必要】不充分"——所以任何**pin 该子树哈希的 provenance 锚会合法地变**。这是**加法式合并的必然产物，不是 R1 违反**（S0 digest 不动）；若确有子树锚，按 R12 rebake 文化补一条 note 即可。可比性还要求把 Godot 版本/addons/scenes 一并写进 provenance（`docs/113` §六），不能只看那两个目录的 diff。

---

## 四、`docs/README.md` 与 `docs/05` 的语义 reconcile 策略

**前提（§〇 更正 1）**：trunk 没碰这两个文件，只有 narrative 碰了 ⇒ **无文本冲突**。真问题是 narrative 的编辑相对 trunk 当前状态**是否仍对**。

### `docs/README.md`（narrative 的编辑：`7a9a5da`→`c57c83c`）
- narrative 做了什么：把索引头 `53-102`→`53-107`，并**新增 92、94–107 的索引表行**。其中 **94–106 是 trunk 自己的波次文档**（trunk 有这些文件、但 trunk 的 `docs/README.md` 冻在 `dae2fbe` **从没索引它们**），107 是 narrative 自己的。
- **陷阱**：trunk 现在的文档集已到 **126**（Wave AC→AG）。**直接取 narrative 版会把索引停在 107**，仍漏 108–126。**直接留 trunk 版**又漏 92、94–107。两版都不完整。
- **策略**：以 trunk 的 `docs/README.md` 为底，**叠加 narrative 的 92/94–107 索引行**（它们对 trunk 是净增、无冲突），**同时补齐 108–126**（trunk 侧既有欠账，严格说超出叙事 reconcile 范围，但同一文件同一次改最省事），头改为真实最大号。107 行的措辞标注它是"平行叙事轨（`codex/narrative`）"。

### `docs/05`（narrative 的编辑：`7bbdc30`→`a5d2e54`）
- narrative 做了什么：把 §A 权威计划指针 `U → X` 改成 **`AA → AB`**，并把波次表从 W/X 扩到 W/X/Y/Z/AA/AB。X/Y/Z/AA 行描述的是 **trunk 的波**（91–106），AB 行（107）是 narrative 自己的。
- **陷阱**：trunk 真实位置是 **Wave AG**（`docs/113` §八）。**narrative 的指针 `AA → AB` 若整版取入，会把权威指针从 AG 倒退回 AB，把 AC–AG 全藏起来**——正是 `docs/README.md` 那段自己警告的"索引落后等于把这一波藏起来"。而且 trunk 已**弃用** `docs/05` 的波次表、迁到 `docs/113`。
- **策略（推荐）**：**最小化 `docs/05` 改动**。不采纳 narrative 的 `AA → AB` 指针行（它对合并后的 trunk 是错的）。叙事在路线图里的正确落点是 **`docs/113` §三**（那里已写"叙事/storylets ... `codex/narrative` ... 下一步并入 trunk"）+ `docs/README.md` 加 107 行。若仍要在 `docs/05` 留痕，只加一行"AB=平行叙事轨，权威见 `docs/107@codex/narrative` 与 `docs/113` §三"，**不动权威指针**（保持 trunk 用 `docs/113` 的约定）。
- 一句话：**`docs/05` 的 reconcile 是"别让 narrative 的旧指针覆盖 trunk 的新现实"，而不是"合并两份编辑"。**

### `docs/107@codex/narrative` 本身
- 直接**取 narrative 的版本**（trunk 无此文件、无冲突）。它是叙事轨的权威计划。合并时确认 `docs/README.md` 那行用 `docs/107@codex/narrative` 之前、并入后改成正常号即可（并入后 107 就在 trunk 上了）。

---

## 五、接口冻结面（叙事消费的 schema）

分两层。**Tier-1 今天就在消费、且完全与 Sim 解耦；Tier-2 是 S14/S18 才碰的真 Sim 面、也是真正要在写侧前冻结的。**

### Tier-1 · narrative 自有合成 schema（先并层消费，NOT_SIM）
1. **S06 `pre_state`**（`NarrativeViewContract.project` 的输入）：顶层键 `roles/nodes/edges/fragments/receipts/claims/requests`；`role` 字段 `now_node/visible_node_ids/visible_edge_ids/carried_fragment_ids/receipt_ids/open_request_ids/route_hint/clock/status`；`edge.from_node/to_node`；`fragment.custodian_role_id`；`receipt.role_id/claim_id`；`request.role_ids`。
2. **S06 十字段 snapshot**（视图边界，`NarrativeViewContract.SNAPSHOT_KEYS`）：`role_id, now_node, visible_nodes, visible_edges, carried_fragment_ids, receipt_ids, open_request_ids, route_hint, clock{day,watch,tick}, status∈{active,blocked,complete}`。三个视图（`WebMazeGraph`/`RolePOVCard` + `s13_visual_test`）各自 `_shape_errors()` **fail-closed 拒多余键**。
3. **S16 committed-trace schema**（`S16Compositor`）：`schema=="living-town-s16-compositor-projection/v1"`、`authority=="projection_only"`、`mode=="READ_ONLY_COMMITTED_TRACE"`；frame `TRANSITION_ID_KEYS`={`actor_role_id, recipient_role_id, requested_action_id, resolved_action_id, target_id, fragment_id`}；`FRAME_HASH_KEYS`={`state_sha256, ledger_sha256, chain_hash`}；`FIXTURE_SHA256` 锚死。

**冻结动作（先并层）**：这三套是 narrative **自定义常量**，冻结 = pin `SNAPSHOT_KEYS`/`TRANSITION_ID_KEYS`/`FRAME_HASH_KEYS` + fixture SHA（已 pin）。**因为它们与 Sim 解耦，trunk 改任何 Sim 字段都不会打破它们**——这既是先并层安全的原因，也是把"语义漂移"风险合法地推迟到 Tier-2 的原因。

### Tier-2 · Sim event/relationship 面（S14/S18 才消费，写侧前必须冻结）
出处 `docs/107@codex/narrative` §三 9 条 ⊗ trunk 在飞的工作：

| 面 | 具体字段 | trunk 现状（谁在动它） | 冻结前不可开写侧 |
|---|---|---|---|
| 事件结果 | `accepted`（已在）、`effect_applied`/`rejection_reason`（AD2 档1）、`witnesses`/`wn_other`、事件 `tick` | **在飞**：`docs/116` AD2 档1/档2 待用户拍 schema | ✔ |
| 关系/信念 | `beliefs`(subject/predicate)、`attitudes`、`factions`、`affinity`、`standing` | state_projection 未覆盖（`docs/113` §一）；AG1 IndustryState 待拍 | ✔ |
| 移动授权 | Sim journey/portal（`SpaceGraph`）、agent `space/floor`（AG3 定为金标 Tier-B） | 已有，但 `_portal_click` 缺 `queue_redraw` 疑似 bug（`docs/113` §三） | ✔ |
| 存档/digest | save codec canonical oracle；digest = `sim digest + narrative hash` 拆分 | **在飞**：canonical oracle 待用户 §0.8 拍（`docs/113` §一） | ✔ |

**这张表就是"即使改不同文件也会语义漂移"的面**：narrative 一旦从 Tier-1 合成态切到 Tier-2 真 Sim 态，任何这些字段的重命名/语义变更都会让叙事投影错。**结论：Tier-2 的几个面 trunk 现在正在改，恰恰是后置层必须等的原因**；而先并层不碰它们、所以能先走。

---

## 六、分阶段 reconcile 方案 + 风险

### 阶段 R-0 · 预飞（只读，不合并）
- 冻结候选 SHA：trunk `3da64b6`（或更新）+ narrative `c107296`。记 `head_sha`/`base_sha`（`docs/113` §四·2 收据口径）。
- 跑 §三 的 R1 A/B + import/parse 预飞，产出 exact-head 三锚收据。
- 产出：先并层清单 + 本文。**无 merge。**

### 阶段 R-1 · 先并层 PR（只读组件，可审查，Codex 要的"只读 reconcile/PR，不直接合"）
- 内容：**只**取类别 A（5 视图 `.gd`）+ B（测试+场景）+ C（fixtures）+ §四的 docs 语义 reconcile（README 叠加、`docs/05` 最小化、107 取入）。
- **新增 trunk 侧 CI 门**：narrative 现在**零 CI 接线**（60-path 不含 `tools/`/`ci.sh`/`.github`）。先并层要在 `tools/ci.sh` 加一个 headless 跑 3 个 narrative 测试 scene 的门（照 `docs/41` §2.5 写探测包络：detects/does_not_detect/confidence）。
- **媒体政策（类别 D/E）决策点**：14 个二进制 ~1.45 MB + py/ps1 验证器是**评审产物**。建议**默认不进 trunk**（留在评审分支/`analysis/` 只读，或按需另设媒体轨），避免永久 git 历史负重；若要留证据，只并 manifest（sha256）+ 一张 contact sheet。**请用户/协调者拍这一条。**
- 门槛：R1 三锚零位移 + 留出种子双跑 + 全量 CI exact-head PASS。**零 schema-freeze 风险**（Tier-1 解耦）。

### 阶段 R-2 · 后置层（gated，S18 裁决前不开写侧）
- 顺序：外部 lab S12 promotion audit → S14 只读真 actor 投影（要 Tier-2 面在 trunk 冻结）→ S18 integration RFC（把 9 条边界拍 accepted/rejected/replaced；触发 `docs/41` §0.8 外审+多棒；**用户拍板**）→ 新一轮 `docs/47` R12 brief → 唯一 Sim 写侧棒（双烘+留出+`rebake_history`）。
- 阻塞项：Tier-2 的事件结果 schema（AD2 档1/档2）、state_projection canonical oracle、digest 拆分——**这几个 trunk 现在在飞，是后置层真正等的东西**。

### 风险（照实列）
1. **媒体永久负重**：~1.45 MB 二进制无 LFS、进 trunk 后永远在历史里。若默认并入会累积。→ R-1 决策点先定政策。
2. **CI 门是新写的、可能跑在不能变红的配置上**（`docs/41` §2.5/§2 第三盲区）：narrative 测试若只喂一个温和合成态，隐藏文本泄漏门可能没牙。→ 门必须带 `_negative_control`（s13 测试已有）并在未改树上先证有判别力。
3. **import 挂死**（`docs/41` §1）：新 `.gd` 若有 parse error，全量 CI 会**挂而不红**。→ R-0 预飞单独 import + 跑 scene。
4. **`docs/05` 指针倒退**：若图省事整版取 narrative 的 `docs/05`，权威指针从 AG 退回 AB，藏掉 AC–AG。→ §四推荐最小化改动，别覆盖。
5. **子树 provenance 锚合法漂移被误读成金标位移**（§三边界）：加文件改 `game/scripts/` 子树哈希。→ 回执明写"digest 零位移、子树哈希加法式变化"，别混为一谈。
6. **Tier-2 面在飞 ⇒ 若有人图快先接 S14/写侧**，会接到一个正在变的 schema 上、语义漂移。→ 后置层硬 gate 在 Tier-2 冻结 + S18 + 用户。
7. **"独立 lab 继续、生产 NO-GO" 的边界要机器化**：`source_receipt.json` 已有 `production_gate:false`，先并层的 CI 门应断言 committed fixture 的 `production_gate==false` 且 `simulation=="NOT_SIM"`，防止有人把 fixture 复制进 `game/data/scenarios/`（`docs/107@codex/narrative` §一停止线）。

---

## 七、这份任务书哪里是错的（照 docs/41 §4）

见 §〇 三条更正，摘要：
1. **"两边都动 `docs/README.md`/`docs/05`"** 不成立——trunk 相对 merge-base 逐字节没碰这两个文件，只有 narrative 碰了。reconcile 是单向漂移，不是双向冲突。
2. **"~60 path / 8k+ 行" 要审的代码只有 5 个 `.gd`/1460 行**，其余是测试/fixture/评审媒体/CI 证据；可执行引擎在**外部 lab 仓**、不在 `codex/narrative`。
3. **叙事今天不消费任何 Sim schema**（`accepted`/`witnesses`/信念都还没接）——它消费自定义合成态；Sim schema 耦合在 S14/S18 才发生。这是先并层零风险的根据，也把"schema 冻结"从先并层移到后置层。
4. 补一条精度：任务书说"S18 之前先并哪层"——精确地说，叙事**内部**停止线是 **S12**（promotion audit），**S18 gates 的是 Sim 写侧**；只读主仓组件不 gated 在 S18，所以先并层可先于 S18 干净落地。

---

## 八、验收对照（AH1）

1. ✅ 60-path 分类表 → §一。
2. ✅ 先并层/后置层两清单 + 读码证据 + R1 零金标 → §二、§三。
3. ✅ `docs/README`+`docs/05` 语义 reconcile → §四。
4. ✅ 叙事消费的 schema 面（接口冻结，Tier-1/Tier-2）→ §五。
5. ✅ 分阶段方案 + 风险 → §六。
6. ✅ 零代码改动（`git diff` 只应有本文）。
