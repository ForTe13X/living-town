# 161 · AV3 · 补完地面暖化：plaza / stone / paths + 水色调和（车道 V 第四片，零金标）

> 底稿：docs/159（AV2 生成瓦地形）§六.4 亲点的两块欠账——「stone/plaza 是程序化色（非瓦，不在射程）」+
> §六.3「冷蓝 CC0 池水配暖色地形」这条被接受的取舍。本片把这两块收口。
> **零金标视觉纪律**（同 AT1/AV1/AV2，docs/148/156/159）：只改 WorldView 绘制读的 **View 侧调色板 + draw 代码**，
> Sim 一格读不到 ⇒ 金标 12/12 逐字节相同（含逐 tick 前缀链）。
> owns：`game/scripts/WorldView.gd`（唯一改动文件）+ 本文 + `docs/media/av3/*`。
> WorldView.gd 内的射程：`P_STREET` 常量（石街，路专用）· 新 `G_PLAZA_WARM`/`G_STONE_WARM` + 派生阶 ·
> `WATER_DAY` 常量（水日间调和罩）· `_draw_area_floors`（广场 paving / 工坊 slab 就地暖化）·
> 石街 cobble draw（整格 jitter）· `_draw_plaza_medallion`（apron/环缝进暖石族）· 水层 `wtint` 一行。
> **没碰**：`P_PLAZA` / `P_STONE` **两个常量**（它们还喂室内茶座/咖啡地板、市集货袋、建筑石基/井——动了会挪 FURNROLE/floor/cafe2f 的采样面）/
> AV2 的 5 张生成瓦与 8 张 CC0 岸线瓦（地形 PNG 一张没动）/ Sim.gd / `golden_digests.json` / 任何 `game/data/**` /
> 室内绘制 / 建筑 / map.json / public(冷澡堂石板) 与 res·com(暖木地板)（非"欠暖的石地面"，见 §五）。
> worktree `agent-a2648c59555771e53` · 分支 `worktree-agent-a2648c59555771e53` · ff 自 `integration/batons`@9eb1e77。

## 〇、一句话
AV2 把草/土/池心烘暖后，全镇还剩三块**冷石地面**（广场偏黄砂、石街中性灰、工坊石近中性灰）+ 两个**偏冷蓝**的池塘。
本片把 plaza / 工坊石 / 石街收敛到**同一族【暖灰鹅卵石】**（照参考 `ref_terrain_v1_stardew.png` 的 STONE PAVEMENT·PLAZA
整行同料），每块再叠一档**确定性 `_hash` 明暗 jitter**读作"铺过的暖石"；并把水的日间 `wtint` 只压蓝通道一档，
把池水由 cyan-blue(B>G) 收进 **teal(G≥B)**，与参考 RIVER 行的 teal 同族。
**全部程序化**（Control._draw 上色 + `_hash`，非瓦、非贴图转换）。**金标 12/12 逐字节相同 + 全 CI 视觉门 PASS（含 POND 仍绿）。**

## 一、改前清点（实读行号，AV2 之后的状态）
| 面 | 位置 | AV2 后画法 | 冷在哪 |
|---|---|---|---|
| 石街 cobble | `P_STREET #a89e8b` + `_draw` 3163-3174 | 单档暖石底 + 2×2 子格 hash 明暗 + 石缝 | R−B=29，是"略偏暖的中性灰"，与暖草同框仍读冷石 |
| 广场 flagstone | `P_PLAZA #c3a97a` + `_draw_area_floors` paving 分支 | 2×2 大方砖 S_PLAZA_HI/LO 交错 + 徽章 | 偏黄砂（G−B=47），不是参考的暖**灰**石；且一整片匀色无颗粒 |
| 工坊石板 | `P_STONE #9b968d` + slab 分支 | 棋盘 0.08 白 + 石缝 | 近中性灰（R−B=14），全镇最冷的地面之一 |
| 池塘 | AV2 生成瓦（心）+ 8 张 CC0 岸线瓦 · `wtint` 日间恒白 | 池心暖 teal (60,129,134)、岸线浅水亮 cyan (31,161,175) | 岸线浅水 **B>G**（cyan-blue），整池对暖镇偏冷 |

## 二、改了什么（`WorldView.gd` 单文件）

