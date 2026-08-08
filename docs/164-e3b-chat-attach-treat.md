# 164 · E3b：闲聊-attach treat 链（糕点→挂既有 `闲聊`）· 判决：**成功——核心三货基本不动，pivot 兑现**

> docs/153（E3a）实测证伪了「新加一条 town 平面 treat 动作干净」这句断言：新动作加 60-80 决策槽/seed，**系统性稀释核心产出约 0.03 中位**（口粮/柴薪/屋瓦 66-78% 的 seed 下移）。§六.1 建议的 pivot：把 treat 消费挂到**既有**的 `闲聊` 动作而非新加动作。本片实现了这个 pivot、标定过、按 docs/153 §四 的方法量了核心验收锚。**结论是肯定的**：留出 seeds 13-30 上口粮/柴薪/屋瓦满足率 median Δ = **+0.041 / −0.001 / +0.006**（两升一平），与 E3a 的全三货系统性下移**方向相反**；一条 NULL 对照证明 `consume.闲聊` 本身零稀释。三锚已在本提交树重烘、CI 三门全绿。行号实读于本片提交树、以 git 为准。

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| **STEP 1** `闲聊` 是否经 `_consume_for` 数据驱动派发 | ✅ **是**——object 动作 → `_advance_object` → `_consume_for(ag,"闲聊")` 泛型派发（Sim.gd:1518）；`consume.闲聊` 自动挂上、**零 Sim.gd 改动** |
| `闲聊` 选中频率不随糕点库存变（no-dilution 保证） | ✅ 缺货不阻断（need 仍在 use 分支补满 Sim.gd:1568；`_consume_for` 返回 false 只喂加价+社会后果）；`闲聊` 恒是 object-kind、绝不是 social-kind 候选（`_social_candidates` 只吐 greet/give/gossip/… 从无 闲聊） |
| off-gate（删本片键 → S0 金标逐字节回 pre-E3b） | ✅ **12/12 逐字节**（含逐 tick 前缀链） |
| #40 糕点进判决、rate 落带、不灌绿上限臂、不破下限、dead_goods 不红 | ✅ **12/12**（seeds 1-12；糕点 rate 0.605-0.918、gated 12/12、never_short 0/12、below_floor 0/12） |
| 硬不变量（含 #01 无饿穿）/ det 两跑一致 | ✅ 硬 **12/12**、det **3/3** |
| **★核心验收锚：留出 13-30 口粮/柴薪/屋瓦 rate 基本不动** | ✅ **成功**（median Δ **+0.041 / −0.001 / +0.006**；口粮 12/18 升、柴薪 9/9 平、屋瓦 10/18 升——**非 E3a 那种全下移**） |
| NULL 对照（coco=糕点师但删 consume.闲聊）证 treat 本身零稀释 | ✅ 同标定 b7_w44 A/B：NULL（无 treat）核心 Δ −0.001/−0.028/−0.018 ≥ WITH-consume +0.024/−0.010/−0.011 ⇒ 残余来自「加一个产者」不可避免项，非 treat |
| 三锚重烘（golden seeds+scenarios / modelpath）+ 全 CI | ✅ 见 §五（复核者/协调者再于 committed 树重烘 complement ledger） |

⇒ **pivot 兑现**：把 treat 挂在既有 `闲聊` 上，避开了 E3a 的系统性核心稀释。docs/153 §六.1 的两条 ⚠ 未验点（`闲聊` 是否经 consume 派发 / 频率是否不随库存变）**都实测成立**。

## 一、STEP 1 · 闲聊-派发可行性（docs/153 的两条 ⚠ 未验点，本片实读）

`闲聊` 由**对象**广告，全镇两处：`counter_1`(吧台·cafe·map.json) 与 `cafe1f_counter`(咖啡吧台·interiors.json)，都是 `need=social`。option 分派（Sim.gd:1461-1465）：
```
match opt.kind: "social"→_advance_social  "attend"→_advance_attend  _→_advance_object
```
- **`闲聊` 恒是 object-kind**：`_object_candidates`（Sim.gd:2095）按广告 action 名建 `kind:"object"`；`_social_candidates`（2129-2242）建的动作是 greet/give/gossip/confide/leak/discuss/invite/confront/apologize/endorse/rally_oust/aid —— **没有 `闲聊`**。⇒ 每一次 `闲聊` 选中都走 `_advance_object`。
- **消费派发是泛型的**：`_advance_object` 在 use 相位调 `short = not _consume_for(ag, opt["action"])`（Sim.gd:1518），`_consume_for` 查 `production.consume[action]`（3464），缺键返回 true。⇒ **加 `consume.闲聊={good,amount}` 即自动被派发、扣糕点、缺货走 `_shortage_fallout`，零 Sim.gd 改动**（与 E3a 的 `吃点心` 同一条数据驱动路）。
- **no-dilution 保证成立**：缺糕点时 `_consume_for` 返回 false，但（Sim.gd:1513-1518）既不 return 也不清 option，need 照在 use 分支补满（1568）；false 只用于①加价②社会后果。⇒ `闲聊` 的**选中频率不随糕点库存变**（有糕点照吃、没糕点照闲聊+写 shortage）⇒ **不新增决策槽**。这正是 pivot 相对 E3a（新动作=60-80 新决策槽）结构上不稀释核心的根据。

