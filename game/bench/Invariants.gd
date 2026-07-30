extends RefCounted
class_name BenchInvariants
## preload 而非全局类名/autoload：--script 的 _init() 阶段 autoload 尚未挂上（docs/41 §2 更正：autoload 其实是加载的）（同 Sim.gd 顶部的纪律）。
## 只用它的【静态】哈希（fnv1a32/mix32）——不实例化、不持有状态。
const SimScript = preload("res://scripts/Sim.gd")
## bench/Invariants.gd — 把「确定性社交底座」的机检不变量抽成单一真相源（语义照搬 sim_soak.gd / sim_social_port.mjs）。
## 条数：**40**（= 本文件里 `R.append(_chk(` 的条数，`grep -c` 即得）。
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
##    ⚠ 真正的余量比上面这两个数大，因为门是【逐 seed 通过率】制：要假红得【两个】seed 同时跌破，
##      而 30 个基线 seed 里跌破的个数是 **0**；反过来 thr_book/thr_bean 是 30/30 个 seed 全跌破。
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

## starve_by_need：可选的逐 need 明细，**只进 detail 字符串，不进任何判据**（默认 {} ⇒ 8 个既有调用点
## 一个字节不用改，输出也与改名前逐字相同）。今天只有 Harness 传它。
static func check_all(S, starved: int, starve_by_need: Dictionary = {}) -> Array:
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
		"触底 need·tick=%d%s (应=0;场景豁免)" % [starved, _need_breakdown(starve_by_need)]))
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
	var r1 := []
	for ag in S.agents:
		if ag["beliefs"].has("R1"):
			r1.append(ag["id"])
	R.append(_chk(5, "谣言传播", r1.size() >= 2 or not harmony or not small_n, "知道 R1=[%s] (应≥2;场景/大N豁免)" % ", ".join(r1)))
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
	var fac_inc := 0
	for ag in S.agents:
		if (String(ag["faction"]) == "") != (int(ag["faction_size"]) == 1): fac_inc += 1
		if String(ag["faction"]) != "" and String(ag["faction"]) != String(ag["id"]) and not S._aligned(ag, S._agent_by_id[ag["faction"]]): fac_inc += 1
	R.append(_chk(25, "S3派系派生一致", fac_inc == 0, "不一致=%d (应=0)" % fac_inc))
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
	#          掐产量不归零的六个变异体：被掐那种货 0.069-0.415（1-12）、最高 0.488（thr_book 的 13-30）
	#        ⇒ 分界带是 [0.488, 0.569]，取 **0.50**。
	#        而且门是【逐 seed 通过率】制（软门容 1/12）⇒ 要假红得有【两个】seed 同时跌破，
	#        30 个基线 seed 里跌破的个数是 **0**；而 thr_book / thr_bean 是 **30/30 个 seed 全跌破**。
	#     ⚠ 为什么不用【缺货天数占比】（第一版就是它，被自己的数据否掉）：它随需求密度漂——
	#        基线最大 0.467（屋瓦 seed 7），而把话本产量掐掉 83% 之后只有 0.300-0.600
	#        ⇒ **不存在能同时分开这两组的阈值**。留作 detail 里的诊断数字，不作判据。
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
		if rate < SUPPLY_FLOOR:
			starved_goods.append("%s 满足率=%.2f(到手%d/想要%d，断供%d/%d天)" % [
				gid, rate, int(per_c[gid]), dm, (sh_day[gid] as Dictionary).size(), days_run])
	R.append(_chk(40, "产出闭环活性与供给充足",
		(not prod_on) or (n_prod > 0 and n_cons > 0 and dead_goods.is_empty() and starved_goods.is_empty()),
		"produce=%d consume=%d 满足率门%s%s%s" % [n_prod, n_cons,
			("下限=%.2f" % SUPPLY_FLOOR) if days_run >= SUPPLY_MIN_DAYS else ("未启用(%d<%d天)" % [days_run, SUPPLY_MIN_DAYS]),
			"" if dead_goods.is_empty() else "；【断链货物】" + ", ".join(dead_goods),
			"" if starved_goods.is_empty() else "；【长期供不应求】" + ", ".join(starved_goods)]))
	return R

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
const HARD_IDS := [1, 6, 7, 9, 10, 12, 13, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39]

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
