# 142 · AQ1 · NPC 选角深度：可辨识居民 12 → 24（杀掉"拨大人口=12 张脸的复读机"）

**棒**：AQ1（内容棒）  **方向**：PC-first  **分支**：`worktree-agent-a3e33bef187e0f259`（基于 `integration/batons` tip `c1d1b08`）

## 〇 一句话

出货默认 N=12 不动一字节；把 personas 从 12 追加到 24，并让**克隆扩容**（N>12）从扩后的全池轮转 —— 拨大人口时露出**更多张不同的脸/名字**，而不再是 12 个原居民的复读机。追加人设的 traits **一律镜像**其轮转位对应的原居民，而 digest/chain **只经 traits 入 Sim**，故 **N=12/16/24/48 全部逐字节不变**（逐 tick 前缀链对齐），零金标 + 零门回归。

---

## 一 · 开工前 investigation（实读复核，含对协调者断言的两处更正）

### 1. 数据模型：`agents.json` vs `personas.json`，12 人从哪加载

- **`game/data/agents.json`**：12 个 agent（顺序 `aria,ben,coco,dan,evy,fei,lin,hai,shu,mei,qin,tie`），每个带 `persona`（外键 → personas.json）、`home`/`spawn`/可选 `spatial_address`。**这 12 条就是 N=12 的出货阵容。**
- **`game/data/personas.json`**：persona_id → `{name,color,traits,bio,style,sprite}` 的**扁平字典**（原 12 条）。
- **加载路径**（`Sim.gd:777-791`，`start_new`）：
  ```
  personas := _read_json("res://data/personas.json")
  adata    := _read_json("res://data/agents.json").agents      # 12 条
  defs     := adata.duplicate()                                # 先把 12 个基座 agent 全放进 defs
  if spawn_count > defs.size():                                # 只有 N>defs.size() 才克隆扩容
      for i in range(defs.size(), spawn_count):
          base := adata[i % adata.size()]                      # ← 旧：只在【12 个基座】里轮转 persona
          defs.append({"id":"npc_%d"%i, "persona": base["persona"], ...})
  for adef in defs: _make_agent(adef, personas)                # 每个 agent 一次 personas.get(key)
  ```
- **克隆从哪个池轮转**：旧代码 `adata[i % adata.size()]["persona"]` —— **只在那 12 个基座 persona 里转**。于是 N=60 时 48 个克隆是 12 个原 persona 的复读机（同名、同 bio、同 sprite 剪影，仅 id-hash 换个色相）。**这就是要修的 placeholder。**
- **最干净的改法**：**数据单改行不通**——克隆读的是 `adata`（agents.json）的 persona 字段；给 agents.json 加条目会**改变 N=12 的 spawn 数**（`for adef in defs` 会 spawn 全部 defs），直接打红 S0。所以必须：① personas.json **追加**新 persona；② 把克隆循环的 persona 源从 `adata` 轮转改为 `personas.keys()` 轮转（**仅** `spawn_count>defs.size()` 分支，N=12 从不进来）。这正是派单允许的"仅动 Sim.gd 克隆段、gated 在 N>12"。

### 2. N=12 路径不被扰动 —— 为什么（三重证明）

