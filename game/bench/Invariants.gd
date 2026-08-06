extends RefCounted
class_name BenchInvariants
## preload 而非全局类名/autoload：--script 的 _init() 阶段 autoload 尚未挂上（docs/41 §2 更正：autoload 其实是加载的）（同 Sim.gd 顶部的纪律）。
## 只用它的【静态】哈希（fnv1a32/mix32）——不实例化、不持有状态。
const SimScript = preload("res://scripts/Sim.gd")
## bench/Invariants.gd — 把「确定性社交底座」的机检不变量抽成单一真相源（语义照搬 sim_soak.gd / sim_social_port.mjs）。
## 条数：**43**（V1 加了 #41、Z1 加了 #42、AA3 加了 #43）。
##   数法：`grep -o "_chk([0-9][0-9]*" game/bench/Invariants.gd | sort -u | wc -l` → **43**（已现跑核过）。
##   ⚠ 原文写的是「`grep -c` 即得」——**那个配方自己是错的，off-by-one**：本行注释里就含有
##   `R.append(_chk(` 这个字面串，`grep -c` 会把**这一行文档**也数进去（HEAD 上 `grep -c`=41 而 id 只有 40）。
##   一条"怎么数"的说明把自己数了进去，这正是它想防的那种过期方式的另一个版本。
##   ⚠ **AA3 又发现修出来的那个配方也不对**：`R\.append(_chk(` 抓不到 **#42**
##   （它由 `_survival_pull_narrowing()` 返回、`_chk(42,…)` 写在那个函数里面），
##   而它同时**照旧**把上面这一行文档数进去 —— 两个 off-by-one 恰好抵消，于是"43"这个数是**碰巧对的**。
##   去掉 `R\.append` 前缀、并要求**至少一位数字**（`[0-9][0-9]*`）之后两边都不再靠巧合：
##   命中 1..43 全部 43 条；本段文档里那几处 `_chk(` 要么不带数字被过滤掉、要么写的是已存在的 `_chk(42`，
##   `sort -u` 自动合并。**这是本棒现跑核过的，不是推断。**
##   ⚠ 这里原先写死的是"20 条"，下面 split_fails 的注释写死的是"33 条"——**两个都过期了**，
##   而它们过期的方式一模一样：条数是长出来的，而写死的数字不会跟着长（H5 修，2026-07-30）。
##   ⇒ 以后要加条数就别再写死；本行给的是【怎么数】而不是数出来的那个值。
## check_all(S, starved) → [{id:int, name:String, ok:bool, detail:String}]，供 bench Harness 跨 seed 网格与 soak 共用。
## 注：现为「终态断言」（跑完整局后评估），非逐 tick；首违 tick 粒度留作后续细化。

## #40 的供给充足度阈值。**三个数都是量出来的，不是拍的**（12 seed × 60 天 × 6 货 = 72 格，
## 隔离副本探针；留出种子 13-30 复核）。改它之前先把 docs/41 §2.5 的包络重跑一遍。
##  · SUPPLY_FLOOR：满足率 = 到手件数 / 想要件数。**选阈值只用 seeds 1-12，13-30 留出复核**：
##      基线 seeds 1-12  逐 seed 最差货：最低 0.615；72 个（货×seed）格里最低也是 0.615。
##      基线 seeds 13-30（留出）        ：最低 0.569 / 次低 0.579 —— **比选阈值那组更低，所以以它为准**。
##      六个「掐产量但不归零」的变异体：被掐那种货 0.069-0.415（1-12）、最高 0.488（thr_book seeds 13-30）。
##    ⇒ 分界带 [0.488, 0.569]，取 **0.50**（上 1.14× / 下 1.02× —— 下方这一格窄，如实写在这里）。
##    ⚠ ~~真正的余量比上面这两个数大，因为门是【逐 seed 通过率】制：要假红得【两个】seed 同时跌破，
##      而 30 个基线 seed 里跌破的个数是 **0**；反过来 thr_book/thr_bean 是 30/30 个 seed 全跌破。~~
##    ⚠ **2026-08-01 S1 实测：上面这段删除线里的每一个数今天都不成立了**（60 个 seed × 60 天，
##      未改动的合并树，`analysis/s1/*.jsonl`）。逐 seed 最差货满足率的实测展布：
##        seeds 1-12 （**CI 第 4 步跑的、也是当初选阈值用的那一组**）0.592 .. 0.797，跌破 0.50 的个数 **0**
##        seeds 13-30（留出）                                        0.419 .. 0.887，跌破 **1**（seed 18 = 0.419 口粮）
##        seeds 31-60（S1 新抽的 30 个，从没有人跑过）                  0.369 .. 0.855，跌破 **4**（36/40/50/58）
##      ⇒ **跌破率不是 0，是 5/60；只算没被用来选阈值的那 48 个是 5/48 = 10.4%（Wilson95% [4.5%, 22.2%]）。**
##      ⇒ 门是逐 seed 通过率制（软门容 1/12）⇒ 按 p=0.104 算，**一个随机 12-seed 网格破软门的概率约 36%**。
##      **这不是推算：实测 `--seeds 49-60`（同一棵未改动的树、同一条命令）读到的判决行逐字是**
##        `=== S0 GATE: FAIL ❌  (硬不变量 seed 12/12 全绿, 软通过率门 ≥11/12(90%) 破, 活性 过, 金标 过, det 1/1) ===`
##        `❌ #40 [软]产出闭环活性与供给充足 10/12  首违 seed 50: …口粮 满足率=0.41(到手429/想要1034，断供40/60天)`
##      ⇒ **seed 18 不是特例，是分布的左尾**；CI 的 seeds 1-12 恰好一个都没抽到。
##      ⚠ 第二格（`tools/ci.sh` 4a，N=16）同样只跑调参段 seeds 1-12。S1 在 N=16 上补跑了留出 13-30：
##        最差货 **0.425 .. 0.894**、跌破 **1/18**（seed 26 = 0.425 **豆子**，不是口粮）
##        ⇒ **留出段余量 −0.075**（R1 记的 N=16 seeds 1-12 余量是 +0.056）。
##        不过 4a 那一格**没有**出现"连续 12 个里红两个"（13-24 红 0、19-30 红 1）⇒ 今天没被这条打到。
##      ⇒ **下一个动标定的棒：12 个 seed 的网格没有分辨这条判据的统计功效。** 判"改好了没有"至少要 48 个 seed，
##        否则你量到的一半是抽样噪声（S1 自己就靠 12→60 才看见这件事）。根因见下面 ③ 那一段的 S1 补注。
##    ⚠ 它是【软】判据：Harness 的软门允许 12 个 seed 里反转 1 个，这一格容差是刻意留着的。
##  · SUPPLY_MIN_DEMAND：需求件数低于此值就不谈满足率——短 horizon / 定向场景里一件货可能只被想要过
##    两三次，那时候的比率是噪声不是性质（同 #29 的 `aid_accepted < 8` 守护）。
##  · SUPPLY_MIN_DAYS：**这条臂需要时间才成立，短跑上它是一条假红**（口径同 Harness.LIVENESS_GATED 的
##    "值 = 该类被门控所需的最短天数"，那里也是实测出来的）。满足率是【全程累计比】，而开局库存被产能顶起来
##    之前的那段亏空会一直摊在分母里。**实测同一棵未改动的树**（seeds 1-12，逐 seed 最差货满足率的最小值）：
##      days=30 → 0.321   days=40 → 0.490   days=50 → 0.577   days=60 → 0.615
##    days=30 时 12 个 seed 里有 3 个跌破 0.50 ⇒ **软门当场破**（ci.sh 文件头写着 `CI_DAYS=30` 是支持的快跑）。
##    days=50 在留出种子 13-30 上只剩 17/18（seed 22 = 0.495），**恰好压在软门线上、余量为零**。
##    ⇒ 定 60。低于它这条臂整个不生效（DetGate 的 20 天、快跑的 30 天都在此列，且它们本就不门控软不变量）。
const SUPPLY_FLOOR := 0.5
const SUPPLY_MIN_DEMAND := 20
const SUPPLY_MIN_DAYS := 60

## #1 的名字。**2026-07-30（J1）由「无饿穿」改成本行**，理由是量出来的，记在这里而不是提交信息里，
## 因为下一个读这一条的人手边只有这个文件。
##
## 判据一个字节没改（`starved == 0 or not harmony`），改的只有名字。
## 喂给本函数的 `starved` 是 **Σ over (agent, tick, need) of [need ≤ 0.5]**（Harness.gd `_run_once`，
## 另有 7 份逐字复制，见下），数的是**任何一条需求触底**，而名字只写了五条需求里的一条。
##
## ⚠ **不是"漂移"，是【生来就不符】**（docs/41 §1.5①：grep 给现状，`git log -S` 给意图）：
##   `git log -S "无饿穿"`、`git log -S 'starved == 0 or not harmony'`、
##   `git log -S 'for nid in ag["needs"]'` **三条都只回一个 commit** —— `ebac5a3`（2026-07-03，
##   首个公开快照）。名字与宽判据是**同一次提交里一起进来的**，此后 27 天谁都没动过。
##   ⇒ 派棒的 brief 写的"只是叫错了 15 天"**偏短了**：正确的说法是"**从来没对过**"。
##   这一条比天数重要：没有"哪一次改动把它改窄/改宽了"可查，所以**不存在一个曾经正确的版本可以回退**。
##
## ⚠ 为什么不是反过来改代码（"只数 hunger"）——**这是量过的，不是选的**。
## docs/54 §五 报的是"72 格里 3 格红、3/3 都是 social、没有一格是 hunger"，读起来像"hunger 那半是死码"。
## 把网格铺开之后不成立（J1，**114 次运行** / 5 种 need / 6 个配置域，逐次实测；hygiene 一次都没触底）：
##
##   配置域                                       运行数  红   hunger  social  energy  fun
##   backend=null，N∈{12,16,20,24,30,60}，60 天      72    3       0     177       0    0
##   backend=null，N=30，120 天                      12    1       0      81       0    0
##   backend=null，N=60，60 天，激进 LOD               6    0       0       0       0    0
##   backend=random(full)，N=12，60 天（出货配置）      8    1      11       0       0    0
##   backend=random(full)，N=30，60 天                 8    3      50     296       0    4
##   backend=random(full)，N=12，8 天，survival_veto=0  8    8     506     133      32    0
##   合计                                          114   16     567     687      32    4
##
## ⇒ **hunger 与 social 的触底实例数是同一量级**（567 : 687），只是各自住在不同的配置域里：
##   零模型地板（`backend=null`）上 100% 是 social；**模型路上 hunger 反而是主项**。
##   docs/41 §2 的第一个盲区（`backend=null` ⇒ `decide()` 根本不进）正好把 hunger 那一半藏在了统计外面
##   ——I3 的网格整个跑在零模型地板上，于是"全是 social"是**采样的性质，不是系统的性质**。
##   `backend=random` + `survival_veto_line=0`（= B14 的 `_survival_ok` 落地之前那棵树）逐字复现了
##   docs/38 §五 记的 `random` 8/8 饿穿，而**那 8 个 seed 的 75.4% 是 hunger** —— 名字所指的那件事，
##   真的会发生，只是不在零模型地板上。
##
## 四格负对照（**判决由本函数自己给出**，不是纸上推演）：
##   世界 H（只有 hunger 触底：random+veto=0，N=12，seed 4 / seed 6，8 天）
##   世界 S（只有 social 触底：null，N=24，seed 3，60 天）
##     | 世界 | 现判据（任一 need） | 「只数 hunger」的判据 |
##     | H(s4)| ❌ 红 starved=39   | ❌ 红 39            |
##     | H(s6)| ❌ 红 starved=59   | ❌ 红 59            |
##     | S    | ❌ 红 starved=35   | ✅ **绿 0** ← 收窄的代价就是这一格 |
##   ⇒ 收窄成"只数 hunger"会让 **S0 网格上今天仅有的 3 格红全部转绿**，且不给 social 留任何门。
##      收窄不是"把名字兑现"，是**净减一半判别力**。名字改起来是零成本的，判别力不是。
##
## ⚠ 改名之后**不要**再把它读窄：本条守的是**五条需求里任何一条**触底
##   （hunger / energy / social / fun / hygiene，`needs.json`）。docs/54 §五 已经点过这个坑的名字：
##   "报告里读到'饿穿'的人会去查粮食，而粮食是无辜的"——所以名字里必须带上"任一需求"。
##
## ── M1（2026-07-31）：**这条判据在 N≥18 上是一次抽签，而它跟 K1 的池 / L2 的 work_pull 都无关** ──
## 派棒的前提是"L2 的 work_pull 在 N=20 引入了硬 #01，而且是第一次带真饥饿"。**两半都不成立。**
## 2×2 消融（池 × work_pull，都由 production.json 的键门控，删键即回退；
## 「删 work_pull 键」这一格与 `git archive ed599e8` 出来的真 K1 树在 N=20 seeds 13-24 上
## **12/12 digest+chain 逐字节相同** ⇒ 消融工具本身先被证明是准的）。
## 四个配置**同一份 N/seed 覆盖**，各 168 次运行（N∈{16,18,20,22,24} × 14 个 12-seed 块，60 天，backend=null）：
##
##   配置                        运行  #01 红   #40 红   长触底段(≥1000tick)  带 hunger 的
##   A 池+work_pull（今天出货）   168     3        2            1                1
##   B 只有池（= K1 ed599e8）     168     6       11            2                2
##   C 只有 work_pull             168     3        6            0                0
##   D 两者都无（= Wave J 末）    168     4       95            0                0
##
## ⇒ ① **#01 的红率四个配置分不开（3/6/3/4 of 168）**，出货树不比它的两个前身差；
##    ② 出货树买到的是 **#40 从 95/168 掉到 2/168**——这才是那两笔改动真正动的那个量；
##    ③ **"第一次带真饥饿"是假的**：K1 自己的树在 N=20 seed 19 就是 `hunger×165`、
##       N=18 seed 8 是 `hunger×104`，两条都在**没人扫过的 seed 段**里（此前的网格只跑 seeds 1-12）。
##
## **hunger 与 social 不是两个现象，是同一段的两个投影。** 全部 36 次 #01 红逐条看
## （出货网格 16 次 + 下面那个被证伪的干预 20 次）：
##   social 段 ≤230 tick 的 29 次 ⇒ hunger **29/29 全为 0**；
##   social 段 ≥2735 tick 的 7 次 ⇒ hunger **7/7 都 >0**（占 social 的 1.3-7.7%）。
##   两组之间没有任何观测（230 与 2735 之间是空的）。逐 tick 追（`find_starve.gd` + M1 探针，N=20 seed 8）：
##   2867 个 need·tick **全部属于 npc_13 一个人**（克隆、无岗位），social 从第 48 天塌下去，
##   随后五条需求一起垮（energy≈15 / fun≈5 / hygiene≈13），hunger 才在第 52 天第一次触底
##   ——而且 **62 个 hunger tick 里每一个 `option` 都是「吃饭」**：他不是没被喂，是整个 need 向量都追不上了。
## ⇒ 报告里把 `hunger×62` 单拎出来当"新的饥饿"读是**读错了**；detail 现在补印形状（几人 / 最长连续段）就是为了堵这个。
##
## **work_pull 结构上够不着这个人**：`_adv_open`（Sim.gd:1622-1626）对**非在任者**直接拒掉带 `job` 的广告，
## 克隆 `_job_of("npc_13") == {}` ⇒ 它一条工位广告都枚举不到 ⇒ `benefit *= work_pull_mult` 那一行永不执行；
## 何况塌方期间 `_min_need < SURVIVAL_GATE` 恒真 ⇒ `mods_ok=false` 把整族乘子都关了。
##
## ⚠ **我自己的机制假设被自己的干预证伪了，写在这里免得下一个人再买一遍。**
## 假设："`_social_candidates`（Sim.gd:1805）的 `if _min_need(ag) < SURVIVAL_GATE: return []`
##       在 argmin 恰是 social 时，把唯一能修好 social 的动作类关掉了 ⇒ 自锁。"
## 干预（隔离副本，把 social 从那道门的 min 里摘掉），同一批 N/seed 各 48 次运行：
##       A 1 红 → **12 红**；B 4 红 → **8 红**；最狠的一格 `hunger×351`（比任何未干预的都大）。
##       并且它移动 **9/12 个 N=12 金标** ⇒ 还要付整套 R12。
## ⇒ 那道门是**承重的**（它上面那句"防大 N 沉迷戏剧而饿穿"的注释是对的），
##    松它买到的是更多饿穿，不是更少。**测过、决定不做。**
##
## ── docs/41 §2.5 探测包络（`does_not_detect` 逐条都是**跑出来的**，不是想出来的）──────────
## detects：
##   · `survival_veto_line` 归零（= B14 的 `_survival_ok` 落地之前那棵树）+ `random` 后端
##     ⇒ 8/8 seed 红，hunger 触底 506 need·tick，hunger 地板 0.00 逐 seed 8/8。
##   · 大 N 下的社会性孤立 ⇒ N=24 s3 / N=30 s1 / N=60 s12 红（social，各 35 / 81 / 61 need·tick）。
##   · 出货配置的模型路（`random` full，N=12，60 天）⇒ seed 1 红（hunger×11）。
## does_not_detect：
##   · **任何非空 `scenario` 一律豁免**（`starved == 0 or not harmony`）。实测：`random`+veto=0+`faction`，
##     seeds 1-4 × 8 天 ⇒ `starved` = 145/86/84/34、hunger 地板 0.00 逐 seed 4/4，而 **#1 绿 4/4**。
##     ⇒ `ci.sh` 4c 的 DetGate 跑 4 条臂，其中 3 条（faction/betray/freerider）本条**结构上不可能变红**。
##   · **停在 0.5 以上的一切退化**。实测：未改动的出货树，N=60（红线 #3 的出货目标）seed 10，
##     hunger 地板 **1.76**（= 98.2% 饿着）而 **#1 绿**；同一格 12 个 seed 里 11 个绿。
##     它是一条**零线**判据，不是余量判据——"快饿死"与"很舒服"在它眼里一模一样。
##   · **激进 LOD 会把它整个盖住**。实测 N=60 + `lod_aggregate`：0/6 红，五条 need 的地板全部 ≥ 8.64
##     （`_far_maintain` 被动喂需求）。⇒ 想用本条守大 N，必须关 LOD，否则量到的是兜底网不是行为。
##   · **不区分"一个人 61 tick"与"61 个人 1 tick"**（不按 agent 去重）。实测：零模型地板上 4 例红
##     4/4 都是**单独一个人**，而计数读起来像一场群体灾难。
##   · 触底**之后**的事一概不管：没有死亡、没有产能损失、没有"饿了多久"。`Sim._consume_for` 的红线是
##     缺货绝不阻断动作（docs/54），所以触底在本仓库里不致死——本条量的是**擦零**，不是后果。
## confidence：N=114 次运行 × 6 个配置域（上表），其中变异体 1 种（`survival_veto_line=0`）；
##   四格负对照 3 格（世界 H 两例 + 世界 S 一例）。**没有**在真机 / 有玩家 / SLM 后端 / N>60 上量过。
const INV1_NAME := "无 need 触底（任一需求，不只饥饿）"

