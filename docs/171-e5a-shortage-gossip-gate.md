# 171 · E5a：缺货流言门（`no_shortage_gossip`）——工业/treat 货缺货不再 churn 声誉基质 · 判决：**合格负结果 · HARD STOP（不 land）**

> 本片是 docs/170（E4d-B）§五点 1 亲手开的那条出路——**「给缺货货一条不进 gossip 的静默通道（改 `_shortage_fallout`，动 Sim.gd）」**——的 **Baton 1**：把机制做出来（Sim.gd 早退 + `production.json` 给糕点挂 `no_shortage_gossip:true`），移金标，**在隔离态证核心中性**。判决：**机制本身干净（off-gate 逐字节自证、golden 可归因地移动），但它【不】在隔离态保核心中性**——两条独立的负信号：**① #40 软门从 12/12 退到 10/12**（重烘金标救不了，是活门回归）；**② 核心留出锚 口粮 点估计 −0.0197（偏负、非平非升）**。按 brief 的判决规则（`核心非 flat/up → STOP/escalate`）+ 硬约束（`验 #40 12/12`，现已破），**不 land 代码、docs-only、上交协调者 escalate**。Baton 2（加饼干）**不启动**。

## 〇、判决摘要（先说结论）

| 验收项 | 结果 |
|---|---|
| **CODE**（Sim.gd `_shortage_fallout` 早退，在 ②memory.add 之后、③信念插入之前）| ✅ 已实现（静态读 `gd.get("no_shortage_gossip",false)`，无 RNG/Time）|
| **DATA**（production.json：`goods.糕点` 加 `no_shortage_gossip:true`，**仅糕点**，无饼干）| ✅ 已实现；缺键=原行为 |
| **★off-gate 自证**（删糕点 flag → 代码在场但门不触发 → `Harness --seeds 1-12 --days 60 --det 3 --golden`）| ✅ **金标一致 12/12 逐字节**（seed1 digest **3894698000** / chain **78488955** / event_digest **1945279565897149957** = 改前金标；含逐 tick 前缀链、det 3/3、S0 GATE PASS）——**代码路在 flag 缺席时是干净 no-op** |
| **move-golden（flag ON 糕点）**| ✅ golden **移动 36 处**、12/12 seed 硬不变量全绿（`hard_fails:[]`）——移动**可归因**：唯一改动的代码路是「flagged 货跳过 ③④」，唯一挂 flag 的是糕点，off-gate 逐字节互补 ⇒ 每一处移动 = 糕点 SH 信念 + 声誉挫伤被抑制的下游 |
| **① 强制性验证**（`_log_event("shortage")` 仍在 → sh_day 仍填 → 糕点不会假装 never_short）| ✅ 糕点 shortage_days 两臂皆 >0（seeds 1-12 无一为 0）——**#40 糕点自身臂完好** |
| **★★★核心留出锚（seeds 13-30 N=12）**| ❌ **口粮 median −0.0197 / mean −0.0233（9 下/9 上，但降幅 0.094 ≈ 升幅 0.048 的 2×；95% CI [−0.063,+0.017] 跨 0，n.s.）**——**非 flat-or-up**（点估计偏负、约 E4d-B −0.046 的一半）；柴薪 −0.0071 · 屋瓦 +0.0000 · 糕点 −0.0021 · 整洁 +0.0000，五货全 n.s. |
| **★★#40 软门（seeds 1-12 N=12）**| ❌ **BASE 12/12 → WITH 10/12**（seed 2、10 触【缺货绝迹】上限臂）——**重烘金标救不了**（#40 满足率判据与 golden 摘要无关）|
| **full ci.sh 判决**| ❌ **S0 FAIL**（软通过率门破：#40 10/12；金标破：36 处——后者预期、重烘可复，前者不可）|

⇒ **Baton 1 的成功判据「隔离态证核心中性」未达成**：机制干净但不中性。**HARD STOP，docs-only 负结果，代码已回退，金标不动。**

