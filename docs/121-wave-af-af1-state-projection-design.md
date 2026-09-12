# 121 · AF1 · `state_projection_v1` 设计（**§0.8 立项前设计——只设计，不实现**）

> owns：**只写本文件**。`game/` / `tools/` / 其余 `docs/` **一个字节都没改**（读码、在隔离副本里跑探针 = 可以；改 trunk = 不行）。
> 收尾 `git diff --stat` 只应有本文件。基线：`integration/batons`（本 worktree ff 到 `528c502`）。
> 依据：[docs/41](41-baton-contract.md)（**§0.8 大设计前评审、红线 #1 确定性、§3 会移动 digest 的改动、§4 报告契约、§5 度量纪律**）、
> [docs/113](113-macro-roadmap.md) §一（架构脊柱）/§二/§五、[docs/120](120-wave-af-plan.md) §一（本棒 brief）、
> [docs/116](116-wave-ad-ad2-event-outcome-model.md)（AD2 的"金标折具名字段"三法则，本文复用其推断框架）、
> [docs/108](108-wave-ac-plan.md)（AC1 立项）、[docs/66](66-faction-contact-gate.md)（Q1 回执：立场分叉早于行为分叉 557 tick）。
> **本文所有行号、字段、数字都以本棒【实读代码 + 实跑探针】为准；brief 与 AC1 回执凡对不上处，见 §八逐条纠正。**
> **本文不引用任何"改善数字"当判据**；所有数都是【观测量】，口径见 §三与附。

---

## 〇、一句话与三条会改变立项判断的事实

问题（外审两轮 + docs/113 §一"最贵的一句话"）：**权威状态投影不存在。** 今天的"逐字节一致"只覆盖
`event_log` + 一条**很窄**的活状态投影（tick + 逐 agent 的 id/pos/needs/talking/option），
**不覆盖** beliefs·attitudes·factions·affinity·pacts·standing·town_stock·space·floor·money·memory 等。
⇒ 两个只差一个此类字段的世界**哈希相同**，不足以承载存档正确性 / 换页 / 冷热镇等价 / 回滚。

**本棒实测后，三条会直接改变立项判断的事实**（详见 §一—§四）：

1. **AC1 探针（607 行）在当前 trunk（`528c502`）上跑通、结论成立、分母可信。** 它的三个 `save_game` 反射常量与
   trunk 现值**逐字抄写一致**（§二.1），所以它数出来的"100 个世界字段 / 35 个 agent 字段"这个分母是真的。
   **brief 说它"未验证"——本棒把它验了：形状对（§二）。** 但 brief 给的坐标 `Invariants.gd:1280/1310` 已腐烂，
   真身在 **`digest`→符号锚 `Invariants.gd:1392`、`chain_step`→`:1422`**（§一，行号是线索不是契约）。

2. **"digest 最终会不会看见它"是个陷阱——真正的判据是【点对点(point-in-time)】能不能分辨。**
   drive 实测里几乎每个"驱动未来"的字段最终都让 digest 变了（`DIFF`），**这会骗人**：那是跑完 10 天后
   **事件已经不同**了，digest 折的是那些**不同的事件**、不是那个字段。而存档/读档/换页/回滚是在一个
   **checkpoint 边界**上比等价——**那一刻没有"未来"可供传播**。本棒的点对点 A/B（§三.1）证明：
   在那一刻，`digest` **和** `chain_step` **都判两个不同世界为相同**（5/5 字段 `SAME`，而独立全状态指纹 `DIFF`）。
   ⇒ **"chain 早晚会抓到"不能替代"把字段折进投影"，因为"早晚"是无界且逐 seed 抖动的**（beliefs 在 seed 3
   跑满 2400 tick 都没现形；§三.2），而 checkpoint 边界的延迟预算是 **0**。

3. **这个盲区不是假想——今天的存档【硬门】就带着它。** `save_load_test.gd` 的 round-trip 判据逐字是
   `Inv.digest(B) == Inv.digest(A)`（该文件 :40）＋续跑 **N=60** tick 比 digest（:52-57）。本棒复刻它、
   喂一次"漏了某 agent beliefs 的读档"：**门①相等、门② 60 tick 零漂移 ⇒ 判 PASS**，且再跑 2400 tick 仍不现形（§四）。
   ⇒ **存档系统自己的正确性门，继承了 digest 的盲。这是当前 trunk 的真实缺口，不是多镇才需要的东西。**

⚠️ **本文不替用户拍板。** 建什么投影、覆盖到哪、要不要给它单独烘一份金标锚——是用户的决定（docs/113 §六）。
本文给的是让用户能拍板的材料：现状、实证、三条实现路的代价、一条推荐、分阶段、以及**设计阶段答不了的清单**。

---

## 一、现状盘点（**读码 + 探针实测**，符号锚 + 当前行号）

