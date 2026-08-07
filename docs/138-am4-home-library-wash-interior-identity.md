# 138 · AM4 — home / home2 / library / wash 室内身份分区（照 AM1/AM2 硬零金标手法）

> Wave AG3 纵切实现·第四片（收尾"每栋建筑室内有身份"）。方向 PC-first（用户 2026-08-07）。
> 手法照抄 AM1（docs/133）/ AM2（docs/134）：**零金标的充要条件 = 导航挡格集逐字节不变**，非"无 advertises"。
> owns：`game/data/interiors.json`（**只动 home/home2/library/wash 四栋**，cafe/shop/work 一个字节没碰）、
> `game/scripts/WorldView.gd`（新装饰 slot 画法 + desk 按 role 派发）、本文档 138。
> **不碰** Sim.gd / golden / ledger 三件套 / cafe·shop·work 室内（AM1/AM2/AM3 地界）。

外审点名的病：**"程序化矩形立面、重复床/桌/书架/盆栽"**。AM1 做 cafe、AM2 做 shop/work、AM3 补往返门；
本片把剩下的**四栋室内**各做成有身份、非模板的家具语汇——两栋民居**彼此可分**（温馨家 vs 素净书斋）、
图书馆书香、澡堂沐浴，四栋各有辨识度且与 cafe/shop/work 明显不同。

对照图（真引擎 `--shot`，红线 R2 非生成图，docker gamecraft-runner:4.6.2 软渲 seed3 正午 `--shot-fit`）：
`docs/media/am4_{home,home2,library,wash}_1f_{before,after}.png`。

---

## 一、现状清点（开工前实读，带原始行号，标 advertises / 挡格）

四栋基线家具（`git show 1f1d24b:game/data/interiors.json`）。BW/BH 取各栋 `spaces.json bounds`。
`_build_interior_grids`(Sim.gd:3995)：slot∉{stairs,rug,window} 且在内格 ⇒ 挡格。

### home（民居，行 201–283；areas.type=residential，role=living；bounds [0,0,9,7]，内格 x∈1..7 y∈1..5）
| slot | pos | advertises? | 挡格? | 判定 |
|---|---|---|---|---|
| bed | [1,1] | **睡觉** | 是 | **Sim 对象 `home1f_bed`（authored 第 1）→ 逐字不动** |
| bed | [6,1] | **睡觉** | 是 | **Sim 对象 `home1f_bed_1`（authored 第 2，顺序定后缀）→ 逐字不动** |
| shelf | [4,1] | 无 | 是 | 纯装饰 → 原地换 slot `dresser`（五斗柜） |
| table | [1,3] | **歇着** | 是 | **Sim 对象 `home1f_table` → 逐字不动** |
| chair | [2,3] | 无 | 是 | 纯装饰 → 留（桌椅） |
| rug | [3,3] | 无 | 否(walkable) | 纯装饰 → 不动 |
| plant | [5,3] | 无 | 是 | 纯装饰 → 原地换 slot `stove`（柴炉） |

### home2（民居，行 392–451；residential，role=living；bounds [0,0,6,5]，内格 x∈1..4 y∈1..3）
| slot | pos | advertises? | 挡格? | 判定 |
|---|---|---|---|---|
| bed | [1,1] | **睡觉** | 是 | **Sim 对象 `home21f_bed` → 逐字不动** |
| shelf | [4,1] | 无 | 是 | 书架（role=living→books，FURNROLE「书架」B 臂）→ 保 slot |
| table | [1,3] | **歇着** | 是 | **Sim 对象 `home21f_table` → 逐字不动** |
| chair | [2,3] | 无 | 是 | 纯装饰 → 原地换 slot `stool`（独凳，与 home 的椅分开） |
| rug | [3,3] | 无 | 否(walkable) | 纯装饰 → 不动 |

