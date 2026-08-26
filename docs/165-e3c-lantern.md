# 165 · E3c：逛灯会-attach treat 链（花灯→挂既有 `逛灯会`）· 判决：**合格但有结构边界——N=12 核心锚成立+pivot 兑现，但 N=16 池尺度门（ci.sh 4a）破，且修它必破核心 ⇒ 不换取**

> 复用 docs/164（E3b）已证的 pivot：新工业货挂【既有】动作消费、工位【只】广告 job-gated 产出。E3b 用 `闲聊`(coco→糕点)，本片换宿主与产者：`逛灯会`(qin→花灯)。
>
> **两句话结论**：①**N=12 上范式兑现**——留出 seeds 13-30 核心四货（口粮/柴薪/屋瓦 + E3b 已 land 的糕点）满足率 median Δ = **口粮 +0.009 / 柴薪 −0.011 / 屋瓦 +0.000 / 糕点 +0.031**（三升平一微降、与 E3a 全三货系统性下移方向相反）；NULL 对照证 `consume.逛灯会` 本身零（净负）稀释；VoiceGate/off-gate/#40@N=12/S0金标/DetGate/BackendGate/ModelPathGate **全绿**。②**但 N=16 破 ci.sh 4a（宏观池尺度门）**——花灯在 N=16 上 3/12 seed（2,3,10）跌破 SUPPLY_FLOOR（软门 9/12 < ≥11/12）。根因：**节日需求随人群规模涨（N=16 时 ×1.7），而单个池化产者的产量跟不上**；这是 production.json `_k1_measured` 记的口粮同类高-N 脆弱性。③**修 4a 必破核心**：把 qin 产量抬到能喂饱 N=16（W36）会让 qin 在 N=12 干 23-44 次、把口粮/糕点拽到 −0.03~−0.06 并灌 N=12，触发 STOP 条款 ⇒ **不换取**。实测 W28/W32/W36 三档：**没有一档同时满足 N=12 核心中性 与 N=16 4a**。
>
> **结构发现（本片最有价值的一条）**：pivot 的跨-N 稳健性取决于【宿主动作的需求-规模曲线】。`闲聊`（E3b：全镇稳态、分布式、随人口平滑涨）⇒ 糕点过 4a；`逛灯会`（节日集中式）⇒ 花灯破 4a。**精炼后的 pivot 规则：挂到一个需求【随人口平滑涨】的既有动作，而非集中在周期性事件上的动作。** 树保留在核心中性的 W28/cap6（已重烘、S0 绿、仅 4a 红），供协调者/用户拍板（接受 N=16 4a 边界为已知高-N 脆弱性，或把 E3c 改挂平滑宿主）。行号实读于本片提交树、以 git 为准。

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| **STEP 1** 宿主可行性：`逛灯会` 经 `_consume_for` 派发、且无既有 consume 货 | ✅ **是**——`逛灯会` 是 festivals.json 节日对象广告的 object-kind 动作（goals.json:19 明记『对象交互』）→ `_advance_object` → `_consume_for(ag,"逛灯会")` 泛型派发（Sim.gd:1518）；改前 consume 表无此键，故加 `consume.逛灯会` 即自动挂上、**零 Sim.gd 改动** |
| 为什么不复用 E3b 的 `闲聊` | consume[action] 是**单货结构**（Sim.gd:3464-3468，一个动作只挂一件货）；`闲聊` 已被糕点占（E3b），加第二件会相争 ⇒ 换一个【本就活跃、object-kind、经 _consume_for 派发、尚无 consume 货】的宿主。全镇唯一满足这四条的现成动作是 `逛灯会`（其余：玩耍/歇着/社交/喝咖啡已各挂一货；晒太阳 0 次从不选中；品茶/打磨/打坐 的室内家具 buildings.json 全 furnish="" 未实例化） |
| `逛灯会` 选中频率不随花灯库存变（no-dilution 保证） | ✅ 缺货不阻断（`_consume_for` 返回 false 只喂加价+社会后果，need 照在 use 分支补满 Sim.gd:1568）；`逛灯会` 由节日调度（day%7==3 且天气晴/阴，确定 f(day)）驱动，与花灯库存无关 |
| off-gate（删本片键 → S0 金标逐字节回 pre-E3c） | ✅ **12/12 逐字节**（把 production.json 回 HEAD → `Harness --seeds 1-12 --golden` = 金标一致 12/12 seed、含逐 tick 前缀链、S0 GATE PASS） |
| #40 花灯进判决、rate 落带、不灌绿上限臂、不破下限、dead_goods 不红 | ✅ **12/12**（seeds 1-12；花灯 rate 0.483-0.808 med 0.638、gated 12/12、never_short 0/12、below_floor 1/12=seed7 0.483 边缘） |
| 硬不变量（含 #01 无饿穿）/ det 两跑一致 | ✅ 硬 **12/12**、软通过率门 ≥11/12 过、det **3/3**（S0 GATE PASS，重烘后金标一致 12/12） |
| **★核心验收锚：留出 13-30 核心四货 rate 基本不动** | ✅ **成功**（median Δ 口粮 **+0.009** / 柴薪 **−0.011** / 屋瓦 **+0.000** / 糕点 **+0.031**；口粮 8↓9↑、柴薪 12↓6↑、屋瓦 7↓8↑3=、糕点 7↓11↑——**非 E3a 那种全下移**） |
| NULL 对照（qin=扎灯匠但删 consume.逛灯会）证 treat 本身零稀释 | ⏳ 见 §四 |
| 三锚重烘（golden seeds+scenarios / modelpath） | ✅ golden seeds 12/12 + scenarios 16/16 + modelpath random_full 4/4（max_n 46→43）重烘于本提交树（W28/cap6 定稿）。⚠ complement ledger 由**协调者**在 committed 树重烘（worktree 假绿） |
| 全 `tools/ci.sh`（除 4a 外全绿） | ✅ S0 PASS（金标 12/12、硬 12/12、det 3/3）· 4b(LOD) · 4c(DetGate 16/16) · 4d(BackendGate 8/8) · 4e(ModelPathGate 失败0) · **4f(VoiceGate) PASS ✅（0 对为空、37 动作全覆盖）** · #43 观察侧 · state_projection · 全单元/集成场景 · 视觉门。**唯 4a 红** |
| **★ci.sh 4a（N=16 宏观池尺度门 #40 软门）** | ❌ **破 9/12**（花灯在 N=16 seed 2/3/10 跌破 0.5，首违 seed2 花灯 0.46=到手36/想要78）——节日需求随人群 ×1.7 涨、单产者池化产量跟不上；同 production.json `_k1_measured` 记的口粮高-N 脆弱性。修它必破核心（见 §五.4a） |

