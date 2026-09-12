# 116 · AD2 · 事件结果模型设计（**§0.8 立项前设计——只设计，不实现**）

> owns：**只写本文件**。`game/` / `tools/` / 其余 `docs/` **一个字节都没改**（读码可以，改码不行）。
> 收尾 `git diff --stat` 只应有本文件。基线：`integration/batons`（本 worktree ff 到 `160559c`）。
> 依据：[docs/41](41-baton-contract.md) 全文（**§0.8 大设计前评审、红线 #2、§3 会移动 digest 的改动、§4 报告契约、§5 度量纪律**）、
> [docs/113](113-macro-roadmap.md) §一/§二、[docs/114](114-wave-ad-plan.md) §二（本棒 brief）、[docs/47](47-wave-e-plan.md) §〇（R12）、
> [docs/105](105-wave-aa-aa2-story-polarity-lock.md)（AA2 的 27.4% 实测与"两路打架"）。
> **本文所有行号、字段、计数都以本棒实读代码为准；brief 与 AA2 的断言凡对不上处，见 §七逐条纠正。**

---

## 〇、一句话与三条最重要的纠正

问题（Codex red #3 + AA2 实测）：**Sim 的状态转移是权威语义，而表现层把 `accepted=false`（被拒/未生效）的事件叙述成 happened**。
AA2 量到出货树 3565 条出处引用里 976 条（27.4%）如此。提议的模型：事件显式携带 `attempted / accepted / effect_applied / rejection_reason`，表现层只在效果真发生时叙述结果。

**读完代码后，三条会直接改变立项判断的事实**（详见 §二、§七）：

1. **测到的那 27.4% 不需要任何 schema 改动就能修。** `accepted` 字段今天**已经在事件上**（`Sim.gd:3801-3802`），
   且对通用社交路**已经正确地区分了被拒**（`Sim.gd:2423` 分支）。bug 在表现层：`Main._event_prose`
   对社交类型**不读 `accepted`**（`Main.gd:2128-2145` 那十来行没有 `if ok` 分支）。**这是一个读侧漏字段的 bug，不是一个缺字段的 bug。**
2. **金标折的是【具名字段】，不是整条事件字典。** 三处折叠（`Sim.gd:3806`、`Invariants.gd:1400-1404`、`:1441-1444`）
   都按字段名 `.get(...)` 取值。⇒ **往事件字典里加一个不被折叠的新键，结构上不动任何 digest**（推断依据见 §一.4、§三）。
   金标会不会动，**取决于两件事**：改不改现有字段的值、加不加**新事件**、以及**要不要把新字段并进折叠**——后者是用户的判断，不是必然。
3. **"两路打架"不是数据有歧义，是一个消费者丢了字段。** 权威侧（`accepted=false`）含义明确，`Sim` 自己的记忆文案读对了
   （`Sim.gd:2433`「被婉拒了」），只有 `Main._event_prose` 忽略它。brief 说的"Sim 记忆说被婉拒、`_event_prose` 不分岔"
   **完全属实**；但这意味着**修法是让表现层服从既有权威**，而不是先去消解一个并不存在的语义冲突。

⚠️ **本文不替用户拍板**。改 schema / 改判据 / 移金标是用户的决定（docs/113 §六）。本文给的是让用户能拍板的材料：现状、三条路的代价、一条推荐、分阶段、以及**设计阶段答不了的清单**。
**本文不引用任何"改善"数字当判据**——唯一出现的两个数（27.4%、AA2 估的 −80%）是**观测计数**，不是门的红/绿余量，口径见 §六。

---

## 一、现状盘点（**读码，给行号**）

### 1.1 今天 `event_log` 的事件字典有哪些字段

唯一构造点 `Sim._log_event`（`Sim.gd:3797` 签名，`:3801-3802` 字典字面量）：

```gdscript
# Sim.gd:3801-3802
var ev := {"id": _next_event_id, "tick": tick_no, "type": type, "actor": actor_id,
    "target": target_id, "subject": subject, "accepted": accepted, "witnesses": wids, "note": note}
```