## 一、四效分解（`_shortage_fallout`，Sim.gd ~3548-3582）——什么抑制、什么保留、为什么①强制

`_shortage_fallout` 做四件事，两件决策惰性、两件喂决策：

| # | 代码 | 行 | 喂不喂决策（backend=null）| 本片处置 |
|---|---|---|---|---|
| ① | `_log_event("shortage", …)` | ~3566 | **惰性**（决策不读 event_log）**但 #40 上限臂强制**：never_short 由 shortage EVENT 经 sh_day 构建（Invariants.gd ~902-903 `elif _ty=="shortage": sh_day[_g][tick/tpd]=true`；~924 `if sh_day[gid].is_empty(): never_short.append`）。**丢了①→糕点全年零 shortage 事件→假装 never_short→翻 #40 绝迹臂红** | **保留** |
| ② | `ag["memory"].add(…)` | ~3570 | **惰性**（memory 只被 serialization/voice 读、决策引擎在 backend=null 下不读）| **保留** |
| ③ | `s["beliefs"]["SH:<good>"]=…` 插入在场者信念 | ~3580-3581 | **喂决策**（SH 信念进 `_unspread_belief` 的 gossip 候选、被转述扩散、扰动社交图）| **抑制** |
| ④ | `_adjust_standing(s, blame, …)` | ~3582 | **喂决策**（standing 是 `_acceptance_rule` 的一项 `st=standing*STANDING_K`）| **抑制** |

**改动**：在 ②（memory.add，~3570）之后、③（`if blame==""…` 块，~3571）之前插入
```gdscript
if bool(gd.get("no_shortage_gossip", false)):
    return
```
`gd` 已在 ~3563 取得。flagged 货的缺货仍进 **①账本 + ②私记 + 镇纪事**，但**不挫产者声誉、不入信念 gossip（③④）**。缺键=原行为，其余八种货逐字节不变。

**为什么 ③④ 是稀释源**（docs/170 §三 的机制）：缺货 → 写 blame=产者 的 SH 信念 + 挫产者 standing → 经既有 gossip 管线扰动全镇信念/声誉/社交轨迹 → 间接改动食物产者（面点师/渔夫）的做活机会 → 拽下最紧的生存货口粮的替补产能。docs/170 量出：加饼干【消费】（→周期性缺货→③④ churn）把口粮拽 −0.046，而 NULL 臂（饼干产而不吃、不缺货、无 ③④）核心逐字节 0.0000。所以稀释**全在** ③④。本片直接抑制 ③④。

## 二、★off-gate 自证——代码在 flag 缺席时逐字节 no-op

删糕点的 `no_shortage_gossip`（保留 Sim.gd 早退）→ `if bool(gd.get(...,false))` 恒 false → 门永不触发 → 跑
`Harness --seeds 1-12 --days 60 --det 3 --golden game/bench/golden_digests.json`（`analysis/e5a/offgate_golden.txt`）：

- **金标一致 12/12 seed（含逐 tick 前缀链 12 条）**；seed1 `digest 3894698000 / chain 78488955 / event_digest 1945279565897149957` = 改前金标逐字节。
- **S0 GATE PASS ✅**（硬 12/12、软通过率门过、活性过、金标过、det 3/3）。

⇒ 代码路是干净 no-op：**任何 golden 移动都只可能来自 flag**。这是 move-golden 归因的干净互补。

## 三、move-golden（flag ON 糕点）——golden 可归因地移动

`analysis/e5a/move_golden_WITH.txt`：golden **36 处不符**，12/12 seed `hard_fails:[]`（硬不变量全绿）。seed1 digest 3894698000→2997753687、chain 78488955→3907638170。

