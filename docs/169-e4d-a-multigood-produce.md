# 169 · E4d-A：多货 `produce[title]` 机器（纯机器·零金标·不加货）· 判决：**成立**——双形状读者落地，单货分支逐字节不变（金标 12/12），Array 分支自测证双入库/著者序/work一次/逐货#39/逐货缺料缩放/逐rec需求全成立

> E4c（docs/168）跑出的结构规则是：工业多样化【过 1 货】的天花板**不在宿主的 N-斜率、在【劳动池】**——
> 12 人镇子每个宿主只养得起【一个】专职产者而保核心中性，加第二件货就要加第二个专职产者、把 spare 浮动工
> 从核心替补池里抽走 ⇒ 口粮系统性稀释。E4c §六给下一棒开的三条出路里，第一条就是
> **「让一个产者兼产两货（多货 produce，而非多产者）」**。本片是那条出路的 **A 部分：纯机器**——
> 让一个【产者】一【场】做出【多件货】，同时【逐字节兼容】既有的裸 `{good,amount,inputs?}` dict。
> 它是已落地的 E4a（docs/166，消费侧多货 `consume[action]`）的**产出侧镜像**。
> **本片不加任何货、不动 production.json**（那是 B 部分——coco 的第二件货——的另一根棒）。
> 安全门是【零金标】：无数据改动 ⇒ 代码改动必须逐字节等价。
>
> **两句话结论**：①**零金标成立**——`Harness --seeds 1-12 --days 60 --det 3 --golden` = 金标一致 **12/12**
> （含逐 tick 前缀链）、S0 GATE **PASS**、det **3/3**，改前（base=integration/batons 未改动树）与改后**每一个 seed 的
> digest/chain/event_digest 逐位相同**（seed 1 digest 3894698000 / chain 78488955 / event_digest 1945279565897149957；
> 12 个 [S0] 行的 sha256 改前=改后 `89502f9c…`）。②**机器真的多货**——合成 2 货自测
> （`bench/e4d_multigood_selftest.gd`，内存注入、不落盘）证 Array 分支：一场做 2 货→两货各入库+2 条 produce 事件
> 按【列表著者序】、`work[title]` 每场只 +1、#39 溯源【按 subject-good 逐货匹配】、缺料缩放【逐货独立】、
> #40 原料需求【逐 rec 累加】。**19/19 断言全绿。**

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| **零金标**（无数据改动 ⇒ 代码逐字节等价） | ✅ **金标一致 12/12**（含逐 tick 前缀链）· S0 GATE PASS · det 3/3 · 12 条 [S0] 行改前=改后逐字节（sha256 同为 `89502f9c…`） |
| 全 `tools/ci.sh` 绿（#38/#39/#40 S0 + N=16 4a · audit_map · DetGate · VoiceGate · 全门） | 见 §四 CI 判决（`analysis/e4d/ci_full.log`） |
| 合成多货自测（Array 分支真的多货） | ✅ **19/19 断言**（双入库/著者序/work一次/逐货#39/逐货缺料缩放/逐rec需求；`bench/e4d_multigood_selftest.gd`） |
| production.json 一字未动、不加任何货 | ✅（B 部分才加货；本片纯机器） |
| HARD_IDS / 不变量条数 / WorldView / economy 未动 | ✅（additive 读者改，无新不变量，Invariants 只改 #39/#40 的读法、不改判据） |
| 确定性（无 randi/randf/Time/float；只列表著者序） | ✅ 见 §三 |
| `_stock_pull_mult` 锁首件货（保 E4c 核心中性论点的前提） | ✅ 见 §一·★ 与 §五 |

## 一、设计：双形状读者（backward-compatible，consume 侧 E4a 的镜像）

`produce[title]` 从此**可以是 `{good,amount,inputs?}` 的 Array（多货）**，但读者**同时接受既有的裸
`{good,amount,inputs?}` dict（单货）**。每一处读点都做同一个归一化（与 E4a 逐字对称）：

