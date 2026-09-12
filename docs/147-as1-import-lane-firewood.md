# 147 · AS1 经济棒 E1：柴薪进口 lane（车道 E 第一片）· 移金标

> 用户 2026-08-07 拍板经济车道 + 放行移金标。E1 = 一条 import lane：把一种【已有货】（柴薪）从『外部无限供给』确定性地到货进镇库 town_stock。**不碰钱**（transfer / economy.json / 硬 #34 全程一字不动）。行号实读于本片提交树、以 git 为准。

## 〇、实读复核：现有经济基础设施【已存在且成熟】（纠 docs/144 / 协调者断言）

逐条实读核对（docs/144 §〇 的坐标基本准确，下面记的是本片提交树的现值）：

| 事实 | 位置（本片树） | 复核结论 |
|---|---|---|
| 镇库 `town_stock`（整数件数，唯一通道 `_stock_move`） | `Sim.gd:310`（decl）/ `_stock_move` `Sim.gd:3351` / `_stock_take` `Sim.gd:3464` | ✅ 与 docs/144 记的 305/3325/3438 一致（本片在前面插了 8 行 logistics 声明+注释，故整体下移） |
| 硬 #38 库存账本自洽，能从 event_log 独立重算 | `Invariants.gd:675`（`_chk(38,…)`），账本重算体 `:652-670` | ✅ docs/144 记 671，准。**账外货臂**在 `:668-670`（town_stock 里不在 `production.goods` 的键判红）——柴薪在 goods 表，不触发 |
| 产出/日界钩子 `_nightly()` → `_stock_nightly()` | `_nightly` `Sim.gd:1626`，`_stock_nightly` `Sim.gd:3658` | ✅ docs/144 记 1578/3632，准。**import 结算就挂在 `_stock_nightly` 之后**（账本按天闭合） |
| 柴薪是【已声明的货】 | `production.json` goods.柴薪：`cap=80, spoil_per_day=0`，`start_stock.柴薪=30` | ✅ 是澡堂唯一燃料（consume.洗澡→柴薪）+ 屋瓦原料（produce.泥瓦匠.inputs.柴薪:3）；产者=杂役(65)/木匠(50) |
| K1 池 `scale.pool` | `production.json`：`["amount","inputs","cap","spoil_per_day","start_stock"]` | ⚠ **纠一处口径**：柴薪【不是】pool 列里的一项——pool 换的是 produce.amount / inputs / goods.cap / spoil / start_stock。柴薪作为一种货，它的 **cap/start_stock 随人口 ×(人口/12)、产者产量也随人口换尺度、需求随人口线性涨** ⇒ 说「柴薪已在池」在这个意义上成立。但**进口 batch 是一个新的、外部的量，不在 pool 里**（本片刻意不缩放，见 §一.5） |

⇒ reuse-first 成立：stock/money/worksite/consume/池化/缺货后果一根没重造。E1 真正新增的只有：① 一条抽象整数注入的 import 通道；② 一个物流节点【声明】（码头，本片只声明供 #44 溯源、不落图，见 §一.3）。

**对协调者断言的两处纠正/补充**（实读发现，docs/144 §六没写全）：
1. **`#38 的 +delta 集`不是唯一要改的判据**。`Invariants.gd:659/663` 的类型集+符号要加 `import`（同 produce 记正号）——这条 docs/144 §六写了。但 **`Invariants.gd:225` 的『社交事件』排除集也必须加 `import`**：import 事件 actor=物流节点 port_dock（非居民）、target=town，若不排除，硬 #02「社交发生」/#03「无永久孤立」会被一条到港记录喂饱（定向场景里哪怕零真社交也过门）。这条 docs/144 没提，是本片实读补的。
2. **真正的移金标风险是 #40 的【上限臂】而不是「灌绿」**。docs/144 §四.2 / 验收⑥ 说「进口不该把 #40 灌绿」。实读 #40 发现：#40 的下限臂 min-over-货 恒被**口粮**钉住（进口柴薪不动口粮 ⇒ 下限臂灌不绿）；真正会被进口触发的是 **`Invariants.gd:932` 的上限臂『缺货绝迹』**——若进口把柴薪推成【全年零缺货】、柴薪进 `never_short` 集，撞 `never_short*2 > gated_n` 判**红**。本片 batch 的定量正是被这条臂夹着定的（§四/§五）。

