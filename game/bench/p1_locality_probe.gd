extends SceneTree
## bench/p1_locality_probe.gd —— P1「知识局部性 epistemic locality」只读探针（docs/63）
##
## 问的问题（docs/62 §一 外审原话）：
##   「如果 B 镇居民虽然尚未收到消息，但决策时仍能读取全局事件/全局 standing/全局事实表，
##     那么『某人运消息』只是一层演出。」
## ⇒ 本探针不造第二个镇、不改任何仓库文件、不写 game/scripts 与 game/data。
##   它只做一件事：**往世界里塞一条只有一个人知道的事实，然后看别人会不会因此改变行为。**
##
## 判别原理（本仓库特有的一条便利，先说清楚否则结果不可读）：
##   `_logic_decide` 的平局抖动盐取自候选的【稳定身份】`_cand_salt(c)`，`_rng_at` 又是**无状态**的
##   （由 (seed,tick,salt,who) 纯播种）⇒ **给 A 的候选表多加一条候选，不会扰动 A 的其它候选、
##   更不会扰动 B 的任何一次掷骰。** `_acceptance_margin` 的抖动同理（`_rng_at(31,_aid(target))`）。
##   ⇒ 两臂之间的差异集 **恰好等于因果锥**，没有 RNG 流错位造成的假分叉。
##   这一条是本探针能做"逐字节"判决的前提，也是它比一般的 A/B 更锋利的原因。
##
## 用法（headless，--script 模式；不加载 autoload 的数据，故照 Harness 显式 _load_data）：
##   godot --headless --path game --script bench/p1_locality_probe.gd -- --seed 1 --days 30 --n 20

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")
const SimExt = preload("res://scripts/SimExtensions.gd")

const FACT := "P1FACT"

var seed_base := 1
var days := 30
var n_agents := 20
var t0 := 1200          # 注入时刻（第 5 天开头）
var delay := 480        # 「延迟两天」

# ── ext 挂点：接受修正器（AcceptanceModifier 鸭子契约：id() / modify()）──────
## 空修正器：注册了 ext 但一分不改 —— 用来证明「挂上 ext 这件事本身」不移动轨迹。
class NullModifier:
	extends RefCounted
	func id() -> String: return "p1_null"
	func modify(_S, _actor, _target, _action, _subject) -> float: return 0.0