```
recs = raw if raw is Array else [raw]        # 裸 dict → 单元素列表；再滤掉空/非 dict
```

**为什么这一步保住零金标**：production.json 一字未动 ⇒ 每个产者仍是裸 dict ⇒ 归一化恒走
`[raw]` 这条单元素分支 ⇒ 对每一处读点，控制流与改前逐字节相同。单元素列表天然**序无关**，
所以下面 §三 讲的"列表序即语义"这条对现有数据不产生任何可观测差别。

★**核心的 work++ 位置**：`_produce_for` 里 `prod_stats["work"][title] += 1` 是**每【场】只加一次**的
【场次】计数（#40 的原料需求分母与满足率都读它）。多货时它必须仍**只加一次**——用一道 `first` 首次迭代守卫
钉在它**改前的确切位置**（首件货的扣料/停工后果之后、首件货 `amount<=0` 短路之前）。单货时 `first` 恒在首圈为真
⇒ 逐字节回改前。★`prod_stats` 不进任何 digest（已验证）⇒ 无论 work++ 怎么放都对 event_digest/state digest 不可见，
零金标不依赖它；`first` 守卫是为了**多货语义正确**（一场一次计数），不是为了零金标。

★**`_stock_pull_mult` 锁定首件货**（见 §五）：工位回拉乘子在多货时**只读列表著者序第一件货的库存**，
刻意【不】取 min-across-goods。理由是 E4c 的核心中性论点依赖【加第二件货不改首个产者的上工节律】——
若取 min，第二件货的低库存会把工位吸引力再抬一次 ⇒ 首个产者上工更勤 ⇒ 反而稀释核心。锁首件正是保这条节律。
镜像 E4a 的 `_trade_fallout`「取首件非空货」。

## 二、九处读点（scoping §2 全清单；行号实读于本提交树、以 git 为准）

| # | 位置 | 改法 | 单货分支为什么逐字节不变 |
|---|---|---|---|
| 1 | `Sim.gd` `_produce_for`（核心） | 归一 `recs`；`work[title]+=1` 在 `first` 首次迭代守卫下**每场只加一次**（钉在改前位置）；按著者序逐货：扣料/lacked-缩放（逐字照抄）、`if amount<=0: continue`（was `return`）、`_stock_move(good,amount,"produce",id,title,wits)` 逐货、逐货 produced++/craft_fallout/memory。 | 单元素列表：`first` 首圈为真 ⇒ work++ 同位置；末圈 `continue` = 改前 `return`（函数结束）；副作用序与改前逐条相同。 |
| 2 | `Sim.gd` `_stock_pull_mult`（工位回拉，produce-only） | 归一后**★锁定首件**非空货读库存（不取 min-across-goods，见 §一·★/§五）。 | 单货 dict→`[dict]`→首件 = 改前 `.get(title,{})` 的那件；空 → 恒 1.0（同改前）。 |
| 3 | `Sim.gd` `_pool_rescale`（N-尺度，produce-only） | 归一后**逐 rec** 缩放 `.amount`/`.inputs`（`out` 是 `raw.duplicate(true)` 深拷贝，dict 引用类型，原地改即改 `out`）。 | 单货 dict→`[dict]`→单次循环→逐字节回改前。 |
| 4 | `Invariants.gd` #39 溯源 | 归一 `recs`；**按 subject-good 匹配**（找 `.good==e.subject` 的那条；无 ⇒「产出了未申报的货」红；有 ⇒ 件数 ≤ **那条**的 `.amount`）。note-split-title（709）与在班（718）两条检查逐字不变。 | 单货 dict→`[dict]`：good==subject 时 matched=该 dict、走件数检查（`matched.amount`＝改前 `rec.amount`）；good≠subject 时 matched={}、走「产出了 %s」红（改前同串）。 |
| 5 | `Invariants.gd` #40 需求 | 归一后**逐 rec**：`producible[good]=true` + 原料需求（`nw=work[title]` 逐 title 一次、与货数无关；一场里每件货的料都被扣 ⇒ 该料需求 = `nw × Σ各 rec 用量`）。 | 单元素列表→单次循环→逐字节回改前（producible/需求式逐字照抄；`nw` 移到 rec 环外是纯读，值恒等）。 |
| 6 | `ScaleSupply.gd` #40 需求 @N-scale（喂 ci.sh 4a） | 同 #5（`nw` 读传入的 `work` 参数）。 | 同 #5。 |
| 7 | `tools/audit_map.py` produce-good 存在性校验 | `for pcr in (rec if isinstance(rec,list) else [rec])`：逐货校验 `good ∈ goods`。 | 单 dict→`[rec]`→单次循环→同一条 fail 文案/顺序。 |
| 8 | `game/bench/t1_workfloor_probe.gd`（2 处：137/202） | 新增 `_first_prod_good(prod,title)` 助手，库存分档取**首件货**。 | 单货 dict→直接读 good；缺产者→""（同改前）。仅探针显示/分档，不进金标/CI。 |
| 9 | `game/bench/v1_social_census.gd`（124） | 同 #8 的 `_first_prod_good`，`"produces"` 展示字段取首件货。 | 同 #8。 |

