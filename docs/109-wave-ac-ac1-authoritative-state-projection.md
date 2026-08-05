# 109 · Wave AC · AC1 回执——**"逐字节一致"说的是【事件账本 + 五个 agent 字段】**；缺的那 29 个字段不是"看不见"，是**看见得晚**

> 派单：[docs/108 §一](108-wave-ac-plan.md)（AC1）。契约 [docs/41](41-baton-contract.md) 全文（尤其 §2.5），R12 见 [docs/47 §〇](47-wave-e-plan.md)。
> 直接前置：[docs/66](66-faction-contact-gate.md)（Q1，**五波之前就实测过 `chain_step` 不折 `attitudes`**）。
> worktree `E:/Documents/Dev/June/26th/.claude/worktrees/agent-a6f3934d575501d25`，分支 `worktree-agent-a6f3934d575501d25`。
> **开工时在 `38ba4a7`（= `master`）**，`git merge-base --is-ancestor 38ba4a7 e2a85bb` 确认是祖先后
> ff 到 `integration/batons` = **`e2a85bb`**（前进 288 个 commit，丢 0 个）。
> ⚠ 主 checkout 当时停在 `codex/narrative`（`e7a64e6`），**没有跟它走**。
> 全部数字自跑：`backend=null` · 无 LOD · **逐 seed，不给均值**。量具 `game/bench/ac1_state_coverage.gd`（新，只读）。

---

## ★ 交付状态

| | 状态 |
|---|---|
| **先量①** 字段清单 + 逐个覆盖判定 | **做了**（§一）。⚠ **不是读源码读出来的**：就地扰动 → 用同一个 `prev`/`ev_from` 重算 → 比值。分母走 `get_property_list()`（**与 `Sim.save_game` 同一套反射**）+ 活 agent 的 `.keys()` |
| **比例** | **36 个"这一局里真的变过"的权威字段中，29 个（80.6%）`digest` 与 `chain` 两头都没折** |
| **先量②** 干预实验 | **做了**（§二）。**25 条臂 × 5 seed**，带**阳性对照**（干预到底落地没有） |
| **本波核心数据**："`digest` 不变而行为变"的字段 | **一个都没有**（全程 10 天口径）。真实形状是**滞后**：`chain` 比行为晚 **1..105 tick**；从干预到 `chain` 分叉的**盲窗 0..1784 tick**，且 `skills`/`beliefs` **各有 2/5 个 seed 十天内从未分叉** |
| 那个"两人都在 (10,10)"的例子 | **属实**（`space`/`floor` 实测 `in_chain=no`），**但它的寿命是 1..37 tick**（§三）——比它听起来轻，比"没事"重 |
| 扩 / 不扩的代价 | **实测**（§四）。⚠ **"金标全部作废"是过头的**：隔离副本实测**只有 `chain` 一列动**，`digest`/`event_digest`/`events` **全部照旧吻合**；**ModelPathGate 锚根本不动**（它不存 chain，实测 EXIT=0） |
| 建议 | **给了，分三阶段**（§五）。**决定留给用户**——改契约/改金标口径不是我的权限 |
| 我动了什么 | **只加了一个 bench 探针**。`game/scripts/**`、`game/data/**`、`tools/**` 一个字节没动 ⇒ 金标按构造不动 |
| `bash tools/ci.sh` | **§六，读的是真输出** |
| §2.5 三行包络 | **§七** |

---

## 〇、先把判决摆前面

1. **外部评审（Codex）说的是对的，而且我把它量成了数**：`Inv.digest` 只折 `event_log`；
   `chain_step` 只折 `tick_no` + 逐 agent 的 `id/pos/needs/talking/option`。
   **36 个演化中的权威字段里 29 个两头都没折。**
2. **但"没折进 hash" ≠ "看不见"。** `chain` 是**逐 tick 前缀链**：一个字段只要真的驱动未来，
   它迟早会把 `pos`/`option`/事件推歪，链跟着分叉。
   **我找不到任何一个"行为变了而 `chain` 全程不变"的字段**（25 臂 × 5 seed = 125 格）。
   ⇒ **真正的缺陷是【延迟】，不是【失明】。** 这一条是对派单措辞的**修正**。
