# 137 · AO1 · state_projection_v1——从 save codec 抽 canonical 投影 + 真咬门

> 路线图 §一架构第一刀，用户 2026-08-07 §0.8 拍板做。AF1 设计（docs/121）+ Codex §三.11 更正（从 save codec 抽单一 oracle、别另造第二套）落地。
> ⚠️ AO1 子棒在写完 oracle+门、跑出 A/B 证据后**卡死**（watchdog 600s）；协调者接手：复核 + 接线 CI + 写本回执 + 重烘 ledger。协调者当时给 backend/ext 补的 does_not_detect 白名单**后被外审 F1 证明不对、已改为从分母剥除**（见 §三，2026-08-07 收口）。

## 〇、它解决的问题（精确说法）

现在的"逐字节一致"很窄：`Inv.digest` 只折 `event_log`、`chain_step` 折 tick+逐 agent `id/pos/needs/talking/option`；**~29 个演化字段没覆盖**（`beliefs·attitudes·factions·affinity·pacts·standing·stock·space·floor·money·memory`）。AF1 干预证明：一次悄悄丢一条 belief 的 save/load 能过 `save_load_test`（零漂移）。
⚠️ 这证明的是**验证门有盲区**，不是 codec 真丢数据（AF1 的丢是合成扰动）。本模块把 round-trip 正确性变得**可证**。

## 一、oracle（`game/bench/StateProjection.gd`）

- **单一真相源**：折 `Sim.save_game` 落盘 blob 的 `state`——成员集 == save 权威面。**不重声明 DERIVED/BENCH_ONLY/VIEW_PARAMS、不重实现反射**（避免 AC1 点名的"分母耦合"）。
- **与 `Inv.digest`/`chain_step` 并行解耦**（docs/121 路 b）：新函数，不进 S0 比对的四个量（digest/event_digest/chain/events）、不烘金标 ⇒ **金标零影响**（除非用户蓄意为它新增锚）。
- **确定性（红线#1）**：字段序规范（dict 键按 `[typeof,str]` 排、与插入序无关 → 冷热镇/跨机等价）；float 折 8 字节 IEEE-754（-0.0/NaN/Inf 归一）；同族 FNV-1a/32（不用引擎 `String.hash()`）。
- **性能**：只在存读档/checkpoint 边界按需算，**不每 tick**。
- 用法：`project_sim(S)`（存盘→读回→折）/ `project_file(path)` / `project_blob(blob)`。

## 二、真咬门（`game/scenes/state_projection_gate.tscn` + `game/scripts/state_projection_gate.gd`，接进 `ci.sh` 步 4h）

协调者自跑（`godot --headless res://scenes/state_projection_gate.tscn` → `state_projection_gate: PASS ✅ (0 fail)`）：
- **① round-trip**：save→load→re-save 投影哈希相同（load 漏还原任一权威字段 ⇒ 红）。
- **② 具名 A/B（money shot）**：20 个 headline 家族三列并排——**每一条 `Inv.digest` SAME · `chain` SAME · `Projection` DIFF**：清空 beliefs / town_stock / 换平面(space·floor) / attitude / standing / affinity(关系·agent) / pact / faction / skills / money(coin) / gift / memory / complementSeen / faction_size / day / weather / factions / pacts_index。坐实"旧折叠盲、投影不盲"。
- **② 全量扫**：**agent 字段 35（=`agents[0].keys()`）· world 字段 99**，各自分母内 0 洞。⚠️**诚实边界（审查 F6/F7）**：agent 分母取 `agents[0]` 单个代表，非全 agent 键并集（只有部分 agent 运行时长出的键不在这 35 里）；world_count 是 save 落盘持久集（耦合 `save_game`，见 §四）非独立权威枚举——两条是 v1 已知边界，**不谎称"全权威面 0 洞"**。（`backend`/`ext` 已按 F1 从分母剥除，见 §三。）
- **④ AF1 灵敏度自证**（⚠️审查 F8 纠措辞：是**自证**、非抓到真 load bug）：手工 `beliefs.erase(k)` **合成**一个"漏 belief 的读档"——`Inv.digest` A==B(漏档) SAME(盲)、`Projection` DIFF(抓住)；续跑 Inv.digest 漂移点=第 17 tick（复刻 docs/121 §四）。这证的是**投影对"丢一个权威字段"敏感**（旧折叠盲、投影不盲）；真正对"load_game 漏还原字段"的门牙是 **① round-trip**（save→load→resave，hash 不同即红）。
- **③ 规范序负对照**：键序不同、逻辑相同 → 投影相等（红线#1 命门）。
- **⑤ does_not_detect（实测）**：非持久面扰动 → 投影 SAME（按设计正确）：DERIVED 缓存（`_near_set`/`_path_cache`）、VIEW（`lod_focus`）、BENCH（`shadow_on`）、存档 `meta.name`。（`backend`/`ext` **不在此列**——F1 后它俩从分母剥除，改由 ⑥ 证注入无关性。）
- **⑥ 注入无关性（F1 新增）**：`backend`/`ext` 键在（headless：值 null）与不在（真机：注入 Object 被 save 跳键）两种 blob → 投影**必须相同**（实跑 `269495820==269495820`）。删掉 `NONAUTH_STATE_KEYS` 剥除逻辑即转红——守红线#1 跨机/冷热等价。

