# 118 · AE1 · 纪事不再把被拒讲成成功（**表现层修复，零金标**）

> 棒：AE1（docs/117 §一）。基线 `integration/batons`（`103d951`，本 worktree ff 到它）。
> owns：`game/scripts/Main.gd`（**只动 `_event_prose`**）+ 新建回归门 `game/scripts/event_prose_test.gd`
> ＋ `game/scenes/event_prose_test.tscn`。未碰 `Sim.gd`/`Story.gd`/`game/data/**`/`game/bench/` 现有文件/
> `tools/**`/`narrative/**`。依据：docs/41（红线 #2、§2.5 探测包络、§3 会移动 digest 的改动、§4 报告契约）、
> docs/116（AD2 设计，本波即它的「档 0」）、docs/105（AA2 的 27.4% 实测）、docs/111（真机活证）。
> **本文所有行号以本棒实读 `103d951` 为准。**

---

## 〇、一句话

`Main._event_prose`（`Main.gd:2120`）对**十个走通用「接受/婉拒」路的社交类型**不读 `accepted`、恒讲成「做成了」，
于是 `accepted=false`（被婉拒/未生效）的事件在纪事里被写成成功。**照 `meet`/`apologize` 已有的写法给这十类加
`if ok else` 被拒分岔即可**——零 schema、零金标、纯表现层。实测一格（seed 7 × 60 天）**被拒讲成成功 496 → 0**。

---

## 一、改了什么（diff：只 `_event_prose` + 新门）

`_event_prose` 的 `match t` 里，给下面十类各加 `if ok else` 分岔（接受走原文案、被拒走「被婉拒/没接茬/话没
递进去」这类）。这十类都在 `Sim.KNOWN_SOCIAL_ACTIONS`（`Sim.gd:953`），走通用社交路
（`Sim.gd:2419-2568`），拒绝时落 `_log_event(action,…,false,…)`（`Sim.gd:2426`），**真能 `accepted=false`**：

| 类型 | 接受版（原文案，保留） | 被拒版（新增，色 `#9aa0b5`） |
|---|---|---|
| `greet` | 找 %s 唠了两句 | 想找 %s 搭话，对方没接茬 |
| `give` | 送了 %s 一份小礼物 | 想送 %s 一份小礼物，被婉言谢绝了 |
| `gossip` | 悄悄向 %s 传了个八卦 | 想找 %s 咬耳朵，对方没搭理 |
| `invite` | 约了 %s 稍后见面 | 想约 %s 见面，被婉拒了 |
| `confide` | 对 %s 吐露了心事 | 想对 %s 说几句心里话，对方没接住 |
| `leak` | 在 %s 面前说漏了嘴 | 想找 %s 攀谈，话没递进去 |
| `gossip_rep` | 向 %s 议论起 %s 的为人 / 说起了别人的长短 | 想向 %s 编排 %s 的不是，对方没接茬 / 说人是非，没人搭腔 |
| `endorse` | 和 %s 对 %s 统一了口径 / 把话说到了一处 | 想拉 %s 一起数落 %s，没能说到一块 / 把话说拢，对方没应声 |
| `discuss` | 和 %s 聊起了各自的看法 | 想和 %s 聊聊看法，对方没接茬 |
| `aid` | 在 %s 难处时搭了把手 | 想在 %s 难处时搭把手，被回绝了 |

`git diff --stat game/scripts/Main.gd` = **1 file, +16 −10**（十条分岔 + 三段注释；`_event_prose` 之外一行未动）。

### 按事件族分清楚（AD1/AD2 的纪律，docs/116 §一.2）——**哪些【不碰】、为什么**

- **`betray`（`Main.gd:2140`）不加分岔**：它是 `leak` 成功时对第三方 teller 的**副作用事件**
  （`Sim.gd:2507`，`accepted` 恒 `true`），自己永不 `false` ⇒ 加 `if ok else` 会是死代码。**刻意不动，不是漏。**
  （`leak` 本身走通用路、能被拒，已加分岔。）