3. **而延迟是要命的那一半**：盲窗实测 **0..1784 tick（0..7.4 天）**。
   `ModelPathGate` 跑 **8 天**、`DetGate` 跑 **20 天**——`skills` 的 1784 tick 盲窗
   已经吃掉 8 天里的 7.4 天，**2/5 个 seed 干脆十天都没分叉**。
   ⇒ **短 horizon 的门与这个盲窗是同一个量级。** 这才是可操作的那条风险。

---

## 一、先量①：覆盖是**量出来的**，不是读出来的

### 1.1 方法（为什么不读源码）

本 session 反复吃过注释过期的亏（`Invariants.gd` 抬头那三段"怎么数条数"的配方**自己错了两轮**）。
所以本棒不读注释也不读源码去判"折没折"，而是**直接测**：

> 跑到 `t0`，记下 `base_chain = chain_step(PREV, S, ev_from)` 与 `base_digest = digest(S)`；
> 然后**只改一个字段**，**用同一个 `PREV`、同一个 `ev_from`** 重算，比值；改完立刻还原。
> **值变了 = 折进去了；值没变 = 没折。** 唯一的自变量就是那个字段。

**分母也不是我手列的**：世界侧走 `S.get_property_list()` 并套用 `Sim.save_game` **逐字抄来的**
三个排除表（`DERIVED` / `VIEW_PARAMS` / `BENCH_ONLY`）——也就是**"权威状态"用的是仓库自己的定义**，不是我的定义；
agent 侧走活 agent 的 `.keys()`。

⚠ **一处真实的耦合我必须写出来**：那三个排除表在 `save_game` 里是**函数内 `const`**，取不到 ⇒ 探针里是**复制品**。
`save_game` 改了而探针没跟，分母就会悄悄错。探针把每一行的归类**逐个打印**出来，让这个耦合是可见的。

### 1.2 「这一局里它变过吗」——分母能不能用，全看这一列

100 个世界字段里**一大半是 `data/*.json` 读进来的配置**（`rhythm`/`utility`/`weather`/`jobs`/`economy`/`production`…）。
它们是这一局的**输入**，不是演化状态，**本来就不该进轨迹哈希**（由数据文件 + 金标一起钉住）。
判据同样可执行、同样不读注释：**`t0` 的值与再跑一天之后的值逐字节比**。

⇒ **该问"覆盖了吗"的分母是【变过的那些】，不是全部 100 个。**

### 1.3 实测（seed 1 · N=12 · t0=480）

```
world: perturbable_state=100  in_chain=3  in_digest=1  skipped=12
agent: perturbable_state=35   in_chain=5  in_digest=0  skipped=1
── 只算【这一局里真的变过】的字段 ──
world: evolves=18  其中 chain/digest 两头都没折=15
agent: evolves=18  其中 chain/digest 两头都没折=14
```

| | 演化中的权威字段 | 被折进去的 | **两头都没折** |
|---|---|---|---|
| 世界侧 | 18 | 3（`tick_no`、`event_log`、以及 `agents` 这个**容器**） | **15** |
| agent 侧 | 18 | 4（`pos`/`needs`/`option`/`talking`；`id` 也折但它不演化） | **14** |
| **合计** | **36** | 7 | **29 = 80.6%** |

**没被折进去的 29 个**：
- 世界侧：`day` · `weather_today` · `town_coin` · `town_stock` · `factions` · `_short_day` · `_trade_day` ·
  `_st_delta` · `event_digest` · `_next_event_id` · `econ_stats` · `prod_stats` · `cand_calls` ·
  `st_neg_events` · `refused_by_bound`
- agent 侧：`inventory`(含 `coin`) · `relationships`(亲/信/怨/熟/望) · `beliefs` · `attitudes` ·
  `faction` · `faction_size` · `skills` · `pacts`※ · `stifled` · `metKnower` · `complementSeen` ·
  `last_say` · `area` · `room` · `talk_with`
  （※`pacts` 在 seed 1 的那一天里没变，故不在"演化"18 个之内，但干预实验证明它驱动未来 ⇒ 一并列出）

⚠ **派单说"别一上来就假设大部分都没覆盖——先量"。我量了：这一次先验是对的（80.6%）。**
但**先验对不等于可以不量**——下面 §二 就有三处，我不量就会写错。

### 1.4 派单没列到的两个**子字段**盲区（新）

**`chain_step` 折的是 `option` 的【六元】签名，不是整个 `option`：**

```
=== OPTION sub-keys ===
  probe agent=aria option keys=["kind","action","target","need","amount","dur_total","remaining","phase"]
  kind YES   action **no**   target YES   need **no**
  amount **no**   dur_total **no**   remaining YES   phase YES
```