## 一、设计（最小、determinism-clean）

### 1. `game/data/logistics.json`（新文件，off 门）
```
{ nodes:[{id:"port_dock", type:"码头", area:"dock", pos:[33,8]}],
  import_lanes:[{good:"柴薪", batch:4, every_days:3, node:"port_dock"}] }
```
- **off 门**：缺文件 ⇒ `Sim._logi_on()==false`（`Sim.gd:751`）⇒ 进口/#44 每一处第一行短路 ⇒ 逐字节回到今天。加载在 `_load_data` 里先 `file_exists` 再读（同 production.json，免得 `_read_json` 的 `push_error` 把「删文件跑一遍」这条零扰动对照自己弄红）。
- `lint_data.py` 用 `glob("*.json")` 自动 parse 本文件（语法错会红），且**不在** REQUIRED 列 ⇒ 删掉它 lint 照过（off 门在 CI 里成立）。

### 2. 进口原语（`Sim._logi_import`，`Sim.gd:3677`）
挂在 `_nightly()`（`Sim.gd:1626`）里 `_stock_nightly()` 之后：
```
if _logi_on():
    _logi_import()
```
每条 lane 每到期日 `day % every_days == 0`（纯 `f(day)`）经唯一通道 `_stock_move(good, batch, "import", node, "import")` 记一批。
- **determinism（红线#1）**：无 `randi`/`randf`/`Time.*`，件数整数，lane 按数组书写序遍历 ⇒ 逐字节可回放。已实测同 seed 两跑逐字节相同（§二.2）。
- **撞 cap 少收**：`_stock_move` 自带（柴薪 cap=80）；柴薪 spoil=0 故到港不损耗。
- **放在 `_stock_nightly` 之后**：当天的消耗/spoil 已入账（今天的缺货/满足率由今天的实际存量定死），到港的这批算今晚库存、供明天用——进口不追溯改写今天。
- **不进 `prod_stats["produced"]`**：进口不是本镇产出（诊断口径分开；prod_stats 不入 digest，此选择对回放零影响）。

### 3. 物流节点 `port_dock`：E1【只声明、不落图】（**纠 docs/144 §六**）
docs/144 §六说「节点经 _compile_worksites 同族路进 world.objects」。**实读发现这在 E1 不可行**，故纠正：
- **WorldView 有成文契约**（`WorldView.gd:3939`）：`world.objects` 里只放 **advertises 非空**的对象——buildings/worksites 两条编译路都对空 advertises `continue`。而码头节点【无 advertises】（它不产候选、不做空间搬运，货物流是抽象整数注入，docs/144 §一），一旦进 `world.objects`，WorldView 的绘制循环解析不出精灵槽（`type='码头'` 不在 `OBJ_SLOT_BY_TYPE`，可借的 bench/counter/desk 槽都已到 `OBJ_SLOT_ALIAS_BUDGET`）⇒ `push_error` 品红占位框 ⇒ `ci.sh` 的 scan 判红。**实测**：第一版把它编译进 world.objects，`player_touch_test` 撞出 `[WorldView] 精灵槽无人认领：对象 'port_dock'…`、CI 红。
- 而 **WorldView + 它的 alias 预算是本片『绝不碰』区**（室内外绘制）⇒ 加精灵槽/改预算都越界。
- ⇒ **E1 只把节点声明在 `logistics.json` 的 `nodes[]`**（pos/area/type 是给 P1 留的坐标）；它的**落图渲染**（world.objects 项 + WorldView 的 `码头` 精灵槽 + alias 预算）交给 **P1 到货动画**那一片一起做（那才是加精灵的自然落点）。
- 本片节点的**唯一作用**：硬 #44 拿它校验进口 actor（`node_ids` 读的是 `logistics.json`、不是 `world.objects`）。⇒ 节点对 E1 的 Sim **零影响**（不入 world.objects、不入导航、不入 digest）。
- ⇒ 附带好处：`audit_map.py`（只审 map.json + worksites）与移金标解释都不用管这个节点——digest **只因柴薪进口**而动。

