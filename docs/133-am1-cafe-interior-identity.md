# 133 · AM1 — cafe 室内身份分区（1F 咖啡区 / 2F 阿丽私宅）+ 2F 像素门 + `_note` 订正

> Wave AG3 纵切实现·第一片（brief：docs/126 §P-B/§P-E）。外审 2026-08-06 Phase 1。
> 手法照抄 R2（docs/69 室内壳）/ S3（家具语义分化）/ AK1（docs/131 视觉门接线）。
> owns：`game/data/interiors.json`、`game/data/spaces.json`(仅订正 `_why`)、`game/scripts/WorldView.gd`、
> `tools/visual_gate.sh` + 新判据 `tools/assert_cafe_2f.py`、本文档 133。**不碰** Sim.gd / golden / ledger 三件套。

外审点名的病：**"现有室内是程序化矩形立面、重复床/桌/书架/盆栽"**。本片把 cafe 1F/2F 做成
**有身份、非模板**的两套家具语汇（公共咖啡区 vs 私人卧室），并补上"多楼层"里从没被任何门看过的 2F。

对照图（真引擎 `--shot`，红线 R2 非生成图）：`docs/media/am1_cafe_{1f,2f}_{before,after}.png`。

---

## 一、现状清点（开工前实读，标 advertises = 不能动 / 纯装饰 = 可动，带原始行号）

`interiors.json` 有**两条 Sim 读取路径**（协调者只交代了第①条，第②条是本片实测补上的，见 §三）：

| 楼层 | slot | pos | 原行号 | advertises? | 判定 |
|---|---|---|---|---|---|
| 1f | stairs | [1,1] | 8–15 | 无 | portal 锚点（spaces.json `p_cafe_stairs` 端点）→ 位置**不动** |
| 1f | shelf | [6,1] | 16–22 | 无 | 纯装饰（`_furniture_role`→cafe→杯碟架）→ 可动 |
| 1f | **counter** | [4,1] | 23–45 | **看摊/闲聊** | **Sim 候选对象 `cafe1f_counter`（staff）→ 位置+slot+advertises 逐字不动** |
| 1f | coffee | [5,1] | 46–53 | 无 | 纯装饰 → 可动 |
| 1f | table | [2,3] | 54–60 | 无 | 纯装饰 → 可动 |
| 1f | chair | [2,4] | 61–67 | 无 | 纯装饰 → 可动 |
| 1f | **table** | [5,3] | 68–82 | **喝咖啡** | **Sim 候选对象 `cafe1f_table` → 逐字不动** |
| 1f | chair | [5,4] | 83–89 | 无 | 纯装饰 → 可动 |
| 1f | plant | [1,4] | 90–96 | 无 | 纯装饰 → 可动 |
| 1f | rug | [3,2] | 97–103 | 无 | 纯装饰（walkable）→ 可动 |
| 2f | stairs | [1,1] | 110–117 | 无 | portal 锚点 → 不动 |
| 2f | **bed** | [2,2] | 118–133 | **睡觉** | **Sim 候选对象 `cafe2f_bed`（阿丽睡这）→ 逐字不动** |
| 2f | desk | [5,2] | 134–141 | 无 | 纯装饰 → 可动 |
| 2f | shelf | [6,1] | 142–148 | 无 | 纯装饰 → 可动 |
| 2f | rug | [3,3] | 149–155 | 无 | 纯装饰（walkable）→ 可动 |
| 2f | plant | [6,4] | 156–162 | 无 | 纯装饰 → 可动 |
| 2f | window | [7,3] | 163–169 | 无 | 纯装饰（walkable）→ 可动 |

**带 advertises 的三件（counter/table 喝咖啡/bed）= sim 对象**：本片位置、slot、advertises 载荷**逐字节从原文件复制、一格没动**（`analysis/am1/edit_interiors.py` 从原 dict 取 advertises，不重写）。

---

## 二、⚠️ 关键更正：**"纯装饰家具 = 零金标" 是错的**（先量清楚才动，动错=移金标）

brief 与协调者的口径：*"不带 advertises 的纯装饰家具 = 只渲染、零金标（Sim.gd:651 注释自证：无 advertises→不加对象→逐字节不变）"*。**实测证伪：这只覆盖了第①条读取路径。**