### 1. 暖灰鹅卵石族（新调色板，克制不碰 P_PLAZA/P_STONE 常量）
暖石 hue 量自参考 (155,131,96)：`G≈R·0.86 / B≈R·0.64`。三档亮度：广场亮=社交焦点 / 石街中 / 工坊石略沉。
- `P_STREET` **常量**由 `#a89e8b` 压到 **`#a8916c`**（R−B 29→60，进暖石族）。**这是本片唯一直接改的授权色常量**，
  安全性 grep 实证：`P_STREET` + 全部派生（`S_STREET_*`/`S_CURB`）**只在户外石街绘制里用**（0 处室内/道具/门采样面）⇒ 零室内爆炸半径。
- 新 `const G_PLAZA_WARM #c0a682`（广场，比 P_PLAZA 退黄进灰：G−B 47→36，仍是全镇最亮地面）
  + `const G_STONE_WARM #a18a65`（工坊石，原近中性灰 → 暖灰石）+ 各自 `HI/LO/LINE` 派生 var。
- **删** `S_PLAZA_HI`/`S_PLAZA_LO`：唯一消费者已全部换到 `G_PLAZA_*`，成零引用，按仓库纪律不留（同 R2 删 `P_KERB`）。

★ **为什么广场/工坊石【不改常量、改 draw】**：`P_PLAZA` 还喂室内茶座地板(`_mat_floor` parlor)、市集货袋/藤篮；
`P_STONE` 还喂咖啡后厨地板、建筑石基/井/徽章冷心。动常量会把 **FURNROLE / floor-roundtrip / cafe2f** 的采样面一起挪走。
故广场(paving)/工坊石(slab)的暖化在 `_draw_area_floors` 里【就地覆盖 base】，只碰户外那一层像素，室内逐字节不动。
**实测佐证**：FURNROLE 签名色里 `#c3a97a`(P_PLAZA)/`#9a8253`(P_PLAZA_LINE) 原样在（货架/杯碟架/毛巾架），门仍绿（§四）。

### 2. 每块确定性明暗 jitter（"铺过的暖石"，非死色块）
全走 `_hash(x,y,salt)`（纯位置、无 RNG/Time ⇒ ROUNDTRIP 冻结帧逐像素可复现）：
- 石街：整格底再抖一档 `_hash(rx,ry,46)%5`（多数保持 base、少数微亮/微沉），叠在原 2×2 子格颗粒之上。
- 广场：每块大方砖 `_hash(块坐标,48)%4` 再抖（更亮/更沉/不动），最亮档留在 base ⇒ 广场仍是全镇最亮地面=社交焦点。
- 工坊石：逐格 `_hash(x,y,47)%6`（亮石/暗石/微亮，其余 base）。
- 徽章：apron/环缝随广场进暖石族（`G_PLAZA_*`），**冷石心盘 `P_STONE` 故意留冷**——与暖石广场拉材质对比，心"沉"成焦点（保留 AP2 的焦点对比）。

### 3. 水色日间调和（`WATER_DAY`，POND 门下的风险项，实测过关才留）
新 `const WATER_DAY := Color(1.0, 1.0, 0.90)`；`wtint` 日间基调由纯白改为它，夜里 `WATER_DAY.lerp(WATER_NIGHT, _wn)`。
**只压蓝通道一档**：池水由 cyan-blue(B>G) 收进 teal(G≥B)——池心 (60,129,134)→(60,129,123)、岸线浅水 (31,161,175)→(31,161,161)。
R/G 不动 ⇒ 不掉亮度、不动岸线台阶的【存在】，只挪蓝。夜 tick 深、`_wn` 高 ⇒ 夜罩≈原 `WATER_NIGHT`（蓝仅差 ~1/255），守住 docs/46 §二-D3-2 的夜彩度对照。