**九个字段**：`id` · `tick` · `type` · `actor` · `target` · `subject` · `accepted` · `witnesses` · `note`。
`accepted` 是**必填的第五个位置参数**（`bool`），`note` 缺省 `""`。**没有** `attempted` / `effect_applied` / `rejection_reason`——
`git log -S "effect_applied" -- game/` 与 `-S "rejection_reason"` 均**零命中**（这两个名字在 `game/` 历史上**从未存在过**，
不是"曾接上又摘掉"，是全新绿地；`grep attempted game/` 亦零命中）。⇒ 三个新名字都干净，不会撞历史语义。

### 1.2 `accepted` 现在**谁写**（全部写点，含它的恒定性）

`_log_event` 的全部调用点（`Sim.gd`），按 `accepted` 实参分三类：

| `accepted` 语义类 | 事件类型（行号） | 写入值 | 能否为 false |
|---|---|---|---|
| **成/败**（同处写两条分支） | `meet`(`:2597`真/`:2608`假) · `confront`(`:2703`/`:2718`) · `apologize`(`:2744`/`:2750`) · `mediate`(`:1092`真/`:1102`假) · `election`(`:3143`=`res.pass`) · `rally_oust`(`:4335`=`backers>0`) | 真值 | ✅ 真会两边都出现 |
| **接受/婉拒**（通用社交路，一条 `_log_event(action,…)`） | 被拒 `:2426`(false) / 接受 `:2559`(true)，覆盖 `greet`·`give`·`gossip`·`gossip_rep`·`discuss`·`invite`·`confide`·`leak`·`endorse`·`aid`（`KNOWN_SOCIAL_ACTIONS`，`Sim.gd:953`） | `_acceptance_rule`(`:3658`) | ✅ 由接受规则决定 |
| **恒定标记**（同一类型永远同值） | `produce`/`consume`/`spoil`(`_stock_move`,`:3331`,恒 true) · `pay`(`:3205`,恒 true) · `world` spawn/despawn(`:3065`/`:3076`,恒 true) · `betray`(`:2507`,恒 true) · `confide` 接受态(`:2559`) · `conflict`(`:2684`,恒 false) · `shortage`(`:3464`,恒 false) · `pact` formed(`:4476`,true)/dissolved(`:4412`,false) | 字面常量 | ❌ 无判别力 |

> **关键**：`accepted` **不是一个含义统一的字段**（AA2 §2.2 已量，本棒复核成立）。它在"成/败"类是极性、在"接受/婉拒"类是接受门、在"恒定标记"类是零信息。
> **⇒ 任何"给 accepted 统一加语义"的改法都是欠定的**——必须按事件类型分档。这是本盘点最该被下一步继承的口径。

### 1.3 `accepted` 现在**谁读**（下游消费者，给行号）

| 读点 | 文件:行 | 在金标路径里吗 | 一旦 `accepted` 语义变会怎样 |
|---|---|---|---|
| **硬不变量 #10**（违约=`meet ∧ ¬accepted`） | `Invariants.gd:343` | ✅ **是**（S0 门每 CI 跑） | 直接红（这是它的牙） |
| **硬不变量 #12**（先对质后和解=`apologize ∧ accepted` 溯源） | `Invariants.gd:369` | ✅ 是 | 直接红 |
| 其余不变量读 `accepted` 的点 | `Invariants.gd:225,310,390,406,454,496,561,573`（共 10 处） | ✅ 是 | 判据依赖它 |
| Digest 折叠（见 1.4） | `Invariants.gd:1402,1443`；`Sim.gd:3806` | ✅ 是 | 见 §一.4 |
| **Goals 折叠匹配器** | `Goals.gd:177,201`；数据 `goals.json:42,50,66,75,83,91,107,108` | 集成场景 `goals_test` | 目标弧识别错 |
| **表现层 `_event_prose`** | `Main.gd:2125`（读），分支见 1.5 | ❌ 否（UI，不进金标） | 屏幕文案（正是 bug 所在） |
| **表现层 `_salience`** | `Main.gd:2172`（`¬accepted → +6`） | ❌ 否 | 失败事件的置顶权重 |
| **Story 极性锁**（AA2 建） | `Story.gd:167-175`（`accepted:true/false` 短语表） | ❌ 否（`grep Story game/bench/`＝0） | 极性锁判据 |
| **Audio 音效线索** | `Audio.gd:243`（`accepted ? 成 : 败`） | 录制路径 | 音效选错 |
| Metrics / 各探针 / 账本 | `Metrics.gd:48,84,109` · `affinity_ledger.gd`(≥12 处) · `BackendBench.gd:395` · `lod_observation_probe.gd:255` · `s4_replay_test.gd:46` 等 | 部分在门里 | 计量/账本 |

