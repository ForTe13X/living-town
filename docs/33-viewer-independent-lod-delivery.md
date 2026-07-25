# 33 · 观察无关 aggregate LOD — 从原型到交付 scope

承 docs/32（规模诊断）。本篇记 2026-07-25 的一段完整循环：**设计 → 实现 → 双层对抗评审（Codex + 11-agent workflow）→ 修 → 验 → 眼验 → 诚实定位**。

## 1. 做了什么

一个**观察无关的 aggregate LOD**：每 tick 从 committed sim 态选「满帧 cohort」，**绝不读相机 `lod_focus`** → 镇子历史不依赖你看哪（红线 Main.gd:159）。取代旧 camera near_cap（viewer-dependent、破回放、不可出货）。

- **cohort = 玩家 ∪ salient(工作态) ∪ 无状态轮转**（`Sim._compute_lod_cohort`）。
- **salient 只认「正在做的事」**：`talking>0 | option!=null | 需求危机 | 玩家 avatar 近旁`。**刻意不认「持久关系」**（has-pact/has-conflict/has-commitment）——那是关系不是工作，稠密关系镇里人人有 → cohort 会涨到≈N、LOD 名存实亡（实测 N=60×15d 冲突累积把 cohort 从 35% 撑到 87%）。真要行动时会以 `option!=null` 冒出来被抓。
- **无状态轮转**：每 id 每 `span=31`(素数,不整除 240) tick 保证一满帧 → liveness floor + 无游标(回放/存档无关) + 夜间反思不被固定相位偏置。
- **cheap ⟺ option==null**：cheap agent 永不寻路 → 天然绕开卡墙 bug；一切位移走真 A*（salient 提升后）。

## 2. 两层对抗评审各抓到什么（都是我单跑没看见的）

**Codex desktop（极高，逐行读真码，自己跑 bench）** 推翻我"已验证/省 44%/已交付"的乐观 framing，抓两真 bug：
- **F6（对规模收益致命）**：salience 认持久关系 → 稠密/长历史镇 cohort→N。→ 收窄为工作态（附带消除"每 tick 扫全历史数组"膨胀 F2）。效果：N=60×15d 87%→35%、N=100 cand 省 44%→65%。
- **F1（真成本漏）**：夜间 O(N²) 反思/结盟仍以 `lod_near_cap>0` 为门、激进档恒 false → 错跑全量 N，cand_calls 探针还看不见。→ 改走观察无关 cohort 门。

**11-agent delivery-scope workflow（理解→设计3视角→各被批判→综合）** 给出交付次序 + 抓出渲染裁剪 3 致命项：
- 头条裁决：**数百 NPC 真交付第一步是「接测量、不接机制」**。不接 Main 出货路径（分叉确定性金标 + 损害≤60卖点 + 数百在出货 UI 本不可达，clamp[6,60]）。不做渲染裁剪盲飞（有 3 致命项 + 在≤60 ship live 零收益）。
- 渲染裁剪 3 致命项（真读相机安全=纯 View，但）：①cull 变量声明在 `_draw()` 局部、别的无参绘制函数读不到（须提成员）；②复用 `screen_to_world` 用裸 `cam.position`、贴边发散数十~百 px → 屏内 agent 误裁 pop-out（须改 `get_viewport_transform().affine_inverse()`）；③相机动无 `queue_redraw` → cull 过期出幽灵/缺人（须在 pan/zoom/follow 各点 emit 重画）。

## 3. 验证（红线全绿）

| 门 | 结果 |
|---|---|
| V1 逐字节 default-off | ✅ == master |
| V2 相机路径无关（观察无关证明） | ✅ 5 个 lod_focus(含擦除/off-map)→digest 一致 |
| V3 确定性 | ✅ 同 seed / 存读==直跑 / fresh==restart |
| V4 硬不变量 | ✅ N=100/200 × 多 seed × ≤40d：starve=0 hard_fail=0 |
| V6 liveness floor | ✅ 0 从未满帧、最大间隔=span |
| **总成本（墙钟,含夜间 O(N²)/全部）** | 全量 vs LOD：N=48 省 57% / N=100 省 68% / N=200 省 79%(~5x)。**省率随 N 涨**（F1 修复后夜间 O(N²)按 cohort² 而非 N² → 真渐进分量）。 |
| **眼验（Docker Xvfb，`shot_scale.sh`）** | N=200 聚合 LOD 镇子活着、无冻结成团/边缘瑕疵；较全量事件 1548→1002/冲突 13→0（远端粗仿=社交更稀疏，如实取舍） |