## ★负对照（本探针的牙）：一个【蓄意的全局事实读】。
##   它不看 actor 知不知道、不看 target 知不知道，只问"这镇上**有没有人**知道 P1FACT"。
##   这正是外审担心的那种形状：行为已经知道事实，而日志晚几天才记一次送信。
##   若这条能让轨迹变红/分叉，而"同一条事实但没有这个读"不分叉 ⇒ 探针有判别力。
class GlobalFactReader:
	extends RefCounted
	func id() -> String: return "p1_globalread"
	func modify(S, _actor, _target, _action, _subject) -> float:
		for ag in S.agents:
			if (ag["beliefs"] as Dictionary).has("P1FACT"):
				return 100.0
		return 0.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed_base = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--n" and i + 1 < args.size(): n_agents = int(args[i + 1])
		elif args[i] == "--t0" and i + 1 < args.size(): t0 = int(args[i + 1])
		elif args[i] == "--delay" and i + 1 < args.size(): delay = int(args[i + 1])

	print("[P1] seed=%d days=%d N=%d t0=%d delay=%d" % [seed_base, days, n_agents, t0, delay])

	# 基线（CTRL）：不注入任何东西。它同时提供逐 tick 逐 agent 的指纹参照。
	var ctrl := _run({"arm": "CTRL"})
	_report("CTRL", ctrl, ctrl)

	# ── ① 挂点自身零扰动（这是后面所有 ext 臂的前提，必须先证）──
	_report("EXT_NULL", _run({"arm": "EXT_NULL", "ext": "null"}), ctrl)

	# ── ② 决定性实验：一条【只有一个人知道、且他讲不出去】的事实 ──
	# 载体 = 爱八卦的阿丽（最有可能扩散的人）；stifled ⇒ _unspread_belief 直接 continue
	# ⇒ 该事实对【知情者自己】也是行为惰性的。此时若世界仍分叉 ⇒ 有人越过知识边界读了它。
	_report("STIFLED_1KNOWER", _run({"arm": "STIFLED_1KNOWER", "inject": "one_stifled"}), ctrl)

	# 负对照：同一条惰性事实 + 一个蓄意的全局事实读 ⇒ 必须分叉（证明上面那条 PASS 不是空真）
	_report("STIFLED_1KNOWER+GLOBALREAD",
		_run({"arm": "STIFLED_1KNOWER+GLOBALREAD", "inject": "one_stifled", "ext": "globalread"}), ctrl)

	# 对照：同一条事实但【不 stifle】⇒ 知情者自己多一条 gossip 候选 ⇒ 预期分叉（物理耦合，非知识泄漏）
	_report("KNOWN_1KNOWER", _run({"arm": "KNOWN_1KNOWER", "inject": "one_open"}), ctrl)

	# ── ③ 外审的三臂对照（全部在【一个镇】里做，不造第二张地图）──
	# 把镇拆成两个 cohort：前半 = "A 镇"，后半 = "B 镇"（同一物理镇、同一 tick 循环）。
	_report("ARM1_INSTANT_GLOBAL", _run({"arm": "ARM1_INSTANT_GLOBAL", "inject": "instant"}), ctrl)
	_report("ARM2_DELAYED_ANON", _run({"arm": "ARM2_DELAYED_ANON", "inject": "delayed_anon"}), ctrl)
	_report("ARM3_DELAYED_NAMED", _run({"arm": "ARM3_DELAYED_NAMED", "inject": "delayed_named"}), ctrl)
	_report("ARM4_CARRIER_TX", _run({"arm": "ARM4_CARRIER_TX", "inject": "carrier"}), ctrl)

	# ── ④ 外审句子里的另一半：「全局 standing」。standing 是**逐关系**的私有字段，
	# 但 `_social_candidates` 的 gossip_rep / endorse 两条会读 **对方的** `_rel(o, C).standing`。
	# 实验：只改 O 一个人对 C 的 standing，看**第一个跟着变的非-O 的人**是不是当时与 O 同区。
	_report("MINDREAD_STANDING", _run({"arm": "MINDREAD_STANDING", "inject": "mindread"}), ctrl)

	# ── ⑤ 现成的硬不变量 #6「知识边界」到底守什么：两条负对照 ──
	# PROV_BREAK：via="gossip" 但**没有对应的传递事件** ⇒ #6 必须红（provenance 有牙）。
	_report("PROV_BREAK_via_gossip", _run({"arm": "PROV_BREAK_via_gossip", "inject": "prov_break"}), ctrl)
	# PROV_SMUGGLE：同一条凭空出现的事实，只把 via 改成 "seen" ⇒ #6 **豁免它**，绿。
	# 这就是"全局事实表"能从哪个门混进来的确切位置。
	_report("PROV_SMUGGLE_via_seen", _run({"arm": "PROV_SMUGGLE_via_seen", "inject": "prov_smuggle"}), ctrl)

	# ── ⑥ belief 层是局部的（②已证），但【夜间层】不是：`_recompute_factions` 每夜读全镇每个人的
	# 私有 attitudes（无任何 area/plane 门），写回 ag["faction"]，而 faction 直接进候选生成与接受判定。
	# 实验：只改**一个人**的私有立场，看有没有【从头到尾没跟他同过区】的人跟着改行为。
	_report("FACTION_NONLOCAL", _run({"arm": "FACTION_NONLOCAL", "inject": "attitude"}), ctrl)

	print("[P1] DONE")
	quit()

