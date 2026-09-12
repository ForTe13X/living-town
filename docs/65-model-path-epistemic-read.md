# 65 · 模型路上的知识泄漏——只读实测回执（Q2）

> 派棒：docs/64 §二（Wave Q 的 Q2 行）+ docs/63（P1，本波的输入）+ docs/41 全部。
> **本棒一行 `game/scripts/**` 都没改**（`AIBackend.gd` 在我的行里，但结论是"不该动"，见 §五）。
> 新增文件：`game/bench/EpistemicPromptProbe.gd` / `.tscn`（只读探针）、本文。
> 基线树 = `10a4aa5`（`integration/batons`），Godot 4.6.2，`Sim.backend=null`，scene 模式。
> 派棒的约束是「只查、只报、给建议；不改红线、不改候选表字段」——**照办了。**

---

## 〇、判决（先说结论）

**四句话：**

1. **递给模型的东西比 P1 以为的窄。** `AIBackend.build_prompt` **一次也没有把 `subject` 渲染进候选行**
   ——实测**候选行命中 0**：`0 / 16715` 条非空 subject（N=12·seeds 1/5/13·30 天）、
   `0 / 60741`（N=20·seeds 1-3·30 天）。
   （全文命中不是 0 而是 12 与 29，**全部落在 `[近事]` 行**——那是选举公开事件写进本人记忆的
   topic id，不是候选表泄的。这一格必须按行拆开才读得对，见 §3.4。）
   `partner` 渲染的是**显示名**不是 id（id 命中 `0 / 33694`）；`target` / `need` / `score` /
   `amount` / `area` / `commit` 一个都不进文本。**同一个 checker 在负对照上 100% 变红**（§三）。
2. **但泄漏是真的，只是它不在任何一个【字段的值】里，而在【候选表的成员资格】里。**
   `_social_candidates` 的 13 个社交动作里有 **8 个**，它们**存在**的条件就是"读了对方的私有状态"。
   模型看见 `说八卦→阿本(老友)`，就等于被告知**"阿本不知道某件我知道的事"**——
   这条推断**可靠且完备**（`_unspread_belief:3403` 返回空串 ⇔ 不存在这样的信念），只是**不指名是哪一条**。
   实测 **52.4% 的决策点**（逐 seed 51.2 / 53.2 / 52.6%）至少带一条这样的选项。
3. **这是契约的缺口，不是一次违规。** 红线 #2 的三个分句我逐条验过，**写侧全部成立**（§四）：
   模型的唯一有效写入就是那个下标；`emotion` / `affinity_delta` 被解析、被钳位、被挂到 intent 上，
   而 **`Sim.gd` 一个字都不读**（`git log -S` 确认是**从来没接过**，不是被摘掉的）。
   红线 #2 **一个字都没提"读"**。⇒ **缺口。补一句话即可，见 §六。**
4. **而派棒 brief 说"这条路被 CI 完全没跑过"是错的，错得有意思。**
   `AIBackend.decide()` 在 CI 里跑得很欢——BackendGate 一次 2 seed × 4 天就**调了 4879 次**。
   零覆盖的是**另一半**：`build_prompt` 在 BackendGate **0 次**、在 ModelPathGate 也 **0 次**
   （隔离副本插桩实测，§二）。
   ⇒ **CI 守的是"模型能交回什么"，对"模型被展示了什么"零覆盖——
   与红线 #2 自己的不对称一模一样。这不是巧合，门是照着红线写的。**

---

## 一、逐字段清单（问题①：到底有哪些字段）

### 1.1 候选字典的全部 key（**跑出来的，不是读代码读出来的**）

探针把每一条候选的 `keys()` 累加起来，N=12·30 天·3 seeds 与 N=20·30 天·3 seeds 两格一致：

| kind | 出现次数(N=12/30d) | 全部 key |
|---|---|---|
| `object` | 59575 | `kind` `action` `target` `need` `amount` `dur_total` `score` `say` |
| `social` | 33694 | `kind` `action` `partner` `subject` `need` `score` `say` |
| `journey` | 1941 | `kind` `action` `target` `need` `amount` `dur_total` `score` `say` **+ `dest_space` `dest_floor`** |
| `attend` | **0** | `kind` `area` `commit` `score` `say`（**没有 `action`**，见 §七-7） |

> `attend` 在**任何一格都没出现过**（N=12/20 × 30 天 × 3 seeds，7810 + 14883 个决策点）。
> 它的字段集是从 `Sim._attend_candidates`（`Sim.gd:1994`）读的，并用**构造性渲染自检**验的（§3.5）。
> `ext.candidates()` 的 provider 在出货树上没有注册 ⇒ 本清单不含它；任何新 provider 都会绕过下面的分析。

### 1.2 `ctx` 的全部 key

`Sim._context(ag)`（`Sim.gd:3588`）= `{"day", "tod", "tick", "pos"}`。**四个，实测确认，P1 记对了。**

### 1.3 ⚠ 但"模型拿到什么"的正确说法不是"ctx + 候选表"