## #1 的触底逐 need 明细（可选）。传了就在 detail 里点名是哪条需求触的底，不传则与改名前逐字相同。
## 为什么要它：I3 在 docs/54 §五 是**手工挖**出"三例都是 social"的——判据自己一个字都没说。
## 一条红了却说不出红在哪的判据，会被下一个人按名字去猜，而这一条的名字恰好猜错了 15 天。
static func _need_breakdown(by_need: Dictionary) -> String:
	if by_need.is_empty():
		return ""
	var ks: Array = by_need.keys()
	ks.sort_custom(func(a, b):
		var ca := int(by_need[a])
		var cb := int(by_need[b])
		return ca > cb or (ca == cb and String(a) < String(b)))   # 计数降序，同数按名——确定
	var parts := PackedStringArray()
	for k in ks:
		parts.append("%s×%d" % [String(k), int(by_need[k])])
	return "  逐 need=[" + ", ".join(parts) + "]"

## M1：把 `starved` 这个**标量**拆回它的三个自变量。**纯观测，不进判据。**
## 为什么值得多打这一行——它是本棒被派出来的直接原因：
##   L1 报的 `[social×2805, hunger×62]` 被读成"2805 次社交失败 + 62 次**真饥饿**"，
##   于是"第一次出现真饥饿"成了一条独立发现。实测（M1，672 次 backend=null 运行）：
##   那 2867 个 need·tick **全部属于同一个人**（`npc_13`，克隆、无岗位），
##   而 62 个 hunger·tick 是那条 6.3 天长的 social 触底段里的**下游派生**，不是第二个现象。
##   `need·tick` 是【人数 × need 种类 × 持续 tick】三者的乘积，
##   ⇒ **同一个数既可能是"很多人短暂触底"，也可能是"一个人躺了六天"，而处置完全不同。**
## ⇒ detail 里补三样：涉及几个人（点名，最多 4 个）· 最长连续触底段（tick 与天）· 该段属于谁的哪条 need。
## shape 缺省 {} ⇒ 追加空串 ⇒ **7 个既有调用点的输出逐字节不变**（同 starve_by_need 的约定）。
static func _starve_shape(shape: Dictionary) -> String:
	if shape.is_empty():
		return ""
	var who: Array = shape.get("agents", [])
	var names := PackedStringArray()
	for i in mini(4, who.size()):
		names.append(String(who[i]))
	var tail := "…" if who.size() > 4 else ""
	return "  涉及 %d 人[%s%s] · 最长连续触底 %d tick=%.1f 天 (%s)" % [
		who.size(), ", ".join(names), tail,
		int(shape.get("max_run_ticks", 0)), float(shape.get("max_run_days", 0.0)),
		String(shape.get("max_run_key", "?"))]

