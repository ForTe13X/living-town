# 166 · E4a：多货 `consume[action]` 机器（纯机器·零金标·不加货）· 判决：**成立**——双形状读者落地，单货分支逐字节不变（金标 12/12），Array 分支自测证双消费/双缺货/半缺 AND-fold/双需求全成立

> E3c（docs/165）跑出的结构边界是：`consume[action]` 是**单货结构**（一个动作只挂一件货），
> 所以工业多样化在 pure-data 上封顶在 1 货。本片是解这条封顶的 **A 部分：纯机器**——让一个动作能消费
> 【多件货】，同时**逐字节兼容**既有的裸 `{good,amount}` dict。**本片不加任何货、不动 production.json**
> （那是 B 部分的另一根棒）。安全门是【零金标】：无数据改动 ⇒ 代码改动必须逐字节等价。
>
> **两句话结论**：①**零金标成立**——`Harness --seeds 1-12 --days 60 --det 3 --golden` = 金标一致 **12/12**
> （含逐 tick 前缀链）、S0 GATE **PASS**、det **3/3**，与改前逐位相同（seed 1 digest 3894698000 / chain
> 78488955 / event_digest 1945279565897149957，12 个 seed 全对）。②**机器真的多货**——合成 2 货自测
> （`bench/e4a_multigood_selftest.gd`，内存注入、不落盘）证 Array 分支：双货足量→都消费+返回 true、
> 双货皆缺→两条 shortage 都触发+返回 false、半缺→AND-fold 返回 false 且只缺的那件写 shortage、
> #40 需求把两件货各自记上（demand = attempts×amount 逐货）。**19/19 断言全绿。**

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| **零金标**（无数据改动 ⇒ 代码逐字节等价） | ✅ **金标一致 12/12**（含逐 tick 前缀链）· S0 GATE PASS · det 3/3 · 与改前逐位相同 |
| 全 `tools/ci.sh` 绿（#38/#39/#40 S0 + N=16 4a · DetGate · VoiceGate · 全门） | ✅ 见 §四 CI 判决（`analysis/phase_d/e4a_ci_full.log`） |
| 合成多货自测（Array 分支真的多货） | ✅ **19/19 断言**（双消费 / 双缺货 / 半缺 AND-fold / 双需求；`bench/e4a_multigood_selftest.gd`） |
| production.json 一字未动、不加任何货 | ✅（B 部分才加货；本片纯机器） |
| HARD_IDS / 不变量条数 / WorldView / economy 未动 | ✅（additive 读者改，无新不变量，Invariants 只改 #40/S1 的读法、不改判据） |
| 确定性（无 randi/randf/Time/float；只列表著者序） | ✅ 见 §三 |

## 一、设计：双形状读者（backward-compatible）

`consume[action]` 从此**可以是 `{good,amount}` 的 Array（多货）**，但读者**同时接受既有的裸
`{good,amount}` dict（单货）**。每一处读点都做同一个归一化：

```
recs = raw if raw is Array else [raw]        # 裸 dict → 单元素列表
```

**为什么这一步保住零金标**：production.json 一字未动 ⇒ 每个动作仍是裸 dict ⇒ 归一化恒走
`[raw]` 这条单元素分支 ⇒ 对每一处读点，控制流与改前逐字节相同。单元素列表天然**序无关**，
所以下面 §三 讲的"列表序即语义"这条对现有数据不产生任何可观测差别。

## 二、六处读点（docs/165 scoping §2 全清单；行号实读于本提交树、以 git 为准）