### 4. 判据改动（`Invariants.gd`）
- **#38 +delta 集**（`:659` 类型集 / `:663` 符号）：`import` 加进允许类型 + 记正号（同 produce）。否则镇库比账本多出进口那一截 ⇒ #38 红。
- **社交事件排除集**（`:225`）：加 `import`（见 §〇 纠正1）。
- **新硬 #44「进口溯源到声明的节点与货」**（`:1032`，入 `HARD_IDS`）：每条 import 事件 actor∈声明节点、货∈某条 lane 声明的货、target==town、件数>0、note 原因=="import"。结构照抄 #39（产出溯源），符号是「进货」侧；与 #38 互补——#38 守【账对不对得上】(绕 `_stock_move` 直写→红)，#44 守【进的货/港合不合法】(经通道但 actor/good 没声明→红)。off 门：缺文件→无 import 事件→恒过（真空为真，同 #39 之于 `_prod_on`）。

### 5. batch 不随人口缩放（判断 + 实测）
batch=4/every_days=3 ⇒ 60 天注入 ~80 件/seed（约柴薪需求 ~630/seed 的 ~13%）。**不进 `scale.pool`**：柴薪作为货，它的 cap/start_stock/产者产量/需求已随人口缩放；而『外部一船货』是固定外部量，人口大它就相对变小。这是**安全方向**——大 N 上进口相对需求趋小 ⇒ 不会把 #40 灌绿（§五实测 N=16/24/60 imports-ON #40 各 0/12 红、最差货 rate 仍贴 SUPPLY_FLOOR，N=60 上甚至略降）。E4（self-contain 弧）若要让进口随本地替代节流，是另一片的事。

## 二、三证据

### 1. off-gate（缺 logistics.json ⇒ 逐字节回到今天）
把 logistics.json 移走，`Harness --seeds 1-12 --days 60 --det 3 --golden`：
```
✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条）
=== S0 GATE: PASS ✅ (硬不变量 12/12 全绿, 软 ≥11/12 过, 活性 过, 金标 过, det 3/3) ===
```
⇒ 带全部代码改动、**缺 logistics.json**，digest+event_digest+逐 tick 链与【现 golden】逐字节相同。第一道自证成立。

### 2. 两跑一致（有 logistics.json ⇒ 逐字节可回放）
`Harness --seeds 1-12 --days 60 --det 12`：`同 seed 两跑摘要一致(批量+增量滚动+逐tick前缀链) 12/12`。

### 3. #38 绿 + 负对照
- **绿**：有 logistics.json，seeds 1-12 硬 #38 12/12、held-out 13-30 硬 #38 18/18（账本能重算含 import 的存量）。
- **负对照**（实测，临时把 `_logi_import` 的 `_stock_move(...)` 换成 `town_stock[good] += batch` 直写、跑 seeds 1-3）：
  `❌ #38 [硬]库存账本自洽 0/3  首违 seed 1: 对不上: 柴薪 现存=20 账本算得=−60`，而同一跑 **`✅ #44 3/3`**（绕过通道 ⇒ 没写 import 事件 ⇒ #44 看不到）。测完已还原。

## 三、探测包络（docs/41 §2.5）

### #38（库存账本自洽）
- **detects**（实测）：绕过 `_stock_move` 直写 `town_stock[柴薪]` ⇒ `#38 0/3`（现存 20 / 账本算得 −60）。
- **does_not_detect**：继承 #38 既有盲区（见 Invariants #38 注释）；#38 只查【账对不对得上】，不查【进的货/港合不合法】——那是 #44 的活（互补，见下）。
- **confidence**：1 个变异体（直写 town_stock），另 #38 本身在 30 seed × 60 天 + 留出 18 seed 上无假红。

