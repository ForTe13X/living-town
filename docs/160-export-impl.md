# 160 · AS5 车道 E-export 首片：货出→钱进（export 收钱 / external 双向闭环）· 移金标

> 接 E2a（docs/155，import 付费 external_coin 进 #34）。E-export = 钱跨镇边界【出账】侧首片：把镇里【过剩】的一种货
> 经唯一钱通道 `transfer("external","town",revenue,"export")` 先收钱进 town_coin、再经 `_stock_move(good,−sold_qty,"export")`
> 出港。**这是核心货币不变量 #45 口径变更（external 单向→双向）+ 新硬 #46（贸易原子性）**，已过 docs/41 §0.8 双路对抗评审
> （docs/158 = 两路收敛 SOUND_WITH_FIXES，外审升格 F7）。设计 docs/157。行号实读于本片提交树、以 git 为准。

## 〇、范围（严格照 docs/157 §八 / docs/158 §四放行）
**做**：一条 export lane（surplus 货豆子，A′ 先收后出）+ external 双向闭环 + #38 export 减号臂 + #45 双向泛化（进−出）
+ **新硬 #46 贸易原子性绑定（F7 命门）** + 社交排除集 +"export"（F3） + #35 外部臂（复用） + floor/price held-out 标定 + 重烘三锚。
**不做**（docs/157 §八 / docs/158 §四 P4 deferred）：多镇守恒域、完整 #38-trade escrow 在途态、完整 #36 event-first 单 reducer、
分布通胀阈值 / town_coin 硬上限（E4）、口岸落图（P1）、大 N export（floor 进 K1 rescale，本片显式限 N=12）。

## 一、改了什么（本片树实读）
| 文件 | 改动 |
|---|---|
| `game/data/logistics.json` | 新增 `export_lanes:[{good:豆子, batch:6, every_days:3, node:port_dock, floor:36, price_per:1, price_den:2}]`（复用 port_dock 节点）。off 门：段缺/空/无 price_per ⇒ 惰性。 |
| `game/scripts/Sim.gd` | `_logi_export()`（日界 `_nightly` 里排在 `_logi_import` 之后）+ `_export_fit()`（三上界预定 sold_qty）+ `_export_commit()`（**F1/F7 exact wrapper**：先 transfer 收钱→再 _stock_move 出货）。 |
| `game/bench/Invariants.gd` | 社交排除集 +"export"（F3）；#38 白名单 +"export"（减号臂）；#45 双向泛化（F6 guard 重构）；**新硬 #46 出口贸易原子性绑定**；HARD_IDS +46。 |
| `tools/gate_fixture_audit.py` | HARD_IDS 副本 +46（E1 教训：两份同步；实测 IDENTICAL n=31）。 |
| `game/scripts/Main.gd` | FEED_SKIP +"export"（export 货事件是 ledger 事件、不进社交播报；不影响任何 digest）。 |
| `game/bench/as5_*.gd` | 三支探针：surplus 选货(F4) / negctl 矩阵 / export 展布。 |

## 二、F1–F7 逐条落地 + 证据

### F1（命门·符号）— 显式正数 sold_qty + exact wrapper
`_stock_move(good,−N,"export")` 的 −臂返回**负** applied（`applied=-mini(-delta,cur)`, Sim.gd）。docs/157 §二字面
`revenue=applied×price/den` 会得**负值** ⇒ `transfer(amt<=0:return false)` **静默拒收每一次 export** ⇒ 货已出、钱没收。
**修法**：`_export_fit` 干算**显式正数** `sold_qty=min(batch, max(0,stock−floor), external×den/per)`；`revenue=sold_qty×price/den`；
`_export_commit` 是**无 await/回调的 exact wrapper**：`transfer("external","town",revenue,"export*<qty>")` 成功 ⇒ 才
`_stock_move(good,−sold_qty,"export")`；契约 `stock_delta==−sold_qty`（运行时 `absi(applied)!=sold_qty` push_error 留痕）。

### F7（新硬 #46 · 贸易原子性绑定）— 外审升格，首片必带非 P4
即便符号修对，若 pay(export) 与 stock(export) 不一一对应等量，#34/#38/#45 只各证钱账/货账自洽，证不出"这笔钱买的就是这批货"。
**#46 硬断言**（从 event_log 独立解）：① F6 货侧合法（export 事件 actor∈声明节点、good∈export_lane、target=town、件数>0、reason=export）；
② F7 原子绑定——把 export 相关事件（type=export 货事件 + note 前缀=export 的 pay）按 log 序抽出，必须**严格 pay,stock 交替**
（exact wrapper 先收后出 ⇒ 每对 pay 紧邻其后一条 stock），且**逐对 pay.qty==stock.qty**（pay/stock note 都编码 `export*<sold_qty>`）。

