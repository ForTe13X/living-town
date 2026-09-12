# 159 · AV2 · 生成瓦地形大改：暖色星露谷地面（车道 V 第三片，零金标）

> 底稿：docs/146（视觉参考素材集）+ docs/49 §七（G5 地形门 + 岸线）+ 用户「terrain 类星露谷」。
> **零金标视觉纪律**（同 AT1/AV1，docs/148/156）：只改 WorldView 绘制读的 **View 侧资产 + 一个 View 常量**，
> Sim 一格读不到 ⇒ 金标 12/12 逐字节相同（含逐 tick 前缀链）。
> owns：`game/assets/art/terrain/{grass_a,grass_b,grass_flowers,dirt,water}.png`（5 张重画）
> + `game/scripts/WorldView.gd` 的 **`SEASON_VEG["夏"]` 一个常量**（AV2 派单唯一允许的 WorldView 改动，仅当 SEASON 门要求）
> + `tools/slice_terrain_ref.py`（新）+ `tools/terrain_gate.py`（改 hybrid）+ `tools/terrain_hashes.json`（新，--rebless 烘）
> + `tools/ci.sh` 第 2c 步注释 + `tools/asset_gate.py` `ELSEWHERE` 注释（两处只改注释文案，声明式越界）
> + 本文 + `docs/media/av2/*`。
> **没碰**：`water_{n,s,e,w,ne,nw,se,sw}.png` 这 **8 张 CC0 岸线自动贴图**（见 §二）/ `Sim.gd` / `Inv` /
> `golden_digests.json` / 任何 `game/data/**` / 室内绘制 / stone·plaza（程序化色，非瓦）/ farmland·sand·boardwalk（无消费者，禁出货死资产）。
> worktree `agent-a2ee9cc01dc13c139` · 分支 `worktree-agent-a2ee9cc01dc13c139` · ff 自 `integration/batons`@2210d99。

## 〇、一句话
把 5 张**原样裁切的 CC0 地形瓦**（grass_a/b/flowers/dirt/water）换成从 `docs/media/references/ref_terrain_v1_stardew.png`
**降采样生成**的暖色星露谷瓦（`tools/slice_terrain_ref.py`），并把地形门 `terrain_gate.py` 从"全 13 张当场重建"改成
**hybrid**：8 张 CC0 岸线瓦仍当场重建-比对，5 张生成瓦改 hash-pin。R4（不许生成图出货）对本切片 **WAIVED**。
暖色基草把【夜】春↔夏季节色差压破了 3.2 门（4.30→2.73），据此把 `SEASON_VEG["夏"]` 再压深一档
（0.72,0.90,0.58 → 0.60,0.82,0.46）回到 4.28 ≥ 3.20。**金标 12/12 逐字节相同 + 全 CI 视觉门 PASS。**

## 一、范围：为什么恰好这 5 张
| 出货瓦 | 来源（参考图 7 行×8 列） | 用途 |
|---|---|---|
| `grass_a` | GRASS · CENTER | 主草地（`_grass_var` 权重 70%）|
| `grass_b` | GRASS · ALTERNATE CENTER | 草地变体（24%）|
| `grass_flowers` | GRASS · hero（第 1 列大格，花最多）| 草地变体（6%）|
| `dirt` | DIRT PATH · CENTER | 土路 |
| `water` | RIVER/WATER · CENTER | **只是池心填充**（岸线仍是 CC0 八向）|

`draw_texture_rect(tex, Rect2(x,y,T,T=48), false, tint)` 按 T×T 填满、与源尺寸无关 ⇒ **16px 瓦是零改动 drop-in**（WorldView 绘制一行没动）。
`.import` sidecar 在本仓库 `.gitignore`（`*.import` + `.godot/`），godot 每次 `--import` 现生成 ⇒ **没有 .import 要提交**；
新瓦走的正是旧瓦同一条 `Art.tex()`（NEAREST + 无损）路径。

## 二、为什么**保留** 8 张 CC0 岸线瓦（这是本片最关键的一条克制）
`water_{n,s,e,w,ne,nw,se,sw}.png` 一个字没改。它们把**陆地侧的草地键成透明**，让 `WorldView._season_veg()`
按季染过色的草地透上来。参考表的岸线是**不透明、单朝向**的：换上去会（a）把 slice_shore.py 抬头记的
"秋天池塘套一圈春绿"的 bug 请回来（烘死的春绿草不随季变黄），(b) 失去键控 ⇒ POND 门变红。
⇒ **暖色地形 + 冷蓝 CC0 池水**是这一格接受的取舍（诚实边界，见 §六）。实测 POND 门在换瓦后仍 PASS（§五），
证明 CC0 水层完好。stone/plaza（程序化色）、farmland/sand/boardwalk（无消费者）也都不动。