**归因**（airtight）：唯一改动的代码路 = 「flagged 货跳过 ③④」；唯一挂 flag 的货 = 糕点；off-gate 证 flag 缺席时逐字节不变。⇒ 每一处 golden 移动 = 糕点缺货的 SH 信念不再插入 + 糕点师 standing 不再被挫 的下游轨迹重排。糕点 shortage 事件（①）照写（shortage_days 两臂皆 >0），移动的是**信念/声誉信道**，不是账本。

## 四、★★★核心留出锚（seeds 13-30 N=12）——**非 flat-or-up**（THE 判决）

`ScaleSupply --agents 0 --seeds 1-30 --days 60` 两臂（BASE=提交树无 flag / WITH=糕点 flag ON），`analysis/e5a/core_anchor_13-30.txt`：

| 核心货 | median Δ | mean Δ | 95% CI(t) | down/up/flat | 判读 | 对照 E4d-B(STOP)/E3b(PASS) |
|---|---|---|---|---|---|---|
| **口粮** | **−0.0197** | −0.0233 | [−0.063,+0.017] | 9/9/0 | **n.s. 偏负** | E4d-B −0.0457 · E3b +0.041 |
| 柴薪 | −0.0071 | −0.0219 | [−0.055,+0.011] | 10/5/3 | n.s. 偏负 | E4d-B −0.0016 |
| 屋瓦 | +0.0000 | −0.0146 | [−0.055,+0.026] | 5/5/8 | n.s. | E4d-B −0.0002 |
| 糕点 | −0.0021 | +0.0079 | [−0.053,+0.069] | 9/9/0 | n.s. | E4d-B +0.0006 |
| 整洁 | +0.0000 | −0.0032 | [−0.026,+0.019] | 6/6/6 | n.s. | E4d-B +0.0000 |

**口粮偏负 −0.0197**（点估计），约 E4d-B −0.046 的一半。9 下/9 上看似平衡，但**降幅（均 0.094）≈ 升幅（均 0.048）的 2×**，净 mean −0.0233。95% CI 跨 0 ⇒ 与「0」**和**「小幅稀释」都统计不可分（n=18、大幅双向重排：seed13 −0.140 / seed15 +0.107 / seed23 −0.102 / seed29 −0.123）。

**关键**：brief 的判据是**「flat 或 IMPROVE（≥ 中性）」**，且预测「抑制 churn 源 → 口粮 neutral-or-up」（因 E3b 加糕点 gossip 时口粮 +0.041）。**实测点估计偏负、非升**——预测**没兑现**。

**为什么预测反了（本片最有价值的一课）**：E4d-B 量出「**加**饼干 gossip → 口粮 −0.046」，自然推论「gossip churn 伤核心 → 抑制它能救口粮」。但本片量出「**抑制**糕点 gossip → 口粮**也**偏负 −0.02」。两向都伤口粮，说明**缺货流言不是单调的稀释杠杆、是一个混沌扰动源**：它已经烘进均衡，加它、减它都只是把轨迹**重排**到另一个（对口粮碰巧也略差的）均衡，而不是「拆掉 churn 就线性收回口粮」。**cut-point 读得对（③④=churn、①②=惰性，off-gate 逐字节自证），错的是 OUTCOME 预测（抑制糕点 ③④ 能保核心中性）。** ⇒ 这正是 brief 的 STOP 条款「the cut-point reading needs escalation」。

## 五、★★#40 软门回归（seeds 1-12 N=12）——**BASE 12/12 → WITH 10/12**，重烘救不了

`analysis/e5a/inv40_1-12.txt`：#40 **BASE 12/12 → WITH 10/12**，seed 2、10 触发 **R1 上限臂「缺货绝迹」**（Invariants.gd ~929-949：`never_short*2 > gated_n` = 严格多数不缺 → 红）。逐 seed never_short 计数：

```
seed  1: 1→2   seed  2: 3→4 TRIP   seed  3: 2→3   seed  4: 1→2   seed  5: 1→3   seed  6: 2→2
seed  7: 1→1   seed  8: 1→3        seed  9: 1→1   seed 10: 3→4 TRIP  seed 11: 2→2   seed 12: 1→2
```

