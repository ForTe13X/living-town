# 155 · AS4 经济棒 E2a：import 付费 / external_coin 进 #34 守恒集（车道 E 第二片）· 移金标

> 用户 2026-08-08 拍板"E2 first"。E2a = 钱跨镇边界第一片：把 E1 的【免费到货】import lane 升级成【先付后到】——到货后经唯一钱通道 `transfer("town","external",cost)` 把货款搬进常驻的 `external_coin` 账户，而 `external_coin` 收进硬 #34 的守恒集。**这是核心不变量 #34 口径变更**，已过 docs/41 §0.8 双路对抗评审（docs/154 = SOUND_WITH_FIXES）。行号实读于本片提交树、以 git 为准。

## 〇、范围（严格照 docs/154 §五）
**只做**：import 付费 + `external_coin`（进 #34）+ 最小硬 #45（import 付费溯源）+ #35 补 external 非负臂 + price_per 标定 + 重烘三锚。
**不做**（docs/154 §四/§五 deferred）：#36 全 money 逐账户完备性折叠（E2b）、export 收钱、多镇守恒域、MoneyLedger 重构、`.coin=` 源码门禁、贸易原子性 #38-trade（P4）。**#34 判据本身一字未改**（只给 `money_total()` 的求和加一项 `external_coin`）。

## 一、实读复核（本片树，纠 docs/151 的行号腐烂）
| 事实 | 位置（本片树） |
|---|---|
| 唯一钱通道 `transfer(from,to,amt,reason,witnesses=[])` | `Sim.gd:3241`（`amt<=0`/`from<amt` 返 false→#35 非负结构保证；`_set_coin`×2 + 写 `pay` 事件 note=reason） |
| `_coin_of`/`_set_coin`（原只特判 `"town"`） | `Sim.gd:3253/3259` |
| `money_total()`（原 = `town_coin + Σagents.coin`） | `Sim.gd:3268` |
| `econ_total0` 开局快照 | `Sim.gd:848`（`town_coin` 注资 `:846` 之后） |
| start_new 里 `town_coin` per-run 重赋值 | `Sim.gd:846` |
| #34 金钱守恒（`money_total()==econ_total0`，econ_on 活门） | `Invariants.gd:606` |
| #35 货币非负 | `Invariants.gd:609` |
| E1 `_logi_import`（原丢弃 `_stock_move` 返回值） | `Sim.gd:3691`（改后含付费；`_import_fit` 新增于 `:3706`） |
| `_stock_move` 返回【真正落账 applied】件数 | `Sim.gd:3367`（撞 cap 少收→返回值 < 请求量） |

## 二、设计（最小、determinism-clean）

### 1. `external_coin` 收进守恒集（三处同棒，docs/154 §三）
- `Sim.gd:277` 新增 world 级 `var external_coin := 0`（`town_coin` 紧邻同族）。
- `_coin_of`/`_set_coin` 各加一条 `"external"` 分支（**照抄 `"town"`**，transfer 本体一字不改）。
- `money_total()` 求和加 `+ external_coin`（一行）⇒ `econ_total0` 自动含其初值 0。
- **#34 恒等（算术）**：守恒集 = `town_coin + external_coin + Σagents.coin`；transfer 每次只做集内 `from-=amt;to+=amt` ⇒ 集合总和是 transfer 的不变量 ⇒ `money_total()≡econ_total0` 结构恒真、判据形状不变、集合 +1 项。〔held-out 13-30 实测 #34 18/18 绿〕