`build_prompt(agent, candidates, ctx)` 的第一个参数是**整个 agent 字典**，它从里面读：
`persona.name` / `persona.traits` / `persona.style`、`needs`（全部五项，取最低的那一项）、
`memory`（`retrieve([], tick, 2)`）、`relationships[partner_id]` 的 `affinity` / `familiarity`。
⇒ **模型看到的是"这个 agent 自己那本册子的一份摘要"，比 `_context` 大得多**（但仍然全是他自己的）。

### 1.4 真正被渲染进 prompt 文本的，只有这些

`AIBackend.build_prompt`（`AIBackend.gd:1304`）逐行：

| prompt 行 | 内容 | 来源 |
|---|---|---|
| `[人设]` | `name`：性格`traits`，口吻`style` | 自己的 persona |
| `[此刻]` | 第`day`天·`_phase_zh(tod)`，`_mood(agent)[0]` | ctx.day / ctx.tod + 自己的 needs |
| `[状态]` | 最想满足:`NEED_ZH[最低 need]`(值/100) | 自己的 needs |
| `[近事]` | `memory.retrieve([], tick, 2)` 两条 | 自己的记忆流 |
| `[候选]` | `A=<标签> B=<标签> …` | 见下 |

单条候选的标签 = `ACTION_ZH.get(action, action)`，**社交候选**再追加
`→<Sim._name(partner)>(<_rel_hint(agent, partner)>)`。**就这些。**

### 1.5 **没有**被渲染的字段（逐条，实测 0 命中）

`subject` · `partner`(id) · `target`(对象 id) · `need`(id) · `score` · `amount` · `dur_total` ·
`area` · `commit` · `dest_space` · `dest_floor` · `say` · `ctx.tick` · `ctx.pos`。

⚠ **但它们没有消失**：`_fire` 把**完整的候选字典**存进 `_pending[id]["snapshot"]`
（`AIBackend.gd:975`，`duplicate(true)`）。**候选表本身确实带着 subject，P1 这半句是对的；
它只是没有被展示给模型。** 这个区别在下面每一节都是承重的。

---

## 二、CI 覆盖：`decide()` 跑 4879 次，`build_prompt()` 跑 0 次

派棒 brief 写的是「`Sim.backend = null` throughout CI，所以这条路被仓库里每一道门都没跑过」。
**前半句在 4d 这一步就不成立**：`BackendGate.gd` 自己的抬头（`:6-9`）写着它存在的理由就是
"别处恒 `backend=null`"，而它自己**设了一个真后端**（`Sim.backend = probe`、`AIBackend.backend = "random"`）。

**隔离副本插桩实测**（把 `print` 塞进 `build_prompt` / `_system_prompt` / `decide` 的第一行，
只在 scratchpad 的副本上，仓库树一个字节没动）：

| 门 | 配置 | `decide()` | `build_prompt()` | `_system_prompt()` |
|---|---|---|---|---|
| **BackendGate**（ci.sh 4d） | seeds 1-4 × 8 天 × N=12 | —— | **0** | **0** |
| **BackendGate** | seeds 1-2 × 4 天 × N=12 | **4879** | **0** | — |
| **ModelPathGate**（ci.sh 4e） | seeds 1-4 × 8 天 × N=12 | —— | **0** | **1** |

两门都 PASS（未受插桩影响，插桩只加 print）。

**机制**（静态可穷举，三个调用点）：`build_prompt` 在 `AIBackend.gd` 里只被
`_probe_once(:598)` / `_fire_http(:1083)` / `_fire_slm(:1101)` 调。而
- `backend=="random"` 且 `sim_decode_ticks<=0` ⇒ `decide` 走 `_instant_random`，**根本不进 `_fire`**；
- `backend=="random"` 且 `sim_decode_ticks>0` ⇒ 进 `_fire`，但在 `if backend == "random"` 那一支
  用 `_rand_raw` 直接造出一个字母就返回，**够不到 `_fire_http` / `_fire_slm`**；
- `mock` 同理（`_mock_raw`）；
- `probe_capability` 是唯一的第三条路，而**没有任何门调它**（唯一调用点是 `Main.gd:1138`，
  且只用 `"slm"`/`"llm"` 调）。

> ⇒ **正确的措辞**：不是"模型路径没有门"（docs/45 之后这句话就不对了），
> 而是**"门守的是回程，不守去程"**。红线 #2 管写不管读，而 CI 忠实地照着它写了。
> **这两件事是同一个缺口的两个投影，不是两个发现。**

⚠ **一条附带的诚实边界**：`probe_capability` 对 `be=="random"` **不会早退**
（早退表只有 `logic`/`mock`），它会走到 `_probe_once` 然后落进 llm 的 `HTTPRequest` 分支。
今天没人这么调（`random` 不在 `available_backends()` 里，UI 选不到），**所以这是死路不是活 bug**；
但它是"新后端接进来时第一个会踩的坑"，记在这里。

---

## 三、问题②：哪些是它有资格知道的，哪些泄漏了别人

### 3.1 逐字段判定（**被渲染的那五行**）

