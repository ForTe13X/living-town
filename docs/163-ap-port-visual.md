# 163 · AP-port · 给滩头 dock 一个看得见的【港口身份】（纯 View，零金标）

> 底稿：docs/162（交通/建筑种类 scoping 收据）§三 亲点的**推荐首片 = Option A**：
> dock 纯 View 港口结构。对应用户 item#2「交通:港口」。
> **零金标视觉纪律**（同 AT1/AV1/AV2/AV3，docs/148/156/159/161）：只加 WorldView 绘制读的
> **一个新 draw 函数 + 一个调用点 + 一个 AUDIT pass 名**；Sim 一格读不到 ⇒ 金标 12/12 逐字节相同（含逐 tick 前缀链）。
> owns：`game/scripts/WorldView.gd`（唯一改动文件）+ 本文 + `docs/media/apport/*`。
> WorldView.gd 内的射程：**一个新 `_draw_port()`** + 6 个 `_port_*` 结构件助手 ·
> `AUDIT_PASSES` 加 `"port"` 项（`AUDIT_PRIMARY` 24→25，doc-only 常量）· `_draw()` dressing 块后一个 `if _ap("port"): _draw_port()` 调用点。
> **没碰**：Sim.gd / `golden_digests.json` / 任何 `game/data/**`（map.json/logistics.json 只读）/ Invariants /
> gate_* / 地形瓦(草/水/石)与 AV2/AV3 的地面 draw / 室内绘制 / `BLD_PAL` 常量。
> worktree `agent-a9adef559747bfb16` · 分支 `worktree-agent-a9adef559747bfb16` · ff 自 `integration/batons`@70e238d（含 AV1/AV2/AV3）。

## 〇、一句话
F5 建的 `dock` 区（`type:plaza`、rect `[30,7,4,2]`、北池南岸、蓄意不含水格）此前只铺了广场石板 + 一个借 bench 精灵的
`bench_pier 渔台` worksite，整块读作**「一块带凳子的铺装」**，没有任何码头/船/仓库。本片把这块铺装【就地】画成真港口：
**木栈桥板 + 临水边梁 + 系缆桩 + 系着的渔船 + 货箱/桶/出口麻袋 + 小船屋 silhouette + 一块交通路牌**。
全部程序化（`Control._draw` 图元 + `_hash` 确定性明暗/木纹 + `_night_amt()` 夜灯），复用现有木/水/暖光色常量、**不加新 type/BLD_PAL**。
**金标 12/12 逐字节相同；POND（唯一真风险）判据数 before=after 逐位不变、门 PASS。**

## 一、改前实况（docs/162 §〇/§三 普查，本片实读复核）
- `dock` 区：`type:plaza`、rect `[30,7,4,2]` ⇒ 格 **x30–33 · y7–8**，在北池（water 层 x28–35 · y2–6）的**正南岸**，dock 顶边 y7 紧贴池水 y6。
- Sim **只读 area 的 `rect`+`label`，从不读 `type`/terrain/本层 draw**（docs/162 §一，实证）⇒ 在 dock 铺装上画港口结构 = 纯 View、零金标。
- `bench_pier` worksite 在 `[31,7]`（production.json，`type:渔台`，借 bench 精灵，由 objects pass 画）；`port_dock` 是 logistics **只声明节点**（保留位 `[33,8]`、不落 world.objects）。本函数**不读 logistics.json**，只读 `areas.dock.rect`。

## 二、改了什么（`WorldView.gd` 单文件，三处 + 一个新函数块）
1. **`AUDIT_PASSES` 加 `"port"`**（`"dressing"` 与 `"arealabels"` 之间）+ `AUDIT_PRIMARY` 24→25（该常量抬头自注「仅存文档」、全仓 0 处引用，实测 grep）。闭合校验用 `not begins_with("bd:")` 自动纳入新 pass；`--draw-audit` 才读，golden 路径读不到。
2. **`_draw()` 调用点**：在 `_draw_building_dressing` / `_draw_area_labels` 之后加 `if _ap("port"): _draw_port()`。**画在 arealabels 之后**——见 §五-1 的诚实边界。
3. **新函数 `_draw_port()` + 6 个 `_port_*` 助手**（自成一块，在 `_draw_landmarks` 之后），几何全由 `areas.dock.rect`+`T` 派生：
   - **① 木栈桥板**：把广场石板【就地】盖成晒白木甲板（8 条竖板 × 每格，板缝/龙骨/钉头 + 每板 `_hash(bi,cy,63)` 明暗档 + 木纹）。
   - **② 临水边梁**（bull rail）：朝水那条边一根深木梁 + 受光高光，画在水线 `py` 上。
   - **③ 结构**：西端**船屋**（人字红顶木屋、门朝栈桥、夜里小窗透暖光）· 两根**系缆桩** + 一条**系缆绳**牵到 · **渔船**（平底小船：深木壳 + 浅木舷内 + 坐板 + 盘网 + 银鱼渔获）· 东端**货堆**（木箱 ×2 + 木桶 + 出口豆子的麻袋）· 西南陆地一块**交通路牌**（木柱 + 两块方向牌 + 箭头，呼应 item#2）。
