# 143 · 叙事车道（lane-3 storylet）· 只读 scoping

> 用户 2026-08-07 放行叙事车道（3→2→1，storylet 先）。本文=只读地勘结论 + 第一片 brief 底稿。协调者已核心复核（golden 分级、事件清单、A/B 分轨）。

## 〇、关键分轨（brief 曾并成一个，必须分开）
| | **A. 出货叙事内容**（lane-3 真落点） | **B. `codex/narrative` compositor** |
|---|---|---|
| 是什么 | `goals.json`(小镇纪事) + `Story.gd`(因果弧) + `Main._event_prose`(编年史) | S13/S16/S17 只读可视化/评审组件 |
| 读什么 | `Sim.event_log`（真账本） | 自定义合成 snapshot + committed trace fixture（**不读 Sim**） |
| 上屏 | **是**（HUD 在跑） | 否（评审媒体，未合 trunk） |
⇒ **lane-3 第一片落 A 面**（零金标）。B 面是**独立 reconcile 轨**（stale：9 ahead/99 behind、4 天没动、文件交集 0；docs/127 已给分层方案）——**不是** storylet 内容，单开一根棒、owns 错开、别整支吞。

## 一、事件系统（叙事原料）—— `Sim._log_event`(Sim.gd:3804)
account `{id,tick,type,actor,target,subject,accepted,witnesses,note}`；**25 个 event type**：社交(greet/give/gossip/gossip_rep/discuss/invite/confide/leak/endorse/aid，可 accepted=false)、mediate(**actor 恒 player**)、meet(成/爽约)、冲突链(conflict/confront/apologize)、betray、rally_oust/pact、world/election(actor="town")、经济(pay/produce/shortage/consume/spoil，多 FEED_SKIP)。

## 二、金标面分级（判据）
金标 = `golden_digests.json`（N=12×60天×logic，`[Inv.digest, event_digest, 逐tick前缀链]`）；`event_digest` 在 `_log_event` 每事件 O(1) 折出 ⇒ **金标见证行为态**。
- **零金标**：扩/改 `goals.json`、扩 `Story.gd` ARCS（新幕/弧/文案）、改 `Main._event_prose` 文案——三者都是 event_log 的**只读 View 派生**（goals_test/story_test A0≡A1 机器证零扰动，不碰 Sim/RNG/不进 event_log）。
- **移金标**：任何**驱动 Sim 决策 / 写 event_log 的新机制**（新 event type、NPC 会 mediate、gossip_rep 加褒贬字段、到场/参与成事件、选角行为深度 lane-2）——`event_digest` 变 → 须 docs/41 §3 + docs/47 R12（双烘 + 留种子 13-30 + rebake_history）。
- ⚠️边界：新增 `.gd`/`.json` **文件**改 `game/` 子树哈希，**不是金标位移**（S0 digest 不动）；有 provenance 锚就按 R12 补 note 重烘。

## 三、第一片（L3-a，零金标，推荐）：`Story.gd` 已有弧新幕
- **为什么**：headroom 最大、风险可控；多个已 emit 事件族在弧上没用上；"加已有弧新幕"是走熟的 Y3 模式（talked/whisper 两幕已此法落地）；不吃 goals 面板行预算。
- **owns**：`game/scripts/Story.gd`(ARCS 表, :361-538 六弧 grudge/promise/secret/pact/craft) + `game/scripts/story_test.gd`(新增正对照 F 夹具) + docs 编号。**单文件生产码、blast radius 小**。
- **零金标风险不在金标**（story_test A0≡A1 守），**在文案守卫**：`PHRASE_LOCK`(措辞锁)/`POLARITY_LOCK`(极性锁 accepted+note 维)/`REPEAT_MARK`(复述锁) + `audit()`(:1050 逐行回 event_log 核 7 件事) + `lint_grammar()`(:272 静态扫)。新幕文案若含锁定短语，其 `type/accepted/note` 必须相容，否则当场红。
- **校准=可落地上界普查**（docs/98 §一）：跑 `story_test --stats`（Story.gd:939 逐弧种矩阵）量"有几条落在**已开着的弧的有向对**上"（非某事件族总数=虚高分母）。参照：sided=147 下界、give 判死=4/432（送礼有 trust 门、开弧多敌对）。⚠️**哪几条新幕能过普查须先跑 --stats**（scoping 只读未跑，标未验证）。
- **过 story_test**：① F1 负对照(只喂 greet→0 故事)不破；② 新幕正对照加手写因果链 F 夹具给唯一答案；③ `lint_grammar().bad` 空；④ A 段 12 seed 增量折≡全量折≡回放三臂绿。

## 四、备选片 & 诚实限制
- **L3-b 备选（更小）**：扩 `goals.json`（纯 data 零 .gd）——⚠️**天花板**：`panel_text` 注释明写 11 条目标×2 行已逼近 RichTextLabel 行预算（Goals.gd:249），再加可能先扩面板容量。
- **加不了（除非移金标）**：① 全员到场/参与型成就（到场不是事件）；② NPC 主动"说和"（mediate 恒 player）；③ 褒/贬旁支叙事（gossip_rep 无 valence 字段，Story.gd:532）；④ town-actor 事件(election/consume/world)进"两人故事"（结构挡非居民 :634）。①②③解锁=给事件加字段/新机制=**移金标+R12**，跨进 lane-2。

## 五、sequenced（lane-3 内部）
L3-a(Story 新幕,零金标) → L3-b(goals 小扩/编年史文案) → L3-c(compositor 先并层,独立轨,照 docs/127 R-1) → L3-d(移金标:解锁上面①②③,须 R12,耦合 lane-2)。⚠️接 lane-2/经济前**须查 #43 状态**（docs/113 §七"#43 修复落地前不开新经济/社会波次"——本 session 早已由 AG2/AL1 收口，落地时复核）；lane-1(默认镇规模)放大 N 会让 N=12 金标不适用、须另立锚。