`lod_verify.gd`(V2/V3) 已入 CI（`ci.sh` step 4b）——把「绝不接相机」红线机器化。

## 4. 一个被推翻的旧结论

**docs/32 的「N=96 破 #01 饿穿 / 单 stove 根因」已过时**：richer-town 合并(#44)给 map 加了第 2 个 food 对象，**全量 sim(出货模式,无 LOD)现在饿穿-free 到 N≥150**（find_starve 实测 N=54/60 seeds1-6、N=96 seeds1-3、N=120、N=150 全 0）。推论：①出货 UI 上限 60 远在安全区（评审担心的"48<N≤60 无饿穿网未验证"→已证安全）；②**LOD 现在纯为性能**（全量不饿穿但慢），非正确性。

## 5. 诚实定位 + 剩下什么

这是一个**观察无关 cohort 原型 + 一个 CLI 测量口（`--lod-agg`）**，**不是「已交付数百 NPC」**：
- **未接出货窗口**（Main boot/面板从不设 LOD 标志，靠此休眠；唯一口是 CLI `--lod-agg`，byte-identical）。
- **剩下的决定性一步 = 真机帧测**（NX789J，`godot-android-loop`）：抓 N=60 全保真怼近人群 与 N=200 `--lod-agg` 的 FPS，判 **render-bound vs sim-bound**（WorldView:751/828 仍每帧遍历全 agent）。桌面软渲不作数。**当前 adb 无设备连接 → 待手机接上。**
- 若真机证明 render-bound → 做渲染视口裁剪（先修 3 致命项 + 门控 `size>=THRESHOLD` 休眠）。
- sim LOD 接 Main / 抬 UI clamp / 资源密度缩放 / 非克隆多样人设 → 仅走 docs/19 大地图 fork2 时做，须先烘 lod-on 金标。

## 6. 真机帧测结果（NX789J / RedMagic，2026-07-25）——【推翻了我的干净结论】

用户提醒"记得连续帧，是 game 卡死了"→ 单帧快照会骗人，连拍才看出真相。设 `settings.cfg` npc_count=200 + backend logic（绕 UI clamp），F3 开 overlay 读 FPS/绘制/tick，空格暂停隔离渲染。

| N=200（clone 镇） | FPS | 绘制 | 内存 | tick/s |
|---|---|---|---|---|
| N=12 基线（跑） | 90 | 2514 | 142MB | 12 |
| N=200 全量 sim，早期(day3) | 16 | 3864 | 172MB | 11.4 |
| N=200 全量 sim，**day4** | **6** | 4548 | 268MB | 13.3（活冲突 49） |
| N=200 **LOD**，day4 | **7** | 4054 | 240MB | 13.4（活冲突 6） |
| N=200 **暂停**（纯渲染，day10） | **90** | 4229 | 273MB | 0 |

**三条硬结论（都和我之前的干净故事相左）：**
1. **渲染【不是】瓶颈**：暂停（冻结 sim）→ 90 FPS，即便 day10 关系线爆炸、200 agent、绘制 4229。→ **渲染视口裁剪不必做**（这点评审对、我对）。WorldView:751/828 遍历全 agent 在此规模真机上够快。
2. **N=200 在真机上跑不顺**：全量 sim 与 LOD 都在 day4 掉到 **6-7 FPS**（"卡死"感）。tick/s 仍达标（13/s）说明 sim 在推进、但每 tick ~70-150ms 吃满主线程帧预算。
3. **LOD 在克隆镇上几乎不救场**：day4 只 6→7 FPS（~17%），**远非 headless 的 79%**。根因：**克隆镇病态过度社交**——200 个克隆共享 ~12 个目标点、全挤广场、无休止互动 → 多数 agent `option!=null` → salient → **cohort≈N → LOD 失效**。headless 79% 是【前 5 天累计均值】（前期稀疏主导）；社交饱和后的【瞬时】收益坍缩。（LOD 确在起作用：活冲突 6 vs 49、绘制更低——远端被粗仿了，只是省下的 cohort 不够大。O(N) 基线成本 decay/`_far_maintain`/移动在解释执行的 GDScript 上也可能压过 LOD 省的社交枚举，需 profiling 定论。）