- **`conflict`（恒 `false`）/ `shortage` / `pact`(按 note) / `world`(按 note) / `rally_oust`(按 backers) / `election`(已分岔)**：
  它们的 `accepted` 要么无判别力、要么用别的字段表达成败，**本就不该按 `accepted` 分岔** ⇒ 不碰。
- **经济族**（`produce`/`consume`/`pay`/`spoil`/`shortage`）全在 `FEED_SKIP`（`Main.gd:284`）⇒ **根本不进表现层**
  ⇒ 与本 bug 无关（docs/116 §一.6）⇒ 不碰。
- **`meet`/`confront`/`apologize`/`mediate`（已有成/败分岔）**：本棒不动它们，也不由本门守（见 §四 does_not_detect）。

---

## 二、仿真侧逐字节不变（digest A/B，法则 A 兑现）

`_event_prose` 是 `Main.gd` 的表现层方法，**不在 Harness/Sim 金标路径上**（`Harness.gd` 只 `preload` `SimScript`、
直接驱动 `Sim`，从不加载 `Main`）。docs/116 §一.4「法则 A」是结构性推断，docs/41 §3/§4 要求**实测兑现**——实测如下：

**留出种子 13-15 × 60 天，改前（原 `Main.gd`）/改后（十条分岔全加）逐位对比**：

| seed | chain | digest | event_digest | events | 改前=改后？ |
|---|---|---|---|---|---|
| 13 | 2559303990 | 1783704470 | 4716512200143802942 | 3404 | ✅ 逐位相同 |
| 14 | 1883147346 | 3458365803 | 9169127939317251893 | 3424 | ✅ 逐位相同 |
| 15 | 3075355779 | 670158992 | 5348862147421552541 | 3380 | ✅ 逐位相同 |

**四项摘要（chain / digest / event_digest / events）改前改后无一位不同** ⇒ 仿真侧逐字节不变。
**出货种子 1-12 的锚由 CI 第 4 步 `Harness --golden game/bench/golden_digests.json` 独占**——金标是本改动之前烘的，
第 4 步全绿即证 1-12 的 digest 与改前基线逐字节相同。**未发现 `_event_prose` 进任何金标路**（无需按 docs/117 §硬要求 1 的
caveat 停手）。

---

## 三、量修好了多少（一格 60 天，改前 vs 改后）

`game/scenes/event_prose_test.tscn -- --census --seed 7 --days 60`：驱动 `Sim` 一格 60 天，逐条 `event_log` 喂
`_event_prose`，统计**受影响类中 `accepted=false` 却被讲成成功**（措辞里无任何被拒语义）的条数：

| 类型 | 该格被拒条数 | 被讲成成功（改前） | 被讲成成功（改后） |
|---|---|---|---|
| `gossip_rep` | 290 | 290 | **0** |
| `greet` | 101 | 101 | **0** |
| `discuss` | 76 | 76 | **0** |
| `gossip` | 29 | 29 | **0** |
| **合计** | **496** | **496** | **0** |

改前 **496 → 改后 0**。这四类正是 docs/116 §一.5 / AA2 §2.2 点名「在出货沙盘真带大量 `accepted=false`」的四类
（`gossip_rep`/`greet`/`discuss`/`gossip`）。其余六类（`give`/`invite`/`confide`/`leak`/`endorse`/`aid`）在 seed 7
本格**被拒 0 条**（潜伏类，docs/116 §五 阶段 2）——本棒仍给它们加了分岔，修的是「当它被拒时说对」，不是「现在有 bug」。

> **口径诚实**：496 是**单格观测计数**（seed 7 × 60 天），不是门的红/绿余量；AA2 的 976/27.4% 是**多 seed × 出货沙盘的
> 聚合**。单格 496 与聚合 976 同一量级、方向一致，但**不是同一个数**，别把二者当同一口径比较。