## 三、切法（`tools/slice_terrain_ref.py`）
参考图 1448×1086，每格 ≈130px 见方、外圈一道深色圆角边框。逐格：① band 定位（行 y / 列 x band 人工量、写死）；
② inset 8px 去直边框；③ 取**居中正方形**（短边 ×0.90）躲圆角（圆角处仍留深框，直接缩放会揉进边缘像素）；
④ LANCZOS 缩到 16×16；⑤ 轻度 posterize（每通道 5 bit=32 级）把抗锯齿糊出来的过渡色吸回硬边。5 张都是不透明地面 ⇒ alpha 恒 255。

**眼验**（每张 16×16 用 NEAREST ×10 放大后 Read，= 出货像素逐点等价；预览留在 `docs/media/av2/tiles/*_x10.png`）：
grass_a/b/flowers = 暖橄榄绿、带细微纹理与零星小花（均值分别 (106,121,33)/(108,123,29)/(111,126,30)，色数 74/50/52）；
dirt = 暖金褐 (199,148,74)；water = 蓝绿带波纹 (45,121,129)，色数 63（多色 ⇒ 有利 POND 池心 distinct）。**均非乱码、题材正确。**

## 四、terrain_gate.py 改 hybrid（本片的重头，keep it honest）
G5 原门 = 全 13 张当场从 CC0 总表重建 + 逐像素比。5 张生成瓦**再也无法从任何 CC0 重建** ⇒ 原判据结构上失效。改法：

| 半 | 瓦 | 判据 | 自证（每次跑都做）|
|---|---|---|---|
| A（CC0）| 8 张岸线 | 当场重建 + 逐像素比（**G5 原样**）| ① 来源自证（读 CC0 ≥1、读出货 **0**）② SHORE teeth（翻 1px⇒compare 报 1px 指名）③ 扫过量>0 |
| B（生成）| 5 张 | **hash-pin**：解码后 RGBA 的 sha256 == `tools/terrain_hashes.json` | ② 生成瓦 teeth（翻 1px⇒sha256 必变，杀常量 hash/return-True）③ 扫过量>0 |
| 共 | 13 张 | 文件集合 == LEGACY∪SHORE（0 缺 0 多）| — |

**用解码 RGBA 的 sha256 而非容器字节**：容器字节随 zlib/Pillow 版本漂，解码像素不漂（同 2b/2c/2d 的硬判据）。

**★ 眼验棘轮（R4 waived 下唯一诚实的缓解）**：`tools/terrain_hashes.json`（anchor 形状，带 `_meta.rebless_history`）
**只能由人**跑 `python tools/terrain_gate.py --rebless "原因"` 重烘，且**必须**在【Read 眼验每张瓦 + 录一帧真机整镇图】之后；
**CI 永不自动重烘**。本片初烘的证据：`docs/media/av2/after_town_day.png` + docker 视觉门全 PASS（§五）。

**★ 丢掉的自证（大声记下）**：G5 第 4 条（`slice_visual.py`↔`slice_shore.LEGACY` 两份切图坐标一致）对生成瓦
**结构上不再适用，本片删掉了它**。代价：两份坐标表的漂移不再有专门判据（岸线半的重建-比对间接兜住"草地键控调色板漂了"，
因为 `slice_shore.build()` 仍用 LEGACY 坐标裁 CC0 草地取键控色）。这是真实的判别力损失。
`slice_shore.LEGACY` 的 5 个名字保留不动 ⇒ `asset_gate.check_elsewhere`（核"这 5 张真有门"）照旧绿。

## 五、验收证据

