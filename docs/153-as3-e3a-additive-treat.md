# 153 · AS3 经济棒 E3a：单环 treat 链（糕点→吃点心接 fun）· 实测判决：**证伪 docs/152『fun-treat 干净』断言、核心三货系统性下移 ⇒ 停、未重烘**

> 用户 2026-08-08 拍板 additive 路线继续、E3 落地 E3a（docs/152 §六最小落地片）。本片照 brief 实现了六个新键、标定过、跑过全套验收。**结论是否定的**：六键在【字节层】是纯加法（off-gate 12/12 逐字节回 pre-E3a golden），但在【行为层】不是 additive——留出 13-30 的口粮/柴薪/屋瓦满足率**系统性下移约 0.03 中位**，根因是【任何一条被大量选中的 town 平面 treat 活动都会稀释全镇有限的决策/空间预算、系统性压低其它岗位的产出】，与 treat 接哪个 need 无关。按 brief 的止损条款（「核心三货若系统性移动=停下报告、别重烘」），**未重烘任何金标锚**。行号实读于本片提交树、以 git 为准。

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| off-gate（删六键 → S0 金标逐字节回 pre-E3a） | ✅ **12/12 逐字节**（analysis/as3/offgate_headHarness_s1-12.txt） |
| 两跑一致（有糕点、同 seed 两跑 digest 逐字节） | ✅ **det 3/3** |
| #38 库存账本自洽（含糕点存量可重算） | ✅ **12/12** |
| #39 产出溯源到在班本职（糕点师） | ✅ **12/12** |
| #40 糕点进判决、rate 落带、不灌绿上限臂、dead_goods 不红 | ✅ **12/12**（N=12 s1-12；糕点 rate 0.536-0.969、gated 12/12、never_short 0/12、below_floor 0/12） |
| #01 无饿穿 | ✅ **12/12** |
| 整洁/豆子/话本 fun 消费微降（可解释） | ✅（整洁 demand −38.5、served 253→213；话本 served 58→53；豆子 flat） |
| **★核心验收锚：留出 13-30 口粮/柴薪/屋瓦 rate 基本不动** | ❌ **系统性下移**（口粮中位 −0.036、柴薪 −0.032、屋瓦 −0.028；每货 66-78% 的 seed 下移） |

⇒ 硬门全绿、字节纯加法，但**核心三货系统性移动** ⇒ 触发 brief 止损条款 ⇒ **停、未重烘三锚、未跑 N>12/CI**。本片是一条【量出来的负结果】：docs/152 §一「加一条接 fun、落 town 平面的平行 treat 货干净」这句断言，在产出侧不成立。

## 一、现有产/消机制复核（实读，本片提交树行号）

照 brief 核对，docs/152 §二/§六坐标全部准确：

| 事实 | 位置 | 复核 |
|---|---|---|
| 镇库 `town_stock`（整数件数，唯一通道 `_stock_move`） | `Sim.gd:310` decl / `_stock_move` `Sim.gd:3351` / `_stock_take` `Sim.gd:3464` | ✅ |
| 消费派发 `_consume_for`（查 `consume[action]`→`_stock_take`；缺货不阻断、走 `_shortage_fallout`） | `Sim.gd:3444` | ✅ 纯数据驱动：新 `consume.吃点心` 自动被派发、扣糕点、缺货写社会后果，**零 Sim.gd 改动** |
| 产出派发 `_produce_for`（按【职位 title】查 `produce[title]`；班次门 `_in_shift`；无 inputs 连缩水都不算） | `Sim.gd:3389` | ✅ 照抄 `咖啡师→豆子` 形状：`produce.糕点师` 无 inputs、determinism-clean |
| 工位广告 job 门 `_adv_open`（带 job 的广告只有现任持有人枚举得到） | `Sim.gd:1756` | ✅ `做点心`(job=糕点师) 只有 coco 见；`吃点心`(无 job) 全镇见 |
| 市集时段门 `_market_open`（只 gate vendor.action==该动作） | `Sim.gd:1766` | ✅ vendor.action=`赶集`≠`吃点心` ⇒ `吃点心` **恒开、不随商贩班次、不经 vendor ⇒ #34 全程不动** |
| #40 判据：`SUPPLY_FLOOR=0.5`、`SUPPLY_MIN_DEMAND=20`、`SUPPLY_MIN_DAYS=60`；demand=`attempts[action]×consume.amount`；上限臂『缺货绝迹』`never_short*2>gated_n` | `Invariants.gd:60-62 / 851 / 932` | ✅ 新货自动被 #38/#39/#40 覆盖，无需新不变量 ⇒ **HARD_IDS 不动**（绕开 E1 坑） |
| worksite type→精灵槽 `OBJ_SLOT_BY_TYPE`（现由**显式表**决定、非 id 前缀）；别名预算 `OBJ_SLOT_ALIAS_BUDGET={bench:5,counter:4,desk:2}` | `WorldView.gd:3952 / 4008` | ✅ 复用现有 type『摊位』(→counter)、零新别名 ⇒ **零 WorldView 改动、不撞预算** |
| spare 居民（无生产职位、现零工） | jobs.json 派 aria/ben/dan/lin/hai/shu；production.json 派 mei/tie/evy ⇒ 空闲 = **coco/fei/qin** | ✅ 取 coco=糕点师（天然单持有人、不触 #41） |