# ── 一臂 ────────────────────────────────────────────────────────────────
func _run(cfg: Dictionary) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if n_agents > 0:
		S.spawn_count = n_agents
	var extmode := String(cfg.get("ext", ""))
	if extmode != "":
		var e = SimExt.new()
		e.register_acceptance(GlobalFactReader.new() if extmode == "globalread" else NullModifier.new())
		e.freeze()
		S.ext = e
	S.start_new(seed_base)

	var ids: Array = []
	for ag in S.agents:
		ids.append(String(ag["id"]))
	var carrier := "aria" if S._agent_by_id.has("aria") else String(ids[0])
	var subj := "coco" if S._agent_by_id.has("coco") else String(ids[mini(2, ids.size() - 1)])
	if subj == carrier:
		subj = String(ids[mini(3, ids.size() - 1)])
	var half := int(ids.size() / 2)          # 前半 = "A 镇"（含 carrier），后半 = "B 镇"
	var a_town: Array = ids.slice(0, half)
	var b_town: Array = ids.slice(half)
	if not (carrier in a_town):              # 保证 carrier 在 A 侧
		a_town.append(carrier); b_town.erase(carrier)

	var inject := String(cfg.get("inject", ""))
	# MINDREAD 臂被改动的那个人（"B 镇"里的第一位）与被改动的第三方 C
	var mut_id := String(b_town[0]) if not b_town.is_empty() else String(ids[ids.size() - 1])
	var total := days * int(S.TICKS_PER_DAY)

	var chain: int = Inv.CHAIN_INIT
	var ev_seen: int = S.event_log.size()
	var chain_ticks := PackedInt64Array(); chain_ticks.resize(total)
	# 逐 agent 指纹：act = chain_step 的逐 agent 那一半（位置/需求/talking/option）**再加上 action/subject**
	#   （⚠ `Inv.chain_step` 的 option 签名是 kind|target|partner|area|phase|remaining ——
	#     **不含 action、不含 subject** ⇒ 它在会话进行中分不出"跟 ben 打招呼"与"跟 ben 说 coco 的传闻"，
	#     要等 CONVERSE_TICKS 后事件落账才看得见。本探针要归因到"谁先改的行为"，所以把这两项补进指纹。）
	#               rel = 关系账本 + 立场 + 派系（"权威关系与归责结果"那一半）
	# ⚠ 用普通 Array 而不是嵌套 PackedInt64Array：Packed* 是**值类型**，`arr[i][t] = v` 写进的是一份副本，
	#   实测会让全部指纹恒为 0 ⇒ 任何两臂都"逐 agent 无分叉"（一条静默恒真的判据，正是 docs/41 §2.5 说的那种）。
	var fp_act: Array = []
	var fp_rel: Array = []
	var fp_area: Array = []        # 逐 tick 所在 area（归因用：读到别人心思的那个人当时站在哪）
	var fp_link: Array = []        # 逐 tick 接触关系「social 对象|talk_with」——把"他是不是正被知情者搭话"变成实测
	var fp_fac: Array = []         # 逐 tick 派系归属：`_recompute_factions` 是全镇聚类，单独拎出来看它有没有非局部耦合
	for _i in ids.size():
		var pa := []; pa.resize(total); fp_act.append(pa)
		var pr := []; pr.resize(total); fp_rel.append(pr)
		var par := []; par.resize(total); fp_area.append(par)
		var pl := []; pl.resize(total); fp_link.append(pl)
		var pf := []; pf.resize(total); fp_fac.append(pf)

	var learn := {}                # id -> 首次持有 FACT 的 tick
	var tx_events: Array = []      # 真正把 FACT 传出去的 gossip 事件
	var starved := 0
	var clean_min := 2.0
	var clean_max := -1.0
	var market_closed := 0
	var market_samples := 0

	for t in range(total):
		S.tick()
		if S.tick_no == t0:
			_inject_t0(S, inject, carrier, subj, a_town, ids, mut_id)
		if S.tick_no == t0 + delay:
			_inject_delayed(S, inject, carrier, subj, b_town)
		chain = Inv.chain_step(chain, S, ev_seen)
		# 传播事件（只看新事件，O(1) 摊销）
		for i in range(ev_seen, S.event_log.size()):
			var e: Dictionary = S.event_log[i]
			if String(e.get("subject", "")) == FACT and bool(e.get("accepted", false)):
				tx_events.append({"tick": int(e["tick"]), "type": String(e["type"]),
					"actor": String(e["actor"]), "target": String(e["target"])})
		ev_seen = S.event_log.size()
		chain_ticks[t] = chain
		for ai in S.agents.size():
			var ag: Dictionary = S.agents[ai]
			(fp_act[ai] as Array)[t] = _fp_act(S, ag)
			(fp_rel[ai] as Array)[t] = _fp_rel(ag)
			(fp_area[ai] as Array)[t] = String(ag.get("area", ""))
			(fp_fac[ai] as Array)[t] = "%s/%d" % [String(ag.get("faction", "")), int(ag.get("faction_size", 1))]
			var _o = ag["option"]
			(fp_link[ai] as Array)[t] = "|%s|%s|" % [
				(String((_o as Dictionary).get("partner", "")) if _o is Dictionary else ""),
				String(ag.get("talk_with", ""))]
			if not learn.has(String(ag["id"])) and (ag["beliefs"] as Dictionary).has(FACT):
				learn[String(ag["id"])] = t + 1
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
		if t % 60 == 0:
			var cm := float(S._clean_mult())
			clean_min = minf(clean_min, cm); clean_max = maxf(clean_max, cm)
			var vend: Dictionary = S.production.get("vendor", {}) if S.production.get("vendor", {}) is Dictionary else {}
			if not vend.is_empty():
				market_samples += 1
				if not S._market_open(String(vend.get("action", ""))):
					market_closed += 1

	var res := Inv.check_all(S, starved)
	var hard: Array = []
	var soft: Array = []
	for r in res:
		if not bool(r["ok"]):
			if bool(r["hard"]): hard.append(int(r["id"]))
			else: soft.append(int(r["id"]))

	var out := {
		"arm": String(cfg.get("arm", "?")), "ids": ids, "carrier": carrier, "subject": subj,
		"a_town": a_town, "b_town": b_town,
		"chain": chain, "chain_ticks": chain_ticks, "digest": Inv.digest(S),
		"event_digest": int(S.event_digest), "events": S.event_log.size(),
		"fp_act": fp_act, "fp_rel": fp_rel, "fp_area": fp_area, "fp_link": fp_link, "fp_fac": fp_fac,
		"mutated": (mut_id if (inject == "mindread" or inject == "attitude") else ""),
		"learn": learn, "knowers": learn.keys().size(), "tx": tx_events,
		"starved": starved, "hard": hard, "soft": soft,
		"clean_min": clean_min, "clean_max": clean_max,
		"market_closed": market_closed, "market_samples": market_samples,
		"work_pull": float(S.work_pull_mult),
		# 归责结果：全镇对 carrier / subject 的 standing 之和（"关系与归责"那一栏）
		"st_carrier": _standing_sum(S, carrier), "st_subject": _standing_sum(S, subj),
		"gossip_n": _count_type(S, "gossip"), "gossip_rep_n": _count_type(S, "gossip_rep"),
	}
	get_root().remove_child(S)
	S.free()
	return out