⇒ **N=12 范式兑现、N=16 有结构边界**：pivot（挂既有动作消费 + 工位只广告 job-gated 产出）在 N=12 上重现成功，但节日集中式宿主的货撑不过 N=16 池尺度门（对比 E3b 平滑宿主 闲聊 的糕点过 4a）。

## 一、STEP 1 · 逛灯会-派发可行性（本片实读）

`逛灯会` 由 festivals.json 的**节日对象**广告（`灯会`：every_days 7 / offset 3 / weather_req 晴阴；对象 pos[31,24]、advertise `{action:逛灯会, need:fun, amount:62, duration:14}`）。它是全镇 fun 吸引力最高的一条（62 > 玩耍 55）。
- **`逛灯会` 恒是 object-kind**：节日对象经 WorldPatch spawn 进 town 平面，agent 选中后走 travel→use 的普通对象逻辑（Sim.gd:1500 `_advance_object`）。goals.json:19 独立佐证：『逛灯会' 是对象交互、**不写 event_log**』。⇒ 每一次 `逛灯会` 都走 `_advance_object` → use 相位调 `_consume_for(ag,"逛灯会")`（Sim.gd:1518）。
- **消费派发是泛型的**：`_consume_for` 查 `production.consume[action]`（Sim.gd:3464），缺键返回 true（天然不缺货）。⇒ 加 `consume.逛灯会={good:花灯,amount:1}` 即自动被派发、扣花灯、缺货走 `_shortage_fallout`，**零 Sim.gd 改动**（与 E3b 的 `闲聊` 同一条数据驱动路）。
- **单货结构 ⇒ 不能复用 `闲聊`**：`_consume_for` 的 `rec` 是单个 `{good,amount}`（Sim.gd:3464-3468），一个动作只挂一件货。`闲聊` 已被糕点占，故必须另择宿主。候选筛查（本片实读 map/interiors/festivals/room_templates/production 全部广告动作）：活跃且尚无 consume 货、又经 _consume_for 派发的，全镇**只有 `逛灯会`** 一个（玩耍→整洁、社交→整洁、歇着→话本、喝咖啡→豆子、闲聊→糕点 已各挂货；晒太阳 广告存在但被玩耍恒压、改前 0 次/seed；品茶/打磨/打坐 是 room_templates 的室内家具动作，而 buildings.json 的房间 `_furnish_note` 全 furnish=""、家具一件没放 ⇒ 这三个动作根本没被实例化）。
- **no-dilution 保证成立**：缺花灯时 `_consume_for` 返回 false，但既不 return 也不清 option，need 照在 use 分支补满（Sim.gd:1568）；`逛灯会` 的选中由节日调度（确定 f(day)）而非花灯库存决定 ⇒ **选中频率不随花灯库存变**（有灯照拿、没灯照逛+写 shortage）⇒ **不新增决策槽**。