### library（图书馆，行 510–558；public，role=study；bounds [0,0,7,6]，内格 x∈1..5 y∈1..4）
| slot | pos | advertises? | 挡格? | 判定 |
|---|---|---|---|---|
| shelf | [1,1] | 无 | 是 | 书架墙（role=study→books，FURNROLE C 臂）→ 保 slot |
| shelf | [2,1] | 无 | 是 | 书架墙（与 [1,1] 逐像素同）→ 保 slot |
| shelf | [5,1] | 无 | 是 | 书架墙 → 保 slot |
| desk | [3,3] | 无 | 是 | 阅读桌（role=study 触发 AM4 新画法）→ 保 slot |
| stool | [4,3] | 无 | 是 | 阅读凳 → 留 |
| plant | [1,3] | 无 | 是 | 纯装饰 → 原地换 slot `lamp`（落地阅读灯） |

**advertises：0 件**（路① 零 world 候选对象）。role=study 需 `shelf≥2 AND desk AND 无 bed` ⇒ 保 3 shelf + desk、绝不引入 bed。

### wash（澡堂，行 285–333；public，role=bath；bounds [0,0,9,7]，内格 x∈1..7 y∈1..5）
| slot | pos | advertises? | 挡格? | 判定 |
|---|---|---|---|---|
| bath | [1,1] | 无 | 是 | 浴池（role=bath 触发器）→ 保 slot |
| bench | [3,1] | 无 | 是 | 纯装饰 → 原地换 slot `basin`（洗漱台） |
| shelf | [5,1] | 无 | 是 | 毛巾架（role=bath→towel，FURNROLE）→ 保 slot |
| plant | [1,3] | 无 | 是 | 纯装饰 → 原地换 slot `bath`（第二个浴池） |
| rug | [3,3] | 无 | 否(walkable) | 纯装饰 → 不动 |
| bench | [5,3] | 无 | 是 | 纯装饰 → 留（更衣凳） |

**advertises：0 件**。role=bath 由【有 bath slot】触发 ⇒ 保 bath[1,1]。

**导航挡格集（内格非-walkable 家具格）**：
- home `{(1,1),(1,3),(2,3),(4,1),(5,3),(6,1)}`
- home2 `{(1,1),(1,3),(2,3),(4,1)}`
- library `{(1,1),(1,3),(2,1),(3,3),(4,3),(5,1)}`
- wash `{(1,1),(1,3),(3,1),(5,1),(5,3)}`

**本片改后逐格不变**（§四自证）。全仓 advertises 8 处只在 cafe/home/home2；本片改的四栋里
只有 home(3)/home2(2) 带 advertises、library/wash 零件——这五件位置+slot+label+advertises+authored 顺序**逐字节不动**。

---

## 二、⚠️ 三条实读订正（先量清楚才动，动错=移金标）

1. **INTSHELL 采样范围比 AM1 转述的宽**：`assert_interior_shell.py` 只采**左右墙列**(col0/col w-1)的内格。
   AM1 给 cafe **2F** 加了挂墙 `picture` 没事，是因为 **2F 不在 INT_SPACES**；而 **S3 已把 home2 与 shop
   加进 INT_SPACES**（visual_gate.sh:84）——∴ **home/home2/library/wash 四栋全被 INTSHELL 采样**。
   ⇒ 本片**不加任何挂墙件**（picture/window 落墙列会移墙众数、B 臂假红），改走**纯内格 re-slot + walkable rug**。
   所有 re-slot 的家具 x∈{1,3,4,5}、都不在 col0/col w-1，画法严格在本格内 ⇒ 不越格污染采样带。

2. **FURNROLE 也吃全部 `vg_int_*`**（含 home2）：home2 EXPECT「书架」⇒ **保 home2 的 shelf(books)** 撑 B 臂
   （同类必须相同：home2↔library 两处 books 逐像素同）。home 的 shelf→dresser ⇒ home 不再进 FURNROLE
   （门对无 shelf 的栋 `continue`，合法；「书架」类退成 {home2, library} 仍成对）。

3. **`_compile_interiors`(:674) 用 authored 顺序给同 slot 去重**：home 两张床按数组顺序得 `home1f_bed` /
   `home1f_bed_1`。∴ 重建 home 数组时**两床保序**（bed[1,1] 在 bed[6,1] 前），否则后缀翻面 ⇒ 移 digest。

---

## 三、改动