### #44（进口溯源）
- **detects**（实测）：把 lane.node 指向未声明的 `ghost_port` ⇒ `#44 0/3`（`actor=ghost_port 非声明节点`），而同一跑 **`#38 3/3 绿`**（import 仍经通道、账仍平）。⇒ 与 #38 负对照互证：两条各查一件事。
- **does_not_detect**：good-arm（货必须是 lane 货）在正常运行下是**真空防御**——每条 import 都来自某条 lane ⇒ 货恒是 lane 货，只有【绕过 `_logi_import`】才能触发它（对称 #39 的「货必须申报」）。本片只实测了 node-arm（可经 config 触发）。
- **confidence**：1 个变异体（node-arm），off 门兜住短 horizon/随机后端/定向场景（缺文件→无 import 事件→恒过）。

## 四、留出种子 13-30 改前/改后展布（N=12，柴薪/屋瓦/洗澡）
数据：`analysis/as1/n12_supply_before_after.txt`（seeds 1-30 全表）。**进口柴薪蓄意松动，这是对的行为变更**：

- **柴薪满足率**（rate）：改前 min/med/max **0.609/0.889/0.980** → 改后 **0.765/0.935/0.978**（最紧的 seed 4 从 0.609 抬到 0.791）。
- **柴薪缺货天数**（shortage_days）：改前 2/9/27 → 改后 2/7/18；缺货事件（含洗澡侧）大幅降（seed 4 209→120、seed 6 134→31、seed 30 66→19，约腰斩）。
- **屋瓦满足率**：普遍升（seed 1 0.883→1.000、seed 4 0.650→0.876、seed 6 0.780→0.894）——因柴薪是屋瓦的原料，柴薪松 ⇒ 窑口料足 ⇒ 屋瓦产得出。
- **为什么是对的**：这正是 self-contain 弧 **P1『外部管够、本地稀薄』**的可见目标（docs/144 §五）。而且**没有把柴薪推成全年零缺货**：改后 **0/30 seed** 柴薪 shortage_days==0 ⇒ 柴薪从不进 `never_short` ⇒ #40 上限臂『缺货绝迹』**一格没红**（arm_high 0/30），本地产能仍是满足率主因。
- 硬不变量：held-out 13-30 改后硬 18/18、#40 软 18/18、饿穿恒 0（与改前同）。

## 五、N>12 离线：#40 不被灌绿（batch 未定太大）
seeds 1-12，各 N，imports ON（`analysis/as1/`）：

数据：`analysis/as1/largeN_40_before_after.txt`。

| N | #40 红 base→ON | 最差货 rate min base→ON | 柴薪 rate(ON) min/med/max | 柴薪 shortage_days(ON) | arm_high 触发(ON) |
|---|---|---|---|---|---|
| 16 | **1/12 → 0/12** | 0.490→0.723 | 0.807/0.917/0.966 | 3–17d | 0/12 |
| 24 | **0/12 → 0/12** | 0.558→0.606 | 0.640/0.917/0.951 | 4–27d | 0/12 |
| 60 | **1/12 → 0/12** | 0.564→**0.543** | 0.688/0.905/0.959 | 4–23d | 0/12 |

**结论：进口未灌绿 #40**——三条互相印证：
1. **最差货 rate 贴着 SUPPLY_FLOOR=0.50（0.72/0.61/0.54，不是 1.0）**，柴薪三个 N 上逐 seed 仍缺货（min 3-4 天）⇒ #40 仍有判别力（门是活的：base 侧就红过 N=16 口粮 0.49 与 N=60 seed 5 上限臂）。
2. **两处 base 红被消掉，都是 butterfly、不是灌绿**：N=16 base 的红是**口粮** 0.49（不是柴薪），进口柴薪不动口粮需求/产量、是轨迹扰动把它抬过 0.50；N=60 base 的红是 seed 5 的**上限臂『缺货绝迹』**（never_short=4），进口把它扰回 never_short=2（**更缺**，不是更绿）。
3. **N=60 上进口甚至让最差货 min 略降（0.564→0.543）**——固定 batch 在大 N 相对需求趋小（80/seed vs 柴薪需求 ~3150/seed ≈ 2.5%），主效应是轨迹重排而非系统性增供 ⇒ 与「灌绿」相反。

