# 134 · AM2 — shop 杂货铺 + work 工坊 室内身份分区（照 AM1 硬零金标手法）

> Wave AG3 纵切实现·第二片（brief：docs/126 §P-B）。外审 2026-08-06 Phase 1。
> 手法照抄 AM1（docs/133）：**零金标的充要条件 = 导航挡格集逐字节不变**，非"无 advertises"。
> owns：`game/data/interiors.json`（**只动 shop + work 两栋**，cafe 一个字节没碰）、
> `game/scripts/WorldView.gd`（新装饰 slot 画法 + counter/crate 按 role 派发）、本文档 134。
> **不碰** Sim.gd / golden / ledger 三件套 / cafe 室内（AM1 地界）/ map.json areas。

外审点名的病同 AM1：**"程序化矩形立面、重复床/桌/书架/盆栽"**。AM1 做了 cafe，本片把
**shop（杂货铺）/ work（工坊）** 各做成有身份、非模板的家具语汇，与 cafe/home 明显不同。

对照图（真引擎 `--shot`，红线 R2 非生成图，docker gamecraft-runner:4.6.2 软渲 seed3 正午）：
`docs/media/am2_{shop,work}_1f_{before,after}.png`。

---

## 一、现状清点（开工前实读，带原始行号，标 advertises / 挡格）

两栋的基线家具（`git show f5949b7:game/data/interiors.json`）。BW/BH 取各栋 `spaces.json bounds`：
**shop bounds [0,0,7,6]（内格 x∈1..5, y∈1..4）；work bounds [0,0,9,7]（内格 x∈1..7, y∈1..5）。**
`_build_interior_grids`(Sim.gd:3995)：slot∉{stairs,rug,window} 且在内格 ⇒ 挡格。

### shop（杂货铺，areas.type=commercial，role=store）
| slot | pos | 原行号 | advertises? | 挡格? | 判定 |
|---|---|---|---|---|---|
| counter | [1,1] | 452 | **无** | 是 | role=store 触发器①（须保 slot 名）→ 只换画法 |
| shelf | [3,1] | 459 | 无 | 是 | 货架（FURNROLE 采样，role=store→goods）→ 保 slot |
| shelf | [4,1] | 466 | 无 | 是 | 货架（同上，与 [3,1] 逐像素同 = C 臂）→ 保 slot |
| crate | [1,3] | 473 | 无 | 是 | 纯装饰 → 就地改名 sacks（同格同 walkable） |
| crate | [2,3] | 480 | **无** | 是 | role=store 触发器②（须保 slot 名）→ 只换画法 |
| rug | [4,3] | 487 | 无 | 否(walkable) | 纯装饰 → 不动 |

### work（工坊，areas.type=workshop，role=workshop）
| slot | pos | 原行号 | advertises? | 挡格? | 判定 |
|---|---|---|---|---|---|
| desk | [1,1] | 341 | 无 | 是 | 纯装饰 → 就地改名 workbench |
| crate | [3,1] | 348 | 无 | 是 | 纯装饰 → 就地改名 lumber |
| shelf | [5,1] | 355 | 无 | 是 | 工具架（FURNROLE 采样，role=workshop→tools）→ 保 slot |
| stool | [1,3] | 362 | 无 | 是 | 纯装饰 → 就地改名 anvil |
| crate | [2,3] | 369 | 无 | 是 | 纯装饰 → 就地改名 materials |
| rug | [4,3] | 376 | 无 | 否(walkable) | 纯装饰 → 不动 |

**导航挡格集（内格非-walkable 家具格）**：shop `{(1,1),(3,1),(4,1),(1,3),(2,3)}`、
work `{(1,1),(3,1),(5,1),(1,3),(2,3)}`。**本片改后逐格不变**（§四自证）。

---

## 二、⚠️ 三条实读订正（先量清楚才动，动错=移金标）

协调者/AM1 转述的两条断言经实读**部分证伪**，据实纠正：

1. **"shop/work 带 advertises 的货架/工位一个字节别动"** —— 实读：**shop 与 work 一件 advertises 都没有**
   （全仓 advertises 只在 cafe/home/home2：`grep advertises` 8 处全命中那三栋）。∴ 这两栋对
   `_compile_interiors`（Sim.gd:652，路①）**零 world 候选对象**。唯一绑定约束是路②的**挡格集**。
   （不影响结论：挡格集守则照守——它对纯装饰也咬。）

