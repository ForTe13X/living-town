# 148 · AT1 · 视觉美术棒：镇上建筑外观往星露谷推（车道 V 第一片，零金标）

> 底稿 docs/146（视觉参考素材集）+ 用户 2026-08-07「town/building appearances 类星露谷」。R4 已 waive。
> owns：`game/scripts/WorldView.gd` 的**建筑外观外壳绘制**（`_draw_building_dressing` / `_draw_facades` / `_draw_sign` / `_draw_window` / `_draw_building` 房盒外壳 + 三个新 draw 辅助）+ 本文 + `docs/media/at1_*`。
> **没碰**：Sim.gd / Inv / golden_digests / gate_* / map.json / buildings.json / 任何 game/data/** / 室内绘制（AM 系 `_draw_interior*`）/ 户外街道·广场（AP 系）/ BLD_PAL 的**色值常量**。
> worktree `agent-a478a45b64a193023` · 分支 `worktree-agent-a478a45b64a193023` · ff 自 `integration/batons`@084aae9。

## 〇、一句话
把镇上建筑外观往参考的魅力推：坡屋顶（瓦纹 / 受光屋脊 / 山墙收头）、砖砌烟囱 +【确定性炊烟】、每类型雨棚/招牌加料、窗扇百叶 + 住宅花箱、**每栋按确定性变体分出辨识度**——全部只改 WorldView 的绘制，Sim 一格读不到 ⇒ **零金标（12/12 含 chain 逐字节相同）**。

## 一、先纠正两处协调者/参考的断言（实读发现，命门先量清）

**① 参考图与它的文档描述不符。** docs/146 §素材集把 `docs/media/references/ref_buildings_v1_stardew.png` 记作「11 栋建筑外观参考表（BAKERY/BLACKSMITH/…/MARKET STALLS）」。**实读那张 PNG：是 6 格中世纪风做旧道具**（板车 / 兵器架 / 酒桶堆 / 破木牌 / 干草垛 / 木框），暗底、厚涂、暖色高光的木质质感——**不是建筑外观表**，只有左下那格破木牌沾点"招牌"的边。故我取的是它**能给的**神韵（暖色做旧木质 + 手绘高光 + 磨损细节），适配到俯视网格；**没有**照它去抄"11 栋具名建筑"（那些在这张图里根本不存在）。→ docs/146 的这条描述应更正（另一张 `ref_terrain_v1_stardew.png` 未核）。

**② 「建筑外观」在这张地图上分两套画，不是一套。** 协调者点了 `_draw_building`（约 3683）+ `_draw_building_dressing`（约 1204）。实读复核：
- `map.json` 的 **`areas`（9 个区）**——`_wall_set` 逐格墙按 `_wall_type`→BLD_PAL 上色，再压 `_draw_facades`（窗+烟囱）与 `_draw_building_dressing`（屋檐+招牌）。**这是"建筑外壳"的主体**（区级围墙 + 屋顶 + 招牌）。
- `map.json` 的 **`rooms` = 空（0 条）**；`_draw_building`（3777）迭代的 `Sim.world["rooms"]` 是**运行期从 `buildings.json` 灌进来的 12 间房**（Sim.gd:597-654），画成嵌在区里的小房盒（各自墙/地/家具/门/窗/灯）。
- ⇒ 两套都改了：区级 dressing/facades（主视觉）+ 房盒 `_draw_building` 的屋脊暖盖（轻触，求辨识度与统一）。

**③ 红旗#2 的"建筑类型门"是【室内】门，不是外景门。** `assert_interior_shell`（INTSHELL）采样的是 **`vg_int_<space>.png` 室内帧的室内墙**（走 `_draw_interior`，AM 系），量墙主面众数判四类可分。**外景（本棒动的这一层）没有任何一道类型可分门**。⇒ 我的新屋顶/招牌**结构上碰不到** INTSHELL 的采样面。已实跑核对：INTSHELL 改后 7 栋/4 类全绿、异类最小 ΔE 17.72（见 §四）。

## 二、现状清点（改前，实读行号）
| 面 | 位置 | 改前画法 |
|---|---|---|
| BLD_PAL（四类墙+屋顶色常量） | `WorldView.gd:473` | 住宅暖木/红瓦 · 商业棕店面/红白遮阳 · 公共灰蓝石/蓝瓦 · 工坊暖灰石/深蓝灰顶 |
| 区级屋檐+招牌 | `_draw_building_dressing`（旧 1204） | **平色屋檐带**（roof 色）+ 一条脊线高光；商业=红白条纹遮阳；招牌走 `_draw_sign`（咖啡杯/♨/烟囱图标/山墙剪影） |
| 区级开窗+烟囱 | `_draw_facades`（旧 1245） | 等距开窗（夜透暖光）；住宅/工坊一根**静态**烟囱 + 两团不动的灰圆 |
| 房盒（12 间） | `_draw_building`（旧 3683） | 落地影+三段外墙+受光高光+室内地板+陈设+南门+北窗+占用灯火 |

## 三、改了什么（diff：`WorldView.gd` +130 −30，单文件）
新增确定性辅助（纯 `_hash`/`Sim.tick_no`，禁 randi/Time）：
- `_bld_variant(x0,y0)`（1208）= `_hash(x0,y0,91)%3`：每栋外观变体 0/1/2（纯 f(左上角格)）。
- `_roof_variant(base,v)`（1212）：屋顶色按变体做小幅 HSV 偏移（旧瓦沉/新瓦亮），**留在类型色系**——红瓦仍读红瓦。**墙主面 BLD_PAL[typ]["face/top/foot"] 一个字不碰**（那是"四类一眼可分"的锚）。
- `_draw_pitched_roof(rect,roof)`（1221）：屋檐带 → 两行错缝瓦（逐片 `_hash` 定明暗）+ 受光屋脊 + 檐口投影 + 两端山墙暗角收头 ⇒「屋顶质感（山墙/瓦纹/受光）」。
- `_draw_awning(eave,pal,bw)`（1244）：商业遮阳篷 = 红白条纹（类型信号）+ 顶棱高光 + **扇贝檐边（valance）**。
- `_draw_chimney(bx,by,x0,y0)`（1344）：砖砌烟囱（帽檐+砖缝）+ **确定性炊烟**——三团沿一个上升周期错相循环，位置/半径/透明度由 `_hash(x0,y0,71)` 定相位 + `Sim.tick_no` 推进（起淡·中浓·顶淡，侧漂）。

改写：
- `_draw_building_dressing`（1256）：按 `_bld_variant` 选屋顶色；非商业走坡屋顶；商业= 坡脊 + 扇贝遮阳篷。
- `_draw_sign`（1275）：商业=悬挑吊牌+咖啡杯；公共=吊牌框+♨蓝盘蒸汽；**工坊=铁砧+锤**（比"烟囱图标"更认得出，真烟囱另在 facades 上）；住宅=受光山墙门牌+暖门+烟囱。
- `_draw_window`（1370，加 `flower` 参）：两侧百叶窗扇（带一道亮竖缝）+ 住宅约半数窗挂**窗台花箱**（木槽+三簇花，确定性子集）。
- `_draw_facades` 烟囱段：改调 `_draw_chimney`。
- `_draw_building`（3777）：房盒顶墙压一条**按房号确定性选档的木瓦脊暖盖**（暖木三档，冷色房盒压上也不跳色）+ 南门木过梁。

## 四、验收证据

### 1. 零金标三证据（含 chain）— 证 Sim 读不到本棒改动
`godot --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json`
```
— 金标（跨进程锚）—
  ✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条；烘于 4.6.2-stable...，本机 4.6.2-stable...）
— 确定性 —
  ✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链)  3/3
=== S0 GATE: PASS ✅  (硬不变量 seed 12/12 全绿, 软≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
⇒ **digest / event_digest / 逐 tick 前缀链 12/12 全逐字节相同**。chain 未动 = 没碰 Sim 读的面。seed 摘要留档见 s0.log（seed1 chain=2804499186 digest=1487044413 … 与金标锚一致）。

### 2. 既有视觉门不回归（`bash tools/visual_gate.sh`，runner=docker，tol=0，exit 0）
| 门 | 结果 |
|---|---|
| DAYNIGHT | PASS（夜帧 world_mode=(57,82,63)=expect，dmax=0）— 地面众数不受建筑改动影响，昼夜比值成立 |
| ROUNDTRIP | PASS — **A[map] 变化像素 0/366800 = 0.000%**：town_before≡town_after 逐像素相同 ⇒ 炊烟每 tick 确定、往返冻结帧不抖 |
| POND（岸线） | PASS |
| **INTSHELL（室内壳类型门）** | **PASS**：7 栋/4 类，异类最小 ΔE 17.72≥8.0、同类 0.00≤4.0（工坊墙 #44423e / 公共 #556169 / 住宅 #886d49·#836a48 / 商业 #5a4028——本棒没碰室内墙） |
| FURNROLE（家具语义） | PASS（6 栋/5 类，异类最小 ΔE 29.19≥12.0） |
| TREESTAND（林相点阵） | PASS（昼 P≈27 / 夜 P≈13，地面色占比≤9.4%）— 炊烟不落在林块采样格 |
| SEASON（四季可分） | PASS（昼最小 ΔE00 8.06、夜 4.30，≥阈 3.20）— 地面主色不受建筑改动影响 |
| PRECIP（降水可见） | PASS（雪 coverage≥1154、雨≥1458） |
| CAFE2F | PASS（非空 0.129、与1F可分 0.230） |
| FLOOR-ROUNDTRIP | PASS |

⚠️ 特别核对 INTSHELL 类型可分（红旗#2）：**未误红**，四类墙主面众数与改前同（我没动 `_draw_interior`）。

### 3. 对照图（`docs/media/at1_*`，真引擎 docker 渲染 seed3）
- `at1_town_before.png` / `at1_town_after.png`：整镇 --shot-fit（正午·春·阴）。
- `at1_buildings_before_after.png`：四类型逐栋 before|after（3×）。眼验：
  - 住宅：坡屋顶受光屋脊 + 山墙暗角；屋顶按栋分档（home2 沉红 / home 亮红）；砖烟囱升炊烟；窗扇百叶 + 花箱红花。
  - 商业：遮阳篷加**扇贝檐边**+顶棱高光，读作真店铺雨棚。
  - 公共/工坊：坡脊+山墙收头；工坊招牌改**铁砧+锤**。
  - **四类型仍一眼可分**（墙主面色未动 + 屋顶留在类型色系）。
- `at1_night_before_after.png`：夜帧——炊烟（被夜蓝乘过成暗团）+ 点灯的百叶窗。

与参考神韵对照：参考是暗底做旧道具（见 §一①），取其"暖木质感 + 手绘高光 + 磨损细节"——落到砖烟囱/木瓦脊/木吊牌/百叶窗扇这些暖木元件上，适配严格俯视 T 格，未抄其 3/4 微俯角透视。

### 4. `bash tools/ci.sh` 判决行
```
  ✅ 视觉门（昼夜 / 界外层重画 / 空间往返 / 岸线 / 室内外壳 / 家具语义 / 树丛点阵 / 季节 / 降水）
=== CI PASS ✅ ===
CI_EXIT=0
```
0-6 全步全绿（含 4b LOD 观察无关 / 4c DetGate / 4d BackendGate / 4f VoiceGate / 4g #43 / 4h state_projection / goals_test / story_test / 第 6 步 docker 视觉门 tol=0）。提交前互补性守卫按纪律不算数，协调者 committed 树重烘重跑。

## 五、红旗自查
1. **只改 draw**：building bounds/pos/nav/blocked/advertises 与 map.json/buildings.json 一格没碰；BLD_PAL 色值常量没动（只在 draw 时按变体派生屋顶色）。零金标 §四.1 已证。
2. **INTSHELL 类型可分**：未误红（§四.2）；新装饰不在室内墙采样面上（外景 vs 室内两套画法）。
3. **没碰室内（AM）/街道广场（AP）**：`_draw_interior*` / plaza·dock（dressing 里 `typ=="plaza"` continue）未动。
4. **确定性**：炊烟/瓦纹/花箱全走 `_hash`+`Sim.tick_no`，禁 randi/Time ⇒ ROUNDTRIP A[map]=0.000% 逐像素复现为证。
5. **lod_verify**：纯 draw，不读相机回喂 Sim。