⇒ 判决：**可行**，走 clean attach（零 Sim.gd 改动）。

## 二、STEP 2 · 设计（owns production.json 6 键 + voicebank 1 行）

复用 E3b 的键形状（docs/164 §二），唯一差别是宿主动作与产者：

```
+ start_stock.花灯 = 6
+ goods.花灯 { cap:6, spoil_per_day:0, blame:"扎灯匠", shortage_memo/claim/standing:-0.2 }
+ produce.扎灯匠 { good:"花灯", amount:4 }             ← 无 inputs（照抄咖啡师/糕点师形状）
+ consume.逛灯会 { good:"花灯", amount:1 }             ← ★挂既有 逛灯会(fun,节日)，不新加动作，免费
+ jobs.qin { title:"扎灯匠", action:"扎花灯", wage:3, shift:["dawn","day"] }
+ worksites[+1] counter_lantern { type:"摊位"(复用 counter 槽), area:"plaza", pos:[29,22],
    advertises:[ {扎花灯, job:扎灯匠, need:fun, amount:28, dur:24} ] }   ← 只一条、job-gated
+ voicebank.qin.扎花灯 = ["扎盏花灯，等月上来～","竹骨糊纸，慢慢就亮了。"]  ← ★VoiceGate（见 §五）
```

- **spare 居民**=qin（苏琴，浪漫散漫的街头琴师；12 agent − 9 有产职 = coco/fei/qin，coco 已被 E3b 占 ⇒ 余 fei/qin。花灯是节令手艺、配浪漫艺术人格，取 qin 而非医生 fei）；从零工转 `扎灯匠`，天然单持有人、不触 #41、不入 craft_credit（同 coco）。
- **type `摊位`** 复用 OBJ_SLOT_BY_TYPE 现有项（counter_stall/counter_pastry 同 type → counter 槽）⇒ **零 WorldView 改动、别名预算不动**（WorldView.gd:4378 三槽预算 bench5/counter4/desk2 全满，只能复用现有 type，不能新增）。
- **pos[29,22]**：广场 rect[28,21,8,6] 内、避开 counter_stall[32,22]/counter_pastry[31,23]/bench_1[30,23]/festival[31,24]/bench_sweepcart[29,25] 等；`audit_map.py` **PASS**（worksites 9→10、区归属+可达交互格+≥2 路线+全图仍连通）。
- **spoil_per_day=0 是关键标定**：花灯是耐存手艺货（同屋瓦/柴薪/豆子/话本）。第一版 spoil=1 实测灾难性——【周消费】的节令货被【日排水】在到达节日前就损耗殆尽（seed6 produced 42/spoiled 41/served 7、rate 0.17），且同时高 spoil 又 below_floor。改 spoil=0 后 rate 立刻回到 0.65-0.93 带内、0 below_floor（见 §三）。
- **免费消费**（不进 vendor 键、不收钱、不经 transfer）⇒ **硬 #34 全程一字不动**。
- **HARD_IDS 不动**：produce/consume/stock 都是已有 typed 通道，新货自动被 #38/#39/#40 覆盖，无需新不变量。