---

## 四、新回归门 + 双向负对照（docs/41 §2.5 三行包络）

新门 `game/scripts/event_prose_test.gd`（`.new()` 一个 `Main` 调 `_event_prose`，纯只读派生、从不写世界状态；
用全局 `Sim` autoload 解析名字，与 goals_test 同路）。两段：①**可分性门**（合成 `accepted=true/false` × 10 类，
`gossip_rep`/`endorse` 另测 `C==""` 变体）；②**普查门**（§三那格，断言被讲成成功 = 0）。

**正样本（改后树，实测）**：可分性门 **36/36 绿**（12 实例 × 3 断言）＋普查门绿（0 条）＝ `EVENT-PROSE GATE: ✅ PASS`。

**双向负对照（实测，读的是判决行与 rc）**：

| 变异体 | 结果 |
|---|---|
| **单删 `greet` 的被拒分岔**（退回非分岔） | `❌ FAIL (2 条断言红)` rc=1；恰好 `greet` 的「被拒版≠接受版」「被拒版含被拒语义」两条红，**其余 9 类全绿** |
| **十条分岔全删**（= 未改动的出货树本身） | 可分性门 **24 条红**（12 实例 × 2 条）＋普查门 **496 条红**；`❌ FAIL` rc=1 |
| **改后（正常）** | 可分性门 36/36 绿 ＋ 普查门绿；`✅ PASS` rc=0 |

**三行包络**：

```
detects:
  · 删任一受影响类型的 if ok else 被拒分岔 ⇒ 该类型「被拒版≠接受版」+「被拒版含被拒语义」两条红
    （实测单删 greet ⇒ 恰好 greet 2 条红、其余 9 类全绿、rc=1）。
  · 十条分岔全删（未改动的出货树）⇒ 可分性门 24 条红 + 普查门 496 条红（实测原树 rc=1）。
does_not_detect:（跑出来 / 想清楚的，这一栏空着 = 没想过）
  · 台词【质量/语气/器物/年代/通顺度】：本门只查关键短语与被拒词【在不在】，不查【好不好】
    （VoiceGate 那类质量问题它也一律放过）。
  · meet/confront/apologize/mediate/election 已有的成/败分岔：不在受影响集，坏了本门不红。
  · 经济族(FEED_SKIP，不上屏)与 conflict/betray/pact/world/rally_oust 这些 accepted 无判别力/用别的字段
    的类型：本门刻意不碰，它们措辞坏了不红。
  · 是否真的【上了屏】：本门只拿 _event_prose 的字符串，不经 RichTextLabel/气泡，屏幕显不显示、
    _salience 置顶与否本门看不见（docs/41 §6 盲区①）。
  · Story 极性锁（AA2/Story.gd 短语表）那一路：本门只守 Main 表现层，不守 Story（那是别棒的活）。
  · 普查只跑 1 格（seed 7 × 60 天）：别的 seed/换阵容/多镇让潜伏类型(give/invite/confide/leak/endorse/aid)
    被拒时，本格普查看不到（它们在 seed 7 恰好 0 条被拒）。
confidence:
  · 正样本 N=12 合成实例（10 类型 + gossip_rep/endorse 各 1 个 C=="" 变体）× 3 断言 = 36 条全绿；
    普查 1 格 60 天。
  · 负样本 N=2（单删 greet ⇒ 2 红；全删=原树 ⇒ 24 红 + 普查 496 红）。
```

⚠️ **本门尚未接进 `tools/ci.sh`**：接它需在第 5 步那条**写死的场景名单**（`ci.sh:637` 的 `for scene in …`）里加
一个词 `event_prose_test`——而 `tools/**` 在本棒的**不得触碰**清单里（docs/117 §一）。这与 D2/E2 当初把
`goals_test`/`story_test` 接进那条名单是同一处，但那两棒是**声明过的越界**、本棒 brief 明令不越。
⇒ **给集成者的一行**：在 `ci.sh:637` 的场景循环里加 `event_prose_test`（回滚＝删这一个词）。在它接入之前，本门靠
本回执里的实测输出证明有牙；「一道没进 CI 的门不是门」这条我认，所以把接入动作明写在这里等 tools 的 owner 拍。