| # | 位置 | 改法 | 单货分支为什么逐字节不变 |
|---|---|---|---|
| 1 | `Sim.gd:3463` `_consume_for`（核心） | 归一 `recs`；`attempts[action]` 在**非空判定之后**只 +1（同改前）；按序逐货 `_stock_take`＋consumed/short 记账＋`_shortage_fallout(ag,action,good)`；**任一货缺⇒返回 false**（AND-fold `all_ok`）。缺键 `raw={}`→过滤后 `recs=[]`→`return true` 且**不**计 attempts（= 改前 `rec.is_empty(): return true`）。 | 单元素列表：`attempts+1` → `took=_stock_take` → `took>=want{consumed+=took;continue→return true}` / 否则 `took>0{consumed+=took}`＋`short+1`＋`fallout`＋`all_ok=false→return false`。副作用序与改前 3463-3478 逐条相同。 |
| 2 | `Sim.gd:3672` `_trade_fallout` | 归一后取**首件**非空货填商贩口碑串（"街面上还买得着%s…"）。 | 单货 dict→`[dict]`→首件 = 改前 `.get(action,{}).get("good","")`；缺键→`""`（同改前）。 |
| 3 | `Invariants.gd:858` #40 需求 | `demand[good] += attempts[action]×amount`：归一后**逐货**累加。 | 单元素列表→单次循环→逐字节回改前（`cg`/累加式逐字照抄）。 |
| 4 | `Invariants.gd:978` S1 off-town reach 探针 | 归一后"任一件货 == gid2 即命中"。 | 单货→`match iff good==gid2`＝改前 `if …!=gid2: continue` 取反；非 dict→不命中（同改前）。 |
| 5 | `ScaleSupply.gd:231` #40 需求 @N-scale（喂 ci.sh 4a） | 同 #3：归一后逐货累加。 | 同 #3。 |
| 6 | `tools/audit_map.py:200` consume-good 存在性校验 | `for cr in (rec if isinstance(rec,list) else [rec])`：逐货校验 `good ∈ goods`。 | 单 dict→`[rec]`→单次循环→同一条 fail 文案/顺序。 |

清点自证（全仓 grep）：全代码库里**结构性**读 `production.consume[action].good/.amount` 的只有这 6 处；
其余 `consume` 命中都是 **event_log 的 `"consume"` 事件类型**（Main.FEED_SKIP / Invariants #38 / ScaleSupply
的事件计数 / gen_town_wiki 的事件标签），与 `consume[action]` 结构无关，不需改。

## 三、确定性论证（红线）

- **只列表著者序**：`_consume_for` 与两处 #40 需求环都严格 `for rec in recs` 顺序迭代，**永不 sort、
  永不依赖 dict 键序**。`for act in production.consume` 仍走 Godot 字典的插入序（保序）。
- **为什么序即语义**：`_shortage_fallout` 顺序写 `event_log`（进 `event_digest`）＋顺序插 belief（gossip 传播序）。
  多货时两件货的 shortage 事件先后由**列表书写序**唯一决定 ⇒ 多货行为也是确定的、由数据的书写序定序。
- 单元素列表天然序无关 ⇒ 现有单货数据对"序"完全不敏感 ⇒ 零金标不受此机制影响。
- 无 `randi/randf/Time/float`：只做整数库存扣减与整数需求累加（`_stock_take` 的 `mini`、`int(...)`）。

## 四、零金标逐字节证 + 合成多货自测 + CI 判决

### 4.1 零金标（安全门）——改后与改前逐位相同

命令：`"$GODOT" --headless --path game --script res://bench/Harness.gd -- --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json`

- **金标一致 12/12 seed（含逐 tick 前缀链 12 条）· S0 GATE PASS · 同 seed 两跑一致 3/3**。
- 改前（base = integration/batons，未改动树）与改后**每一个 seed 的 digest / chain / event_digest 逐位相同**，例：

  | seed | digest | chain | event_digest | 改前=改后 |
  |---|---|---|---|---|
  | 1 | 3894698000 | 78488955 | 1945279565897149957 | ✅ |
  | 2 | 892587041 | 2013063766 | 4550192148962757269 | ✅ |
  | 12 | 3016862290 | 1119578655 | 6841852709900862734 | ✅ |

  （12/12 全对；base 与 post 两次 Harness 输出的 [S0] 行逐 seed 相同。）
- 硬不变量 46 条 12/12（#01 无饿穿在内）、软通过率门 ≥11/12 过、#40 12/12、活性 17 类全在。
- ⇒ 双形状读者在 dict 分支上**行为逐字节等价**，安全门通过。

### 4.2 合成 2 货自测（证机器真的多货）——`game/bench/e4a_multigood_selftest.gd`

命令：`"$GODOT" --headless --path game -s res://bench/e4a_multigood_selftest.gd` → **PASS，19/19 断言**。

在内存里给一个合成动作注入 2 货 `[{口粮,2},{柴薪,1}]`（**不改 production.json**，跑完随 Sim 释放），
直接驱动真实 `Sim._consume_for`：

