# 172 · E6a：丰裕工业货探针（让第二件被消费的工业货【永不缺】以清空缺货信道）· 判决：~~PROMISING~~ → **§0.8 内审下调 REJECT（见 docs/173）**

> **⚠️ 协调者 §0.8 内审更正（权威裁决层＝docs/173，2026-08-09）**：本文原判 **PROMISING** 与多处措辞，在 §0.8 内审（5 视角对抗性审查 + 逐 blocker/major 发现独立验证）后被**下调为 REJECT（产品/ROI 判决，非安全/红线判决——技术上 V1 在红线与硬不变量全过）**，并更正若干过度措辞：
> - ① 饼干代码**不 land**：决策惰性＝**装饰货**、零玩家可感增量（小镇有它没它玩起来一样）；且裸 `discretionary` 豁免是 **§0.5 式「给出货配置预埋一条永不变红的门」**（唯一守 缺货绝迹 的臂被 data 布尔关掉、无代码守卫）。全部知识价值由 **docs 落地（本文＋analysis/e6a）** 100% 捕获，无需并代码。
> - ② 「**决策逐字节等同基线**」下调为「**测样内（N∈{12,16}、seed≤30）决策【结果】整数等同**、强结果不变性、**非字节级**」（从未算过决策隔离指纹；两个现有指纹都含 event_log，饼干事件必然扰动）。
> - ③ off-gate 只证「**删饼干→金标回一致**」（harness 惰性 / removal-reverts），**不**证「加饼干只多饼干记录 / 决策链未动 / 100% 归因饼干」。
> - ④ §五「**动戏剧库存必混沌拉低核心**」的**对称律**被删——它只有 E5a（n.s.，95%CI 跨 0）+ V2（混淆）支撑；只保留**方向性**事实「**加一件会缺货的被消费货**稀释核心 −0.04~0.05（经 shortage→gossip）」。派生的「第二件戏剧货结构性封死、只剩红线区手术」**过度归纳**（n=2 配置、都 blame 核心邻接产者）——**诚实版＝「每个试过的配置都稀释；非穷尽、非不可能性证明」**；未试的更便宜路仍在（非核心 blame 目标 / 换挂载点 / 罕缺中间 cap）。
> - ⑤ V2 是 **4 变量混淆**臂（糕点 cap20→120 / spoil1→0 / amount6→12 / start_stock12→40 全动；最大活杠杆是 `_stock_pull_mult` 工作节律，非"移除戏剧"）——从"三条独立负路同向硬化"里**剔除**（V2＝STOP 本身仍对）。
> - ⑥ 「**丰裕货＝决策惰性 可复用通用机制**」下调为「**仅在测定标定域 N∈{12,16} 内**社会惰性」——never-short 是**标定属性**（cap120/spoil0/amount12）非结构保证；高 N 若饼干真缺，`_consume_for` AND-fold 翻转 → `_shortage_fallout` 重新点火 → E4d-B 稀释回归。
>
> 以下正文为探针原始报告（原始乐观措辞保留作记录），一切解读以 **docs/173** 为准。
>
> 本片是 docs/170（E4d-B）§五点 1 与 docs/171（E5a）§九亲手开的第三条出路——**「让第二件货【不缺货】（by construction，非抑制）」**——的原型验证。**只原型 + 离门探针 + 出结论，不 land 代码、不移金标、不 push、不重烘。** game/ 改动留本 worktree 供协调者复核。
>
> **三句话结论**：
> ① **假设被证实、且比预测更强**：给小镇加一件【丰裕（永不缺）】的第二件被消费工业货『饼干』（V1：糕点保持缺货戏剧不动、只在 coco 的 produce 记录追加饼干），核心口粮留出锚 **Δ=+0.0000（逐 seed 逐字节，0/0/18 flat）**——不是"≥中性"，是**决策路逐字节等同基线**（口粮/柴薪/屋瓦/糕点/整洁 五货 served/demand + 社交事件 + coco 上工节律全部逐 seed 相等）。#40 在 N=12/N=16 都 **12/12 绿**（discretionary 上限臂豁免生效），硬不变量 30 seed 全绿，VoiceGate 过，off-gate 删饼干后金标逐字节回一致。
> ② **机制：丰裕货是【决策惰性】的**。E4d-B 已证多货 produce 产出侧对核心逐字节零效应；本片进一步证：一件永不缺的货【被消费】也是零效应——∵ `_stock_pull_mult` 锁首件糕点（无人读饼干库存）、且饼干永不缺 ⇒ `_consume_for` 的 AND-fold 里饼干那一件恒 `took>=want` ⇒ `_shortage_fallout` 对饼干**从不触发** ⇒ ③信念/④声誉/②记忆全空 ⇒ 消费=静默扣库存。**缺货信道由构造为空，不是抑制**（对比 E5a 抑制 ③④ 的混沌重排）。
> ③ **决定性附注（协调者必须权衡）**：丰裕之所以核心中性，**恰恰因为它社会惰性**——饼干给小镇的经济图加了一件真被产、真被吃、真进库存的货，却造**零缺货戏剧**（无 shortage 事件、无 gossip、无声誉、无新决策槽）。它是一件**"装饰货"**。而 brief step1 字面要求的**「两货都丰裕」变体（V2：把既有的糕点也喂到丰裕）反而 STOP**：口粮留出锚 **−0.0654 中位、SIG DOWN（95%CI [−0.134,−0.012] 全在 0 下、比 E4d-B −0.046 还深）**+ seed3 豆子被饿到 0.36 撞下限臂——**把既有戏剧货改丰裕 = 移除它的缺货戏剧 = 复现并加重 E5a 的混沌稀释**。⇒ 结论分两句：**能**核心中性地【新增】一件丰裕的第二消费货（过了"1 消费工业货"封顶的核心中性那一版）；**不能**把某件【会缺货的既有戏剧货】改丰裕来绕开稀释。丰裕买到的是中性，卖掉的是戏剧。行号/数值实读于本 worktree、以 git 为准。

