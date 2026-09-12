extends SceneTree
## bench/q1_faction_probe.gd —— Q1「派系层的接触门」只读探针（docs/64 §一 · 接 docs/63 §四）
##
## 与 P1 的探针（bench/p1_locality_probe.gd）的关系：**复用它的臂形状，但换掉判据**。
## P1 的 `_fp_rel` 把【关系账本 + attitudes + faction】折进**同一个**指纹 ⇒ 它分不出
##   「别人的立场变了」与「别人的派系标签变了」。而 docs/63 §四 那条判决的全部重量恰好压在这个区分上：
##   P1 的推理是「@1440 全世界【行为】逐字节相同 ⇒ 1200-1440 之间不可能有 discuss 载过 lin 的新立场」。
##   ⚠ 这一步是**不成立的**：`Inv.chain_step` 折的是 位置/需求/talking/option/事件，**不含 attitudes**。
##     同一 tick、同样接受结果的一次 discuss，会在两臂里传递**不同的**立场值而**不改变任何行为**。
##     ⇒ 「行为逐字节相同」推不出「立场没传出去」。
## 本探针把 attitudes 单独拎成一条指纹（`_fp_att`），于是那一步变成**直接观测**而不是推理。
##
## 三类指纹，逐 tick 逐 agent，互不混合：
##   fp_act  行为（P1 口径：位置/需求/talking/option 含 action+subject）
##   fp_att  **只有 attitudes**（int 量化 1/65536）
##   fp_fac  **只有 faction/faction_size**
##   fp_rel  **只有关系账本**（affinity/trust/resentment/familiarity/standing），不含 attitudes、不含 faction
##
## 隔离臂（docs/64 明确要求的「更强的隔离设计」）：把被改动者从 **tick 0** 起钉在一个
##   自造平面 `q:cell` 上。`_nearby_agents` 的判据是 `_same_plane and area 相同`
##   ⇒ 他**从头到尾**不可能出现在任何人的 `_nearby_agents` 里，也没有任何人出现在他的
##   ⇒ greet/gossip/discuss/confide/见证 一条都不可能发生，familiarity 恒 0。
##   对照臂是**同样被隔离但立场没改**的那一局 ⇒ 两臂唯一的差别就是那一个人的私有 attitudes。
##   ⇒ 这一步不再靠时序，靠构造。
##
## 用法：
##   godot --headless --path game --script bench/q1_faction_probe.gd -- --seed 1 --days 10 --n 12 --t0 1200

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var seed_base := 1
var days := 10
var n_agents := 12
var t0 := 1200

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed_base = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--n" and i + 1 < args.size(): n_agents = int(args[i + 1])
		elif args[i] == "--t0" and i + 1 < args.size(): t0 = int(args[i + 1])

	print("[Q1] seed=%d days=%d N=%d t0=%d" % [seed_base, days, n_agents, t0])

	# ── ① 出货配置（无隔离）：复现 docs/63 §四，但把 attitudes 与 faction 分开看 ──
	var ctrl := _run({"arm": "CTRL"})
	var att := _run({"arm": "ATT1", "mutate": true})
	_report("ATT1", att, ctrl)

	# ── ② 隔离臂：被改动者从 tick 0 起物理上不可能与任何人共处 ──
	var qctrl := _run({"arm": "QCTRL", "quarantine": true})
	var qatt := _run({"arm": "QATT1", "quarantine": true, "mutate": true})
	_report("QATT1", qatt, qctrl)

	print("[Q1] DONE")
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
	S.start_new(seed_base)

	var ids: Array = []
	for ag in S.agents:
		ids.append(String(ag["id"]))
	# 被改动者：取 id 定序后的**后半第一位**（与 P1 的 mut_id 同一口径：ids.slice(half)[0]）
	var half := int(ids.size() / 2)
	var mut_id := String(ids[half]) if half < ids.size() else String(ids[ids.size() - 1])
	var quarantine := bool(cfg.get("quarantine", false))
	var mutate := bool(cfg.get("mutate", false))
	var total := days * int(S.TICKS_PER_DAY)

	if quarantine:
		_quarantine(S, mut_id)

	var chain: int = Inv.CHAIN_INIT
	var ev_seen: int = S.event_log.size()
	var fp_act: Array = []
	var fp_att: Array = []
	var fp_fac: Array = []
	var fp_rel: Array = []
	for _i in ids.size():
		var a1 := []; a1.resize(total); fp_act.append(a1)
		var a2 := []; a2.resize(total); fp_att.append(a2)
		var a3 := []; a3.resize(total); fp_fac.append(a3)
		var a4 := []; a4.resize(total); fp_rel.append(a4)

	var starved := 0
	# 隔离验证：被改动者与别人同区的 tick 数（必须恒为 0），以及他 familiarity 的总和
	var co_ticks := 0
	# 派系通道活性：逐 tick 记录"有多少人 faction_size>=QUORUM"（endorse/rally_oust 的前置）
	var quorum_ticks := 0

	for t in range(total):
		S.tick()
		if quarantine:
			_quarantine(S, mut_id)
		if mutate and S.tick_no == t0:
			var A: Dictionary = S._agent_by_id[mut_id]
			for tp in A["attitudes"]:
				A["attitudes"][tp] = 0.9
				(A["attitude0"] as Dictionary)[tp] = 0.9
		chain = Inv.chain_step(chain, S, ev_seen)
		ev_seen = S.event_log.size()
		var mut_area := String(S._agent_by_id[mut_id].get("area", ""))
		for ai in S.agents.size():
			var ag: Dictionary = S.agents[ai]
			(fp_act[ai] as Array)[t] = _fp_act(S, ag)
			(fp_att[ai] as Array)[t] = _fp_att(ag)
			(fp_fac[ai] as Array)[t] = "%s/%d" % [String(ag.get("faction", "")), int(ag.get("faction_size", 1))]
			(fp_rel[ai] as Array)[t] = _fp_rel(ag)
			if int(ag.get("faction_size", 1)) >= int(S.FACTION_QUORUM):
				quorum_ticks += 1
			if String(ag["id"]) != mut_id and String(ag.get("area", "")) == mut_area and S._same_plane(ag, S._agent_by_id[mut_id]):
				co_ticks += 1
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1

	var res := Inv.check_all(S, starved)
	var hard: Array = []
	var soft: Array = []
	for r in res:
		if not bool(r["ok"]):
			if bool(r["hard"]): hard.append(int(r["id"]))
			else: soft.append(int(r["id"]))

	# 被改动者的 familiarity 总和（隔离臂应恒 0）
	var mut_fam := 0.0
	for oid in (S._agent_by_id[mut_id]["relationships"] as Dictionary):
		mut_fam += float(S._agent_by_id[mut_id]["relationships"][oid]["familiarity"])

	var out := {
		"arm": String(cfg.get("arm", "?")), "ids": ids, "mut": mut_id,
		"chain": chain, "digest": Inv.digest(S), "events": S.event_log.size(),
		"fp_act": fp_act, "fp_att": fp_att, "fp_fac": fp_fac, "fp_rel": fp_rel,
		"hard": hard, "soft": soft, "starved": starved,
		"co_ticks": co_ticks, "mut_fam": mut_fam, "quorum_ticks": quorum_ticks,
		"endorse_n": _count_type(S, "endorse"), "oust_n": _count_type(S, "rally_oust"),
		"discuss_n": _count_type(S, "discuss"), "fac_n": int(S.factions.size()),
	}
	get_root().remove_child(S)
	S.free()
	return out