- **A 双货足量**：返回 true；口粮库存 −2、柴薪 −1；`consumed[口粮]+=2`、`consumed[柴薪]+=1`；
  `attempts[act]` 只 +1（一次动作一次计数，与货数无关）。
- **B 双货皆缺**：AND-fold 返回 false；`short[口粮]+1`、`short[柴薪]+1`；event_log 新增**2** 条 shortage（两货各一）。
- **C 半缺**（一有一无）：返回 false；有货的口粮照常 `consumed+=2` 且**不**记 short；缺货的柴薪 `short+1`；
  event_log 只新增 **1** 条 shortage。⇒ 逐货独立、AND-fold 正确。
- **D 需求逐货**：`demand[口粮]=attempts×2`、`demand[柴薪]=attempts×1`——两件货各自累加。
  D 用 `_demand_of()`，它是 Invariants.gd:858 / ScaleSupply.gd:231 **同一份 4 行需求环（含双形状归一化）的逐字副本**；
  之所以复刻而不直接调那两处：Invariants #40 只在完整 60 天 gated 局里评估（本探针不跑满局），
  ScaleSupply `extends SceneTree`（一 `new()` 就跑整场 census）——两处的**单货分支**已由 §4.1 零金标逐字节证过，
  D 只需证**Array 分支**把两件货各自累加。

⚠ 探针只被 `--import` 解析、**不被 Harness / ci.sh 自动执行**、只读自己的 Sim 实例 ⇒ 对零金标与全 CI 判决零影响。

### 4.3 全 `tools/ci.sh` 判决

见 §四表：`analysis/phase_d/e4a_ci_full.log`（本 worktree 跑）。关注点：
- **S0（第 4 步）**：金标 12/12 + 硬 12/12 + det 3/3。
- **4a 宏观池尺度门 N=16**：#40 软门（本片不加货 ⇒ 与 base 同判，双形状读者的单货分支逐字节不变）。
- **4c DetGate / 4d BackendGate / 4e ModelPathGate / 4f VoiceGate / 4g #43 / 4h state_projection**：全按 base 判。
- **1b audit_map**（site 6 的 Python 改）：PASS。
- ⚠ **complement ledger 由协调者在 committed 树重烘**（worktree 的 complement-guard 过是提交前假绿——
  锚的 `baked_game_tree` 对不上未来 commit）。按 baton，协调者 re-bake ledger + 跑 committed-tree 全 CI。

## 五、诚实边界

- **本片是 A 部分（纯机器），不加任何货**。B 部分（真加一件挂多货宿主的货 + 标定 + 核心锚 + off-gate）是**另一根棒**。
- 零金标只证【dict 分支逐字节等价】；【Array 分支】的正确性由 §4.2 自测证（19 断言），
  但自测是**合成注入**、非真机/非满局网格——它证机器成立，不证任何**平衡**（那是 B 部分的活）。
- 自测 D 用的是需求环的**逐字副本**而非直接调 Invariants/ScaleSupply（理由见 §4.2）；两处真实读点的
  单货分支由零金标 12/12 逐字节兜住，Array 分支的行数与副本逐字相同。
- `_trade_fallout` 多货时口碑串只提**首件**货（设计选择：摊子撑着"某货"）——单货逐字节不变；
  多货的措辞是否要列全部货，留给 B 部分按真实宿主定。
- 未跑真机 / SLM / LOD；未跑 N=24/60。
- complement ledger 未在本 worktree 重烘（假绿），交协调者。

## 六、附：文件

- 改动 6 处：`game/scripts/Sim.gd`（`_consume_for` + `_trade_fallout`）、`game/bench/Invariants.gd`
  （#40 需求 + S1 reach）、`game/bench/ScaleSupply.gd`（#40 @N-scale）、`tools/audit_map.py`（consume 存在性）。
- 新增探针：`game/bench/e4a_multigood_selftest.gd`（只读自测，不进金标路/CI 自动执行）。
- 证据：`analysis/phase_d/e4a_ci_full.log`（全 ci.sh 输出）、`analysis/phase_d/e4a_zero_golden_after.log`
  （改后 Harness --golden 12/12；**改前基线 = 已提交的 `game/bench/golden_digests.json` 自身**，它烘于未改动树，
  故"金标一致 12/12"即改前=改后的跨进程锚证明）、`analysis/phase_d/e4a_selftest.log`（合成 2 货自测输出）。