> ⇒ **`accepted` 是一个被 40+ 不变量与多个子系统共读的承重字段**。这条决定了一个方向：
> **只能【加】字段，不能【改】`accepted` 的含义**——重定义它会同时打中 #10/#12 等硬门与账本、目标、故事三层。

### 1.4 金标到底折哪些字段（**这是"金标影响"的全部推断依据**）

三处独立折叠，全部**按字段名取值**，不遍历整条字典：

```gdscript
# ① Sim 滚动 event_digest（Sim.gd:3806）——折 7 个字段，无 witnesses、无 note
"%d:%s:%s:%s:%d:%s:%d" % [id, type, actor, target, int(accepted), subject, tick]

# ② Inv.digest 全程摘要（Invariants.gd:1400-1404）——折全部 9 个字段（含 witnesses、note）
"%d:%s:%s:%s:%d:%s:%d:%s:%s" % [id, type, actor, target, int(accepted), subject, tick, wstr, note]

# ③ chain_step 逐 tick 前缀链（Invariants.gd:1441-1444）——折 6 个事件字段（含 note，无 witnesses、无 tick）
"%d:%s:%s:%s:%d:%s:%s" % [id, type, actor, target, int(accepted), subject, note]
```

金标 S0 行同时比对 `digest`（②）、`event_digest`（①）、`chain`（③）、`events`（＝`event_log.size()`）四项（AA2 §六复核）。

**由此推出三条金标影响法则**（**结构性推断，非"应该不大"**）：

- **法则 A（加不折的字段＝零影响）**：往 `_log_event` 的字典里加一个新键，只要**不**把它写进上面①②③任一个格式串、且不改任何现有字段的值、不改事件条数与顺序 ⇒ **三个 digest 逐字节不变**，`events` 不变 ⇒ **不触发 R12**。依据：①②③ 都靠 `.get("<名>")` 显式取值，GDScript 字典按键取值与插入序无关。
- **法则 B（加新事件＝全动）**：任何**新增一条 `event_log` 记录**（如把今天不落账的失败尝试记下来）都会让该 seed 之后**所有事件的 `id` 平移**（`_next_event_id` 单调，`Sim.gd:3803`）⇒ ①②③ 全变、`events` 变 ⇒ **每个产生该事件的 seed 都移金标 ⇒ 必走完整 R12**。
- **法则 C（把新字段并进折叠＝全动）**：若采纳 docs/41 `Invariants.gd:1381-1391` 的"语义承重字段应当被折叠"哲学，把 `effect_applied`/`rejection_reason` 加进②③ ⇒ 每个带该字段的事件都改折叠串 ⇒ **每 seed 移金标 ⇒ 完整 R12**。**折不折是用户的判断题**：不折＝金标看不见它（法则 A）、折＝金标钉住它但要重烘。

### 1.5 表现层今天错在哪（bug 的精确定位）

`Main._event_prose`（`Main.gd:2120-2167`）按类型 `match`。**读 `accepted`/`note` 分岔的**（正确）：
`meet`(`:2132`) · `confront`(`:2134`) · `apologize`(`:2135`) · `mediate`(`:2136`) · `election`(`:2160`) · `pact`(按 note,`:2153`) · `world`(按 note,`:2161`) · `rally_oust`(按 backers,`:2146`)——共 8 种。