### 2. 🔴 BLOCKER-1：`external_coin` per-run 重置（硬红线#1，docs/154 §二.1）
`Sim.gd:846` 后、`econ_total0 = money_total()` 快照（`:848`）**之前**，镜像 `town_coin` 加 **`external_coin = 0`**。
- **为什么是命门**：`goto_tick`（`:1146`）反复调 `start_new` 重演；import 付费让 `external_coin` 局末非零（实测 56~60）。若不清零，第二遍 `econ_total0 = money_total()` 把上一局残值算进基准。
- **实测证据**（`analysis/as4/replay_*.txt`，`as4_replay_probe.gd`）：一个跑满一局（external=56）的【脏】Sim `goto_tick(7200)` 后 `econ_total0=204`、`external_coin=28`、`town_coin=110`、digest=3097185526，与全新 Sim 逐字段相同（4/4 seed `match=true`、`econ_total0_stable=true`）。
- **负对照**（临时注释掉 `external_coin = 0` 重跑）：`goto_tick` 后 `econ_total0` 被污染 **204→260**、`money_total`→260、`external_coin`→84（28 fresh + 56 残）、`match=false`。⚠**关键发现**：此 bug 下 **digest 逐字节不变**（3097185526，external 不驱动事件），且 **#34 仍绿**（260==260，两侧同带残值）——正是 docs/154 §二.1 说的『#34 反把 bug 盖绿』。⇒ 金标/digest/#34 三者都看不见它，**唯一的守门就是这条显式重置 + 状态级回放核对**。

### 3. import 付费（选项 A 先付后到，docs/151 §三）
`_logi_import`（`Sim.gd:3691`）：付费门 = `_econ_on() and price_per>0 and price_den>0`。
- 门开：`_import_fit(good,batch)` 干算这批实际能到多少（`min(batch, cap−cur)`，纯读、与 `_stock_move` +delta 臂同一条 cap 逻辑）⇒ `cost = fit × price_per / price_den`（整数地板、无浮点）。**选项 A**：`fit<=0` 或 `town_coin<cost` ⇒ 当天不到货（continue），无免费货偷渡。付得起 ⇒ `applied = _stock_move(...)`（==fit）⇒ `transfer("town","external", applied×price_per/price_den, "import")`。
- 门关（缺 economy / lane 无 price_per）⇒ 回 E1【免费到货】的原路径（`_stock_move` 直接调）。
- **接住 `_stock_move` 返回值**（原 `:3691` 丢弃）：撞 cap 少收 ⇒ applied 少 ⇒ 同步少付、不买空气。

### 4. price_per 标定 = **3/4 = 0.75 钱/件**（AS4 实测，纠 docs/154『盈亏平衡≈0.8』的【理由】）
定价 `cost = applied × price_per / price_den` 存 `logistics.json` 的 lane（就近、off 门语义清）。`price_den` 是分数定价旋钮（避浮点、保确定性）。

**docs/154/151 的静态断言错在哪**：它假设 town 只有 `town_start=60` 无余量、盈亏平衡≈0.8。**实测（`as4_econ_probe.gd`，base=免费到货）**：吃饭收入 > 做活工资 ⇒ 绝大多数 town 60 天**净盈余**，`town_coin` 从 60 长到 104..161（N=12 seeds 1-12 逐 tick 不跌破 60、`econ_total0=204`）。⇒ N=12 最紧 seed 的『抽干到 0』真实盈亏平衡 ≈ 104/80 ≈ **1.3 钱/件**，远高于 0.8。

**取 0.75 的理由**：≈docs 的 0.8 直觉、稳在真实盈亏平衡 1.3 之下留余量。价扫（1 / 0.75 / 0.5，见下表）确认 N=12 金标在三档都健康；取 0.75 = 对穷镇施加**有意义的 self-contain 压力**又不勒死金标。

| price | N=12 金标 town_coin_min / wskip | 到货活性 | 留出 13-30 最紧 seed18 min/wskip |
|---|---|---|---|
| 1.0   | 19 / 0 | 全 60 天到第 59 天 | 0 / 16 |
| **0.75（选定）** | **38 / 0** | **全 60 天到第 59 天** | **0 / 10** |
| 0.5   | 55 / 0 | 全 60 天到第 59 天 | 0 / 3 |

