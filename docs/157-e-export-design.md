# 157 · E-export 设计提案：货出→钱进（export 收钱 / external 闭环）· 只读探索

> 车道 E 第三片草案，接 E2a（import 付费已落地，docs/155）。**只读设计探索、未实现未改码。** 行号实读于当前树（ec0a4c3，已含 E2a）、会腐烂、以 git 为准。所有「逐字节 / #34 恒等 / #38 臂 / 闭环上界」是**结构推断，须落地实测（held-out 13-30 + 负对照 + 重烘三锚）**。⚠️**export 改 #45（硬货币溯源）口径 + 让 #35 外部非负臂首次可达 = 核心货币不变量口径变更，须 docs/41 §0.8 双路外审 + 用户拍板后才实现（判决见 §七 = YES）。** 本片是 docs/154 §四 / docs/155 §八 显式 defer 到 **P4** 的 export 侧首片。

## 〇、实读复核（当前树，E2a 已在）
| 事实 | 位置 |
|---|---|
| 唯一钱通道 `transfer(from,to,amt,reason,witnesses)`（`amt<=0`/`from<amt` 返 false；`_set_coin`×2 + 写 `pay` 事件 note=reason） | `Sim.gd:3241` |
| `_coin_of`/`_set_coin` 已含 `"external"` 臂（照抄 `"town"`） | `Sim.gd:3253/3261`（external 分支 `:3256/3265`） |
| `money_total()` = `town_coin + external_coin + Σagents.coin` | `Sim.gd:3273`（external 已在求和，`:3274`） |
| `external_coin` world 级整数声明 | `Sim.gd:277`（import 收款方；注释已写「export 收钱的付款方，留 E2b」） |
| start_new per-run 重置 `external_coin = 0`（在 econ_total0 快照前，BLOCKER-1） | `Sim.gd:847`（`town_coin` 重赋值 `:846`、`econ_total0 = money_total()` `:849`） |
| `stock_total0`（#38 基准）开局快照 | `Sim.gd:874`（声明 `:317`） |
| `_stock_move(good,delta,type,actor,reason)`：+delta 撞 cap 少收、−delta 只扣到 0（返回 applied，写 `type` 事件 note=`reason*|applied|`，target 恒 "town"） | `Sim.gd:3367`（−臂 `:3375-3376`、写事件 `:3380`） |
| `_stock_take(good,want)`：**不写事件**，扣库存 + 累加 `_stock_day[good]`（夜结 flush 成一条 "consume") | `Sim.gd:3480`（`_stock_day` bump `:3486`；夜结 `_stock_nightly` flush `:3680`） |
| import 日结 `_logi_import`（付费门 `_econ_on() and pnum>0 and pden>0`；选项 A 先付后到；`transfer("town","external",cost,"import")`） | `Sim.gd:3700`（`_import_fit` `:3732`） |
| 数据门 `_logi_on()`（缺 logistics.json → false → 每挂点首行短路）/ `_econ_on()` | `Sim.gd:757 / 3229` |
| #34 金钱守恒（`money_total()==econ_total0`，econ_on 活门） | `Invariants.gd:606` |
| #35 货币非负（已含 `and S.external_coin >= 0`，E2a 预埋「防 export 透支凭空铸币」） | `Invariants.gd:611`（注释 `:609-610`） |
| #38 库存账本自洽：`现存 == stock_total0 + Σmoved − _stock_day`，`moved` 只认 `["produce","import","consume","spoil"]`、`+` 仅 produce/import | `Invariants.gd:678`（moved 循环 `:660-666`、类型白名单 `:662`、符号 `:666`） |
| #44 进口溯源（import 事件 actor∈nodes、good∈lane、target=town、amt>0、reason=import） | `Invariants.gd:1035`（循环 `:1019-1034`） |
| #45 import 付费溯源：`external_coin == Σ_import amt×price_per/price_den` + 每笔 target=external 的 pay 必 actor=town/reason=import。**口径假设（`:1050`）：external 只被 import 贷入（export 才有借出）** | `Invariants.gd:1078`（应付 `:1063-1070`、pay 良构 `:1071-1077`） |
| 社交排除集（哪些事件类型**不算社交参与**，喂 #2/#3 会稀释成空门）= `["pay","world","election","produce","consume","spoil","shortage","import"]` | `Invariants.gd:225`（E1 追加 "import" 的理由 `:230`） |
| HARD_IDS 两份（改硬不变量须同步）= `[…,44,45]` | `Invariants.gd:1439` + `tools/gate_fixture_audit.py:71` |
| import lane 现值：柴薪 batch4/every3/price 3÷4 | `game/data/logistics.json` `import_lanes` |
| 货表 | 口粮 / 柴薪 / 屋瓦 / 豆子 / 话本 / 整洁（import = 柴薪，最紧货） |