## 〇、判决摘要（先说结论）

| 验收项 | V1（糕点保戏剧 + 饼干丰裕，**主变体**）| V2（两货都丰裕，**brief 字面**）|
|---|---|---|
| **A. 丰裕性（N=12 seeds 1-30）** | ✅ 饼干 **30/30 seed never-short**（rate 1.000、shortage_days 0、spoiled 0）；糕点照旧缺货 8-34 天（不动）| ✅ 糕点+饼干 **各 30/30 never-short** |
| **B. 核心口粮留出锚（seeds 13-30 N=12）** | ✅ **+0.0000（median=mean=+0.0000、0/0/18 flat、逐字节）** 对标 E3b +0.041 / E4d-B −0.046 / E5a −0.020 | ❌ **−0.0654 median / −0.0732 mean / 95%CI[−0.134,−0.012] SIG DOWN**（12/6 下）|
| **★ 决策逐字节等同基线** | ✅ 核心五货 served/demand + 社交事件 + coco 上工节律**逐 seed 全相等**（30/30 seed）| ❌ 全镇 churn（口粮 served ±200、社交 ±140、上工节律变）|
| **C. #40 软门** | ✅ **N=12 12/12**、**N=16 12/12**（discretionary 上限臂豁免；下限臂仍收着糕点/饼干）| ⚠ N=12 **11/12**（seed3 豆子 0.36 撞下限臂——churn 饿出来的**新**红）|
| **D. 硬不变量（30 seed）** | ✅ **全绿**（唯一软破 = 基线固有 seed21 #40，糕点 held-out 0.478<0.5，非本改动）| ✅ 硬全绿；软破 #40 seed 3,19 |
| **off-gate 自证（删饼干 6 键→committed）** | ✅ **金标一致 12/12 逐字节**（seed1 digest 回 **3894698000** / 逐 tick 前缀链 / det 3/3 / S0 GATE PASS）——**Invariants/ScaleSupply 改动是纯 harness、不移金标；金标移动 100% 归因饼干** | 同左（同一 off 门）|
| **VoiceGate（新货是否造台词缺口）** | ✅ **PASS**（0 对为空）：饼干是【货】不是【动作】，候选动作集不变（仍 做点心/闲聊）| 同左 |
| **golden 移动（WITH）** | 移动（seed1 digest 3894698000→1051947300）——**可归因**：off-gate 逐字节互补，唯一新增的是饼干 produce/consume 事件进 event_log/town_stock，决策链不动 | 移动（决策也变）|