**机制（清楚且重要）**：WITH 每个 seed 的 never_short 计数**系统性 ≥ BASE**——抑制糕点缺货流言**calm 了全镇**（少了扰动社交/时序的 churn）→ 居民消费更少被打断 → **其他货**（屋瓦/整洁/话本/豆子）更频繁全年零缺货 → 撞 #40「缺货应【周期性】而非从不」的绝迹臂。**触发的不是糕点自己**（① 保留、糕点照缺货，见 §〇「① 验证」）——是糕点 gossip 被拆后、镇子平静下来的**二阶波及到别的货**。

**为什么这是硬阻断**：#40 是软不变量，门槛固定 ≥11/12，**与 golden 摘要无关**。协调者重烘金标只更新 digest 锚，**不改** #40 的满足率计算 ⇒ 重烘后 S0 **仍**在软通过率门破（#40 10/12）。这与「golden 36 处不符」（预期、重烘可复）性质不同——**#40 是重烘救不了的活门回归。**

> brief 的 #40 缓解（保①，别让糕点假装 never_short）是**必要但不充分**：它挡住了糕点自身臂翻红，却挡不住「拆糕点 gossip → 全镇少缺货 → 别的货绝迹」这条二阶路径撞同一条上限臂。#40 绝迹臂在 N=12 seeds 1-12 只有「余量 1 种货」（Invariants.gd ~945），任何足够大的轨迹扰动都可能翻它——而 move-golden 要的正是「足够大的轨迹扰动」。**「golden 要移动」与「#40 要 12/12」在余量=1 时正面冲突。**

## 六、软不变量 CI 结果（full ci.sh，flag ON）

`analysis/e5a/ci_full_WITH.log`：**S0 FAIL**（#40 10/12 软门破 + 金标 36 处破）。brief 点名要 verify 的软不变量在 S0 seeds 1-12 的表现（首违只报 #40，其余软不变量该批次**未出现在 fail 列表**⇒ 各自 ≥11/12 门内）：#5/#16（谣言/声誉扩散）、#2/#3（社交/孤立）、#26（派系亲和）均未破软门；**唯一破的软门是 #40**（+ 金标，预期）。硬不变量 **12/12 全绿**、det 3/3、活性过。（4a 宏观池门等后续步骤见 log 尾；S0 已定性 STOP。）

## 七、体感的不对称（feel note）

抑制 ③④ 后，**工业/treat 货的产者在下行时“无后果”**：糕点断了，糕点师（coco）不再被埋怨、声誉不被挫、镇上不传「coco 那边跟不上」。生存货（口粮/柴薪/屋瓦/整洁）断了照旧走完整 ③④——**只有工业货的失败被静音**。这在叙事上是一种刻意的不对称（「点心断了是小事、口粮断了是大事」），但它也意味着：糕点师这个岗位**在社会面只剩上行没有下行**（craft_credit 正镜像仍在、shortage 负镜像被拆），per-run 的声誉投放从「有正有负」变成「只正」。若 Baton 2/后续要用这条门，要接受这个体感代价（或只对**非生存**工业货开、且承认它让那些岗位的声誉单边化）。

## 八、诚实边界

