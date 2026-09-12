# 139 · outdoor 金标面 scoping —— 连续街区探路（派内容棒前的只读地勘）

> 路线图 §review 2026-08-07 定的纪律：outdoor「连续街区」是**金标最险的一片**（全 ~60 居民每天在 `town/outdoor` 64×48 导航网寻路），**先只读勘金标面、再照室内同款纪律派内容棒**。本文是勘测结论 + 第一根内容棒底稿。协调者已 spot-check 承重项（下标 ✔）。

## ① outdoor 导航网的真源 ✔
- **地形=数据 authored**（非运行期程序生成）：`Sim.gd:525` `world = _read_json("res://data/map.json")`；map.json 由离线 `tools/gen_town.py` 确定性生成（无 RNG）、产物入库。
- **决定每格 walkable/blocked 的唯一函数 = `_build_nav()`（Sim.gd:3975-3991）**：`_blocked = map.json.blockers ∪ {space=="town" 的 object.pos}`（排除 `fest_`/`civic_` 动态对象）。A* 走 `_grid_for("town","outdoor")→_cell_walkable`。
- **✔ 协调者已验**：全 `Sim.gd` 里 `_blocked[...]=` 只在 3976/3981/3989（全在 `_build_nav` 内）；运行期对 blocked 集**零写入** ⇒ outdoor 导航网是 `f(map.json)` 的**纯函数**，无涌现漂移入口。**这是 outdoor 零金标的地基。**

## ② golden-move 面：两路分析（照室内同款）+ outdoor 独有面
**移金标（Sim 读）**：
- **路①** advertises→决策候选：outdoor `objects`（床/灶/吧台/浴池/工作台/长椅/游戏机，带 advertises）、`production.json` worksites(`_compile_worksites` Sim.gd:711)、`buildings.json`(`_compile_buildings` :578) 编译成 town objects 进 `_object_candidates`(:1917)。动 pos/advertises/amount = 移金标。
- **路②** 格→挡格：blockers + object.pos → `_blocked`。任一格进出 blocked = 全居民 A* 重排 = chain 漂 = S0 红。
- **outdoor 独有（也移金标）**：`areas[*].rect` 被 `_area_at`(:3862 社交桶) + `_area_centroid`(:2764 attend/扩容/far-drift 的**寻路目标**) 读 ⇒ 改 rect / 增删 area（**含空区**——它是新社交桶）= 移金标。`areas[*].label` 进叙事文本、金标邻接、**当"别碰"处理**。

**零金标（纯 View，Sim 读不到）**：
- `areas[*].type`（只 WorldView `_build_terrain` 1006-1018 读上墙色 + plaza 特判；Sim 不读；map dock `_type_why` 实测 12/12）。
- `walls`/`water`/`trees` 数组（纯渲染；Sim 只读 `blockers`）——⚠但 CI 硬耦合见 ⑤红旗1。
- `doors` 数组（纯 View 土路；Sim 零读，导航门=spaces.json portals）。`landmarks`（well/board，**可踩装饰、永不进 blockers**）。
- 一切地面/草/水/路/装饰绘制 + 季节/降水 wash（WorldView 调色板常量、`_build_decor` 程序散布、`_draw_climate_wash/rain/snow`）。

## ③ 高频路径格 vs 安全 free cell 的判别法
⚠**布局推断、未跑仿真 heatmap（未验证）**：中央四区(home/cafe/wash/work 环抱 plaza[28,21,8,6]) + 门→plaza 走廊 = 高频带（约 x18–46×y7–35，碰不得）；外围 wilderness（地图边缘/树林周边/远角）= 可落装饰。
- **✅ 现成机器判别器（直接复用）**：`_build_decor`(WorldView.gd:810-820) 已在算安全散布格：`非区 ∧ 非家具 ∧ 非blocked ∧ 非土路`（花草石现在就散这上面）。**这就是 outdoor 的"安全 free cell"谓词**，新街具复用它即可，不需 heatmap。
- 只有想放**挡路**街具才需 heatmap——而那本身移金标、不做 ⇒ 第一片不需要 traffic 探针（F3：不投机造探针）。

## ④ 分级零金标方案
**可零金标做（纯 View）**：① 地面/路/plaza 重铺画法（WorldView 调色板 + `_build_paths` 画色，把**已 walkable 的**门→plaza 走廊+plaza 画成石铺连街）；② 街景装饰落 `_build_decor`-安全 free cell（路灯/花坛/招牌/长凳，当纯美术）；③ `areas[*].type` 换 View 配色（Sim 零读）；④ landmarks 重皮 + 可踩 props（**永不进 blockers**）；⑤ 季节 wash 样式微调（红旗4 边界内）。

**必须避开（移金标）**：改 `blockers` 任一格 / 改 `areas[*].rect` 或增删 area（含空区）/ 增删挪 outdoor `objects` / 改 spaces.json `portals` / 单改 `walls·water·trees` 数组（CI 红，红旗1）/ 碰 `weather.json`·`lifecycle.json`（红旗4）。

**★ 推荐第一片（可直接派）**：**plaza + 现有门→plaza 土路网重铺成石铺"连街/广场"**（`_build_paths` 已在的 walkable 走廊格），两侧 verge（路与建筑墙间、没人走的 free cell）落纯 View 街具。= 室内"就地换画法 + 地面重绘 + 装饰只落 walkable free cell"的 outdoor 孪生：**blockers/rect/objects/portals 一字不动，只做视觉连缀**。

## ⑤ 风险红旗（outdoor 独有，派棒必钉死）
1. **✔ CI 硬耦合 `audit_map.py:90-99`**：校验 `walls∪water∪trees == blockers`（否则"渲染/导航脱节"判红）。⇒ **不许靠编辑 typed-layer 数组重铺地形**；重铺走 WorldView 绘制/调色板，别碰四数组。（landmarks 显式不计入并集。）
2. **audit_map 连通性/≥2 路由/工位连通**：任何挡格增加可能切孤岛——不加挡物即免疫。
3. **相机/LOD 红线**：`bench/lod_verify.gd`(ci.sh 4b) 5 个 lod_focus digest 必须逐字节同。outdoor 是相机真移动/缩放处 ⇒ 新绘制**只许纯 draw、绝不读相机再回喂 Sim**（WorldView.gd:150-151 红线）。
4. **SEASON/PRECIP 混淆**：季节/降水 wash 是 View，但门控在 `Sim.season_today`/`weather_today`（来自 weather.json/lifecycle.json，且驱动 Sim 决策）。做"户外季节观感"**只动 WorldView wash 层，绝不碰 weather/lifecycle**。
5. **程序装饰确定性**：新装饰必须 `_hash(x,y,salt)+Sim.tick_no`（无 RNG/Time），保 `--shot` 逐像素复现。
6. **陈旧标志位/缓存 bug 家族（WorldView.gd:660-673）**：`_terrain_built`/`_paths_built`/`_decor_built` 从不清；`_grass_var` 按**首张**世界 `w*h` 分配却用**当前** `w` 索引。64×48 恒定 → 潜伏；**若连街内容改了地图尺寸就画错格/越界** ⇒ 第一片**不改图尺寸**即避开。