### 5. 🔴 BLOCKER-2：最小硬 #45（import 付费溯源，docs/154 §二.2/§五）
`Invariants.gd:1038` 新增硬 #45：**`external_coin` 在 import 首片是唯一收款方、单调只增**（export=E2b）⇒ 现值必恰等于所有 import 事件按 lane price 折算的应付款之和：`external_coin == Σ_import _amt_of(note)×price_per/price_den`（逐笔整数地板，与运行时同口径）+ 每笔 `pay`(target=external) 必 `actor=="town"`、`reason=="import"`。跨 economy×logistics×event_log×运行时 external 四方对账。
- **与 #34/#44 互补**：#34 守【总量守恒】、#44 守【进的货/港合法】、#45 守【付的款有 import 撑且额对】。
- **off 门**：economy 关 或无 price_per ⇒ 无付费 ⇒ external==应付==0 ⇒ 恒过（真空为真）。
- **同步两份 HARD_IDS**（docs/147 §七 教训）：`Invariants.gd:1399` 的 `const HARD_IDS`（+45）+ `tools/gate_fixture_audit.py:71` 的副本（29→30 条）——`_check_hard_ids` 现读现比、对得上。

### 6. #35 补 external 非负臂（docs/154 §三）
`Invariants.gd:609` 加 `and S.external_coin >= 0`（对称 town）。import 首片 external 单调增暂不可达负，零成本、防 export/选项B 未来某棒凭空铸币。

## 三、负对照（证 #34/#45/#35 各有判别力，`as4_negctl_probe.gd`，`analysis/as4/negctl_s1.txt`）
期望矩阵实测全中（`expected_matrix_ok=true`）：
- **CLEAN**：#34/#35/#45 全绿（external=56 应付=56、总量204基准204）。
- **NEG_34**（直接 `town_coin−=5` 漏贷 external）⇒ **#34 红**（总量199基准204）、**#45 绿** ✅。
- **NEG_45**（凭空 `transfer("town","external",5,"import")`）⇒ **#45 红**（external=61 应付=56）、**#34 绿**（transfer 守恒）✅ ——证 #45 抓的正是 #34 抓不到的那类（凭空付款/额不符）。
- **NEG_35ext**（合成 `external_coin=−5`）⇒ **#35 红**（外部=−5）✅。

## 四、off 门 2 轴矩阵
- **轴① 删 logistics.json**：带全部代码改动、缺文件 ⇒ `_logi_on()==false` ⇒ import/付费每处第一行短路 ⇒ 逐字节回今天（与 E1 的 off 门同，继承实测）。
- **轴② logistics ON + economy OFF（或 lane 无 price_per）**：付费门 `_econ_on() and price_per` 关 ⇒ 回 E1【免费到货】。**实测**：把 price_per 拿掉跑 `Harness --seeds 1-12 --days 60 --det 3 --golden`（对**当前 E1 golden**，重烘前）= **`金标一致 12/12 seed（含逐 tick 前缀链）`、`S0 GATE PASS ✅`**（`analysis/as4/offgate_noprice_s1-12_d60.txt`）⇒ external_coin 全 0、付费路全短路时逐字节 == E1，纯加法、无扰动。

## 五、留出种子 13-30 改后展布（N=12，price 0.75）
数据：`analysis/as4/pay3_4_s1-30.txt` / `base_cashflow_s13-30.txt`。
- **N=12 金标 seeds 1-12**：`town_coin_min 38..60`、`wages_skipped 全 0`、柴薪 import **全 30 seed 持续到货至第 59 天**、付款 50..60。**不枯竭、活性足**。
- **留出 13-30**：`town_coin_min 0..60`、`wages_skipped 0..10`（合计 10，**全落在 seed 18 一个种子**）。唯一被压到 min=0 的 **seed 18 是结构性赤字镇**：免费到货下 town_coin 也只有 min=29/末 42（<60 起点，工资天然>饭钱、60 天净亏 −18）。import 付费把它推到 0 并跳 ~10 次工资——**这正是选项 A 蓄意的 self-contain 压力『穷镇进不起口』**（docs/151 §四.4），非标定失败；且它的 import 仍全到货到第 59 天（external=60=全 80 件付清）。
- **硬不变量**：seeds 1-12 硬 12/12（含 #34/#35/#45）、held-out 13-30 硬 #34/#45 各 18/18。