## 六、重烘金标锚（docs/41 §3）
**三份锚都烘**（docs/144 §六只写了两份——ModelPathGate 那份是实读补的，同 Wave E1 的教训 docs/47 §二-E1；实测只烘两份 ⇒ `ci.sh` 第 4e 步变红）：
- `golden_digests.json` **seeds 段**：`Harness --seeds 1-12 --days 60 --bake-golden`；**scenarios 段**：`DetGate --seeds 1-4 --days 20 --bake-golden`。
- `modelpath_anchor.json`（模型路径 random(full) 臂的世界轨迹）：`ModelPathGate.tscn --seeds 1-4 --days 8 --agents 12 --bake-anchor`。C 段 4/4 seed digest/event_digest/landed+候选规模移动（A/B prompt 编码段未动）。
- 三份 `_meta.rebake_history` 各补一条（2026-08-07 + 原因="E1 import lane 柴薪"）。
- **golden diff 说明**（`golden_before.json` vs 重烘后）：
  - **seeds 段 12/12 全动**（digest + event_digest + chain 三路同动）——首个分叉落在第 3 天首次到港。事件数**有涨有落**（seed 1 3336→3416、seed 5 3288→3523 涨；seed 3 3402→3293、seed 4 3392→3285 落——柴薪松 ⇒ 缺货事件变少），净变 ±100-200/seed，与「~20 条 import 事件 + 下游缺货/消费/加价轨迹移动」一致。
  - **scenarios 段 16/16 全动**（4 track × 4 seed；20 天里 day%3==0 到港 6 次）。
  - ⇒ 每一处 digest 移动都能归到【柴薪进口 + 其下游】，无一处解释不了（docs/41 §3：解释不了就停、不重烘——本片不触发这条）。

## 七、CI 判决行
✅**权威 landing CI（协调者 finalize，committed 树 `9d7b9dd`/game `f17ac3f` + 重烘三锚 + fresh ledger）**：`analysis/as1/ci_landed_verdict.txt` = **`=== CI PASS ✅ ===`**——**S0 GATE PASS 12/12（硬不变量含 #38/#44、新 golden 过、det 3/3）**、**ModelPathGate PASS**、互补性守卫 fresh（锚烘于 `8b85a7c`，35 不变量含 #44）、全门绿。
协调者独立移金标复核（committed 树）：① off-gate 缺 logistics.json → S0 金标 12/12 逐字节 = pre-E1 golden（纯加法）；② new golden 一致 + 两跑可回放；③ #38/#44 双负对照；④ 留出 13-30 柴薪↑/缺货腰斩/屋瓦↑=self-contain P1、#40 未灌绿。
⚠️协调者补一处 E1 未覆盖：E1 加了硬 #44 但漏更新 `tools/gate_fixture_audit.py` 的 `HARD_IDS` 副本（28→29）⇒ 重烘安全闸拒烘（正确：不给漏条锚固化基线）；协调者补 `+44` 后重烘成功。

## 附：未做 / 边界（诚实）
- 进口**免费到货**：本片一字不碰钱。钱跨边界（进口付费给「外部」）=E2，会触发硬 #34 架构决策（docs/144 §四.1），须 §0.8 外审后做。
- port_dock **本片只声明、不落图**（§一.3）：落图（world.objects + WorldView 精灵槽 + alias 预算）是 P1 到货动画的事——那是加「码头」精灵的自然落点，本片碰不得 WorldView。P1 落图后需给 `_compile_worksites` 家族补一条节点编译路 + 给 WorldView 加 `码头` 槽。
- batch 不缩放：大 N 上进口趋于可忽略——这是 E1 的安全选择，不是 self-contain 的终态（P3『本镇自给』要 import 对核心货节流到 0，是 E4）。
- #44 good-arm 是真空防御（见 §三）；audit_map 不审 logistics 节点（§一.3）——两条都是已知盲区，据实记着。
- **教训**：docs/144 §六「节点进 world.objects」+「brief 只写两份金标锚」两处都不完整——前者撞 WorldView 的 spriteless-object push_error（实测 player_touch_test 红），后者漏了 ModelPathGate 第三份锚（实测 4e 红）。两条都在本片实测中被 CI 抓出并纠正。