⇒ **两个只差 `action` 或 `subject` 的 option 在 `chain_step` 里同哈希。**
这**不是新发现**：`game/bench/p1_locality_probe.gd:148` 早就写下了这一条，并在自己的指纹里补了那两项。
**它和 Q1 的 `attitudes` 是同一类事情的两次局部撞见**——外部评审做的正是把它一般化。

**关系账本 7 个子字段无一被折**：`affinity`/`trust`/`resentment`/`familiarity`/`standing`/`last_pos`/`last_neg` 全 `no`。

**`event_log` 9 个子字段全部被 `digest` 折进**（`id/tick/type/actor/target/subject/accepted/witnesses/note` 全 `YES`）
⇒ 事件账本那一侧是**完整的**，问题**只在世界状态侧**。

---

## 二、先量②：干预实验（**本波核心数据**）

### 2.1 方法与**阳性对照**

每条臂 = 一次完整的局（10 天 = 2400 tick），在 `tick_no == 480` **一次性**只改一个逻辑字段，
逐 tick 记 `chain` 与一条**更宽的行为指纹**（P1/Q1 的 `_fp_act` 口径，**含 `option.action`/`subject`**，
外加 `space`/`floor`）。对照臂是同一 seed 不做干预的那一局。

⚠ **阳性对照是必须的，因为我第一版栽在这上面三次。** 探针在干预前后各算一次**全状态指纹**
（`save_game` 会存的那一整坨），两者不等才算"干预落地了"。**`landed=NO` 的行结果作废。**

### 2.2 我自己犯的三个错（**它们全都长得像"这个字段是死的"**）

| 我写的 | 症状 | 真相 |
|---|---|---|
| `skills["做活"] += 40` | `SAME/SAME`，看起来 `skills` 是死字段 | **被改动者的岗位动作是 `烤点`**（`production.json` 的 `job_action` 覆盖了 `jobs.json`）⇒ 我改的是一个他永远用不到的键。改成读**他真实的**岗位动作后：**`chain` 5 个 seed 里 3 个动，盲窗 1075..1784 tick** |
| `mem.add(tick, text, …)` | 运行时报错，那一臂**崩着跑完** | 真实签名是 `add(text, importance, tick, tags)`（`Memory.gd:11`）——**参数顺序反了** |
| `pacts["__ac1__"] = {partner, formed}` | `_active_pact_count` 当场抛错 | 盟约的契约是 `:887`/`:4457` 那个**七键** dict，且**按构造是双边的**；缺 `status` ⇒ 世界处在造不出来的非法态 |

**还有一类更隐蔽的**：`stifled`/`metKnower`/`complementSeen`/`factions`/`agent.affinity` 的读路径
**全是按 id 查表**（`ag["stifled"].has(cid)` `:2540`/`:3772`、`ag["complementSeen"].get(oid)` `:4448`/`:4450`）。
我第一版塞的键是 `"__ac1__"`——**世界上没有任何 subject 叫这个名字 ⇒ 那条查表永远命中不了**。
于是"字段惰性"与"我的键根本不可能被查到"**长得一模一样**。全部改成**真 id** 重跑之后，
这几条**仍然**是 `SAME`——**所以现在它们的 `SAME` 才是个结果。**

### 2.3 实测网格（**5 seed，给展布不给均值**；盲窗 = 分叉 tick − 480）

```
arm                    landed   chain DIFF  chain 盲窗(tick)        行为分叉(tick)        hard_red
attitudes              5/5      5/5         72..574                72..469               []
beliefs                5/5      3/5         100..1028 (+never x2)  90..1028 (+never x2)  []
relationships_affinity 5/5      5/5         82..300                82..300               []
relationships_standing 5/5      5/5         4..518                 4..518                [27],[]
space_floor            5/5      5/5         0..36                  -1..-1                [1]
coin                   5/5      5/5         6..371                 6..401                [34]
town_stock             5/5      5/5         28..82                 41..205               [38]
town_coin              5/5      0/5         never x5               never x5              [34]
skills                 5/5      3/5         1075..1784 (+never x2) never x5              []
memory                 5/5      0/5         never x5               never x5              []
mood                   5/5      0/5         never x5               never x5              []
xi_eps                 5/5      5/5         82..443                82..433               []
faction                5/5      1/5         193..193 (+never x4)   193..193 (+never x4)  []
pacts                  5/5      5/5         176..999               176..999              []
last_say               5/5      0/5         never x5               never x5              []
agent_affinity         5/5      0/5         never x5               never x5              []
stifled                5/5      0/5         never x5               never x5              []
metKnower              5/5      0/5         never x5               never x5              []
complementSeen         5/5      0/5         never x5               never x5              []
weather_today          5/5      2/5         58..60 (+never x3)     58..60 (+never x3)    []
day                    5/5      5/5         246..722               246..722              []
factions_world         5/5      0/5         never x5               never x5              []
area                   5/5      2/5         0..0 (+never x3)       0..0 (+never x3)      []
talk_with              5/5      0/5         never x5               never x5              []
inventory_gift         5/5      5/5         100..310               90..310               []
```