## 三、STEP 3 · #40 标定（seeds 1-12 × 60 天 × N=12 × backend=null）

需求侧是**既有 `逛灯会` 频率**（节日门控，实测 demand=逛灯会 attempts × 1 ≈ **26-69/seed**，天然 ≥20 门但**比 E3b 的闲聊 149-215 低且随节日天气波动更大**）。因需求固定且偏低，只标供给：工位吸引力 W（=qin 的扎花灯频率）、批量 A、cap、spoil。

| 配 | 批量 A | W | cap | spoil | 花灯 rate min/med/max | below_floor | never_short | 核心锚(13-30) 判 |
|---|---|---|---|---|---|---|---|---|
| b2_w34_cap8_sp1 | 2 | 34 | 8 | 1 | 0.171/0.560/0.780 | **5** | 0 | — | spoil=1 日排水打空周消费的库存 ⇒ 破下限×5 |
| b2_w34_cap6_sp0 | 2 | 34 | 6 | 0 | 0.654/0.837/0.926 | 0 | 0 | 口粮 **−0.028**(12↓) | rate 好，但 qin 干 22-35 次/seed 太重 ⇒ 面点师 −1.44/咖啡师 −2.06、**口粮系统性下移** |
| **b4_w28_cap6_sp0** | **4** | **28** | **6** | **0** | **0.483/0.638/0.808** | **1**(seed7 0.483) | **0** | **口粮 +0.009 / 柴薪 −0.011 / 屋瓦 +0.000 / 糕点 +0.031** ★选它 |

定稿 = **b4_w28_cap6_sp0**：批量 4、W28、cap6、spoil0、start6、逛灯会.amount1。
- ★**主杠杆是 qin 的工作【频次】、不是每次产量**：b2_w34 让 qin 干 22-35 次/seed（与 coco 同量级），其广场活动把面点师（口粮）与咖啡师（豆子）系统性压下去（口粮 median −0.028、走 E3a 的老路）；b4_w28 用【高批量+低 W】把 qin 压到 **5-15 次/seed**（held-out 均 ~10），单次产 4 件即够填 cap6、供上周消费，而广场活动足迹小到不再稀释核心 ⇒ 口粮翻回 +0.009。这正是 L2/E3a 记的机制：一条高吸引力活动的【决策槽/空间引力】总量与产者的**在场次数**成正比，压次数即松核心。
- **诚实边界**：seed7（1-12）花灯 rate 0.483 略破 0.5（软门容 1），seed13/seed19（13-30）rate 0.462/0.425 也在边缘（seed19 需求 80 特别高）——花灯自身落带的边缘、非核心货、且 held-out 不进 CI 判决。花灯 rate 中位 0.638 比 E3b 糕点的 0.739 略低，因节日需求波动大、供给按低-需求 seed 调不能同时喂饱高-需求 seed。

## 四、★STEP 4 · 核心验收锚：**成功**——留出 13-30 核心四货基本不动（本片的心脏）

留出 seeds 13-30（N=12，clean baseline（本片提交树、含 E3b 但无 E3c）vs 定稿 b4_w28）：

| 核心货 | median Δrate | mean Δ | down/up/flat | **E3a（docs/153，对照 FAIL）** |
|---|---|---|---|---|
| 口粮 | **+0.009** | +0.021 | 8 / 9 / 1 | −0.036（12/18 **下**） |
| 柴薪 | **−0.011** | −0.014 | 12 / 6 / 0 | −0.032（14/18 **下**） |
| 屋瓦 | **+0.000** | −0.002 | 7 / 8 / 3 | −0.028（14/18 **下**） |
| 糕点（E3b 基线货） | **+0.031** | +0.039 | 7 / 11 / 0 | （E3a 前不存在） |

**这不是 E3a 那种系统性下移**：口粮/屋瓦/糕点三货中位【升或平】，唯柴薪中位 −0.011（≈base 0.928 的 1.2%、0.12 个 seed 标准差）。E3a 是全三货 median ~−0.03、66-78% 同向下；本片方向【混合】。口粮——E3a 里被稀释最狠的那一格——在本片**升**（+0.009，9/18 上）。