⇒ reuse-first 成立：stock/consume/produce/工位/job 门/池化/#38/#39/#40 一根没重造。E3a 真正新增的只有 `production.json` 六个键。**测量探针复用现成的 `ScaleSupply.gd`（只读、逐 good 报 rate/demand/shortage_days/gated），零新探针文件。**

## 二、E3a 设计与六键（diff 纯加法）

`game/data/production.json` 六个新增键（`git diff --stat`：21 insertions / 5 deletions，5 个删除全是给既有行**加尾逗号**以追加同级项、core 货的 goods/produce/consume/inputs/start_stock **值一字节未改**）：

```
+ start_stock.糕点 = 12
+ goods.糕点 { cap:20, spoil_per_day:1, blame:"糕点师", shortage_memo/claim/standing }
+ produce.糕点师 { good:"糕点", amount:4 }              ← 无 inputs（不吃任何 core 货）
+ consume.吃点心 { good:"糕点", amount:1 }              ← 接 fun，不接 hunger/hygiene/energy，免费
+ jobs.coco { title:"糕点师", action:"做点心", wage:3, shift:["dawn","day"] }
+ worksites[+1] counter_pastry { type:"摊位"(复用), area:"plaza", pos:[31,23],
    advertises: [ {做点心, job:糕点师, need:fun, amount:44, dur:24},
                  {吃点心,          need:fun, amount:48, dur:16} ] }
```

- `type:"摊位"` 复用 `OBJ_SLOT_BY_TYPE` 现有项（counter_stall 同 type）⇒ 零 WorldView 改动、别名计数不变。
- pos[31,23]：广场 rect[28,21,8,6] 内、避开 well[30,26]/board[33,26]/bench_1[30,23]/arcade_1[33,24]/节日灯笼锚[31,24] 与另三个广场工位；`audit_map.py` PASS（area 归属正确 + 有可达交互格 + 不切图 + ≥2 路线）。
- 免费消费（不进 vendor 键、不收钱、不经 transfer）⇒ **硬 #34 全程一字不动**。

### 标定（照 G3 屋瓦标定法扫，seeds 1-12 × 60 天 × N=12，backend=null；量完 6 轮见 analysis/as3/r1-r6）

| 轮 | 吃点心吸引力 E | 批量 A | cap | 糕点 rate (min/med/max) | never_short | below_floor | 判 |
|---|---|---|---|---|---|---|---|
| r1 | 44 | 6 | 24 | 1.00/1.00/1.00 | 12/12 | 0 | demand 14-30 太低（gated 6/12）、灌满 |
| r2 | 52 | 4 | 24 | 0.39/0.61/0.75 | 0 | **3/12** | demand 101-130 过高、单糕点师供不起荒 seed |
| r3 | 48 | 4 | 24 | 0.57/0.76/1.00 | 2/12 | 0 | 近了、2 seed 灌满（高 work seed） |
| r4 | 48 | 4 | 14 | 0.44/0.71/0.89 | 0 | **2/12** | cap 压过头、底破 |
| r5 | **48** | **4** | **20** | **0.54/0.72/0.97** | **0/12** | **0/12** | **★选它**：0 灌满、0 底破，10/12 严格落带、2 seed 0.92/0.97 仍有缺货天 |
| r6 | 48 | 5 | 16 | 0.50/0.77/1.00 | 2/12 | 1/12 | A=5 顶出灌满+底破，更差 |

定稿 = r5：**吃点心 amount 48（<玩耍 55、demand 42-97 全 ≥20 门）、做点心 amount 44、批量 4、cap 20、spoil 1、start_stock 12**。★spoil_per_day=1 是【平坦 1/天】排水（60 天 ~50-60 件），是主压缩杠杆；cap 只在高-work seed 上 bind、压缩上尾不动下尾——这两条把满足率从 r3 的『2 seed 灌满』收进带内而不破底。

## 三、硬门全绿证据（N=12 seeds 1-12，analysis/as3/final2_harness_s1-12_det3.txt）