1. **结构短路**：S0 金标恒在 `spawn_count=0`（`ci.sh` 第 4 步不传 `--agents`）跑 ⇒ `0 > 12` 恒 false ⇒ **克隆分支从不执行** ⇒ 只 spawn agents.json 原样的 12 条、按原序、persona 键不变。
2. **查表不迭代**：`_make_agent` 用 `personas.get(adef["persona"], {})` —— **单键查表**，从不迭代 personas 全字典。往 personas.json **追加**键，对原 12 个 agent 的查表结果**零影响**。
3. **digest/chain 只经 traits 入 Sim**（关键，实读 `Invariants.gd:1397 digest` + `1427 chain_step`）：
   - `digest` 只哈希 `event_log` 的 `{id,type,actor,target,accepted,subject,tick,witnesses,note}`；`chain_step` 只哈希 `tick_no` + 每 agent 的 `{id,pos,needs,talking,option}` + 本 tick 事件。
   - `actor/target/subject/witnesses` 是 **agent id**（`npc_12`…），不是 persona 键/名；所有 `_log_event(...,note)` 的 note 都是**静态串**（`"seed"/"mediated"/"spawn"/"formed"/"backers:%d"`…），**从不嵌 persona 名/键**。
   - persona 进 Sim 决策**唯一**通道是 **traits**：`_make_agent` 的 `xi/eps`（`好奇/热情/寡言/务实/敏感/豁达` 成员判定）+ 决策分支 `爱八卦`(GOSSIP_TRAITS)、`耿直`(BLUNT_TRAITS)、`寡言/温柔`（confront/gossip/leak 矜持项）。
   - `name/color/bio/style/sprite/persona_key` **均不进 digest/chain**：`persona_key` 全仓仅两处——定义（`Sim.gd:905`）与 voicebank 取词（`Sim.gd:3944`，只进 UI 气泡）；voicebank 台词专用 RNG 盐 6007、独立流、不进 digest（数据文件抬头自述且实测）。

   ⇒ **推论**：只要新 persona 的 traits **镜像**其克隆轮转位对应的原 persona，则**每个克隆的决策行为逐字节不变**，仅显示层（脸/名/卡片/台词）不同。这把"零金标"从 N=12 一路推到**任意 N**。

### 3. VoiceGate —— 读哪个文件、要补什么，以及对协调者断言的**更正**

- **读**：`game/data/voicebank.json`（`{persona_key:{action:[台词…]}}`）。判据：**阵容里出现过的每个 persona_key 都必须被枚举到**（结构覆盖，非数量地板）+ 每个被 offer 的候选动作都有本人格的话（否则空串 → 判红）。
- **⚠ 更正协调者断言③**："VoiceGate 是 N 无关的 roster 枚举门…新 persona 没配台词会判红" —— **两处不准**：
  1. VoiceGate **是 N-相关**的：它枚举的是 `S.agents`（`start_new` 在**它跑的那个 N** 下产生的阵容）。
  2. `ci.sh:578-579` 跑 VoiceGate **不传 `--agents`** ⇒ 恒 **N=12** ⇒ `_cast_personas` 只含**原 12 个** persona_key ⇒ **新 persona 从不进它的枚举** ⇒ **CI VoiceGate 不会因新 persona 判红、也不会强制它们配台词**。
- **结论**：CI VoiceGate 绿与否**与新 persona 无关**（恒枚举原 12）。但为**产品质感**（拨大后新面孔说人话、不落通用罐头），本棒仍为 12 个新 persona_key **补齐** voicebank（各自镜像原居民的动作键集、台词全新、逐条非空）。

---

## 二 · 改了什么

### 文件与 diff 摘要

| 文件 | 改动 | 影响面 |
|---|---|---|
| `game/data/personas.json` | 原 12 条**一字节不动**；**追加** 12 条新 persona（键 `hua/shi/mian/huai/dou/gui/liu/tao/mo/yin/yun/yong`） | 扩池；N=12 查表不受影响 |
| `game/scripts/Sim.gd`（克隆段，仅 `spawn_count>defs.size()` 分支） | 克隆 persona 源 `adata[i%12]["persona"]` → `personas.keys()[i%24]` | 仅 N>12；N=12 从不进 |
| `game/data/voicebank.json` | 原 12 条 + `_note` **逐字节保留**（实测 head 13827B 一致）；**追加** 12 条新 persona 台词（各镜像其原型的动作键集） | 仅 UI 气泡；不进 digest |

`git diff --stat`（实测）：`personas.json | 15 +-`（原 12 仅 tie 行加尾逗号，其余 11 行为 context；+12 新条目）、`voicebank.json | 1028 ++`（纯追加，每行一条台词/键，indent=1）、`Sim.gd | 11 +-`（克隆段 +8 注释/1 池行/替 2 行）。

### 新增 12 位居民（追加在原 12 之后、**绝不重排**；traits **只用已枚举 token**）