## 一、触发：export lane（对称 import_lanes）
1. **数据**：`logistics.json` 新增 `export_lanes: [{good, batch, every_days, node, price_per, price_den}]`（形状照抄 `import_lanes`）。off 门：段缺/空 ⇒ export 循环第一行短路（同 import）。
2. **调度**：新原语 `_logi_export()`，挂**同一日界**（`_nightly`），`day % every_days == 0`（纯 `f(day)`、一天一次非 per-tick）。
3. **选什么货 = surplus，不是 scarcity**：import 选柴薪是因为它最紧；export 必须选**过剩货**——今天满仓 `spoil` 被丢弃的那部分（docs/144 §五 P4「余量成收入而非丢弃」）。候选识别须**落地跑 surplus 探针**（哪种货 town_stock 常年贴 cap / 有 `spoiled` 计数），与 import 选柴薪走的 scarcity 探针对称。**a-priori 候选**：`整洁`（`spoil_per_day=2`、#40 的 coverage 在 60 天收敛到 1.34–1.66 > 1.5，是产 > 耗的货，`Invariants.gd:730-733`）——**须实测证物理库存确有余量，非 coverage 指标假象**。**红线**：export 货**绝不能**碰满足率紧的口粮/屋瓦/柴薪，否则直接把 #40 供给底打红（§六）。
4. **出多少 = 双上界**：`batch_actual = min(lane_batch, surplus_above_floor, affordable_by_external)`。其中
   - `surplus_above_floor = max(0, _stock_of(good) − floor)`（floor 保住本地消费/产料需求；纯整数），**只出地板以上的余量 ⇒ 结构上不饿镇**；
   - `affordable_by_external`：见 §二（external 付得起的件数），这是闭环上界。

## 二、钱侧：#34 守恒 + external 是**闭环、有界、非负源**（本片最关键的发现）
- **收钱** = `transfer("external","town", revenue, "export")`，`revenue = applied × price_per / price_den`（整数地板，同 import 口径）。
- **#34 恒等（算术，与 import 同构）**：`external` 与 `town` 都在守恒集内 ⇒ 一次 export transfer 做的是集内 `external -= revenue; town += revenue` ⇒ `Δmoney_total = −revenue + revenue = 0` ⇒ `money_total() ≡ econ_total0` **结构恒真、#34 判据一字不改**（同 docs/155 §二.1 对 import 的证明，方向相反）。〔须 held-out 实测背书〕
- **★external 是闭环、不是无限源（决定性结论）**：`transfer` `:3245` 的 `from_coin < amt: return false` + #35 `:611` 的 `external_coin >= 0` 臂 ⇒ **external 永不为负**。external 从 0 起，只被 import **贷入（+cost）**、被 export **借出（−revenue）** ⇒ 任意时刻 `external_coin = Σimports − Σexports ≥ 0` ⇒ **累计 export 收入 ≤ 累计 import 支出**。
  - ⇒ 回答 task「export 是否被 prior import spending 上界 / external 是否无限源」：**是闭环，有界。** 镇子对外的净货币头寸 = `−external_coin ≤ 0`，即镇子对外部世界**永远是净付出方**；export 至多**收回**此前 import 付出去的钱，**不能把镇子变得比基线更富**。这正面回收 docs/151 §四.2 的通胀/分布担忧：external 非负 ⇒ 没有无限 export 水龙头把镇子灌富。
  - **为什么非闭环不可**：若允许 external 透支（无限源）⇒ #35 外部臂红、export 凭空铸币、#34 抓不到（同 docs/151 §一.18 / docs/154 §四 对「external 当集外无限源」的否决）。E2a 在 `:611` 预埋外部非负臂**正是为此**。