### 3.1 `interiors.json`（四栋就地换身份 + walkable 装饰；cafe/shop/work 等 4 段 + _note 逐字节不变）
- **home（温馨家）**：`shelf[4,1]→dresser`（五斗柜+柜面相框=私人物件）、`plant[5,3]→stove`（柴炉，slot 名 stove ⇒ 夜里自带暖光池）；
  留两床+桌椅；加 walkable `rug[5,4]`（炉前地毯）+ `rug[2,2]`（床前小毯）。
- **home2（素净书斋）**：`chair[2,3]→stool`（独凳）；保 bed+桌+shelf(书架)；加 walkable `rug[2,2]`。
  —— 与 home 明显不同：一床/无柜无炉、以整墙书为主 = 读书人单间。
- **library（书香）**：`plant[1,3]→lamp`（落地阅读灯）；保 3 书架墙 + `desk`(阅读桌) + stool(阅读凳)；加 walkable `rug[3,2]`（阅读区地毯）。
- **wash（沐浴）**：`bench[3,1]→basin`（洗漱台+圆镜）、`plant[1,3]→bath`（第二个浴池）；保 bath 池 + shelf(毛巾架) + bench(更衣凳)；加 walkable `rug[3,2]`/`rug[1,2]`（浴垫）。
- 每件原有家具**位置不动、walkable 属性不动**——挡格集因此逐字节不变（§四）。
- 写回用 `json.dumps(indent=1)` 后 `\n→\r\n`（原文件 CRLF）⇒ diff 只落在四栋（48+/6-），其余逐字节不变。

### 3.2 `WorldView.gd`（`_draw_interior_furniture`）
- **新增 4 个纯装饰 slot 画法**：`dresser`（五斗柜+抽屉+铜拉手+柜面相框）、`stove`（深金属柴炉+炉门火光+烟囱）、
  `basin`（石台洗漱盆+龙头+圆镜）、`lamp`（落地灯+灯罩+暖光晕）。
- **`desk` 按 role 派发**（照 counter/crate/shelf 的 S3 同型）：`role=="study"` 走图书馆阅读桌（摊开的书+墨水瓶），
  **else 分支逐字节沿用改前代码** ⇒ cafe 2F 私宅书桌渲染不受扰（实测 5/5 行 byte-identical）。role=study 只命中 library 一层。
- 全部严格画在本格 `[base,base+T]` 内、x∈[0.05,0.92]，**不越格污染 INTSHELL 墙面采样列**。纯 View、Sim 从不读 ⇒ 零金标。

---

## 四、零金标三证据（实测逐字节不变，含 chain）

| 证据 | 文件 | 结论 |
|---|---|---|
| ② 开工前 golden baseline | `analysis/am4/golden_baseline.log`（HEAD 1f1d24b） | 金标 **12/12 PASS（含 12 条逐 tick 链）**，det 3/3；本机 4.6.2 |
| ① 自造 A/B（改后 vs 基线，**逐字节含 chain**） | `digests_final.txt` vs `digests_baseline.txt` | `diff` **exit 0 = 12/12 seed 逐字节相同（含 chain 字段）**；`golden_final.log`：S0 GATE **PASS** |
| ③ 留出的 seed | 同上 | seeds `1-12` × 60 天 × det 3，全程可复现 |

**挡格集 + advertises 自证**（`analysis/am4/edit_interiors.py` 末尾，按每栋各自 bounds）：
```
home     内格挡格集 identical: True | {(1,1),(1,3),(2,3),(4,1),(5,3),(6,1)}  old==new
home2    内格挡格集 identical: True | {(1,1),(1,3),(2,3),(4,1)}              old==new
library  内格挡格集 identical: True | {(1,1),(1,3),(2,1),(3,3),(4,3),(5,1)}  old==new
wash     内格挡格集 identical: True | {(1,1),(1,3),(3,1),(5,1),(5,3)}        old==new
ALL 挡格集 byte-identical: True
ALL advertises byte-identical: True （home 3 / home2 2 / library 0 / wash 0 件对象序列逐字节同）
```

> 一句话：**digest 不动不等于零金标**——golden 门还含逐 tick 链，室内挡格改了它就漂（AM1 §二实测）。
> 本片停在真·零金标的一侧（挡格集逐字节不变、advertises 对象序列逐字节不变），chain 也逐字节回来。