## starve_by_need：可选的逐 need 明细，**只进 detail 字符串，不进任何判据**（默认 {} ⇒ 8 个既有调用点
## 一个字节不用改，输出也与改名前逐字相同）。今天只有 Harness 传它。
## starve_shape：可选的**形状**明细（涉及几人 / 最长连续段），同样只进 detail 字符串、不进判据。
## 默认 {} ⇒ 8 个既有调用点里的 7 个一个字节不用改，输出也与本次改动前逐字相同。
static func check_all(S, starved: int, starve_by_need: Dictionary = {}, starve_shape: Dictionary = {}) -> Array:
	var R: Array = []
	var log: Array = S.event_log
	var accepted: Array = []
	for e in log:
		if bool(e["accepted"]) and not (String(e["type"]) in ["pay", "world", "election", "produce", "consume", "spoil", "shortage"]):
			accepted.append(e)   # 经济(pay)/世界变更(world)/治理(election)/产出账本(produce/consume/spoil/shortage)
			                     # 事件不算社交参与——否则 inv2/3 被稀释成空门。
			                     # ★Wave E 必须补这四个：produce/consume 的 actor 是干活/吃饭的人，
			                     #   不排除的话「#3 无永久孤立」会被"他吃过饭"喂饱，一个从不社交的居民也能过门。

	var harmony: bool = String(S.scenario) == ""   # 定向场景(faction/betray/freerider)会扭曲关系/致饿穿 → 豁免和睦不变量
	var small_n: bool = S.agents.size() <= 12       # 涌现/单源传播类只在设计 N(≤12)硬断言；大 N 单源谣言 fizzle 是现实(docs/12 L4)
	# 1) 无 need 触底（旧名「无饿穿」——判据从来就是【任一】need≤0.5，见 INV1_NAME 处的实测与四格对照）
	R.append(_chk(1, INV1_NAME, starved == 0 or not harmony,
		"触底 need·tick=%d%s%s (应=0;场景豁免)" % [starved, _need_breakdown(starve_by_need), _starve_shape(starve_shape)]))
	# 2) 社交发生
	R.append(_chk(2, "社交发生", not accepted.is_empty(), "已接受社交事务=%d (应>0)" % accepted.size()))
	# 3) 无永久孤立
	var participated := {}
	for e in accepted:
		participated[e["actor"]] = true
		participated[e["target"]] = true
	var isolated := []
	for ag in S.agents:
		if not participated.has(ag["id"]):
			isolated.append(ag["id"])
	R.append(_chk(3, "无永久孤立", isolated.is_empty(), "孤立 NPC=[%s]" % ", ".join(isolated)))
	# 4) 关系分化
	var aff_max := 0.0
	var aff_min := 0.0
	var any_nonzero := false
	for ag in S.agents:
		for oid in ag["relationships"]:
			var a := float(ag["relationships"][oid]["affinity"])
			aff_max = maxf(aff_max, a); aff_min = minf(aff_min, a)
			if a != 0.0:
				any_nonzero = true
	R.append(_chk(4, "关系分化", any_nonzero and aff_max - aff_min > 0.0, "affinity 跨度 %.0f..%.0f" % [aff_min, aff_max]))
	# 5) 谣言传播：R1 至少 2 人知道
	# ★O1(2026-07-31) 删掉了这一条的 `or not small_n`（大 N 豁免）。
	#   它原来的理由（注释在 :205「大 N 单源谣言 fizzle 是现实」）在**这棵树上不再成立**：
	#   fizzle 的成因不是"大 N 里谣言自然会冷"，而是 `_social_candidates` 里 greet 严格支配 gossip
	#   （非爱八卦者 25567 次机会 0 胜）＋ `_unspread_belief` 的插入序让贫富闲话占死唯一的 gossip 槽。
	#   两处修好之后（utility.json 的 gossip_news_first/bonus），R1 知晓人数（60 天，逐 seed 展布）：
	#     N=12 seeds 1-12  改前 2,3,3,2,2,2,2,3,2,3,3,3   改后 10,9,7,7,9,7,9,9,8,9,11,9
	#     N=16 seeds 1-12  改前 3,2,3,2,2,3,3,3,4,2,3,5   改后 12,10,13,12,12,13,13,10,12,11,11,9
	#     N=20 seeds 1/5/13 改前 2,3,2 → 改后 13,10,15 · N=60 同三 seed 改前 2,2,2 → 改后 56,56,56
	#   ★ **删掉豁免【本身】不改变任何一格的红绿**，这一条必须写清楚，因为它和派棒时的预期相反：
	#     负对照实测（隔离副本，两个键设回 0 = 改前轨迹逐字节，N=16 seeds 1-12 × 60 天）⇒
	#     **#5 仍然 12/12 绿、软门 PASS**。也就是说 `or not small_n` 在 N=16 上**从来不承重**：
	#     `>=2` 这条阈值在改前的树上本来就恒过（改前展布最小 2、最大 5）。
	#     ⇒ 豁免是**装饰**，真正没有牙的是阈值。删它是对的（一条永不可能生效的豁免只会误导读者），
	#       但**别把删它当成"谣言传播现在被守住了"**。
	#   ⚠ 为什么阈值仍留在 2、没有趁着这次余量收紧：**算过之后决定不做**（docs/41 §5）。
	#     要有牙就得 > 改前最大值 5 ⇒ 阈值至少 6；而改后最差一格是 7（N=12 seeds 3/4/6）
	#     ⇒ 余量只有 7/6 = **1.17×**。本仓库对"收紧"的参照标准是 2×（见本文件 HARD_IDS 上方那段）。
	#     "有牙"与"有余量"在今天的展布下**不可兼得** ⇒ 不动阈值，把展布写在这里给下一棒。
	var r1 := []
	var r1_src := {}
	for ag in S.agents:
		if ag["beliefs"].has("R1"):
			r1.append(ag["id"])
			r1_src[String(ag["id"])] = String((ag["beliefs"]["R1"] as Dictionary).get("source", ""))
	# 扩散深度（**只报告、不参与判定**）：沿 belief.source 往上走，种子持有者=0 跳。
	# 为什么把它印出来：`>=2` 只要求"发生过一次转述"，而多镇主诉要的是"消息越过了源头自己的社交半径"，
	# 那对应的是【≥2 跳】。实测这两件事今天分得开：改前 9 个格子（N∈{12,20,60}×seeds{1,5,13}×60 天）
	# 最深恒为 **1 跳、二跳人数恒为 0**，而 `>=2` 在同样 9 个格子上**全部通过** ⇒ 判据看不见这个区别。
	var r1_maxhop := 0
	for k in r1:
		var h := 0
		var cur := String(k)
		while h < 64:
			var s := String(r1_src.get(cur, ""))
			if s == "" or not r1_src.has(s):
				break
			cur = s; h += 1
		r1_maxhop = maxi(r1_maxhop, h)
	R.append(_chk(5, "谣言传播", r1.size() >= 2 or not harmony,
		"知道 R1=%d 人 最深%d跳 [%s] (应≥2;场景豁免)" % [r1.size(), r1_maxhop, ", ".join(r1)]))
	# 6) 知识边界
	var boundary_bad := 0
	for ag in S.agents:
		for cid in ag["beliefs"]:
			var b: Dictionary = ag["beliefs"][cid]
			if String(b.get("via", "")) in ["seed", "seen"]:
				continue   # seed=开局种子 / seen=亲眼所见(阶层 gossip 的财富目击)——一手知识无上游事件,豁免溯源
			var has_source: bool = S._agent_by_id.has(b.get("source", ""))
			var has_event := false
			for e in log:
				if String(e["type"]) == String(b.get("via", "")) and bool(e["accepted"]) and e["target"] == ag["id"] and e["subject"] == cid:
					has_event = true; break
			if not has_source or not has_event:
				boundary_bad += 1
	R.append(_chk(6, "知识边界", boundary_bad == 0, "无来源/无事件 belief=%d (应=0)" % boundary_bad))
	# 7) 账本可溯源
	var ids := {}
	for e in log:
		ids[e["id"]] = true
	var prov_bad := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var r: Dictionary = ag["relationships"][oid]
			if int(r["last_pos"]) > 0 and not ids.has(int(r["last_pos"])):
				prov_bad += 1
			if int(r["last_neg"]) > 0 and not ids.has(int(r["last_neg"])):
				prov_bad += 1
	R.append(_chk(7, "账本可溯源", prov_bad == 0, "指向不存在事件=%d (应=0)" % prov_bad))

	# ── 承诺系统 ──
	var c_created: int = S.commitments.size()
	var c_fulfilled := 0
	var c_broken := 0
	var c_leaked := 0
	for c in S.commitments:
		match String(c["status"]):
			"fulfilled": c_fulfilled += 1
			"broken": c_broken += 1
			"active":
				if int(c["deadline"]) < S.tick_no:
					c_leaked += 1
	var broken_events := 0
	for e in log:
		if e["type"] == "meet" and not bool(e["accepted"]):
			broken_events += 1
	# 8) 承诺生命周期
	R.append(_chk(8, "承诺生命周期", c_created > 0 and c_fulfilled > 0, "创建=%d 兑现=%d (均应>0)" % [c_created, c_fulfilled]))
	# 9) 无悬挂承诺
	R.append(_chk(9, "无悬挂承诺", c_leaked == 0, "已过点仍 active=%d (应=0)" % c_leaked))
	# 10) 违约可溯源且有后果
	R.append(_chk(10, "违约可溯源有后果", broken_events == c_broken and (c_broken == 0 or S.st_neg_events > 0),
		"broken=%d 违约事件=%d 负向声誉=%d" % [c_broken, broken_events, S.st_neg_events]))

	# ── 冲突生命周期 ──
	var cf_created: int = S.conflicts.size()
	var cf_confronted := 0
	var cf_repaired := 0
	var bad_repair := 0
	var bad_repair_prov := 0
	for c in S.conflicts:
		if int(c["confronted"]) > 0:
			cf_confronted += 1
		match String(c["status"]):
			"repaired":
				cf_repaired += 1
				if int(c["confronted"]) <= 0:
					bad_repair += 1
				var has_apo := false
				for e in log:
					if e["type"] == "apologize" and bool(e["accepted"]) and e["actor"] == c["b"] and e["target"] == c["a"]:
						has_apo = true; break
				if not has_apo:
					bad_repair_prov += 1
	# 11) 冲突生命周期
	R.append(_chk(11, "冲突生命周期", cf_created > 0 and (cf_repaired + cf_confronted) > 0,
		"触发=%d 对质=%d 修复=%d" % [cf_created, cf_confronted, cf_repaired]))
	# 12) 先对质后和解
	R.append(_chk(12, "先对质后和解", bad_repair == 0, "未对质即修复=%d (应=0)" % bad_repair))
	# 13) 修复可溯源
	R.append(_chk(13, "修复可溯源", bad_repair_prov == 0, "无道歉支撑的修复=%d (应=0)" % bad_repair_prov))

	# ── S1 声誉 ──
	var st_max := 0.0
	var st_min := 0.0
	for ag in S.agents:
		for oid in ag["relationships"]:
			var sv := float(ag["relationships"][oid]["standing"])
			st_max = maxf(st_max, sv); st_min = minf(st_min, sv)
	var rep_events := 0
	for e in log:
		if e["type"] == "gossip_rep" and bool(e["accepted"]):
			rep_events += 1
	var perceived := {}
	var prop_a := {}
	var acc_a := {}
	for ag in S.agents:
		var s := 0.0
		var n := 0
		for b in S.agents:
			if b["id"] != ag["id"]:
				s += float(S._rel(b, ag["id"])["standing"]); n += 1
		perceived[ag["id"]] = s / max(1, n)
		prop_a[ag["id"]] = 0; acc_a[ag["id"]] = 0
	for e in log:
		if String(e["type"]) in ["greet", "give", "gossip", "invite", "gossip_rep"]:
			prop_a[e["actor"]] = int(prop_a[e["actor"]]) + 1
			if bool(e["accepted"]): acc_a[e["actor"]] = int(acc_a[e["actor"]]) + 1
	var actives: Array = []
	for ag in S.agents:
		if int(prop_a[ag["id"]]) >= 5: actives.append(ag["id"])
	actives.sort_custom(func(x, y): return float(perceived[x]) < float(perceived[y]))
	var ostr := "n/a"
	var ostracism_ok := true
	if actives.size() >= 2:
		var town_acc := 0.0
		for id in actives:
			town_acc += float(acc_a[id]) / float(prop_a[id])
		town_acc /= float(actives.size())
		var worst: String = actives[0]
		var rw := float(acc_a[worst]) / float(prop_a[worst])
		ostr = "最坏 %s(%.1f) 接受率 %.2f / 镇均 %.2f" % [worst, perceived[worst], rw, town_acc]
		if float(perceived[worst]) <= -0.8:
			ostracism_ok = rw <= town_acc + 0.08
	# 14) standing 分化
	R.append(_chk(14, "standing分化", st_max - st_min > 0.0, "跨度 %.0f..%.0f" % [st_min, st_max]))
	# 15) 涌现放逐 —— ⚠ DIAGNOSTIC ONLY，见 DIAG_IDS：本指标已知有时间泄漏（temporal leakage），不作门。
	#   泄漏在哪：perceived 由「跑完后的终态 standing」算（上面 :140-149），而 prop_a/acc_a 数的是「整局全程」的
	#   提议/接受 —— 于是被放逐者在【变坏之前】那段时间的高接受率也被算进分母，指标必然被稀释/反转。
	#   项目已就此结案：修正版指标 #15v2（tools/exile_v2.py，只数「standing 跌破阈值之后」的窗口）在 126 个
	#   held-out seed 上返回 INCONCLUSIVE，故 docs/31-15-resolution.md 明确决定【不落任何机制、不设门】。
	#   保留检查是为了保留观测（残留 ~5% 是度量伪影而非真实放逐失败），但它永远不得让 CI 变红。
	R.append(_chk(15, "涌现放逐", ostracism_ok or not small_n, ostr + (" (大N豁免:密集社交下放逐不锐利)" if not small_n else "")))
	# 16) 声誉传播
	var bad_rep_exists := st_min <= float(S.REP_GOSSIP_TH)
	R.append(_chk(16, "声誉传播", (not bad_rep_exists) or rep_events > 0, "坏名声=%s gossip_rep=%d" % [str(bad_rep_exists), rep_events]))
	# 17) 坏名声形成且可恢复
	R.append(_chk(17, "坏名声形成可恢复", S.st_neg_events > 0 and cf_repaired > 0, "L3负向=%d 修复=%d (均应>0)" % [S.st_neg_events, cf_repaired]))

	# ── S2 意见动力学 ──
	var att_spread := 0.0
	for t in S.TOPICS:
		var vmax := -2.0
		var vmin := 2.0
		for ag in S.agents:
			var v := float(ag["attitudes"][t])
			vmax = maxf(vmax, v); vmin = minf(vmin, v)
		att_spread = maxf(att_spread, vmax - vmin)
	var att_moved := 0
	for ag in S.agents:
		for t in S.TOPICS:
			if absf(float(ag["attitudes"][t]) - float(ag["attitude0"][t])) > 0.02:
				att_moved += 1
	var discuss_events := 0
	for e in log:
		if e["type"] == "discuss" and bool(e["accepted"]):
			discuss_events += 1
	var stifled_count := 0
	for ag in S.agents:
		stifled_count += ag["stifled"].size()
	# 18) 观点演化不坍缩
	R.append(_chk(18, "观点演化不坍缩", (att_spread > 0.3 and att_moved > 0) or not harmony, "跨度 %.2f 变动者 %d (场景豁免)" % [att_spread, att_moved]))
	# 19) 有界信任门
	R.append(_chk(19, "有界信任Deffuant", (discuss_events > 0 and S.refused_by_bound > 0) or not harmony, "discuss=%d 因ε拒谈=%d (场景豁免)" % [discuss_events, S.refused_by_bound]))
	# 20) 谣言变冷
	R.append(_chk(20, "谣言变冷MakiThompson", stifled_count > 0 or not small_n, "stifler=%d (应>0;大N豁免:依赖单源谣言充分传播)" % stifled_count))

	# ── S3c 秘密信息博弈 (21-24，含小N守护) ──
	var betray_ev: Array = []
	for e in log:
		if e["type"] == "betray": betray_ev.append(e)
	var secret_cids := {}
	var secret_bad_via := 0
	for ag in S.agents:
		for cid in ag["beliefs"]:
			var b: Dictionary = ag["beliefs"][cid]
			if bool(b.get("secret", false)):
				secret_cids[cid] = true
				if not (String(b.get("via", "")) in ["confide", "leak", "seed"]): secret_bad_via += 1
	for e in log:
		if e["type"] == "gossip" and secret_cids.has(e["subject"]): secret_bad_via += 1
	R.append(_chk(21, "秘密专道", secret_bad_via == 0, "秘密漏进gossip/非法via=%d (应=0)" % secret_bad_via))
	var betray_bad := 0
	for be in betray_ev:
		var betrayed: Dictionary = S._agent_by_id.get(be["target"], {})
		var has_rel: bool = (not betrayed.is_empty()) and betrayed["relationships"].has(be["actor"])
		var has_conflict := false
		for c in S.conflicts:
			if c["a"] == be["target"] and c["b"] == be["actor"]: has_conflict = true; break
		var ln_ok: bool = has_rel and int(betrayed["relationships"][be["actor"]]["last_neg"]) > 0 and ids.has(int(betrayed["relationships"][be["actor"]]["last_neg"]))
		if not (has_rel and has_conflict and ln_ok): betray_bad += 1
	R.append(_chk(22, "背叛有后果可溯源", betray_bad == 0, "无冲突/不可溯源的背叛=%d (应=0)" % betray_bad))
	R.append(_chk(23, "背叛重挫名声", betray_ev.is_empty() or S.st_neg_events > 0, "背叛=%d 累积负判=%d" % [betray_ev.size(), S.st_neg_events]))
	var false_betray := 0
	for be in betray_ev:
		var has := false
		for e in log:
			if int(e["id"]) < int(be["id"]) and bool(e["accepted"]) and (e["type"] == "confide" or e["type"] == "leak") and e["actor"] == be["target"] and e["target"] == be["actor"] and e["subject"] == be["subject"]:
				has = true; break
		if not has: false_betray += 1
	R.append(_chk(24, "背叛无误判", false_betray == 0, "无直接上游吐露证据的背叛=%d (应=0)" % false_betray))

	# ── S3a 观点派系 (25-28，含小N守护) ──
	# ★Q1：#25 的名字承诺的是「派系归属与它的派生规则一致」，而派生规则在 Q1 之后是**两个**合取项：
	#   ①与医心 `_aligned`（想的一样）②与医心 `_acquainted`（真的照过面）。
	#   docs/41 §2 第四个盲区点名的正是"名字是合取式而实现只查了一半"——#39 就这么漏了「在班」两个字。
	#   所以这里把第二项也查上，两个计数**分开报**，红的时候能一眼看出破的是哪一半。
	#   ⚠ 余量：门开时 `_recompute_factions` 按构造保证这两项，故 `unmet` 恒 0；
	#     门关时（`faction_fam_th<=0`）`_acquainted` 恒真 ⇒ 这一项自动退化为无牙，**与被守的性质同步消失**，
	#     不会在 ablation 配置上假红。这一条写进 docs/65 的 does_not_detect。
	var fac_inc := 0
	var fac_unmet := 0
	for ag in S.agents:
		if (String(ag["faction"]) == "") != (int(ag["faction_size"]) == 1): fac_inc += 1
		if String(ag["faction"]) != "" and String(ag["faction"]) != String(ag["id"]):
			if not S._aligned(ag, S._agent_by_id[ag["faction"]]): fac_inc += 1
			if not S._acquainted(String(ag["id"]), String(ag["faction"])): fac_unmet += 1
	#   ⚠ 第三项 `fac_unmet_placements` 是**累计**量而不是终态量，理由见 Sim.gd 那个字段的抬头：
	#     12 人的镇跑 60 天之后人人都认识人人 ⇒ 只查终态的话，**把接触门整条删掉也全绿**（实测 3/3）。
	#     写成直接取属性、**不写 `S.get("...")`**：后者对不存在的属性返回 null ⇒ `int(null)` = 0 ⇒
	#     哪天字段被改名，这一臂会**静默变成恒真**——那正是本棒在防的那种失效。本文件其余各条同样是直接取。
	var fac_unmet_ever := int(S.fac_unmet_placements)
	R.append(_chk(25, "S3派系派生一致(对齐且相识)", fac_inc == 0 and fac_unmet == 0 and fac_unmet_ever == 0,
		"对齐不一致=%d 终态未谋面同派系=%d 全程未谋面归堆=%d (均应=0)" % [fac_inc, fac_unmet, fac_unmet_ever]))
	var fac_count: int = S.factions.size()
	var in_sum := 0.0
	var in_n := 0
	var cr_sum := 0.0
	var cr_n := 0
	for a in S.agents:
		for b in S.agents:
			if a["id"] == b["id"] or String(a["faction"]) == "" or String(b["faction"]) == "": continue
			var aff := float(S._rel(a, b["id"])["affinity"])
			if String(a["faction"]) == String(b["faction"]): in_sum += aff; in_n += 1
			else: cr_sum += aff; cr_n += 1
	var fac_aff_ok := true
	var fac_msg := "派系=%d ingroup对=%d cross对=%d" % [fac_count, in_n, cr_n]
	if harmony and fac_count >= 2 and in_n >= 3 and cr_n >= 3:
		var in_avg := in_sum / float(in_n)
		var cr_avg := cr_sum / float(cr_n)
		fac_aff_ok = in_avg > cr_avg + float(S.FACTION_AFF_MARGIN)
		fac_msg = "同派系均%.1f vs 跨派系均%.1f" % [in_avg, cr_avg]
	else: fac_msg += " (小N/场景跳过)"
	R.append(_chk(26, "S3同派系亲和>跨派系", fac_aff_ok, fac_msg))
	var st_overflow := 0
	var endorse_bad := 0
	for ag in S.agents:
		for oid in ag["relationships"]:
			if absf(float(ag["relationships"][oid]["standing"])) > float(S.STANDING_CAP) + 0.001: st_overflow += 1
	for e in log:
		if e["type"] == "endorse" and not S._agent_by_id.has(e["subject"]): endorse_bad += 1
	R.append(_chk(27, "S3协同守边界", st_overflow == 0 and endorse_bad == 0, "|standing|越界=%d 无效endorse=%d" % [st_overflow, endorse_bad]))
	var fac_bucket_bad := 0
	for m in S.factions:
		if (S.factions[m] as Array).size() < 2: fac_bucket_bad += 1
		for id in (S.factions[m] as Array):
			if String(S._agent_by_id[id]["faction"]) != String(m): fac_bucket_bad += 1
	R.append(_chk(28, "S3派系视图自洽", fac_bucket_bad == 0, "坏桶/标签不符=%d" % fac_bucket_bad))

	# ── S3b 互助盟约 (29-33，含小N守护) ──
	var aid_ev: Array = []
	for e in log:
		if e["type"] == "aid" and bool(e["accepted"]): aid_ev.append(e)
	var pact_pairs := {}
	for p in S.pacts_index: pact_pairs[p["key"]] = true
	var aid_nonpact := 0
	for e in aid_ev:
		if not pact_pairs.has(S._pact_key(e["actor"], e["target"])): aid_nonpact += 1
	R.append(_chk(29, "I-PACT互助偏内", S.aid_accepted < 8 or aid_nonpact == 0, "非盟约aid=%d (aid总%d,样本≥8应=0)" % [aid_nonpact, S.aid_accepted]))
	var pact_b_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "broken" and String(p.get("reason", "")).begins_with("freerider"):
			var has_ev := false
			for e in log:
				if e["type"] == "pact" and not bool(e["accepted"]) and String(e.get("note", "")) == "dissolved:freerider" and ((e["actor"] == p["a"] and e["target"] == p["b"]) or (e["actor"] == p["b"] and e["target"] == p["a"])):
					has_ev = true; break
			if not has_ev or int(p.get("breakGap", 0)) < S.FREERIDER_GAP: pact_b_bad += 1
	R.append(_chk(30, "I-PACT-free-rider可溯源", pact_b_bad == 0, "异常=%d (应=0)" % pact_b_bad))
	var pact_c_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "active" and not (float(p["formTrustA"]) >= float(S.PACT_TRUST_TH) and float(p["formTrustB"]) >= float(S.PACT_TRUST_TH) and float(p["formFam"]) >= float(S.PACT_FAM_TH) and int(p["formComplement"]) >= S.PACT_COMPLEMENT_TH): pact_c_bad += 1
	R.append(_chk(31, "I-PACT结盟门达标", pact_c_bad == 0, "低门被结的active=%d" % pact_c_bad))
	var pact_d_bad := 0
	var active_keys := {}
	for p in S.pacts_index:
		if not (String(p["status"]) in ["active", "broken"]): pact_d_bad += 1
		if String(p["status"]) == "active":
			active_keys[p["key"]] = int(active_keys.get(p["key"], 0)) + 1
			var A: Dictionary = S._agent_by_id.get(p["a"], {})
			var B: Dictionary = S._agent_by_id.get(p["b"], {})
			if A.is_empty() or B.is_empty() or not (A["pacts"].has(p["b"]) and String(A["pacts"][p["b"]]["status"]) == "active" and B["pacts"].has(p["a"]) and String(B["pacts"][p["a"]]["status"]) == "active"): pact_d_bad += 1
	for k in active_keys:
		if int(active_keys[k]) > 1: pact_d_bad += 1
	R.append(_chk(32, "I-PACT无悬挂无重复对称", pact_d_bad == 0, "异常=%d" % pact_d_bad))
	var pact_e_bad := 0
	for p in S.pacts_index:
		if String(p["status"]) == "broken" and int(S._agent_by_id[p["a"]]["complementSeen"].get(p["b"], 0)) == 0: pact_e_bad += 1
	R.append(_chk(33, "I-PACT解体可恢复", pact_e_bad == 0, "complementSeen被清=%d" % pact_e_bad))

	# ── Wave 1b 经济 (34-35，economy.json 缺失时恒过=零扰动) ──
	var econ_on: bool = not S.economy.is_empty()
	var neg_coin := 0
	for ag in S.agents:
		if int(ag["inventory"].get("coin", 0)) < 0: neg_coin += 1
	# 34) 金钱守恒：Σagent coin + 镇库 恒等于开局总量（transfer 唯一通道的结构保证，机检兜底）
	R.append(_chk(34, "金钱守恒", (not econ_on) or int(S.money_total()) == int(S.econ_total0),
		"总量=%d 基准=%d (应相等)" % [int(S.money_total()), int(S.econ_total0)]))
	# 35) 货币非负：transfer 不足即拒 → 任何人不可能透支
	R.append(_chk(35, "货币非负", neg_coin == 0 and S.town_coin >= 0, "负余额agent=%d 镇库=%d" % [neg_coin, int(S.town_coin)]))

	# ── Wave 2b 节日 (36，festivals.json 缺失时恒过) ──
	# 36) 节日无残留且账实相符：fest_ 对象只在节日进行中存在；spawn-despawn 事件差 == 现存 fest 对象数
	var fest_now := 0
	for oid in S.world.get("objects", {}):
		if String(oid).begins_with("fest_"): fest_now += 1
	var sp_ev := 0
	var dsp_ev := 0
	for e in log:
		if String(e["type"]) == "world" and String(e["target"]).begins_with("fest_"):  # 只数节日对象事件（civic_ 选举 WorldPatch 不参与配对）
			if String(e.get("note", "")) == "spawn": sp_ev += 1
			elif String(e.get("note", "")) == "despawn": dsp_ev += 1
	var fest_ok: bool = (fest_now == 0 or String(S.festival_active) != "") and (sp_ev - dsp_ev == fest_now)
	R.append(_chk(36, "节日对象配对无残留", fest_ok, "现存=%d 活动=%s spawn=%d despawn=%d" % [fest_now, String(S.festival_active), sp_ev, dsp_ev]))
	# #37 选举计票自洽（Wave 3a 硬不变量，docs/15「计票=快照纯函数=硬不变量」）：每场选举 票数守恒(yea+nay+abstain=选民数)
	#   + 结果与票数一致(pass=yea>nay) + election 事件数=选举场次。elections 关→election_log 空→恒真(off 门不引约束)。
	var elec_ok := true
	var elec_detail := "无选举"
	if not S.election_log.is_empty():
		var eligible := 0
		for ag in S.agents:
			if not bool(ag.get("is_player", false)): eligible += 1
		var elec_events := 0
		for e in log:
			if String(e["type"]) == "election": elec_events += 1
		for r in S.election_log:
			var rd: Dictionary = r
			var sumv := int(rd["yea"]) + int(rd["nay"]) + int(rd["abstain"])
			if sumv != int(rd["voters"]) or sumv != eligible or bool(rd["pass"]) != (int(rd["yea"]) > int(rd["nay"])):
				elec_ok = false; break
		if elec_ok and elec_events != S.election_log.size():
			elec_ok = false
		elec_detail = "%d 场 选民=%d 事件=%d" % [S.election_log.size(), eligible, elec_events]
	R.append(_chk(37, "选举计票自洽", elec_ok, elec_detail))

	# ── Wave E 劳动产出闭环 (38-40，production.json 缺失时恒过=零扰动；docs/47 §二-E1) ──
	# 结构照抄 #34/#35：库存增减只有 Sim._stock_move / _stock_take 一个通道，于是"账本能独立重算出现存量"
	# 就是那个通道没被绕过的机检证据。绕过它（直接写 town_stock）→ #38 立刻红。
	var prod_on: bool = not S.production.is_empty()
	# 38) 库存账本自洽 + 非负：对每种货，现存 == 开局 + Σproduce − Σconsume(已入账) − Σspoil − 当日待入账
	#     （待入账项来自"消耗按天入账"的设计：逐次入账会往 event_log 塞上千条流水，把 Main 的小镇纪事冲掉。
	#      日界结算后该项恒为 0，而 Harness/DetGate 的收尾 tick 恰好落在日界上。）
	var ledger_bad: Array = []
	if prod_on:
		var moved := {}          # good -> Σ(+produce −consume −spoil)，全部从 event_log 解出来
		for e in log:
			var ty := String(e["type"])
			if not (ty in ["produce", "consume", "spoil"]):
				continue
			var g := String(e["subject"])
			var amt := _amt_of(String(e.get("note", "")))
			moved[g] = int(moved.get(g, 0)) + (amt if ty == "produce" else -amt)
		for g in S.production.get("goods", {}):
			var gid := String(g)
			var expect: int = int(S.stock_total0.get(gid, 0)) + int(moved.get(gid, 0)) - int(S._stock_day.get(gid, 0))
			var got: int = int(S.town_stock.get(gid, 0))
			if got != expect:
				ledger_bad.append("%s 现存=%d 账本算得=%d" % [gid, got, expect])
			if got < 0:
				ledger_bad.append("%s 库存为负=%d" % [gid, got])
		for g2 in S.town_stock:      # 账外货：不在 goods 表里的键说明有人绕过了唯一通道
			if not (S.production.get("goods", {}) as Dictionary).has(String(g2)):
				ledger_bad.append("未申报的货 %s" % String(g2))
	R.append(_chk(38, "库存账本自洽", ledger_bad.is_empty(),
		("对不上: " + "; ".join(ledger_bad)) if not ledger_bad.is_empty()
		else ("库存=%s" % str(S.town_stock) if prod_on else "产出系统关闭(缺 production.json)")))
	# 39) 产出溯源到在班本职：每条 produce 事件的 actor 必须是【持有该职位的人】，货必须是该职位申报的货，
	#     件数必须落在 (0, 申报批量]（撞 cap 会少收，故是 ≤ 而不是 ==）。
	#     它跨 jobs.json × production.json × 代码路径三方对账 —— 让"货从天上掉下来"或"张三产出李四的货"变红。
	var prov_bad2: Array = []
	if prod_on:
		for e in log:
			if String(e["type"]) != "produce":
				continue
			var actor := String(e["actor"])
			var job: Dictionary = S._job_of(actor)
			var title := String(job.get("title", ""))
			var rec: Dictionary = S.production.get("produce", {}).get(title, {})
			var amt2 := _amt_of(String(e.get("note", "")))
			if job.is_empty() or rec.is_empty():
				prov_bad2.append("#%d %s 无本职/该职位未申报产出" % [int(e["id"]), actor])
			elif String(rec.get("good", "")) != String(e["subject"]):
				prov_bad2.append("#%d %s(%s) 产出了 %s" % [int(e["id"]), actor, title, String(e["subject"])])
			elif amt2 <= 0 or amt2 > int(rec.get("amount", 0)):
				prov_bad2.append("#%d %s 件数=%d 超出申报 %d" % [int(e["id"]), actor, amt2, int(rec.get("amount", 0))])
			elif String(e.get("note", "")).split("*")[0] != title:
				prov_bad2.append("#%d note 职位=%s 实为 %s" % [int(e["id"]), String(e.get("note", "")).split("*")[0], title])
			# ★「在班」这一半此前【根本没有检查】（2026-07-30 外部审计抓到）：
			#   这条不变量叫"产出溯源到【在班】本职"，而它从不读 e["tick"]、从不调 _in_shift。
			#   失败场景是具体的：把 _produce_for 开头那道班次守卫（现 Sim.gd:2925，`or not _in_shift(job)`；
			#   原注写的 `:2889` 与 `and not _in_shift(job)` 两处都已过期）删掉，
			#   面点师就会在 03:00 烤点、渔夫半夜打渔，而 #39 依然全绿。
			#   八个岗位全都有真实班次（jobs.json / production.json.jobs）⇒ 这是一条【活的】约束，不是真空条款。
			#   班次谓词是 f(tick)，而 tick 就在事件里 ⇒ 它一直是可查的，只是没查。
			elif not _shift_ok_at(S, job, int(e.get("tick", -1))):
				prov_bad2.append("#%d %s(%s) 在【非班次】时段产出（tick=%d 相位=%s 班次=%s）" % [
					int(e["id"]), actor, title, int(e.get("tick", -1)),
					_phase_at(S, int(e.get("tick", -1))), str(job.get("shift", []))])
	R.append(_chk(39, "产出溯源到在班本职", prov_bad2.is_empty(),
		("异常=%d: %s" % [prov_bad2.size(), "; ".join(prov_bad2.slice(0, 3))]) if not prov_bad2.is_empty()
		else ("produce 事件全部可溯源" if prod_on else "产出系统关闭")))
	# 40) 【软】产出闭环活性【与供给充足】：#38/#39 都是"若 X 发生则 X 良构"，X 归零它们全绿——
	#     production.json 还在、而产出/消耗一次都没发生，正是要防的那种"机制被静默关掉"。
	#     ★ 2026-07-30 第一次收紧（Wave F）：全镇合计 → 逐货物。合计量掩盖单品死亡。
	#     ★ 2026-07-30 第二次收紧（Wave H5，外部对抗评审给的干预）：**存在性 → 连续性**。
	#       外审原话：`粮食 produce 3 / consume 200` ⇒ **过门**，然后库存耗尽、居民饿死在 60 天以后。
	#       `∃producer ∧ ∃consumer` 只能证明系统没有【完全】断裂，证明不了它够用。
	#
	#     ── 三个候选判据先量了再选（12 seed × 60 天 × 6 货 = 72 格 + 留出 13-30，隔离副本探针，量完即撤）──
	#     ① `coverage = Σproduce/Σconsume ∈ [0.8,1.5]`（外审的第一个建议）—— **实测否掉，但理由不是"它恒等于1"**。
	#        我第一版在这里写的是"结构性地钉在 1 附近、掐掉 95% 产量它照样 1.0x"——**那句是我编的，实测是假的**：
	#        把口粮两个生产者从 90/85 掐到 4/4 之后，口粮 coverage = **0.500-0.755**，它是会动的。
	#        真正的机制窄得多，从 #38 守的那条恒等式直接推得：
	#            `coverage = 1 + (期末库存 − 开局库存 + Σspoil) / Σconsume`
	#        ⇒ 它由【开局库存与每日损耗】决定，**不由健康度决定**，而且随天数收敛到 `1 + 损耗×天数/Σ消耗`。
	#        实测这条收敛（同一棵未改动的树，整洁 spoil_per_day=2）：
	#            days=30 → 0.964-1.467   days=40 → 1.151-1.544   days=50 → 1.256-1.608   days=60 → 1.338-1.661
	#        ⇒ **`[0.8,1.5]` 这个区间在出货树上就是红的**：整洁在 30 个基线 seed 里有 **13 个超过 1.5**
	#          （seeds 1-12 里 4 个、13-30 里 9 个）⇒ 软门要 ≥11/12，当场破。
	#        ⇒ 而且它的灵敏度更差：屋瓦产量砍 60%（30→12）时 coverage = 0.846-0.923，**整整落在区间里**，
	#          同一批 seed 上满足率判据抓到了 7/12。**⇒ 一个货一个基线，不存在全局区间。**
	#     ② `days_of_supply = 期末库存 / 日均消耗`（外审的第二个建议）—— **实测否掉**：
	#        它是【终态快照】，基线实测 话本 seed 11 = 0.000、口粮 seed 8 = 0.615，**余量为零**。
	#     ③ `供给满足率 = 已服务件数 / 需求件数` —— **选它**。它对"需求密度"免疫（这正是 ①② 的死因）。
	#        实测（逐 seed 取【最差的那种货】，这正是门真正判的量）：
	#          基线 seeds 1-12  ：0.615 0.634 0.683 0.720 0.762 0.788 0.812 0.814 0.875 0.880 0.884 0.889
	#          基线 seeds 13-30 ：最低两个是 0.569 / 0.579（留出种子，不参与选阈值，只用来复核）
	#     ⚠ **上面那行 13-30 的数字今天已经不成立了**（O1 2026-07-31 复跑 ScaleSupply 全 18 个 seed）：
	#        H5 之后 L2/M2/K1 各自蓄意移动过轨迹，而没有人回来复核这条判据的余量。
	#        **O1 改动【之前】的树上，13-30 的最差货满足率最低值是 0.500 —— 恰好等于门槛本身，余量已经是 0。**
	#        逐 seed（改前，13→30）：0.611 0.756 0.697 0.633 0.596 0.732 0.766 **0.500** 0.667 0.732
	#                                0.605 0.629 0.624 0.685 0.779 0.809 0.718 0.845
	#        ⇒ 谁的改动只要让 seed 20 再掉 1%，这道软门就会红，而红的理由跟他改的东西可能毫无关系。
	#        这不是"别的机器上会假红"（同 seed 同二进制逐字节可复现），是**真实灵敏度已经被吃光了**。
	#        根因看得见：柴薪全镇只有【杂役】一个产者，他 60 天的在班次数在 18 个 seed 上摆动 1-12。
	#        ⇒ **下一个动社交/时间分配的棒，请先跑一次 ScaleSupply 13-30 拿到这条基线，别只看红绿。**
	#          掐产量不归零的六个变异体：被掐那种货 0.069-0.415（1-12）、最高 0.488（thr_book 的 13-30）
	#        ⇒ 分界带是 [0.488, 0.569]，取 **0.50**。
	#        而且门是【逐 seed 通过率】制（软门容 1/12）⇒ 要假红得有【两个】seed 同时跌破，
	#        ~~30 个基线 seed 里跌破的个数是 **0**~~；而 thr_book / thr_bean 是 **30/30 个 seed 全跌破**。
	#     ⚠ **2026-08-01 S1：删除线那句今天是假的，而且 O1 上面那份"改前 13-30"的逐 seed 数也已经再次过期。**
	#        S1 在【合并树】上重跑同一条命令（ScaleSupply，13-30 × 60 天），逐 seed（13→30）：
	#          0.726 0.765 0.878 0.842 0.810 **0.419** 0.753 0.849 0.769
	#          0.887 0.789 0.744 0.839 0.701 0.761 0.832 0.792 0.507
	#        ⇒ 最低的那一格从 O1 记的 seed 20 换成了 **seed 18 = 0.419（口粮）**，次低是 **seed 30 = 0.507（屋瓦）**
	#          ——**连"最紧的是哪一种货"都换了**（O1 归因给柴薪的单产者，今天最紧的两格一个是口粮一个是屋瓦）。
	#        S1 又新抽了 seeds 31-60（30 个，从没有人跑过）：跌破 4 个。**合计 5/60。**
	#        **根因是量出来的**（n=60，Spearman ρ(口粮满足率, 面点师+渔夫在班完成) = **0.618**）：
	#          五个红 seed 里有四个是口粮，而它们正是"口粮的两个生产者【同时】掉到地板"的那几个——
	#          面点师+渔夫 60 天在班完成之和在 60 个 seed 上的展布是 **5 .. 30**，
	#          而五个红 seed 的这个和是 5(seed50) / 6(seed18) / 7(seed58) / 8(seed36)（第五个 seed40 是另一条：
	#          咖啡师 60 天只上工 **1** 次 ⇒ 豆子 0.369）。
	#        ⇒ 这条判据的左尾由**单个岗位的在班完成次数**驱动，而那是一个高方差、下沿贴地的量
	#          （咖啡师 1..17 · 杂役 1..10 · 渔夫 2..14 · 面点师 2..19，60 个 seed）。
	#          **谁要收紧它、或者要证明自己"修好了"，先跑 ≥48 个 seed。**
	#     ⚠ 为什么不用【缺货天数占比】（第一版就是它，被自己的数据否掉）：它随需求密度漂——
	#        基线最大 0.467（屋瓦 seed 7），而把话本产量掐掉 83% 之后只有 0.300-0.600
	#        ⇒ **不存在能同时分开这两组的阈值**。留作 detail 里的诊断数字，不作判据。
	#
	#
	#     ── ★K1（2026-07-31，docs/41 §0.5 双尺度）：**本条判据在两种产出契约下一个字节都没改**，理由在这里 ──
	#     §0.5 与 docs/57 §一 都预期"宏观池要配一套自己的判据"。**实测不需要，而且不加是更强的选择**：
	#       · 满足率是**比值**（到手件数/想要件数），对"记账单位"天然免疫。宏观池换的正是记账单位
	#         （一次在班完成从"一个人的产量"变成"这一行的产量"）⇒ 分子分母同尺度 ⇒ 判据不变。
	#       · 分母那一半会**自动跟着换尺度**，因为它读的是 `S.production`，而 K1 的池是在
	#         `Sim.start_new` 里把 production 整体换尺度后交给下游的（`Sim._pool_rescale`）——
	#         包括 `produce[职位].inputs`，所以窑口那份柴薪需求在池口径下仍然对得上（实测 0 次 MISMATCH）。
	#     ⇒ **#38/#39/#40 这三条的判据里没有任何一处读人口**。
	#     ⚠ 但"本文件里没有一处读人口"是**假的**，我自己写下这句之后跑 grep 才发现——
	#        `small_n = S.agents.size() <= 12`（现 :205）是**本棒之前就有**的人口分档，
	#        被 #5(谣言传播) / #15(涌现放逐) / #20(谣言变冷) 三条用来在大 N 上**豁免自己**。
	#        它与 §0.5 点名的那个坑是同一族（按人口放过），只是方向相反：它让那三条在 N>12 上不断言，
	#        ~~而 **CI 恒跑 N=12 ⇒ `small_n` 恒为 true ⇒ 这三条豁免在 CI 里一次都没生效过**（休眠，不是假绿）。~~
	#        ⚠ **删除线那句写下来的当天就过期了**（O1 2026-07-31 查出）：K1 写它是在 `d96ea99`，
	#          而**同一天**晚些的 `2b4565e`（L1）给 `tools/ci.sh` 加了第 4a 步，跑的是 `--agents ${CI_POOL_N:-16}`
	#          ⇒ **`small_n` 在 CI 里从那一刻起每次都是 false，三条豁免每次 CI 都在生效。**
	#          「休眠」变成了「每跑必用」，而没有人回来改这句话——`docs/41 §1.5` 的同一个病。
	#        O1 已经把 **#5 的 `or not small_n` 删掉**（见 #5 那一段的证据与余量）；#15/#20 仍然留着：
	#          · #15 在 `DIAG_IDS` 里，本来就永不成门，豁免与否无所谓；
	#          · #20（谣言变冷）的豁免看起来**同样不承重**：`stifled_count` 在【改动前】的 N=60 上
	#            实测就是 4599-4653（seeds 1/5，30 天），判据要的只是 `> 0` ⇒ 豁免与否都绿。
	#            但本棒**没有把它连同 #5 一起删**——一次只动一条判据，而且 #20 的展布只在 2 个 seed 上量过。
	#            留给下一棒，别以为这条纪律已经全仓落实。
	#        §0.5 点名要防的是"按人口分档 ⇒ 给出货配置预埋一条永不变红的门"；#40 这里连分档都没有，
	#        两种契约走**同一条**判据，而它在池化契约下仍然会红——三个负对照（K1 回执）：
	#          nc1 池倍率取整到 0（供给恒 0）      → N=60 **红 2/2**、N=12 **红 2/2**（满足率 0.000，断供 60/60）
	#          nc2 池只给一半（base_population=24）→ N=60 **红 3/3**（最差货 0.319-0.396，屋瓦断供 39-49/60）
	#          nc3 批量再 ×8（灌满）              → N=60 **绿 2/2** ← 这一条【当时】是 does_not_detect：本判据没有上限臂
	#        ⚠ **2026-08-01 R1 已补上上限臂**（见下面「缺货绝迹」那一段）⇒ 上面这句「没有上限臂」不再成立。
	#          但 nc3 这个变异体**换了个理由继续抓不到**：R1 在 N=12 上复跑同一个变异体，
	#          上限臂**仍然绿**（零缺货货数 max 2），而**下限臂红 2/12**（口粮 0.426 / 柴薪 0.487）。
	#          机制量出来了：`cap` 不动 ⇒ 一炉 720 份撞 130 的满仓当场丢掉；整洁被灌满 ⇒ `_clean_mult`
	#          恒 1.0 ⇒ 广场活动不再打折 ⇒ 全镇反而少干活。**「把产量放大」不是单调干预**，
	#          要造真正的灌满得 amount 与 cap 一起放大（R1 的 nc2，实测上限臂红 8/12 @N=12）。
	#     ⚠ 但契约本身要能读出来 ⇒ detail 末尾追加"产出契约=宏观池 ×num/den | 逐笔"（只报不判，见下）。
	#     ⚠ **本判据在 CI 里仍然只跑 N=12**（docs/54 §八：ci.sh 里没有任何一处在 N>12 上评估不变量），
	#        而 N=12 上池倍率恰为 1 ⇒ **池这条路 CI 一步都没走过**。这是 docs/41 §2 第三个盲区的新实例，
	#        修它要动 `tools/ci.sh`（不在 K1 的行）。复跑命令与实测成本见 K1 回执。
	#
	#     ── 分档（外审的第二条警告：将来引入【本就不该被生产】的货，"每种货 produce>0" 会假红）──
	#     不写死货物名单，而是**从数据自己的结构里推**：
	#       · 有人在 `produce` 里申报要产它 ⇒ 才要求 Σproduce>0；
	#       · 有动作在 `consume` 里申报要用它、或有工种把它申报为 `inputs` 原料 ⇒ 才要求 Σconsume>0 与满足率。
	#     ⇒ 加一件谁都不产、谁也不用的传说物品，本条**自动豁免它**（实测：旧判据当场红，本判据绿）。
	var n_prod := 0
	var n_cons := 0
	var per_p: Dictionary = {}        # 货 -> Σ产出【件数】（旧版数的是事件条数；改数件数，>0 的判定等价而 detail 更有信息）
	var per_c: Dictionary = {}        # 货 -> Σ【真正拿到手】的件数（consume 事件 + 当日待入账，口径同 #38 的 pending 项）
	var sh_day: Dictionary = {}       # 货 -> 出现过 shortage 的【天】集合（只进 detail，不作判据，见上）
	var producible: Dictionary = {}   # 货 -> 有申报的生产者
	var demanded: Dictionary = {}     # 货 -> 有申报的用途（消费动作 或 别的工种的原料）
	var demand: Dictionary = {}       # 货 -> 需求【件数】：消费动作 attempts×件 + 原料 在班完成×件
	var tpd: int = maxi(1, int(S.TICKS_PER_DAY))
	var days_run: int = maxi(1, int(S.tick_no) / tpd)
	if prod_on:
		for g in S.production.get("goods", {}):
			var gid0 := String(g)
			per_p[gid0] = 0; per_c[gid0] = 0; sh_day[gid0] = {}
			producible[gid0] = false; demanded[gid0] = false; demand[gid0] = 0
		for title in S.production.get("produce", {}):
			var prec: Dictionary = (S.production["produce"] as Dictionary)[String(title)]
			if producible.has(String(prec.get("good", ""))):
				producible[String(prec.get("good", ""))] = true
			var pins = prec.get("inputs", {})
			if pins is Dictionary:
				# G3 的原料需求走 _stock_take，不进 prod_stats.attempts ⇒ 必须从【在班完成次数】补上，
				# 否则柴薪的分母少掉窑口那一份，满足率会算出 >1（实测 1.254）。
				var nw := int((S.prod_stats.get("work", {}) as Dictionary).get(String(title), 0))
				for ing in (pins as Dictionary):
					var ig := String(ing)
					if demanded.has(ig):
						demanded[ig] = true
						demand[ig] = int(demand[ig]) + nw * int((pins as Dictionary)[ing])
		for act in S.production.get("consume", {}):
			var crec: Dictionary = (S.production["consume"] as Dictionary)[String(act)]
			var cg := String(crec.get("good", ""))
			if demanded.has(cg):
				demanded[cg] = true
				demand[cg] = int(demand[cg]) \
					+ int((S.prod_stats.get("attempts", {}) as Dictionary).get(String(act), 0)) * int(crec.get("amount", 1))
	for e in log:
		var _ty := String(e["type"])
		var _g := String(e["subject"])
		if _ty == "produce":
			n_prod += 1
			if per_p.has(_g): per_p[_g] = int(per_p[_g]) + _amt_of(String(e.get("note", "")))
		elif _ty == "consume":
			n_cons += 1
			if per_c.has(_g): per_c[_g] = int(per_c[_g]) + _amt_of(String(e.get("note", "")))
		elif _ty == "shortage":
			if sh_day.has(_g): (sh_day[_g] as Dictionary)[int(int(e.get("tick", 0)) / tpd)] = true
	for g0 in per_c.keys():
		per_c[g0] = int(per_c[g0]) + int(S._stock_day.get(String(g0), 0))   # 当日尚未入账的那一截也已经到手了
	var dead_goods: Array = []
	var starved_goods: Array = []
	var gated_n := 0                                     # 真正进判决的货数（下限臂与上限臂共用同一批）
	var never_short: Array = []                          # 其中【全年一天都没断过】的那些
	for g in per_p:
		var gid := String(g)
		if bool(producible[gid]) and int(per_p[gid]) <= 0:
			dead_goods.append("%s(申报有产者·实产=0)" % gid)
		if not bool(demanded[gid]):
			continue                                     # 谁也不用的货：不要求它被消耗，也不谈满足率
		if int(per_c[gid]) <= 0:
			dead_goods.append("%s(申报有用途·实耗=0)" % gid)
			continue
		var dm := int(demand[gid])
		if dm < SUPPLY_MIN_DEMAND or days_run < SUPPLY_MIN_DAYS:
			continue                                     # 样本太小/horizon 太短：那时候的比率是噪声不是性质
		var rate := float(per_c[gid]) / float(dm)
		gated_n += 1
		if (sh_day[gid] as Dictionary).is_empty():
			never_short.append(gid)
		if rate < SUPPLY_FLOOR:
			starved_goods.append("%s 满足率=%.2f(到手%d/想要%d，断供%d/%d天)" % [
				gid, rate, int(per_c[gid]), dm, (sh_day[gid] as Dictionary).size(), days_run])
	# ── R1 上限臂：**缺货绝迹**（docs/68）──────────────────────────────────────────────
	# 由来：L2 在自己的回执里（docs/58 §四①）点名『缺货变得太少』是一个**没有任何门会报警**的回归——
	#   `work_pull` 把 N=60 上整洁的全年零缺货 seed 数从 0/12 推到 8/12、屋瓦 1/12 → 4/12，
	#   而 `production.json._calibration` 自己写的设计意图是「缺货【周期性】发生，不是恒常，**也不是从不**」。
	#   K1 的 nc3（批量 ×8）实测**照样绿** ⇒ 在此之前 #40 只有下限臂。本段是那条上限臂。
	#
	# ── 判据的形状：为什么是【全镇的多数】而不是逐货 ──────────────────────────────────
	# **逐货的上限臂在结构上不可能成立**，这是量出来的不是推的：未改动的出货阵容 N=12 上，
	#   豆子 7/12 · 整洁 5/12 · 话本 3/12 个 seed 全年零缺货（本棒 12 seed × 60 天实测）
	#   ⇒ 任何「每一种货都必须缺过」的判据在**未改动的出货树上当场红**。
	# ⇒ 只能判「这个镇整体还有没有稀缺」：`全年零缺货的货数 × 2 > 进判决的货数`（严格多数）。
	#   分母不写死 6、分子不写死 4 —— 它取的是当天**真正进了判决**的那些货，
	#   加一种货 / 摘一种货都自动跟着走（沿用下限臂那条「从数据自己的结构里推」的分档纪律）。
	#
	# ── 阈值的余量（docs/41 §5「收紧判据前先量余量」；全部 60 天 · backend=null · 无 LOD · ScaleSupply）──
	#   全年零缺货货数的逐 seed 极值（**并列一起报**），六种货、阈值=4：
	#     N=12 seeds 1-12   0..3   max 3 = seed 4                       余量 1 种货
	#     N=12 seeds 13-30  0..3   max 3 = seeds 14,30（**留出种子**）   余量 1 种货
	#     N=16 seeds 1-12   1..3   max 3 = seeds 3,6,7,11               余量 1 种货
	#     N=24 seeds 1-12   2..3   max 3 = seeds 2,3,4,8,10,11          余量 1 种货
	#     N=60 seeds 1-12   3..4   max 4 = seeds 2,3,4,5,7,8            **余量 −1：当场红**
	#   ⇒ CI 真正跑这条臂的两格（第 4 步 N=12、第 4a 步 N=16）各有【一种货】的余量，
	#     而且门是逐 seed 通过率制（软门容 1/12）⇒ 要假红得【两个】seed 同时越线；
	#     30 个 N=12 基线 seed（1-12 ∪ 13-30）里越线的个数是 **0**。
	#
	# ⚠ **它上线之后第一件事就是把 N=60 判红，而那【不是】假红。** 实测 N=60 seeds 1-12：
	#   豆子 12/12 与 话本 12/12 个 seed 全年零缺货（**这两条在 L2 改之前就已经是 12/12，不是 work_pull 造成的**），
	#   整洁与屋瓦才是 work_pull 推上来的那两条；四种同时不缺 ⇒ 六分之四 ⇒ 红。
	#   这正是 `_calibration` 那句话在 N=60 上不成立——**门只是第一次把它说出来了**。处置见 docs/68。
	#
	# ── 另外三个候选统计量都跑过、都被数据否掉（逐条记着，免得下一个人重跑）──────────────
	#   ① `最差货满足率 ≥ 上限`（下限臂的镜像）—— **否掉**：最差货那一格永远被「生产者最稀的那种货」钉住
	#      （柴薪只有杂役一个产者，60 天在班完成 1-11 次）。实测 amt8cap8 变异体下最差货最大只到 0.953，
	#      而**未改动的** N=60 seed 1 已经是 0.958 ⇒ 红绿两侧倒过来了，分不开。
	#   ② `全镇断供天数合计`—— **否掉**：它随人口单调下滑（未改动树：N=12 42..78 · N=16 28..53 ·
	#      N=24 18..36 · N=60 7..25），而变异体 amt8cap8@N=12 是 5..29 ⇒ **与未改动的 N=24 重叠**。
	#      用它等于按人口分档，正是 §0.5 点名要防的那个病。
	#   ③ `中位货满足率`—— **否掉**：未改动的树上 N=16/24/60 多数 seed 的中位数早就是 1.000，余量为零。
	#
	# ── 样本守卫 `gated_n >= 3` ──
	#   一两种货分不开「这个镇不再稀缺」与「我们只量了一两种货」（docs/41 §5：n 很小时读作"这个网格分辨不出"）。
	#   实测它在 DetGate(20 天) / BackendGate(8 天) 上恒生效：那里 `days_run < SUPPLY_MIN_DAYS`
	#   ⇒ 一种货都进不了判决 ⇒ `gated_n == 0` ⇒ 本臂整段不评估（与下限臂共用同一道 horizon 门）。
	var glut := ""
	if gated_n >= 3 and never_short.size() * 2 > gated_n:
		glut = "；【缺货绝迹】%d/%d 种货全年零缺货(%s) —— production.json._calibration 要的是【周期性】缺货，不是从不" % [
			never_short.size(), gated_n, ", ".join(never_short)]
	# ── S1 2026-08-01：【需求侧落点】——上限臂红了之后第二句要问的那件事（**只报不判**）────────
	# 由来：R1 把 N=60 的红分成两半，而"豆子/话本 12/12 全年零缺货"那一半的成因**不在产出侧**。
	# S1 把它量成了一条**结构**事实（S1Reach 探针，隔离副本，digest 与金标逐字节相同 3/3）：
	#   六种货里，**恰好那两种**在 `production.consume` 一侧【没有任何 town 平面的满足者】——
	#     喝咖啡 → 只有 `cafe1f_table@cafe/1f`；歇着 → 只有 `home1f_table@home/1f` + `home21f_table@home2/1f`
	#     其余四种（吃饭/赶集→口粮、洗澡→柴薪、睡觉→屋瓦、玩耍/社交→整洁）都有 town 平面的满足者。
	#   而克隆出来的 `npc_<i>` 没有 `spatial_address` ⇒ `home_space=="town"`、非 `cafe_regular`
	#   ⇒ `_journey_candidates` 的两个分支都取不到（(A) 要 `cafe_regular`；(B) 要 `aspace!="town" or home_space!="town"`）
	#   ⇒ **他们一辈子出不了 town 平面**。实测 60 天里"到过非-town 平面"的 agent 数（S1Reach 探针，逐 tick 逐 agent）：
	#     **N=12 → 9（0 克隆）· N=24 → 9（12 个克隆里 0 个）· N=60 → 9（48 个克隆里 0 个）**
	#     逐个点名恒是 aria/ben/coco/dan/evy/hai/lin/mei/tie ——**人口 ×5，这个数一个都没动。**
	#   ⇒ 这两种货的需求分母**按构造不随人口涨**（实测 N=12→N=60 需求比：豆子 ×1.00、话本 ×0.50，人口 ×5.00），
	#     而宏观池把它们的**产量**按人口 ×5 ⇒ 大 N 上"缺货绝迹"是**必然**，不是标定失手。
	# ⚠ **为什么只报不判**（docs/41 §5「收紧判据前先量余量」，量完之后决定不做）：
	#   任何形如「可达人数/人口 ≥ x」的判据在**今天这棵未修的树**上 N≥16 就是红的
	#   （豆子可达 4 人：4/12=0.333、4/16=0.250、4/60=0.067）⇒ 加它等于给出货树加一道当场红的门。
	#   把世界改到能过那道门的代价也量过了，**同样是否定的**：见 docs/72 §三（在 town 平面补落点的两个变体，
	#   实测 varA 把社交发起数压掉 35%、逐岗位在班完成动 ±50% ⇒ 它**不是**一条干净的需求侧改动）。
	var offtown: Array = []
	var objs = S.world.get("objects", {})
	if prod_on and not never_short.is_empty() and objs is Dictionary:
		for gid2 in never_short:
			var planes: Dictionary = {}
			for act2 in S.production.get("consume", {}):
				var crec2 = (S.production["consume"] as Dictionary)[String(act2)]
				if not (crec2 is Dictionary) or String((crec2 as Dictionary).get("good", "")) != String(gid2):
					continue
				for oid2 in objs:
					var o2 = objs[oid2]
					if not (o2 is Dictionary):
						continue
					for adv2 in (o2 as Dictionary).get("advertises", []):
						if adv2 is Dictionary and String((adv2 as Dictionary).get("action", "")) == String(act2):
							planes[String((o2 as Dictionary).get("space", "town"))] = true
			if not planes.is_empty() and not planes.has("town"):
				var pl: Array = planes.keys()
				pl.sort()
				offtown.append("%s(仅 %s)" % [String(gid2), "、".join(pl)])
	var reach := ""
	if not offtown.is_empty():
		reach = "；【需求侧落点】%s —— 这些货在 town 平面无满足者 ⇒ 只有进得了该平面的居民才产生需求，分母不随人口涨" % ", ".join(offtown)
	# ── K1：把【产出契约】写进 detail（**不是**分档，见上面的 K1 注释）──────────────────────
	# 判据在两种契约下**一个字节都不变**，所以这里只报不判。报它的理由是可读性：
	# 大 N 上看到一条红的 #40，第一句要问的就是"当时池开着没有、倍率是多少"，而那件事此前无处可读。
	# ── L2 同理追加【工作吸引力的人口项】（docs/58 §二）：同样**只报不判**。
	#    理由与 K1 那条逐字相同——大 N 上看到一条红的 #40，第二句要问的是"当时工作吸引力被抬了多少"。
	#    倍率恰为 1.0（出货阵容 N=12、或缺 work_pull 键）⇒ 这一截**不出现**，
	#    所以 N=12 的 detail 字符串与本次改动之前**逐字节相同**（金标/CI 的 detail 对照不受影响）。
	var contract := ""
	if prod_on:
		contract = "；产出契约=" + (("宏观池 ×%d/%d" % [int(S.prod_pool_num), int(S.prod_pool_den)])
			if bool(S.prod_pooled) else "逐笔")
		if float(S.work_pull_mult) != 1.0:
			contract += "｜工作吸引力 ×%.3f" % float(S.work_pull_mult)
	R.append(_chk(40, "产出闭环活性与供给充足",
		(not prod_on) or (n_prod > 0 and n_cons > 0 and dead_goods.is_empty()
			and starved_goods.is_empty() and glut == ""),
		"produce=%d consume=%d 满足率门%s%s%s%s%s" % [n_prod, n_cons,
			("下限=%.2f·上限=多数不缺" % SUPPLY_FLOOR) if days_run >= SUPPLY_MIN_DAYS else ("未启用(%d<%d天)" % [days_run, SUPPLY_MIN_DAYS]),
			"" if dead_goods.is_empty() else "；【断链货物】" + ", ".join(dead_goods),
			"" if starved_goods.is_empty() else "；【长期供不应求】" + ", ".join(starved_goods),
			glut + reach,
			contract]))

	# ── 41) V1 手艺的社会痕迹（docs/84）───────────────────────────────────────────
	# 守的是什么：**一门开了 `craft_credit` 的手艺，必须在【别人身上】留下痕迹；而没开的手艺不许留。**
	# 这条判据的名字里每一个词都有代码在查（docs/41 §2 第四个盲区，「合取式最容易只落一半」）：
	#   「开了的」→ ①produce 事件真的带上了目击者；②别人真的形成了 CR:<职位> 信念（via=seen、subject=本人）；
	#   「没开的」→ ④其余职位的 produce 事件 witnesses 必须**恒空**——这一臂才是牙：
	#             它抓的是"有人把目击者接成了全局副作用"，那会让"这是【一门】手艺的产出"这句话变成假的。
	# 豁免：`craft_credit` 缺键/空 ⇒ 恒过（off 门，与 `_prod_on` 同一套设计）；
	#       某职位在这一局产出次数 < CRAFT_MIN_WORKS ⇒ 该职位跳过（短 horizon 的定向场景里一次工都没上）。
	# ⚠ 明写它**不**查什么（跑出来的，见 docs/84 §五）：不查 `standing` 有没有真的动
	#   （把 `standing` 设成 0 ⇒ 本条全绿）；不查 claim 文案；不查 witnesses 里的人当时真的在场。
	var craft_tbl: Dictionary = S.production.get("craft_credit", {}) if prod_on and S.production.get("craft_credit", {}) is Dictionary else {}
	var craft_bad: Array = []
	var craft_note := "关"
	if not craft_tbl.is_empty():
		# 每个职位持有人 -> 他的 produce 事件数 / 带目击者的条数
		var pr_n: Dictionary = {}
		var pr_w: Dictionary = {}
		for e in log:
			if String(e.get("type", "")) != "produce":
				continue
			var aid := String(e.get("actor", ""))
			pr_n[aid] = int(pr_n.get(aid, 0)) + 1
			if (e.get("witnesses", []) as Array).size() > 0:
				pr_w[aid] = int(pr_w.get(aid, 0)) + 1
		var on_holders: Dictionary = {}          # holder id -> title（开了本机制的）
		for t in craft_tbl:
			var ti := String(t)
			if ti.begins_with("_"):
				continue                          # `_why` 之类的注释键
			var hid := String(S._holder_of_title(ti))
			if hid == "":
				continue
			on_holders[hid] = ti
		var parts: Array = []
		for hid2 in on_holders:
			var ti2: String = on_holders[hid2]
			var p := int(pr_n.get(hid2, 0))
			if p < CRAFT_MIN_WORKS:
				parts.append("%s:产出%d<%d(豁免)" % [ti2, p, CRAFT_MIN_WORKS])
				continue
			var w := int(pr_w.get(hid2, 0))
			if w <= 0:
				craft_bad.append("%s 产出%d次但【一次都没被看见】(witnesses 通道断了)" % [ti2, p])
			var bid := "CR:%s" % ti2
			var believers := 0                    # 一手（via=seen，亲眼看见他干活的人）
			var relayed := 0                      # 二手（via=gossip，听人说的）
			var wrong := 0
			for ag in S.agents:
				if not ag["beliefs"].has(bid):
					continue
				var b: Dictionary = ag["beliefs"][bid]
				var vv := String(b.get("via", ""))
				# ⚠ **本行是本棒自己的门抓出来的一次假红**（docs/84 §六②）：第一版写的是 `via != "seen" ⇒ 错`，
				#   而 `_commit_social` 的 gossip 分支会把这条信念转述出去、转述件的 via 恒为 "gossip"
				#   ——那是**本机制想要的行为**（手艺的名声传出去了），却被判成"来路不对"。
				#   seed 11 恰好发生了 3 次转述 ⇒ 门红。**判据本身错，不是机制错。**
				#   留住的那一半仍然有牙：`subject` 必须是本人（张冠李戴），`via` 必须是这两条合法路之一。
				if String(b.get("subject", "")) != hid2 or not (vv in ["seen", "gossip"]):
					wrong += 1
					continue
				if String(ag["id"]) == hid2:
					continue                      # 本人不该持有关于自己的这条（_craft_fallout 已排除）
				if vv == "seen":
					believers += 1
				else:
					relayed += 1
			if believers <= 0:
				craft_bad.append("%s 产出%d次·被看见%d次，却没有任何人【亲眼】形成 %s" % [ti2, p, w, bid])
			if wrong > 0:
				craft_bad.append("%s 有%d条 %s 的 subject/via 不对" % [ti2, wrong, bid])
			parts.append("%s:产出%d 被看见%d 知情%d人(其中转述%d)" % [ti2, p, w, believers + relayed, relayed])
		# ④ 反向臂：没开本机制的职位，produce 事件 witnesses 必须恒空
		var leaked: Array = []
		for aid2 in pr_w:
			if not on_holders.has(String(aid2)):
				leaked.append("%s(%d条)" % [String(aid2), int(pr_w[aid2])])
		if not leaked.is_empty():
			craft_bad.append("未开本机制的产者也带上了目击者：" + ", ".join(leaked))
		craft_note = "开[%s]" % "；".join(parts)
	R.append(_chk(41, "手艺的社会痕迹(被看见·被知道·不外溢)", craft_bad.is_empty(),
		"craft_credit=%s%s" % [craft_note, "" if craft_bad.is_empty() else "；【异常】" + "；".join(craft_bad)]))
	# 42) ★Z1：生存推力（Sim._survival_pull）的三道收窄仍然成立。判据是【结构】，与 seed / 世界演化无关。
	R.append(_survival_pull_narrowing(S))

	# ── 43) AA3 买卖的社会痕迹（docs/106）────────────────────────────────────────
	# 守的是什么：**开了 `vendor.trade_credit` 的那条人→人货款，必须在【别人身上】留下痕迹；
	#             而其余的钱不许留。**
	# 名字里每一个词都有代码在查（docs/41 §2 第四个盲区，「合取式最容易只落一半」）：
	#   「被看见」→ ①商贩那条 `pay`(note=`buy:<赶集>`) 事件真的带上了目击者；
	#   「被知道」→ ②真的有人**亲眼**形成 `TR:<职位>`（subject=商贩、via∈{seen,gossip}，且至少一条 seen）；
	#   「不外溢」→ ③**其余每一条 `pay` 事件的 `witnesses` 必须恒空**——这一臂才是牙：
	#             `transfer` 是全镇钱的唯一通道（工资/房租/镇库收费全走它），
	#             谁把目击者接成 `transfer` 的全局副作用，"这是【买卖】留下的痕迹"这句话当场变成假的。
	# 豁免：`trade_credit` 缺键/空 ⇒ 恒过（off 门，同 `_prod_on` / `craft_credit` 那一套）；
	#       镇上没有现任商贩 ⇒ 恒过（`_holder_of_title` 返回 ""，与 `Sim._market_open` 同一条口径）；
	#       本局的人→人成交 < `TRADE_MIN_SALES` ⇒ 跳过①②（短 horizon / 随机后端里可能一笔都没成交）。
	# ⚠ 明写它**不**查什么（跑出来的，见 docs/106 §五）：不查 `standing` 有没有真的动；
	#   不查那句中文；不查目击者当时真的在场；**也不查商贩本人在不在场**——
	#   而最后这一条是**故意的**：实测他只在 19-24% 的成交里与买家同区（docs/106 §一），
	#   把"他在场"写进判据等于给这道门装一条余量 3、被零假设臂就能压穿的臂。
	#   ★AA3-FIX（docs/112）："不查他在场"≠"他自己算目击者"。①的 sales_w 现在只数
	#   【商贩以外】的目击者（见下面 wn_other）——修的是"一笔只被商贩自己看见的成交
	#   也算被看见"这个自证软点（改前实测 40/715 笔、逐 seed 1-6）。
	var vend_tbl: Dictionary = S.production.get("vendor", {}) if prod_on and S.production.get("vendor", {}) is Dictionary else {}
	var tc_tbl: Dictionary = vend_tbl.get("trade_credit", {}) if vend_tbl.get("trade_credit", {}) is Dictionary else {}
	var trade_bad: Array = []
	var trade_note := "关"
	if not tc_tbl.is_empty():
		var v_title := String(vend_tbl.get("title", ""))
		var v_id := String(S._holder_of_title(v_title))
		var buy_note := "buy:" + String(vend_tbl.get("action", ""))
		var sales := 0                        # 人→人的成交（钱真的进了商贩口袋）
		var sales_w := 0                      # 其中带目击者的
		var spill: Dictionary = {}            # note -> 条数：**不是**买卖、却带了目击者的 pay 事件
		for e in log:
			if String(e.get("type", "")) != "pay":
				continue
			var wits43: Array = e.get("witnesses", []) as Array
			var wn := wits43.size()
			if v_id != "" and String(e.get("note", "")) == buy_note and String(e.get("target", "")) == v_id:
				sales += 1
				# ★AA3-FIX（docs/112）防御纵深："被看见"只数【商贩以外】的目击者。
				#   采集侧（Sim.gd 的 twits 过滤）已经不把商贩写进 witnesses 了；这里再挡一道：
				#   即使将来采集侧被改回，一笔只被商贩自己"看见"的成交也不再计入 sales_w
				#   ⇒ 这条臂不会被自证喂绿。负对照（docs/112 §四.2）：把过滤撤掉 + 全部
				#   witnesses 换成 [商贩] ⇒ 旧判据(wn>0)恒绿、本判据 sales_w=0 ⇒ 红。
				var wn_other := 0
				for w43 in wits43:
					if String(w43) != v_id:
						wn_other += 1
				if wn_other > 0:
					sales_w += 1
			elif wn > 0:
				var nk := String(e.get("note", ""))
				spill[nk] = int(spill.get(nk, 0)) + 1
		# ③ 反向臂：先查，且**不受豁免线保护**——它守的是整本账，与商贩今天卖没卖出去无关。
		if not spill.is_empty():
			var sp: Array = []
			for nk2 in spill:
				sp.append("%s(%d条)" % [String(nk2), int(spill[nk2])])
			trade_bad.append("不是买卖的钱也带上了目击者：" + ", ".join(sp))
		if v_id == "":
			trade_note = "开[镇上没有现任%s ⇒ 豁免]" % v_title
		elif sales < TRADE_MIN_SALES:
			trade_note = "开[%s:人→人成交%d<%d(豁免)]" % [v_title, sales, TRADE_MIN_SALES]
		else:
			if sales_w <= 0:
				trade_bad.append("%s 成交%d笔但【一笔都没被看见】(pay 的 witnesses 通道断了)" % [v_title, sales])
			var bid2 := "TR:%s" % v_title
			var believers2 := 0               # 一手（亲眼在摊前）
			var relayed2 := 0                 # 二手（听人说的）
			var wrong2 := 0
			for ag2 in S.agents:
				if not ag2["beliefs"].has(bid2):
					continue
				var b2: Dictionary = ag2["beliefs"][bid2]
				var vv2 := String(b2.get("via", ""))
				# via 的两条合法路与 #41 同一条（`_commit_social` 的 gossip 分支会把它转述出去，
				# 那是**想要的行为**——docs/84 §六② 那次假红的教训直接照抄，不重踩）。
				if String(b2.get("subject", "")) != v_id or not (vv2 in ["seen", "gossip"]):
					wrong2 += 1
					continue
				if String(ag2["id"]) == v_id:
					continue                  # 商贩自己不该持有关于自己的这条（_trade_fallout 已排除）
				if vv2 == "seen":
					believers2 += 1
				else:
					relayed2 += 1
			if believers2 <= 0:
				trade_bad.append("%s 成交%d笔·被看见%d笔，却没有任何人【亲眼】形成 %s" % [v_title, sales, sales_w, bid2])
			if wrong2 > 0:
				trade_bad.append("%s 有%d条 %s 的 subject/via 不对" % [v_title, wrong2, bid2])
			trade_note = "开[%s:成交%d 被看见%d 知情%d人(其中转述%d)]" % [v_title, sales, sales_w, believers2 + relayed2, relayed2]
	R.append(_chk(43, "买卖的社会痕迹(被看见·被知道·不外溢)", trade_bad.is_empty(),
		"trade_credit=%s%s" % [trade_note, "" if trade_bad.is_empty() else "；【异常】" + "；".join(trade_bad)]))
	return R