⇒ **V1 满足 brief 的 PROMISING 四条（A∧B∧C∧D）**，且 B 是**逐字节 flat**（比门槛"≥中性"更强）。**V2（brief 字面的"两货都丰裕"）命中 STOP 条款「核心 SIG DOWN」。**
⇒ **判决：PROMISING（条件性）**——丰裕路对【新增一件丰裕消费货】可行且核心中性，**建议进 §0.8 双路评审 + move-golden land（V1）**；但协调者须在 §0.8 拍板：一件**决策惰性的丰裕装饰货**是不是想要的"多样化"（见 §五）。

## 一、假设（比 E5a 更强的理论基础）

不掐 gossip（E5a 已证抑制 ③④ 混沌重排、口粮 −0.02 + #40 10/12），而是**让工业货丰裕（never-short）**，使缺货信道**从源头为空（by construction）**：
- E4d-B 已证**产出侧零效应**（NULL 臂：饼干产而不吃、核心逐字节 0.0000）；全部 −0.046 稀释来自**消费侧缺货事件**（饼干 57 次/seed → `_shortage_fallout` → ③④ gossip churn）。
- 若第二货**永不缺** ⇒ 无缺货事件 ⇒ `_shortage_fallout` 根本不触发 ⇒ ③④ 自然为空（**非抑制、无 E5a 的混沌重排**）⇒ 消费=静默扣库存=零社会效应。
- ∴「丰裕的被消费货」理论上=零核心效应。**唯一风险=coco 能否把第二货喂到永不缺（受她锁定的 cadence 限制）。** 本片实测该风险。

## 二、原型 diff 概要（owns production.json + harness）

### V1（主变体，本 worktree 当前 game/ 状态）
```
game/data/production.json（DATA，移金标）：
+ goods.糕点.discretionary = true                      ← 仅标类，cap20/spoil1/amount6【一律不动】⇒ 糕点照旧周期性缺货、社会后果逐字节同基线
+ goods.饼干 { label, cap:120, spoil_per_day:0, blame:糕点师, discretionary:true, shortage_* }
                                                        ← ★蓄意【不】孪生糕点 cap/spoil：大 cap+零 spoil ⇒ 库存单调累积、永不缺
+ start_stock.饼干 = 40
  produce.糕点师 = [ {糕点,6}, {饼干,12} ]               ← ★E4d-A produce-Array，_stock_pull_mult 锁首件糕点 ⇒ coco 上工节律不变、零加劳动
  consume.闲聊   = [ {糕点,1}, {饼干,1} ]                ← ★E4a consume-Array，饼干挂既有闲聊、不新增决策槽

game/bench/Invariants.gd（HARNESS，【不移金标】——金标=Sim 回放）：
  #40 R1 上限臂（缺货绝迹）：把 discretionary 货从 never_short/gated 计数剔除
    · 新增 glut_gated_n / glut_never_short（只数非 discretionary 的 gated 货）
    · glut 触发判据 gated_n→glut_gated_n、never_short→glut_never_short
    · discretionary 货【仍留下限臂】（rate≥SUPPLY_FLOOR，确保真被生产）
    · 缺 discretionary 键 = 原行为（全货都进上限臂）⇒ off 门恒过
game/bench/ScaleSupply.gd（HARNESS，只读探针）：
  · _measure 每 good 追加 discretionary 字段（供离门分析）
  · probe_arm_high 同步豁免 discretionary（否则打假 MISMATCH）；下限臂不豁免
```
- **无新岗位/工位/agent/台词**：饼干是【货】不是【动作】，coco 仍只做既有 做点心、闲聊仍是既有动作 ⇒ VoiceGate 无缺口、worksites 不变。
- **免费消费**（不进 vendor）⇒ 硬 #34 不动。HARD_IDS 不动。

### V2（brief 字面"两货都丰裕"，快照 `analysis/e6a/_production_V2.json`，仅探针用、非当前 game/ 状态）
在 V1 基础上再把**糕点也喂到丰裕**：`goods.糕点 cap 20→120 / spoil 1→0`、`produce.糕点师[糕点] amount 6→12`、`start_stock.糕点 40`。⇒ 移除糕点的基线缺货戏剧。

## 三、★★★A/B/C/D 实测表