### 1. 零金标（证 Sim 读不到本片改动）
```
GODOT --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json
⇒ ✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条；烘于/本机同为 4.6.2-stable (official).71f334935）
  === S0 GATE: PASS ✅  (硬不变量 12/12 全绿, 软 ≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
`git status` 里 `game/bench/golden_digests.json` **未修改**（磁盘逐字节不动）——瓦是 View 资产、`SEASON_VEG` 是 View 常量，Sim 均读不到。

### 2. ★ SEASON 重量（本片头号风险，逐档量）
四季地面主色两两 ΔE00 最小值（`analysis/af2/assert_season.py`，晴天四季×昼夜，门阈 3.20；夜是约束档）：

| 树 | 昼 min ΔE00 | 夜 min ΔE00（春↔夏）| 判决 |
|---|---|---|---|
| **改前**（CC0 草 + 夏 veg 0.72,0.90,0.58）| 8.06 | **4.30** | PASS |
| 新瓦 + **旧**夏 veg（0.72,0.90,0.58）| 7.49 | **2.73** | ❌ FAIL（< 3.20）|
| 新瓦 + **新**夏 veg（0.60,0.82,0.46）| 8.21（春↔冬）| **4.28** | ✅ PASS |

病因：暖色基草把渲染出的春帧地面主色由 (134,179,63) 变暖变深到 (114,140,33)，夜里被昼夜乘子压掉 R/G（春夏差异所在）⇒ 春↔夏糊近。
修法：`SEASON_VEG["夏"]` 再压深一档（只动【夏】= 游戏日 15-29；所有 CI 视觉帧在春·游戏日 3 ⇒ 昼夜门那两帧不受夏改动影响）。
离线预测器（用实测主色线性外推、以旧值复现 2.73 校准）给 4.37，实测 4.28（夜/夏主色 (33,53,16)），恢复 ~1.34× 余量。春/秋/冬 veg 不动。

### 3. gate 表（全部实跑，docker `tol=0`）
| 门 | 结果 | 备注 |
|---|---|---|
| terrain_gate（hybrid）| ✅ PASS | 文件集合 13/13 · 来源自证 · SHORE teeth(water_e) · 8/8 岸线逐像素同 · 生成瓦 teeth(dirt) · 5/5 hash 同 |
| POND | ✅ PASS | distinct=55（旧纯色贴纸时靠岸线；新水心 63 色更稳）· path median 1.727/1.922 · 台阶 5/6 · **证 CC0 水完好** |
| SEASON | ✅ PASS | 夜 4.28 ≥ 3.20（见 §五.2）|
| DAYNIGHT / TREESTAND / space-roundtrip / INTSHELL / FURNROLE / PRECIP / cafe2f / floor-roundtrip | ✅ PASS | 新瓦重量后全绿（treestand 地面参考色现取空地格、自适应）|
| S0 金标 + 32 条不变量 | ✅ PASS | 12/12（§五.1）|
| asset_gate（2d）| ✅ PASS | `check_elsewhere` 仍核到这 5 张（LEGACY 未删）|

### 4. terrain_gate 负对照（隔离副本，逐条核过退出码）
| 变异 | rc | 判决行 |
|---|---|---|
| M0 未改动 | 0 | TERRAIN GATE PASS ✅ |
| M1 生成瓦 grass_a 翻 1 px | 1 | `grass_a 解码 RGBA sha256 与清单不符` |
| M2 删 water.png | 1 | `出货目录缺 1 张：water` |
| M3 常量 hash（未投毒清单）| 1 | 生成瓦 hash 与钉子不符 + teeth 前提不成立 |
| M3b 常量 hash **+ 连清单一起投毒** | 1 | **生成瓦 teeth：`翻 1 px 后 sha256 没变 ⇒ hash 判据是坏的`** ← teeth 独有的活 |
| （SHORE 半）岸线瓦翻 1 px | 1 | SHORE compare teeth 报 1px 指名（G5 原样保留）|

M3b 是关键：即便有人用退化的常量 hash **连清单一起重烘**（pin 也变常量、A-半 pin 比对被蒙过），**teeth 仍抓住它**——这正是 teeth 存在的理由。

## 六、诚实边界（不藏）
1. **hash-pin 就是 G5 当初点名要避开的"校验和清单"**：它"可靠更新清单蒙混"。对这 5 张生成瓦，没有 CC0 源可当第二份独立真相 ⇒ 主动接受这条弱点，唯一诚实的缓解是 §四的**眼验棘轮**（人跑 --rebless + 眼验 + 真机帧 + CI 永不自动重烘）。它**挡不住**"重烘时把偷改的瓦一起钉进去"——那层只有人眼守。
2. **丢了 G5 第 4 条自证**（切图坐标一致性）——见 §四，两份坐标表漂移不再有专门判据。
3. **冷蓝 CC0 池水配暖色地形**——为保 CC0 岸线键控（季节透草）+ 过 POND，接受色调不完全统一（§二）。
4. **只重画了 5 张**：stone/plaza 是程序化色（非瓦，不在射程）；farmland/sand/boardwalk 无消费者，给死资产上暖皮 = 把死资产钉成"正确"，不做。

## 七、媒体
- 整镇 before/after（docker `--shot-fit`，seed3 游戏日3 正午/夜）：`docs/media/av2/{before,after}_town_{day,night}.png`
- 5 张出货瓦 ×10 NEAREST 眼验预览：`docs/media/av2/tiles/*_x10.png`