2. **bounds 不是 cafe 的 8×6**：shop=7×6、work=9×7。AM1 `edit_interiors.py` 硬编码 `BW,BH=8,6`
   **不能照抄**；本片自证按【每栋各自 bounds】算内格。portal 端点 shop[3,5]/work[4,0] 均落**边界格**、
   非内格，且 `_build_interior_grids` 对边界与 portal 都另有分支 ⇒ 不影响内格挡格集守则。

3. **role 分类器耦合**（`WorldView._furniture_role`，纯 View、不动 digest，但 **FURNROLE 门吃它**）：
   - **shop → "store" 需 `slots.has("counter") AND slots.has("crate")`**（WorldView.gd:1570）。
     ⇒ 本片**保留 counter[1,1] 与 crate[2,3] 两个 slot 名**（只把它们的**画法**按 role 派发成杂货铺款）。
     若把这两个 slot 改名，shop 掉回 "living"、货架变书架 ⇒ **FURNROLE 门红**。
   - **work → "workshop" 由 `areas.type` 决定**（WorldView.gd:1568，与 slot 无关）⇒ work 的
     desk/crate/stool 可自由改名。
   - 两栋各**保留 shelf slot**（FURNROLE 只采 `shelf` 格）：shop 货架(store)、work 工具架(workshop)。

---

## 三、改动

### 3.1 `interiors.json`（shop/work 就地换身份 + walkable 装饰；cafe/home 等 6 栋逐字节不变）
- **shop**：`crate[1,3]→sacks`（谷袋堆）；`counter[1,1]`/`crate[2,3]` 留 slot 名（画法按 role 派发成
  杂货铺前柜/敞口果箱）；两 `shelf` 留货架；加 walkable `rug[3,4]`（店门迎宾垫，门在 [3,5]）。
- **work**：`desk[1,1]→workbench`、`crate[3,1]→lumber`、`stool[1,3]→anvil`、`crate[2,3]→materials`；
  `shelf[5,1]` 留工具架；加 walkable `rug[4,1]`（工坊门垫，门在 [4,0]）。
- 每件原有家具**位置不动、walkable 属性不动**——挡格集因此逐字节不变（§四）。
- 写回用 `json.dumps(indent=1)` 后 `\n→\r\n`（原文件 CRLF；CRLF-redump 已验证逐字节等于原文件）
  ⇒ diff 只落在 shop/work 两段（19+/5-），cafe/home/wash/home2/library **一个字节没碰**。

### 3.2 `WorldView.gd`（`_draw_interior_furniture`）
- **新增 5 个纯装饰 slot 画法**：`sacks`（谷袋）、`workbench`（工作台+台钳+刨）、`lumber`（木料堆+原木端面）、
  `anvil`（铁砧+木墩+锤）、`materials`（料箱+棒料+铜线卷）。
- **`counter` / `crate` 按 role 派发**（照 `_draw_shelf` 的 S3 同型）：`role=="store"` 走杂货铺款
  （收银机+挂秤+果篮 / 敞口果箱），**else 分支逐字节沿用改前代码** ⇒ cafe 的吧台/木箱渲染不受扰。
- 全部严格画在本格 `[base,base+T]` 内、x∈[0.05,0.92]，**不越格污染 INTSHELL 墙面采样列**（col0/col w-1）。
  纯 View、Sim 从不读 ⇒ 零金标。

---

## 四、零金标三证据（实测逐字节不变，含 chain）

| 证据 | 文件 | 结论 |
|---|---|---|
| ② 开工前 golden baseline | `analysis/am2/golden_baseline.log` | 金标 12/12 PASS（含 12 条逐 tick 链），det 3/3；本机 4.6.2 复现 AM1 基线 |
| ① 自造 A/B（改后 vs 基线，**逐字节含 chain**） | `digests_final.txt` vs `digests_baseline.txt` | `diff` **exit 0 = 12/12 seed 逐字节相同（含 chain 字段）**；`golden_final.log`：S0 GATE **PASS** |
| ③ 留出的 seed | 同上 | seeds `1-12` × 60 天 × det 3，全程可复现 |