| 渲染出来的东西 | 读的是谁的状态 | 判定 |
|---|---|---|
| `persona.name/traits/style` | 自己 | **局部** ✅ |
| `ctx.day` / `_phase_zh(ctx.tod)` | 全局环境（天色人人看得见） | **公共** ✅ |
| `_mood(agent)` / `最想满足:X(v/100)` | 自己的 `needs` | **局部** ✅ |
| `[近事]` 两条记忆 | 自己的 `memory` 流 | **局部** ✅（每一条记忆的写入点都有事务/目击溯源，见 §3.4） |
| 候选标签 `ACTION_ZH[action]` | 动作名本身 | 见 §3.2——**这一格才是问题所在** |
| `Sim._name(partner)` | 对方的**显示名** | **公共** ✅（且生成时被 `_nearby_agents` 夹着：同平面 + 同 area） |
| `_rel_hint(agent, pid)` | **自己**的 `relationships[pid]`（affinity/familiarity） | **局部** ✅ |

> ⚠ `_rel_hint` 这一条要点名，因为它是最容易读反的：docs/63 §七-7 提醒过
> "per-relationship ≠ 只读自己的"。**这里确实是只读自己的**——
> `AIBackend.gd:1269` 取的是 `agent.get("relationships", {})`，不是 `_rel(o, ...)`。

**⇒ 逐字段看，prompt 里没有一个【值】是越界的。**

### 3.2 泄漏在【成员资格】里，不在值里

`_social_candidates`（`Sim.gd:1837`）枚举 13 个社交动作，其中 **8 个的存在条件读了对方的私有状态**。
选项**出现在候选表里**这件事本身，就是一次披露：

| 动作 | 渲染成 | 它的存在向模型证明了什么（对方的私有状态） | 实测次数(N=12/30d) |
|---|---|---|---|
| **discuss** | `聊看法→X(…)` | **X 在某个话题上的立场与我相差 ∈ (0.15, 我的 eps]** ——一个带上下界的区间 | **6811** |
| **gossip** | `说八卦→X(…)` | **X 的 `beliefs` 缺少至少一条我持有的信念**（精确谓词：存在一条我的信念，非 secret、非 stifled、subject≠X，而 X 没有——`_unspread_belief:3403` 的四道 continue） | **4991** |
| **gossip_rep** | `提醒名声→X(…)` | **X 对某个【不在场的】第三方 C 的私有 standing 比我高** | **4861** |
| **rally_oust** | `联合施压→X(…)` | **X 的 `faction` ≠ 我的** | 156 |
| **endorse** | `统一口径→X(…)` | **X 的 `faction` == 我的，且 X 对某个不在场的 C 的 standing 比我高** | 52 |
| **confide** | `说心事→X(…)` | X 不知道我的某个秘密 **＋ EARSHOT 内没有第三者**（`_secret_private:3468` 扫【同平面全部 agent】的 `pos`——这一条披露的是**旁人**的位置，不是 X 的） | **0** |
| **leak** | `说漏秘密→X(…)` | X 不知道**第三人托付给我的**某个秘密 ⇒ 连带披露那个第三人的隐私 | **0** |
| **aid** | `搭把手→X(…)` | X 的某个 `need` 低于 `AID_NEED_TH=60` | **0** |
| greet / give / invite / confront / apologize | — | 只读自己（礼物、trust、自己的约、自己那侧的 conflict 记录） | 局部 |

**判定：这 8 条都是【跨主体读】，而模型确实看得见它们。**
但披露是**存在性**的、不是**指名**的：模型知道"X 不知道某件事"，不知道"是哪件事"
（`subject` 没进文本）；知道"X 对某个不在场的人印象比我好"，不知道"是谁"。

### 3.3 量级（契约 §5：给展布不给均值）

**N=12，seeds 1 / 5 / 13，30 天，7810 个决策点**（`|C|≥2` 才计）：

| | seed 1 | seed 5 | seed 13 | 合计 |
|---|---|---|---|---|
| 决策点 | 2568 | 2619 | 2623 | 7810 |
| 至少含 1 条跨主体条件选项 | 1315 | 1394 | 1380 | **4089** |
| 占比 | **51.2%** | **53.2%** | **52.6%** | **52.4%** |

跨主体条件选项 / 局部条件选项 = **16871 / 78339**。

**同一个 prompt 里、针对【同一个被点名的人】同时开出几条跨主体选项**（这条才是"关于 X 泄了多少"）：

```
1 条 → 1748 次    2 条 → 3058 次    3 条 → 2837 次    4 条 → 124 次
```
⇒ **众数是 2-3 条**。也就是说被点名的那个邻居，通常同时被披露了 2-3 个彼此独立的私有谓词
（例如"他不知道某事" ∧ "他在某话题上与我有分歧" ∧ "他对某个不在场的人评价比我高"）。

**N=20，seeds 1-3，30 天，14883 个决策点**：62.5 / 62.8 / 62.8%（合计 **62.7%**，9331/14883）；
跨主体 / 局部 = 61058 / 161539；同一被点名者的同时披露数 `1→3431 · 2→11105 · 3→11483 · 4→242`。
⇒ **人越多，泄漏面越大**（社交候选数随 N 涨，docs/58 §二量过同一条曲线：
N=12 每次决策 3.6-4.2 条社交候选 → N=60 是 24.9-26.3 条）。