**这正是 Codex/workflow 反复警告的"克隆镇不可靠"，如今在真机上被实证。** 内存也随时长涨到 240-268MB（累积社交态），长时高 N 需盯 OOM。

**交付路线图的真修正**：LOD 观察无关+确定性+红线安全都成立，headless 稀疏/早期也确省。但【唯一能上真机的大镇=克隆镇】过度社交、把 LOD 打废——所以我【还不能】在真机上证明"LOD 交付流畅数百 NPC"。真正的前置【不是】渲染裁剪、【不是】接 Main，而是**一个真·稀疏大镇（各有家/作息、散得开的人设，即 docs/19 fork2 大地图）**。N=200 也【非出货档】（UI clamp 60；N≤60 真机 90 FPS 顺）。

## 7. 真机【微秒分拆计时】——终于是【实测】不是推断（Codex 结构评审第 1 条：别推断，测）

§6 的"渲染不是瓶颈"是【被暂停测试误导】的错判：暂停同时抽走了 sim-tick + 每 tick 触发的 `_draw` 重算（Codex 抓出此混淆）。改用【一次性 usec 计时】埋点（Sim.tick 与 WorldView 社交+agent 绘制块，投到 overlay），真机实测：

**N=200，day3，全量 sim，帧 166.7ms：`分拆 sim-tick 63.9ms · draw社交 59.5ms`**（→ 静态地图重绘+杂项 ~43ms）

**两大【实测】成本**：sim-tick 64ms + 逐-agent/社交绘制 59.5ms（合计约占单帧 ¾）；余 ~43ms = 每帧开销 + 静态地图重绘。**【自我纠错】**：我一度把这第三块【标成"静态重绘"】——又是推断。静态重绘 N-无关，受 N=12 整帧仅 11ms 的上界卡死，所以它是【小头】(≤11ms)；那 43ms 的大头是其它每帧开销（未逐项测）。所以真实是【两大杠杆】（sim + 逐-agent 绘制），不是"三等份且第三份是静态重绘"。这一次性解释了全部前面的困惑：
- **暂停→90 FPS** 因为暂停抽走【三者全部】（无 tick → 无 sim 且无 queue_redraw → `_draw` 不重算）。§6 误判为"仅 sim"。
- **LOD 单开只 6→7 FPS** 因为它只砍 ⅓（那 64ms sim-tick）。
- **没有单一杠杆能救 N=200**：要顺跑数百须【三管齐下】——sim LOD(sim-tick) + 渲染裁剪(社交/agent 绘制，WorldView:747-754 O(N²) 关系线) + 静态地图缓存(全图每帧重绘，Codex #2)，各值 ⅓。

**每个评审者都对了一部分，而我每个"单一瓶颈"结论都错了**（sim-only→render-only→sim-only，来回三次）。诚实交付路线（若真要手机数百）：**两大实测杠杆** = sim LOD（砍 sim-tick 64ms）+ 渲染裁剪逐-agent/社交绘制（砍 59.5ms）；静态缓存只是小头。sim LOD 是必要非充分件。N≤60（出货档）真机 90 FPS 顺，不需要这些。

**元教训**：①宣告 done 前先过评审（见 `feedback-adversarial-external-review`）。②真机连拍 > headless 单点（用户"连续帧"挡住早期单帧错判，见 `feedback-record-on-stage-change`）。③**别推断瓶颈，埋计时器【测】**——我连错三次单一瓶颈判断，直到真机 usec 分拆才看清是 sim + 逐-agent 绘制两大块。而且【这毛病顽固】：连我在"别推断要测"的复盘里，都还把没测的第三块顺手标成"静态重绘"，后来靠 N=12 整帧 11ms 的上界才自己抓出来（见 §7 自我纠错）。Codex"别推断，测"要贯彻到底。