- **第①条**（`Sim._compile_interiors`, :652）：只有**带 advertises** 的家具编译成 world 候选对象。纯装饰→跳过→不进候选。协调者说的是这条，**对**。
- **第②条**（`Sim._build_interior_grids`, :3995）：**每一件家具**（不分 advertises）只要 slot ∉ `WALKABLE_SLOTS={stairs,rug,window}` 就把它那格**挡进该平面导航网**。而阿丽(aria) `spatial_address={cafe,2f,[2,2]}` **真住 2F**、按 portal 跨平面走动（docs/126 §三，`_journey_candidates→_route_next_hop→_move_agent`）⇒ **在原先空的格上新增一件纯装饰家具会挡路、重排她的室内寻路。**

**实测判决**（摘要归档 `analysis/am1/digests_after.txt`——第一版布局把甜点柜/吧凳/衣柜等**加在原先空的内格**上；⚠️审查 F4 纠：本片只归档了 `digests_*.txt` 摘要，未单独存 `golden_*.log` 判决全文）：

```
digest / event_digest / events：12/12 seed 逐字节【相同】
chain（逐 tick 前缀链）：      12/12 seed 【全变】  ⇒ 金标门破 ⇒ S0 GATE FAIL
```

即：**终态聚合与全部事件一字不差，但逐 tick 轨迹漂了**——居民被新家具挡格改了室内走位。golden 门含 chain ⇒ CI 会红。**这正是 brief 里"动错=移金标、停下"要防的那条**，只不过它藏在第②条路径里，`Sim.gd:651` 的注释看不见它。

### 修法：不是"硬改"，是把改动**约束成真·零金标** —— 保持【导航挡格集】不变

零金标的充要条件不是"无 advertises"，是 **`_build_interior_grids` 的挡格集逐格不变**。据此三条纪律：

1. **就地换身份**：每个原有家具格**位置不动、walkable 属性不动**，只换 `slot`（换的是画法/身份，不是几何）。挡格由 (格, walkable) 决定、与 slot 名无关 ⇒ 挡格集不变。
2. **新增装饰只用 walkable slot(`rug`)** 落在原先空的内格（walkable ⇒ 不挡格）。
3. **挂墙装饰(`picture`)只落边界格**（x=0/7 或 y=0/5——本就被外墙挡，furniture 再挡是幂等）。

`edit_interiors.py` 末尾自带**挡格集不变式自证**（逐楼层比 old==new，见输出）；两楼层均 `identical: True`。

---

## 三、改动

### 3.1 `interiors.json`（cafe 1F/2F 就地换身份 + walkable 装饰）
- **1F 咖啡区**：`table[2,3]→pastry`（玻璃甜点柜）、`chair[2,4]/[5,4]→barstool`（吧凳）、`plant[1,4]→menu`（A 字黑板菜单牌）；`shelf[6,1]` 留杯碟架、`coffee[5,1]` 留咖啡机；加 walkable `rug[4,4]`（门口迎宾地毯）。
- **2F 阿丽私宅**：`shelf[6,1]→wardrobe`（高衣柜）、`plant[6,4]→vanity`（梳妆镜）；`desk[5,2]` 留书桌；加 walkable `rug[2,3]`（床前地毯）+ 边界格 `picture[0,2]/[0,3]`（左墙私人相片墙）。
- 公共 vs 私人两套家具语汇，与彼此、与其余 7 栋都不再一个模子。

### 3.2 `WorldView.gd`（`_draw_interior_furniture` 新增 6 个纯装饰 slot 画法）
`pastry`（玻璃甜点柜）/ `barstool`（吧凳）/ `menu`（A 字黑板）/ `wardrobe`（衣柜）/ `vanity`（梳妆镜）/ `picture`（相框）。全部严格画在本格 `[base,base+T]` 内、不越格污染墙面采样带。纯 View、Sim 从不读 ⇒ 零金标。
另：家具绘制循环改走 `_ac("interior_furniture", …)` 零重排闸门 —— 出货 `_askip==""` 时原样返回集合（逐字节不变），`--draw-skip interior_furniture` 时跳过家具，供 2F 门拍**真渲染空 2F 负对照**。

### 3.3 `spaces.json` cafe `_why` 订正（Inv 跳 `_`/`_why` 键 ⇒ 零金标）
旧注 *"Tier-A：只 Probe inspect、居民不进、digest 逐字节不变"* **与实况矛盾**（阿丽真住 2F、journey 跨平面）。改成 **Tier-B** 实况 + 金标口径（advertises 家具/挡格集两条真源）。`interiors.json` 顶 `_note` 同步订正同一处腐烂。