# ── 注入 ────────────────────────────────────────────────────────────────
func _bel(subj: String, src: String, via: String, tick: int) -> Dictionary:
	# via="seed" ⇒ 硬不变量 #6 知识边界对它豁免（一手知识无上游事件）；
	# 同时 via != "seen" ⇒ 吃得到 O1 的 gossip_news_bonus，与"从别处带来的消息"同档。
	return {"claim": "远处出了一桩事", "subject": subj, "source": src, "via": via, "tick": tick}

func _inject_t0(S, mode: String, carrier: String, subj: String, a_town: Array, ids: Array, mut_id: String) -> void:
	match mode:
		"mindread":
			# 只动【一个人】对第三方 C 的私有 standing。它对 O 自己当然不是惰性的（会改 O 的 bad_targets），
			# 所以这一臂问的不是"有没有分叉"，而是"**第一个跟着变的非-O 的人**是不是当时与 O 同区"。
			# ⚠ 值必须在 [-STANDING_CAP, +STANDING_CAP] 内：第一版写 -10.0，硬 #27「S3协同守边界」
			#   当场变红（|standing| 越界）——**探针自己造了一个非法状态**。用 -CAP 才是合法的极端坏名声。
			S._rel(S._agent_by_id[mut_id], subj)["standing"] = -float(S.STANDING_CAP)
		"one_stifled":
			S._agent_by_id[carrier]["beliefs"][FACT] = _bel(subj, "__elsewhere__", "seed", S.tick_no)
			S._agent_by_id[carrier]["stifled"][FACT] = true
		"one_open", "carrier":
			S._agent_by_id[carrier]["beliefs"][FACT] = _bel(subj, "__elsewhere__", "seed", S.tick_no)
		"prov_break":
			# 声称"别人转述给我的"，却没有任何一条 accepted 事件 target=我、subject=FACT ⇒ #6 应红
			S._agent_by_id[carrier]["beliefs"][FACT] = _bel(subj, String(a_town[a_town.size() - 1]), "gossip", S.tick_no)
			S._agent_by_id[carrier]["stifled"][FACT] = true
		"attitude":
			# 把 B 侧第一个人的私有立场（含天生锚 attitude0，否则 FJ 会把它拉回去）改成强意见。
			# 值域 [-1,1]，与 _fj_update 的 clampf 同域 ⇒ 合法状态。
			var A: Dictionary = S._agent_by_id[mut_id]
			for t in A["attitudes"]:
				A["attitudes"][t] = 0.9
				(A["attitude0"] as Dictionary)[t] = 0.9
		"prov_smuggle":
			# 同一条凭空事实，只把 via 改成"亲眼所见" ⇒ #6 的 `via in ["seed","seen"]` 豁免直接放行
			S._agent_by_id[carrier]["beliefs"][FACT] = _bel(subj, "__seen__", "seen", S.tick_no)
			S._agent_by_id[carrier]["stifled"][FACT] = true
		"instant":
			for id in ids:
				S._agent_by_id[id]["beliefs"][FACT] = _bel(subj, "__seen__", "seed", S.tick_no)
		"delayed_anon", "delayed_named":
			for id in a_town:
				S._agent_by_id[id]["beliefs"][FACT] = _bel(subj, "__elsewhere__", "seed", S.tick_no)