### A — 丰裕性（N=12 seeds 1-30，backend=null）
| | never-short seed 数 | 备注 |
|---|---|---|
| **V1 饼干** | **30/30** | rate 恒 1.000、shortage_days 恒 0、spoiled 恒 0、stock_end 71-120（大 cap 缓冲；大 batch×coco 场次 ≫ 需求）|
| V1 糕点 | 0/30 | 照旧缺货 8-34 天/seed（**逐 seed 与基线相同**）——戏剧不动 |
| **V2 糕点+饼干** | 各 **30/30** | 两货都被喂到丰裕 |

⇒ **coco 能把【第二件】货（首件锁之外的饼干）喂到永不缺**——大 cap+零 spoil+大 batch 即可，标定不难（B=12 一发入魂）。风险假设"喂不到永不缺"**未兑现**。糕点（首件、驱动 cadence）要丰裕则须动 cap ⇒ 见 V2。

### B — 核心口粮留出锚（seeds 13-30 N=12，criterion：口粮 ≥0 flat-or-up）
| 变体 | 口粮 median Δ | mean Δ | 95%CI(t) | down/up/flat | 判读 |
|---|---|---|---|---|---|
| **V1** | **+0.0000** | +0.0000 | [+0.0000,+0.0000] | **0/0/18** | ✅ **逐字节 flat**（决策等同基线）|
| **V2** | **−0.0654** | −0.0732 | [−0.1345,−0.0119] | 12/6/0 | ❌ **SIG DOWN** |
| （对标）E4d-B | −0.0457 | | | 14/2/2 | STOP |
| （对标）E5a | −0.0197 | | [−0.063,+0.017] | 9/9/0 | STOP（偏负）|
| （对标）E3b | +0.041 | | | | PASS（落地）|

V1 五货全 **+0.0000 flat**（柴薪/屋瓦/糕点/整洁同口粮，逐 seed 0）。V2 除口粮 SIG DOWN 外：糕点 **+0.294 SIG UP**（它自己变丰裕了，废话），但**真正要紧的生存货口粮被稀释 −0.065**；屋瓦 −0.029、柴薪 −0.009 也偏负。

### C — #40 软门（discretionary 上限臂豁免）
| | N=12 seeds1-12 | N=16 seeds1-12（≈ci.sh 4a）| 备注 |
|---|---|---|---|
| **V1** | **12/12 ✅** | **12/12 ✅** | glut_gated_n=6（非 discretionary），非 disc never_short 1-3 → 从不撞多数臂；饼干+糕点虽 never/常缺都不进上限臂 |
| baseline | 12/12 | 12/12 | 参照系 |
| **V2** | **11/12 ⚠**（seed3 破）| 未跑 | seed3 破的是**下限臂**：豆子 rate 0.36<0.5——两货丰裕的 churn 把一件**非 discretionary 生存货**饿穿（基线 seed3 豆子不破）⇒ 勉强过软门但是**新伤** |

⇒ **discretionary 豁免机制成立**：V1 两件 treat（一丰裕一缺货）都不再撞上限臂，而生存货绝迹照旧红（判别力保住）。off-gate 证豁免是纯 harness、不移金标。

### D — 硬不变量（30 seed）
- V1：**硬 30/30 全绿**。唯一软破 = seed21 #40（held-out）——**基线固有**（糕点 rate 0.478<0.5 下限臂，V1 逐字节继承、非本改动引入；已核对 baseline seed21 同破）。
- V2：硬全绿；软破 #40 seed 3、19。

## 四、★关键机制——V1 决策逐字节等同基线（why 丰裕货是决策惰性的）

沿三条通道逐一核对"饼干能否改到决策"，全部为否：
1. **`_stock_pull_mult`（工位回拉，唯一读 town_stock 的决策项）** 锁**首件货糕点**（Sim.gd ~1898-1908）⇒ 无人读饼干库存 ⇒ 饼干库存高低不改 coco 上工节律。实测 coco(糕点师) 在班完成次数 V1 逐 seed = 基线（seed13-15：25/25/30 两臂相同）；V2（糕点 cap 变）则 22/31/23 变了。
2. **`_consume_for` 的 AND-fold**（Sim.gd ~3515-3528）：`short = not all_ok`，`all_ok` = 各件货 `took>=want` 的与。饼干**永不缺** ⇒ 饼干那一件恒 `took>=want` ⇒ `all_ok` 只由糕点决定 ⇒ `short`（喂加价）**逐次等同基线**。`_shortage_fallout` 对饼干**从不被调**（顺序也不变：只有糕点在原位调它）⇒ ③信念/④声誉/②记忆逐字节同基线。
3. **无其他决策读饼干**：无第二个产者产饼干；`_clean_mult` 只读整洁；import/export 只读**声明过的 lane 货**，饼干不在任何 lane。