## #42 的 `cur` 网格。全部严格小于 `SURVIVAL_GATE`——本项在 `cur >= GATE` 处按构造（`maxf(0, GATE-cur)`）
## 恒为 0，拿那一段当探针等于在探一个恒真的性质。0.1 与 35.9 是两端的贴边点。
const SP_CUR_GRID := [0.0, 0.1, 9.0, 18.0, 27.0, 35.9]
## #42 的 argmin 臂网格：`[cur, min_need]` 且 **cur > min_need ≥ 0**（= social 不是 argmin），此时本项必须恒 0。
const SP_ARGMIN_GRID := [[9.0, 0.0], [18.0, 9.0], [27.0, 18.0], [35.9, 27.0], [35.9, 0.0], [0.1, 0.0]]

## ★Z1（编号 100）：给 `Sim._survival_pull` 的三道收窄补一道门。
##
## 【为什么需要】Y1（docs/96 §七 `does_not_detect` ⑦）拿四个变异体逐个跑过：
##   删掉整项 ⇒ `DetGate` 红 · 把 social 守卫**取反** ⇒ `DetGate` 红 ·
##   **放宽到全部 need ⇒ 全 CI 绿** · **剂量翻倍到 k=2.0 ⇒ `DetGate` 绿**。
##   ⇒ 后两道收窄今天只由 `Sim._survival_pull` 抬头的注释维护，**没有任何机器在查**。本条把它们变成机检。
##
## 【判据为什么可以是【结构】的，不是统计的】本项只在 `social == argmin < SURVIVAL_GATE` 时非零，
##   而那一刻 `mods_ok = (min_need >= SURVIVAL_GATE)` **恒为 false** ⇒ `Sim._object_candidates` 里
##   rhythm / weather / season / cleanliness / work_pull / stock_pull **六个乘子全部关闭**
##   ⇒ 它所修饰的那条广告的收益恰好是未打折的 `urgency * amount / 60`。
##   ⇒ 「推力上限 vs 它所修饰的那个分数」这个比值可以**精确算出来**，不含 seed / 天数 / 世界演化。
##   这也是本条为什么归**硬**档：它是代码+数据的结构性质，任何 LOD / 规模 / 场景下都必须为真。
##
## 【三条臂】
##   A **只对 social**：对 `needs_def` 里**每一条**非 social 的 need，在 `cur == min` 的整条网格上必须恒 0。
##   B **只在 argmin**：social 但 `cur > min_need` 时必须恒 0。
##   C **不反客为主**：`推力上限 = _survival_pull("social", 0, 0)` 必须 **<** 全镇【最弱】那条 social 广告
##     在 `cur=0` 处的基准收益。这一条逐字就是 Y1 选出货剂量时那条**承重**论证
##     （docs/96 §二.4 第 2 条：「这一项的上限 36k 不该超过它所修饰的那个分数本身」），而它此前没有任何机器在查。
##
## 【余量是量出来的，不是拍的】HEAD 这棵树（`_z1_probe` 实测）：`k=1.000`、`SURVIVAL_GATE=36` ⇒ 上限 **36.00**；
##   世界里恰好 3 条 social 广告——`counter_1(吧台·闲聊·42)` → 70.00、`bench_1(长椅·社交·40)` → 66.67、
##   `cafe1f_counter(咖啡吧台·闲聊·40)` → 66.67 ⇒ 最弱 **66.67** ⇒ **比值 0.5400，门在 1.0，余量 1.852×**。
##   ⇒ Y1 的「剂量翻倍」变异体 k=2.0 ⇒ 上限 72.00 ⇒ 比值 **1.0800 ≥ 1.0 ⇒ 红**。
##   ⚠ **门咬的位置是 k ≥ 1.852，不是 k > 1.0**：`k ∈ (1.5, 1.852)` 这一段本条**抓不到**（写进包络）。
##
## 【本项未启用时本条无判别力，且必须照实说】`k == 0`（缺键/为 0 —— 那条"缺键即零扰动"的 ablation 路）
##   ⇒ 三条臂全部**平凡**成立。detail 里明写「本条此跑无判别力」，**不打绿勾骗人**
##   ——与本波 ① 那条（`Harness` 没传 `--golden` 却印「金标 过」）是同一条纪律。
static func _survival_pull_narrowing(S) -> Dictionary:
	var bad: Array = []
	var k: float = float(S._w("obj_survival_pull", 0.0))
	# ── A：只对 social ──
	var probed_needs := 0
	for nd in S.needs_def:
		var nid := String((nd as Dictionary).get("id", ""))
		if nid == "" or nid == "social":
			continue
		probed_needs += 1
		for cur in SP_CUR_GRID:
			var v: float = float(S._survival_pull(nid, float(cur), float(cur)))
			if v != 0.0:
				bad.append("A 越界到非 social：need=%s cur=min=%.2f 得 %.4f（应 0）" % [nid, float(cur), v])
				break
	# ── B：只在 social 就是 argmin 时 ──
	for pr in SP_ARGMIN_GRID:
		var c2: float = float((pr as Array)[0])
		var m2: float = float((pr as Array)[1])
		var v2: float = float(S._survival_pull("social", c2, m2))
		if v2 != 0.0:
			bad.append("B 越过 argmin 门：social cur=%.2f > min=%.2f 却得 %.4f（应 0）" % [c2, m2, v2])
			break
	# ── C：剂量不得反客为主（上限与基准收益都是【现读现算】，不写死数字）──
	var ceil_pull: float = float(S._survival_pull("social", 0.0, 0.0))   # = maxf(0, GATE-0) * k
	var weakest := -1.0
	var weakest_id := ""
	var n_ads := 0
	var objs: Dictionary = S.world.get("objects", {})
	for oid in objs:
		var o: Dictionary = objs[oid]
		for adv in o.get("advertises", []):
			if not (adv is Dictionary):
				continue
			if String(adv.get("need", "")) != "social":
				continue
			var amt := int(adv.get("amount", 0))
			if amt <= 0:
				continue                     # amount<=0 的广告 _object_candidates 自己就 continue 掉了
			n_ads += 1
			var b0: float = 100.0 * float(amt) / 60.0   # cur=0 ⇒ urgency=100；六个乘子按构造全关（见抬头）
			if weakest < 0.0 or b0 < weakest:
				weakest = b0
				weakest_id = "%s(%s·%s·%d)" % [String(oid), String(o.get("type", "")),
					String(adv.get("action", "")), amt]
	var ratio := -1.0
	if n_ads > 0 and weakest > 0.0:
		ratio = ceil_pull / weakest
		if ratio >= 1.0:
			bad.append("C 剂量反客为主：推力上限 %.4f ≥ 最弱 social 广告基准收益 %.4f[%s]，比值 %.4f（门 <1.0）"
				% [ceil_pull, weakest, weakest_id, ratio])
	# ── detail：四种"本跑没有判别力"的情形都必须自己说出来（k=0 / 上限=0 / 无 social 广告 / 无非-social need）──
	# ⚠ 而且要说在【名字】里，不能只说在 detail 里：Harness 的不变量表只在**失败**时才印 detail
	#   ⇒ 一条"本跑什么都没判"的条目会以一个**光秃秃的绿勾**出现在表上，正是本波要修的那个形状
	#   （`Harness` 没传 --golden 却印「金标 过」/ 单 seed 软门恒过却打 ✅，84bd95d）。
	#   名字里带标记 ⇒ 表上直接读得到。
	var detail := ""
	var vac: Array = []
	if k == 0.0:
		vac.append("k=0·未启用")
		detail = "k=0 ⇒ 本项未启用(缺键即零扰动那条 ablation 路)·三臂平凡成立·【本条此跑无判别力】"
	elif ceil_pull == 0.0:
		# k 不为 0，上限却是 0 ⇒ 函数体被短路成恒 0（或 SURVIVAL_GATE 被改成 0）。
		# 三条臂此时**全部平凡成立**，而 k!=0 又骗过了上面那一格 ⇒ 不标出来就是一个静默的洞。
		vac.append("上限=0·本项已被短路")
		detail = "k=%.3f 但推力上限=0 ⇒ 本项已被短路成恒 0(或 SURVIVAL_GATE=0)·三臂平凡成立·【本条此跑无判别力】" % k
	elif n_ads <= 0:
		vac.append("C臂无social广告")
		detail = "k=%.3f 上限=%.2f · A 探 %d 条非 social need × %d 格 · 【C 臂无判别力：世界里 0 条 social 广告】" % [
			k, ceil_pull, probed_needs, SP_CUR_GRID.size()]
	else:
		detail = "k=%.3f 上限=%.2f · 最弱 social 广告 %s 基准收益 %.2f · 比值 %.4f(门<1.0，余量 %.3f×) · A 探 %d 条非 social need × %d 格 · B %d 对" % [
			k, ceil_pull, weakest_id, weakest, ratio, (1.0 / ratio) if ratio > 0.0 else 0.0,
			probed_needs, SP_CUR_GRID.size(), SP_ARGMIN_GRID.size()]
	if probed_needs <= 0:
		vac.append("A臂无非social需求")
		detail += " ·【A 臂无判别力：needs_def 里没有非 social 的 need】"
	if not bad.is_empty():
		detail += "；【异常】" + "；".join(bad)
	var nm := "生存推力的收窄(只 social·只 argmin·不反客为主)"
	if not vac.is_empty():
		nm += "【本跑无判别力：%s】" % ",".join(vac)
	return _chk(42, nm, bad.is_empty(), detail)

