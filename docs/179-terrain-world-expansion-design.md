# 179 · terrain/geography 扩展【设计】——coast/ocean + 视觉起伏 + creek（并行车道 V/map）

> 触发：用户 2026-08-10 terrain 愿景（docs/113 节）。workflow whbsatm1o（5-agent：布局×起伏×确定性/POND→synth→对抗 verify）。**只设计不 build。** 关键锚协调者已复核（`audit_map.py:98` typed==blockers、`gate_complement_guard` freshness）。

## 〇、核心物理（整套设计由一条决定）

**Sim 导航只读 `blockers[]`**（`Sim.gd:4242`，全仓 grep 证 water/walls/trees 分层 Sim 零读）；`audit_map.py:90-99` **硬校验 `walls∪water∪trees == blockers`**（相等，`ci.sh:99` 每轮跑）。⇒ 地形劈两档：
| 档 | 判据 | 成本 |
|---|---|---|
| **零 sim 金标** | `blockers[]` 逐字节不动（纯 View draw / 重上色已挡格 / 可走 decor 不进 typed 层） | View 棒，digest 零变 |
| **移金标** | 任何进 typed 层的**不可走**新格 → 被 audit_map 强拉进 blockers → nav → 轨迹 → digest | committed 树重烘三锚+CI |

**★免费杠杆**：re-type 一格 `trees[]→water[]`（树本就在 blockers）⇒ union 不变 ⇒ blockers 逐字节不变 ⇒ **零 sim 金标**（≠ 新增 water 格＝该格原可走→挡→blockers 长大→移金标）。
**⚠️ HOLE D（对抗 verify 逮出·必记）**：**零 sim 金标 ≠ 免 finalize**。任何动 `game/` 的 commit（含纯 View）都 stale 互补锚新鲜度（`gate_complement_guard.check_ledger_freshness` 比 `HEAD:game`，`ci.sh:309` fail-closed）⇒ 欠一次 committed 树 `--bake-ledger`（~12min）；AV1/AV2/AV3/港口 每个先例提交都带这次重烘为证。并行多棒动 game/：协调者【合并后统一烘一次】。见 [[project-finalize-baton-committed-tree]]。

硬边界：全图单连通（`audit_map:113-119` BFS + `:135-138` islands）+ **≥2 不相交路线门（`audit_map:290-315`，home-work/cafe-wash/home-cafe，HOLE B 提案漏引）** + home/spawn/工位/门/地标不落 blockers + 岸线瓦仅 8 张（`WorldView:973-1006`，无 1 格宽 mask）⇒ 每块水 ≥2×2、拐角 90°。W/H 固定 64×48（改则 idx 全平移，别碰）。

## 一、布局选项（并列，选一）

| | **LA 东海** East Ocean | **LB 南湾** South Bay | **LC 东翼河** River | **L0 双潟湖** |
|---|---|---|---|---|
| 水体 | `x60-63×y0-47`(竖海,新 blocker 166) | `y45-47×x0-63`(水平海∪南池,新 ≈176) | `x46-47×y2-46`(2宽河,最重) | 西/东丛 trees→water(re-type) |
| 港口 | 新 dock 面东出水 | 南 dock 面南海 | 河口 dock | 北池 dock 不动 |
| walkable 冲击 | 小（吃东 4 列留白） | 小-中（吃底 3 行草） | **大**（切东 1/3 靠桥） | 无 |
| sim 金标 | 移金标 | 移金标 | 移金标·最重（islands 险） | **零 sim 金标** |
| POND 门 | 北池不动=零影响 | **天然免疫**（POND 只采北池） | — | 零影响 |
| 美感 | **最像理想 ocean+coast**（日出面海+松岬） | 坐拥南湾 | 地理叙事强但**平格无 z⇒河只是平蓝带+木桥** | **re-skin 非新地理** |

北池在 LA/LB 均留作内陆池 ⇒ 一镇双水（海+池）。**对抗 verify 荐 LA>LB 美感，但两者门代价一致（都欠互补锚刷新+P2 三锚）。**
**⚠️ HOLE A（对抗 verify 逮出）**：**L0 把两丛 156 树全转水 ⇒ `trees[]` 空 ⇒ `assert_tree_stand.py:189-190` fail-closed 硬红**（林相门，接 `visual_gate.sh:388`）。提案"L0 零成本零风险"**不成立**——要落 L0 必须**留 ≥1 丛**或改林相门口径。

## 二、视觉起伏 + creek（平格无 z）