⇒ 判决：**可行**，走 clean attach（零 Sim.gd 改动）。

## 二、STEP 2 · 设计（owns 仅 production.json，6 键）

复用 E3a 已证的产出侧（docs/153 §二），**唯一差别、也是整个 pivot 的心脏**：消费挂既有 `闲聊`、工位【只】广告 job-gated 的 `做点心`（不加任何 town 平面消费动作）。

```
+ start_stock.糕点 = 12
+ goods.糕点 { cap:20, spoil_per_day:1, blame:"糕点师", shortage_memo/claim/standing:-0.2 }
+ produce.糕点师 { good:"糕点", amount:6 }          ← 无 inputs（不吃任何 core 货，照抄咖啡师形状）
+ consume.闲聊 { good:"糕点", amount:1 }            ← ★挂既有 闲聊(social)，不新加动作，免费
+ jobs.coco { title:"糕点师", action:"做点心", wage:3, shift:["dawn","day"] }
+ worksites[+1] counter_pastry { type:"摊位"(复用 counter 槽), area:"plaza", pos:[31,23],
    advertises:[ {做点心, job:糕点师, need:fun, amount:48, dur:24} ] }   ← 只一条、job-gated
```

- **spare 居民**=coco（12 agent − 9 有产职 = coco/fei/qin；coco 天然单持有人、不触 #41），从零工（做活/看摊，零产出）转 `糕点师`。
- **type `摊位`** 已在 `OBJ_SLOT_BY_TYPE`（WorldView.gd:4327-4335，→counter；counter_stall 同 type），别名预算 counter=4 已满但**复用现有 type ⇒ 不加新 type ⇒ 断言不动、零 WorldView 改动**。
- **pos[31,23]**：广场 rect[28,21,8,6] 内、避开 bench_1[30,23]/arcade_1[33,24]/counter_stall[32,22]/节日灯笼锚[31,24]；`audit_map.py` **PASS**（worksites 8→9、区归属+可达交互格+≥2 路线+不切图）。
- **免费消费**（不进 vendor 键、不收钱、不经 transfer）⇒ **硬 #34 全程一字不动**。
- **HARD_IDS 不动**：produce/consume/stock 都是已有 typed 通道，新货自动被 #38/#39/#40 覆盖，无需新不变量（绕开 E1 的 HARD_IDS 坑）。

## 三、STEP 3 · #40 标定（复用 docs/153 §二 扫法；seeds 1-12 × 60 天 × N=12 × backend=null）

需求侧不再是「新动作的吸引力」而是**既有 `闲聊` 频率**（实测 demand=闲聊 attempts × 1 ≈ **149-215/seed**，天然远 ≥20 门），所以**只标供给**让糕点周期性短。因需求固定且偏高，需求侧那条 E3a 杠杆（吃点心.amount）在这里不存在——改扫工位吸引力 W（=coco 的做点心频率）与批量 A。

| 配 | 批量 A | W（做点心） | 糕点 rate min/med/max | below_floor | never_short | #40(seeds1-12) | 判 |
|---|---|---|---|---|---|---|---|
| b6_w44 | 6 | 44 | 0.424/0.711/0.858 | **1**(seed7 0.424) | 0 | 11/12 | seed7 低-work→破下限 |
| b7_w44 | 7 | 44 | 0.600/0.786/0.869 | 0 | 0 | 11/12 | seed10【核心货】灌绿上限臂（非糕点） |
| b7_w40 | 7 | 40 | 0.478/0.661/0.753 | **2**(seed9,12) | 0 | 10/12 | W 太低→coco 少做→两 seed 破底 |
| **b6_w48** | **6** | **48** | **0.605/0.739/0.918** | **0** | **0** | **12/12 ★** | **★选它**：高 W 抬齐低-work seed 的下限、低批量避免上限灌绿 |