**挡格集自证**（`analysis/am2/edit_interiors.py` 末尾，按每栋各自 bounds）：
```
shop bounds 7x6  内格挡格集 identical: True | {(1,1),(1,3),(2,3),(3,1),(4,1)}  old==new
work bounds 9x7  内格挡格集 identical: True | {(1,1),(1,3),(2,3),(3,1),(5,1)}  old==new
ALL 挡格集 byte-identical: True
```

> 一句话：**digest 不动不等于零金标**——golden 门还含逐 tick 链，室内挡格改了它就漂（AM1 §二实测）。
> 本片停在真·零金标的一侧（挡格集逐字节不变、advertises 零候选），chain 也逐字节回来。

---

## 五、视觉门实际输出（`LT_VISUAL=require`，docker tol=0）

`analysis/am2/visual_gate.log`（本次实际归档内容）：

```
runner=docker  mode=require
shot ok  vg_night.png / vg_noon.png / vg_int_*.png …（采集齐）
void-gate ok       (静态不重画 + settle 期真的画过 + 空间往返必重画)
space-roundtrip 采集 ok  (town_before → interior → town_after)
```

⚠️**审查 F4 纠**：上面这份归档的 `visual_gate.log` **只截到 shot/void-gate/space-roundtrip 的采集行，没有 INTSHELL/FURNROLE 的逐门判决行**（那两道 assert 的 stdout 在 CI run 里、未单独落进本 log）。故本 doc 原来"判决行原文"是空占位、"全过"无本地存证支撑。✅**整轮 CI 归档回填（2026-08-07，`analysis/review-2026-08-07-ci/verdict.txt`，HEAD `1fcbfc8`）**——在现役 interiors.json（含 shop/work）上真跑这两道门：
- **`[INTSHELL] ✅ 室内外壳类型门 PASS（7 栋 / 4 类：commercial/public/residential/workshop，异类 ΔE ≥ 8.0、同类 ΔE ≤ 4.0）`**（work=workshop 墙主面 `#44423e`，与 commercial 类可分）。
- **`[FURNROLE] ✅ 家具语义分化门 PASS（6 栋 / 5 类，异类 ΔE ≥ 12.0、同类 ≤ 8.0）`**——含 **shop 期望=货架（2 格 7200px）、work 期望=工具架（1 格 2652px）**，两者签名色可分。
⇒ shop(commercial)/work(workshop) 的可分性判决**坐实**。

**读法（结构论证，非门判决）**：INTSHELL 只采**墙**（左右列 col0/col w-1 的 [0.35T,0.80T] 带）——我的家具都在内格、
不越格 ⇒ 墙众数不受扰、shop(commercial)↔cafe 同类应 ≤4.0、work(workshop) 异类应 ≥8.0。
FURNROLE 只采 **shelf 格**——shop 货架(store)/work 工具架(workshop) 画法没动、role 也没掉档
⇒ 异类应 ≥12.0、同类 ≤8.0。**这是"为什么不该红"的结构理由，判决行以上述整轮 CI 归档为准。**

---

## 六、验收结果（本机 docker gamecraft-runner:4.6.2 软渲 pin，tol=0）

- **零金标**：golden **12/12 seed 逐字节相同（含 chain）**，det 3/3 —— §四。挡格集 shop/work 两栋 byte-identical。
- **`visual_gate.sh` 采集段绿**（`LT_VISUAL=require`，rc=0）：归档 log 见 §五（shot/void-gate/roundtrip ok）。⚠️INTSHELL/FURNROLE 逐门判决行**未落进归档 log**，判决以 2026-08-07 整轮 CI 归档为准（审查 F4）；§五给的是"为什么不该红"的结构论证。
- **对照图眼验**（红线 R）：
  - shop：柜台→收银机+挂秤+果篮、`crate[1,3]`→谷袋、`crate[2,3]`→敞口果箱、加迎宾垫；与 cafe/home 明显不同。
  - work：desk→工作台(台钳+刨)、`crate`→木料堆/材料箱、stool→铁砧、留工具架、加门垫；工坊身份清晰。
- **CI**：`bash tools/ci.sh` 落地时跑绿（读判决行非退出码）；该 run 的判决行当时未单独归档 `analysis/am2`（审查 F4）。✅**整轮 CI 归档回填（2026-08-07，`analysis/review-2026-08-07-ci/verdict.txt`，HEAD `1fcbfc8`）= `=== CI PASS ✅ ===`**（S0 12/12 含链 + INTSHELL/FURNROLE 见 §五 + 全门绿）。