### 2.4 **核心数据**：没有"行为变而 chain 不变"，有的是"chain 比行为晚"

**125 格里，"行为分叉了而 `chain` 全程没分叉"的格子：0 个。**
真实形状是**滞后**，逐 seed 列出（15 格）：

```
attitudes              seed=1   chain 比行为晚  10 tick (行为@+239, chain@+249)
attitudes              seed=13  chain 比行为晚  10 tick (行为@+183, chain@+193)
attitudes              seed=21  chain 比行为晚 105 tick (行为@+469, chain@+574)
beliefs                seed=7   chain 比行为晚  10 tick (行为@+90,  chain@+100)
beliefs                seed=13  chain 比行为晚  10 tick (行为@+518, chain@+528)
relationships_standing seed=5   chain 比行为晚   6 tick (行为@+183, chain@+189)
space_floor            seed=1/5/7/13/21  晚 1/15/37/4/1 tick（行为在**同一 tick** 就分叉）
xi_eps                 seed=5   晚 10 tick   · seed=21 晚 10 tick
inventory_gift         seed=5   晚 10 tick   · seed=7  晚 10 tick
```

⚠ **这个"晚 10 tick"反复出现不是巧合**：`chain_step` 折的 `option` 少了 `action`/`subject`（§1.4）
⇒ **换了动作但没换目标/阶段的那一步，链看不见**，要等到动作真的落成事件才追上。

### 2.5 抽样有多严重（**Y1/AA1 那条纪律的又一个实例**）

**同一条臂在不同 seed 上给出不同判决**：`beliefs` 3/5 · `skills` 3/5 · `weather_today` 2/5 · `area` 2/5 · `faction` 1/5。
⇒ **只跑 seed 1 的话，25 条臂里有 5 条我会写错。** 单 seed 结论在这道题上是不成立的。

### 2.6 十天内**测不到**驱动未来的 10 个字段（`landed=5/5` 且 `chain`/行为 `0/5`）

| 字段 | grep 证据 | 判读 |
|---|---|---|
| `mood` | **只有 `Sim.gd:914` 一处赋初值 `"neutral"`，全仓零读、零再写** | **死字段**（"演化"列也是 `no`） |
| `agent["affinity"]` | **全仓零读零写**；`git log -S '"affinity": {}'` 只回一条 `ebac5a3`（首次公开快照） | **死字段**（所有 `["affinity"]` 命中都是 `_rel(...)` 的关系账本，是另一个东西） |
| `last_say` | 只写（`:1099`/`:2351`/`:2376`），仿真侧零读 | **View / voice 用**，不驱动仿真 |
| `talk_with` | 唯一读点 `:1361` 是 `== "player"` | **玩家专属**；headless bench 无玩家 ⇒ 结构上不可达 |
| `memory` | `retrieve()` 供台词接地 | 驱动**台词**，不驱动仿真决策 |
| `town_coin` | — | **`chain` 看不见，硬不变量 #34（金钱守恒）当场红** ⇒ 另一条防线接住了 |
| `stifled` / `metKnower` | `:2540` / `:2543-2545` / `:3772` **真实门** | 读路径**在**，但真 id 干预 10 天内 0/5 传出去 |
| `complementSeen` | `:4448` / `:4450` **真实门** | 同上 |
| `factions`（世界级） | 每夜全量重建 | 下一次重建把它抹掉，读不到 |

⚠ **`stifled`/`metKnower`/`complementSeen`/`factions` 这四个必须写清**：它们**有 grep 证明的读路径**，
只是**这一组 seed × 10 天里没传出去**。**"没测到"不是"是死的"**——把它们归进"死字段"就是我在替数据说话。