- **付不起处置（须外审/用户拍板的行为分叉，对称 import 选项 A）**：export 前算 `revenue`，若 `external_coin < revenue` ⇒
  - **选项 A′「先收钱后出货」（推荐、守恒忠实）**：external 付不起就**当天不出货**（`continue`，同 import `:3720` 的 `town_coin<cost:continue`）。或退一步：只出 external 付得起的件数 `affordable = external_coin × price_den / price_per`。**副作用（须诚实标）**：**从未 import 过的镇子（external=0）无法 export 收钱**——必须先「进」才能「出换钱」。60 天里 import 按 cadence 稳定累积 external（docs/155 实测局末 external 达 56–60），故中后期 export 有储备可抽；这是闭环的自然节流，也是最反直觉、最须实测确认活性的一点。
  - **选项 B「先出货后收钱、收不到白送」**：破坏经济语义（货白流走），且 external 无储备时退化成纯 stock 损耗，不推荐。

## 三、货侧：#38 需要一条 export 减号臂
- **走哪个通道**：export 应走 `_stock_move(good, −batch, "export", node, "export")`（对称 import 的 +delta），**不走 `_stock_take`**。
  - `_stock_move` −臂（`:3375-3376`）只扣到 0、返回 applied、写一条独立 `type="export"` 事件（可被溯源不变量校验）。
  - ⚠**陷阱**：`_stock_take` 会让 #38「免费通过」——它扣库存**同时**累加 `_stock_day`（`:3486`），而 #38 的 `expect` 恰好 `− _stock_day`（`:669`）⇒ got==expect 自动成立。**但**夜结把 `_stock_day` flush 成一条 **"consume"** 事件（`:3680`）⇒ 出口货被记成**居民消费**：污染 #40 的 `per_c`「已服务件数」、与 export **无独立事件/无节点/无 reason** ⇒ **无法溯源**。故 `_stock_take` 语义错，弃。
- **#38 的确切缺口**：`moved` 循环的类型白名单（`:662`）= `["produce","import","consume","spoil"]`，**不含 "export"** ⇒ 一条 `type="export"` 事件会被**跳过不计**，而 `town_stock` 物理已减 ⇒ `got < expect` ⇒ **#38 当场红**。
- **修法（对称 E1 给 import 加 + 号臂）**：`:662` 白名单加 `"export"`，`:666` 符号逻辑把 export 归入**减号**（`amt if produce/import else −amt` 已把非 produce/import 当减，故只需把 "export" 放进白名单即可自动记负——**须核对 `:666` 现有三元式**：现为 `(ty=="produce" or ty=="import")` 记正、else 记负 ⇒ 加 "export" 进 `:662` 后它天然落 else 分支记负，**符号自动正确**）。这是最小改动：**一处白名单加词**。〔须负对照实测：绕过 export 事件直写 town_stock−N ⇒ 账本多这一截 ⇒ #38 红〕
- **货侧溯源（可选、对称 #44）**：是否要 #44-analog（export 事件 actor∈export_nodes、good∈export_lane、reason=export）？**首片建议最小化**：#44 守「进的货/港合法」，export 的对称需求是「出的货/口岸合法」。可**并入 §四的 #45 泛化**统一守，或单列一条轻量 export 货溯源。首片**不必须**，但若不加，「货从未声明口岸流走」只由金标 digest 兜底。

## 四、溯源：#45 **必须**泛化（这是本片绕不开的口径变更）
- **为什么绕不开**：#45（`:1078`）现断言 `external_coin == Σ_import price`，其**成立前提**是 `:1050` 明写的「external 只被 import 贷入」。export **借出** external ⇒ 首次 export 后 `external_coin < Σimport` ⇒ **#45 当场红**。⇒ **export 无法在不动 #45 的前提下落地**（这与 §三 #38 的红并列，是两条硬红）。
- **最小泛化（推荐）**：把 #45 的等式改为双向对账
  `external_coin == Σ_import (amt×p_imp/d_imp) − Σ_export (amt×p_exp/d_exp)`（逐笔整数地板，与运行时同口径）；
  并把 pay 良构臂（`:1071-1077`）扩一条：每笔 **actor=="external"** 的 pay 必 `target=="town"` 且 `reason=="export"`（对称现有「target=external 必 actor=town/reason=import」）。这四方对账（economy × logistics × event_log × 运行时 external）继续成立，且这正是 docs/155 §八自陈的「E2b 打破 external 单向假设 ⇒ #45 须升级为 #36」的**export 切片最小版**——尚**不是**完整 #36（event-first 单 reducer 逐账户折叠），那仍是更大的 E2b。