**已枚举 token 全集**（原 12 人的 24 个 trait，逐一列出）：
`热情·爱八卦·务实·寡言·内向·敏感·豁达·爱讲古·好奇·莽撞·温柔·细心·勤快·唠叨·耿直·好酒·严谨·固执·细致·多疑·浪漫·散漫·豪爽·急躁`。
其中**带决策分支**的只有：`爱八卦`(GOSSIP_TRAITS)、`耿直`(BLUNT_TRAITS)、`寡言`、`温柔`（+ xi/eps 用 `好奇/热情/寡言/务实/敏感/豁达`）。新 persona **零新增 token、零新分支**。

| 键 | 名 | 职业/性格 | traits（**每个都镜像左侧原型、均"已枚举"**） | sprite |
|---|---|---|---|---|
| `hua` | 花婶 | 集市卖花 | `热情·爱八卦`  ← 镜像 aria【已枚举】 | Mage-Cyan |
| `shi` | 石头 | 石匠 | `务实·寡言`    ← 镜像 ben【已枚举】 | Soldier-Red |
| `mian`| 阿绵 | 绣娘 | `内向·敏感`    ← 镜像 coco【已枚举】 | Archer-Green |
| `huai`| 老槐 | 看庙园丁 | `豁达·爱讲古`  ← 镜像 dan【已枚举】 | Warrior-Red |
| `dou` | 阿豆 | 跑腿孩子 | `好奇·莽撞`    ← 镜像 evy【已枚举】 | Mage-Red |
| `gui` | 桂姨 | 采药 | `温柔·细心`    ← 镜像 fei【已枚举】 | Soldier-Blue |
| `liu` | 六婶 | 磨豆腐 | `勤快·唠叨`    ← 镜像 lin【已枚举】 | Archer-Purple |
| `tao` | 阿涛 | 码头扛包 | `耿直·好酒`    ← 镜像 hai【已枚举】 | Warrior-Blue |
| `mo`  | 墨先生 | 账房 | `严谨·固执`    ← 镜像 shu【已枚举】 | Character-Base |
| `yin` | 银针 | 当铺掌眼 | `细致·多疑`    ← 镜像 mei【已枚举】 | Soldier-Yellow |
| `yun` | 云生 | 扎风筝 | `浪漫·散漫`    ← 镜像 qin【已枚举】 | Mage-Cyan |
| `yong`| 大勇 | 撑船 | `豪爽·急躁`    ← 镜像 tie【已枚举】 | Warrior-Red |

**为什么镜像而非另配 traits**：4a 宏观池门（N=16、12 seed、**无 golden**、判不变量）的 #40 口粮软门余量薄；给克隆换 traits 会扰动 N>12 轨迹、可能翻红。镜像使**各 N 逐字节不变**（下节实证），4a/4b/不变量门**零回归**且**可证**——这是给"margin 薄的门"最稳的选择。可辨识度全由**显示层**（名/卡片/脸/台词）承担，恰好是"12 复读机"抱怨的那一层。

### 克隆轮转如何仍然逐字节等价（代数）

新克隆 i（i≥12）取 `keys[i%24]`；keys 保序 `[原0..11, 新0..11]`，且 `新k.traits == 原k.traits`。
故 `keys[i%24].traits == 原((i%24) mod 12).traits == 原(i%12).traits ==` 旧克隆 i 的 traits。**每个克隆位的 traits 与改前完全相同** ⇒ 决策逐字节不变；仅 persona_key/显示不同。

---

## 三 · 零金标三证据（命门，含 chain）

**seed**：S0 固定 `1-12`（`ci.sh` 不传 `--agents`），days 60，det 3。烘于 godot `4.6.2-stable.71f334935`，本机同版。

1. **① 开工前 S0 baseline**（`analysis/aq1/s0_baseline.log`）：`S0 GATE: PASS ✅ 12/12`，金标一致 12/12（含逐 tick 前缀链 12 条）。
2. **② 改后 S0 金标**（`analysis/aq1/s0_after.log`）：
   `✅ 金标一致 12/12 seed（含逐 tick 前缀链 12 条）` · `S0 GATE: PASS ✅ 硬 12/12 · 软 ≥11/12 · 活性过 · 金标过 · det 3/3`。
   ⇒ **N=12 spawn 的原 12 人一字节未动**（`golden_digests.json` 未改，S0 逐字节比中）。