### 3.4 `[近事]` 与 `chat()` 路：两条我该点名但**不在**上面表里的

- **`[近事]` 是合法的，但它把 raw id 带进过文本。** 实测 `subject` 串命中 12 次（N=12/30d），
  **全部落在非候选行**，全部是 `cafe_expand`——来自选举里程碑记忆
  （`Sim.gd:2941`：`镇上就『%s』表决…` 直接把 topic id 拼进记忆文本）。
  选举是**公开事件**，且那条记忆还写着**本人**的票，所以它不是泄漏；
  **但如果只写一个"subject 不许出现在 prompt 里"的 checker，它会在这里假红。**
  我是靠把命中按行拆开才分清的（探针里那个 `候选行 / 非候选行` 的判别）。
- **`chat()` 路（玩家对话）比 decide 路暴露得多。** `_secret_guard`（`AIBackend.gd:1133`）
  把该 agent `beliefs` 里所有 `secret==true` 的 **claim 原文**逐条拼进 system prompt
  （包括**别人吐露给他的**秘密），再加一句"绝不可透露"。
  按本仓库的口径这是**他自己的信念库**（硬不变量 #6 守着它的来路），所以是局部的；
  docs/22 记录它把对话泄密率从 35% 压到 0%。**本棒没有测这条路**——它由玩家发起、CI 从不触达。

---

### 3.5 构造性渲染自检（因为四个动作一次都没自然出现过）

`confide` / `leak` / `aid` / `attend` 在所有网格里都是 0 次 ⇒ **"它们渲染成什么样"不能靠等**。
探针手搓一份覆盖**全部 13 个社交动作 + object + journey + attend** 的候选表
（每条塞进金丝雀串 `SUBJECT_CANARY` / `OBJ_CANARY` / `AREA_CANARY` / `COMMIT_CANARY` + 真 partner id），
交给**真的** `AIBackend.build_prompt` 渲染。原样输出（N=12 seed 13 收尾态）：

```
[人设] 阿丽：性格热情·爱八卦，口吻语气活泼、爱用感叹号、喜欢打听新鲜事
[此刻] 第9天·深夜，还算自在
[状态] 最想满足:精力(65/100)
[近事] 我和铁牛之间的疙瘩，还没解开。；想找阿林说了说别人的事，被婉拒了
[候选] A=打招呼→阿本(点头之交) B=送礼→阿本(点头之交) C=说八卦→阿本(点头之交)
D=提醒名声→阿本(点头之交) E=聊看法→阿本(点头之交) F=约见→阿本(点头之交)
G=当面理论→阿本(点头之交) H=道歉→阿本(点头之交) I=说心事→阿本(点头之交)
J=说漏秘密→阿本(点头之交) K=统一口径→阿本(点头之交) L=联合施压→阿本(点头之交)
M=搭把手→阿本(点头之交) N=吃饭 O=喝咖啡 P=
```
```
候选行里出现 SUBJECT_CANARY : false
候选行里出现 OBJ_CANARY     : false
候选行里出现 AREA_CANARY    : false
候选行里出现 COMMIT_CANARY  : false
候选行里出现 partner id(ben) : false
```

**两件事同时被这一张照片坐实：**
① 五个金丝雀一个都没进候选行 ⇒ §3.1 那张表不是读代码读出来的；
② **`P=` 后面什么都没有**——`attend` 渲染成一个空标签（§七-7）。

---

## 四、问题③：这算不算违反红线 #2

### 4.1 红线 #2 的逐字与逐分句

> **无模型也能玩**：logic 地板在零模型下必须完整可玩。模型只能在**引擎枚举出的合法候选**里
> 挑一个下标 + 可选台词，**永远不能写世界状态**。

三个分句，我逐条验：

**(a)「零模型完整可玩」** —— 成立且是全仓库跑得最多的一条（金标/DetGate/LOD 全在 `backend=null` 上）。

**(b)「只能挑一个下标 + 可选台词」** —— **结构上成立**：
`parse_decision` 主路只认单字符 A-Z，越界/prose 一律 fail-closed 返回 `{}`；
JSON 兼容路也只用 `pick` 取 `candidates[pick].duplicate()`。
落地前 `decide()` 还用 `_cand_key` 对**当前**候选重验一次（`AIBackend.gd:829-838`）。
BackendGate 的 C 臂把这条机检了（且用自检臂证明了它有判别力）。

**(c)「永远不能写世界状态」** —— **成立**，而这一条我特意去找过反例：
`parse_decision` 的 JSON 路**还会解析 `speech` / `emotion` / `affinity_delta`**（后者钳到 ±3），
`decide()` 把 `emotion` / `affinity_delta` **挂到返回的 intent 上**（`:846-847`），
intent 随后交给 `Sim.agent_apply`。
- **实测：`Sim.gd` 里 `affinity_delta` 与 `emotion` 各 0 处引用**（全仓 `--include=*.gd` grep）。
- **`git log -S "affinity_delta" -- game/scripts/Sim.gd` 空**
  ⇒ 照契约 §1.5 的纪律，这是**从来没接过**，不是"接过又被有意摘掉"。