- **负对照（须实测三条判别力）**：① 凭空 `transfer("external","town",X,"export")` 无 export 货撑 ⇒ external < 应值 ⇒ #45 红；② `revenue≠price×applied` ⇒ external≠应值 ⇒ #45 红；③ 收付款方写反（actor≠external / reason≠export）⇒ #45 红。且须复跑 import 侧 NEG_45 仍红（泛化没削弱旧判别力）。
- **off 门**：无 export lane / 无 export price ⇒ `Σ_export = 0` ⇒ 等式退回 import 首片形态 ⇒ 恒过（真空为真）。

## 五、社交排除集 + 分布通胀（task 5 命中的两处）
- **社交排除集（`Invariants.gd:225`）—— 命中，须补一词**：export 的 `pay` 事件（`transfer("external","town",…)`）type 已是 `"pay"`、**已在**排除集，无需动。**但**货侧 `type="export"` 事件（`_stock_move` 写、`accepted==true`）**不在**排除集 ⇒ 不排除的话 #2「社交发生」/#3「无永久孤立」会被一条**出港记录**喂饱（同 E1 给 import 补 "import" 的理由，`:230`）⇒ **须把 "export" 加进 `:225` 的排除列表**。这正是 E2 评审 §四所指的「export 触社交排除集」。
- **分布通胀（docs/151 §四.2）—— 命中，但被闭环上界夹住**：export **增** `town_coin`（revenue 进镇库）⇒ 直接喂「town_coin 单调涨 → 工资永不 skip → 抹掉镇库空压力」这条分布风险。**但** §二已证：town_coin 经 export 增涨**至多回收**此前 import 支出（external 非负闭环），**无法**被无限泵富。残余风险是**标定级**（export price×cadence 若过高，把结构性赤字镇也喂平、削弱 self-contain 压力）——归 §六标定 + **P4 的分布通胀阈值 / 钱上限**（docs/151 §四.2「留 E4」；当前树**无任何 town_coin 上限**，grep 确认）。

## 六、确定性 / off 门 / 标定
- **确定性**：`revenue = applied×p/d` 纯整数地板；调度 `day%every==0` 纯 `f(day)`；floor / surplus / affordable 全整数 `mini/maxi`。**零 randi/randf/Time/float**（对称 import，须 diff 实测证）。
- **off 门 2 轴**：① 删 logistics.json ⇒ `_logi_on()==false` ⇒ export 每挂点首行短路 ⇒ 逐字节回今天（同 import Axis1）。② logistics ON + economy OFF（或 export lane 无 price_per）⇒ **建议 export 整条挂在 `_econ_on() and p>0` 之后、economy off 时 export lane 惰性**（**不做**「免费出港/白送货」）⇒ 逐字节。⚠**与 import Axis2 的不对称须显式拍板**：import 的 economy-off 退化成「免费到货」（E1 有先例）；export 的 economy-off **没有** E1 先例（出口本身是 E2 才有的概念），故 export 应**直接惰性**而非「免费出港」——免费出港 = 无补偿的 stock 损耗，无 E1 语义可继承。
- **标定（对称 docs/155 §二.4，须实测价扫）**：export price/cadence 取值须同时满足——① **不饿镇**：floor + surplus-only 结构保证，但须 held-out 13-30 逐 seed 证 export 货满足率/相关下游货不被 #40 打红（§一.3 红线）；② **不暴富**：town_coin 涨幅须留住穷镇 self-contain 压力（结构性赤字镇仍会跳工资），不因 export 收入把 wages_skipped 全抹平；③ **闭环活性**：须实测中后期 external 储备足以支撑 export cadence（否则 export 频繁 stall，机制在账本上存在、在可见面近乎沉默——同 docs/154 §三对 import 静默断供的告警）。价扫矩阵（如 price 0.5/0.75/1.0 × cadence）逐 seed 展布，取「export 看得见 & 金标不饿 & 穷镇仍有压力」的交集。