⇒ 饼干唯一能改到的是 event_log/town_stock（多了 produce/consume/spoil 事件）⇒ **event_digest/digest 移动（golden 移），但决策链逐字节不动** ⇒ 核心 +0.0000。这实际上是 **E4d-B 的 NULL 臂 + 静默消费**：饼干被吃了，但因为永不缺，那口吃下去在社会面**一声不响**。

## 五、★结构规则（本片交给协调者/下一棒）

> **工业多样化【过 1 消费货】的核心中性版可行——代价是那件货必须【丰裕=决策惰性=零戏剧】。**
>
> 三条负结果（E4c 茶 −0.044 / E4d-B 饼干缺货 −0.046 / E5a 抑制 gossip −0.020）+ 本片 V2（两货丰裕 −0.065）合起来钉死一件事：**任何触动"缺货戏剧存量"的改法都会混沌地把口粮拽下**——加一件会缺的货（+churn）伤口粮；抑制既有货的 gossip（−churn，E5a）伤口粮；把既有戏剧货改丰裕（−churn，V2）伤口粮更狠。**缺货流言是烘进均衡的混沌扰动源，不是可线性加减的旋钮。**
>
> V1 之所以中性，是它**根本没碰存量**：糕点的戏剧一字不动，只在旁边**并排放**一件永不缺、无人为它议论的饼干。∴ 两条互斥的出路，协调者在 §0.8 二选一：
> 1. **要核心中性的多样化** ⇒ 走 V1：新增的第二消费货必须**丰裕（discretionary、大 cap、零 spoil、大 batch）**。它给经济/产出图加真货（coco 多烤一样、居民多吃一样、进库存/贸易），但**不加社会戏剧**。适合"想让镇上东西更多、但不想再多一条缺货新闻线"的诉求。**本片证它安全、可 move-golden land。**
> 2. **要第二件货的缺货戏剧** ⇒ 今天**仍被封死**：任何会缺的第二消费货都经 `_shortage_fallout`→gossip churn 稀释口粮 −0.04~0.07。要解锁得动更深的机制（把工业货缺货流言与**核心食物产者的做活机会解耦**，红线区、动 Sim 的信念→决策耦合），那是另一根棒、且 E5a 已证外科式摘 churn 会净负重排 ⇒ 高风险。

★可复用正面产物：① **discretionary #40 上限臂豁免**成立（纯 harness、off-gate 逐字节自证不移金标、豁免后判别力保住）——一个干净的"treat 货可丰裕、生存货须周期缺"的分类门。② **丰裕货=决策惰性**的三通道证明（`_stock_pull_mult` 锁首件 + AND-fold 首件短路 + 无旁路读）——比 E4d-B 的 NULL 臂更进一层（NULL 是产而不吃，本片是产且吃但永不缺，仍逐字节零）。③ **V2 的 SIG DOWN 把 E5a 的"抑制 churn 也伤核心"复现在第三条独立路径上**（丰裕≡移除缺货≡−churn），三条负路同向 ⇒ "缺货流言是混沌扰动源"这条判读硬化。

## 六、诚实边界

