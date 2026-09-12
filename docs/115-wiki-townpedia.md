# 115 · AD1 · 镇民百科 wiki（**纯只读投影，零金标风险**）——回执

> 波次 docs/114 §一（AD1）。基线 `integration/batons`（本 worktree 从 `160559c` 起分支 `ad1-wiki`）。
> 前置：docs/41 合同（红线 #2 与 §2.5）、docs/113 §三 功能轨道。
> **本波只加新文件、不改任何既有文件**——`git status` 全是 `??`，对既有门结构上零风险。

## 〇、一句话

从**已有仿真态**（`event_log` / `beliefs` / 关系账本 / 职业 / 记忆）生成一份**镇民百科**：
每个 NPC 一页——职业与班次、五需求、带符号的关系、信念（含 `CR:`/`TR:`/`SH:`/`W:`/秘密）、
把 `event_log` 讲成人话的**大事记**、以及由数据归纳的故事弧。
**纯只读投影：不改仿真一个字节，不进金标。** 仿真侧逐字节不变有三路独立证据（§三）。

## 一、owns 与产物

**新建**（本波全部产物；无一改动既有文件）：

| 文件 | 作用 |
|---|---|
| `game/bench/wiki_dump.gd` | 引擎侧【纯只读】导出台：跑正典循环 → 把每 NPC + 整条 `event_log` 投影成 JSON；自带 `--selfcheck`（A/B + 金标 + 留出 seed 的 digest 门） |
| `tools/gen_town_wiki.py` | 渲染器：读投影 JSON → 自包含离线 HTML（+ 每人 markdown）；自带 `--gate`（可追溯性门） |
| `analysis/wiki/seed07/town_wiki.json` | 真样例投影（seed 7 / 60 天 / 12 NPC / 3235 事件，1.3 MB） |
| `analysis/wiki/seed07/town_wiki.html` | 真样例百科（自包含、可离线打开，428 KB） |
| `analysis/wiki/seed07/md/*.md` | 12 位 NPC 的 markdown 版（复用/机读友好） |
| `analysis/wiki/seed07/traceability_report.json` | 可追溯性门的收据（含 §2.5 三行包络） |
| `docs/media/wiki_town_index.png` | 截图（桌面暗色，含花名册 + NPC 卡） |
| `docs/media/wiki_npc_mobile.png` | 截图（移动端单列自适应） |

**不得触碰**（brief §一）：既有 `game/scripts/**` / `game/data/**` / `game/bench/**` / `tools/**`、
`game/scripts/narrative/**`、`game/scripts/story_test.gd`——一个字节都没动。

跑法：

```
# 导出一 seed 的投影
godot --headless --path game --script res://bench/wiki_dump.gd -- --seed 7 --days 60 --out ../analysis/wiki/seed07/town_wiki.json
# 渲染 + 可追溯性门 + markdown
python tools/gen_town_wiki.py --in analysis/wiki/seed07/town_wiki.json --outdir analysis/wiki/seed07 --gate --md
# 仿真零扰动 + 权威轨迹自检
godot --headless --path game --script res://bench/wiki_dump.gd -- --selfcheck --days 60 --heldout 13
```

## 二、导出的字段 schema（供 storylets / narrative 复用）

投影 JSON = `town_wiki/v1`。**这就是 brief §一硬要求4「schema 要能被将来复用」的落点**——
下面每个字段都直接取自 Sim 的活状态或 `event_log`，不重算、不发明。

- `meta`：`seed / days / tick_no / day / n_agents / n_events / ticks_per_day / godot / digest / event_digest / chain`、
  `needs`（五需求定义：id/label/low/decay）、`topics`（三个镇议题）、`id_to_name`。
- `agents[]`（每 NPC）：
  - 身份：`id / name / traits / bio / style / color / persona_key`
  - 职业：`job{title, action, wage, shift[]}`（从 `jobs.json` 解析）、`faction / faction_size`
  - 状态：`needs{}`（五需求 0-100）、`mood / coin / gift / skills{} / area / space / floor`
  - 关系：`relationships{oid → {affinity, trust, resentment, familiarity, standing, last_pos, last_neg}}`
  - 信念：`beliefs{bid → {claim, subject, source, via, tick, secret?, owner?, confidedBy?}}`
    键前缀语义：`CR:`手艺口碑、`TR:`买卖口碑、`SH:`缺货记恨、`W:<id>:rich/broke`贫富见闻、
    `R1`/`S_own_<id>`/`S_*`秘密与传闻。
  - 看法：`attitudes{topic → [-1,1]}`；盟约：`pacts{}`；记忆：`memory[]`（`{text, importance, tick, tags}`）。