**不分岔、恒叙述成"发生了"的**（bug）：`greet`(`:2128`) · `give`(`:2129`) · `gossip`(`:2130`) · `invite`(`:2131`) · `gossip_rep`(`:2142`) · `endorse`(`:2143`) · `discuss`(`:2144`) · `aid`(`:2145`) · `confide`(`:2140`) · `leak`(`:2141`)。
这十种里，**在出货沙盘真的带大量 `accepted=false`** 的是 `gossip_rep`(−5143) · `greet`(−1374) · `discuss`(−810) · `gossip`(−396)（计数取自 AA2 §2.2）——**976 条 / 27.4% 就落在这里**。
其余（`confide` −0、`invite` −0、`aid`/`endorse`/`give` 罕见/恒真）今天是**潜伏**：一旦换阵容/多镇让它们被拒，屏幕立刻说反。

> 补一条本棒新查到、AA2 未点的**默认值不一致**：`_event_prose` 读 `accepted` 缺省 **false**（`Main.gd:2125`），
> 而 `_salience` 读 `accepted` 缺省 **true**（`Main.gd:2172`）。⇒ 一个"没有 accepted 概念"的新事件类型，
> 会被 `_salience` 当成功、被 `_event_prose` 当失败。设计新类型时必须显式给 `accepted`，别靠缺省。

### 1.6 哪些类型"根本没有 accepted 概念"，以及它们今天怎么表达失败

- **经济族**（`produce`/`consume`/`spoil`/`pay`/`shortage`）**全在 `FEED_SKIP`**（`Main.gd:284`）⇒ **根本不进表现层信息流**，所以 27.4% 那个 bug **与它们无关**。它们的"失败"今天用**别的机制**表达，而不是 `accepted=false`：
  - **产不出**：`_stock_move` 在 `applied==0`（满仓/见底）时**不落任何事件**（`Sim.gd:3328` 提前 return）；
  - **买不到**：单独的 `shortage` 事件（`Sim.gd:3464`，`accepted` 恒 false，是"想要而镇上空了"的独立类型）；
  - **付不起**：`transfer` 资金不足时**直接 return false、不落事件**（`Sim.gd:3202`）⇒ **失败的支付今天完全不可观测**。
- ⇒ "让经济族也带 attempted/rejection_reason"意味着**新增今天不存在的事件**（失败支付、被挡产出）⇒ **法则 B ⇒ 全动金标**，而收益是给一族**本就不上屏**的事件加可观测性。**这是代价最高、可见收益最低的一档**（分阶段里排最后，§五）。

---

## 二、一个必须先讲清的事实：**测到的 bug 与"完整模型"是两件事**

把提议的四字段拆开，对着现状看，它们的**必要性与代价天差地别**：

| 概念 | 今天有没有 | 差什么 | 修它要动金标吗 |
|---|---|---|---|
| **attempted** | **部分有**：社交路每次尝试都落一条事件（无论成败）；但**失败支付/被挡产出不落事件** | 只有"今天不落事件的失败"才缺 | 补这些＝**加新事件＝法则 B＝全动** |
| **accepted** | **有**（`Sim.gd:3801`），社交路已正确区分被拒（`:2423`） | 不缺；缺的是**表现层去读它**（`Main.gd` 社交分支） | 修表现层＝Main/Story，**不进金标＝零影响** |
| **effect_applied** | **没有**。且"accepted 但效果没落"**真实存在**：`gossip` 对已知者不转信念(`:2450` 的 guard)、`gossip_rep`(`:2473`)、`confide`(`:2482`)、`endorse`(`:2521`)、`aid`(`:2531`) 都有内层 guard | 需 Sim 记录"守卫是否放行"，一个新 bool | **加不折的字段＝法则 A＝零影响**；折进去＝法则 C |
| **rejection_reason** | **没有**，但**原料齐了**：`_acceptance_margin`(`Sim.gd:3714-3715`) 已算出 `sum/threshold/aff/st/need/fac/jitter`，被拒时哪一项主导是**纯读**、不耗新 RNG | 需定一套稳定的 reason 标签并从 margin 派生 | 同上：加不折＝零影响 |

**⇒ 立项的真正问题不是"要不要事件结果模型"，而是"要覆盖到哪一档"**：