- `say` 只写到 `ag["last_say"]`，读它的只有 `WorldView.gd:1062`（显示）与两个 bench；
  它**不在** `Invariants.digest` 也**不在** `chain_step` 的 canon 里（两者的字段我逐个核过）。
  而红线 #2 明文允许"可选台词"。

⇒ **模型今天唯一的有效写入就是那个下标。写侧没有破。**

### 4.2 所以：**缺口，不是违规**

红线 #2 的三个分句**没有一句提到"读"**。§三量到的泄漏全部发生在"模型被展示了什么"这一侧，
**而那一侧从来没有被写下来过**。派棒 brief 的读法（"gap rather than breach"）**我复核后同意**。

**但要把它读准，别读成"所以无所谓"**：红线 #2 的**理由**是"引擎枚举合法性、模型不越权"，
而§三那 8 条说明**枚举本身就是一次披露**。⇒ 缺的不是一条新红线，是**同一条红线的另一半**。

### 4.3 ⚠ 一个我认为必须点名的【潜伏写通道】（不是今天的违规）

`affinity_delta` 是一支**上了膛的枪**：schema 声明它、parser 钳位它、`decide()` 把它挂上 intent、
`agent_apply` 收下它。**今天 Sim 不读，明天一句 `if intent.has("affinity_delta")` 就是一次
模型对关系账本的直接写入**——而**没有任何一道门会红**：

- BackendGate 的 C 臂比的是 `Sim._cand_key`（`Sim.gd:4091`），字段是
  `kind|action|partner|target|subject|need|area|commit|amount|dur_total`
  ——**`affinity_delta` / `emotion` / `say` 都不在里面** ⇒ 带着它的 intent 照样"闭集封闭 ✅"。
- 而且 BackendGate 的两条臂是 `random`，它们经 `_rand_raw` 只产一个字母
  ⇒ **`parse_decision` 的 JSON 分支（唯一会产出 `affinity_delta` 的地方）在 4d 里根本不执行**。
  唯一碰它的是 `m2_test`（ci.sh :434，只测钳位到 ±3），**没有任何断言说"它不许影响世界"**。

**我没有动它**（§0.8：改候选/intent 契约是架构改动，要评审）。处置建议见 §六-3。

---

## 五、为什么我没有改 `AIBackend.gd` 一个字

`AIBackend.gd` 在我的行里，最省事的"修法"是在 `build_prompt` 里少渲染点东西。**那会是装修。**
§三的结论是泄漏**不在渲染里**——今天渲染已经很干净了（0 命中）。
真正的通道是**候选表的成员资格**，而它由 `Sim._social_candidates` 决定（**不是我的行，是 Q1 的**），
且**改它就是改候选表**——派棒明确禁止，§0.8 也要求先评审。
⇒ **本棒的正确产出是一句契约 + 一份量，不是一个 patch。**

---

## 六、建议（问题③的后半：红线该怎么补）

### 6.1 建议加在红线 #2 后面的一句（**我建议的措辞，逐字**）

> **读侧同受本条约束**：递给模型的 prompt 里，每一个**值**都必须是该 agent
> **自己的状态、公共事实、或他经事务/观察合法获知的东西**（即 `Sim.gd:10` 那条
> 「知识边界(只能经事务/观察获知)」的同一条口径）。
> 而**候选表的成员资格本身也是一次读**——一个选项存在，就等于告诉模型它的枚举条件成立了。
> **因此候选枚举的门就是 prompt 的知识门，二者不得分离**：
> 能进这个 agent 候选表的对象，必须是他本来就能感知的对象。

> ⚠ 措辞里那句"或他经事务/观察合法获知的东西"是**必要的**，不是宽松：
> `[近事]` 里合法地存在"听阿丽说起可可的事"（`Sim.gd:2260`）、
> "看见 A 和 B 在广场送礼"（旁观者记忆，`Sim.gd:2348`）这类**关于别人的**内容。
> 写成"只能是自己的状态或公共事实"会把记忆流整条判违规，而记忆流每一条写入点都有溯源。

**为什么是这个形状，而不是"prompt 里不许出现 X 字段"**：
- 字段黑名单**今天已经满足了**（§〇-1 与 §3.5 全 0），所以它是一条**没有判别力的判据**——
  契约 §6 那条"先在未改动的树上跑一遍"正是在防这个。
- 而"枚举门 ≡ 知识门"这一句**今天基本已经成立**（P1 §1.2：跨主体读几乎全部夹在
  `for o in _nearby_agents(ag)` 里），**所以它便宜**；
- 而且它**不是新政策，是把一条已有的自我描述变成有牙的**：`Sim.gd:8` 原文就写着
  "候选除物件交互外，还枚举**【感知到的其他 agent】**的社交动作"，`Sim.gd:10` 写着
  "知识边界(只能经事务/观察获知)"。**今天这两句都没有任何门在守**（P1 §1.2 的原话：
  "这条保证不是一道门在守，是一个循环的形状"）；