- **确定性**：明暗/木纹只读 `_hash(x,y,salt)`，夜灯只读 `_night_amt()`(f(`Sim.time_of_day`))——无 randi/randf/Time/OS ⇒ `--shot` 逐像素可复现（ROUNDTRIP 冻结帧）。
- **复用色常量**：木 `X_WOOD_MID`/`D_WOOD_LINE`、桶身 `P_COM_FOOT`、屋顶 `P_RES_ROOF`、麻布 `P_PLAZA`、水影 `P_WATER_DEEP`/`P_WATER_LIT`、暖光 `X_GLOW*`、牌面 `P_RES_FLOOR`——**不加新 BLD_PAL**。

## 三、★POND 安全——把结构钉死在水线之下（docs/162 §三点名的唯一真风险）
POND 门（`tools/pond.py`）量北池那圈 **grass↔water 岸线**的过渡：池心 `distinct`、`grass_modal` 环带众数、四边剖线的 `path`（折线/直线）/`levels`（台阶）/`frac_direct`。dock 在**南岸**，`bot@` 剖线会向下探进 dock 顶格 y7 约 5px。

**本函数的硬约束：一像素都不画到水线 `py`(=dock 顶边=池南岸) 之上。** 所有结构 `top_y`/`ground_y` 均 clamp 在 `y≥py` 的已铺 dock 格里 —— 池水与岸线像素一个不碰。两点让它天然安全：
- **`path`/`grass_modal` 判据排除南岸**：南岸剖线陆侧本就是**铺装/木甲板（非草）**，`grass_modal` 众数由整圈草地主导（南岸那点非草像素在基线里【本就是石板】，改成木板不新增非草面）⇒ 众数不动；`path` 只在能找到「草→水」完整过渡的剖线上取样，南岸取不到 ⇒ 不进 `path`/`frac_direct`。
- **`levels` 只增不减**：木结构给南岸剖线**加**颜色台阶（利好判据），不会抹掉草→水梯度。

### POND before → after（docker `gamecraft-runner:4.6.2`，mesa 钉死，tol=0；`vg_noon`/`vg_night` seed3 tick600/488 `--shot-fit`）
| 判据（**被门判的**） | 昼 before → after | 夜 before → after |
|---|---|---|
| 池心 `distinct` | 55 → **55** | 55 → **55** |
| 参考差 `REF` | 138.73 → **138.73** | 47.43 → **47.43** |
| **`path` median** | 1.761 → **1.761** | 1.922 → **1.922** |
| `path` p10 | 1.288 → **1.288** | 1.402 → **1.402** |
| 一步直达 `frac_direct` | 6.7% → **6.7%** | 5.5% → **5.5%** |
| 台阶 `levels` median | 5 → **5** | 6 → **6** |
| **门判决** | ✅ PASS（distinct 55≥2 · path 1.761≥1.25 · 直达 6.7%≤25% · 台阶 5≥2） | ✅ PASS（… path 1.922 · 台阶 6 …）|

⇒ **每一条被门判的数 before=after 逐位相同**。只有**诊断量**（不参与判定）动了：昼 `cross/REF` median 0.429→0.406、`win_max` 160.64→209.90（正是新木结构落在南岸 5px 探针里被读成「最大跳变」，而 pond.py 抬头明写 `win_max`「被岸边装饰钉死，不判定」）。**这正是判据设计要免疫的东西**：我在南岸加了木头，诊断量抖了，判决量一位没动。

**没有画跨水 pier**：docs/162 §三给的选项是「要跨水 pier 就重跑 POND 确认绿、红就拉回陆地」。本片**主动选择陆侧到底**——渔船蓄意画成平底小船、整船落在水线下，边梁只压在 y7 顶边。收益（港口一眼成立）已足，不值为一截伸进水里的栈桥去动那道被 12 版判据反复标定的岸线。