### 1.1 `Inv.digest` 折什么（符号锚 `Invariants.gd:1392`）

对 `S.event_log` 里**每条事件**折 9 个具名字段，`|` 拼接后过 `Sim.fnv1a32`：

```
id : type : actor : target : accepted : subject : tick : witnesses : note
```

**只遍历 `event_log`。** 一个 agent 的 beliefs、一个镇的 town_stock、谁在几楼——`digest` **一个字节都不看**。
探针"EVENT_LOG sub-keys"节实测：末事件的 9 个键 `in_digest` 全 `YES`；**除此之外无任何状态进 digest**。

### 1.2 `chain_step` 折什么（符号锚 `Invariants.gd:1422`，`CHAIN_INIT`=`:1419`）

逐 tick 前缀链 `H_t = h(H_{t-1} ‖ canon_state_t ‖ canon_events_t)`，其中：

- `S.tick_no`；
- **逐 agent**：`_aid(ag)`（id 缓存）、`pos(x,y)`、`needs`（每条量化到 1/65536）、`talking`、
  `option` 的**六元签名** `kind|target|partner|area|phase|remaining`；
- 自 `ev_from` 起本 tick 新增的事件：`id:type:actor:target:accepted:subject:note`（6 事件字段，无 witnesses、无 tick）。

⚠️ **两处关键遗漏（探针 OPTION 子键节实测）**：`option` 有 8 个键，chain 只折其中 4-6 个——
**不折 `action`**（真正选中的动作！）**也不折 `subject`/`need`/`amount`/`dur_total`**。这正是为什么行为指纹
（P1/Q1 的 `_fp_act` 口径）要**额外**把 `option.action` 与 `option.subject` 折进去——chain 自己看不见"他到底要做什么"。

### 1.3 探针实测的覆盖分母（`cover` 模式，seed 1，N=12，t0=480）

用**与 `save_game` 同一套反射**枚举字段，逐个就地扰动、用**固定 prev/ev_from** 重算 chain/digest（点对点判据）：

```
world: 可扰动 state 字段=100   in_chain=3   in_digest=1   （skip 12：derived/view/bench/wiring/unperturbable）
agent: 可扰动 state 字段=35    in_chain=5   in_digest=0   （skip 1：memory 是嵌套 Object）
```

- **world `in_chain=3`** = `tick_no` · `agents`（chain 遍历它）· `_aid_cache`（chain 读它，是派生缓存的假阳性）。
- **world `in_digest=1`** = `event_log`。
- **agent `in_chain=5`** = `id` · `pos` · `needs` · `option` · `talking`——**与 §1.2 逐字吻合**。
- **agent `in_digest=0`** = agent 状态一个字段都不进 digest。

只算**这一局里真的演化过**的字段（配置/常量由 data 文件 + 金标钉住，本不该进轨迹哈希）：

```
world: evolves=18   其中 chain/digest 两头都没折 = 15
agent: evolves=18   其中 chain/digest 两头都没折 = 14
```

⇒ **单 seed 单窗口就有 29 个"会演化、却两头都没折"的字段。** 这就是盲区的形状。
agent 侧点名（`evolves=YES` 且 `in_chain=in_digest=no`）：`inventory`(money/gift)、`relationships`、`beliefs`、
`attitudes`、`stifled`、`metKnower`、`faction`、`faction_size`、`complementSeen`、`skills`、`last_say`、`area`、`room`、`talk_with`。
world 侧点名：`day`、`weather_today`、`town_coin`、`town_stock`、`econ_stats`、`prod_stats`、`_short_day`、`_trade_day` 等。

> ⚠️ **space/floor 在本局 `evolves=no`**（seed 1，720 tick 内没人换平面）——这是"space·floor 盲窗"的第一个证据：
> cover 连"它有没有演化"都撞不到。点对点 A/B（§三.1）用**强制换平面**补了这个洞：space/floor **确实**点对点盲。

---

## 二、AC1 形状验证（**逐条对/错**）

### 2.1 探针能不能信：分母耦合复核 = **过**

AC1 把 `save_game` 里三个函数内 const 抄进探针（它自陈这是"一处真实耦合，抄错分母就悄悄错"）。本棒逐字比对当前 trunk：

| 常量 | 探针值 | trunk `save_game` 现值 | 一致 |
|---|---|---|---|
| `SAVE_DERIVED` | `_agent_by_id,_active_commitments,_near_set,_path_cache,_nav_grids,_player_pos` | 同（`Sim.gd` save_game 内 `DERIVED`） | ✅ |
| `SAVE_VIEW_PARAMS` | `lod_focus` | 同（`VIEW_PARAMS`） | ✅ |
| `SAVE_BENCH_ONLY` | `shadow_on,shadow_trace` | 同（`BENCH_ONLY`） | ✅ |