- **档 0（表现层修复）**：只让 `Main._event_prose` 对社交类型读 `accepted`（Story 的极性锁 AA2 已铺好基建）。**零 schema、零金标、直接消掉 976/27.4% 的绝大部分。**
- **档 1（语义补全，加不折字段）**：加 `effect_applied` + `rejection_reason` 到事件字典，**不折进金标**。给 NPC 记忆/未来 storylet/wiki 更细的"接受但没生效/为什么被拒"。**零金标（法则 A）。**
- **档 2（可观测性扩张，加新事件）**：把今天不落账的失败（付不起、被挡产出）也记下来，或把新字段**折进金标**钉死。**每个受影响 seed 移金标 ⇒ 完整 R12。**

这三档正好对上下面三条实现路。

---

## 三、三条（＋）实现路的代价对照

口径：**金标影响一律给法则 A/B/C 的结构性推断依据**，不写"应该不大"。

### 路 (a)：在现有 event dict 上**加字段**（`effect_applied` / `rejection_reason`，可选 `attempt_id`）

- **schema 改动**：`_log_event` 签名加 2 个可选参数、字典加 2 个键（`Sim.gd:3797/3801`）。调用点可渐进改（缺省值＝旧行为）。
- **金标影响**：**取决于折不折**。
  - 不折（推荐起步）＝**法则 A：三个 digest、`events` 全部逐字节不变，不触发 R12**。**推断依据**：①②③ 折叠串（`Sim.gd:3806`、`Invariants.gd:1400-1404`、`:1441-1444`）不含新键，加键不改这三串。
  - 折进去＝**法则 C：每带该字段的事件移金标，完整 R12**。
  - 派生 `rejection_reason` **不耗新 RNG**（`_acceptance_margin` 今天已被 `_acceptance_rule` 调用，`Sim.gd:3659`）⇒ 不因"多算一次"而移轨迹。
- **迁移成本**：**低**。字段可增量铺；旧读者不受影响（多一个键，`.get` 不受扰）。
- **对 40+ 不变量的冲击**：**近零**（不改 `accepted` 含义、不加事件）。若把 `effect_applied` 折进③，才需重烘并复验 #10/#12 语义仍成立。
- **对 AA2 短语锁 / narrative 的下游**：**正向**。Story 极性锁读的是 `accepted`/`note`（`Story.gd:167-175`），新字段是**额外**信号，不破坏既有锁；表现层修复（档 0）可与本路解耦先行。
- ⚠️ 与 `story_test` 的 `F2/F6` 夹具相关：AA2 §一·3 指出它们写的正是 `gossip_rep accepted=false`——**给故事槽位补 `accepted` 过滤时会撞这两组夹具**，需同批 rebaseline（不是本路加字段造成的，是"修表现/故事"这件事本身要处理的）。

### 路 (b)：**单独的 outcome 事件**（attempt 一条 + outcome 一条，outcome 引用 attempt）

- **schema 改动**：新事件类型 `outcome`（或 `attempt`+`outcome` 成对），需 `ref` 字段指回 attempt 的 `id`。
- **金标影响**：**法则 B——全动**。每次社交尝试从 1 条变 2 条 ⇒ `event_log.size()` 约翻倍、`id` 全平移 ⇒ ①②③ 全变、`events` 变 ⇒ **12 个 seed 全部移金标，Day 1 就要完整 R12**（三份锚 + 留出 13-30，见 §四）。
- **迁移成本**：**高**。所有消费者（#10/#12 等不变量、`Goals.gd`、`affinity_ledger.gd`、`Story.gd`、`Metrics.gd`、各探针）都要从"读一条事件"改成"join attempt+outcome"。这是**一次性打散 40+ 判据**的改动。
- **对不变量的冲击**：**大**。#10 逐字是 `broken_events == c_broken`（`Invariants.gd:343` 数 `meet ∧ ¬accepted`）——拆成两条后"哪条算数"要重写。
- **对 narrative 的下游**：Story 的 `narrate_cited` 每行回指一条 `event`（`Story.gd`），拆成两条后可追溯性口径要重定义。
- **好处**：语义最干净（attempt 与 outcome 物理分离，天然支持"多次尝试同一目标"）。但对本项目**当前**问题是**过度工程**。

### 路 (c)：**每次 attempt 一条记录**（含今天完全不落账的尝试）