---

## 五、CI 判决

`GODOT=<4.6.2> bash tools/ci.sh`（读输出、非退出码）：

```
=== CI PASS ✅ ===   （CI_EXIT=0）
```

改动只碰 `Main._event_prose`（表现层，不在任何门读的路径）+ 两个新 bench 文件（不进 CI 的场景循环）⇒
现有各门读的文件一字未变，全绿。

---

## 六、这份 brief（docs/117 §一）哪里对不上（docs/41 §4）

1. **brief 内联的 buggy 清单漏了 `leak`。** brief §一现状把 buggy 类列为
   `greet·give·gossip·invite·confide·gossip_rep·endorse·discuss·aid`（9 类），另把 `leak`/`betray` 单拎出来说
   「先判其 accepted 语义再决定」。**实读判决**：`leak` 走通用社交路、拒绝时落 `Sim.gd:2426` 的 `accepted=false`
   ⇒ **它属于要修的那一档**（本棒已加分岔）；`betray`（`Sim.gd:2507` 恒 `true`）**不属于** ⇒ 不动。
   ⇒ 真正要修的是**十类**（含 `leak`），而 docs/116 §一.5 的清单**正是这十类、一开始就对**——brief 内联那句压缩掉了 `leak`。
2. **坐标 `Main.gd:2120-2148` 的右界偏窄。** `_event_prose` 函数体到 `:2167`（改前），而 buggy 的 `match` 分支一直排到
   `aid`（改前 `:2145`）。brief 给的 2148 大致命中函数头与 `accepted` 读点，但**要改的最后一行是 `aid`（原 2145）**，
   不是 2148。（改后函数与行号已整体下移，见 §一。）
3. **「976 条 / 27.4%」不是单格数。** brief 说「改前应≈AA2 那条量级」。AA2 的 976 是**出货沙盘多 seed 聚合**；
   本棒按 brief「跑一格」测的是 seed 7 × 60 天 = **496**。二者同量级、同方向，但**口径不同**（聚合 vs 单格），
   §三已标注，别当同一个数比。
4. **brief 说 `meet/confront/apologize/mediate` 已按 `ok` 分岔——复核成立**（`Main.gd:2135/2137/2138/2139`，改后行号）。
   附一条本棒新查、brief/AA2 未点的：`_event_prose` 读 `accepted` **缺省 false**（`:2125`），而 `_salience` 读它
   **缺省 true**（`:2170`）——一个「没有 accepted 概念」的新事件类型会被一个当成功、被另一个当失败（docs/116 §一.5
   已记）。本棒未动 `_salience`，只把这条缺省不一致记在此，供设计新类型的人显式给 `accepted`、别靠缺省。

---

## 附：交付自查

- **文件级不相交**：`git status` = `M game/scripts/Main.gd`、`?? game/scripts/event_prose_test.gd`、
  `?? game/scenes/event_prose_test.tscn`。未碰 AE2（编号 119）owns 的 `tools/**`，也未碰任何被禁文件。
- **仿真不变**：留出种子 13-15 四项摘要改前=改后逐位相同（§二）；出货种子 1-12 由 CI 第 4 步金标锚住。
- **度量诚实**：496（单格观测）与 976/27.4%（AA2 聚合）**均为观测计数、非门余量**；本文不以任何「改善数字」作判据。
- **行号会腐烂**：本文行号实读于 `103d951` + 本棒改后树。以符号/上下文为准（docs/41 §1.5）。
- **不 push、不 merge**：仅本 worktree 分支一个 commit。