**机制侧（留出 13-30 逐职位在班完成 mean Δ，定稿 b4_w28）**：扎灯匠(qin) **+10.1**（新产者、轻足迹）· 面点师 **+2.00** / 渔夫 **+0.67**（口粮两产者【双升】⇒ 口粮 rate +0.009）· 木匠 **+1.67** / 杂役 **+0.17**（柴薪产者升）· 泥瓦匠 **+2.44**（屋瓦产升，但 屋瓦←柴薪 input 链每窑吃 3 柴 ⇒ 柴薪被多耗、rate 微降 −0.011——这是既有货由货做的耦合、非 qin 稀释）· 糕点师 **+1.28**（糕点 +0.031）· 环卫工 **−2.11**（整洁，非核心、cleanliness 反馈货）· 咖啡师 −0.61 / 教书先生 −0.06（小）。⇒ 核心【产者】几乎全升、唯一显著降的是非核心的整洁——这是【轨迹重排】而非【全线压产】。对比 b2_w34（qin 27.6 次）的面点师 −1.44/咖啡师 −2.06：把 qin 的在场次数从 ~28 压到 ~10，核心从系统性压产翻回净升。

### ★NULL 对照——证 `consume.逛灯会` 本身零稀释
（同 §三 定稿 b4_w28 的产出侧，但删 `consume.逛灯会`、花灯成死货、逛灯会不吃它 ⇒ A/B 只差 consume 这一项。）

| 臂（均 qin=扎灯匠 b4_w28，vs clean baseline 13-30） | 口粮 | 柴薪 | 屋瓦 | 糕点 |
|---|---|---|---|---|
| WITH consume.逛灯会（定稿） | **+0.009** | **−0.011** | **+0.000** | **+0.031** |
| NULL：删 consume.逛灯会（花灯=死货） | **−0.069**（15/18 下） | −0.006 | −0.003 | −0.036 |

⇒ **NULL 的核心移动【更大】、方向全为负**（口粮 −0.069 vs WITH +0.009，糕点 −0.036 vs +0.031）。即：`consume.逛灯会`（本片真正的 pivot 机制）不但**零稀释、实为净负稀释**——挂上消费反而让核心【回升】。机制上可理解：删掉 consume 后花灯无人吃、库存卡在 cap6，stock_pull 让『扎花灯』失去吸引力 ⇒ qin 无产出出口、转而在广场做社交/玩耍等零散活动、以【无方向的在场】稀释核心；挂上 consume 后节日周期性抽空花灯 ⇒ qin 有稳定的补货节律、活动被【收进自己的工位】。⇒ 残余的核心移动全部来自【加一个产者=qin 换岗】这一**任何新货都不可避免**的项，而 pivot 机制本身净加零稀释。这条 NULL 比 E3b 的更强：E3b 的 NULL 与 WITH 都是小移动，本片的 NULL 明显更差 ⇒ 消费-attach 的价值不只是『不添乱』、而是『把新产者的足迹导入建设性通道』。

## 五、STEP 5 · off-gate + 移金标三锚重烘（本提交树）

- **off-gate（字节纯加法自证）**：✅ 把 production.json 回 HEAD（= 删 6 键）→ `Harness --seeds 1-12 --days 60 --golden` = **金标一致 12/12 seed（含逐 tick 前缀链）+ S0 GATE PASS**。⇒ 6 键是【删键即回滚】的纯加法。（voicebank.qin.扎花灯 是显示层、不进 Sim digest，off-gate 不受其影响。）
- **移金标三锚全动且可归因**（重烘于本提交树的定稿 b4_w28）：
  1. **golden seeds 段**（`Harness --seeds 1-12 --days 60 --bake-golden`）：12/12 seed digest/event_digest/chain 全移——花灯 produce/consume 事件进 event_digest、town_stock[花灯] 轨迹进批量 digest/chain。
  2. **golden scenarios 段**（`DetGate --seeds 1-4 --days 20 --bake-golden`）：4 track × 4 seed = 16/16 全移（硬 16/16、两跑 16/16、数据指纹一致）——同因。
  3. **modelpath_anchor**（`ModelPathGate --seeds 1-4 --days 8 --agents 12 --bake-anchor`）：random_full 4/4 seed digest 移 + 候选规模 **max_n 46→43**（扎花灯 job-gated 候选只加在 qin 自己决策上、未设新全局峰值；qin 从游荡零工转定点工位重排了全局峰值决策的社交候选数，landed 640→675 升）。ModelPathGate **PASS（失败 0）**。