- 且它**自动继承给多镇**：另一个镇的人天生不在 `_nearby_agents` 里
  （`_area_key` 对非-town 返回 `"space:floor"`）⇒ B 镇居民不会出现在 A 镇居民的候选表里
  ⇒ 也不会出现在他的 prompt 里。**docs/62 想买的那条性质，在读侧是白拿的。**

### 6.2 这句话一旦写进去，**第一个不合格的是谁**（诚实地说）

**`endorse` 与 `rally_oust`，以及同派系亲和。** 理由是 P1 已经量过的两条：
- `endorse` 读 `_agent_by_id[C]["faction"]`，而 **C 可以完全不在场**（docs/63 §1.2 表里唯一那条"门：无"）；
- `o["faction"]` 本身是 `_recompute_factions()` 每夜从**全镇每个人的私有 attitudes** 重算的派生量，
  **零空间门**（docs/63 §四）。

⇒ **读侧这句话与 Q1 手上那件事指向同一个对象**。这不是巧合：
`faction` 既是写侧那条零接触通道的出口，也是读侧唯一一条**绕过** `_nearby_agents` 的入口
（`endorse` 里的 C 不必在场，其余每一条跨主体读都在那个 for 循环体内）。
**⇒ 建议这句话与 Q1 的判定一起过评审，别分两次改。**

### 6.3 关于 `affinity_delta`（§4.3 那支枪），建议的最小处置

**三选一，我推荐第 2 条**：

1. 从 `DECISION_SCHEMA` / `parse_decision` / `decide` 里删掉 `affinity_delta` 与 `emotion`
   ——最干净，但会动 `m2_test` 的断言，且 `emotion` 未来可能有用（表情）。
2. **留着，但把它们钉成"显示层专用"**：在 `Sim.agent_apply` 入口加一条断言/注释级契约
   "intent 上除 `say`/`emotion` 外的任何非 `_cand_key` 字段一律不得影响世界"，
   并在 BackendGate 的 C 臂旁边加一条**反向自检臂**：注入一个带 `affinity_delta=±3` 的 intent，
   要求**世界轨迹逐字节不变**（今天必绿，将来有人接线时立刻变红）。
   **这正是 4d 自检臂 `inject:fabricate` 的同一个形状，模板现成。**
3. 什么都不做，只把这件事写进文档。——**我不推荐**：契约 §2 第四个盲区讲的就是
   "名字承诺了一个合取式而实现只查一半"，这里是它的镜像：**一个字段承诺了自己没有效果，而没有代码在查。**

⚠ **这三条我都没有实施**（§0.8 + 派棒禁令）。

---

## 七、这份 brief / docs/64 / P1 哪里是错的（契约 §4）

1. **派棒 brief「`Sim.backend = null` throughout CI, so this path is unexercised by every gate
   in the repo」——错。** `BackendGate`（ci.sh 4d）设 `Sim.backend = probe` +
   `AIBackend.backend = "random"`，`decide()` 实测在 2 seed × 4 天里跑了 **4879 次**。
   `BackendGate.gd:6-9` 自己就是这么写的。**零覆盖的是 `build_prompt`，不是"这条路"。**
2. **派棒 brief「BackendGate … P1 suggests parts of the prompt path may be dead under it」——
   方向对，程度轻了：是【全部】而不是【部分】。** `build_prompt` 在 4d 与 4e 里都是 **0 次**
   （插桩实测），`_system_prompt` 在 4e 里恰好 **1 次**（ModelPathGate 的字面断言）。
3. **P1（docs/63 §八）「递给模型的候选表带着 `subject`（信念 id）与 `partner`，
   模型可以据此推断谁知道什么」——前半句对候选表成立、对 prompt 不成立；后半句的结论对，机制不对。**
   - 候选表**确实**带着它们（`_pending[id]["snapshot"]` 存的是 `duplicate(true)` 的完整字典）；
   - **但 `build_prompt` 一次也没渲染它们**（0/16715 与 0/60741，负对照 100% 变红）；
   - "推断谁知道什么"这条**结论成立**，走的却是**另一条路**：不是读 `subject`，
     而是**看见 `说八卦→X` 这个选项存在**。⇒ **披露是存在性的，不是指名的。**
   - 这个区别不是文字游戏：**按 P1 的机制去修（"别把 subject 递给模型"）今天是个 no-op**，
     一行都不用改，而泄漏一点没少。
4. **P1（docs/63 §八）「模型后端拿到 `_context(ag)`（`{day, tod, tick, pos}`，本身很局部）
   加上引擎枚举好的候选表」——`_context` 的四个键复核无误，但这句话漏了最大的那一项。**
   `build_prompt` 的第一个参数是**整个 agent 字典**，人设/needs/记忆/关系账本都从那里读；
   而 `ctx` 里的 `tick` 与 `pos` **反而一个都没被渲染**。
   ⇒ 真实的暴露面 = **自己那本册子的摘要 + 候选表的成员资格**，不是"ctx + 候选表"。
5. **docs/64 §二「红线 #2 明写：模型只能…永远不能写世界状态。这条红线管的是"写"」——对，
   而且比它说的更对**：我去找过写侧的反例（`emotion`/`affinity_delta`），
   结论是今天写侧确实没破（§4.1），**但那不是设计守住的，是"没人接线"守住的**（§4.3）。