## 三、零金标（证 Sim 读不到本片改动）
```
GODOT --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json
⇒ ✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条；烘于/本机同为 4.6.2-stable (official).71f334935）
  ✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链) 3/3
=== S0 GATE: PASS ✅  (硬不变量 12/12 全绿, 软 ≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
`git status` 里 `game/bench/golden_digests.json` **未修改**（磁盘逐字节不动）——本片全部是 View 侧调色板 + draw 代码，Sim 均读不到。

## 四、gate 表（docker `tol=0`，实跑）
| 门 | 结果 | 关键数（before AV2 → after AV3） |
|---|---|---|
| S0 金标 + 32 条不变量 | ✅ PASS | 12/12 · det 3/3（§三）|
| **POND**（水色风险项）| ✅ PASS | 昼 path median **1.727 → 1.761**（↑，蓝减改了折线几何）· 台阶 median 5→5 · 一步直达 6.7%→6.7% · 水众数 (31,161,**175**) B>G → (31,161,**161**) G=B · REF 149.8→138.7（>>8）· **夜 path median 1.922 逐字节不变**（夜 _wn 高 ⇒ wtint≈原夜罩）|
| **SEASON**（地面四季可分）| ✅ PASS | 昼 min ΔE00 **8.21**（春↔冬）· 夜 min **4.28**（春↔夏）· 阈 3.20 —— 与 AV2 基线**同值**：世界主色是**草**（117,141,54），plaza/石街/工坊石不进 world_mode ⇒ 本片不动它 |
| ROUNDTRIP（空间往返冻结帧）| ✅ PASS | A[map] 变化像素 **0/366800 = 0.000%** —— 新 draw 全 `_hash` 确定性，逐像素复现 |
| DAYNIGHT | ✅ PASS | 夜 world_mode (50,66,43)=expect · dmax=0（地面众数=草，不受本片影响）|
| INTSHELL（室内壳类型）| ✅ PASS | 7 栋/4 类，异类最小 ΔE 17.72 —— 没碰室内墙 |
| FURNROLE（家具语义）| ✅ PASS | 6 栋/5 类，异类最小 ΔE 29.19 · 签名色 `#c3a97a`/`#9a8253` 仍在 ⇒ **P_PLAZA 未动** |
| TREESTAND（林相点阵）| ✅ PASS | 昼 P≈25.9 / 夜 P≈13.1 · 地面参考色现取空地草格（#758d36），不落 plaza/石街 |
| CAFE2F / FLOOR-ROUNDTRIP / space_roundtrip / PRECIP | ✅ PASS | 室内/降水未碰，逐段全绿 |

> POND 的判决方式：它量的是**北池那道草→岸泥→浅水→深水的过渡**（`path`/`levels`），本片把水层整体压蓝一档
> **同时压在池心与 8 向岸线上**（一视同仁），因此直接压在门量的那道岸上。实测 **path median 反而升**（1.727→1.761）：
> 蓝减让"草→水"直线距离 REF 变短、而折线本身几乎不变 ⇒ 比值升。台阶/一步直达占比不变。**门更绿，不是勉强过。**

## 五、诚实边界（不藏）
1. **程序化，不是瓦转换**：plaza/stone/paths 是 `Control._draw` 的**上色 + `_hash` 颗粒**，不是 autotile 瓦——沿用 AV2 §六.4 对这块的定性（它当时把 stone/plaza 归为"程序化色、非瓦"，本片正是在这一层暖化）。参考给的是"暖灰石 hue + 每石变体"的神韵，落到俯视 T 格的程序化铺面，未抄它的具体石块排布。
2. **水色调和【已出货】，但它治的是"整池 hue"不是"心=边"**：单一 `wtint` 乘在所有水瓦上 ⇒ **保持池心与岸线的相对差**，
   动不了 AV2 那条"生成心瓦(muted teal) vs CC0 岸线浅水(brighter cyan)"的**逐瓦亮度差**（那要改瓦，不在本片射程/AV2 owns 瓦）。
   本片做到的是把**整池**由 cyan-blue 收进 teal（心边同向挪蓝），与暖镇更配；心/边的明暗落差仍在，那是 AV2 接受的边界。
3. **没碰 P_PLAZA/P_STONE 常量** ⇒ 室内茶座地板仍是旧砂色 P_PLAZA、咖啡后厨仍是旧灰 P_STONE：**户外广场铺装 ≠ 室内茶座地板**，
   这是刻意的分离（护 FURNROLE/floor/cafe2f），不是漏改。若日后要室内也统一暖石，另开一片、连同那几道门一起重量。
4. **public(澡堂/图书馆冷石板) 与 res·com(暖木地板) 原样不动**：它们不是"欠暖的石地面"（澡堂本就该冷、木地板本就暖），
   且动它们会挤 INTSHELL/floor 门的关系余量 —— 收益小、风险实，不做。
5. **工坊户外石板大半被建筑盒遮住**：暖化主要在区块边缘可见；这是地图布局决定的，不是没暖到。

## 六、媒体（`docs/media/av3/`，真引擎 docker 渲染 seed3 游戏日3）
- 整镇 before/after：`{before,after}_town_{day,night}.png`（正午 tick600 / 夜 tick488，`--shot-fit`）。
- `plaza_paths_before_after.png`：广场+石街 ×4 放大（上 before / 下 after）——暖灰石 + 每块 jitter 颗粒。
- `pond_before_after.png`：北池 ×6 放大（左 before cyan-blue / 右 after teal）。
