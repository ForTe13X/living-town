# 141 · AP2 内容棒——outdoor 连续街区第二片：plaza【镇社交心脏】+ 连街网收尾

> 底稿 = docs/139（outdoor 金标面 scoping）+ docs/140（AP1 石铺连街）。本片承接 AP1：AP1 把门→广场
> 铺成了石街、广场铺成了 flagstone，但**广场仍读作一块方铺装、缺"镇中心"读感**，且外围 plaza-型区（码头）
> 是**没有街连过去的孤岛**。AP2 只在 `WorldView.gd` 的 outdoor 绘制路做视觉/连缀，
> `blockers/walls/water/trees/areas[*].rect/objects/portals` **一字未动**，landmark **也没进 blockers**。
> **零金标**（Sim 读 blockers/rect，读不到绘制层），下面 ④ 三证据实证（含 chain），不是口头声称。
> owns：`game/scripts/WorldView.gd`（outdoor 绘制 + landmark 绘制 + plaza 铺装 + 街具）、本文档、`docs/media/ap2_*`、`analysis/ap2/`。

## ① 现状清点（改前，行号锚在 `integration/batons` tip `df8e74b` 的 WorldView.gd）

| 面 | 改前画法 | 位置（改前行号） | Sim 读吗 |
|---|---|---|---|
| 中央广场铺面 | `_:`(paving) 分支：2×2 大方砖交错明暗 + 十字灌浆缝 + 亮内沿（AP1）⇒ 读作**均质的方铺装**，无中心焦点 | `_draw_area_floors` 1333–1345 | ✗（读 areas[*].type，Sim 零读 type） |
| 地标 well[30,26]/board[33,26] | 各约 **1 格**的小水井（蓝三角顶）/小告示板（红顶+两张纸）⇒ 在广场里**读不出分量** | `_draw_landmarks` 3133–3154 | ✗ 纯 View（landmark **不在 blockers**，见下"实测坐实"） |
| 门→广场路网 | 7 door 各一条 L 形石街连到广场最近带（AP1）；逐格 `_is_blocked` 跳挡格 | `_build_paths` 1127–1163 | ✗（读 doors/plaza rect，Sim 不读 `_path_set`） |
| 码头 dock[30,7,4,2]（type=plaza） | 已被 AP1 当 plaza 铺成 flagstone，但**没有 door ⇒ `_build_paths` 不给它连任何街** ⇒ 整镇俯瞰读作**孤岛** | 同上 `_build_paths` | ✗ 纯 View |

**改前读感**（`docs/media/ap2_town_before.png` / `ap2_plaza_before.png`，docker 真渲、seed3 正午 shot-fit）：
门→广场是连续石街（AP1 已成），但广场中心**是块空的方铺装**、只在下沿蹲着两件小地标；码头是**浮在草地上的一小块铺装**。

**★ 对协调者/docs 断言的实读纠正**（先量清再动，docs/139 纪律）：
- 「landmark 是不是真不进 blockers」——**真不进**。实测 `map.json`：`well[30,26]`、`board[33,26]` 均 ∉ blockers（403 格）。本棒也**只画不写**，绝不把它们塞进 blockers（进了=挡广场中央生存路 ⇒ #01 破）。
- 「哪些门还是土径 / 孤岛」——协调者原话设想"仍是土径/孤岛的门→plaza 连接重铺成石街"。**实读：AP1 已把全部 7 door（含外围 shop/home2/library）石街化，无一条残留土径。** 逐门在 Python 里复算 `_build_paths`（同 GDScript 逻辑）：cafe/home 各 8 格、home2 29 格、library 28 格、shop 28 格、wash/work 各 8 格，**7 条全 0 挡格跳过（无断口）**。⇒ 有门的建筑**全部已连街**。第一眼疑似"图书馆是孤岛"是**裁图错位**（它的 L 街走最左 x=12 列再沿 y=26 拐进广场，被我第一版裁框切在框外），复裁坐实其石街完整。
- 「plaza 内哪些格 walkable 可落中心景」——plaza rect[28,21,8,6]=48 格 AP1 已实测**全 walkable（0 挡）**；街具谓词 `_in_area` 把广场/码头**整体排除** ⇒ 广场内部**没有任何 AP1 街具/花草**，中心景可干净落子。
- **真正的孤岛只有 dock**（无门的 plaza-型区）。这是本片 #2 要收的口。

**实测坐实"零金标地基"**（docs/139 ①）：outdoor 导航网 = `f(map.json.blockers)` 纯函数；广场/码头/地标全是 Sim 读不到的绘制或 rect-only。重铺只换像素，一格 walkable/blocked 都不动。

## ② 改了什么（全在 `WorldView.gd`，`git diff --stat` = 1 file，+102/−15）