---

## 三、那个"两个人都在 (10,10)"的例子——属实，但它的寿命是 1..37 tick

**属实**：§1.3 实测 `space` 与 `floor` 的 `in_chain` 都是 `no` ⇒ **同一 `pos`、不同平面，`chain_step` 给同一个哈希。**
`space`/`floor` 是**结构地址**（`_same_plane` `:3873` → `_nearby_agents` `:3885` 决定谁能和谁互动），不是涌现统计。

**但要同时读到另一半**：把人挪到 `cafe/2f` 之后，
- **行为指纹在同一个 tick 就分叉**（他的邻居集合当场变了）；
- **`chain` 在 1..37 tick 之内追上**（5/5 seed），并且 `#01` 硬红。

⇒ **这是一次真实的哈希碰撞，但不是一个能长期藏住的洞。** 它的价值在于**它便宜**（每 agent 两个字符串），
而不在于它堵住了什么灾难。**把它说成"两个世界一直同哈希"是过头的。**

---

## 四、扩 / 不扩的代价——**实测，不是估计**

### 4.1 金标到底动多少（隔离副本，两档加宽各跑一次）

在**隔离副本**里给 `chain_step` 加宽，拿**未重烘的**金标去比（`--seeds 1-3 --days 60`）：

- **tier1** = 加 `space`/`floor` + `option.action`/`subject`
- **tier2** = tier1 再加 `attitudes` + 关系账本五元 + `beliefs` + `coin`

**两档给出【同样形状】的结果**：

```
  ❌ 金标不符（3 处）：
      seed 1 chain  期望 2588462706  实得 1185822188      ← tier1
      seed 2 chain  期望 89356086    实得 3560817523
      seed 3 chain  期望 4168480363  实得 2764866318
=== S0 GATE: FAIL ❌ (硬不变量 seed 3/3 全绿, 软通过率门 过, 活性 过, 金标 破, det 1/1) ===
```

**读三件事**：
1. **只有 `chain` 一列不符**。`digest`/`event_digest`/`events` **3/3 全部照旧吻合**——它们压根没出现在失配清单里。
   ⇒ **派单（与我自己一开始的想法）说的"金标全部作废"是过头的。**
   金标每行 6 列，动的是 **`chain` + `chain_ck` 两列**；`days`/`digest`/`event_digest`/`events` 四列不动。
2. **硬不变量 3/3 全绿、`det 1/1`**：加宽**只换见证，不换世界**——这本来就该如此，但它是跑出来的。
3. **`ModelPathGate` 锚【不用】重烘**：它只存 `digest`/`event_digest`/`landed`，**不存 chain**。
   实测两档隔离副本上 `ModelPathGate --seeds 1-4 --days 8 --agents 12` **EXIT=0**。
   ⇒ **R12 那条"三份锚都要重烘"是按【行为变更】写的**；本类改动是**只动见证**，
   实测要重烘的是**两份**（`Harness --bake-golden` + `DetGate --bake-golden`），不是三份。
   ⚠ **这是对 R12 适用范围的一条更正，不是对 R12 的否定**——它那条规则在行为变更上仍然成立。

### 4.2 此后 R12 会不会变频繁（用 §二 的臂当代理）

今天 25 条臂里 **15 条**会动 `chain`；把这些状态全折进去之后，**凡是落地了的干预都会动** ⇒ **25 条**。

> **⇒ 触碰状态的改动里，会触发 R12 的比例约 ×1.67（15→25）。**

⚠ **这个 1.67 是【代理指标】不是【预测】**：我的 25 条臂是我挑的，不是真实 commit 的分布。
真实分布里绝大多数改动根本不碰这些字段。**别把它当成"R12 会多 67%"。**

### 4.3 性能——**这是两档之间真正的分水岭**

`chain_step` **每 tick 对每个 agent 跑一遍**，是 `Harness`/`DetGate`/`BackendGate` 的热路径（CI 22-26 分钟的大头）。
同一条命令（`--seeds 1-3 --days 60 --det 1`）、同一台机器、连着跑：

| | 用时 | 相对基线 |
|---|---|---|
| 基线（未改动的树） | **51 s** | 1.00× |
| **tier1**（`space`/`floor` + `option.action`/`subject`） | **52 s** | **1.02×** |
| **tier2**（再加 `attitudes` + 关系账本五元 + `beliefs` + `coin`） | **125 s** | **2.45×** |

