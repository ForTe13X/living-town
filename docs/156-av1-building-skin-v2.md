# 156 · AV1 · 建筑外皮 v2：往星露谷参考再推一档（车道 V 第二片，零金标）

> 底稿 docs/148（AT1 建筑外皮 v1）+ docs/146（视觉参考素材集）+ 用户「town/building appearances 类星露谷」。
> **严格照 AT1 模板（docs/148）**——同一套「只改 WorldView 绘制 ⇒ Sim 一格读不到 ⇒ 零金标」的零金标视觉纪律。
> owns：`game/scripts/WorldView.gd` 的**建筑外壳绘制辅助**（AT1 那批：`_draw_building_dressing` / `_draw_facades` / `_draw_sign` / `_draw_pitched_roof` / `_draw_awning` / `_bld_variant` / `_roof_variant`）+ 两个新 draw 辅助（`_draw_corner_posts` / `_draw_foundation`）+ 一个新色档辅助（`_trim_wood`）+ 本文 + `docs/media/av1_*`。
> **没碰**：Sim.gd / Inv / golden_digests / gate_* / map.json / buildings.json / 任何 game/data/** / 室内绘制（AM 系 `_draw_interior*`）/ 户外街道·广场（AP 系 `_build_paths`/cobblestone）/ `BLD_PAL` 的**色值常量** / terrain PNG。
> worktree `agent-a2924464bd8676ce5` · 分支 `worktree-agent-a2924464bd8676ce5` · ff 自 `integration/batons`@ec0a4c3（AT1 已 land 在这条线上）。

## 〇、一句话
在 AT1 的坡屋顶/炊烟/雨棚/招牌之上再加一档参考魅力：**木构角框**（左右竖角板 + 四角木块，把大片平板墙面读成"木构建筑"）+ **错缝石基**（建筑坐在石头地基上而非浮在草上）+ **更立体的瓦屋顶**（三行叠瓦逐片带底影 + 木脊梁盖 + 受光/背光两端山墙）+ **每栋分色的条纹雨棚**（红/蓝/暖金，两家商业一眼分得开，对齐参考集市三顶）+ **门头提灯**（夜里点亮）——全部只改 WorldView 绘制、纯 `_hash`/`Sim.tick_no` 派生，Sim 一格读不到 ⇒ **零金标（12/12 含逐 tick 前缀链逐字节相同）**。

## 一、先纠正 docs/148 §一① 的过期断言（AV1 命门先量清）
AT1 的 docs/148 §一① 写「`ref_buildings_v1_stardew.png` 实读是 6 格中世纪风做旧道具，不是建筑外观表」。**那条今天过期了**，已在 docs/148 §一① 就地加 2026-08-08 订正：那段描述的是**当时存错的文件**（docs/146 记着首次提交抓成了别项目 Jianghu 的图，后用页内 JS `fetch(img.src)` 取回真图替换）。**今天树上的 `ref_buildings_v1_stardew.png` 是 docs/146 记的那张真·11 栋建筑外观表**（BAKERY CAFÉ / BLACKSMITH / GENERAL STORE / LIBRARY / BATHHOUSE / COTTAGE / TRAIN STATION / HARBOR DOCK / WAREHOUSE / WATERMILL / MARKET STALLS，暖色统一像素、3/4 微俯角）。AV1 实读了这张真图，取它**真正给得出的**神韵：**瓦屋顶质感 + 深木构件（角柱/雨棚支柱/脊梁）+ 石砌地基 + 条纹布棚（三色）+ 门头提灯 + 每栋辨识度**，适配到本镇严格俯视 T 格（T=48）；**未**抄它的 3/4 微俯角透视（本镇是切顶正俯视）。docs/146 §素材集那行原本就是对的——错的是 docs/148 §一① 读到了过期文件。

## 二、AT1 模板复用（docs/148 是被证明的零金标图案，AV1 一比一沿用）
| AT1 纪律（docs/148） | AV1 如何沿用 |
|---|---|
| 只改 WorldView 绘制辅助，Sim 读不到 ⇒ 零金标 | AV1 全部改动落在 AT1 那批辅助 + 2 个新 draw 辅助；无一处碰 Sim 读的面。§四.1 金标 12/12 逐字节相同为证。 |
| 确定性：只用 `_hash(x,y,salt)` + `Sim.tick_no`，禁 randi/randf/Time/OS | 角柱木色 `_hash(x0,y0,93)%4`、雨棚色 `_bld_variant=_hash(x0,y0,91)%3`、瓦片明暗 `_hash(列,行,61)%3`、提灯昼夜 `Sim.time_of_day()`——全确定性。ROUNDTRIP A[map] 逐像素相同为证。 |
| 不碰 `BLD_PAL` 的 face/top/foot 色值常量（四类一眼可分的锚） | AV1 一个字没改 `BLD_PAL`；新色**全部**由已授权常量派生（`X_WOOD_MID`/`P_STONE`/`P_COM_FOOT`/`P_PUB_ROOF`/`X_GLOW*`/`P_TEXT`/`D_WOOD_LINE`），**无一个新 `Color("#...")` 字面量**（守 WorldView.gd 抬头那条纪律）。 |
| 外景与室内是两套画法；室内壳门（INTSHELL）采样室内墙、走 `_draw_interior` | AV1 只改**外景**（town 绘制路径）。`_draw_body` 在 probe 非-town 空间时于 early-return 前只画 `_draw_interior_backdrop`（WorldView.gd:3008-3011），**外景 dressing/facades 结构上进不了室内帧** ⇒ INTSHELL/FURNROLE/CAFE2F/FLOOR-ROUNDTRIP 结构上不受影响。 |
| 每栋按确定性变体分辨识度（`_bld_variant`/`_roof_variant`） | AV1 复用它，再加 `_trim_wood`（木构件做旧/新木档）与雨棚分色 ⇒ 辨识度从"屋顶色"扩到"木框 + 布棚"。 |

## 三、改了什么（`WorldView.gd`，单文件）
新增确定性辅助（纯派生色，无字面量）：
- `_trim_wood(v)`（`_roof_variant` 之后）：木构件按变体挑一档做旧/新木色，全由 `X_WOOD_MID`/`P_COM_FOOT` 派生，留在暖木一族。
- `_draw_corner_posts(x0,y0,bw,bh,wood)`：**木构角框**——左右两条竖角板（薄，贴最外缘 ⇒ 避开内缩≥0.10T 的窗扇，从檐下一路连到石脚）+ 四角加宽木块（角格永不开窗，可宽）+ 底排石柱脚（`P_STONE`/`P_STONE_LINE`）。
- `_draw_foundation(x0,y0,bw,bh)`：**错缝石基**——底墙那一行最下 ~T*0.26 压一条石砌带（皮数线 + 错缝砌块缝），留在建筑轮廓内（窗洞之下、门槛之上 ⇒ 不碰地面/岸线/林块采样格）。

改写：
- `_draw_pitched_roof(rect,roof)`：两行瓦 → **三行错缝瓦（逐片带底影，读作一层压一层的叠瓦）**+ **木脊梁盖**（`P_COM_FOOT` 深木盖 + 梁下沿高光，比旧版单条高光更像真屋脊）+ **受光/背光两端山墙**（旧版两端同暗 → 左端受光/右端背光，与墙面顶棱/左棱高光同一套光向，读出坡屋顶两个斜面）。
- `_draw_awning(eave,pal,bw,v)`（加 `v` 参）：条纹深色**按建筑变体挑**（v0 红 / v1 蓝 `P_PUB_ROOF` / v2 暖金 `X_GLOW_DEEP.darkened`），亮条恒为奶白 `P_TEXT` ⇒ 咖啡馆(v2 暖金)与杂货铺(v1 蓝)一眼分得开（对齐参考集市三顶不同色布棚）；再加**两端木支柱**（把布棚支起来，参考里每顶集市棚都有）。
- `_draw_sign(typ,pal,cx,cy,night)`（加 `night` 参）：招牌两侧各挂一盏**檐下提灯**（夜里点亮暖光晕、白天熄灯的铜灯；灯芯色由 `X_GLOW*` 派生）。四类型招牌图标（咖啡杯/♨/铁砧锤/山墙门牌）原样保留。
- `_draw_building_dressing(w)`：现算昼夜（`Sim.time_of_day()`）；每栋先压**石基 + 四角木框**（读作木构坐在石基上），再压屋顶（画在角柱之后 ⇒ 屋顶盖住柱头 = 屋顶坐在柱上），最后挂招牌 + 提灯；木框色 `_trim_wood(_hash(x0,y0,93)%4)`、雨棚色随 `_bld_variant`。

**未改** AT1 的 `_draw_building` 房盒屋脊（3790）——那一档轻触室内房盒、离 AM 系近，AV1 不动它以缩小面。

## 四、验收证据

### 1. 零金标三证据（含 chain）— 证 Sim 读不到本片改动
`godot --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json`
```
— 金标（跨进程锚）—
  ✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条；烘于 godot 4.6.2-stable.71f334935，本机同版本）
— 确定性 —
  ✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链)  3/3
=== S0 GATE: PASS ✅  (硬不变量 seed 12/12 全绿, 软≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
⇒ **digest / event_digest / 逐 tick 前缀链 12/12 全逐字节相同**（seed1 chain=2804499186 digest=1487044413 … 与金标锚一致，同 AT1）。chain 未动 = 没碰 Sim 读的面。硬不变量 #01–#14/#16–#19 全 12/12。

### 2. 既有视觉门不回归（`tools/ci.sh` 第 6 步，runner=docker，镜像钉死 mesa ⇒ tol=0，全绿）
| 门 | 结果（本片实测，seed3） |
|---|---|
| DAYNIGHT | PASS — 夜帧 world_mode=(57,82,63)=expect，dmax=0（地面众数不受建筑改动影响） |
| ROUNDTRIP | PASS — **A[map] 变化像素 0/366800 = 0.000%、最大通道差=0**：town_before≡town_after 逐像素相同 ⇒ 提灯/木框每 tick 确定、冻结帧不抖 |
| POND（岸线） | PASS |
| **INTSHELL（室内壳类型门）** | **PASS**：7 栋/4 类，异类最小 ΔE 15.43（library↔work）≥8.0、同类最大 ΔE 1.98（home↔home2）≤4.0（墙主面众数与改前同——本片没碰室内墙） |
| FURNROLE（家具语义） | PASS（6 栋/5 类，异类最小 ΔE ≥12.0） |
| TREESTAND（林相点阵） | PASS（昼 P≈27.4 / 夜 P≈13.8，地面色占比≤9.4%）——木框/石基不落在林块采样格 |
| SEASON（四季可分） | PASS（昼最小 ΔE00 8.06、夜 4.30，≥阈 3.20）——地面主色不受建筑改动影响 |
| PRECIP（降水可见） | PASS（冬雪/非冬雨 on/off × 3 seed 全过） |
| CAFE2F | PASS（非空 0.129≥0.060、与1F可分 0.230≥0.100、色数落差 18≥8） |
| FLOOR-ROUNDTRIP | PASS |

⚠️ 结构性论据（比逐帧读数更强）：AV1 只改**外景 town 绘制路径**；`_draw_body`（WorldView.gd:3008-3011）在 probe 非-town 空间时 early-return 前只画室内 backdrop，**外景 dressing/facades 进不了室内帧** ⇒ INTSHELL/FURNROLE/CAFE2F/FLOOR-ROUNDTRIP **结构上**看不到本片改动。外景各门（DAYNIGHT/POND/TREESTAND/SEASON/PRECIP/ROUNDTRIP）采样的是地面/水/林块众数色，而 AV1 的新绘制**全部留在建筑轮廓内**（角柱在墙格、石基在底墙行、木框贴最外缘不越格、屋顶沿用 AT1 既有悬挑包络）⇒ 不落在任何地面/岸线/林块采样格。

### 3. 对照图（`docs/media/av1_*`，真引擎 docker 渲染 seed3、正午·春·阴、2560×1536 --shot-fit）
- `av1_town_before.png` / `av1_town_after.png`：整镇 before/after。
- `av1_buildings_before_after.png`：四类型逐栋 before|after（2×放大）。眼验：
  - **住宅（住宅区）**：左右竖木角框 + 四角木块 + 底排石柱脚；三行叠瓦 + 木脊梁盖；招牌两侧挂提灯 + 山墙门牌；窗扇百叶 + 花箱（AT1 保留）。
  - **商业（咖啡馆）**：雨棚由红白 → **奶白+暖金**（v2），加两端木支柱；木角框 + 石基。
  - **公共（澡堂）/ 工坊（工坊）**：木角框（深木压冷灰墙对比低但可见）+ 石基 + 石柱脚更明显；蓝/深顶三行叠瓦 + 脊梁。
  - **四类型仍一眼可分**（`BLD_PAL` 墙主面色未动 + 屋顶留在类型色系 + 木框/石基是叠加不改类型信号）。
- `av1_night_before_after.png`（住宅/商业逐栋 before|after）+ `av1_town_night_after.png`（整镇夜帧）：夜帧——门头提灯点亮的暖光晕 + 点灯的百叶窗（AT1 保留），角框/石基被夜蓝乘暗成暗木/暗石。

与参考神韵对照：参考 11 栋的共同语言是**深木构件把瓦屋顶撑在石基上 + 条纹布棚 + 门口提灯**，AV1 把这几样落到俯视 T 格的角柱/脊梁/石基/分色雨棚/提灯上；参考的 3/4 微俯角透视本镇不采（切顶正俯视）。

### 4. `bash tools/ci.sh` 判决
```
  ✅ 视觉门（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳 / 家具语义 / 树丛点阵 / 季节 / 降水）
=== CI PASS ✅ ===
CI_EXIT=0
```
0–6 全步全绿：红线#4 / data lint / map audit / **link lint** / art·terrain·asset·可重算·互补性守卫门 / import·parse / 第 4 步 S0 金标（12/12 含 chain，det 3/3）/ 4a 宏观池 / 4b LOD 观察无关 / 4c DetGate / 4d BackendGate / 4e ModelPathGate / 4f VoiceGate / 4g #43 / 4h state_projection / 第 5 步 unit·integration scenes / 第 6 步 docker 视觉门 tol=0（上表 10 道全绿）。
> ⚠️ 过程记录：本片第一次跑 CI 时 **link lint 假红一次**——因为当时 docs/156 还没落盘（我在 CI 跑起来之后才写它），而 docs/148 已经引了「见 docs/156」。docs/156 落盘后重跑，link lint OK（182 份 md、150 篇编号文档全部 resolve），全 CI PASS。提交前互补性守卫按纪律不算数，协调者在 committed 树重烘重跑。

## 五、红旗自查
1. **只改 draw**：building bounds/pos/nav/blocked/advertises 与 map.json/buildings.json 一格没碰；`BLD_PAL` 色值常量没动（只在 draw 时按变体派生木/瓦/雨棚色）。零金标 §四.1 已证。
2. **无新字面量**：新色全部由已授权 `P_*`/`X_*`/`D_*` 常量派生，守 WorldView.gd 抬头「不许再出现新 `Color("#...")`」纪律（实测 owned 区 0 命中）。
3. **INTSHELL 类型可分 / 室内各门**：结构上进不了室内帧（§四.2）；未误红。
4. **没碰室内（AM）/街道广场（AP）/terrain**：`_draw_interior*` / plaza·dock（dressing 里 `typ=="plaza"` continue）/ `assets/art/terrain/` 未动。
5. **确定性**：角框/石基/瓦纹/雨棚/提灯全走 `_hash`+`Sim.time_of_day()`，禁 randi/Time ⇒ ROUNDTRIP A[map] 逐像素复现为证。
6. **off-gate 状态**：外景无任何"类型可分"门（docs/148 §一③ 已量清——外景那层从来没有类型门），故 AV1 的外观加料**没有一道现成门能自证它"变好看了"**；这是视觉片的固有边界，只能靠 §四.3 的真引擎对照图眼验，不靠机检。既有 10 道视觉门守的是"没变坏"（回归），不是"变好看"（改进）。
7. **诚实边界**：
   - 公共/工坊墙是冷灰蓝，深木角框压上去**对比偏低**（不如住宅/商业醒目）——这是"暖木元件 vs 冷墙"的固有对比问题，AV1 没有为它调墙色（那是 `BLD_PAL` 锚，出界）。
   - 俯视切顶下"屋顶"只是顶墙那条悬挑带，无法像参考那样占据大半立面的坡屋顶——这是本镇"能看见室内"的设计约束，AV1 在带内加料到顶，未扩带（扩带会遮室内家具）。
   - AV1 未做参考里的 5 类新经济建筑（车站/码头/仓库/水磨坊/集市）造型——那是造型 + 数据（map.json/buildings.json），属车道 E 机制片，不在本视觉片零金标范围内。