**★F1 免费流失现被 F7 抓住（负对照矩阵 as5_negctl_probe seed 1，实测）**：

| 负对照 | 施加 | #34 | #38 | #45 | #46 | 判别 |
|---|---|---|---|---|---|---|
| CLEAN | 真 export | ✅ | ✅ | ✅(external=10=进56−出46) | ✅(钱货一一绑定) | 基线全绿 |
| **NEG_F1_free** | `_stock_move(豆子,−5,"export")` 出货**不收钱** | **✅** | **✅** | ❌(external=10>应值5) | ❌(货事件无前导 pay/免费流失) | **★外审说的"全绿漏洞"(#34/#38 绿)被 #46+#45 抓** |
| NEG_F7_collect | 收钱不发货 | ✅ | ✅ | ❌ | ❌(pay 无紧随货) | #46+#45 抓 |
| NEG_F7_qty | 收 5 发 3 | ✅ | ✅ | ❌(external=5≠应值7) | ❌(pay.qty=5≠stock.qty=3) | #46+#45 抓"收 N 发 k" |
| NEG_34 | town_coin−5 | ❌ | ✅ | ✅ | ✅ | 只 #34 |
| NEG_38 | 直写 town_stock−5 | ✅ | ❌(豆子现存21≠账本26) | ✅ | ✅ | 只 #38 |
| NEG_45imp | 凭空 import 付款+5 | ✅ | ✅ | ❌(external=15>应值10) | ✅ | 只 #45 |
| NEG_35ext | external=−5 | ❌ | ✅ | ❌ | ✅ | #35 红 |
| **NEG_F2_cross** | phantom import(+5)+export(−5) 净 0 | ✅ | ✅ | **✅(被净额骗过)** | **❌(phantom export pay 无紧随货)** | **★F2：#45 盲区被 #46 补** |

`expected_matrix_ok=true`（seed 1 与赤字 seed 18 各一次）。**关键读数**：NEG_F1_free 下 #34/#38 全绿正是外审点名的"静默价值流失且全绿"，而 #46 与 #45 各自红——首片不 defer F7 是对的。

### F2（#45 跨边负对照）
NEG_F2_cross（phantom import +5 与 phantom export −5 净为 0、export lane 激活）：**#45 被净额骗过绿**（external 净不变、Σexport 从货事件统计=0），
而 **#46 红**（phantom export pay 无紧随货事件）。证 #46 补 #45 的对账盲区（cross-side cancellation）。

### F3（社交排除集 · 理由订正 #2-only）
`Invariants.gd` 社交排除集加 "export"。理由订正（docs/158 F3）：export 货事件 actor=port_dock（**非居民**）、target=town ⇒
只可能虚增 **#2「社交发生」accepted 计数**、**动不了 #3「无永久孤立」**（#3 遍历 S.agents 居民）——与 E1 import 的 #2-only 理由一致。

### F4（选货 held-out 标定 + 反馈耦合红线）
**选【豆子】**（物理库存 surplus 探针 `as5_surplus_probe.gd`，seeds 13-30×60 天实测）：
- 排除**反馈耦合货整洁**（`_clean_mult=stock/cap` 驱动广场吸引力，出口它退化清洁反馈——F4 红线）；
- 排除**供给紧货口粮/屋瓦/柴薪**（#40 满足率紧的三货，docs/157 §一.3 红线）；
- 豆子在非排除货里物理余量最足：`stock_med` 跨 13-30 mean~30/cap 45、**常年顶到 cap 45**（基线 N=12 豆子 7/12 seed 全年零缺货，是天然过剩货，撞 cap 的产量当前被 `_stock_move` 少收白丢——export 正是把这截**本会丢弃的余量变收入**，docs/144 §五 P4）；
- 豆子需求**定点**（仅 cafe，#40 detail 自陈"分母不随人口涨"）⇒ 固定 floor 在大 N 相对安全。
- 豆子改前 #40 满足率跨 13-30 **恒 ≥0.50**（一格没进 starved 列，纠 docs/155 记的 seed 18=0.419 旧数——树已移动，现 #40 对 13-30 全绿）。

**floor 逐货标定**：豆子最坏【多日净消耗】（任意窗口 `Σconsume−Σproduce` 的 Kadane 上确界）跨 13-30 = **21..39**（seed 22=39 最坏）、med ~28。
取 **floor=36**：贴近绝对最坏 39（留 3 的极小风险余量）、盖住典型最坏 ~28 有余、留 cap−floor=9 出港余量。
★**诚实边界**：36<39 ⇒ 极端 seed 最坏窗口理论上可让 export 多抽豆子 ≤3，但 held-out 13-30 改后 **#40 18/18 全绿、饿穿 0**——
这不是"结构上不饿镇"（**降级 docs/157 §一.3 的『结构』字样**，F4），是【标定 + held-out 实测】的不饿镇。

### F5（人口缩放 · 显式限 N=12）
export **只在 `prod_pool_num==prod_pool_den`（人口==base=12、K1 池倍率恰为 1）运行**，N≠12 惰性（`_logi_export` 第一行短路）。
理由：这是 export 首片，大 N 上 floor 是否够护本地消费未标定 ⇒ 显式 defer；限 N=12 使 **CI 4a 宏观池尺度门（N=16）完全不碰 export ⇒ 该门零风险**。
held-out 13-30 在 N=12 跑 ⇒ export 被实测（#40 18/18）。大 N export（floor 进 K1 rescale 或按定点需求标定）= 后续棒。

### F6（货侧合法 #44-analog + #45 空 import 守卫 + 回放）
- **#44-analog for export**：并入新硬 **#46** 第①臂（export 事件 actor∈声明节点、good∈export_lane、reason=export，镜像 #44 之于 import）。
- **#45 空 import lane_price 守卫重构**：把 import 项与 export 项**各自独立守卫**——export 项在 import lane_price 为空时**也计算**
  （旧式整段 guard 在 import 空时短路会吞掉 export 项）。
- **回放**：goto_tick 先收后出逐字节一致（见 §五）。

### F7 见上（新硬 #46）。

## 三、#45 双向泛化（核心货币口径变更）
旧式 `external == Σimport price` 的成立前提是"external 只被 import 贷入"；export 借出 ⇒ 首次 export 即打红。
改为双向：**`external_coin == Σ_import(_amt_of×p_imp/d_imp) − Σ_export(_amt_of×p_exp/d_exp)`**（逐笔整数地板，与运行时同口径）。
external 从 0 起、只被 import 贷入(+)/export 借出(−) ⇒ 此等式恒真。pay 良构双向：target=external 必 actor=town/reason=import；
actor=external 必 target=town/reason=export。**闭环有界**（docs/157 §二实证）：`transfer` 的 `from<amt:false` + #35 external≥0 臂
⇒ external 恒 ≥0 ⇒ 累计 export 收入 ≤ 累计 import 支出、镇对外净头寸恒 ≤0、**不能被泵富**。
实测：held-out 13-30 与 golden 1-12 的 #45 各 18/18、12/12 绿；seed 18 局末 external=0（export 把 import 贷入全额抽回 ⇒ 闭环满负荷）。

## 四、held-out 展布（改后、export 激活，`as5_export_probe.gd`）
| seed 段 | #40 | #34 | #35 | #45 | #46 | town_coin_min | wages_skipped | export 豆子量 |
|---|---|---|---|---|---|---|---|---|
| **1-12（金标 N=12）** | 12/12 | 12/12 | 12/12 | 12/12 | 12/12 | min=53 | **0/0** | mean 26/seed(max 54, sum 321) |
| **13-30（留出）** | 18/18 | 18/18 | 18/18 | 18/18 | 18/18 | min=0(seed18) | **仅 seed18 跳 1 次** | mean 28/seed(max 56, sum 512) |

**★分布通胀（F4 §六 goal② 不暴富）标定**：docs/155 记 import-only 下**结构性赤字镇 seed 18** town_coin_min=0/跳 10 次工资。
初标 price=1.0 时 export 把 seed 18 喂到 town_min=27/跳 0 次（抹平了蓄意 self-contain 压力）。**降到 price=0.5 + floor=36 后
seed 18 回到 town_min=0/跳 1 次工资**——**赤字镇仍跳工资**（goal② 达成），同时 export 仍可见（金标 mean 26、held-out mean 28/seed）。
残余：town_coin 硬上限=E4（docs/157 §五），本片靠标定+闭环夹。诚实边界：export 确实让 seed 18 从跳 10 次降到跳 1 次
（monetize 豆子余量的自然结果，闭环 external≥0 保证不能泵富），不是完全保留 import-only 的压力量级。

## 五、确定性 / 回放（红线#1）
- 纯整数：`revenue=sold_qty×price/den`、`sold_qty=min/max/mini/maxi`、调度 `day%every==0`，**零 randi/randf/Time/float**。
- **goto_tick 先收后出逐字节回放一致**（`as4_replay_probe.gd`，export 现在也在被重演的轨迹里）：脏 Sim（跑满一局、external 非零）
  goto_tick(7200) 与全新 Sim tick 到 7200 **digest+event_digest 逐字段相同 6/6 seed**、`econ_total0_stable=true`。
  external per-run 重置（start_new 在 econ_total0 快照前，E2a BLOCKER-1）承重、export ordering replay-safe。

## 六、off 门 2 轴（实证，非断言）
- **轴① 删 logistics.json**（export 惰性 ⇒ 逐字节回今天）：archive **pre-export 树 ce33072** + 本 export 树，**各删 logistics.json**，
  Harness seeds 1-4 days 60 ⇒ **[S0] digest/event_digest/chain/events 逐字节一致 4/4**（seed1 digest=2354668902、event_digest=7824884320643865142、events=3336，两树相同）
  ⇒ export 代码在 logistics 缺席时**完全惰性**、纯加法。
- **轴② export 无 price_per**（economy off 或 lane 无价 ⇒ export 惰性，**NOT 免费出港**，与 import 蓄意不对称 docs/157 §六）：
  config A（无 export_lanes，只 import）vs config B（export_lanes 在、删 price_per）⇒ Harness seeds 1-4 **digest 逐字节一致 4/4**
  （seed1 2840124/4092798599200292446，== 当前 import-only 金标）⇒ 无价 export **真惰性**、无无偿 stock 损耗。

## 七、重烘三锚（docs/41 §3 / docs/155 §六，移金标纪律）
- **golden_digests.json seeds 段**（`Harness --seeds 1-12 --days 60 --bake-golden`）：**12/12 全动**（seed1 事件 3436→3448=+12 export 事件；#34/#40/#45/#46 各 12/12）。
- **golden_digests.json scenarios 段**（`DetGate --seeds 1-4 --days 20 --bake-golden`）：**8/16 动**——export 是 **surplus-gated**：20 天短局里只在豆子累到 floor 以上且 external 付得起的 seed/track 触发，其余 8 个惰性=不动（硬 16/16、det 16/16）。
- **modelpath_anchor.json**（`ModelPathGate --seeds 1-4 --days 8 --agents 12 --bake-anchor`）：C 段 random_full 网格 event_digest 移动（A/B prompt 编码段未动——本片不碰 AIBackend）。
- **golden 移动归因（docs/41 §3：解释不了就停）**：每一处移动都归到【每个出港日新增一条 external→town pay(export) 事件 + 一条 export 货事件进 event_digest + town_coin/external_coin/豆子库存进批量 digest/chain】——无一处解释不了，不触发停机。
- 两份 `_meta.rebake_history` 各补一条（golden 19 条、modelpath 13 条）。

## 八、协调者 committed-tree finalize（务必）
**互补性 ledger（tools/gate_complement_ledger.json）本片【未重烘】**：本片改了 game/ ⇒ committed 树上 baked_game_tree≠HEAD:game
⇒ 互补性守卫在 committed 树会红(STALE) + ledger 不认识新 #44/#45/#46（worktree 复跑 `gate_complement_guard.py` 现只**告警不判红**、exit 0，
是 docs/155 §九点名的 **pre-commit 假绿**）。**协调者须在 committed 树**用全 godot exe 路径重烘 ledger（`gate_fixture_audit.py --run --bake-ledger`，
memory [[reference-local-godot-exe-path]]：Windows Python subprocess 必传全 exe 路径否则白跑）+ 跑全量 committed-tree CI。
（HARD_IDS 两份已同步 +46、实测 IDENTICAL；golden/modelpath 已重烘于本片工作树、内容锚与 commit 无关。）

## 九、诚实边界
- floor=36<绝对最坏净耗 39：不是结构保证不饿镇，是标定+held-out 实测（§二 F4）。
- export 让赤字 seed 18 从跳 10 次工资降到跳 1 次：闭环 external≥0 保证不泵富，但确实缓解了 import-only 的压力量级；town_coin 硬上限=E4。
- F5 显式限 N=12：大 N export 未标定（floor 缩放/定点需求）= 后续棒。
- #45/#46 是 #36（event-first 单 reducer 逐账户完备性）与完整 #38-trade escrow 的 export 切片最小版，非终态（P4）。
- port_dock 仍只声明不落图（P1）。
- 互补性 ledger 待协调者 committed-tree 重烘（§八）。