- **schema 改动**：为每一次"发起社交/支付/产出的意图"都落一条，无论是否到达 resolution。
- **金标影响**：**法则 B——最严重**。不仅翻倍，还要把**今天不产生任何事件**的路径（失败支付 `:3202`、被挡产出 `:3328`、未触发的社交）全部变成事件 ⇒ `event_log` 体量数量级上升 ⇒ 全 seed 全动。
- **迁移成本 / 不变量冲击**：**最高**，同 (b) 且更甚。
- **消费级硬件（红线 #3）**：**直接顶红线**。出货目标 60 居民、骁龙 8 Elite；`event_log` 是**全量保留**（不变量/账本回扫），每 tick 新增记录数量级上升 ⇒ 内存与逐 tick 折叠成本（`Sim.gd:3806` 每事件 O(1)，但条数爆炸）都上台阶。60 人长跑的内存封顶是既有痛点（见 MEMORY 里 #34 池化史）。
- **好处**：可观测性最大（能问"这次没成的支付是谁发起的"）。但**收益集中在今天不上屏的经济族**，性价比最低。

### 三路速览

| | schema | 金标（推断依据） | 迁移 | 对 40+ 不变量 | narrative/短语锁下游 | 硬件(红线#3) |
|---|---|---|---|---|---|---|
| **(a) 加字段** | 小（+2 键） | **不折＝零(法则A)**／折＝全动(法则C) | 低 | 近零 | 正向、可解耦先行 | 无影响 |
| **(b) 单独 outcome** | 中（新类型+ref） | **全动(法则B)**：条数≈×2 | 高（全消费者改 join） | 大（#10/#12 重写） | 可追溯口径重定义 | 事件×2 |
| **(c) 每 attempt 一条** | 中 | **全动(法则B)**：条数数量级↑ | 最高 | 最大 | 同上更甚 | **顶红线** |

---

## 四、推荐：**路 (a)，且分档落地**——先零金标修可见的，把移金标留到用户认它值

**推荐 (a)**，理由：

1. **测到的 bug（27.4%）在 (a) 的档 0 里零成本消掉**——不动 schema、不动金标（表现层 Main/Story 不在金标路径，`grep Story game/bench/`＝0，`_event_prose` 属 UI）。
2. **(a) 把"移不移金标"变成用户可控的旋钮**（折/不折＝法则 C/A），而 (b)(c) 从第一天就强制完整 R12 且打散 40+ 判据。
3. **(a) 不重定义 `accepted`**，因此不打中 #10/#12 与账本/目标/故事三层的既有读法（§一.3）。
4. (b) 的"物理分离 attempt/outcome"是更干净的架构，但对**当前**这个"表现层丢字段"的问题是过度工程；(c) 顶红线 #3。**若将来多镇/贸易真的需要"一次意图多次尝试"的时间线，再把 (b) 作为 `state_projection_v1`（docs/113 §一）的一部分单独立项**，而不是塞进本次修复。

**明写：档 2 必须走完整 R12。** 一旦"把新字段折进金标"或"新增失败事件"，就是 docs/41 §3 + docs/47 §〇 的受控动作：
① 确认蓄意行为变更并说清为什么 ② **重烘三份锚**——`Harness --bake-golden`（`golden_digests.json`）、`DetGate --bake-golden`、`ModelPathGate --bake-anchor`（`modelpath_anchor.json`，只烘前两份会让 `ci.sh` 第 4e 关必红）
③ `_meta.rebake_history` 补日期+原因 ④ **跑留出种子 13-30 改前/改后各一遍，两侧数字都报**。
**档 0/档 1（不折）不移金标 ⇒ 不适用 R12**，但仍需自造 A/B digest 证明"确实没动"（法则 A 是推断，落地要实测兑现）。

---

## 五、分阶段迁移方案（**按"被拒可观测性"排序**）

排序依据＝该类型今天**既带真被拒、又上屏、且表现层现在讲错**的程度（计数取 AA2 §2.2，均为观测计数非门余量）。

- **阶段 1 — 表现层修复，零金标**（先干这个）：让 `Main._event_prose` 对 `gossip_rep`(−5143)、`greet`(−1374)、`discuss`(−810)、`gossip`(−396) 读 `accepted` 分岔；Story 侧把这四类（+两条 `aside`）纳入 AA2 极性锁。**这一步吃掉 976/27.4% 的主体，不碰 schema、不碰金标。** 需处理 `story_test` F2/F6 夹具（AA2 已预警）。
  - 验收：重跑 AA2 的 `slot_polarity` 探针，量修后引用里"被拒叙述成 happened"降到多少（AA2 估掉 ~80%，**是估计、未在修后树上跑过**，见 §六）。表现层改动**必须眼验**（`_event_prose` 在 record/visual 路径，出一张改前/改后面板图）。
- **阶段 2 — 潜伏社交类型补分岔，零金标**：`confide`/`invite`/`aid`/`endorse`/`give`/`leak` 今天罕见/无被拒，但换阵容/多镇会触发。给它们的表现分岔补上，**修的是"当它发生时说对"**，不是"现在有 bug"。也不动 schema。
- **阶段 3 — 加 `effect_applied` + `rejection_reason`（不折），零金标**：Sim 在社交效果块（`:2443-2541`）记录内层 guard 是否放行（`effect_applied`），并从 `_acceptance_margin`（`:3714`）派生 `rejection_reason` 标签。供 NPC 记忆、wiki、storylet 用更细的语义。**用 A/B digest 证明不动金标（法则 A）。**
- **阶段 4 — 经济族失败可观测（移金标，完整 R12）**：仅当确有需求（如经济 storylet 要讲"某人付不起房租"）才做。给失败支付/被挡产出落事件 ⇒ 法则 B ⇒ **完整 R12**。**排最后**，因为经济族在 `FEED_SKIP` 里、可见收益最低、代价（金标+性能）最高。
- **阶段 5（可选，用户拍板）— 把语义字段折进金标**：若判断 `effect_applied`/`rejection_reason` 是"语义承重、金标必须钉住"（docs/41 `Invariants.gd:1381-1391` 的哲学），走法则 C 折进②③ ⇒ 完整 R12。**这是纯判据口径决定，交用户。**

---

## 六、风险与未知（**照实列——哪些是设计阶段答不了、必须实现后实测的**）

1. **法则 A 是结构性推断，不是实测。** 落地时**必须**自造 A/B（改前/改后各跑 `Harness --chain-dump`，逐 tick 前缀链 sha256 比对 + 留出 13-30）兑现"digest 真没动"。历史上"读了注释以为没动"翻车过（docs/41 §4）。
2. **阶段 1 修后 976 条实际掉多少，设计阶段答不了。** AA2 的 −80% 是**估计、未在修后树上跑过**（AA2 §十一 自曝）。**这是观测计数，不是门余量**——本文不拿它当判据；真值要在修后树重跑 `slot_polarity`。
3. **`rejection_reason` 的标签体系答不了。** `_acceptance_margin`（`:3714`）给的是连续 `sum/threshold` 与各分项，但"哪一项主导＝被拒原因"需要一套**稳定、确定性**的判定（并列时的平局抖动盐必须取稳定身份，红线 #1）。标签定义本身是设计题，且它一旦上屏/进记忆就是模型语音的 grounding 原料，错了会传播。
4. **表现层修复对视觉/录制门的影响答不了。** `Main.gd` 不进金标，但**在 record/visual 路径**（docs/41 §6）。改文案要眼验（headless 绿≠屏幕对），且要确认不误伤 `visual_gate`/`chat-shoot` 类脚本。
5. **`effect_applied` 的语义边界要实现后才清。** 内层 guard 有多种（信念已知、subject 不存在、need 不匹配…），"效果没落"该记成一个 bool 还是分原因，取决于消费者要多细——设计阶段可先定 bool，用起来再细化。
6. **性能：任何新增事件（阶段 4）在 60 人真机上的内存/逐 tick 成本没测。** 红线 #3 要求消费级手机；`event_log` 全量保留。**必须真机实测**（MEMORY #34 的池化史说明满负载内存是真痛点），不能估。
7. **`story_test` F2/F6 夹具与阶段 1 的耦合**要在实现时一并 rebaseline（AA2 §一·3 预警），否则修表现会让这两组夹具红。
8. **"被拒事件到底要不要上屏"是产品决定，不是本文能定的**：叙述"尝试/被婉拒" vs 干脆不显示 `accepted=false` 的社交，是 UX/产品取舍，交用户。

---

## 七、这份 brief（docs/114 §二）哪里是错的

**brief 对现状的断言，逐条对代码复核**：

1. **brief：「根因是 `discuss`/`gossip`/`gossip_rep` 那族匹配器不筛 `accepted`，且 Sim 记忆说被婉拒而 `Main._event_prose` 对同类型不分岔——两路打架」——事实层面**全部属实**，但"根因"指向偏了。**匹配器不筛 `accepted`是 Story 层的现象；真正让 976 条上屏说反的是 `Main._event_prose`（`Main.gd:2128-2145`）对社交类型压根不读 `accepted`**。Story 的匹配器"不筛"只是让极性锁盖不住，`_event_prose` 的"不分岔"才是屏幕上真出错的那一处。两者要分开修（Story 极性锁 + Main 表现分岔），brief 把它们并成一句"匹配器不筛"会让人以为只改匹配器。
2. **brief 的提议模型 `attempted / accepted / effect_applied / rejection_reason` 预设了"缺一整套 schema"。实测：`accepted` 已在、社交路已正确区分被拒（`Sim.gd:2423`）。** 测到的 27.4% **不需要任何 schema 改动**就能修（表现层读既有字段）。提议的另三个字段（attempted/effect_applied/rejection_reason）是**语义增强**，价值真实但**与"修那 27.4%"是两件事**——把它们捆成"必须先上 schema 才能修 bug"会把一个零金标的表现修复升格成架构改动。
3. **brief：「事件显式携带四字段，Sim 为唯一权威」——方向对，但"携带"这个词掩盖了金标的判断题。** 携带（加不折的字段）＝零金标（法则 A）；把它折进金标钉死＝全动（法则 C）。**"要不要折"才是用户真正要拍的板**，而 brief 没点出这一层。
4. **brief 把它列为"改事件 schema，属 §0.8"因此"只做设计"——§0.8 的判断对，但触发它的不是 schema。** 即便一个字段都不加（只走档 0 表现层修复），改的是社交叙述这一**共享表现面**，仍值得评审；而真正的架构级动作（移金标）只在档 2/阶段 4/5 才发生。**"是不是 §0.8"和"动不动 schema"在这里不是一回事。**
5. **brief（转述 AA2）说"两路打架，AA2 按 §0.8 没动"——复核成立**，但要点是：**数据侧没有歧义**（`accepted=false` 明确），打架的是两个消费者。**所以修法不是"消解冲突"，是"指定 Sim 记忆那一路为准、让 `_event_prose` 服从"**——这正是 brief 自己说的"Sim 为唯一权威"，只是它没说清"两路打架"其实是"一路读对一路读漏"。

**顺带纠正一处 brief 的下游断言**（docs/114 §一 AD1 部分，虽非本棒 owns，但派棒者写给两棒共用）：AD1 brief 说 wiki 层用 `event.accepted` 区分"做成了/被拒了"——**对社交路成立，但对经济族不成立**：`produce`/`consume`/`pay` 的 `accepted` 恒 true，"失败"是 `shortage` 事件或"无事件"（§一.6），wiki 若照 `accepted` 读经济族会把所有产出都读成"做成了"。这条口径 AD1 需要知道。

---

## 附：交付自查

- **零代码改动**：`git diff --stat` 只应有 `docs/116-*`（本文件）。未碰任何 `game/` / `tools/` / 其它 `docs/`。
- **未跑 CI**：本波不改代码、不改任何门读的文件，`ci.sh` 不受影响；未跑（无改动可验）。
- **度量诚实**：本文出现的 27.4%（AA2 实测计数）、−80%（AA2 估计、未在修后树跑过）**均为观测量，非门的红/绿余量**；本文不以任何"改善数字"作判据（docs/41 §5、docs/113 §六"红数不是判据"）。
- **行号会腐烂**：本文行号实读于 `160559c`。任何人在被引文件里增删行后，下面每条行号引用都会漂——**以符号/上下文为准，行号是线索不是契约**（docs/41 §1.5、`Invariants.gd:1390`「引符号，别引行号」）。