### 3.4 `tools/`：cafe 2F 像素门
`visual_gate.sh` 补拍 cafe **2F** 两帧（正常 + `--draw-skip interior_furniture` 空 2F），rc=7 专给采集失败；`tools/assert_cafe_2f.py`（新判据）宿主侧判。**命名不用 `vg_int_` 前缀**——否则会被 `assert_interior_shell/furniture_role` 当 space id globby 进去（`cafe_2f` 不是 space ⇒ 壳门假红）；1F 参照直接复用 `vg_int_cafe.png`。

---

## 四、零金标三证据（预期逐字节不变，含 chain）

| 证据 | 文件 | 结论 |
|---|---|---|
| ② 开工前 golden baseline | `analysis/am1/digests_baseline.txt`（金标 12/12 baseline，det 3/3；⚠️判决 `.log` 未单独归档） | 基线在本机 4.6.2 复现 |
| ① 自造 A/B 摘要（改后 vs 基线，**逐字节**） | `analysis/am1/digests_final.txt` vs `digests_baseline.txt` | **12/12 seed 逐字节相同（含 chain）**，S0 GATE PASS（判决行在落地 CI run；摘要=digests_final.txt） |
| ③ 留出的 seed | 同上，seeds `1-12` × 60 天 × det 3 | 全程可复现 |

**负结果留档（诚实）**：第一版布局（加密度、挡格集变了）→ 摘要 `digests_after.txt`：digest/event_digest 相同、**chain 全变、S0 FAIL**。据此改为"就地换身份"（挡格集不变）→ chain 也逐字节回来（`digests_final.txt` 复现 12/12）。⚠️审查 F4：两次复现的判决 `.log`（原文写作 `golden_chainsafe.log`/`golden_final.log`）**未落进 `analysis/am1`**，只归档了 `digests_*.txt` 摘要——勿把这两个 `.log` 名当存证。

> 一句话：**digest 不动不等于零金标**——golden 门还含逐 tick 链，室内挡格改了它就漂。本片停在真·零金标的一侧（挡格集不变），未越 R12 线。

---

## 五、cafe 2F 像素门（`assert_cafe_2f.py`）探测包络

守第十条性质：**多楼层里 2F 真被渲出家具、且与 1F 分得开。** 三臂（阈值全部在未改动真帧上量、两侧留 ~2× 余量）：

- **A 非空**：`frac_diff(2F, 空2F) ≥ 0.06`（实测 0.129）。空 2F = `--draw-skip interior_furniture` 真渲染，若 2F 渲成空则 2F==空、frac→0 ⇒ 红。**负对照在判据内、每次 CI 都跑。**
- **B 与 1F 可分**：`frac_diff(2F, 1F) ≥ 0.10`（实测 0.230）。
- **C 有牙自证**：`colors(2F) − colors(空2F) ≥ 8`（实测 35−17=18）。

detects：① 2F 渲成空（家具没画）⇒ A/C 红（实测：把空 2F 当 2F 喂进去，A=0.0 / gap=0 ⇒ FAIL）；② 楼梯往返没换层/两层画一样 ⇒ B 红。
does_not_detect：颜色对不对（关系判据，色值真源留 WorldView）；只看 cafe 一栋 2F；软渲 docker 非真机；不判 1F 往返不变式（那是 `assert_space_roundtrip` 的活）。

---

## 六、验收结果（本机 docker gamecraft-runner:4.6.2 软渲 pin，tol=0）

- **零金标**：golden **12/12 seed 逐字节相同（含 chain）**，det 3/3 —— §四。
- **`visual_gate.sh` 全绿**（`LT_VISUAL=require`，rc=0）：
  - DAYNIGHT PASS · void-gate ok · space-roundtrip ok · POND PASS
  - **INTSHELL PASS**（7 栋/4 类；cafe 墙主面众数 `#5a4028` commercial，我的家具没溢出到墙面采样列 col0/7）
  - **FURNROLE PASS**（7 栋/5 类；cafe 杯碟架画法/位置没动 ⇒ 门不受扰）
  - TREESTAND / SEASON / PRECIP PASS
  - **CAFE2F PASS**（新门）：A 非空 0.129≥0.06 · B 与1F可分 0.230≥0.10 · C 色数落差 18≥8
- **2F 门负对照有牙**（把 `--draw-skip interior_furniture` 的空 2F 当 2F 喂进去）：`A=0.0 / gap=0 ⇒ FAIL`。
- **CI**：`bash tools/ci.sh` 判决行 = **`=== CI PASS ✅ ===`**（rc=0；step6 视觉门含新 cafe 2F 门全绿、S0 金标 12/12、DetGate/BackendGate/ModelPathGate/VoiceGate/AA3#43/单元测试全过）。