定稿 = **b6_w48**：批量 6、做点心 W48、cap20、spoil1、start_stock12、闲聊.amount1。★W（做点心吸引力）是主杠杆：它设 coco 的做活【频率】、抬它把低-work seed 的下限抬齐；批量 A 设【每次产量】、压它避免高-work seed 把 rate 顶过 0.9。b7_w44 的 seed10 上限臂红是【核心货】屋瓦/豆子/话本/整洁在那条轨迹上转为全年不缺（供给变【多】、非稀释），只在 batch7 出现、batch6 消失——不是糕点自己的问题，b6_w48 直接绕开。
- **诚实边界**：留出 seeds 13-30 上有 1 个 seed（21）糕点自身 rate 0.478（略破 0.5，断供 34/60 天）——与 docs/153 §七记的 E3a 留出 seed 0.463 同量级，是**糕点自己的**落带边缘、非核心货、且留出不进 CI 判决。

## 四、★STEP 4 · 核心验收锚：**成功**——留出 13-30 核心三货基本不动（本片的心脏）

留出 seeds 13-30（N=12，clean baseline vs 定稿 b6_w48；baseline 逐 seed 重跑于**干净树**——见 §七诚实边界①）：

| 核心货 | median Δrate | mean Δ | down/up/flat | **E3a（docs/153，对照 FAIL）** |
|---|---|---|---|---|
| 口粮 | **+0.041** | +0.015 | 6 / **12** / 0 | −0.036（12/18 **下**） |
| 柴薪 | **−0.001** | +0.001 | **9 / 9** / 0 | −0.032（14/18 **下**） |
| 屋瓦 | **+0.006** | +0.010 | 8 / **10** / 0 | −0.028（14/18 **下**） |

**这不是 E3a 那种系统性下移**：两货中位【上升】、一货中位 −0.001（9/9 完美对半=噪声定义）。E3a 是全三货 median ~−0.03、66-78% 同向下；本片方向【相反】。口粮——E3a 里被稀释最狠、L2 记的『两个产者同塌』的那一格——在本片**升**（12/18 上），直接反证决策/空间稀释机制。

**机制侧（留出 13-30 逐职位在班完成 Δ）**：面点师 −1.11 / 渔夫 +0.72（口粮两产者近抵消，叠 吃饭 demand −5.2 ⇒ 口粮 rate 净升）· 木匠 −0.94 / 杂役 −0.28（柴薪，小）· 泥瓦匠 +0.61（屋瓦升）· 咖啡师 +0.50 / 教书先生 +0.28 / 环卫工 −0.28 · **糕点师(coco) +26.9**。对比 E3a 的【六个产者系统性下】（木匠 −1.56、环卫工 −1.83、咖啡师 −1.33、杂役 −1.28、教书先生 −1.28、面点师 −0.83）：本片**咖啡师/教书先生反升、环卫工几乎不动**，是【混合小扰动=轨迹重排】而非【全线压产=稀释】。

### ★NULL 对照——证 `consume.闲聊` 本身零稀释（比 E3a 的 E40 对照更干净）

问题：残余的 coco→糕点师【产者转换】本身会不会稀释核心？造一条 NULL 臂：**coco=糕点师、照产糕点、但删掉 `consume.闲聊`**（糕点成【死货】、闲聊不吃它、无 treat）。为让 A/B 只差 consume.闲聊 这一项，NULL 与其对照臂都跑在**同一标定 b7_w44**（做点心 W44/批量 7）上、对同一 clean baseline（留出 13-30、N=12）：

| 臂（均 coco=糕点师，vs clean baseline 13-30） | 口粮 | 柴薪 | 屋瓦 |
|---|---|---|---|
| WITH consume.闲聊（b7_w44） | +0.024 | −0.010 | −0.011 |
| NULL：删 consume.闲聊（b7_w44，糕点=死货） | −0.001 | **−0.028** | **−0.018** |

⇒ **同一标定下，NULL（无 treat）的核心移动 ≥ WITH-consume**（柴薪 −0.028 vs −0.010、屋瓦 −0.018 vs −0.011、口粮两者都在噪声内）。即：核心那点小移动来自【加一个产者=coco 换岗】这一**任何新货都不可避免**的项（F1/F5/G3 每片都付过、判据是『没有岗位掉出改前展布』），**而 `consume.闲聊`（本片真正的 pivot 机制）在其上净加零稀释**——正是 docs/153 §六.1 预言的「挂既有动作不新增决策槽 ⇒ 结构上不稀释」。这条 NULL 比 E3a 的 E40（吃点心吸引力调低、但吃点心广告仍在）**更干净**：本片 NULL 里 town 平面**一条新消费动作都没有**。（定稿 b6_w48 的核心锚更佳=两升一平，见上表；未在 b6_w48 上重跑 NULL，因结论在 b7_w44 上已立、且 b6_w48 的 WITH 已优于其 b7_w44 版。）