- `events[]`：**整条 event_log**，逐条 `{id, tick, type, actor, target, subject, accepted, witnesses[], note}`。
  这是大事记可追溯性的根——每句大事记回指某条 `event.id`。

## 三、仿真侧逐字节不变——三路独立证据（`--selfcheck`，60 天）

`wiki_dump.gd` 只从 Sim 读字段，绝不调用任何写世界态的方法。证据（实测输出，全绿）：

| 证据 | 判据 | 结果 |
|---|---|---|
| **A/B（读 vs 不读）** | 同 seed 跑两遍：一遍中途每日界 + 终局做全套投影读、一遍什么都不读 → `digest`/`event_digest`/`chain`/`events` 必须逐字节相同 | **13/13 seed AB=OK**（含留出 seed 13） |
| **金标匹配** | 本台的每 seed `digest`/`event_digest`/`chain` == `game/bench/golden_digests.json`（Harness 烘的权威金标） | **12/12 seed golden=OK** |
| **留出 seed** | seed 13（不在金标 1-12 里）做 A/B，证明「读零扰动」与是否在金标里无关 | **seed 13 AB=OK**（golden=MISS，金标本就无此 seed） |

正典循环（`chain=Inv.CHAIN_INIT`、每 tick `Inv.chain_step` 后 `ev_seen=event_log.size()`、终局 `Inv.digest`）
**逐符号抄自 `Harness._run_once`**——12/12 与金标吻合正是「本台跑在权威轨迹上、没把仿真带偏」的证明。

seed 7 样例的三摘要：`digest=1815148170`、`event_digest=6746897355515116126`、`chain=1323281150`，
与 `--selfcheck` 里 seed 7 那一行**逐位相同** ⇒ 导出路与 digest 路一致。

### §2.5 三行包络 · digest 门（`wiki_dump.gd --selfcheck`）

```
detects:        读投影臂改变了任一 seed 的 digest/event_digest/chain ⇒ AB=FAIL（本次 13 seed 全 OK）
detects:        本台轨迹与金标 1-12 任一不符 ⇒ golden!=OK（本次 12/12 匹配）
does_not_detect: 投影字段是否【齐全】——少读一个字段 digest 照样不变（digest 只折 event_log，不折我读了哪些活状态）
does_not_detect: 渲染层是否把 rejected 写成 happened——那由 gen_town_wiki.py 的可追溯门守，不在本台
confidence:      A/B N=13 seeds（含留出 seed 13）；golden N=12 seeds
```

⚠️ **诚实边界**：A/B 恒等在「只读」下近乎必然成立（GDScript 读不 mutate）。它真正防住的是
**将来有人给 `wiki_dump.gd` 加了一个会 mutate 的读**（例如误调 `memory.add` / 触发懒构造）——
那时这道门立刻变红。金标匹配才是「轨迹没被带偏」的强证据。

## 四、可追溯性 + 被拒如实标——渲染层的门（`gen_town_wiki.py --gate`）

大事记不发明情节（红线 #2 的精神）：**每一句都由一条真实 `event` 生成，并在 HTML 上以 `#<id>`
标注、`data-ev` 属性机读**。被拒的社交事件用 `event.accepted=false` **如实标成「被拒」**，绝不写成 happened
（这正是 AA2 量到的 27.4% 病，wiki 层先如实标；从源头修是 AD2 的设计题）。

实测（seed 7 / 60 天 / 12 NPC）：**1961 条大事记行全部可追溯**（0 违规）；
**932/932 条社交被拒事件被如实标注**（跨页对账全镇社交被拒 `event` 共 498 条，
一条社交事件同现于 actor 页与 target 页 ⇒ 932 ≈ 498×~1.9）。收据：`analysis/wiki/seed07/traceability_report.json`。

### §2.5 三行包络 · 可追溯性门（`gen_town_wiki.py --gate`）

```
detects:        大事记引用了投影里不存在的 event id（发明情节/串号）⇒ 门红（本次 1961 行全部命中真实 id）
detects:        社交类 accepted=false 被渲染成 happened（漏标被拒，AA2 的 27.4% 病）⇒ 门红（本次 932/932 如实标）
does_not_detect: 大事记措辞的语义保真度（subject 指错人、器物/年代错）——只校 event.accepted 这一位，不校文案质量
does_not_detect: Sim 自身把事件标错 accepted 的情形（wiki 层如实转写 Sim 的字段，不复核 Sim 的判定）
does_not_detect: 非社交类 accepted=false（shortage/conflict 结构性 false）——不是被拒，按类型另叙，故意不套被拒框
does_not_detect: greet/discuss/witness-only 参与不逐条上大事记（避免刷屏），故其被拒走【聚合】而非逐条追溯
confidence:      N=1961 大事记行、932 条社交被拒（当事人页）、498 条全镇社交被拒 event
```

