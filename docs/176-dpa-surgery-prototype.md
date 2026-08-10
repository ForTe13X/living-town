# 176 · DP-A 解耦手术原型 + 离门 probe · 判决：~~PROMISING~~ → **UN-LANDED（Codex 外审 4 P0 全证实 + committed-tree CI 红，2026-08-10）**

> **⚠️⚠️ 最终更正（2026-08-10，权威）**：DP-A move-golden 一度 land 进 integration/batons，但 push 前 committed-tree CI 红(DetGate 金标 scenarios 段陈旧) + Codex 外审判 REQUEST CHANGES、4 P0【逐条 file:line 复核全部证实】，故 **UN-LANDED**（reset 回 92accbe、代码/config 全撤）。**本文正文多处措辞 over-claim、以此更正为准**：
> - **① drama 声明【撤回】**：正文"饼干被议论 gossip ~51/seed / 满城议论 / 玩家可感"是【错指标】——probe_b.py:31 读的是 `social_by_type.gossip`＝【全主题】gossip，非饼干专属。**饼干专属转述 `bing_belief_relayed`＝0.11/seed（18 held-out 只 1 seed>0）**。饼干真实 drama 仅＝缺货 + ~11 一手 SH:饼干 信念(几乎不传开) + write-only grievance ghost(无 reader)。「带戏剧第二货/玩家可感」不成立。
> - **② E7 基线 buggy**：E7 消融的 ④ standing 通道建在 `standing - signf(standing)` 【翻号 bug】上（已在 c868aa2 独立修复：move_toward + 性质自检）。E7 只能说"关掉该 buggy 路径消除了某 supply-rate 差异"，非"语义正确声誉模型"。
> - **③ 核心中性【解耦】仍是真结果**（移走 ④ 写 ⇒ churn 停 ⇒ 核心 rate 恢复、逐 seed rate 平），但它是"良好隔离但戏剧薄"的 decouple，不是"首个带戏剧第二货"。与 GPT-5 Pro 外审 finding#4(grievance ghost-ish)收敛。
> - 以下正文（含 §八 GPT-5 Pro 外审、§九 M1+M3 硬化）保留作过程记录，但**一切结论以本横幅 + 记忆 project-economy-trade-loop 的 Codex-P0 更正为准**。评审要求：先修证据/门系统(#44-46 fail-closed、standing[已修]、E7 提交化)，再谈任何 DP-A land。

> 本片是 docs/174（E7 判决性测量）§五授权的 **Phase 1 · DP-A 原型**。E7 已判死："第二件被消费工业货缺货稀释核心口粮的 leak【全在 ④声誉挫伤】(`_adjust_standing`@Sim.gd → `_acceptance_margin`@3913 的涌现放逐)、③信念/gossip 零贡献、DP-B(换 blame 目标) 是搬家非解耦"。本片按那张精确切点图做 **DP-A 手术**：把【工业/comfort 货】缺货的 ④standing 挫伤【改道】进一个【自含 grievance 字段】(而非删)，让第二工业货饼干【缺货且被议论、后果被看见】而【不稀释核心生存货】。**原型 + 离门 probe，不 land、不移金标、不 push、不重烘。** 代码留本 worktree 供协调者 §0.8 复核。

## 〇、一句话
**DP-A 成立、全 A–E 过——这是整条 E3b→E7 弧上【第一次】做到【带戏剧的第二被消费工业货 + 核心中性】。** 把工业货缺货的 ④声誉挫伤【改道】进自含 grievance 字段（不被任何决策读）后：核心口粮 held-out **Δ=−0.0001（16/18 平、paired +0.0479 SIG UP 完全恢复）**；饼干【真缺货】（rate 0.71、缺货 52.6 事件/seed）、【被议论】（SH:饼干 ~11 具名信念持有者、gossip 51/seed，玩家经 inspect 面板可见）；off-gate 金标逐字节（门关 S0 GATE PASS、golden 12/12）；#40 软 12/12@N12 + 12/12@N16-4a；硬不变量 30 seed 零红。**⚠️§0.8 内审更正（见 §八）**：玩家可感戏剧只由 ①②③（饼干具名信念+shortage 记忆+gossip）背书；**B3『grievance 被写 11.07』下调为『改道管线已触发』的自检、【非】戏剧门/交付价值**（grievance 是纯只写字段、出货路零读者）。且诚实记：DP-A 把饼干的 standing 驱动【被动】戏剧（名牌 %±、conflict 反馈行、gossip_rep 点名、grudge 弧）与 leak【一同】交易掉了（同一 standing→_acceptance_margin 机制）——饼干残留可感戏剧＝inspect 面板那薄条。⇒ **§0.8 内审 SOUND_WITH_FIXES：修 3 前置（守卫/头衔/高 N）→ 外审 → move-golden land。**

## 一、设计（E7 §四授权的确切 scope，已内化 docs/174/173/170，未重探已定的东西）

**问题**（E7/E4d-B 证）：任何第二件【会缺货】的被消费工业货，其缺货经 `_shortage_fallout` 的 ④ 声誉挫伤——`_adjust_standing(seer, blame, -0.2)` 写 `standing`，而 `standing` 是 `_acceptance_margin`@3913 里 `st = standing*STANDING_K` 的一项，进每种社交接受和式 → 涌现放逐 → churn 决策/RNG 织物 → 翻食物产者 argmax → 口粮 held-out −0.046。E7 单切 ④ ⇒ 口粮回 −0.0001（16/18 平）；单切 ③（SH 信念/gossip）零恢复 ⇒ ③对核心零 leak，可放心保留作戏剧。

**DP-A 手术**：per-good 数据门 `grievance_reroute`，**只对带该键的货**把 ④ 这一面【改道】——不再写决策会读的 `standing`，改写进关系账本上一个【自含 `grievance` 字段】。该字段：
- **绝不 `*STANDING_K`**、**不进 `_acceptance_margin`(3913)** 的社交接受和式；
- **不进 `bad_targets`(2130)** 的坏名声预算、**不进 `gossip_rep`(2205) 阈**；
- **不进夜间衰减(1648)**（那条只读 `resentment`/`standing`）、**不进 digest**（`Invariants.digest` 只哈希 `event_log`，见下）；
- 即**不被任何决策读**，只留给 Story/编年史/语音读作 drama grounding（"这个产者让我为这件货缺过多少次货"）。

**保 ①②③ 戏剧**：饼干仍缺货、shortage 事件①照 `_log_event`(喂 #40)、当事人不满记忆②照记、SH:饼干 信念③照写照传 gossip。**只把④"产者被涌现放逐"这一面改道**。无需 DP-D（③本不 leak，docs/174 证）。

**只对第二/工业货生效、good-typed 数据门、默认关**：缺 `grievance_reroute` 键 → 原路 `_adjust_standing`（逐字节 no-op）。**糕点不加此键**（保既有 ④→standing 行为不变；不动既有货的通道——docs/174 §三.4 E5a vs arm3 教训）。

## 二、diff 概要（代码留 worktree，仅 3 处，25 行 Sim.gd + 27 行只读 bench）

**`game/scripts/Sim.gd`**（+25 −1）：
1. `const GRIEVANCE_CAP := 3.0`（第 149，镜像 STANDING_CAP 量级）。
2. `_shortage_fallout`（~3577）：在 `for s in seers` 循环前读门键 `reroute := bool(gd.get("grievance_reroute", false))` 与 `sstd`；循环内把原 `_adjust_standing(s, blame, sstd)` 分叉为 `if reroute: _add_grievance(s, blame, sstd) else: _adjust_standing(s, blame, sstd)`。信念形成③那两行不动。缺键 → else 分支 = 逐字节原路。
3. 新增 `_add_grievance(observer, target_id, delta)`（~4500，紧邻 `_adjust_standing`）：`r["grievance"] = minf(float(r.get("grievance",0.0)) + absf(delta), GRIEVANCE_CAP)`。

**`game/bench/ScaleSupply.gd`**（+27，纯只读纯追加 probe B 读数）：run 后遍历 agents 汇总 `grievance_total`/`grievance_rels`（④改道被写）与 `bing_belief_holders`/`_seen`/`_relayed`（③ SH:饼干 信念形成/传开）。不 mutate S、不进 digest、不进 ci.sh、不动金标。

**`game/data/production.json`**：**工作树保持 committed（无饼干）**。饼干配置只落 `analysis/dpa/prod/{with,dpa}.json`（探针加载用），跑完即 `cp clean.json` 还原。dpa.json = with.json（饼干镜像糕点：cap20/spoil1/produce[糕点师]=[{糕点,6},{饼干,6}]/consume[闲聊]=[{糕点,1},{饼干,1}]/blame=糕点师/shortage_memo·claim·standing 齐）**+ `goods.饼干.grievance_reroute=true`**。

## 三、grievance 字段语义

- **落点**：`_rel(seer, blame)["grievance"]`，float ≥ 0，键缺省不存在（`_rel` 默认 dict 不含它，`.get(...,0.0)` 兜底）。改道复用与原 ④ **完全相同的 (seer→blame) 关系拓扑**——`_adjust_standing` 本就 `_rel(seer,blame)`，故改道不新建/不改关系图，只换写哪个字段。
- **更新**：每次该货 shortage fallout，对每个 seer `grievance += |shortage_standing|`（=|−0.2|=0.2），封顶 `GRIEVANCE_CAP=3.0`。
- **单调累积（刻意不复用 `_adjust_standing` 的翻号漂移）**：`_adjust_standing`@4497-4498 用每-tick 共享累加器 `_st_delta` + ± 混写 + 对称 cap——craft_credit(+) 与 shortage(−) 同键混写时，tick 内写入序影响钳制结果（docs/173 open_q 的"翻号漂移"）。grievance 改用 `min(Σ|delta|, CAP)`：只增不减、无共享累加器、与写入序无关 → 无新混沌、纯确定、且【只写不读】故结构上不可能反哺决策。
- **衰减**：本原型**不衰减**（怨气累计"总账"）。温和衰减（挂 1648 夜间循环，`grievance = maxf(0, grievance - GRIEVANCE_DECAY)`，仍只写不读）是 Phase-2 备选——为最大化可审计性、把改道压到单一写点，原型选最保守的单调累积。
- **读者**：目前仅 bench probe（只读汇总）。Phase-2 接 Story/observation-console/语音（"糕点师最近老让人扑空，饼干罐总空着"），成本低、字段已存在且被写（probe B 证 grievance_total>0），留 UI 接线为 Phase-2。

## 四、A–E 离门 probe（held-out 13-30、N=12、backend=null headless、seed≤30；脚本 `analysis/dpa/`，复用 e7 anchor/inv40/offgate 形状）

| probe | 内容 | 结果 | 判 |
|---|---|---|---|
| **A 核心中性** | DP-A vs CLEAN 口粮 held-out Δ | **−0.0001 mean / +0.0000 median（1/1/16 平、CI[−0.005,+0.005]）**；paired vs WITH **+0.0479 SIG UP[+0.016,+0.080]**；柴薪/屋瓦/糕点/整洁 全恢复到平 | **PASS** |
| —sanity | WITH vs CLEAN 应复现稀释 | 口粮 **−0.0480 SIG DOWN**（14/2/2）✓ 复现 E4d-B/E7 | ✓ |
| **B 戏剧保留** | 饼干真缺+被议论+grievance 被写 | B1 真缺货 18/18（rate 0.71、缺货事件 52.6/seed、缺货天 20.6）；B2 ③SH:饼干信念 18/18（~11 持有者、gossip 51/seed）；B3 ④grievance 被写 18/18（total 11.07）| **PASS 18/18/18** |
| **C determinism** | 门关（committed 无饼干）跑改后 Sim.gd | **S0 GATE PASS**、金标 12/12 逐字节（seed1 digest 3894698000=committed）、det 3/3 | **PASS** |
| **D #40 共存** | 饼干缺货是否 replay-safe 进 #40 | 软门 WITH 12/12@N12（=BASE）；①糕点 shortage_days 从不 0（无掉事件 bug）；**N=16 4a 12/12**；30 seed inv40_ok 29/30（1 软偏差、held-out、非硬红）| **PASS** |
| **E 硬不变量** | DP-A 30 seed | 硬红 union=[]（零红）；watch #01/#34/#35/#38/#39 零红；软 union=[40]（预期软方差）| **PASS** |

**要点**：饼干 shorts【很凶】（52.6 事件/seed、20.6 缺天）却核心【逐 seed 平】——戏剧与中性【同时】达成。对比：E6a 装饰货饼干永不缺、零戏剧、byte-identical=空心；DP-A 饼干凶缺、满城议论、却因 ④ 改道离开决策路而不拽核心。

## 五、判决与下一步

**判决＝PROMISING（全 A–E 过）。** DP-A 是 E7 精确切点图的干净实现：改道 ④（非删③④=E5a 混沌、非丰裕=E6a 装饰、非换 blame=DP-B 搬家），核心中性且戏剧保留、determinism 门关自证、#40/硬全绿。这【破了】工业多样化封顶——第二个【玩家可感】的被消费工业货成立。

**下一步（协调者）**：
1. **§0.8 双路评审**（core-invariant caliber 变更须双路收敛）：内审多-critic workflow（对抗性验：grievance 是否【真】决策不可达？drama 是否【真】玩家可感 vs 只在数据层？单调累积语义/cap 是否有边界 bug？改道是否漏任何 ④ 次级读点 2130/2205？红线/硬门？）+ 外审 GPT-5 Pro told to REFUTE。
2. 收敛后 **move-golden finalize**：饼干落 game/data/production.json（+grievance_reroute）、committed 树重烘三锚（golden+modelpath+complement ledger via gate_fixture_audit --run --bake-ledger）、跑完整 CI、HARD_IDS 无涉（grievance 不加不变量）、VoiceGate（饼干是货非动作、+shortage_claim 已备）。
3. Phase 2：grievance 接 Story/observation-console/语音（drama 上屏）；再层 Anno per-class 满足条（见 docs/175）。

**这直接落地 [[docs/175]] 的 big-Other 分层 + Anno consequence-on-consumer**：缺货后果落自含层（grievance→Phase2 消费者情绪/语音）、绝不 churn 生存产者决策。DP-A 是整个 needs-满足度系统的【地基 enabler】。

## 六、诚实边界

- 只 backend=null headless、N=12（+ N=16 4a seeds 1-12）、seed≤30、60 天；未跑真机/SLM/LOD/N≥24。
- DP-A 只改道 ④ 的【第二/工业货】面；既有糕点的 ④→standing 一字未动（保既有涌现放逐核心戏剧）。
- grievance 尚未接 UI（Story/语音）——probe B 只证字段【存在且被写 + ③信念仍形成/传开】，"玩家可感"的 UI 呈现留 Phase 2。
- complement ledger / golden 三锚 **未重烘**——本片是原型 + 离门 probe，工作树 game/data 无改动（饼干只在 analysis/ 配置），Sim.gd 改是默认关的纯门控（probe C 自证）。协调者 §0.8 复核后若 land，才走 move-golden 重烘。

## 七、附：证据文件（analysis/dpa/）

- `prod/{clean,with,dpa}.json`：CLEAN（=committed）/ WITH（饼干③④原样）/ DP-A（+grievance_reroute）三配置。
- `runs/{clean,with,dpa}.jsonl`：N=12 seeds 1-30 主证据。`runs/dpa_n16.jsonl`：N=16 4a。`runs/offgate_golden.txt`：probe C 金标门。
- `anchor.py`/`attribute.py`/`inv40.py`/`offgate.py`（复用 e7）+ `probe_b.py`/`hardinv.py`（新）：只读分析脚本（UTF-8）。
- `run_all.sh`：一次跑完全部 arm + 门 + 分析（不 background-then-exit）。`RESULTS.txt`：全部 probe 输出。

## 八、§0.8 内审裁决（14-agent，5 视角对抗 + 逐发现验证）· **SOUND_WITH_FIXES**

**科学轴＝真突破，不虚报**：核心安全声称「grievance 决策/RNG/digest【真】不可达」经 5 独立对抗审 + 独立验证 + 综合者亲自 grep/追源后仍站住——唯一写者 `_add_grievance`(Sim.gd:4509，仅 reroute 分支调)、唯一 game/ 读者是只读 bench probe(ScaleSupply.gd:178)、每个决策读点(_acceptance_margin 3925/bad_targets 2131/gossip_rep 2209/夜衰 1650)按名读固定键从不触 grievance、digest/chain_step 不序列化 relationships、HARD_IDS 干净。**这【不是】E6a**（E6a 永不缺=byte-identical=零戏剧被 REJECT；DP-A 是相反极：饼干凶缺+满城 gossip+具名信念+记忆在 inspect 面板呈现）。「带戏剧第二被消费工业货 + 核心中性」是 E3b→E7 弧真·第一次。**别为怀疑否定这个干净正结果。**

**但现在【不能 land】——3 条 land 前置（都非致命、原型与 A–E 探针本身干净）**：
1. **【BLOCKER·守卫】** `grievance_reroute` 是裸 `gd.get` per-good 布尔、**无 survival-good 守卫**（全树无白/黑名单）。标到生存货（口粮/柴薪/…）即【静默】删该产者的 ④→涌现放逐社会戏剧而【无任何门变红】（shortage 事件在分叉上游照记⇒#40 恒绿且不在 HARD_IDS；#15 放逐是 DIAG 永不成门；grievance 被 digest 排除）——正是 docs/173 §四.3 判过的「硬前置、不可软化」§0.5 反模式。**修＝fail-closed 白名单**：Sim.gd 加 `REROUTE_ELIGIBLE` 常量（comfort/attach 货，如糕点/饼干），`reroute := bool(gd.get(...)) and (good in REROUTE_ELIGIBLE)`——误标生存货静默回 standing 原路、新增货默认受保护。**必须先于/同于 config 进 committed 树+重烘 land**。（不违反 [[feedback-freeze-gates-drift-recurs]]：是把【已存在的数据门】收窄成 fail-closed、非新造投机门。）重形式（Invariants HARD 判红 + gate_fixture_audit 双枚举）＝可选纵深。
2. **【头衔·诚实】** B3『grievance 被写』从「戏剧门」降为「改道管线已触发」自检——grievance 纯只写、出货路零读者、**不计入交付价值**（否则＝verified→gated 升格，撞 [[feedback-relay-turns-observation-into-mechanism]]）。玩家可感只由 ①②③ 背书。且须记：DP-A 把饼干的 standing 驱动【被动】戏剧（名牌/conflict 行/gossip_rep 点名/grudge 弧）与 leak【一同】交易掉（同机制）——已在 §〇/§六 更正。（grievance→Story 合理留 Phase 2，不需先接 UI。）
3. **【高 N·标度】✅ 已 gate（definitive）**：协调者跑了 **N=24/48/60 核心中性 sweep（clean/with/dpa、held-out 13-30）**——DP-A 核心口粮 Δ＝**+0.0000 逐 seed 字节平（0/0/18）@ N=24、N=48、N=60**（全 5 核心货全平），且饼干在各 N【真凶缺】（如 N=24 seed13 缺货 38 事件）——即饼干在场且凶缺、核心却逐字节等同 CLEAN。对照 WITH 在高 N 仍稀释（N=48 口粮 mean −0.024、|dn| 0.198 混沌）。⇒ ③gossip 6.5× 高 N 回归担忧【实测证伪】，「破封顶」是 **scale-general（N=12→60 全范围）** 非 N=12 标定假象。（证据 analysis/dpa/runs_hiN + RESULTS_hiN*.txt。）

**minor**：Sim.gd:4505 确定性注释理由写错（浮点加法非结合、`min(Σ|δ|,CAP)` 序无关只因单货 δ=0.2 恒定才成立；真保证＝确定性重放同写序 + grievance 被 digest 排除）——改注释即可、非阻塞。

**路径**：修守卫 + 改头衔（本片已改）+ 补高 N（或 scope）→ **外审 GPT-5 Pro told to REFUTE**（重点盯高 N 回归 + 守卫设计 + grievance 不可达是否结构性）→ **move-golden**（守卫+饼干 config 同 land、三锚重烘、全 CI、若加 HARD 守卫则 HARD_IDS 双处同步、VoiceGate）。**别为凑 land 软化守卫，也别为怀疑否定正结果。**