1. **plaza 中心徽章**（新 `_draw_plaza_medallion`，在 `_draw_area_floors` 的 paving 分支里**仅对 `aid=="plaza"`** 调用；dock 也是 plaza 型但它是码头、不加）：中央同心石环（外环+中环缝）+ 8 向放射灌浆缝 + **冷石心盘**（`P_STONE` 冷灰压在暖砂 flagstone 上 ⇒ 材质对比把中心"沉"下去成焦点）+ 心点高光。★**刻意做成多格尺度**（半径=广场短边×0.42≈2.5格）：默认全镇 zoom 下一格才 ~11px、单格细节读不出，唯有跨数格的环/色块咬得住镜头 ⇒ "镇中心"在整镇俯瞰里也一眼成立（#3）。
2. **有分量的水井**（重写 `_draw_landmarks` 的 `"well"` 臂）：圆石井圈（叠椭圆做圆台厚度）+ 井沿受光 + 井内壁 + 井水 + 水面反光；两根木立柱 + 卷绳横梁 + 井绳 + 吊桶；**双坡木屋顶**（gable，向上伸出本格如建筑屋檐 overhang）。读作**像样的村井**——广场的锚。
3. **有分量的告示栏**（重写 `"board"` 臂）：木外框 + 暖木软木板面 + **一排 6 张不同色告示**（奶油/绿/羊皮/蓝/红/小纸）+ 红披檐 + 立柱。读作**镇公告栏**。
4. **座圈**（新 `_draw_plaza_seatring`，`_draw_landmarks` 循环后按广场 rect 调用）：徽章外沿一圈小石凳，**南半留口**（朝水井/告示板那侧不叠座）⇒ 读作"围着中心坐的一圈"。画在花草/街具之上、居民之下（人站上去自然遮住="有人坐这儿"）。
5. **码头连街**（`_build_paths` door 循环后新增）：给每个**非主广场的 plaza-型区**（=dock）补一条 View-only 连缀石街到主广场，与 door 路**同构**——只写 `_path_set`（Sim 不读）、逐格 `_is_blocked` 跳挡格。连缀格全落已 walkable 空地（dock 中心 x32 竖下 y9→21，实测 0 挡格）。**副产**：`_build_street_props` 的 verge 谓词读 `_is_paved`(含 `_path_set`)，新石街两侧自然点亮几盏路灯/长椅（确定性，见 `ap2_dock_after.png`）。

**调色板**：**零新增授权色**（红线#5 复用优先）。徽章/座圈/井/板全部复用既有常量或其 `.lightened/.darkened` 派生：`P_PLAZA_LINE`、`P_STONE`/`P_STONE_LINE`、`S_PLAZA_HI`、`S_PLANTER`、`P_PUB_FACE/TOP/FOOT`、`P_PUB_ROOF`、`P_WATER_DEEP`、`X_COLD_WHITE`、`X_WOOD_MID`、`D_WOOD_LINE`、`P_COM_FOOT/ROOF`、`P_RES_FLOOR`、`P_TEXT`、`X_PARCHMENT`、`X_SIGNAL_POS/NEG`、`D_BOOK_BLUE`。

**改后读感**（`docs/media/ap2_town_after.png` / `ap2_plaza_after.png` / `ap2_dock_after.png`）：广场中心是**一圈铺装徽章 + 座圈 + 像样水井/告示栏**，一眼读成"大家聚的镇心"；码头由一条石街连回广场，不再孤岛。**默认播放 zoom（1x 整镇 shot-fit）下徽章环/连街依然读得出**（见 `ap2_plaza_{before,after}` 的 1x 近景对照）。

## ③ 硬红旗逐条守住（docs/139 ⑤ + AP1 已验）

1. **typed-layer 数组不许单改** → 未碰 `walls/water/trees/blockers`（`audit_map` PASS：walkable=2653/blockers=403，与改前同）。重铺全走 WorldView 绘制。**landmark 未进 blockers**。
2. **导航连通性/≥2 路由** → 未加任何挡格；连街只写 `_path_set`(纯 View)、落在已 walkable 格（`audit_map` 连通性/工位/≥2 路由 PASS）。
3. **相机/LOD 红线**（ci 4b） → 新绘制**只纯 draw**，不读相机回喂 Sim（`lod_verify` V2+V3abc PASS——WorldView 在该门里根本不实例化，结构性免疫）。
4. **SEASON/PRECIP** → 只动 WorldView 绘制层，未碰 `weather.json/lifecycle.json`（季节/降水门 PASS）。
5. **装饰/景确定性** → 徽章/座圈/井/板/连街全由 `map.json`（doors/areas rect/landmarks pos，只读）+ `T` 常量派生，**无 `randi()/Time`** ⇒ `--shot` 逐像素可复现；空间往返门 `town_after==town_before` 变化像素=0。
6. **陈旧缓存/尺寸 bug 家族** → **不改地图尺寸**；连街仍写既有 `_path_set`（`_build_paths` 里 clear+重烘）、徽章/座圈无缓存（每帧按 rect 现画）⇒ 缓存标志逻辑一字未动。
6b. **街具不进 DECOR_POOL** → 徽章/座圈/井/板全走程序 `draw_*` 图元（同 AP1/landmarks），未碰 `asset_gate` 管的 DECOR_POOL。