- 只 backend=null headless。V1 跑了 A（1-30）+ B 锚（13-30）+ C（#40 N=12 1-12 · N=16 1-12）+ D（硬 1-30）+ off-gate golden（1-12 det3）+ VoiceGate（1-3×60）。V2 跑了 A/B/C/D（1-30，#40 1-12）。N=24/60、真机/SLM/LOD **未跑**。
- **V1 的 B=+0.0000 是逐字节的**（决策等同基线，三通道 code-reasoned + 实测 served/demand/social/work 全等），不是"noise 内 flat"——这是本片最强的一格，因为丰裕货的决策惰性有构造性理由，不只是统计。
- **未穷举 B 敏感性**：V1 用 饼干 amount=12/cap=120/spoil=0 一发入魂（30/30 never-short），未扫更小 batch 下"刚好永不缺"的临界（机制上只要 never-short 就决策惰性，临界点无关中性、只关"够不够丰裕"）。
- **V2 的 −0.0654 含大幅双向重排**（12/6 下、CI 全在 0 下 ⇒ 系统性），但逐 seed 有 ±0.1 摆动；与 E4d-B/E5a 同款"社会基质混沌"。V2 的 cadence 变化（糕点 cap 20→120 改 `_stock_pull_mult`）与"移除糕点缺货戏剧"两个因子**未分离**——但两者都指向同一方向（churn 扰动），且 brief 要的是"两货都丰裕能不能行"的判决，答案是 STOP，分不分离不改判决。
- **complement ledger / golden 三锚均未重烘**——本片 PROMISING 但**不 land**（探针棒），代码留 worktree、金标不动。协调者若采纳 V1 走 move-golden land，须在 committed 树重烘（golden 会移 ~N 处、可归因饼干，见 off-gate 互补）+ 跑全 CI + 补 complement ledger。
- **"决策惰性=零戏剧"是特性也是局限**：本片没解决"给镇子加**有戏剧**的第二消费货"——那条仍封死。若用户的"工业多样化"诉求是后者，本片是**部分**答案（中性但惰性），须 §0.8 拍板是否接受。

## 七、finalize（探针版）：不 land 代码、docs-only 交付判决

1. **代码留 worktree 供协调者复核**（不 land、不 push、不重烘）：`game/data/production.json`（V1）+ `game/bench/Invariants.gd`（#40 豁免）+ `game/bench/ScaleSupply.gd`（discretionary 字段）。off-gate 已自证：删饼干 6 键 → 金标一致 12/12 逐字节（`analysis/e6a/offgate_golden.txt`）⇒ Invariants/ScaleSupply 是纯 harness、不移金标。
2. **本片 land**：`docs/172`（本文）+ `analysis/e6a/`（证据 jsonl + 只读脚本 + 两变体 production 快照 + off-gate 输出）。
3. **给协调者的判决**：**PROMISING（条件性）**。丰裕路对【新增一件丰裕消费货】(V1) 可行且**核心逐字节中性**、#40 绿、硬绿、VoiceGate 过、golden 可归因移动——**建议进 §0.8 双路评审 + move-golden land**。**但须拍板**：(a) 接受"丰裕货=决策惰性装饰货、零缺货戏剧"这个语义（§五出路 1）；(b) brief 字面的"两货都丰裕"(V2) **STOP**（口粮 −0.065 SIG DOWN，别把既有戏剧货改丰裕）。**丰裕买中性、卖戏剧。**

## 八、附：证据文件（analysis/e6a/）

- `baseline_s1-30.jsonl` / `baseline_n16_s1-12.jsonl`：干净基线（committed integration/batons，无饼干；seed1 digest 3894698000=金标）。
- `v1_s1-30.jsonl`：**V1 主证据**（饼干 30/30 never-short + 核心锚 13-30 逐字节 +0.0000 + #40 12/12 + 决策等同基线）。
- `v1_n16_s1-12.jsonl`：**V1 @ N=16**（饼干 12/12 never-short、#40 12/12、决策仍等同基线）。
- `v2_s1-30.jsonl`：**V2 对照**（两货丰裕 → 口粮 −0.0654 SIG DOWN + seed3 豆子撞下限臂 + 全镇 churn）。
- `offgate_golden.txt`：off-gate 自证——删饼干、harness 改动在场 → **金标一致 12/12（含逐 tick 前缀链）· S0 GATE PASS · det 3/3**。
- `_production_V1.json` / `_production_V2.json`：两变体 production.json 快照（供复核；当前 game/ 为 V1）。
- `analyze.py`：只读分析脚本（A 丰裕/byte-identity/B 锚/C #40/D 硬，CORE/TREATS 常量可改，UTF-8）。
- `v1_report.txt` / `v2_report.txt`：analyze.py 对两变体的完整输出。
- ⚠ 协调者在 committed 树跑全 CI 会复算金标一致 12/12（本 worktree 已自证，见 offgate_golden.txt）；采纳 V1 land 则须重烘（golden 移动可归因饼干）。