- `_meta.rebake_history` 各补一条（golden / modelpath）。
- **HARD_IDS 未动**（additive 无新不变量，Invariants.gd 一字未改）。
- **VoiceGate**：qin 的 job-gated `扎花灯` 动作已补 `voicebank.qin.扎花灯` 两句（合其浪漫散漫人格）——本片吸取 E3b 的 VoiceGate 红（漏配 coco.做点心）教训，committed 树上 W28/cap6 全 CI 复验 **VoiceGate PASS ✅**（301 对 / 37 动作 / 0 对为空）。
- ⚠ **complement ledger 未在本 worktree 重烘**：worktree 的 complement-guard 过是【提交前假绿】（锚的 baked_game_tree 对不上未来的 commit）。按 brief，**协调者在 committed 树重烘 ledger + 跑 committed-tree 全 CI**（含 VoiceGate）。

### ★§五.4a · ci.sh 4a（N=16 宏观池尺度门）破——结构边界与「修它必破核心」的实测

跑全 `tools/ci.sh` 抓到一处红（其余门全绿）：**4a 宏观池尺度门（N=16 seeds 1-12，产出契约=宏观池 ×16/12、工作吸引力 ×1.125）**。#40 软门 **9/12 < ≥11/12**：花灯在 N=16 的 seed 2/3/10 跌破 SUPPLY_FLOOR（首违 seed2 花灯 0.46=到手36/想要78、断供7/60天）。

**根因（实测，非推断）**：`逛灯会` 需求是【节日集中式】——灯会每 7 天一次、人群到场随人口涨（B17 记 N=12 时 9.94 人/节日）。实测花灯需求 N=12 是 26-69/seed，N=16 涨到 **40-100/seed（×1.7）**；而供给侧 qin 是【单个池化产者】：批量随池 ×1.333，但 qin 的【在班次数】被 work_pull ×1.125 压着基本不随 N 涨（N=16 W28 下 qin 只干 6-15 次）。⇒ 供给 ×1.333 追不上需求 ×1.7。N=16 破带的两个 seed（5,10）实测是【产量受限】（qin 产 30-45 vs 需求 75-100），非【缓冲受限】⇒ 加 cap 治不了（cap8 实测 N=16 仍 2/12 破），只有加产量能治。

**「修它必破核心」实测（W 扫，cap8，N=16 4a vs N=12 核心锚 13-30）**：

| W（扎花灯吸引力） | N=16 4a（花灯 below_floor / 12） | N=12 核心锚 13-30 median Δ（口粮/柴薪/屋瓦/糕点） | N=12 花灯 #40 | 判 |
|---|---|---|---|---|
| **28（定稿）** | **2**（seed5 0.48 / seed10 0.37；cap6 时 3=seed2,3,10）→ **4a 破** | **+0.009 / −0.011 / +0.000 / +0.031**（核心中性 ✅） | rate 0.48-0.81 med 0.64、periodic short ✅ | 核心过、4a 破 |
| 32 | **0** → 4a 过 | **−0.061** / −0.020 / −0.030 / +0.016（**口粮系统性下、比 E3a −0.036 还狠**） | rate 0.78-1.0 med 0.96、偏灌 | 4a 过、**核心破** |
| 36 | **0** → 4a 过 | +0.0005 / −0.019 / −0.009 / **−0.029**（糕点下、qin 干 23-44 次） | rate 0.92-1.0、灌 | 4a 过、**核心破**（糕点） |

⇒ **没有一档同时满足 N=12 核心中性 与 N=16 4a**。抬产量（W）能过 4a，但 qin 在 N=12（需求低至 23-69）就过量：既把花灯灌到 0.9-1.0（丢 periodic-short），又让 qin 的广场足迹从 ~10 次涨到 20-44 次、把口粮/糕点拽下 0.03-0.06。⚠ 附一条【口粮锚是噪声主导】的诚实观察：口粮 median 跨三档是 +0.009→−0.061→+0.0005（**非单调**），说明 18-seed×N=12 的口粮锚被轨迹重排噪声主导、单档不可尽信；正因如此，**取足迹最轻（W28，qin ~10 次）的那一档最稳当地不扰核心**——这也是选它保留在树上的理由。

