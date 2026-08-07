# 140 · AP1 内容棒——outdoor 连续街区第一片：门→广场【石铺连街】+ verge 纯 View 街具

> 底稿 = docs/139（outdoor 金标面 scoping）。本片是室内「就地换画法 + 地面重绘 + 装饰只落 free cell」的 **outdoor 孪生**：
> `blockers/rect/objects/portals/walls/water/trees` **一字未动**，只在 `WorldView.gd` 的 outdoor 绘制路做视觉连缀。
> **零金标**（Sim 读 blockers，读不到绘制），下面第 ④ 节三证据实证，不是口头声称。
> owns：`game/scripts/WorldView.gd`（只动 `_build_terrain/_build_paths/_build_decor` + 相关调色板 + 广场铺装绘制）、本文档、`docs/media/ap1_*`、`analysis/ap1/`。

## ① 现状清点（改前，行号锚在 `integration/batons` 6e2b474 的 WorldView.gd）

| 面 | 改前画法 | 位置（改前行号） | Sim 读吗 |
|---|---|---|---|
| 门→广场路网 | `dirt` 瓦片 + 一层 `Color(X_WOOD_MID,0.16)` 暖褐罩 ⇒ 读作**土径** | `_draw_body` 2762–2770（`_ac("paths",_path_set)` 两趟） | ✗ 纯 View |
| 路网几何 | 每家门外第一格起 L 形（先竖后横）铺到广场最近带，**只铺 walkable 格** | `_build_paths` 1022–1064 | ✗（读 doors/plaza rect 烘 `_path_set`；Sim 不读 `_path_set`） |
| 中央广场 | `P_PLAZA(#c3a97a)` 砂色底 + 十字缝 line@0.28 ⇒ 读作**孤立的砂色方块** | `_draw_area_floors` 的 `_:`(paving) 分支 1209–1213 | ✗（读 areas[*].type，Sim 零读 type） |
| verge 草地 | 只散花草石（`DECOR_POOL` 6 项，~22% 密度，谓词=非区∧非家具∧非blocked∧非路） | `_build_decor` 782–855（谓词 813） | ✗ 纯 View |

**改前读感**（`docs/media/ap1_before.png`，docker 真渲、seed3 正午 shot-fit）：**草地上的建筑孤岛 + 细褐土径通向一小块砂色广场**。

**实测坐实"零金标地基"**（docs/139 ①）：`map.json` 的 `walls∪water∪trees == blockers`（403 = 167+80+156，`audit_map` 硬校验），
plaza[28,21,8,6]=48 格、dock[30,7,4,2]=8 格 **全 walkable（0 格 blocked）**，7 door、well[30,26]/board[33,26] 两地标都在 plaza rect 内。
⇒ 广场与路网**本就是 walkable 格**，重铺只换像素、不动任何格的 walkable/blocked。

## ② 改了什么（全在 `WorldView.gd`，`git diff --stat` = 1 file，+169/−10）

1. **门→广场石铺连街**（替换 2762–2770 那两趟土径绘制）：`dirt` 打底保颗粒 → 暖石底 `P_STREET(#a89e8b)@0.90` → 每格 4 块 `_hash(rx*2+si,ry*2+sj,45)%3` 明/暗鹅卵石 → 石缝十字 → **路缘石**（每街格朝非铺装侧压一条 `S_CURB` 暗边）。读作**砌出来的石街**，不是踩出来的土径。
2. **广场 flagstone**（`_draw_area_floors` 的 paving 分支）：`P_PLAZA` 底上加 2×2 大方砖交错明暗（`S_PLAZA_HI/LO@0.30`）+ 十字灌浆缝 + 亮内沿。石街鹅卵石(2×2 细分)汇入广场 flagstone(2×2 大块) ⇒ **同一套铺装语言**，街—广场读作一体。
3. **verge 纯 View 街具**（新 `_build_street_props`/`_draw_street_prop`，`_build_decor` 里一并烘）：路灯/花坛/长椅/系缆柱。安全谓词**复用** `_build_decor` 那套（非区∧非家具∧非blocked∧非路），其上加一层"贴着铺装"(`_is_paved` 的 8 邻) 把散布收敛到 verge。落点/类型全走 `_hash(x,y,{41,43})`（无 RNG/Time）。实测 **84 件**：路灯 30 / 花坛 22 / 长椅 11 / 系缆柱 21。
4. 调色板：新增 `const P_STREET`（暖石板，取在 P_STONE↔P_PLAZA 之间偏暖）+ 9 个从 P_STREET/P_PLAZA/X_WOOD_MID/P_STONE **派生**的阶（`S_STREET_HI/LO/SEAM`、`S_CURB`、`S_PLAZA_HI/LO`、`S_LAMP_POST`、`S_BENCH_WOOD`、`S_PLANTER`）——不新增授权色（红线#5 复用优先）。

**改后读感**（`docs/media/ap1_after.png`）：**门→广场是连续的鹅卵石街 + 路缘石，汇入中央 flagstone 广场，街两侧路灯/长椅/花坛成列**。镇中心一眼读成连着的街区/广场。