⇒ **探针的分母对当前 `528c502` 有效**，"100/35 个字段"不是手列的、是反射数出来的、且反射集与存档权威集一致。

### 2.2 探针方法学：**对**（并纠正一个会被误读的点）

AC1 把两个问题**分开**问，这是对的、也是 Codex 对它前身批评的正解：

- **①覆盖（瞬时/点对点）**：字段折进 chain/digest 没有——**扰动后就地重算、不读注释**。✅ 直接量、可执行。
- **②驱动未来（跨时）**：只改一个字段、跑两条完整臂，量 chain 首分叉 / 行为首分叉 / 终态 digest。
  它带**阳性对照**（干预前后 `_full_fp` 全状态指纹必须不等，否则 landed=NO ⇒ 结果不可用）——这一条是它最该被继承的纪律。

**探针自身跑通**：`cover` / `drive` 两模式在 trunk 上 rc=0，无 parse error、无 SCRIPT ERROR（唯一噪声是
可选 SLM 后端 `nobodywho.gdextension` 找不到的告警，与本 bench 无关）。**brief 说"未验证"——现已验证：形状对。**

> ⚠️ **一个必须点破的误读（也是 Codex 对 AC1 前身的原话批评"别用一天前后变没变代替未来读不读"的延伸）**：
> `drive` 表里几乎每个驱动未来的字段**终态 `digest=DIFF`**。**这不等于"digest 覆盖了它"**——见 §三.2 与 §〇.2。
> AC1 的 `drive` 量的是"字段会不会**最终**传播进事件"，而 `state_projection` 要的是"**在 checkpoint 那一刻**能不能分辨"。
> **两者是不同的问题**，AC1 把它们分开问了（这是对的），但读它的表时极易把 ②的 `DIFF` 当成①的覆盖。本文用 §三.1 把①单独钉死。

### 2.3 覆盖结论逐条：**与 §一实测一致**

| AC1/brief 断言 | 本棒实测 | 判 |
|---|---|---|
| `digest` 只折 `event_log` | cover：world `in_digest` 仅 `event_log`；agent `in_digest=0` | ✅ 对 |
| `chain` 折 tick+逐 agent id/pos/needs/talking/option | cover：agent `in_chain`={id,pos,needs,option,talking}，world 含 tick_no | ✅ 对 |
| beliefs/attitudes/factions/affinity/pacts/standing/stock/space·floor/money/memory 都不覆盖 | cover 全部 `in_chain=in_digest=no`；A/B 点对点 `SAME`（§三.1） | ✅ 对 |
| 坐标 `Invariants.gd:1280`(digest)/`:1310`(chain) | 真身 `:1392`/`:1422`（行漂 ~110） | ⚠️ **brief 坐标过期**，内容对 |
| AC1"未验证" | 本棒验了：跑通 + 分母可信 + 形状对 | ⚠️ **可升级为"已验证"** |

---

## 三、干预实证（**digest 不变而行为变，给数字，逐 seed 展布**）

### 3.1 点对点盲区 A/B（本棒新造探针 `ac1_ab.gd`，坐实①）——**这是架构承重的那一半**

做法：boot 到 t0=480 → 记 `(digest0, chain0, full_fp0)` → **只改一个字段** → 记 `(digest1, chain1, full_fp1)`。
`full_fp` = `save_game` 会落盘的那一整坨（世界字段 + 每 agent 字典，memory 折条数）折成一个数——是"真的不同吗"的独立见证。

**seed 1，N=12，t0=480，五个字段全部**：

| 干预（只改一个字段） | `digest` | `chain_step` | `full_fp`（独立见证） | landed |
|---|---|---|---|---|
| 清空某 agent beliefs | **SAME** | **SAME** | DIFF | yes |
| town_stock 每种 +20 | **SAME** | **SAME** | DIFF | yes |
| 某 agent 移到 (cafe,2f)（同步刷 area） | **SAME** | **SAME** | DIFF | yes |
| 某 agent 全类型 attitude=0.9 | **SAME** | **SAME** | DIFF | yes |
| 某 agent 全关系 standing=-30 | **SAME** | **SAME** | DIFF | yes |

⇒ **在一个 checkpoint 边界那一刻，`digest` 和 `chain_step` 都把两个真正不同的世界判成等价**（`full_fp` 证明它们不同、干预真落地）。
**这正是存档/读档/换页/回滚所依赖的等价预言的盲区，本棒当场量到、5/5 命中。** space/floor 也在其中——补上了 §一末的盲窗。

### 3.2 驱动未来 + 延迟无界（AC1 `drive` 模式，坐实②，**三 seed 展布**）