func _inject_delayed(S, mode: String, carrier: String, subj: String, b_town: Array) -> void:
	# ARM2/ARM3 唯一的差别就是下面这一个字符串字段。
	var src := "__anon__" if mode == "delayed_anon" else carrier
	if mode != "delayed_anon" and mode != "delayed_named":
		return
	for id in b_town:
		if not (S._agent_by_id[id]["beliefs"] as Dictionary).has(FACT):
			S._agent_by_id[id]["beliefs"][FACT] = _bel(subj, src, "seed", S.tick_no)

# ── 指纹 ────────────────────────────────────────────────────────────────
func _fp_act(S, ag: Dictionary) -> int:
	var h: int = Inv.CHAIN_INIT
	h = SimScript.mix32(h, S._aid(ag))
	var p: Vector2i = ag["pos"]
	h = SimScript.mix32(h, int(p.x) * 65536 + int(p.y))
	for nid in ag["needs"]:
		h = SimScript.mix32(h, int(round(float(ag["needs"][nid]) * 65536.0)))
	h = SimScript.mix32(h, int(ag.get("talking", 0)))
	var opt = ag["option"]
	if opt is Dictionary:
		h = SimScript.fnv1a32_into(h, "%s|%s|%s|%s|%s|%s|%s|%s" % [
			str(opt.get("kind", "")), str(opt.get("target", "")), str(opt.get("partner", "")),
			str(opt.get("area", "")), str(opt.get("phase", "")), str(opt.get("remaining", "")),
			str(opt.get("action", "")), str(opt.get("subject", ""))])   # ★ chain_step 没有的两项
	else:
		h = SimScript.mix32(h, -1)
	return h

func _fp_rel(ag: Dictionary) -> int:
	var h: int = Inv.CHAIN_INIT
	for oid in ag["relationships"]:
		var r: Dictionary = ag["relationships"][oid]
		h = SimScript.fnv1a32_into(h, "%s|%d|%d|%d|%d|%d" % [String(oid),
			int(round(float(r["affinity"]) * 256.0)), int(round(float(r["trust"]) * 256.0)),
			int(round(float(r["resentment"]) * 256.0)), int(round(float(r["familiarity"]) * 256.0)),
			int(round(float(r["standing"]) * 256.0))])
	for t in ag["attitudes"]:
		h = SimScript.fnv1a32_into(h, "%s|%d" % [String(t), int(round(float(ag["attitudes"][t]) * 65536.0))])
	h = SimScript.fnv1a32_into(h, String(ag.get("faction", "")))
	return h

func _standing_sum(S, who: String) -> float:
	var s := 0.0
	for ag in S.agents:
		if String(ag["id"]) == who: continue
		if (ag["relationships"] as Dictionary).has(who):
			s += float(ag["relationships"][who]["standing"])
	return s

func _count_type(S, ty: String) -> int:
	var c := 0
	for e in S.event_log:
		if String(e.get("type", "")) == ty: c += 1
	return c