## 事件发生【当时】的相位（不是检查时的相位）。#39 的「在班」那一半靠它。
## 为什么不能直接调 Sim._in_shift：它读的是 time_of_day() = f(当前 tick_no)，
## 而我们要判的是【历史事件那一刻】的班次 —— 用事件自带的 tick 重算。
static func _phase_at(S, tick: int) -> String:
	if tick < 0:
		return ""
	var tpd := int(S.TICKS_PER_DAY)
	if tpd <= 0:
		return ""
	return String(S._phase_of(float(tick % tpd) / float(tpd)))

static func _shift_ok_at(S, job: Dictionary, tick: int) -> bool:
	var sh: Array = job.get("shift", [])
	if sh.is_empty():
		return true                      # 无班次 = 全天，与 Sim._in_shift 同口径
	var ph := _phase_at(S, tick)
	return ph == "" or ph in sh       # 相位表查不到时不冤枉它，同 Sim._in_shift

## 库存事件的 note 编码 "<原因>*<件数>" → 件数（Sim._stock_move 写、本文件读；对不上就是 0 → #38 会红）。
static func _amt_of(note: String) -> int:
	var i := note.rfind("*")
	return int(note.substr(i + 1)) if i >= 0 else 0

static func _chk(id: int, name: String, ok: bool, detail: String) -> Dictionary:
	return {"id": id, "name": name, "ok": ok, "detail": detail, "hard": id in HARD_IDS}