`drive` 在 t0=480 一次性施加只改一个字段的干预，跑 10 天（2400 tick），量**行为首分叉 tick**（`behav_div@`，
含 chain 不折的 `option.action`/`subject`）。CTRL 每 seed `hard=[]`。**关键在逐 seed 的抖动**：

| 字段（点对点均盲） | s1 `behav_div@` | s2 | s3 | 硬不变量红 |
|---|---|---|---|---|
| **beliefs** | 1508 | 1680 | **never** | [] |
| attitudes | 719 | 486 | 1316 | [] |
| relationships_affinity | 729 | 705 | 1036 | [] |
| relationships_standing | 597 | 486 | 678 | **[27]** |
| **skills** | **never** | 2174 | **never** | [] |
| xi_eps | 729 | 486 | 1536 | [] |
| faction | **never** | 669 | **never** | [] |
| pacts | 656 | 624 | 665 | [] |
| coin（agent money） | 486 | 843 | 689 | **[34]** |
| town_stock | 678 | 582 | 615 | **[38]** |
| inventory_gift | 790 | 486 | 837 | [] |
| weather_today | 538 | **never** | **never** | [] |
| day | 1047 | 750 | 720 | [] |
| area（只改缓存） | 480 | 486 | **never** | [] |
| space_floor（强制换平面） | 479 | 479 | 479 | **[1]** |

**读法（这是本节的全部意义）**：

1. **"驱动未来"是真的**：beliefs/attitudes/relationships/skills/pacts/faction/money/stock 都在至少一个 seed 里
   让行为分叉。§一.6 的静态读路径印证（`grep`，非注释）：beliefs → `_unspread_belief`（`Sim.gd:2089`，在 option 枚举里）
   → 决策 → 事件；attitudes → 决策打分（`:2141/:3115/:3157`）。**这些字段不是死的。**
2. **"早晚会抓到"是无界且逐 seed 抖动的**：同一个 beliefs 干预，s1 要 **1028 tick** 才现形、s2 要 **1200**、
   **s3 跑满 2400 tick 都不现形**。skills 在 s1/s3 都 never、s2 要 1694。**延迟从 6 tick 到 ∞，非单调。**
   ⇒ **任何"chain 迟早会抓到所以不用折"的论证，都被 s3 的 beliefs=never 直接证伪。** checkpoint 边界延迟预算=0。
3. **硬不变量是一张【偏】安全网，不是替代**（consistent 逐 seed）：coin/town_coin 破 **#34 金钱守恒**、town_stock 破
   **#38 库存账本自洽**、standing 破 **#27 协同守边界**、space_floor 破 **#1 无 need 触底**。
   **但**：①它只在扰动**违反守恒/一致律**时红——一次**合法**的再分配（把 coin 从甲挪到乙、总额不变）会**同时**过 digest（盲）
   **和** #34（总额守恒）⇒ 两个不同世界都放行；②beliefs/attitudes/relationships/skills/pacts/faction **没有任何不变量守**
   （上表 `[]`）——它们是**纯盲区**。beliefs 是最干净的样板：点对点盲、驱动未来、零安全网。

> ⚠️ **诚实边界（契约 §4，不用推断填 never）**：`town_coin`（被 #34 兜住）、`memory`、`mood`、`last_say`、
> `agent_affinity`、`stifled`、`metKnower`、`complementSeen`、`factions_world`、`talk_with` 三 seed 全 `never`。
> **这不等于"死字段"**——`stifled`/`metKnower`/`complementSeen` 各压在一道具体社交门上（探针注：`:2544`/`:4448`），
> 只是 10 天窗口/12 人阵容没触发；`talk_with` 唯一读点是玩家专属（`:1361`），headless 无玩家；
> `memory` 大概率是叙事/wiki 读、非决策读。**"窗口内 never" = 本网格分辨不出，不是零**（docs/41 §5）。
> **而这恰恰强化结论**：连"它到底驱不驱动未来"都无法在有限窗口内判定的字段，更不能靠"chain 迟早抓到"来省掉它。

### 3.3 小结：为什么"驱动未来的证据"是【包含】判据而非【排除】判据

§三.2 证明盲区**真实且后果严重**（大量字段驱动未来），但它**不是**"该折哪些字段"的筛子：
延迟无界 ⇒ **你无法安全地排除任何演化字段**（今天 never 的 memory，是玩家存档里 NPC 的记忆，读档必须原样还原）。
⇒ **投影的成员集 = 存档权威面（`save_game` 反射集）本身**，因为那正是 checkpoint/换页/回滚必须逐字节保住的东西；
"驱动未来的证据强度"只用来**排分阶段的先后**（§六），不用来决定**最终覆盖**。

---

## 四、当前 trunk 的具体缺口：存档硬门带着这个盲（本棒新造 `ac1_saveload_blind.gd`）