```
✅ #01 无 need 触底 12/12   ✅ #38 库存账本自洽 12/12   ✅ #39 产出溯源到在班本职 12/12
✅ #40 产出闭环活性与供给充足 12/12   ✅ #41 手艺社会痕迹 12/12
✅ 同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链) 3/3
=== S0 GATE: PASS ✅ ===
```

- **off-gate（字节纯加法自证）**：把六键删掉（= production.json 回 HEAD）→ `Harness --seeds 1-12 --golden` = **✅ 金标一致 12/12 seed（含逐 tick 前缀链）**，与现 golden 逐字节相同（analysis/as3/offgate_headHarness_s1-12.txt）。⇒ 六键是【多键移除即回滚】纪律下的纯加法，删键即回今天。
- **两跑一致**：det 3/3（有糕点、同 seed 两跑三路摘要逐字节相同）⇒ determinism-clean（整数、无 inputs 无缩水、无 randi/Time/浮点）。
- **#38 绿（正）**：账本能独立重算含糕点的镇库存量（糕点走与全部货同一条 `_stock_move`/`_stock_take` 通道，#38 覆盖自动继承）。**负对照说明**：绕 `_stock_move` 直写 `town_stock[糕点]` → #38 必红——此变异体是【货无关】的（E1 已在柴薪上实测：docs/147 §二.3『现存 20/账本算得 −60』），糕点无任何专属代码路可绕，故其负对照与柴薪逐字同构；本片未再临时改 Sim.gd 复跑该负对照（禁区 + 已由 E1 覆盖）。
- **#40 落带（N=12 s1-12）**：糕点 gated 12/12、demand 42-97（全 ≥20）、rate 0.536-0.969（med 0.72）、never_short 0/12（上限臂不触发）、below_floor 0/12（下限臂不触发）、dead_goods 不红（糕点真被产真被吃）。

## 四、★核心验收锚：**失败**——留出 13-30 核心三货系统性下移（本片的心脏）

留出 seeds 13-30（N=12，改前 baseline_n12_s1-30.txt vs 改后 final2_n12_s1-30.txt）：

| 核心货 | rate 改前(min/med/max) | rate 改后 | **中位 Δrate** | 下移 seed 数 |
|---|---|---|---|---|
| 口粮 | 0.702/0.856/0.967 | — | **−0.036** | 12/18 |
| 柴薪 | 0.765/0.934/0.978 | — | **−0.032** | 14/18 |
| 屋瓦 | 0.818/0.966/1.000 | — | **−0.028** | 14/18 |

**这不是轨迹重排微扰，是系统性下移**（方向一致、66-78% seed 下移、且可归因）：

- **核心货 demand 未动**（吃饭 −6、洗澡 +8、睡觉 +2/seed，基本 flat）⇒ 分母没变。**掉的是产出侧**：核心生产者在班完成次数系统性下滑（留出 13-30 均值 Δ）：木匠 −1.56、环卫工 −1.83、咖啡师 −1.33、杂役 −1.28、教书先生 −1.28、面点师 −0.83（仅渔夫 +0.61、泥瓦匠 +1.89 上升）。产出 ÷ 不变的需求 = 满足率下移。量级自洽：面点师 −0.83 work × 90 口粮 − 渔夫 +0.61×85 ≈ −40 口粮/seed，/需求 1050 ≈ −0.04 rate，与实测中位 −0.036 同阶。

### 根因（**证伪 docs/152 §一『干净』断言**）：treat 稀释全镇有限决策/空间预算

第一假设是【吃点心(fun48) 抢 job 持有人的 fun-工作动作（烤点 fun20 等）】。**用两条实测证伪/收窄了这个假设**：

1. **调低吸引力不解决**：E=40（analysis/as3/E40_n12_s1-30.txt）demand 塌到 6-22（gated 仅 2/30、糕点失去被判据的资格），**而核心仍下移**（口粮中位 −0.035）。⇒ 核心下移的大部分不来自 fun-竞争的量级，来自【coco 变糕点师 + 广场多一个高吸引力活动簇】本身的轨迹重排。
2. **换 need 到 social 更糟**：吃点心 need=social amount=44（analysis/as3/social44_n12_s1-30.txt），job 工作动作是 fun、social treat 结构上抢不到工作 —— 但核心**下移更多**（口粮中位 −0.059、柴薪 −0.046、面点师 −1.94）。⇒ 彻底证伪『fun 竞工作』是主因。