## L4 不变量两分（docs/12 §L4）：
##  · 硬（结构）= 状态合法性/可溯源/边界/生命周期合法性。任何 LOD/规模/激进降频下都必须为真——
##    冻结一个远端 agent 不会让它的状态变非法，只是不再产生涌现行为。
##  · 软（涌现统计）= 需要活动才会显现的量（社交发生、分化、放逐锐利度、观点演化…），
##    已按 场景/大N 豁免；激进 LOD 下远端=背景群演，软不变量按设计会漂。
## 消费方：激进 LOD 门只查硬不变量（split_fails().hard==0）；soak/Harness 仍查【全部】条目（不写死条数，见文件头）。
## Wave E 追加：#38/#39 是硬（结构：账本自洽/产出可溯源，任何 LOD/规模下都必须为真）；
##   #40 是软（活性=涌现统计：短 horizon 的定向场景里产出可能一次都没发生，硬断言会误红）。
##   H5 把 #40 从存在性升级为供给充足度之后，它**仍然是软**，而且理由更强了一条：
##   满足率的基线最小值（30 个 seed）是 **0.569**、阈值 0.50，单格余量只有 **1.14×**
##   —— 这个宽度撑不起"每 seed 必绿"的硬断言。软门的"12 个 seed 容 1 个"正是留给这道余量的
##   （要改硬，先把单格余量量到 2× 以上；今天没有）。
## V1：#41 入硬档。理由与 #38/#39 同一条——它查的是**结构**（通道接没接上、有没有外溢），
## 不是涌现统计；而"产出次数 < CRAFT_MIN_WORKS 就跳过"这条豁免已经把短 horizon / 定向场景兜住了。
## Z1：#42 入硬档。理由与 #38/#39/#41 同一条——它查的是**结构**（一个加分项的作用面与量级），
##   而且比它们更硬一格：它**完全不读 event_log、不读世界演化**，只读代码+数据，
##   在任何 seed / 天数 / LOD / 场景下逐字节同一个判决 ⇒ 结构上不存在"涌现统计漂了"这种假红。
##   ⚠ 它有**四条**真实的失去判别力的路（`k==0` 的 ablation、上限被短路成 0、世界里没有 social 广告、
##     `needs_def` 里没有非-social need），而它们**由条目自己的【名字】报出来**（不是只写在 detail 里
##     ——不变量表只在失败时印 detail），不靠人记得。前两条各有一个跑过的变异体（编号 100 §二.3 的 M4 / M8）。
## AA3：#43 入硬档。理由与 #38/#39/#41 同一条——它查的是**结构**（消费侧那条通道接没接上、
##   有没有把目击者接成 `transfer` 的全局副作用），不是涌现统计；而"人→人成交 < TRADE_MIN_SALES
##   就跳过"这条豁免已经把短 horizon / 随机后端 / 定向场景兜住了。
const HARD_IDS := [1, 6, 7, 9, 10, 12, 13, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41, 42, 43]