## 把 agent 钉死在一个自造平面上：`_same_plane` 比 space+floor，`_nearby_agents` 还要 area 相同。
## 镇上没有任何人会有 space=="q" ⇒ 双向不可见。area 直接写死（不经 _area_key，免得 town 分支把它算回镇上）。
func _quarantine(S, mut_id: String) -> void:
	var A: Dictionary = S._agent_by_id[mut_id]
	A["space"] = "q"; A["floor"] = "cell"; A["area"] = "q:cell"

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
			str(opt.get("action", "")), str(opt.get("subject", ""))])
	else:
		h = SimScript.mix32(h, -1)
	return h

## ★ 只有 attitudes。这是本探针相对 P1 的关键改动。
func _fp_att(ag: Dictionary) -> int:
	var h: int = Inv.CHAIN_INIT
	for t in ag["attitudes"]:
		h = SimScript.fnv1a32_into(h, "%s|%d" % [String(t), int(round(float(ag["attitudes"][t]) * 65536.0))])
	return h

## 只有关系账本（不含 attitudes、不含 faction）
func _fp_rel(ag: Dictionary) -> int:
	var h: int = Inv.CHAIN_INIT
	for oid in ag["relationships"]:
		var r: Dictionary = ag["relationships"][oid]
		h = SimScript.fnv1a32_into(h, "%s|%d|%d|%d|%d|%d" % [String(oid),
			int(round(float(r["affinity"]) * 256.0)), int(round(float(r["trust"]) * 256.0)),
			int(round(float(r["resentment"]) * 256.0)), int(round(float(r["familiarity"]) * 256.0)),
			int(round(float(r["standing"]) * 256.0))])
	return h