## ③ 硬红旗逐条守住（docs/139 ⑤）

1. **typed-layer 数组不许单改** → 未碰 `walls/water/trees/blockers`（`audit_map` PASS，见 ⑤）。重铺全走 WorldView 绘制/调色板。
2. **导航连通性** → 未加任何挡格（街具落在 walkable 草地、Sim 不感知；`audit_map` 连通性/≥2 路由 PASS）。
3. **相机/LOD 红线** → 新绘制**只纯 draw**，不读相机回喂 Sim（`lod_verify` V2+V3abc PASS）。
4. **SEASON/PRECIP** → 只动 WorldView 绘制层，未碰 `weather.json/lifecycle.json`（季节门/降水门 PASS）。花坛植栽走 `_season_veg()`（与草地同源）。
5. **装饰确定性** → 街具落点/类型 + 石街鹅卵石明暗全走 `_hash(x,y,salt)`，无 `randi()/Time` ⇒ `--shot` 逐像素可复现。
6. **陈旧缓存/尺寸 bug 家族** → **不改地图尺寸**；新缓存 `_plaza_cells`（`_build_paths` 里 clear+重烘，同 `_path_set`）、`_street_prop_items/_cells`（`_build_decor` 里 clear+重烘，同 `_decor_items`）**不新增缓存标志** ⇒ `_invalidate_world_caches`/cache-gate 逻辑一字未动。

## ④ 零金标三证据（实证，含 chain）

1. **开工前 baseline**（`analysis/ap1/golden_before.txt`）：`S0 GATE PASS ✅`，金标一致 **12/12 seed（含逐 tick 前缀链 12 条）**，det 3/3。
2. **改后**（`analysis/ap1/golden_after.txt`）：`S0 GATE PASS ✅`，金标 **12/12（含链 12 条）**，det 3/3 —— 与 baseline 判决行 **`diff` 为空（逐字节相同）**。
3. **金标锚文件未动**：`game/bench/golden_digests.json` sha256 改前改后同为 `52cba6b8…30d724d7`（`git diff` 对它零改动）。

⇒ **digest 与 chain 都没动**：Sim 读 blockers/rect/objects，读不到 outdoor 绘制层。这是 docs/139 ①"outdoor 导航网是 f(map.json) 纯函数、无涌现漂移入口"在本片上的实证——**pure View 应零金标，且实证了它**。

## ⑤ 既有 outdoor 门不回归（读判决行）

| 门 | 命令 | 判决行 |
|---|---|---|
| audit_map (ci 1b) | `python tools/audit_map.py` | `AUDIT PASS`（typed-layers 一致 + 全可达 + 每家具有交互格 + ≥2 路线），exit 0 |
| lod_verify (ci 4b) | `lod_verify.gd -- 48 3` | `LOD-VERIFY GATE: ✅ PASS (V2+V3abc 全绿)`，exit 0 |
| 视觉门 (ci 6：昼夜/void/空间往返/岸线/室内壳/家具/树丛/**季节**/**降水**/cafe2f/楼层往返) | `LT_VISUAL=require LT_VISUAL_RUNNER=docker bash tools/visual_gate.sh` | 全绿 **exit 0**：DAYNIGHT/ROUNDTRIP/POND/INTSHELL/FURNROLE/TREESTAND(昼+夜)/SEASON/PRECIP/CAFE2F/FLOOR-ROUNDTRIP **全 PASS**、0 条 FAIL；`空间往返 A1[map] 变化像素=0/366800 (0.000%)`（我的重铺确定性 ⇒ town_after==town_before 逐字节相同）|
| 全 CI | `bash tools/ci.sh` | **`=== CI PASS ✅ ===`**（全程 1277s，exit 0；0–6 每一步全绿，含 4a 宏观池/4d 外部后端/4h state_projection/5 story_test 193s/6 视觉门九道全 PASS）|

**为什么这些门对本片免疫（先量清、docs/139 纪律）**：昼夜门/季节门判的是 HUD-free 横带 x∈[60,960) 的**众数色 = 草地**（我不动草地/veg）；岸线门判两水池剖线（我不动 water、街具收敛在中央 verge、离池塘远）；空间往返门判 `town_after==town_before` 的**确定性**（我的改动确定性 ⇒ 恒等）+ 界外带活着（我不动界外层）；降水门判 on/off 差（我的重铺在 on/off 两帧都在 ⇒ 差不变）。**均无冻结的 outdoor 地面像素锚**。

## ⑥ 交付
- worktree：`E:/Documents/Dev/June/26th/.claude/worktrees/agent-a6d72996575bc04d8`，分支 `worktree-agent-a6d72996575bc04d8`（基于 `integration/batons` 6e2b474 = docs/139 tip）。
- 提交（不 push/不 merge）。对照图：`docs/media/ap1_before.png` / `ap1_after.png`。证据：`analysis/ap1/golden_{before,after}.txt`。