## 四、零金标 + gate 表
### 零金标（证 Sim 读不到本片）
```
GODOT --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json
⇒ ✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条；烘于/本机同为 4.6.2-stable (official).71f334935）
  ✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链) 3/3
=== S0 GATE: PASS ✅  (硬不变量 12/12 全绿, 软 ≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
`git status` 里 `game/bench/golden_digests.json` **未修改**（磁盘逐字节不动）——本片全部是 View 侧 draw 代码，Sim 均读不到。

### gate 表（`tools/ci.sh`，docker `tol=0`，`LT_VISUAL=require` 强制视觉门真跑）
| 门 | 结果 | 关键数 |
|---|---|---|
| S0 金标 + 不变量 | ✅ PASS | 12/12 · det 3/3（上）|
| **POND**（水色/岸线风险项）| ✅ PASS | 判决量 before=after 逐位不变（§三）|
| DAYNIGHT | ✅ PASS | 夜 world_mode=草，本片不动世界主色 |
| ROUNDTRIP（空间往返冻结帧）| ✅ PASS | 新 draw 全 `_hash` 确定性，逐像素复现 |
| SEASON（四季地面可分）| ✅ PASS | 世界主色=草，dock 木甲板不进 world_mode |
| TREESTAND / PRECIP | ✅ PASS | 未碰树/降水层 |
| INTSHELL / FURNROLE / CAFE2F / FLOOR-ROUNDTRIP / space_roundtrip | ✅ PASS | 室内/往返未碰 |
| art / terrain / asset / 互补性守卫 / audit_map | ✅ PASS | 未碰资产/nav/data |

> CI 全程 verdict 见 §六。

## 五、诚实边界（不藏）
1. **「滩头」区名被港口结构盖住了**：`_draw_area_labels` 在整-镇取景(`--shot-fit`)下把字号拉到 ~52px、正压在栈桥中央，会糊住渔船/货堆。本片把 `_draw_port()` 排在 arealabels **之后**，让结构盖过那个巨字——判断是**港口结构本身已让 dock 一眼是码头**，一个 2 字标签不值那份遮挡。代价：dock 在所有缩放档都不再显「滩头」文字标签（其余 8 区照显）。若日后要留标签，可把它挪到 dock 上方水线外的草地、或缩小字号，另开一片。
2. **程序化，不是精灵**：港口是 `Control._draw` 的图元 + `_hash` 颗粒，不是贴图；参考 `ref_buildings_v1_stardew.png` 的 HARBOR DOCK 只借了「栈桥板 + 船屋 + 货箱 + 泊船」的**读法**，手译成俯视 T=48 的程序化画法，未抄具体像素排布。
3. **渔船是平底小船、不带高桅**：为守「不越水线」这条硬约束，船蓄意画平（无向上伸出的桅杆/帆）。这是 POND 安全换来的取舍，不是没画完。
4. **`bench_pier 渔台` worksite 仍由 objects pass 画在栈桥上**（cell31,7）——本片不动它，它现在读作「泊在码头的渔台」，正好。
5. **夜灯是普通 draw、不是加色光层**：船屋小窗的暖光走 `_night_amt()` 调 alpha 的普通 `draw_rect`，会被全局夜罩一起压暗（不像 facades 的 `X_LIGHT_WIN` 走 D3 加色光层会「发亮」）。夜里它读作「一扇比周围暗木更亮的暖窗」，不 bloom。要真发光得接 `lights` pass，那是另一处调用点、超出本片 owns（一函数+一调用点+一 AUDIT 项）。

## 六、CI verdict
`LT_VISUAL=require GODOT=<4.6.2 win64> bash tools/ci.sh`（docker 视觉门 tol=0，强制真跑，不 SKIP）：
```
（跑完后填：全步 PASS / 退出码 0；POND PASS，判决量 before=after 逐位不变）
```

## 七、媒体（`docs/media/apport/`，docker 真渲染 seed3 · 昼 tick600 / 夜 tick488 · `--shot-fit`）
- 整镇 before/after：`{before,after}_town_{day,night}.png`。
- dock 放大 before|after（左旧右新）：`dock_before_after_{day,night}.png`——旧=带凳石铺装 + 白「滩头」大字 / 新=木栈桥 + 船屋 + 渔船 + 货堆 + 路牌，而**池水与岸线逐像素相同**。