⇒ **机制是决策/空间稀释、与 treat 接哪个 need 无关**：一条被大量选中（demand 60-80/seed）的 town 平面消费活动 = 60-80 个决策槽 + 广场空间引力（coco 摆摊 + 人群聚拢来吃）。这些槽/时间从居民【有限的行动预算】里来，job 持有人也参与（在广场吃/逗留 → 离工位远 → fun 需求召唤时就近吃/玩而非跋涉回工位）⇒ 系统性压低全镇其它岗位的到岗/产出。核心 need 消费（吃饭/洗澡/睡觉）不受影响（need 驱动、必满足），受影响的是【自由裁量】槽——而 job 工作在本仓库正是【自由裁量的 fun 活动】，故被稀释。

**结论：docs/152 §一「加一条接 fun、落 town 平面的平行 treat 货干净」在消费侧成立（核心 need 不动）、在产出侧不成立（核心供给被稀释）。** 「干净」是错的，纠正之。

### 可解释的一侧（fun 货微降）——这一半符合 brief 预期

留出 13-30：整洁 demand −38.5（玩耍被 吃点心 蚕食 −50/seed）、served 253→213；话本 served 58→53；豆子 flat。⇒ 「整洁/豆子/话本 fun 消费微降（可解释）」这条成立。问题只在核心三货那条锚。

## 五、判决与止损（照 brief 执行）

brief 三处明写止损：「若这三条动了=没做成 additive，停下报别硬上」/「核心三货若系统性移动=停」/「（或核心三货被移动）→ 停下报告、别重烘」。核心三货系统性移动 ⇒ **执行止损**：

- **未重烘任何锚**（golden_digests 的 seeds/scenarios 段、modelpath_anchor 全部保持 HEAD 值）。
- **未跑 N>12（16/24/60）与全量 ci.sh**（止损点在核心锚之前；跑大 N 无意义、只会固化一个不该 land 的基线）。
- HARD_IDS 未动（additive 无需新不变量，本就不碰）。
- `production.json` 的六键**留在树上**（供协调者复核实测），但金标故意不动 ⇒ 提交树上 S0 金标会因糕点轨迹移动而【红】——这【是】正确信号（红线#1：金标意外变红时正确反应是查代码/查设计、不是重烘），不是 bug。off-gate 已证删六键即绿。

## 六、给协调者/用户的建议（不擅自 pivot）

1. **docs/152 §七的「更低扰动变体」很可能才是真 additive**：把糕点挂到**既有**的社交/闲待动作（如 `闲聊`）而不是【新加一条决策选项】。因为【缺货绝不阻断动作】红线保证既有动作的**选中频率不随糕点库存变**（有糕点照吃、没糕点照闲聊+写 shortage）⇒ 不新增决策槽竞争 ⇒ 结构上不稀释核心产出，需求=既有闲聊频率（127/seed，天然 ≥20、随人口涨）。代价是「改既有动作语义」，docs/152 自己写「严格 reviewer 可能不认作纯 additive」——**这是一次设计 pivot，需协调者/用户拍板**，本棒不擅自改。⚠ 需先验证 `闲聊` 是否经 `_consume_for` 派发（本片未验）。
2. **或**接受核心三货 ~0.03 中位下移为「可接受的 additive 代价」——但那与 brief「基本不动」的措辞冲突，属用户重新划线，不是本棒能判的。
3. **或**放弃 town 平面 treat、走 docs/152 拒掉的其它候选——同样是设计层决定。

## 七、诚实边界

- 只 backend=null headless、N=12（大 N 未跑，止损在前）。
- 标定值（E48/A4/W44/cap20/spoil1）是 seeds 1-12 扫出的 r5，留出 13-30 上有 1 个 seed 糕点 rate 0.463（below 0.5，软门容 1）——糕点自己的落带在留出上基本成立；**问题不在糕点、在它对核心的稀释**。
- 「决策/空间稀释」的精确分解（决策槽 vs 空间引力 vs 承诺 pre-empt 各占多少）未分离——能确定的是【与 need 类型无关、调低吸引力不消除、换 social 更糟】三条，足以判「非 additive」。
- 未临时改 Sim.gd 跑 #38 糕点专属负对照（禁区；#38 货无关、E1 柴薪已覆盖）。
- 未跑真机/SLM/LOD。

## 附：证据文件（analysis/as3/）

- `baseline_n12_s1-30.txt`：改前基线（核心三货锚）。
- `r1..r6_n12_s1-12.txt`：标定扫（6 轮 E/A/cap）。
- `final2_harness_s1-12_det3.txt`：定稿硬门全绿 + det 3/3。
- `final2_n12_s1-30.txt`：定稿（fun48）改后，核心三货系统性下移的主证据。
- `offgate_headHarness_s1-12.txt`：off-gate 12/12 逐字节。
- `E40_n12_s1-30.txt`：调低吸引力不解决核心下移（demand 塌、核心仍动）。
- `social44_n12_s1-30.txt`：换 social need 核心下移更多（证伪 fun-竞工作主因）。