## #41 的豁免线：一局里该职位的 produce 事件少于这么多次就跳过它。
## 5 是量出来的下界，不是拍的：N=12 × 60 天 × 12 seed，环卫工的 produce 事件是 19..31 条
## （最小 19，余量 19/5 = 3.8×）；而 DetGate 的 20 天 / ModelPathGate 的 8 天 / scenarios 的短局
## 本来就上不满 5 次工 ⇒ 结构上不会误红。
const CRAFT_MIN_WORKS := 5

## #43 的豁免线：一局里【人→人】的成交（钱真的进了商贩口袋）少于这么多笔就跳过①②。
## 5 与 `CRAFT_MIN_WORKS` 同值，而它同样是量出来的下界（`game/bench/aa3_vendor_census.gd`，9 格 108 局）：
## **本门真正吃的那个量**是「钱真到手 且 当场有旁人」的条数，它的九格最小值是 **13**
## （N=12 seeds 1-12 20 天 seed 2；零假设臂 obj_dist_penalty 0.400→0.401 在同一格给出**同样的 13**
##  ⇒ 这个余量是性质，不是巧合）。成交数本身的九格最小值是 15 ⇒ 余量 15/5 = 3×。
## ⚠ 与 #41 那条豁免线的**区别要写清**：#41 那条兜的是"短局里一次工都没上"，
##   本条兜的是"短局 / 随机后端里一笔都没成交"——BackendGate 的 30 天与 ModelPathGate 的 8 天
##   走的是 `random` 后端，赶集的频次与 logic 地板不可比，**那两格的成交数我没有单独量过**（docs/106 §十）。
const TRADE_MIN_SALES := 5