6. **`game/bench/dump_decide_prompt.gd` 与 `game/bench/log_decisions.gd` 里的 `build_prompt`
   手抄件【都已经漂了】，而且是同一处漂。** 两者的 `_idx_label` 还是旧的
   `str(i) if i < 10 else char(65 + i - 10)`（0-9 然后 A-Z），而出货树是 **A-Z、`LLM_PICK_CAP=26`**
   ——docs/42 §4.2 记录的正是"数字编号让模型一次也不选 0 号槽 ⇒ 系统性跳过维生动作"这个 bug，
   **抄件把那个 bug 完整保留着**。`dump_decide_prompt.gd` 的 `_sys_prompt()` 还带着
   docs/42 §7.3-1 已删掉的字面示例编号「如 3 或 A」（那一句实测把 30.0% 的决策焊死在 index 3）。
   `log_decisions.gd` 的 `_cap_order()` 里 cap 还是 36（行号刻意不引）。
   ⇒ **拿这两个文件去论证"模型看到了什么"，论的是一份出货树上不存在的 prompt。**
   `PickCtxDump.gd:4-9` 已经就 `log_decisions` 的**排序**漂移写过一次交代，
   **字母表这一处是第二处、且它同时存在于两个文件**。本棒因此走 scene 模式调真函数（§九）。
7. **`attend` 候选在 prompt 里渲染成一个【空标签】。** 它的字段集里**没有 `action`**
   （`Sim.gd:2006`），于是 `build_prompt` 的 `ACTION_ZH.get("", "")` 吐空串，
   而 `kind != "social"` 所以也不追加对象 ⇒ 模型看到的是一个**光秃秃的字母加等号**。
   构造性渲染自检实测（§3.5 那张照片的最后一项）：`… N=吃饭 O=喝咖啡 P=`。
   ⚠ **但它今天是潜伏的不是活的**：`attend` 候选在 N=12/20 × 30 天 × 3 seeds 的
   **22693 个决策点里一次都没出现过**。所以这是"将来会咬人"，不是"现在正在咬"。
   **我没有修**——`Sim.gd` 是 Q1 的行，且在 `ACTION_ZH` 里补一条会改 prompt 文本（= 改模型路行为）。
8. **`confide` / `leak` / `aid` —— 表里最狠的三条（`leak` 会连带披露第三人的隐私）——
   在我跑的每一格里都是 0 次。** 所以 §3.3 那个 52.4% **不包含它们**。
   这与 `bench/PrivacyProbe.gd` 早就量过的"私密独处漏斗很窄"一致。
   ⇒ **不要把 52.4% 读成上界**，它是"在这些条件没触发的前提下"的数。

---

## 八、探测包络（契约 §2.5）

本棒**没有新增任何一道门**（只有一个只读探针）。但探针里那个 containment checker
是 §六-1 那句话最容易被误做成的形状，所以它的包络必须写出来——**尤其是它抓不到什么**：

```
detects:（全部实测变红，非分析预言）
  · 把任意候选的 subject 追加进 prompt 文本 ⇒ checker 命中
      16715/16715（N=12·seeds 1/5/13·30d）· 60741/60741（N=20·seeds 1-3·30d）
  · 把任意社交候选的 partner【id】追加进文本 ⇒ 命中 33694/33694 · 112408/112408
  · 构造性渲染金丝雀：手搓一份覆盖全部 13 个社交动作 + object/journey/attend 的候选表，
    塞进 SUBJECT_CANARY / OBJ_CANARY / AREA_CANARY / COMMIT_CANARY + 真 partner id，
    交给【真的】AIBackend.build_prompt 渲染 ⇒ 候选行里五项全部 false。
    任何一次让它们变 true 的改动都会被这条抓到。

does_not_detect:（跑出来的，不是想出来的）
  · ★【本文的整个结论】——存在性泄漏。checker 在今天的树上全绿，而同一批 prompt 里
    52.4%（N=12）/ 62.7%（N=20）仍然在披露被点名邻居的私有谓词。
    一个查【值】的判据对【成员资格】结构上是瞎的。
    ⇒ 这条 checker 绝不可以被当成"知识门"出货——它会给出一个假的安全感，
      而那正是契约 §2.5 那句外审原话点的病。
  · 本人记忆里合法出现的 raw id：选举里程碑（Sim.gd:2941）把 topic id `cafe_expand`
    写进记忆文本 ⇒ 未按行拆分的 checker 会在这里报假红：12/16715（N=12/30d）、
    29/60741（N=20/30d），两格的【候选行】命中都是 0。
    我是把命中按"候选行 / 非候选行"拆开才分清的。
  · chat() / reflect() 两条路完全没测（_secret_guard 会把秘密 claim 原文喂给模型）。
  · backend != null + 真模型：一个数据点都没有。本探针只【渲染】prompt，不问任何模型。
  · attend 的空标签：checker 看不见它（它查的是"不该出现的串出现了没有"，
    不是"该出现的串缺了没有"）。是靠构造性渲染自检抓到的，不是靠 checker。

confidence: N=3 类变异（subject 追加 / partner-id 追加 / 5 个构造金丝雀）
  × 2 个网格（N=12·seeds 1,5,13·30d = 7810 决策点；N=20·seeds 1-3·30d = 14883 决策点）
  + 1 次隔离副本插桩跑（CI 覆盖那条结论）。
  存在性普查（52.4% / 62.7%）是【描述性统计】，不是一道门，别当判据引用。
```