## 六、重烘三锚（docs/41 §3 / docs/147 §六）
**三份锚都烘**（`analysis/as4/bake_*.txt`）：
- `golden_digests.json` **seeds 段**（`Harness --seeds 1-12 --days 60 --bake-golden`）：**12/12 全动**（digest+event_digest+chain 三路同动）；**scenarios 段**（`DetGate --seeds 1-4 --days 20 --bake-golden`）：**16/16 全动**（4 track×4 seed，20 天里 day%3==0 到港 6 次、每次一条 pay）。
- `modelpath_anchor.json`（`ModelPathGate --seeds 1-4 --days 8 --agents 12 --bake-anchor`）：C 段 `random_full` 网格 4/4 seed 的 `event_digest/inv_digest` 移动（A/B prompt 编码段未动——本片不碰 AIBackend）。
- **golden 移动归因（docs/41 §3：解释不了就停）**：每一处 digest 移动都能归到【每个 import 日新增一条 `town→external` 的 pay 事件（进 event_digest）+ town_coin/external_coin 状态变化（进批量 digest/chain）+ 极紧穷镇的 wage-skip 下游轨迹重排】——无一处解释不了，本片不触发停机条款。
- 两份 `_meta.rebake_history` 各补一条（golden 18 条、modelpath 12 条，原因="E2a import 付费 external_coin+#45"）。

## 七、CI 判决行
**本片 worktree 自测（重烘三锚后，全绿）**：`bash tools/ci.sh` = **`=== CI PASS ✅ ===`（CI_EXIT=0，全程 1312s）**，`analysis/as4/ci_full.txt`。逐门：
- **S0 GATE PASS ✅**（硬不变量 seed 12/12 全绿【含 #34/#35/#45】、软通过率 ≥11/12 过、活性过、**金标过**【新烘 seeds 段 12/12 逐字节】、det 3/3）；
- **DetGate PASS ✅**（硬 16/16、两跑一致 16/16、**金标 16/16 可比**【新烘 scenarios 段】）；
- **ModelPathGate PASS ✅**（失败 0，比对新烘 modelpath_anchor）；
- 宏观池尺度门（N=16）/ LOD-VERIFY / VoiceGate / AA3 #43 回归门 / 2f 互补性守卫 / state_projection / story_test(193s) / goals_test(69s) 全 PASS。
- ⚠ 互补性守卫在 worktree 自测里**已过**（HARD_IDS 两份同步 +45、gate_complement_ledger 锚未牵动）；协调者仍应在 committed 树重烘重跑（`gate_fixture_audit` failclosed 对 committed 锚，docs/147 §七）。

## 八、附：未做 / 边界（诚实）
- **#36 全 money 逐账户完备性折叠 = E2b**（docs/154 §一 GPT-5 Pro principled 终态，含 event-first 单 reducer + MoneyLedger 重构）。本片 #45 是它的 import-切片最小版：只对账 external 一个账户、只守 import 流，**假设 external 只被 import 贷入**（export 才有借出）——这条假设 E2b 打破时 #45 须升级为 #36。
- **export 收钱 / 多镇守恒域 / #38-trade / 分布通胀阈值** = P4（docs/154 §四）。
- **price_den 分数定价的整数地板**：applied 极小时（撞 cap 只到 1-2 件）cost 可能地板到比例略低甚至 0——确定性、守恒忠实（#45 同口径重算恒等），是"就低不就高"的良性取整，据实记着。
- `port_dock` 仍**只声明不落图**（E1 §一.3 未变，落图=P1）。
- **诚实纠错**：docs/154/151 的『盈亏平衡≈0.8/price_per≥1 抽干 town』是**静态读码的误判**——漏了 town 的吃饭净收入，真实 N=12 盈亏平衡≈1.3；本片以实测 base 现金流 + 价扫订正（§二.4）。