## 第三档：诊断（DIAGNOSTIC）——【报告但永不成门】（既不入 hard_red 也不入 soft_red）。
## 收录标准只有一条：该指标本身已被证明是度量伪影，把它做成门就是在给噪声上锁。
##  · #15 涌现放逐：终态 standing × 全程接受率 = 时间泄漏；修正版 #15v2 在 126 个 held-out seed 上
##    INCONCLUSIVE，docs/31-15-resolution.md 已决定不落机制、不设门。实测 seeds 1-24 × 60d 下它是
##    唯一破软门的项（22/24），把整个软容差预算全吃掉——正是「不该为噪声付预算」的教科书例子。
const DIAG_IDS := [15]

## ⚠ 诊断档(DIAG_IDS，现为 #15)【不计入 soft】：Harness/DetGate/LodAblation 各自都已跳过它，唯独本函数
## 还把它算作软失败——任何新消费方照此把门就会被一个【已知有时间泄漏、docs/31 判定无效】的指标拖红。
## 单列 diag 桶：既堵住这个陷阱，又不丢信息。（LodAblation 自算 fh/fs 不走本函数 → 既有门判定不受影响。）
static func split_fails(S, starved: int, starve_by_need: Dictionary = {}) -> Dictionary:
	var hard := 0
	var soft := 0
	var diag := 0
	for c in check_all(S, starved, starve_by_need):
		if bool(c["ok"]):
			continue
		if int(c["id"]) in DIAG_IDS: diag += 1
		elif bool(c["hard"]): hard += 1
		else: soft += 1
	return {"hard": hard, "soft": soft, "diag": diag}

## event_log 确定性摘要：同 seed 两跑应得同一值（覆盖 id/类型/双方/接受/主题/时刻 + 见证人 + note）。
## ⚠ 为什么要多覆盖 witnesses/note：Sim._log_event 的滚动 event_digest（Sim.gd:2603）折的是
##   "id:type:actor:target:accepted:subject:tick" —— 与本函数原先【逐字符相同】的串。也就是说
##   Harness 号称的「双独立见证」其实是同一个见证人被哈希了两遍，等价于只有一路证据。
##   witnesses（旁观者集合，决定 _judge_actor 的声誉扩散）与 note 都是语义承重的：
##     · #36 靠 note 分 spawn/despawn（本文件 `== "spawn"` / `== "despawn"` 那两行，现 :383-384）
##     · #30 靠 note=="dissolved:freerider" 溯源（现 :338）
##   ⚠ 上面这两个行号在 2026-07-30 被查出【都是过期的】（原写 :345-346 / :300，实际差三四十行），
##     同一天还查出 Harness.gd:41 引本文件 #29/#34/#35 的三个行号也全过期。
##     行号是本文件里最容易腐烂的一类事实：任何人在上面插一行，下面每一条引用都错。**引符号，别引行号。**
##   把它们并入本摘要后，两路摘要覆盖的字段集才真正不同 → 双见证名副其实。
static func digest(S) -> int:
	var parts := PackedStringArray()
	for e in S.event_log:
		var wits: Array = e.get("witnesses", [])
		var wstr := ""
		for i in wits.size():
			if i > 0: wstr += ","
			wstr += String(wits[i])
		parts.append("%d:%s:%s:%s:%d:%s:%d:%s:%s" % [
			int(e.get("id", 0)), String(e.get("type", "")), String(e.get("actor", "")),
			String(e.get("target", "")), int(bool(e.get("accepted", false))),
			String(e.get("subject", "")), int(e.get("tick", 0)),
			wstr, String(e.get("note", ""))])
	# ★用【项目自有】Sim.fnv1a32 而不是引擎的 String.hash()：金标的每一个数字都必须由本仓库的源码定义，
	#   否则 Godot 升级换一次内部哈希实现，全部金标一起漂，而行为其实一个字节没变（红线#1 假红/假绿两头都占）。
	return SimScript.fnv1a32("|".join(parts))

# ── 逐 tick 前缀哈希链（B9）────────────────────────────────────────────────
## 为什么终态摘要不够：digest / event_digest 都是【全程汇总】。
##   1) 中途分叉、末尾又合流的轨迹（LOD 生存兜底、承诺 pre-empt、需求钳位这类"自愈"路径）
##      能把差异抹平 → 终态一致 → 静默漏过；
##   2) 就算它们红了，也只会说「不一样」，说不出【第一个不一样的 tick】——排查得靠人肉二分。
## 前缀链 H_t = h(H_{t-1} ‖ canon_state_t ‖ canon_events_t)：任一 tick 出现差异，此后每个 H 都不同，
## 且逐 tick 留痕 → 能报出首个分叉 tick（见 Harness 的 --chain-dump / --chain-ref 与金标 chain_ck）。
##
## canon_state 取【会驱动后续决策的活状态】：位置、需求（定点量化）、说话中、当前 option 签名。
## 需求量化到 1/65536：远细于任何真实行为差异（need 一步至少 0.01 量级），又挡住 float 末位噪声的假红。
const CHAIN_INIT := 2166136261        # = Sim.HASH_OFFSET32
const CHAIN_NEED_Q := 65536.0

static func chain_step(prev: int, S, ev_from: int) -> int:
	var h: int = prev
	h = SimScript.mix32(h, int(S.tick_no))
	for ag in S.agents:
		h = SimScript.mix32(h, S._aid(ag))                    # id（走 Sim 的缓存，热路径不重算哈希）
		var p: Vector2i = ag["pos"]
		h = SimScript.mix32(h, int(p.x) * 65536 + int(p.y))
		for nid in ag["needs"]:                               # Dictionary 保序（插入序）→ 确定
			h = SimScript.mix32(h, int(round(float(ag["needs"][nid]) * CHAIN_NEED_Q)))
		h = SimScript.mix32(h, int(ag.get("talking", 0)))
		var opt = ag["option"]
		if opt is Dictionary:
			h = SimScript.fnv1a32_into(h, "%s|%s|%s|%s|%s|%s" % [
				str(opt.get("kind", "")), str(opt.get("target", "")), str(opt.get("partner", "")),
				str(opt.get("area", "")), str(opt.get("phase", "")), str(opt.get("remaining", ""))])
		else:
			h = SimScript.mix32(h, -1)
	for i in range(ev_from, S.event_log.size()):              # 本 tick 新产生的事件（canon_events_t）
		var e: Dictionary = S.event_log[i]
		h = SimScript.fnv1a32_into(h, "%d:%s:%s:%s:%d:%s:%s" % [
			int(e.get("id", 0)), String(e.get("type", "")), String(e.get("actor", "")),
			String(e.get("target", "")), int(bool(e.get("accepted", false))),
			String(e.get("subject", "")), String(e.get("note", ""))])
	return h
