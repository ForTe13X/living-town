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

**元教训**：这次是【宣告 done 前】先过评审——纪律用对了。见 memory `feedback-adversarial-external-review`。