# ── 报告 ────────────────────────────────────────────────────────────────
func _report(_label: String, a: Dictionary, ref: Dictionary) -> void:
	var arm := String(a["arm"])
	var same_chain: bool = int(a["chain"]) == int(ref["chain"])
	var first_div := -1
	var ct: PackedInt64Array = a["chain_ticks"]
	var cr: PackedInt64Array = ref["chain_ticks"]
	for i in mini(ct.size(), cr.size()):
		if ct[i] != cr[i]:
			first_div = i + 1
			break
	# 逐 agent 首次分叉
	var div_act := {}
	var div_rel := {}
	for ai in (a["ids"] as Array).size():
		var pa: Array = a["fp_act"][ai]
		var pb: Array = ref["fp_act"][ai]
		for i in mini(pa.size(), pb.size()):
			if pa[i] != pb[i]:
				div_act[String(a["ids"][ai])] = i + 1
				break
		var qa: Array = a["fp_rel"][ai]
		var qb: Array = ref["fp_rel"][ai]
		for i in mini(qa.size(), qb.size()):
			if qa[i] != qb[i]:
				div_rel[String(a["ids"][ai])] = i + 1
				break
	# 有没有【在自己知道这条事实之前】就行为分叉的人
	var pre_knowledge: Array = []
	for id in div_act:
		var d := int(div_act[id])
		var l := int((a["learn"] as Dictionary).get(id, 1 << 30))
		if d < l:
			pre_knowledge.append("%s(div@%d, learn@%s)" % [id, d, ("never" if l == (1 << 30) else str(l))])
	pre_knowledge.sort()

	# ★归因：最早分叉的是谁？他当时知不知道那条事实？他跟被改动者同区吗？
	var earliest := 1 << 30
	for id in div_act:
		earliest = mini(earliest, int(div_act[id]))
	var first_movers: Array = []
	var mut := String(a.get("mutated", ""))
	var mut_idx := (a["ids"] as Array).find(mut)
	# 该 tick 的知情者集合（用于判"不知情的第一批人是不是正被知情者搭着话"）
	var knowers_at := []
	if earliest < (1 << 30):
		for id in (a["learn"] as Dictionary):
			if int((a["learn"] as Dictionary)[id]) <= earliest:
				knowers_at.append(String(id))
	for id in div_act:
		if int(div_act[id]) != earliest:
			continue
		var l := int((a["learn"] as Dictionary).get(id, 1 << 30))
		var tag := "知情" if l <= earliest else "不知情"
		if tag == "不知情" and not knowers_at.is_empty():
			# ★接触判定必须【两臂都看】：知情者的行为一变，有可能是"本来要找你说话、现在不找了"，
			#   于是被影响的那个人在【本臂】里反而看不到接触——只有对照臂里有。只看一臂会把
			#   一次普通的物理耦合误报成"越过知识边界的读"（我第一版就是这么误报的）。
			var myidx := (a["ids"] as Array).find(id)
			var linked := false
			for arm_d in [a, ref]:
				var mylink := String((arm_d["fp_link"][myidx] as Array)[earliest - 1])
				for k in knowers_at:
					if ("|%s|" % k) in mylink:
						linked = true; break
					var kidx := (a["ids"] as Array).find(k)
					if kidx >= 0 and ("|%s|" % id) in String((arm_d["fp_link"][kidx] as Array)[earliest - 1]):
						linked = true; break
				if linked: break
			tag += "/被知情者搭话(含反事实)" if linked else "/**与知情者无接触**"
		if mut != "":
			var idx := (a["ids"] as Array).find(id)
			var same := (mut_idx >= 0 and idx >= 0 and earliest >= 1
				and String((a["fp_area"][idx] as Array)[earliest - 1]) == String((a["fp_area"][mut_idx] as Array)[earliest - 1]))
			tag += ("/与%s同区" % mut) if same else ("/与%s异区" % mut)
		first_movers.append("%s[%s]" % [id, tag])
	first_movers.sort()

	print("[P1] === %s ===" % arm)
	print("[P1]   chain=%d digest=%d event_digest=%d events=%d  同基线=%s" % [
		int(a["chain"]), int(a["digest"]), int(a["event_digest"]), int(a["events"]), str(same_chain)])
	print("[P1]   首个分叉 tick=%s  逐agent分叉(act)=%d/%d  (rel)=%d/%d" % [
		("无" if first_div < 0 else str(first_div)), div_act.size(), (a["ids"] as Array).size(),
		div_rel.size(), (a["ids"] as Array).size()])
	print("[P1]   知道 %s 的人=%d  传播事件=%d %s" % [FACT, int(a["knowers"]), (a["tx"] as Array).size(),
		str(a["tx"]).substr(0, 300)])
	# 知情者在最早分叉那一 tick 的接触对象（本臂 vs 对照臂）—— 把因果讲具体
	var kl := ""
	if earliest < (1 << 30):
		for k in knowers_at:
			var kidx := (a["ids"] as Array).find(k)
			if kidx < 0: continue
			kl += " %s:本臂%s 对照%s" % [k, String((a["fp_link"][kidx] as Array)[earliest - 1]),
				String((ref["fp_link"][kidx] as Array)[earliest - 1])]
	print("[P1]   最早分叉@%s 的人=%s" % [("无" if earliest == (1 << 30) else str(earliest)), str(first_movers).substr(0, 400)])
	print("[P1]   知情者当时的接触:%s" % kl.substr(0, 300))
	# ★被改动者 X 的臂：谁在【从 t0 到自己分叉为止一次都没跟 X 同过区】的情况下就改了行为？
	#   —— 这才是"隔着整个镇被影响"的实测形态（`_recompute_factions` / `_form_pacts_greedy` 那条路）。
	if mut != "" and mut_idx >= 0:
		var never: Array = []
		var everco := 0
		for id in div_act:
			if String(id) == mut: continue
			var d := int(div_act[id])
			var idx2 := (a["ids"] as Array).find(id)
			var co := false
			for tt in range(maxi(0, t0 - 1), d):
				if String((a["fp_area"][idx2] as Array)[tt]) == String((a["fp_area"][mut_idx] as Array)[tt]):
					co = true; break
			if co: everco += 1
			else: never.append("%s@%d" % [id, d])
		never.sort()
		print("[P1]   非-%s 者：分叉前与 X 同过区 %d 人 · **一次都没同过区** %d 人 %s" % [
			mut, everco, never.size(), str(never).substr(0, 400)])
		# ★派系字段单独看：`_recompute_factions` 每夜从【全镇每个人的私有 attitudes】重算，无任何空间门。
		#   若 X 的立场一变，就有【非-X】的人在**下一个日界**换了派系，那就是零接触的全局耦合。
		var fac_first := 1 << 30
		var fac_who: Array = []
		for ai2 in (a["ids"] as Array).size():
			if String(a["ids"][ai2]) == mut: continue
			var fa: Array = a["fp_fac"][ai2]
			var fb: Array = ref["fp_fac"][ai2]
			for i in mini(fa.size(), fb.size()):
				if String(fa[i]) != String(fb[i]):
					if i + 1 < fac_first:
						fac_first = i + 1; fac_who = []
					if i + 1 == fac_first:
						fac_who.append("%s(%s→%s)" % [String(a["ids"][ai2]), String(fb[i]), String(fa[i])])
					break
		fac_who.sort()
		print("[P1]   非-%s 者的【派系字段】首次改变@%s：%s" % [mut,
			("从未" if fac_first == (1 << 30) else str(fac_first)), str(fac_who).substr(0, 300)])
	print("[P1]   先动后知(act 分叉早于习得)=%d %s" % [pre_knowledge.size(), str(pre_knowledge).substr(0, 400)])
	print("[P1]   硬=%s 软=%s 触底=%d  gossip=%d gossip_rep=%d  st(carrier)=%.1f st(subject)=%.1f" % [
		str(a["hard"]), str(a["soft"]), int(a["starved"]), int(a["gossip_n"]), int(a["gossip_rep_n"]),
		float(a["st_carrier"]), float(a["st_subject"])])
	print("[P1]   全局读观测: clean_mult∈[%.4f,%.4f]  市集关闭 %d/%d 采样  work_pull=%.6f" % [
		float(a["clean_min"]), float(a["clean_max"]), int(a["market_closed"]),
		int(a["market_samples"]), float(a["work_pull"])])