`save_load_test.gd` 是 R0-2 存档硬门，它的等价判据（逐字复刻其源）：① round-trip `Inv.digest(B)==Inv.digest(A)`（:40）；
② 续跑 **N=60** tick 逐 tick 比 `Inv.digest`/`event_digest`（:52-57）。本棒喂它一次"漏了 beliefs 的读档"
（两个同 seed 同 T=160 的实例 = 一次完美读档，再把 B 的一个 agent beliefs 清掉 = 漏字段）：

```
T=160 完美读档基线: digest(A)=digest(B)=3130778475  相同=true
制造漏档: 清空 B 的 lin 的 1 条 beliefs（A 保留）
门① round-trip: digest(B_漏档)=3130778475 == digest(A)  →  true     ← 门①看不见漏的 beliefs
门② 续跑 60 tick 逐 tick 比对: 漂移点 = -1                          ← save_load_test 会判 PASS
真相: 再跑 2400 tick（共 2460）仍未现形 ⇒ 这次漏档在 2460 tick 窗口内永远不可观测
```

⇒ **今天的存档正确性门，会放行一次静默丢掉 beliefs（同理 attitudes/factions/affinity/pacts/standing/skills/stock 分布）的读档。**
根因两条，都结构性：(a) round-trip 判据用的就是那个盲 digest；(b) N=60 的续跑窗口**远低于**这些字段的现形延迟
（实测 1508+ 或 never，§三.2）。**这不是多镇的先决条件——这是当前 trunk 存档正确性的一个现行洞。**
`state_projection` 的第一个消费者就该是这道门（把 `Inv.digest` 换成投影）。

> 诚实边界：本例 `lin` 在 T=160 只有 1 条 beliefs，是个小扰动；但 §三.2 已证 6 条 beliefs 也要 1508 tick 才现形，
> 60 tick 一律抓不到。**结论对扰动大小不敏感**：N=60 << 最小观测延迟。

---

## 五、三条实现路的代价对照（**金标影响一律给结构性推断依据，不写"应该不大"**）

**金标推断的地基（同 docs/116 的法则框架）**：S0 门每 CI 比对四个量——`digest`（`Inv.digest`）、`event_digest`
（`Sim` 滚动，`Sim.gd:3808`）、`chain`（`chain_step`）、`events`（`event_log.size()`）——对金标锚。
**一个改动动不动金标，取决于它改不改这四个量的输出。**

### 路 (a)：把更多字段**折进现有 `Inv.digest`/`chain_step`**

- **金标影响**：**全动，必走完整 R12。** 推断依据：`digest`/`chain` **是** S0 比对的两个量；往它们的格式串里加字段
  ⇒ 每个带该字段非平凡值的 seed 的 `digest`/`chain` 输出改变 ⇒ 与金标锚逐位不符 ⇒ 必须重烘三份锚
  （`Harness --bake-golden`、`DetGate --bake-golden`、`ModelPathGate --bake-anchor`）+ 跑留出 13-30 双侧。这是结构性的，不是"可能"。
- **迁移成本**：中——但**把两个语义混成一个**：`digest`/`chain` 今天的职责是**轨迹回放等价**（同 seed 两跑一致），
  加进 checkpoint 等价所需的字段后，一次**合法的平衡调参**（本该只动轨迹）会连带惊动 checkpoint 语义，反之亦然。