## ④ 零金标三证据（实证，含 chain）

1. **开工前 baseline**（`analysis/ap2/golden_before.txt`）：`S0 GATE PASS ✅`，金标 **12/12 seed（含逐 tick 前缀链 12 条）**，det 3/3。烘/本机同为 `godot 4.6.2-stable.71f334935`。
2. **改后**（`analysis/ap2/golden_after.txt`）：`S0 GATE PASS ✅`，金标 **12/12（含链 12 条）**，det 3/3 —— 判决行与 baseline **`diff` 为空（逐字节相同）**。
3. **金标锚文件未动**：`game/bench/golden_digests.json` `git diff` 零改动，sha256 改前改后同为 `52cba6b8…30d724d7`。

⇒ **digest 与 chain 都没动** ⇒ Sim 读 blockers/rect/objects，读不到 outdoor 绘制层与 landmark 重皮。**pure View 应零金标，且实证了它**。`git diff --stat` = **1 file `WorldView.gd` +102/−15**。

## ⑤ 既有 outdoor 门不回归（读判决行）

| 门 | 命令 | 判决行 |
|---|---|---|
| audit_map (ci 1b) | `python tools/audit_map.py` | `AUDIT PASS`（typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线），walkable=2653/blockers=403，exit 0 |
| lod_verify (ci 4b) | `lod_verify.gd -- 48 3` | `LOD-VERIFY GATE: ✅ PASS (V2+V3abc 全绿)`，exit 0 |
| 视觉门 (ci 6：昼夜/void/空间往返/岸线/室内壳/家具/树丛/季节/降水/cafe2f/楼层往返) | `LT_VISUAL=require LT_VISUAL_RUNNER=docker bash tools/visual_gate.sh` | 全绿 **exit 0**（`analysis/ap2/visual_gate.txt`）：DAYNIGHT/ROUNDTRIP/POND/INTSHELL/FURNROLE/TREESTAND(昼+夜)/SEASON/PRECIP/CAFE2F/**FLOOR-ROUNDTRIP 全 PASS**、0 条 FAIL；**空间往返 `变化像素=0/366800 (0.000%)`**（我的重铺+连街确定性 ⇒ town_after==town_before 逐字节相同）；SEASON 昼草地众数仍 (134,179,63) 等——dock 那条 ~12 格石街未翻转草地众数 |
| 全 CI（棒内，提交前） | `LT_VISUAL=require LT_VISUAL_RUNNER=docker bash tools/ci.sh` | **`=== CI PASS ✅ ===`**（1302s，exit 0；0–6 每步全绿、`❌ FAIL:` 计数=0；`analysis/ap2/ci_verdict.txt`）。⚠️2e 可重算门里两条 **`否`(gate:false)** 信息行打 ❌ 但门本身 PASS：`palette-gpl-de00-6p3`(6.3 vs 8.07，读 `palette.gpl`、本棒未碰、注册表明写不判红) + `lint-links-md-count`(93 vs 167，数 md 文件数的快照、明写「不该上门」)——**改前即如此、非本棒引入**（`recalc.py:38`「gate:true 才 rc=1」）。 |

> ⚠️**互补性守卫**（`check_ledger_freshness` 比 committed `HEAD:game`）：本棒改 `WorldView.gd`（进 `game/`）在自 worktree 是**提交前**跑 CI ⇒ 当时 `HEAD:game` 尚=旧树=baked ⇒ 该守卫**假新鲜**通过，**不算数**（同 docs/140 §⑤纪律）。协调者 finalize **在 committed 树重烘 + 重跑 CI** 才是权威门。本棒只保证 golden/其他门绿 + 改动 pure View。

**为什么这些门对本片免疫**（先量清）：昼夜/季节门判 HUD-free 横带 x∈[60,960) y∈[60,420) 的**众数色=草地**（我不动草地/veg；徽章/连街只重上广场内暖砂 + 加 dock 那条 ~12 格石街，远不足以翻转草地众数）；岸线门判两水池剖线（我不动 water；连街走 dock 南侧、不碰池塘）；空间往返门判 `town_after==town_before` 的**确定性**（我的改动确定性 ⇒ 恒等）；降水门判 on/off 差（我的重铺在 on/off 两帧都在 ⇒ 差不变）。**均无冻结的 outdoor 地面像素锚**。

## ⑥ 交付
- worktree：`E:/Documents/Dev/June/26th/.claude/worktrees/agent-a1f0737c21163bd3e`，分支 `worktree-agent-a1f0737c21163bd3e`（reset 到 `integration/batons` tip `df8e74b` = AP1 石街 + AM4 四栋室内 + F1）。
- 提交（不 push/不 merge）。对照图：`docs/media/ap2_town_{before,after}.png`（整镇）、`ap2_plaza_{before,after}.png`（广场中心近景）、`ap2_dock_after.png`（码头连街）。
- 证据：`analysis/ap2/golden_{before,after}.txt`、`visual_gate.txt`、`ci_verdict.txt`。