---

## 九、方法与复现

**为什么走 scene 模式**：`AIBackend` 是 autoload，且 `build_prompt` 内部引用**全局 `Sim`**
（`Sim._name` / `Sim.get_agent`）。`--script` 模式里自建一个 `SimScript.new()` 实例，
`build_prompt` 仍会去查 autoload 的那个 `Sim` ⇒ 名字全查空。
这正是 `dump_decide_prompt.gd` 当初选择"手抄一份"的原因，**而抄件后来漂了**（§七-6）。
⇒ 本探针照 `bench/PickCtxDump.gd` 的形状驱动 autoload 的 `Sim` 本体，**零重实现**。

**零扰动**（红线 #1）：采集挂在既有的只读钩子 `Sim.decision_sink`（`Sim.gd:3561`，
不抽 RNG、不进 `event_log`/digest、CI 恒空）；`backend=null` 全程；探针只读、只拼字符串。

```bash
cd game
# 主网格（N=12，契约 §5 的展布用这一格）
C:/Users/yp/.local/bin/godot --headless --path . \
  res://bench/EpistemicPromptProbe.tscn -- --seeds 1,5,13 --days 30 --agents 12
# 规模格
C:/Users/yp/.local/bin/godot --headless --path . \
  res://bench/EpistemicPromptProbe.tscn -- --seeds 1-3 --days 30 --agents 20
# 明细（可选）：--out <绝对路径>.jsonl
```

六次网格运行全部 **0 条 `SCRIPT ERROR`**。CI 覆盖那一节（§二）的插桩跑在 scratchpad 的隔离副本上，
**仓库树一个字节没动**。

---

## 十、没能测到什么（不用推断填空）

- **没有跑任何真模型。** 本文量的是"模型被展示了什么"，**不是"模型从中推断出了什么"**。
  一个 0.5B–8B 的模型会不会真的利用 §三 那条存在性通道——**零数据点**。
  这条边界很重要：§3.3 的 52.4% 是**信道容量**，不是**已实现的泄漏**。
- ~~没有跑 `tools/ci.sh` 全量。~~ **跑了，`=== CI PASS ✅ ===`（本 worktree，全步骤，0 条 ❌）。**
  包括：版权红线 / data+link lint / 地图审计 / asset gate / S0 金标门 / LOD 观察无关门 /
  DetGate / **BackendGate** / **ModelPathGate** / VoiceGate / 9 个集成场景 / 视觉门（昼夜+界外重画+空间往返）。
  本棒只新增两个 bench 文件 + 本文，且新场景**不在** `ci.sh` 的任何一步里；
  照契约 §1「改完 bench 场景先单独跑那个场景」，先单独跑过 6 次才跑全量
  （契约 §1 那条「bench 场景的 parse error 会让 ci.sh 永远挂住而不是变红」就是指这个）。
- **`confide` / `leak` / `aid` / `attend` 四个动作一次都没出现过**（22693 个决策点）。
  它们的**渲染形态**是构造性验证的，**发生频率完全没测**。
- **`chat()` / `reflect()` 两条 prompt 路没测**——它们由玩家/夜间触发，`decision_sink` 抓不到。
  `_secret_guard` 把秘密原文喂给模型这件事我只做了代码判读，没有跑。
- **没有测 `ext.candidates()` 的 provider**：出货树上没有注册任何 CandidateProvider，
  所以 §一 的字段清单**对任何新 provider 都不成立**——一个新 provider 可以往候选字典里塞任何键，
  而 `build_prompt` 会照它的规则渲染（只认 `action` 与 `kind=="social"`）。
- **seed 数很小**：N=12 三个（1/5/13），N=20 三个（1-3）。52.4% 这类比例的展布很窄
  （51.2–53.2%），但按契约 §5，别把它当作跨配置可外推的常数。
- **`_names_nonnearby` 那一格我第一版量错了，写下来当教训**：初版没有排掉 agent **自己的名字**
  （它就在 `[人设]` 行里），也没考虑 **N=20 时 persona 复用会造成重名**（实测 8 个重名），
  于是它在 N=20 那一格报出 **84.4%**，而例子全是 agent 自己的名字——一个纯属伪影的数。
  修好之后：N=12/30d（0 重名）**76.1%**，N=20/30d **58.4%**
  （后者仍有 8 个重名在混，**这一格的读数要打折**）。N=12 那一格前后没变（没有重名可混）
  ——**这正是"伪影只在某一档配置上现形"的教科书样本**（契约 §2 第三个盲区）。
  这个数的正确解读是"`[近事]` 会合法地提到当时不在场的人"，**不是泄漏**——
  每一条记忆的写入点都有事务或目击溯源（`Sim.gd:2348` 的旁观者记忆是最宽的一条，
  而它写的正是"我看见 A 和 B 在某处做某事"）。