- **对 40+ 不变量/存档 LOD 下游**：`lod_verify` 的 V2（五机位同 digest）、`save_load_test`、`DetGate` 全部读这两个量 ⇒ 全部要重验。
- **性能**：`chain_step` 是**每 tick** 调用（前缀链）。把 relationships（§五性能表：N=60 有 **3540** 条边 ×7 子字段
  ≈ **24,780** 次 fnv/**每 tick**，且 O(N²)）折进 `chain_step` ⇒ 每 tick 成本上一个台阶，直接压红线 #3（骁龙 8 Elite / 60 人）。
- **判决**：**反模式。** 它把"要不要移金标"从用户旋钮变成"第一天就强制全动"，还污染了轨迹 digest 的单一职责。

### 路 (b)：**并行新增 `state_projection`**，与旧 `digest`/`chain` 解耦（**Codex 推荐、docs/113 §一钦定**）

- **金标影响**：**零（法则 A 的同构）——除非用户主动给它烘锚。** 推断依据：`state_projection(S)` 是一个**新函数**，
  **不是** S0 比对的四个量之一；只要不把它的输出加进 S0 的比对集，四个量逐字节不变 ⇒ 金标不动、不触发 R12。
  它**移金标当且仅当**有人为它**新增一份金标锚**（一个蓄意、独立的 bake）——**这就把"动不动金标"变成用户可控的旋钮**
  （与 docs/116 法则 A/C 同一形状：不锚=金标看不见它、锚=钉死但要烘）。
- **迁移成本**：低且可解耦先行。第一个消费者 = §四那道存档门（把 round-trip 的 `Inv.digest` 换成 `state_projection`，
  并把续跑窗口这条"延迟兜底"降级为辅助信号）。其余消费者（换页、回滚、冷热镇）随多镇分期接。
- **对 40+ 不变量/narrative 下游**：**近零**——不改任何现有量，旧 `digest`/`chain`/金标原样保留，纯**新增**一条投影。
- **性能**：**可控**——投影只在 checkpoint/换页/存读档**边界**算，**不必每 tick**（这是它与 (a) 的根本区别）。
  高维字段的每 tick 成本用路 (c) 的增量子摘要摊平（若某消费者确需每 tick 投影）。
- **判决**：**推荐。** 见 §六。

### 路 (c)：高维状态用**确定性增量子摘要**（**是 (b) 的实现技术，不是 (b) 的替代**）

- **定位**：当某消费者需要**每 tick** 的投影、而全量扫描 relationships/beliefs 太贵（§五性能表）时，
  让**写入点**（改 relationship/belief 的那几行）顺手维护一个 per-agent 增量子摘要（`h ← mix(h, 变化量)`），
  边界处 O(N) 合并子摘要，避免 O(N²) 全扫。
- **金标影响**：同 (b)（零，除非锚）——它只改投影**怎么算得快**，不改投影**是不是** S0 的比对量。
- **红线 #1 的硬约束（本路最大的坑）**：增量摘要**必须**对"到达同一逻辑态的不同路径"给同一值——
  ⇒ 子摘要要么走**规范序**（对 relationship/belief 的键排序后折），要么严格证明插入序在 seed 下确定且经 save/load 保序。
  **"谁先写谁先折"式的增量 = 违反红线 #1**（与 §七 异步那条同源）。
- **判决**：**(b) 的加速档**，仅在实测证明每 tick 全量投影超预算时才引入；起步不需要它（边界处全量扫一次，N=60 的
  一次性成本 ≈ 24,780 fnv，可接受）。

### 三路速览

| | 金标（推断依据） | 迁移 | 对 40+ 不变量/存档 LOD | 性能（每 tick？） | 红线 #1 |
|---|---|---|---|---|---|
| **(a) 折进旧 digest/chain** | **全动**（改的是 S0 比对量本身） | 中（且混淆双职责） | 全部重验 | **每 tick**，relationships O(N²) 压 #3 | 保持 |
| **(b) 并行新投影** | **零**（新函数非比对量）／锚=全动，**用户旋钮** | 低、可解耦先行 | 近零（纯新增） | **仅边界**算 | 需规范序 |
| **(c) 增量子摘要** | 同 (b) | (b) 的加速档 | 同 (b) | 摊平 O(N²)→O(N) | **必须规范序，否则破 #1** |

（性能锚点：t0=480 实测，N=12 关系边 132／N=24 中间／N=60 **3540**；beliefs N=12 **55**／N=60 **1385**；关系 O(N²) 增长。）

---

## 六、推荐：**路 (b)，投影覆盖=存档权威面，分阶段按"证据强度"排先后，移金标留到用户认它值**

**推荐 (b)（Codex 与 docs/113 §一一致，本棒实证支持）**，理由：

1. **(b) 把"移不移金标"变成用户可控旋钮**（不锚=零金标、锚=全动 R12），而 (a) 从第一天强制全动且污染轨迹 digest 的单一职责。
2. **(b) 有一个当前就该修的消费者**（§四的存档硬门），不必等多镇——立项即有兑现。
3. **(b) 不重定义、不触碰**任何现有量（旧 `digest`/`chain`/40+ 不变量/金标原样），风险面最小。
4. **投影的成员集 = `save_game` 反射的权威面**（§三.3 的论证：延迟无界 ⇒ 不能靠"驱动未来"筛除任何演化字段）。

**分阶段（先后按"驱动未来的证据强度"，覆盖目标是全权威面）**：

- **阶段 1 — 立起 `state_projection(S)` 骨架（零金标）**：一个**新函数**，规范序遍历 `save_game` 反射集（世界字段 + 每 agent
  字典，memory 折其序列化形），过 `Sim.fnv1a32`。**只边界调用、不进 S0 比对、不烘锚 ⇒ 金标逐字节不变**（落地必用自造 A/B 兑现法则 A，
  §七.1）。先证：同一世界两次投影相等、`save_game→load_game` 往返投影相等。
- **阶段 2 — 接第一个消费者：存档硬门（零金标）**：把 `save_load_test.gd` 的 round-trip 判据从 `Inv.digest` 换成
  `state_projection`（§四）。这一步**眼见为实地堵上当前那个洞**，且不碰仿真、不碰金标。**验收：§四那个漏 beliefs 的读档现在被判 FAIL。**
- **阶段 3 — 覆盖高证据字段（零金标）**：优先把 §三.2 里"驱动未来证据最强、且无不变量安全网"的字段纳入投影覆盖
  的**回归测试**：beliefs、attitudes、relationships(affinity/standing)、skills、pacts、faction、space/floor。
  （它们本就在权威面里被阶段 1 覆盖了；本阶段是补**针对性的负对照**，证明投影真能分辨这些字段的差异。）
- **阶段 4 — 接换页/回滚/冷热镇边界（随多镇，仍可零金标）**：换页决定"只由已提交仿真态得出"（docs/41 §0.5 那条 V2 红线照抄），
  投影作为热/冷镇进出的等价戳。仍是**新增消费者**，不动金标。
- **阶段 5（可选，用户拍板）— 给投影烘一份金标锚**：若判断"权威投影必须被 CI 每 seed 钉死"（而不只是存读档/换页边界自查），
  则给 `state_projection` 新增一份锚 ⇒ 每 seed 移金标 ⇒ 完整 R12。**这是纯口径决定，交用户**（法则 C 的同构）。

**明写：阶段 1-4 不移金标 ⇒ 不适用 R12**，但每一步仍须自造 A/B digest 兑现"确实没动旧四量"（法则 A 是推断，落地要实测，§七.1）。
**只有阶段 5 触发** docs/41 §3 + R12 的受控动作（三份锚 + rebake_history + 留出 13-30 双侧）。

---

## 七、风险与未知（**照实列——哪些是设计阶段答不了、必须实现后实测的**）

1. **"新增投影不动旧金标"是结构性推断，不是实测。** 落地阶段 1 **必须**自造 A/B（改前/改后各跑
   `Harness --chain-dump` 逐 tick 前缀链 + 金标四量 + 留出 13-30）兑现"旧 digest/chain/event_digest/events 一个字节没动"。
   历史上"读了注释以为没动"翻过车（docs/41 §4）。
2. **规范序是投影正确性的命门（红线 #1）。** GDScript 字典保插入序、且 save/load 保序，所以**同进程 checkpoint** 里
   插入序足够确定；但**冷热镇等价/跨机**要求两个经不同历史到达同一逻辑态的世界给同一投影 ⇒ 必须对
   relationship/belief/pacts 等字典的**键排序**后折。**用不用规范序、在哪一层用，是设计阶段就要定死的**，且要负对照
   （构造两个键序不同但逻辑相同的世界，证明投影相等）。**这一条没做对，投影会假红/假绿两头占。**
3. **space·floor 盲窗仍未完全消。** 点对点 A/B（§三.1）证明了 space/floor **点对点盲**；但"一次**合法**的
   space/floor 差异（两世界都有效）单独会不会驱动未来"——本棒的 drive 强制换平面破了 #1（非法态），**没能干净隔离**。
   ⇒ 投影**必须**覆盖 space/floor（存档要还原谁在几楼），但"它驱动未来的独立证据强度"是**已知的未知**。
4. **0–1784 tick 盲窗未系统扫。** 本棒 t0=480、10 天窗口；docs/66(Q1) 量到过 557 tick 延迟，本棒量到 beliefs 1508+/never。
   **"某字段最长多久才现形"这个上界，设计阶段答不了**——而这正是"chain 迟早会抓到"不可信的量化根据。落地后应做
   **静态注入 + 长窗（≥全天 1784+）**的延迟普查，尤其覆盖"晚触发/中途恢复"（AC1 已把这写进目标，未跑够长）。
5. **性能预算 N=60/100+ 未测。** 本棒只量了**状态体量**（N=60：3540 关系边、1385 beliefs），**没量投影的实际 wall-clock**，
   更没在真机（骁龙 8 Elite，红线 #3）上量。docs/113 §0.5 明写 **N>24 一格都没测过**。**边界处一次性全量投影**大概率可接受，
   但**每 tick 投影 + O(N²) 关系**是否超预算、要不要上路 (c)——**必须真机实测，不能估**（MEMORY #34 的池化史说明满负载内存是真痛点）。
6. **与存档/换页接口未定。** `load_game` 今天是 `for k in state: set(k,state[k])` 的整表恢复；投影接进去后，
   "投影不等时怎么处置"（拒绝读档？报告？）、换页的"进/出镇"边界在哪个 tick、异步预计算如何在**确定 tick 边界** join
   （docs/41 §0.5：任何"谁先算完先用谁"直接破红线 #1）——**这些是接口设计题，本文只列不解**。
7. **memory 是嵌套 Object，投影要特案序列化。** cover 里 memory `unperturb`（Object），`save_game` 对它特案序列化。
   投影折 memory 要与 save 的序列化**同源**（否则存了能读、投影却看不见 memory 差异，等于给自己留一个新盲区）。
8. **投影覆盖到派生缓存会引入假阳性。** cover 实测 `_aid_cache`（派生）`in_chain=YES`、`area/room`（`_area_key` 缓存）
   在权威面里。投影**必须只折真源、排除派生缓存**（照 `save_game` 的 DERIVED 排除表），否则"只改缓存不改真源"这类
   不一致态会让投影红得没有意义（AC1 的 `area` 臂就是这条的探针）。

---

## 八、这份 brief（docs/120 §一）哪里是错的

**逐条对代码/实测复核**：

1. **brief：`Inv.digest`(Invariants.gd:1280) / `chain_step`(:1310)——坐标过期。** 真身
   `digest`→`Invariants.gd:1392`、`chain_step`→`:1422`（行漂约 110）。**内容全对**（digest 只折 event_log；
   chain 折 tick+逐 agent id/pos/needs/talking/option）。docs/41 §1.5 早说了"引符号别引行号"——本文用符号锚。
2. **brief：AC1 探针"607 行、未验证"——行数对（607），"未验证"可升级。** 本棒在 trunk `528c502` 上跑通
   `cover`/`drive`、复核了它三个 `save_game` 反射常量与 trunk 一致（分母可信）、形状结论逐条成立（§二）。
   **它不是"未验证"了，是"已验证：形状对"。**
3. **brief 把干预实证的预期写成"① digest/chain 变不变（预期不变=问题）"——这个预期在 `drive` 口径下会被 `DIFF` 反驳，
   必须拆成点对点 vs 跨时。** `drive` 跑完 10 天后大多数字段**终态 digest=DIFF**（因为事件已不同）——
   若照 brief 字面"预期不变"，会误判成"digest 其实覆盖了"。**正确的①是【点对点】判据**（本棒用 `ac1_ab.gd` 单独钉死：
   5/5 字段 digest+chain 均 `SAME`）。brief 的直觉对（digest 盲），但它没区分"边界那一刻盲"与"10 天后事件已不同"，
   而这个区分正是 `state_projection` 存在的全部理由。
4. **brief：三条实现路 (a)/(b)/(c) 平列——实测表明 (c) 不是 (a)/(b) 的同级替代，而是 (b) 的实现技术。**
   (c)（增量子摘要）解决的是"每 tick 全量扫 O(N²) 太贵"，它**内嵌在 (b) 里**、且只在"确需每 tick 投影"时才要
   （投影主要在边界算，起步不需要 (c)）。把三者平列会让人以为要在"折进旧 digest / 新投影 / 增量摘要"里三选一，
   而真实结构是"**选 (b)，其高维档用 (c)**"。
5. **brief（转述 docs/113）：state_projection 是"多镇的先决条件"——对，但它**同时**是当前 trunk 的现行缺口。**
   `git log -S "state_projection"` 与 grep 均**零命中**（确是绿地、无历史语义可撞，这点 brief/roadmap 对）；
   但 §四证明它的第一个消费者（存档硬门）**今天就漏**——把它纯粹讲成"多镇先决"会低估它的紧迫性：它不只是
   "多镇之前要做"，是"存档正确性现在就缺"。
6. **顺带纠正一处 brief 的字段清单口径**：brief 列的"money"在数据里**没有单一字段**——它是 agent 的
   `inventory.coin` **加** 世界的 `town_coin`，两者**都**点对点盲于 digest，但**都**被 #34 金钱守恒兜住（§三.2）。
   投影覆盖 money 要同时折这两处，别只折一处。

---

## 附：交付自查

- **零代码改动**：`git diff --stat` 只应有 `docs/121-*`（本文件）。未碰任何 `game/` / `tools/` / 其它 `docs/`。
  探针（`ac1_state_coverage.gd` 取自 `origin/wip/ac1-state-projection`；`ac1_ab.gd`/`ac1_saveload_blind.gd`/`ac1_volume.gd` 本棒新造）
  **全部只在 scratchpad 的隔离副本里跑**，未入 trunk。
- **未跑 CI**：本波不改代码、不改任何门读的文件，`ci.sh` 不受影响；未跑（无改动可验）。探针跑在隔离副本、Godot 4.6.2。
- **度量诚实**：本文所有数（cover 分母 100/35、29 个未折演化字段、drive 逐 seed `behav_div@`、save/load 盲区 60→2460、
  N=60 关系 3540 边）**均为观测量，非门的红/绿余量**；本文不以任何"改善数字"作判据（docs/41 §5、docs/113 §六）。
  **每个"never"读作"本网格分辨不出"，非"零"**；未测项（真机性能、长窗延迟上界、合法 space/floor 独立驱动）在 §七明写为未知。
- **行号会腐烂**：本文行号实读/实跑于 `528c502`。以符号/上下文为准，行号是线索不是契约（docs/41 §1.5）。