**判决**：按 brief 的 STOP 条款（核心系统性稀释=停、别硬上），**不把核心换给 4a** ⇒ 树保留 W28/cap6（核心中性、S0 绿、仅 4a 红），协调者/用户拍板。

### ★§五.结构发现 · pivot 的跨-N 稳健性取决于宿主的需求-规模曲线

E3b 的 `闲聊`（全镇稳态、分布式、~150-200 次/seed、随人口平滑涨）⇒ 糕点在 N=16 **过 4a**（ci.sh 4a 的 N=16 首违只点名花灯、没点糕点）。本片的 `逛灯会`（节日集中式、随人群到场涨得比人口快）⇒ 花灯 **破 4a**。⇒ **精炼 pivot 规则：新工业货应挂到一个需求【随人口平滑涨】的既有动作，而不是集中在周期性事件（节日/选举）上的动作。** 这条把 E3b 的「挂既有动作」细化成「挂既有【平滑需求】动作」，是 E3c 交付给下一棒的结构性一课。

## 六、诚实边界

- 只 backend=null headless。N=12 跑了核心锚（13-30）+ #40（1-12）；**N=16 跑了 4a（seeds 1-12）——破**（§五.4a）；N=24/60 未跑。
- 花灯需求是节日门控（逛灯会），比 E3b 的闲聊【低且波动大】（N=12 26-69 vs 149-215）⇒ #40 落带更难，N=12 rate 中位 0.638、1 个边缘 seed（seed7 0.483）略破 0.5（软门容 1）。
- **N=16 4a 破是本片的主边界**：不是花灯自身的落带噪声，是节日需求随人群规模涨、单池化产者跟不上的结构问题；修它必破 N=12 核心（W 扫三档实测，§五.4a），故不换取。
- 「口粮核心锚噪声主导」：18-seed×N=12 上口粮 median 跨 W 档非单调（+0.009/−0.061/+0.0005），故对单档口粮值不下强结论；干净的机制隔离由 NULL 对照（固定 W28、只差 consume）给出。
- 「决策槽 vs 空间引力」细分解未做；未跑真机/SLM/LOD。
- 「决策槽 vs 空间引力」的更细分解未做——但 pivot 判据（核心不系统性下移 + treat 零稀释）已由锚 + NULL 两条实测立住。
- 未跑真机/SLM/LOD。

## 七、附：证据文件（analysis/e3c/）

- `baseline_clean_s1-30.jsonl`：干净树（含 E3b、无 E3c）改前基线。
- `after_b4w28cap6_s13-30.jsonl`：定稿 b4_w28 改后留出 13-30（**核心锚主证据**）。
- `cal_b4w28cap6_s1-12.jsonl`：定稿 #40（seeds 1-12）。
- `cal_b2_w34_s1-12.jsonl` / `cal_b2_w34_cap6_sp0.jsonl`：#40 标定扫（spoil1 破下限 / spoil0 但 qin 太重）。
- `after_b2w34cap6_s13-30.jsonl`：b2_w34 的核心锚（口粮 −0.028，示范 qin 过重即稀释）。
- `null_nocons_s13-30.jsonl`：NULL 臂（删 consume.逛灯会、花灯死货）。
- **N=16 4a 证据**：`n16_cap8_s1-12.jsonl`（W28/cap8，2/12 破）· `n16_w32cap8_s1-12.jsonl`（W32，0/12 过）· `n16_w36cap8_s1-12.jsonl`（W36，0/12 过）——含 4a 的 N=16 花灯落带。（W28/cap6 的 N=16 见 `ci_full.log` 4a 段 [S0] N=16 行，seed 2/3/10 soft_fails[40]。）
- **W 扫核心锚**：`after_w32cap8_s1-30.jsonl`（口粮 −0.061 破）· `after_w36cap8_s1-30.jsonl`（糕点 −0.029 破）——证「修 4a 必破核心」。
- `ci_full.log`：committed 树 W28/cap6 全 `tools/ci.sh` 输出（除 4a 外全绿、含 VoiceGate PASS）。
- `parse.py` / `anchor.py`：只读分析脚本（UTF-8）。