func _count_type(S, ty: String) -> int:
	var c := 0
	for e in S.event_log:
		if String(e.get("type", "")) == ty: c += 1
	return c

# ── 报告 ────────────────────────────────────────────────────────────────
## 对每一类指纹，报【非被改动者】的首次分叉 tick 与当时是谁。
func _first_div(a: Dictionary, ref: Dictionary, key: String, skip_mut: bool) -> Dictionary:
	var mut := String(a["mut"])
	var best := 1 << 30
	var who: Array = []
	for ai in (a["ids"] as Array).size():
		var id := String(a["ids"][ai])
		if skip_mut and id == mut: continue
		var pa: Array = a[key][ai]
		var pb: Array = ref[key][ai]
		for i in mini(pa.size(), pb.size()):
			if str(pa[i]) != str(pb[i]):
				if i + 1 < best:
					best = i + 1; who = []
				if i + 1 == best:
					who.append("%s(%s→%s)" % [id, str(pb[i]), str(pa[i])] if key == "fp_fac" else id)
				break
	who.sort()
	return {"tick": best, "who": who}

func _report(_label: String, a: Dictionary, ref: Dictionary) -> void:
	var arm := String(a["arm"])
	var mut := String(a["mut"])
	var d_att := _first_div(a, ref, "fp_att", true)
	var d_fac := _first_div(a, ref, "fp_fac", true)
	var d_act := _first_div(a, ref, "fp_act", true)
	var d_rel := _first_div(a, ref, "fp_rel", true)
	var d_act_all := _first_div(a, ref, "fp_act", false)
	var f := func(d: Dictionary) -> String:
		return "从未" if int(d["tick"]) == (1 << 30) else str(int(d["tick"]))
	print("[Q1] === %s (ref=%s) 被改动者=%s ===" % [arm, String(ref["arm"]), mut])
	print("[Q1]   隔离自证: 被改动者与人同区 tick=%d(ctrl=%d)  familiarity总和=%.1f(ctrl=%.1f)" % [
		int(a["co_ticks"]), int(ref["co_ticks"]), float(a["mut_fam"]), float(ref["mut_fam"])])
	print("[Q1]   ★非被改动者 首次分叉：attitudes@%s  faction@%s  行为@%s  关系账本@%s" % [
		f.call(d_att), f.call(d_fac), f.call(d_act), f.call(d_rel)])
	print("[Q1]     faction 变的人: %s" % str(d_fac["who"]).substr(0, 400))
	print("[Q1]     attitudes 变的人: %s" % str(d_att["who"]).substr(0, 200))
	print("[Q1]   含被改动者 行为首次分叉@%s  chain同=%s(%d vs %d)" % [
		f.call(d_act_all), str(int(a["chain"]) == int(ref["chain"])), int(a["chain"]), int(ref["chain"])])
	var verdict := "不适用"
	if int(d_fac["tick"]) < (1 << 30):
		verdict = "★零传播派系耦合成立" if int(d_fac["tick"]) < int(d_att["tick"]) else "否（立场先传到了别人身上）"
	print("[Q1]   判决: %s   (faction@%s vs 别人 attitudes@%s)" % [verdict, f.call(d_fac), f.call(d_att)])
	print("[Q1]   通道活性 本臂/对照: endorse %d/%d  rally_oust %d/%d  discuss %d/%d  派系数 %d/%d  quorum内agent-tick %d/%d" % [
		int(a["endorse_n"]), int(ref["endorse_n"]), int(a["oust_n"]), int(ref["oust_n"]),
		int(a["discuss_n"]), int(ref["discuss_n"]), int(a["fac_n"]), int(ref["fac_n"]),
		int(a["quorum_ticks"]), int(ref["quorum_ticks"])])
	print("[Q1]   硬=%s 软=%s 触底=%d(ctrl=%d)" % [str(a["hard"]), str(a["soft"]), int(a["starved"]), int(ref["starved"])])