⇒ **tier1 的性能代价约等于零；tier2 把这一格的墙钟翻了 2.45 倍。**
而且这还是 **N=12**：关系账本那一层是 **O(N²)**（N=60 时每 tick 3600 条而不是 132 条）
⇒ **红线 #3 的 N=60 目标下，tier2 的斜率比这张表更陡。**

⚠ 三次运行、每档 N=1，没做重复测量 ⇒ **51 vs 52 这一格分辨不出真实差异**（它落在噪声里，本来就该如此）；
**51 vs 125 这一格远超噪声**，是结论承重的那一格。

### 4.4 不扩的代价

不扩就**必须把话说清**，否则"逐字节一致"这句话会继续被读成它并不成立的意思：

> 今天这句话的**准确**含义是：**事件账本逐字节一致，且逐 tick 的 `pos`/`needs`/`talking`/`option`(六元) 一致。**
> 它**不**保证 `beliefs`/`attitudes`/关系账本/`space`/`floor`/`money`/`town_stock`/`skills` 在两次跑之间相同——
> 只保证它们的**下游后果**迟早会显形（实测 0..1784 tick 之内，且 10 天内有 2/5 seed 不显形）。

---

## 五、建议（**决定留给用户**）

**我建议扩，但只扩到 tier1，并且把 §四.4 那段话同时写进契约。** 理由，按证据强度：

**阶段 1（建议现在做）· 便宜、证据强、并且修掉一条已知的碰撞**
- `space` / `floor`（每 agent 两个字符串）——结构地址，`_same_plane` 直接读；实测确有碰撞。
- `option.action` / `option.subject`（在**已有**的格式串里加两项，几乎零成本）——
  这一条还**顺带修掉 §2.4 那个反复出现的"晚 10 tick"**，而且 P1 五波前就写下了它。
- **金标代价**：`chain` + `chain_ck` 两列重烘，两份锚（不是三份）。**实测已跑通。**

**阶段 2（建议先别做，等一个真实需求）**
- `attitudes` + 关系账本五元 + `beliefs` + `coin`。**它们确实驱动未来**（5/5、5/5、3/5、5/5）。
- 但：① `chain` 今天**已经**能抓到它们，只是晚 6..1028 tick；
  ② **实测把这一格的墙钟从 51 s 打到 125 s（2.45×）**，而关系账本是 O(N²)、红线 #3 的目标是 N=60
  ⇒ **这是阶段 2 真正的代价，也是我建议先别做的主要理由**；
  ③ 金标代价与阶段 1 **完全相同**（同样只动 `chain` 一列）⇒ **分阶段不是为了省金标，是为了省性能与复核成本**。

**阶段 3（不建议）**
- `memory`/`mood`/`agent.affinity`/`last_say`/`talk_with`：前两个是**死字段**，后三个是 View/玩家侧。
- **`mood` 与 `agent["affinity"]` 的正确处置不是折进哈希，是删掉**——
  它们在 `save_game` 里占着"权威状态"的名分而全仓零读。⚠ 但那是 `game/scripts/**`，**不是我的 owns**。

**⚠ 与阶段无关、但我认为更该先做的一件事**：§〇·3 那条。
`ModelPathGate` 8 天 / `DetGate` 20 天的 horizon 与实测盲窗（最长 7.4 天）是**同一个量级**。
**扩 hash 会把盲窗压到 0，但"短门的 horizon 够不够"是一个独立的问题**，
且它对**今天**就成立——即使一个字段都不扩，也值得单独量一次。

---

## 六、CI 实际输出

（见下节 §六.1，逐字贴的是 `bash tools/ci.sh` 的真输出。）

---

## 七、§2.5 探测包络

⚠ **本波【没有新增或收紧任何一道门】**——我只加了一个只读探针。
所以下面这份包络写的是**探针本身**（`game/bench/ac1_state_coverage.gd`）的判别力：
它是本波全部结论的量具，**量具自己的盲区必须写出来**，否则 §一/§二 的数字就没有边界。

