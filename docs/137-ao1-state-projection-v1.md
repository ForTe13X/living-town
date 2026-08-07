# 137 · AO1 · state_projection_v1——从 save codec 抽 canonical 投影 + 真咬门

> 路线图 §一架构第一刀，用户 2026-08-07 §0.8 拍板做。AF1 设计（docs/121）+ Codex §三.11 更正（从 save codec 抽单一 oracle、别另造第二套）落地。
> ⚠️ AO1 子棒在写完 oracle+门、跑出 A/B 证据后**卡死**（watchdog 600s）；协调者接手：复核 + 补一处 does_not_detect 分类 + 接线 CI + 写本回执 + 重烘 ledger。

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
- **② 全量扫**：**agent 字段 35/35 覆盖 0 洞 · world 字段 99/99 覆盖 0 洞**（+ `backend`/`ext` 2 个 does_not_detect，见下）。
- **④ AF1 回归**：同一"漏 belief 的读档"——`Inv.digest` A==B(漏档) SAME(盲)、`Projection` DIFF(抓住)；续跑 Inv.digest 漂移点=第 17 tick（复刻 docs/121 §四）。**这就是新门的牙。**
- **③ 规范序负对照**：键序不同、逻辑相同 → 投影相等（红线#1 命门）。
- **⑤ does_not_detect（实测）**：非持久面扰动 → 投影 SAME（按设计正确）：DERIVED 缓存（`_near_set`/`_path_cache`）+ **`backend`/`ext`**。

## 三、协调者补的一处分类（AO1 卡死处）

AO1 的全量扫把 `backend`/`ext` 报成 world 覆盖洞 ⇒ 门 FAIL。**复核：它们是运行时 Object 服务引用**（`Sim.gd:407/410` `Object = null`，AI 后端）——save_game 落盘时为 null（Object 不进持久态、load 时**重新接线**非从存档还原）。⇒ 扰动它们投影不变是**正确**：不属"必须 round-trip 的权威持久态"，与 DERIVED 缓存同类。故白名单剔除、记为 **does_not_detect 按设计**（`WORLD_DND=["backend","ext"]`）。改后门 PASS。

## 四、零金标 + 边界

- **零金标**：只加新文件（oracle + 门），**没碰** `Inv.digest`/`chain_step`/`Sim` 行为/`golden` ⇒ 现有 S0 金标 12/12 含链不动（全量 CI 复核）。
- **game tree 变了**（加了 game/ 文件）⇒ 协调者按 AE2 收口后的纪律**重烘 complement ledger**（见下一条 commit）。
- **没做到的**（诚实）：v1 只覆盖 save 权威面的**当前形**；`space·floor` 的 0–1784 tick 盲窗、late-triggered/mid-recovery 的**跨时窗**覆盖是 v2 的事（本门测的是"存读档边界两点"的覆盖，非全时程）。增量子摘要/每 tick 折叠**没做**（性能上按需即可；未来若有 per-tick 消费者再说）。KnowledgeState（多镇第二先决）是另一条线，不在此。