- **mountain/cliff＝程序化假崖面 `_draw_mountains()`**（仿 `_draw_port`:3520：山格下伸深岩带+`_hash` 石缝+崖脚落影，读出高地）＝**零 sim 金标**主力。真 z＝不做（引擎 z-work 单独立项）。不可走岩体 blocker＝移金标（美感/风险比最差，缓）。
- **creek＝独立细水瓦**（CC0 窄水族，池塘 autotile 不动⇒**POND 零扰动**，推荐）；过河选 (a) crossing 格不 type 成 water（零门逻辑）或 (b) `bridges[]` 层（水流桥下、需扩 audit_map）。
- **plain＝低频确定性色偏**（`_hash(tx>>2,ty>>2)` 草甸↔旱地明暗，零金标，推荐）。
- **terrain_gate**：新 CC0 瓦走【重建半】（无 rebless 棘轮）——必先注册进 `slice_shore.SHORE`+`slice_visual.py`；沿用现水观感则复用 8 岸瓦零新瓦。**绝不碰 `--rebless`/`terrain_hashes.json`**（生成瓦钉子）。

## 三、相位序 + disjoint 棒

**策略：改 blockers 的地形攒成【一根移金标棒 P2】一次付三锚；观感全走零金标 View/工具棒。海岸先于起伏。**
| 棒 | 拥有文件 | 内容 | 档 |
|---|---|---|---|
| **P0 双潟湖**（可选,须留≥1丛） | `map.json` | 树丛 re-type→water,blockers 不变 | 零 sim 金标+**欠互补锚刷新** |
| **P1a View 能力** | `WorldView.gd` | `_draw_mountains`/plain 色偏/creek/bridge draw+`AUDIT_PASSES` | 零 sim 金标+**欠互补锚刷新** |
| **P1b 工具+瓦** | `audit_map.py`/`gen_town.py`/`slice_*.py`/`assets/art/terrain/*.png` | audit 判据扩(加严)+登记 CC0 瓦+slice | 零 sim 金标+**欠互补锚刷新** |
| **P2 MAP-SHIP** | `map.json`/`pond.py`(仅动北池)/三锚文件 | 落选定海/河/山/溪+三锚重烘+CI | **移金标** |

派发：`P0∥P1a∥P1b`（写-disjoint，但预对齐 schema：层名 mountains/creek/bridges+瓦名）→ **P2 串最后**（依赖 P1b audit 扩展）。**P0/P1a/P1b 并行动 game/⇒协调者合并后统一烘互补锚一次（HOLE D）。** P2 三锚 finalize＝golden(seeds+scenarios 两段)/modelpath/ledger+committed 树全 CI+held-out 13-30（#40 展布随水变=预期非回归据实记）+refute。

## 四、对抗 verify 判决（总）

主干**成立且诚实**（自认 L0 re-skin、无真 z、port/water 解耦）。**2 致命洞必先修进成本表**：**D**（零金标≠免重烘，每根动 game/ 欠互补锚刷新）+**A**（L0→trees 空→林相门红）。**2 中度**：**B**（连通漏 ≥2 路线门,LA/LB 恰安全但未言明）、**C**（dock rehome 非水层、碰 P1-a 与北池 POND——**terrain 棒应只供水体地理，dock 落点所有权交回 P1-a**）。river(LC) 缓做正确。

## 五、开放决策（呈用户）

**★用户拍板 2026-08-10：ocean + 【LA 东海 East Ocean】**（日出面海+松岬，最像理想海岸；北池留内陆池⇒海+池双水）。3-7 项按推荐默认：起伏＝(i) 纯程序化假崖面(零sim金标)、plain＝低频色偏(零金标)、creek＝缓做、新岸线不上 POND 门(如南池裸露)、L0 若做须留≥1丛。**dock 落点交回 P1-a（HOLE C：terrain 棒只供水体地理，不自开 dock rect）。**

1. ~~ocean vs river~~ → **ocean**（已定）。
2. ~~东(LA)还是南(LB)~~ → **LA 东海**（已定）。move-golden +166 blocker，攒进 P2；离北池远⇒POND 零影响，但 P2 须验"dock rehome 后北池 POND 仍过"（HOLE C）。
3. **起伏做多少**：荐 **(i) 纯程序化假崖面**（零 sim 金标，无真 z）；(ii) 不可走岩体 / (iii) 手绘崖瓦+rebless 缓。
4. **新岸线上不上 POND 门**：默认**不上**（如南池现状裸露，可接受）；上=扩 `pond.py NORTH`→region 列表（代码改）。
5. **creek 现在做吗**：若做选独立细水瓦（POND 零扰动）；或缓做。
6. **plain 色偏**：荐低频确定性色偏（零金标）。
7. **L0 双潟湖先落吗**：须留 ≥1 丛（否则林相门红）；是 re-skin 非新地理，美感由你定。

> 全文（含 file:line 与对抗 verdict）见 workflow whbsatm1o 输出；关键锚协调者已复核（audit_map:98 union==blockers、ledger freshness fail-closed）。