```
detects:
  · 「字段 X 有没有被折进 chain_step / digest」——就地扰动 + 同 prev/ev_from 重算。
    实测在 135 个字段上跑通（world 100 + agent 35），并**逐个**给出 YES/no。
    正对照：pos/needs/talking/option/id 报 YES（它们确在源码里）；event_log 九个子键 digest 全 YES。
    负对照：space/floor/attitudes/relationships 七元报 no —— 与 docs/66 (Q1) 五波前
            **独立**实测的「chain_step 不含 attitudes」**一致**（跨棒交叉核对，不是自证）。
  · 「干预到底落地没有」——干预前后各算一次全状态指纹（save_game 口径）。
    **实测抓到了我自己的三个 no-op 干预**（skills 键写错 / memory 参数顺序反 / pacts 缺 status
    导致 _active_pact_count 抛错），见 §2.2 —— 这一栏是它**已经**兑现过的价值，不是设想。
  · 「假 id 干预」——把 stifled/metKnower/complementSeen 的键从 "__ac1__" 换成真 id 后重跑，
    结论未变（仍 0/5）⇒ 排除了「查表永远命中不了」这一种伪阴性。

does_not_detect:
  · **「never」不等于「永远不会」。** 窗口是 10 天 × 5 seed；skills/beliefs 各有 2/5 个 seed
    在窗口内没分叉，**我没有把那两格测到底**。任何"该字段不驱动未来"的读法都超出了这份数据。
  · **抓不到"读路径存在但这组 seed 没走到"**：stifled/metKnower/complementSeen 有 grep 证明的
    真实门（:2540/:2543/:4448/:4450），干预却 0/5 传出去 —— 探针**分不出**「门没被触发」与「字段惰性」。
  · **抓不到我没造臂的字段**：25 条臂是我挑的。_short_day/_trade_day/_st_delta/econ_stats/
    prod_stats/cand_calls 等六个演化字段**一条臂都没有**。
  · **只在 N=12 / backend=null / 无 LOD 下量过**。LOD 激进档会冻结远端 agent，
    盲窗在那一档是什么样子，**我一格都没跑**。
  · **扰动器是通用的**（int+1 / String+"Z" / Dictionary 改首键…）：对"值域受限"的字段
    （枚举串、被 clamp 的数）它造出的可能是**非法值**。§一 只重算哈希、立刻还原，
    所以非法值无害；但这意味着 §一 量的是**「这个字段在不在哈希输入里」**，
    **不是**「一个合法的改动会不会被抓到」——后者是 §二 的事，两者别混。
  · **分母依赖一份复制品**：save_game 的三个排除表在探针里是抄的（§1.1）。
    save_game 改了而探针没跟 ⇒ 分母静默错。探针**印出**每行归类，但**不判红**
    ——按本仓库自己的话说，「打印了却不阻止就不是检查」⇒ **这一条今天是个已知缺口。**

confidence:
  · 覆盖（§一）：N=135 个字段 × 1 个 (seed,tick) 快照。**覆盖判定与 seed 无关**
    （chain_step 的输入集是结构性的），但我**只在 seed 1 / t0=480 验过**，没做跨 seed 复核。
  · 驱动未来（§二）：**N=25 臂 × 5 seed = 125 格**，全部 landed=5/5。
    ⚠ 5 个 seed 已经足够暴露判决翻转（beliefs 3/5、skills 3/5、weather 2/5、area 2/5、faction 1/5）
    ⇒ **单 seed 会写错 5/25 条**；但 5 个 seed 也**不足以**给出比例的置信区间。
  · 金标 blast radius（§4.1）：**N=2 档 × 3 seed × 60 天**，两档形状一致。
  · 性能（§4.3）：**每档 N=1 次运行**，51/52/125 s ⇒ **51 vs 52 分辨不出**，51 vs 125 远超噪声。
```

---

## 八、边界与我没做的事

- **我没有改任何判据、没有扩任何 hash、没有重烘任何金标。** 本波是"量 + 给选项"，扩不扩是用户的决定。
- **10 天 × 5 seed 是一个窗口，不是全部**：`skills`/`beliefs` 各有 2/5 seed 在窗口内没分叉——
  **那两格到底是"更晚"还是"永远"，我没测到底**，别把 `never` 读成"永远不会"。
- **25 条臂是我挑的**，不是权威状态的全覆盖；`_short_day`/`_trade_day`/`_st_delta`/
  `econ_stats`/`prod_stats`/`cand_calls` 等诊断计数器我没单独造臂（它们的读路径是"只写不读"或日名额簿记）。
- **N=12、`backend=null`、无 LOD**。N=60 与 LOD 档下的盲窗我没量。
- §4.2 那个 ×1.67 是**代理指标**，见那一段自己的警告。