## 三、backend/ext：从"记 does_not_detect"到 F1 收口（外审纠错）

AO1 卡死处：全量扫把 `backend`/`ext` 报成 world 覆盖洞 ⇒ 门 FAIL。协调者当时的处置是**白名单剔除、记 `WORLD_DND` does_not_detect**，理由"运行时 Object 服务引用、save 落 null"。

⚠️**2026-08-07 外审 F1 证明这处置不对**：GDScript `null is Object == false`，故 `save_game` 的 `if v is Object: continue`（`Sim.gd:1172`）**跳不掉 null 的 backend/ext** ⇒ headless 存盘时 `backend:null/ext:null` **真进了 `blob.state`**（被折进投影）；而真机 `Main` 注入了 AIBackend Object 时 `v is Object==true` ⇒ 整个键**消失**。**同一权威态 → 两套键集 → 两个投影哈希**，直接违反本模块卖点"跨机/冷热等价"（红线#1）。而且门里 `WORLD_DND` 在 probe 之前就 `continue`，这俩**从没被真扰动过**——原文"实测确认"是未执行的空标签（审查 F5）。

**F1 收口**：backend/ext 是运行时注入句柄、**非权威持久态**（load 时重接线、不从存档还原），应从投影**和**覆盖分母**统一剥除**，而非折进去再打星号。落地：`StateProjection.NONAUTH_STATE_KEYS = ["backend","ext"]`，`project_blob` 折 `_auth_state(blob)`（剥顶层这两键）、`manifest` 同步剥（world 分母 101→99）。新增门 **⑥ 注入无关性** 证 `headless(键在/null)==真机(键不在)` 投影同（实跑 `269495820==269495820`）。改后 gate PASS、backend/ext 不再进 world_fields、无 dnd 星号。零金标（bench-only、不进 S0）。

## 四、零金标 + 边界

- **零金标**：只加新文件（oracle + 门），**没碰** `Inv.digest`/`chain_step`/`Sim` 行为/`golden` ⇒ 现有 S0 金标 12/12 含链不动（全量 CI 复核）。
- **game tree 变了**（加了 game/ 文件）⇒ 协调者按 AE2 收口后的纪律**重烘 complement ledger**（见下一条 commit）。
- **没做到的**（诚实）：v1 只覆盖 save 权威面的**当前形**；`space·floor` 的 0–1784 tick 盲窗、late-triggered/mid-recovery 的**跨时窗**覆盖是 v2 的事（本门测的是"存读档边界两点"的覆盖，非全时程）。增量子摘要/每 tick 折叠**没做**（性能上按需即可；未来若有 per-tick 消费者再说）。KnowledgeState（多镇第二先决）是另一条线，不在此。