清点自证（全仓 grep）：全代码库里**结构性**读 `production.produce[title].good/.amount/.inputs` 的只有这 9 处（10 个物理读点）；
其余 `produce` 命中都是 **event_log 的 `"produce"` 事件类型**（#38 账本 / #40 事件计数 / v1 的 produce 通道计数 /
Story.gd 的事件标签），与 `produce[title]` 结构无关，不需改。

## 三、确定性论证（红线）

- **只列表著者序**：`_produce_for` 与两处 #40 需求环都严格 `for rec in recs` / `for prec in precs` 顺序迭代，
  **永不 sort、永不依赖 dict 键序**。`for title in production.produce` 仍走 Godot 字典的插入序（保序）。
- **为什么序即语义**：`_produce_for` 逐货调 `_stock_move`→`_log_event` 顺序写 `event_log`（进 `event_digest`）+
  顺序扣料/写记忆。多货时两件货的 produce 事件先后由**列表书写序**唯一决定 ⇒ 多货行为也是确定的、由数据的书写序定序。
- 单元素列表天然序无关 ⇒ 现有单货数据对"序"完全不敏感 ⇒ 零金标不受此机制影响。
- 无 `randi/randf/Time/float`：只做整数库存增减（`_stock_move`/`_stock_take` 的 `mini`/`maxi`）与整数缩放
  （`amount*r_num/r_den`、`v0*num/base`）、整数需求累加。

## 四、零金标逐字节证 + 合成多货自测 + CI 判决

### 4.1 零金标（安全门）——改后与改前逐位相同

命令：`"$GODOT" --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json`

- **金标一致 12/12 seed（含逐 tick 前缀链 12 条）· S0 GATE PASS · 同 seed 两跑一致 3/3**。
- 改前（base=integration/batons，未改动树，`analysis/e4d/zero_golden_BEFORE.log`）与改后
  （`analysis/e4d/zero_golden_AFTER.log`）**每一个 seed 的 [S0] 行逐位相同**，例：

  | seed | digest | chain | event_digest | 改前=改后 |
  |---|---|---|---|---|
  | 1 | 3894698000 | 78488955 | 1945279565897149957 | ✅ |
  | 2 | 892587041 | 2013063766 | 4550192148962757269 | ✅ |
  | 12 | 3016862290 | 1119578655 | 6841852709900862734 | ✅ |

  12 条 [S0] 行整块 sha256 **改前=改后=`89502f9c9902de866d75fc5e4f15b6e2a40b316835a76fddffa2f9b3e558c6e6`**
  （`analysis/e4d/s0_before.txt` == `s0_after.txt`，`diff` 无差异）。
- ⇒ 双形状读者在 dict 分支上**行为逐字节等价**，安全门通过。★注意 base 与 post 的 `golden_digests.json` 一字未动
  （它本就烘于未改动树）⇒ 「金标一致 12/12」即改前=改后的**跨进程锚证明**。