3. **③ N>12 逐字节等价**（`--chain-dump`/`--chain-ref`，`git stash` 前后同命令；见 `analysis/aq1/chainref_n*_after.txt`）：

   | N | 配置 | digest/chain（before == after） | 逐 tick 前缀链 |
   |---|---|---|---|
   | 16 | seeds 1-3 · 30d | seed1 `1147017195`/`1426770953`、seed2 `736576017`、seed3 `1413459885`（全等） | **✅ 逐 tick 一致 3/3** |
   | 24 | seeds 1-3 · 30d | seed1 `891602587`/`869009267`、seed2 `3931039487`、seed3 `4151237543`（全等） | **✅ 逐 tick 一致 3/3** |
   | 48 | seeds 1-2 · 20d | seed1 `2084433069`、seed2 `3648427935`（全等） | **✅ 逐 tick 一致 2/2** |

   ⇒ 克隆池换 persona **没有搅动任何一个 tick 的任何一个 agent**（chain 是逐 tick 前缀哈希，任一 tick 分叉都会雪崩到终值）。**4a(N=16)/4b(N=48)/所有不变量判据在各 N 逐字节不变** ⇒ 结构上不可能回归。

留档 seed 与全部 before/after 值：`analysis/aq1/vals_n*_before.txt` + `chainref_n*_after.txt`。

---

## 四 · 拨大眼验（N=24 · 同 seed 同 tick · 改前 vs 改后）

参数固定：`--agents 24 --seed 1 --warmup-tick 120`（第 1 天正午，居民出门）。

- **克隆卡片各异**（点 3 个原克隆位，`--select npc_N`）：

  | 克隆位 | 改前卡片 | 改后卡片 | traits（镜像，不变） |
  |---|---|---|---|
  | `npc_12` | **阿丽**（aria 复读） | **花婶**「集市卖花的婶子…」 | 热情·爱八卦 |
  | `npc_15` | **老邓**（dan 复读） | **老槐**「看庙的老园丁…」 | 豁达·爱讲古 |
  | `npc_18` | **阿林**（lin 复读） | **六婶**「磨豆腐的六婶…」 | 勤快·唠叨 |

  见 `docs/media/aq1_{before,after}_card_npc{12,15,18}.png`。改前 npc_12 场景里同时挂着**两个"阿丽"**名牌；改后同位置的名牌变成 `花婶`/`云生`（新居民），全镇只剩**一个**基座"阿丽"。事件流也从清一色原名变出 `六婶/阿豆/阿涛/老槐`。

- **全镇取景**（`--shot-fit`）：`docs/media/aq1_{before,after}_n24_wide.png`。两图**居民位置逐格相同**（byte-identical sim 的直观佐证），差别只在身份——正是本棒的边界：**改身份、不改仿真**。

---

## 五 · 门输出 / CI 判决行

- `lint_data`：`OK · 23 json parsed · FKs resolve (12 agents, **24 personas**, 8 objects)`。
- S0（第 4 步）：`S0 GATE: PASS ✅ 12/12`（金标含 12 条链）。
- 4a 宏观池门（N=16）/ 4b LOD（N=48）：逐字节等价（§三·③）⇒ 判据不变 ⇒ 绿。
- 4f VoiceGate（N=12）：恒枚举原 12（§一·3）⇒ 绿；新 persona 台词已补（拨大后说人话）。
- 全 `bash tools/ci.sh` 判决行：见 `analysis/aq1/ci_full.log` 末行（回执附）。
  ⚠ 提交前跑的**互补性守卫**比的是 committed `HEAD:game`（docs/140），与工作树可能不同——由协调者在 committed 树重烘重跑，本棒不据其定绿红。

## 六 · owns 边界

碰：`personas.json`（追加）、`voicebank.json`（追加）、`Sim.gd` 克隆段（仅 N>12）、本文档、`docs/media/aq1_*`、`analysis/aq1/`。
**未碰**：Sim.gd 的 N=12 决策/加载路径、原 12 人设、`golden_digests.json`/`DetGate`/`Inv.digest`/chain、WorldView/室内外绘制、`gate_*`、VoiceGate.gd。