## 七、§0.8 判决：**YES —— export 首片实现前须 docs/41 §0.8 双路对抗外审 + 用户拍板**
**决定性理由（任一独立成立）：**
1. **export 强制改 #45（硬货币溯源）口径**：§四已证 export **无法**在不泛化 #45 的前提下落地（首次 export 即把 #45 打红）。#45 是硬不变量（HARD_IDS 含 45，两份），把它从「external 单向（import 贷入）」升级为「双向（import 贷入 − export 借出）」= **核心货币不变量口径变更**——与 E2a 折 external 进 #34 同一档、docs/155 §九确立的「核心 #34/#45 口径变更须 §0.8」纪律直接命中。
2. **export 让 external 从单调账户变成双向储备，激活 #35 外部非负臂 + 引入新守恒语义**：「external 非负 ⇒ export 收入 ≤ 累计 import 支出」是一条**新的守恒-语义不变量**，其失败模式（先收后出的**顺序**、affordable 上界算错、external 透支铸币）正是 §0.8 REFUTE 路专抓的 **BLOCKER-1 同类隐 bug**——docs/155 实测证过这类 bug 能「digest 逐字节不变 + #34 反把 bug 盖绿」，唯一守门是显式结构约束 + 对抗复核。
3. **docs 明文 defer**：docs/154 §四/§五 把「export 收钱 / 社交排除集 / 分布通胀 / #38-trade / 多镇域」整体列 **P4 deferred**、docs/151 §三「export 留到…P4」、docs/155 §八再确认——export 一直是**独立门控的后续决策**，非 import 首片的 additive 延伸。

**反方（为什么 export 不是「纯 additive 像 E1」）**：E1（import 货、不碰钱）确未走 §0.8；#38 的 export 减号臂（§三）确与 E1 加 import 加号臂同构、单独看是 additive。**但** export 同时改 #45 口径 + 引 external 双向语义（上两条），已越过「纯 additive」，落回「核心货币口径变更」档。⇒ **判决 YES 不动摇。**

**落地纪律（外审通过后，对称 docs/155 §五-七）**：泛化 #45（非新增 ID ⇒ HARD_IDS 不必 +1，但**须核对两份 HARD_IDS 仍一致**）+ #38 白名单加 "export" + `:225` 排除集加 "export" + #35 外部臂已在（复用）；**重烘三锚**（golden seeds+scenarios / modelpath / complement ledger——export 每日新增 `export` 货事件 + `external→town` pay 事件进 event_digest ⇒ modelpath 必移；ledger 须在 **committed 树**按新 game 树重烘，docs/155 §九教训「baton 自报重烘不实」）；off 门 2 轴实证补跑；held-out 13-30 改前/改后逐 seed 展布 + 负对照矩阵（#34/#35/#38/#45 各证判别力）。

## 八、边界：E-export 首片 vs P4 deferred
- **本片（E-export 首片）拟做**：一条 export lane（surplus 货，先收钱后出货选项 A′）+ external 双向闭环 + #38 export 减号臂 + #45 泛化（双向对账）+ #35 外部臂（复用）+ 社交排除集 +"export" + price/floor/cadence 标定 + 重烘三锚。
- **仍 deferred（P4，docs/154 §四）**：**多镇守恒域**（遍历账本账户注册表而非单镇；居民迁镇不双算）、**#38-trade 贸易原子性**（钱动货没动 = 假成功；TradeExecuted 原子事件 / escrow 在途态）、**分布通胀阈值 / town_coin 硬上限**（docs/151 §四.2 → E4）、**完整 #36**（event-first 单 reducer 逐账户完备性，本片 #45 泛化只是其 export 切片最小版）、**export 口岸落图**（port/dock world.objects + 精灵槽，同 E1 的 P1 defer）。

## 九、诚实边界
纯静态读码，**未跑 CI/bench/真机**。以下均**未验证、落地实测**：surplus 货候选（整洁是否物理有余量）、export 闭环在 60 天的活性（external 储备是否够 cadence 抽）、先收后出在 goto_tick 重演一致性、price/floor 标定不饿镇不暴富、#38 单加白名单符号自动正确、#45 双向泛化不削弱旧 import 判别力、方案 A′ 守 #34/#35。行号会腐烂（以 git 为准）。**本探索不实现不改码**——仅本 doc 提交至 worktree。