### 4.2 合成 2 货自测（证机器真的多货）——`game/bench/e4d_multigood_selftest.gd`

命令：`"$GODOT" --headless --path game -s res://bench/e4d_multigood_selftest.gd` → **PASS，19/19 断言**。

在内存里注入一个合成岗位（`shift=[]` ⇒ `_in_shift` 恒 true，让班次守卫放行）+ 一个合成产职的 2 货 produce
（**不改 production.json**，跑完随 Sim 释放），直接驱动真实 `Sim._produce_for`：

- **A 一场做 2 货足库容**：`[{口粮,2},{柴薪,1}]` → 两货各入库（口粮 +2、柴薪 +1）；`produced[口粮]+=2`、`produced[柴薪]+=1`；
  **`work[title]` 只 +1**（一场一次计数、与货数无关）；event_log **新增 2 条 produce、顺序 = 列表著者序 `[口粮,柴薪]`**。
- **B #39 逐货溯源**：两条 produce 事件各自匹配到 `.good==subject` 的申报、件数 ≤ 该货批量 ⇒ `prov_bad` 空。
- **C 缺料缩放逐货独立**：`[{屋瓦,4,inputs:{柴薪,4}},{口粮,2}]`，柴薪库存只 2（需 4）⇒ 屋瓦整数缩水到 `4×2/4=2`、
  写 1 条「料:柴薪」缺料后果；口粮无料 → 满产 2、**不受另一件缺料影响**；`short[柴薪]+1`；**缺料一场仍 work 只 +1**。
- **D #40 原料需求逐 rec 累加**：`[{屋瓦,4,inputs:{柴薪,4}},{口粮,2,inputs:{柴薪,1}}]`，`work=10` ⇒
  `demand[柴薪] = 10×(4+1) = 50`——两条 rec 的同一料各自累加。
  D 用 `_prod_demand_of()`，它是 Invariants.gd #40 / ScaleSupply.gd #40 **同一份需求环（含双形状归一化）的逐字副本**；
  之所以复刻而不直接调那两处：Invariants #40 只在完整 60 天 gated 局里评估（本探针不跑满局），
  ScaleSupply `extends SceneTree`（一 `new()` 就跑整场 census）——两处的**单货分支**已由 §4.1 零金标逐字节证过，
  D 只需证**Array 分支**把两条 rec 的料各自累加。

⚠ 探针只被 `--import` 解析、**不被 Harness / ci.sh 自动执行**、只读自己的 Sim 实例 ⇒ 对零金标与全 CI 判决零影响。
（退出时 `ObjectDB instances leaked` 是 headless 拆场的良性告警，非失败。）

### 4.3 全 `tools/ci.sh` 判决

见 `analysis/e4d/ci_full.log`（本 worktree 跑，`GODOT=<4.6.2 exe> PYTHON=python`）。关注点：
- **S0（第 4 步）**：金标 12/12 + 硬 12/12 + det 3/3（= §4.1）。
- **4a 宏观池尺度门 N=16**：#40 软门（本片不加货 ⇒ 与 base 同判，双形状读者的单货分支逐字节不变；且 `_pool_rescale`
  的逐-rec 缩放对单元素列表 = 改前逐字节）。
- **1b audit_map**（site 7 的 Python 改）：PASS。
- **3 import/parse smoke**：解析全部 .gd（含两个探针 site 8/9）——验其无 parse 错。
- **4c DetGate / 4f VoiceGate / 其余门**：全按 base 判（无数据/判据改动）。
- ⚠ **2f 互补性守卫（complement ledger）在本 worktree 是提交前假绿**——锚的 `baked_game_tree` 对不上未来 commit
  （game/ 已改）。按 baton，**协调者在 committed 树 re-bake ledger + 跑 committed-tree 全 CI**。

## 五、`_stock_pull_mult` 首件锁——为什么必须锁首件（而不是 min-across-goods）