---

## 五、视觉门实际输出（`LT_VISUAL=require`，docker tol=0）

`analysis/am4/visual_gate.log`（判决行原文）：

```
[INTSHELL] home       type=residential  墙主面众数=#886d49   [INTSHELL] home2   type=residential  墙主面众数=#836a48
[INTSHELL] library    type=public       墙主面众数=#556169   [INTSHELL] wash    type=public       墙主面众数=#556169
[INTSHELL] ✅ 室内外壳类型门 PASS（7 栋 / 4 类，异类最小 ΔE ≥ 8.0、同类最大 ΔE ≤ 4.0；home↔home2 residential 同类、wash↔library public 同类均过）
[FURNROLE] home2      期望=书架     1 格 /  5329 px  签名5 色: #5a4028 #3c2a1b #5f7b34 #41607f #a8443a
[FURNROLE] library    期望=书架     3 格 / 10800 px  签名5 色: #5a4028 #3c2a1b #5f7b34 #41607f #a8443a   （与 home2 逐色同 = B 臂；3 格 C 臂逐像素一致）
[FURNROLE] wash       期望=毛巾架    1 格 /  2652 px  签名6 色: #82868f #213b47 #eaf3f8 #f2dca8 #c3a97a #585c64
[FURNROLE] ✅ 家具语义分化门 PASS（6 栋 / 5 类，异类最小 ΔE ≥ 12.0、同类最大 ΔE ≤ 8.0）
其余同帧门：DAYNIGHT PASS · void-gate ok · space-roundtrip ok · POND PASS · TREESTAND PASS(昼+夜) · SEASON PASS · PRECIP PASS · CAFE2F PASS(0.129/0.230/18，cafe 未碰) · FLOOR ROUNDTRIP PASS ⇒ visual_gate rc=0
```

> ⚠️ home 的 shelf→dresser ⇒ home 不再进 FURNROLE（无 shelf 的栋门 `continue`，合法）；「书架」类退成 {home2, library} 仍成对。
> home 墙众数 `#886d49` 比 home2 `#836a48` 略暖是 `_draw_interior_night` 正午占用暖光（≤5/3/1 通道、ΔE≈2.1 < 4.0），INTSHELL 标定已含此噪声。

**读法**：INTSHELL 只采**墙**（左右列 col0/col w-1）——我的家具都在内格、不越格 ⇒ 四栋墙众数不受扰、
residential(home↔home2)/public(wash↔library) 同类仍相同、异类仍分得开。FURNROLE 只采 **shelf 格**——
home2/library 书架(books) 逐像素同、wash 毛巾架(towel) 未动 ⇒ B/C 臂过、异类仍 ≥12。

---

## 六、验收结果（本机 docker gamecraft-runner:4.6.2 软渲 pin，tol=0）

- **零金标**：golden **12/12 seed 逐字节相同（含 chain）**，det 3/3 —— §四。四栋挡格集 + advertises byte-identical。
- **`visual_gate.sh` 全绿**（`LT_VISUAL=require`，rc=0）：见 §五判决行（INTSHELL/FURNROLE 含四栋全过）。
- **对照图眼验**（红线 R2）：
  - home：shelf→五斗柜(带相框)、plant→柴炉(炉火)、+炉前/床前地毯；两床暖家。
  - home2：chair→独凳、保整墙书架、+素毯；素净单间（与 home 一眼可分）。
  - library：plant→落地阅读灯、desk→摊开书的阅读桌、3 书架墙、+阅读地毯；书香。
  - wash：bench→洗漱台(圆镜)、plant→第二浴池、留毛巾架/更衣凳、+浴垫；沐浴堂（去掉重复盆栽）。
  - 四栋各有辨识度，且与 cafe/shop/work 明显不同。
- **CI**：`bash tools/ci.sh` 判决行 = **`=== CI PASS ✅ ===`**（rc=0，全程 1297s；`analysis/am4/ci.log`）。
  step4 S0 金标 12/12（含 chain）· step4a 宏观池 N=16 · step6 视觉门（INTSHELL/FURNROLE 含四栋全绿）· 全部 asset/recalc/complement/det/backend 门皆过。