**可解释的一侧**：留出 13-30 fun/social 消费侧，糕点被真吃（demand 151-223/seed、rate 0.6-0.9），闲聊 shortage 事件按既有管线出社会后果（blame=糕点师=coco）；豆子/话本/整洁等 fun 货微动、可归因。

## 五、STEP 5 · off-gate + 移金标三锚重烘（本提交树）

- **off-gate（字节纯加法自证）**：把 6 键删掉（production.json 回 HEAD）→ `Harness --seeds 1-12 --golden` = **✅ 金标一致 12/12 seed（含逐 tick 前缀链）+ S0 GATE PASS**。⇒ 6 键是【多键移除即回滚】纪律下的纯加法，删键即回 pre-E3b。
- **移金标三锚全动且可归因**（重烘于本提交树；每处归到 糕点 produce/consume + 做点心候选 + 闲聊-consume 下游）：
  1. **golden seeds 段**（Harness --bake-golden）：12/12 seed digest/event_digest/chain 全移——糕点 produce/consume/spoil 事件进 event_digest、town_stock[糕点] 轨迹进批量 digest/chain。
  2. **golden scenarios 段**（DetGate --bake-golden）：default/faction/betray/freerider × seeds 1-4 = 16/16 全移（硬 16/16、det 16/16、数据指纹一致）——同因。
  3. **modelpath_anchor**（ModelPathGate --bake-anchor）：random_full 4/4 seed digest 移 + **候选规模 max_n 42→46**（这一格直接是 `做点心` job-gated 广告给 coco 新加的那一个候选）。
- `_meta.rebake_history` 各补一条（golden 20 条 / modelpath 14 条）。
- **HARD_IDS 未动**（additive 无新不变量，Invariants.gd 一字未改）。
- 重烘后三门复验：**Harness S0 GATE PASS（金标 12/12、硬 12/12、#40 12/12、det 3/3）· DetGate PASS（16/16 可比）· ModelPathGate PASS（失败 0）**。全 `tools/ci.sh` 见提交（analysis/e3b/ci_full.log）。
- ⚠ **complement ledger 未在本 worktree 重烘**：worktree 的 complement-guard 过是【提交前假绿】（锚的 baked_game_tree 对不上未来的 commit）。按 brief，**协调者在 committed 树重烘 ledger + 跑 committed-tree CI**。

## 六、诚实边界

- 只 backend=null headless、N=12（留出 13-30 跑了核心锚；大 N 未跑）。
- 标定值（batch6/W48/cap20/spoil1/start12）是 seeds 1-12 扫出的 b6_w48；留出 13-30 上 seed 21 糕点 rate 0.478（略破 0.5、断供 34 天）——糕点自身落带的边缘，非核心货、不进 CI。
- 「产者转换 vs treat-consume」的分解由 NULL 臂给出（干净）；「决策槽 vs 空间引力」的更细分解未做——但 pivot 的判据（核心不系统性下移 + treat 零稀释）已由锚 + NULL 两条实测立住。
- 基线曾因【后台 baseline 与本片改键在同一文件、跑中被改】污染过一次（§七①），已在干净树上重跑 seeds 1-30、逐 seed 校验 糕点师 work=0 后据以判锚。
- 未跑真机/SLM/LOD。

## 七、附：证据文件（analysis/e3b/）

- `baseline_clean_s1-30.jsonl`：**干净树**改前基线（核心三货锚 + #40 全景）。
- `after_final_b6w48_s13-30.jsonl`：定稿 b6_w48 改后留出 13-30（**核心锚主证据**）。
- `null_nocons_s13-30.jsonl` / `after_batch7_s13-30.jsonl`：NULL A/B 的两臂（均 b7_w44、coco=糕点师；前者删 consume.闲聊=死货、后者带 treat）——证 treat 零稀释。
- `cal_batch6_s1-12 / cal_batch7_s1-12 / cal_b6_w48_s1-12 / cal_b7_w40_s1-12.jsonl`：#40 标定扫（4 配）。
- `anchor.py / parse.py`：只读分析脚本（UTF-8）。
- `ci_full.log`：全 `tools/ci.sh` 输出。
- ① **污染记录**：首个 baseline 后台跑与本片改 production.json 撞车（ScaleSupply 每 seed 重载数据文件）⇒ 部分 baseline seed 含糕点。已弃用、在干净树重跑（`baseline_clean_*`）。