`_stock_pull_mult(title)` 是工位吸引力的【回拉乘子】（空仓加把劲、满仓歇一歇），只乘进打分用的 `benefit`。
多货产者服务的每件货都有自己的库存，一个自然的写法是取 **min-across-goods**（哪件最空就按哪件加劲）。**本片刻意不这么写**，改为**锁定列表著者序第一件货**：

- **E4c 的核心中性论点依赖【首个产者上工节律不因加第二件货而变】**。B 部分要走的正是 E4c §六第一条出路——
  让**已有的**第一个产者（如 coco=糕点师）**兼产**第二件货，而不是新招一个专职产者。若 `_stock_pull_mult` 取 min，
  第二件货一空就把工位吸引力再抬一次 ⇒ coco 上工更勤 ⇒ 挤占它作为核心替补工漂在池里的时间 ⇒ **正好复现 E4c 的稀释**。
  锁首件 ⇒ coco 的上工节律**只由它的第一件货（糕点）的库存决定**，与新挂的第二件货无关 ⇒ 节律不变 ⇒ 核心中性论点在 B 部分才可能成立。
- **零金标**：单货时 `precs=[dict]`、首件 = 那件 dict ⇒ 与改前 `.get(title,{})` 逐字节相同。
- 这是**机器层的设计选择**，不是平衡结论；B 部分若量到"锁首件让第二件货自己供给不足"，那是 B 的标定活（调 amount/cap），
  不该回来改这条锁——一改就把首个产者的节律又耦合进第二件货、把 E4c 的坑重新挖开。

## 六、诚实边界

- **本片是 A 部分（纯机器），不加任何货**。B 部分（真给一个已有产者挂第二件货 + 标定 + 核心锚 + off-gate）是**另一根棒**。
- 零金标只证【dict 分支逐字节等价】；【Array 分支】的正确性由 §4.2 自测证（19 断言），
  但自测是**合成注入**、非真机/非满局网格——它证机器成立，不证任何**平衡**（那是 B 部分的活）。
- 自测 D 用的是需求环的**逐字副本**而非直接调 Invariants/ScaleSupply（理由见 §4.2）；两处真实读点的
  单货分支由零金标 12/12 逐字节兜住，Array 分支的行数与副本逐字相同。
- `_stock_pull_mult` / `_trade_fallout` / 两个探针多货时**只提首件货**（设计选择，见 §五）——单货逐字节不变；
  多货宿主的具体标定留给 B 部分。
- **#40 满足率仍无上限臂对"一场产多货"的产能上限做校验**：#40 靠「在班完成次数 × 用量」重建原料需求分母（docs/54 §十），
  多货时每件货各自累加——这条在自测 D 证过逐 rec 累加正确，但满局网格上的边际行为（多货是否让某件货长期越带）是 B 部分的标定。
- 未跑真机 / SLM / LOD；未跑 N=24/60。
- complement ledger 未在本 worktree 重烘（假绿），交协调者。

## 七、附：文件

- 改动 7 处（9 逻辑读点）：`game/scripts/Sim.gd`（`_produce_for` + `_stock_pull_mult` + `_pool_rescale`）、
  `game/bench/Invariants.gd`（#39 溯源 + #40 需求）、`game/bench/ScaleSupply.gd`（#40 @N-scale）、
  `tools/audit_map.py`（produce 存在性）、`game/bench/t1_workfloor_probe.gd` + `game/bench/v1_social_census.gd`（两探针，非 CI）。
- 新增探针：`game/bench/e4d_multigood_selftest.gd`（只读自测，不进金标路/CI 自动执行）。
- 证据（`analysis/e4d/`）：`zero_golden_BEFORE.log` / `zero_golden_AFTER.log`（改前/改后 Harness --golden 12/12）、
  `s0_before.txt` == `s0_after.txt`（12 条 [S0] 行逐字节、sha256 同）、`selftest.log`（合成 2 货自测 19/19）、
  `ci_full.log`（全 ci.sh 输出）。