- **③④-carry-dilution 是 code-reasoned，anchor 才是判决**：docs/170 的「稀释全在③④」结论 + 本片 cut-point 是代码推理（off-gate 逐字节证代码干净、golden 可归因移动坐实 ③④ 喂决策），但「抑制糕点 ③④ 对核心的净效应」是**测量**——测出来是**偏负 + #40 破**，不是预测的中性。**anchor + #40 是判决，cut-point 推理不是。**
- 只 backend=null headless。跑了 #40（1-12）+ 核心锚（13-30）+ off-gate golden（1-12 det3）+ move-golden（1-12 det3）+ full ci.sh（flag ON）。**未做**：把 ③（SH 信念 gossip）与 ④（standing 挫伤）逐条 ablate（两者共用早退、未分离哪一条主导 −0.02 与 #40 波及）；未跑 N=16/24/60 核心锚；未跑真机/SLM/LOD。
- 口粮 n.s.（CI 跨 0）——严格说「偏负、非升」而非「显著稀释」；但 brief 的门是「≥ 中性/flat-or-up」，点估计偏负即**未过**，且 **#40 10/12 是独立的、非噪声的硬阻断**——即使对核心锚做最宽容解读（flat within noise），#40 一条就 STOP。
- **golden / modelpath / complement ledger 三锚均未重烘**——STOP 负结果、代码已回退、不触金标（同 E3c/E4b/E4c/E4d-B「不 land 代码」）。

## 九、finalize（STOP 版）：不 land 代码、docs-only

命中 brief 的 STOP 条款「核心非 flat/up → STOP/escalate」**且**硬约束「#40 12/12」已破：
1. **代码已回退**：`game/scripts/Sim.gd`（早退）+ `game/data/production.json`（糕点 flag）已 `git checkout` 回 committed（integration/batons）⇒ 工作树 game/ **零改动**、金标一致（off-gate 已自证逐字节，见 §二）。
2. **本片只 land**：`docs/171`（本文）+ `analysis/e5a/`（证据 + 只读脚本）。golden/modelpath/complement ledger 一律不动、HARD_IDS 不动。
3. **给协调者的判决**：Baton 1 的「隔离态证核心中性」**未达成**——机制干净（off-gate 逐字节、golden 可归因）但**不中性**（口粮偏负 + #40 10/12 重烘救不了）。**Baton 2（加饼干）不启动。** 需 escalate：cut-point 对、OUTCOME 预测错——缺货流言是混沌扰动源而非单调稀释杠杆，抑制它 calm 全镇反而撞 #40 绝迹臂。修正方向（都出 Baton 1 的行、动更深的机制）：把工业货 shortage 事件（①）与 #40 绝迹臂解耦（让静音货不计入 never_short 分母）、或对 ③④ 逐条 ablate 定位主导项、或换一个「不缺货又 gated」的第二件货标定缝（docs/170 §六：该缝很可能不存在）。

## 十、附：证据文件（analysis/e5a/）

- `offgate_golden.txt`：off-gate 自证——flag 缺席、代码在场 → **金标一致 12/12（含逐 tick 前缀链）· S0 GATE PASS · det 3/3**，seed1 逐字节回改前金标。
- `move_golden_WITH.txt`：flag ON → golden 36 处不符、12/12 硬全绿（可归因移动）。
- `scale_BASE_s1-30.log` / `scale_WITH_s1-30.log`：ScaleSupply 原始 stdout（两臂，N=12 agents=0，seeds 1-30 × 60 天）。
- `baseline_s1-30.jsonl` / `with_s1-30.jsonl`：extract 出的干净 jsonl（`[SCALE]` 行）。
- `core_anchor_13-30.txt`：核心留出锚——**口粮 −0.0197 偏负、五货全 n.s.、非 flat-or-up**。
- `inv40_1-12.txt`：#40 R1 绝迹臂逐 seed——**BASE 12/12 → WITH 10/12**、① 验证（糕点两臂皆缺货）。
- `ci_full_WITH.log`：full ci.sh（flag ON）——S0 FAIL（#40 10/12 + 金标 36 处）。
- `anchor.py`（核心锚，含 t-CI，CORE 常量可改）/ `inv40.py`（#40 绝迹臂逐 seed，含 ① 验证）/ `extract.py`（[SCALE]→jsonl）：只读分析脚本（UTF-8）。
- ⚠ 协调者在 committed 树跑全 CI 会复算金标一致 12/12（本 worktree 已自证，见 offgate_golden.txt）。