## 五、`accepted` 的语义按事件族分岔（**brief 有错，此处更正**）

brief（docs/114 §一）说「用 `event.accepted` 区分做成了/被拒了」。**这只对社交族成立，
对经济族是错的**——我实读 Sim 后按族拆开，波中 AD2 也独立发来同一条更正，两路一致：

| 事件族 | 类型 | `accepted` 语义 | wiki 层处置 |
|---|---|---|---|
| **社交族** | `greet·give·gossip·gossip_rep·discuss·invite·confide·leak·endorse·aid·meet·confront·apologize` | 真区分接受/婉拒（被拒记忆 Sim 写「被婉拒了」） | **读 `accepted`**：false → 标「被拒」，用被拒文案 |
| 提案/号召 | `election·rally_oust·mediate` | 通过/否决、有无响应、劝没劝和 | 读 `accepted`，但标「未成」而非「被拒」（不套社交被拒框） |
| **经济族** | `produce·consume·pay·spoil` | **恒 `true`**（失败的 pay 根本不落账）——无接受/拒绝概念 | **不读 `accepted`**，直接叙述「发生了」（走聚合统计） |
| 固定标记 | `conflict·shortage` | **恒 `false`**——不是被拒，是这类事件的固定标记 | **不读 `accepted`**，按类型叙述（冲突/缺货记恨），不标被拒 |

⇒ 若把每个 `accepted=false` 一律当「社交被拒」，本身就是一次误标（把 shortage/conflict 的结构性 false
写成「被拒了」）。这是本 session「**先确认你量的是哪个对象**」的又一例——同一个 `accepted` 位承载三种含义。
渲染器的 `SOCIAL_REBUFF`/`ECONOMY`/`FIXED_FALSE`/`PROPOSAL` 四个集合就是这张表的落地。

## 六、这份 brief 哪里是错的（§4 报告契约）

1. **`accepted` 一刀切**（见 §五）——brief 的「用 `accepted` 区分做成了/被拒了」漏掉了它是**三义**的；
   经济族恒 true、conflict/shortage 恒 false。已按族拆开，波中 AD2 的更正与我的实现一致。
2. **基线 SHA 漂移**：brief 与 docs/113 §〇 写基线 `integration/batons` 为 `3b639d9`，
   实测本 worktree 可见的 `integration/batons` HEAD 是 **`160559c`**（docs/114 那条 commit 本身）。
   我从 `160559c` 起分支，它是我 checkout HEAD 的后代（可 ff）。不影响产物。
3. **「零引用先 `git log -S`」照做了**：`git log -S wiki` / `git log -S 百科` 只命中 docs/113·114·07 等
   规划文档，树上**无任何既有 wiki/百科代码**可复用——绿地属实。
4. 其余 brief 描述（只读投影、不进金标、编号 115、别写 `docs/`+116）均属实并已遵守。

## 七、样例观察（真数据，非结论）

seed 7 涌现出一条可读的社会剧：**阿丽 vs 铁牛**长期不睦（亲密 −32、大量「想跟铁牛议论…被挡回来」），
中途一次 confront→apologize 和解（`#2008`→`#2071`→`#2670`→`#2777`）；阿丽与**阿本/沈书**是稳定挚友；
全镇反复因**口粮/柴薪断货**记恨到面点师**阿林**与杂役**老邓**头上（`SH:` 信念 + shortage 事件）。
这些都逐条指得回 `event.id`，无一句杜撰。

## 八、CI

`GODOT=... bash tools/ci.sh` 全量跑一遍——**我没碰任何门**，CI 应原样绿（只证没顺手弄坏）。
实际输出见 §2.5 三行包络（本波两道门都是**自检**，不是 `ci.sh` 里的门）。CI 结果贴在回报里。

## 九、没能测到 / 留给后续

- **只投影了一个 seed（7）的样例**——生成器对任意 seed 通用（`--seed`），但 HTML 样例只出了 seed 7。
- **HTML 走 Chrome headless 截图**（桌面暗色 + 移动端）；引擎内面板未做（brief 二选一，选了 HTML 路，自包含可离线）。
- 大事记只覆盖**当事人**（actor/target/subject）行；**witness-only** 参与与 **greet/discuss** 高频社交走聚合，
  不逐条追溯（见 §四 `does_not_detect`）——这是刻意的刷屏权衡，不是漏。
- 反向声誉（别人怎么看 TA）只在**当前在场** NPC 间统计；festival 临时 spawn 的过客不计。
