extends SceneTree
## bench/ac1_state_coverage.gd —— AC1「权威状态投影」只读探针（docs/108 §一）
##
## 回答两个**分开**的问题，别把它们混成一个：
##   ① 覆盖（瞬时）：把字段 X 就地改一下、**用同一个 prev / 同一个 ev_from** 重算
##      `Inv.chain_step` 与 `Inv.digest` —— 值变不变？变=折进去了，不变=没折。
##      ⚠ 这一步**不读源码、不读注释**（本 session 反复吃过注释过期的亏）：它是直接量出来的。
##      分母也不是手列的——世界侧走 `get_property_list()`（**与 `Sim.save_game` 同一套反射**），
##      agent 侧走活 agent 的 `.keys()`。**"有多少字段"这个数是跑出来的。**
##   ② 驱动未来（跨时）：对未覆盖字段造一个**只改它**的干预，跑两条完整臂，量
##      chain 首次分叉 tick / 行为首次分叉 tick / 终态 digest 变没变。
##      ⇒ **①不变而②变 = 真盲区；①不变而②也不变 = 那个字段是死的（那也是结果）。**
##
## ⚠ 为什么①②必须都跑：一个字段没被折进 hash，**不等于**它的变化永远看不见——
##   只要它驱动未来，几个 tick 之后 pos/option/事件就会分叉，chain 跟着分叉。
##   真正要量的是【延迟】和【会不会永远看不见】。docs/66 (Q1) 实测过一格 557 tick 的延迟。
##
## 用法：
##   godot --headless --path game --script bench/ac1_state_coverage.gd -- --mode cover --seed 1 --n 12 --t0 480
##   godot --headless --path game --script bench/ac1_state_coverage.gd -- --mode drive --seed 1 --n 12 --t0 480 --days 10

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

## 与 `Sim.save_game` 里那三个 const **逐字抄写**。它们在那里是函数内 const，取不到 ⇒ 这里必须复制。
## ⚠ 这是一处真实的耦合：`save_game` 改了这三个列表而这里没跟，本探针的分母就会悄悄错。
##   探针会把"反射到但不在权威集里"的字段**逐个打印出来**，让这个耦合是可见的而不是隐形的。
const SAVE_DERIVED := ["_agent_by_id", "_active_commitments", "_near_set", "_path_cache", "_nav_grids", "_player_pos"]
const SAVE_VIEW_PARAMS := ["lod_focus"]
const SAVE_BENCH_ONLY := ["shadow_on", "shadow_trace"]

var seed_base := 1
var n_agents := 12
var t0 := 480
var days := 10
var mode := "cover"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed_base = int(args[i + 1])
		elif args[i] == "--n" and i + 1 < args.size(): n_agents = int(args[i + 1])
		elif args[i] == "--t0" and i + 1 < args.size(): t0 = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--mode" and i + 1 < args.size(): mode = String(args[i + 1])

	if mode == "cover":
		_run_cover()
	else:
		_run_drive()
	quit()

# ══════════════════════════════════════════════════════════════════════════
# ① 覆盖（瞬时）
# ══════════════════════════════════════════════════════════════════════════
func _run_cover() -> void:
	print("[AC1-COVER] seed=%d N=%d t0=%d" % [seed_base, n_agents, t0])
	var S = _boot()
	var ev_from := 0
	for _t in t0:
		ev_from = S.event_log.size()
		S.tick()

	# 基准：**固定** prev 与 ev_from，之后每次重算都用同一对 ⇒ 唯一变量就是被改的那个字段。
	const PREV := 123456789
	var base_chain: int = Inv.chain_step(PREV, S, ev_from)
	var base_digest: int = Inv.digest(S)
	print("[AC1-COVER] baseline chain=%d digest=%d  events=%d agents=%d" % [
		base_chain, base_digest, S.event_log.size(), S.agents.size()])

	# ── 「这一局里它变过吗」──────────────────────────────────────────────
	# ⚠ 这一列是分母能不能用的关键。100 个世界字段里有一大半是 `data/*.json` 读进来的**配置**
	#   （rhythm/utility/weather/jobs/economy/production…）——它们是这一局的**输入**，不是演化状态，
	#   本来就不该进"轨迹哈希"（它们由数据文件 + 金标烘焙一起钉住）。
	#   判据可执行且不读注释：**t0 时刻的值 与 再跑一天之后的值 逐字节比**。变了 = 演化状态。
	#   ⇒ 真正该问"覆盖了吗"的分母是【变过的那些】，不是全部 100 个。
	var before := {}
	for p in S.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var nm0 := String(p["name"])
		var v0 = S.get(nm0)
		if v0 is Object or v0 is Callable:
			continue
		before[nm0] = var_to_bytes(v0)
	var agent_before := {}
	for k0 in (S.agents[0] as Dictionary).keys():
		var col := []
		for ag0 in S.agents:
			var vv = (ag0 as Dictionary).get(k0)
			col.append(var_to_bytes(vv) if not (vv is Object) else PackedByteArray())
		agent_before[String(k0)] = col
	var probe_S = _boot()
	for _t2 in (t0 + int(probe_S.TICKS_PER_DAY)):
		probe_S.tick()
	var mutated := {}
	for nm1 in before:
		var v1 = probe_S.get(nm1)
		mutated[nm1] = (var_to_bytes(v1) != before[nm1]) if not (v1 is Object or v1 is Callable) else false
	var agent_mutated := {}
	for k1 in agent_before:
		var ch := false
		for ai1 in probe_S.agents.size():
			if ai1 >= (agent_before[k1] as Array).size():
				break
			var vv1 = (probe_S.agents[ai1] as Dictionary).get(k1)
			if vv1 is Object:
				continue
			if var_to_bytes(vv1) != (agent_before[k1] as Array)[ai1]:
				ch = true; break
		agent_mutated[k1] = ch
	get_root().remove_child(probe_S)
	probe_S.free()

	# ── 世界侧：与 save_game 同一套反射 ──────────────────────────────────
	print("\n=== WORLD (Sim script variables, same reflection as save_game) ===")
	print("%-28s %-10s %-8s %-8s %-8s" % ["field", "class", "in_chain", "in_digest", "evolves"])
	var w_tot := 0; var w_chain := 0; var w_dig := 0; var w_skip := 0
	var w_evolve := 0; var w_evolve_uncov := 0
	var world_rows: Array = []
	for p in S.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var nm := String(p["name"])
		var cls := "state"
		if nm in SAVE_DERIVED: cls = "derived"
		elif nm in SAVE_VIEW_PARAMS: cls = "view"
		elif nm in SAVE_BENCH_ONLY: cls = "bench"
		var v = S.get(nm)
		if v is Object or v is Callable:
			cls = "wiring"
		var evo := bool(mutated.get(nm, false))
		if cls != "state":
			w_skip += 1
			world_rows.append([nm, cls, "-", "-", "YES" if evo else "no"])
			continue
		var pr := _perturb(v)
		if not bool(pr[0]):
			w_skip += 1
			world_rows.append([nm, "unperturbable", "?", "?", "YES" if evo else "no"])
			continue
		w_tot += 1
		S.set(nm, pr[1])
		var c2: int = Inv.chain_step(PREV, S, ev_from)
		var d2: int = Inv.digest(S)
		S.set(nm, v)
		var inc := c2 != base_chain
		var ind := d2 != base_digest
		if inc: w_chain += 1
		if ind: w_dig += 1
		if evo:
			w_evolve += 1
			if not inc and not ind: w_evolve_uncov += 1
		world_rows.append([nm, "state", "YES" if inc else "no", "YES" if ind else "no", "YES" if evo else "no"])
	for r in world_rows:
		print("%-28s %-10s %-8s %-8s %-8s" % [r[0], r[1], r[2], r[3], r[4]])

	# ── agent 侧：活 agent 的实际 keys ─────────────────────────────────
	print("\n=== AGENT (live agent dict keys) ===")
	print("%-20s %-10s %-8s %-8s %-8s %s" % ["field", "class", "in_chain", "in_digest", "evolves", "note"])
	var keys: Array = (S.agents[0] as Dictionary).keys()
	var a_tot := 0; var a_chain := 0; var a_dig := 0; var a_skip := 0
	var a_evolve := 0; var a_evolve_uncov := 0
	for k in keys:
		var kk := String(k)
		var inc := false; var ind := false; var okany := false; var note := ""
		var nperturbed := 0
		for ai in S.agents.size():
			var ag: Dictionary = S.agents[ai]
			if not ag.has(kk):
				continue
			var v = ag[kk]
			if v is Object:
				note = "Object (save_game 特案序列化)"
				break
			var pr := _perturb(v)
			if not bool(pr[0]):
				continue
			okany = true
			nperturbed += 1
			ag[kk] = pr[1]
			var c2: int = Inv.chain_step(PREV, S, ev_from)
			var d2: int = Inv.digest(S)
			ag[kk] = v
			if c2 != base_chain: inc = true
			if d2 != base_digest: ind = true
		var aevo := bool(agent_mutated.get(kk, false))
		if not okany:
			a_skip += 1
			print("%-20s %-10s %-8s %-8s %-8s %s" % [kk, "unperturb", "?", "?", "YES" if aevo else "no", note])
			continue
		a_tot += 1
		if inc: a_chain += 1
		if ind: a_dig += 1
		if aevo:
			a_evolve += 1
			if not inc and not ind: a_evolve_uncov += 1
		print("%-20s %-10s %-8s %-8s %-8s %s" % [kk, "state", "YES" if inc else "no",
			"YES" if ind else "no", "YES" if aevo else "no",
			"在 %d/%d 个 agent 上可扰动" % [nperturbed, S.agents.size()]])

	# ── option 子字段：chain_step 折的是**六元**签名，不是整个 option ──
	print("\n=== OPTION sub-keys (chain_step folds only 6 of them) ===")
	var opt_owner := -1
	for ai in S.agents.size():
		if (S.agents[ai] as Dictionary)["option"] is Dictionary:
			opt_owner = ai; break
	if opt_owner < 0:
		print("  (t0=%d 这一刻没有任何 agent 持有非 null option ⇒ 本节无判别力)" % t0)
	else:
		var ag: Dictionary = S.agents[opt_owner]
		var opt: Dictionary = ag["option"]
		print("  probe agent=%s option keys=%s" % [String(ag["id"]), str(opt.keys())])
		for ok_ in opt.keys():
			var okey := String(ok_)
			var ov = opt[okey]
			var pr := _perturb(ov)
			if not bool(pr[0]):
				print("  %-14s unperturbable" % okey); continue
			var newopt: Dictionary = opt.duplicate(true)
			newopt[okey] = pr[1]
			ag["option"] = newopt
			var c2: int = Inv.chain_step(PREV, S, ev_from)
			ag["option"] = opt
			print("  %-14s in_chain=%s" % [okey, "YES" if c2 != base_chain else "no"])

	# ── relationships 子字段（关系账本）──────────────────────────────
	print("\n=== RELATIONSHIP sub-keys ===")
	var rel_owner := -1
	for ai in S.agents.size():
		if not (S.agents[ai]["relationships"] as Dictionary).is_empty():
			rel_owner = ai; break
	if rel_owner < 0:
		print("  (没有任何 agent 有关系条目 ⇒ 本节无判别力)")
	else:
		var ag2: Dictionary = S.agents[rel_owner]
		var rels: Dictionary = ag2["relationships"]
		var oid := String(rels.keys()[0])
		var r0: Dictionary = rels[oid]
		print("  probe agent=%s vs %s keys=%s" % [String(ag2["id"]), oid, str(r0.keys())])
		for rk_ in r0.keys():
			var rkey := String(rk_)
			var rv = r0[rkey]
			var pr := _perturb(rv)
			if not bool(pr[0]):
				print("  %-14s unperturbable" % rkey); continue
			var old = r0[rkey]
			r0[rkey] = pr[1]
			var c2: int = Inv.chain_step(PREV, S, ev_from)
			r0[rkey] = old
			print("  %-14s in_chain=%s" % [rkey, "YES" if c2 != base_chain else "no"])

	# ── event_log 子字段：digest 与 chain 各折哪些 ────────────────────
	print("\n=== EVENT_LOG sub-keys ===")
	if S.event_log.is_empty():
		print("  (event_log 空 ⇒ 本节无判别力)")
	else:
		var e0: Dictionary = S.event_log[S.event_log.size() - 1]
		print("  last event keys=%s" % str(e0.keys()))
		for ek_ in e0.keys():
			var ekey := String(ek_)
			var ev = e0[ekey]
			var pr := _perturb(ev)
			if not bool(pr[0]):
				print("  %-14s unperturbable" % ekey); continue
			var old = e0[ekey]
			e0[ekey] = pr[1]
			var d2: int = Inv.digest(S)
			# 末事件属于**上一 tick**（ev_from 之前），chain 那一格不重算它 ⇒ 只报 digest。
			e0[ekey] = old
			print("  %-14s in_digest=%s" % [ekey, "YES" if d2 != base_digest else "no"])

	print("\n=== COVER TALLY ===")
	print("world: perturbable_state=%d  in_chain=%d  in_digest=%d  skipped(derived/view/bench/wiring/unperturbable)=%d" % [
		w_tot, w_chain, w_dig, w_skip])
	print("agent: perturbable_state=%d  in_chain=%d  in_digest=%d  skipped=%d" % [a_tot, a_chain, a_dig, a_skip])
	print("── 只算【这一局里真的变过】的字段（配置/常量不该进轨迹哈希，它们由数据文件+金标钉住）──")
	print("world: evolves=%d  其中 chain/digest 两头都没折=%d" % [w_evolve, w_evolve_uncov])
	print("agent: evolves=%d  其中 chain/digest 两头都没折=%d" % [a_evolve, a_evolve_uncov])
	print("[AC1-COVER] DONE")

# ══════════════════════════════════════════════════════════════════════════
# ② 驱动未来（跨时）
# ══════════════════════════════════════════════════════════════════════════
## 每条臂 = 一次完整的局。干预在 tick_no == t0 那一刻**一次性**施加，只改一个逻辑字段。
const ARMS := [
	"attitudes", "beliefs", "relationships_affinity", "relationships_standing",
	"space_floor", "coin", "town_stock", "town_coin", "skills", "memory",
	"mood", "xi_eps", "faction", "pacts", "last_say", "agent_affinity", "stifled",
	"metKnower", "complementSeen", "weather_today", "day", "factions_world",
	"area", "talk_with", "inventory_gift",
]

func _run_drive() -> void:
	print("[AC1-DRIVE] seed=%d N=%d t0=%d days=%d" % [seed_base, n_agents, t0, days])
	var ctrl := _arm("")
	print("[AC1-DRIVE] CTRL chain=%d digest=%d events=%d hard=%s soft=%s" % [
		ctrl["chain"], ctrl["digest"], ctrl["events"], str(ctrl["hard"]), str(ctrl["soft"])])
	print("")
	print("%-22s %-7s %-6s %-7s %-11s %-11s %-7s %s" % [
		"arm", "landed", "chain", "digest", "chain_div@", "behav_div@", "events", "hard_red"])
	var notes: Array = []
	for a in ARMS:
		var r := _arm(a)
		var cdiv := -1
		var bdiv := -1
		for t in mini((r["chain_hist"] as Array).size(), (ctrl["chain_hist"] as Array).size()):
			if cdiv < 0 and (r["chain_hist"] as Array)[t] != (ctrl["chain_hist"] as Array)[t]:
				cdiv = t
			if bdiv < 0 and (r["behav_hist"] as Array)[t] != (ctrl["behav_hist"] as Array)[t]:
				bdiv = t
			if cdiv >= 0 and bdiv >= 0:
				break
		print("%-22s %-7s %-6s %-7s %-11s %-11s %-7d %s" % [
			a,
			"yes" if bool(r["landed"]) else "**NO**",
			"SAME" if r["chain"] == ctrl["chain"] else "DIFF",
			"SAME" if r["digest"] == ctrl["digest"] else "DIFF",
			("never" if cdiv < 0 else str(cdiv)),
			("never" if bdiv < 0 else str(bdiv)),
			int(r["events"]),
			str(r["hard"])])
		if String(r["note"]) != "":
			notes.append("  %-22s %s" % [a, String(r["note"])])
	if not notes.is_empty():
		print("\n--- 干预细节（阳性对照的可读版）---")
		for nn in notes:
			print(nn)
	print("\n⚠ landed=**NO** 的行【结果不可用】：那说明干预本身没落地，不是字段惰性。")
	print("[AC1-DRIVE] DONE")

func _arm(which: String) -> Dictionary:
	var S = _boot()
	var total := days * int(S.TICKS_PER_DAY)
	var ids: Array = []
	for ag in S.agents:
		ids.append(String(ag["id"]))
	var half := int(ids.size() / 2)
	var mid := String(ids[half]) if half < ids.size() else String(ids[ids.size() - 1])

	var chain: int = Inv.CHAIN_INIT
	var ev_seen := 0
	var chain_hist: Array = []
	var behav_hist: Array = []
	var starved := 0
	var applied := false
	var applied_note := ""
	var applied_fp := [0, 0]     # 干预前后【全状态指纹】：两者不等 = 干预真的落地了（阳性对照）
	for _t in range(total):
		S.tick()
		if not applied and which != "" and S.tick_no >= t0:
			applied_fp[0] = _full_fp(S)
			applied_note = _apply(S, mid, which)
			applied_fp[1] = _full_fp(S)
			applied = true
		chain = Inv.chain_step(chain, S, ev_seen)
		ev_seen = S.event_log.size()
		chain_hist.append(chain)
		# 行为指纹：P1/Q1 的 _fp_act 口径（**含 option.action / option.subject**，
		# 那两个恰恰是 chain_step 不折的）——全镇折成一个数。
		var bh: int = Inv.CHAIN_INIT
		for ag in S.agents:
			bh = SimScript.mix32(bh, S._aid(ag))
			var p: Vector2i = ag["pos"]
			bh = SimScript.mix32(bh, int(p.x) * 65536 + int(p.y))
			bh = SimScript.fnv1a32_into(bh, "%s|%s" % [String(ag.get("space", "")), String(ag.get("floor", ""))])
			for nid in ag["needs"]:
				bh = SimScript.mix32(bh, int(round(float(ag["needs"][nid]) * 65536.0)))
			bh = SimScript.mix32(bh, int(ag.get("talking", 0)))
			var opt = ag["option"]
			if opt is Dictionary:
				bh = SimScript.fnv1a32_into(bh, "%s|%s|%s|%s|%s|%s|%s|%s" % [
					str(opt.get("kind", "")), str(opt.get("target", "")), str(opt.get("partner", "")),
					str(opt.get("area", "")), str(opt.get("phase", "")), str(opt.get("remaining", "")),
					str(opt.get("action", "")), str(opt.get("subject", ""))])
			else:
				bh = SimScript.mix32(bh, -1)
			for nid in ag["needs"]:
				if float(ag["needs"][nid]) <= 0.5:
					starved += 1
		behav_hist.append(bh)

	var res := Inv.check_all(S, starved)
	var hard: Array = []
	var soft: Array = []
	for r in res:
		if not bool(r["ok"]):
			if bool(r["hard"]): hard.append(int(r["id"]))
			else: soft.append(int(r["id"]))
	var out := {
		"chain": chain, "digest": Inv.digest(S), "events": S.event_log.size(),
		"chain_hist": chain_hist, "behav_hist": behav_hist, "hard": hard, "soft": soft,
		"landed": applied_fp[0] != applied_fp[1], "note": applied_note, "mut": mid,
	}
	get_root().remove_child(S)
	S.free()
	return out

## 只改一个逻辑字段的干预。**每一条都要能说出"它只动了这一个东西"**。
## 返回一句 before→after，供**阳性对照**用：`SAME/SAME` 那几行只有在这句话证明"干预真的落地了"
## 之后才意味着"字段是惰性的"；否则它只意味着**我的干预本身是个 no-op**——
## 这正是本 session 反复强调的那类错误（"打印了却不阻止"的同族：改了却没改到）。
func _apply(S, mid: String, which: String) -> String:
	var A: Dictionary = S._agent_by_id[mid]
	var _b := ""
	match which:
		"attitudes":                       # docs/66 (Q1) 的同一条干预，便于交叉核对
			for tp in A["attitudes"]:
				A["attitudes"][tp] = 0.9
				(A["attitude0"] as Dictionary)[tp] = 0.9
		"beliefs":
			(A["beliefs"] as Dictionary).clear()
		"relationships_affinity":
			for oid in A["relationships"]:
				A["relationships"][oid]["affinity"] = 60.0
		"relationships_standing":
			for oid in A["relationships"]:
				A["relationships"][oid]["standing"] = -30.0
		"space_floor":
			# ⚠ 这条**不是**纯单字段：`area` 是 `_area_key(space,floor,pos)` 的派生缓存，
			#   不同步刷新它，世界就处在一个 `_make_agent`/`_move_agent` 永远造不出来的非法态。
			#   ⇒ 这里同步刷 area，语义上仍是"只改了他在哪个平面"。
			A["space"] = "cafe"; A["floor"] = "2f"
			A["area"] = S._area_key(A["space"], A["floor"], A["pos"])
		"coin":
			# ⚠ 只加 agent 的钱会破 #34（金钱守恒）——那**正是要报的东西**：
			#   hash 看不见它，而不变量看得见。两者是**不同的**防线。
			(A["inventory"] as Dictionary)["coin"] = int((A["inventory"] as Dictionary).get("coin", 0)) + 50
		"town_stock":
			for g in S.town_stock:
				S.town_stock[g] = int(S.town_stock[g]) + 20
		"town_coin":
			S.town_coin = int(S.town_coin) + 50
		"skills":
			# ⚠ 第一版写死 `"做活"` —— 若被改动者的本职动作是"看摊"或他根本没岗位，
			#   这条干预就是个 no-op，而结果会长得跟"skills 是死字段"一模一样。
			#   改成读他**真实的**岗位动作，并把岗位一起报出来。
			var job: Dictionary = S._job_of(mid)
			var act := String(S._job_action(job)) if not job.is_empty() else ""
			if act == "":
				_b = "岗位=<无> ⇒ 本臂无判别力(skills 对无岗位者按构造不进 _wage_for)"
			else:
				var lv0 := int(S._skill_level(A, act))
				(A["skills"] as Dictionary)[act] = int((A["skills"] as Dictionary).get(act, 0)) + 40
				_b = "岗位动作=%s 熟练 %d→%d 级 (wage_bonus=%d/级)" % [
					act, lv0, int(S._skill_level(A, act)), int(S.skills.get("wage_bonus", 0))]
		"memory":
			# ⚠ 第一版参数顺序写反了（实际签名 add(text, importance, tick, tags)）⇒ 运行时报错、干预从未落地。
			var mem = A.get("memory")
			if mem != null and mem.has_method("add"):
				var n0 := int((mem.items as Array).size())
				mem.add("AC1 探针注入的一条记忆", 9, S.tick_no, ["ac1"])
				_b = "memory.items %d→%d" % [n0, int((mem.items as Array).size())]
		"mood":
			A["mood"] = "angry"
		"xi_eps":
			A["xi"] = 0.9; A["eps"] = 2.0
		"faction":
			A["faction"] = String(A["id"]); A["faction_size"] = 99
		"pacts":
			# ⚠ 第一版塞的是 {partner,formed} —— 缺 `status` ⇒ `_active_pact_count` 当场抛错，
			#   那一臂其实是**崩着跑完的**，结果不可用。契约是 `:887` / `:4457` 那个七键 dict，
			#   而且盟约**按构造是双边的** ⇒ 两侧都要写，否则世界处在造不出来的非法态。
			var other := ""
			for o in S.agents:
				if String(o["id"]) != mid and not (A["pacts"] as Dictionary).has(String(o["id"])):
					other = String(o["id"]); break
			if other == "":
				_b = "找不到可结盟对象 ⇒ 本臂无判别力"
			else:
				var O: Dictionary = S._agent_by_id[other]
				var key := String(S._pact_key(mid, other))
				(A["pacts"] as Dictionary)[other] = {"partner": other, "key": key,
					"formedTick": S.tick_no, "status": "active", "given": 0, "received": 0, "lastAidTick": 0}
				(O["pacts"] as Dictionary)[mid] = {"partner": mid, "key": key,
					"formedTick": S.tick_no, "status": "active", "given": 0, "received": 0, "lastAidTick": 0}
				_b = "与 %s 结一个 active 盟约（双边）" % other
		"last_say":
			A["last_say"] = "AC1 探针"
		# ⚠ 下面这一组的读路径**全是按 id 查表**（`ag["stifled"].has(cid)` :2540/:3772、
		#   `ag["complementSeen"].get(oid)` :4448/:4450 …）。第一版我塞的键是 `"__ac1__"`，
		#   而世界上没有任何一个 subject/partner 叫这个名字 ⇒ **那条查表永远命中不了**，
		#   于是"字段惰性"与"我的键根本不可能被查到"长得一模一样。**必须用真 id。**
		"agent_affinity":
			(A["affinity"] as Dictionary)[_other(S, mid)] = 1.0
		"stifled":
			(A["stifled"] as Dictionary)[_other(S, mid)] = true
		"metKnower":
			var ok2 := _other(S, mid)
			(A["metKnower"] as Dictionary)[ok2] = int(S.STIFLE_K)
			_b = "metKnower[%s]=%d (=STIFLE_K，正压在 :2544 那道门上)" % [ok2, int(S.STIFLE_K)]
		"complementSeen":
			var oc := _other(S, mid)
			(A["complementSeen"] as Dictionary)[oc] = int(S.PACT_COMPLEMENT_TH)
			(S._agent_by_id[oc]["complementSeen"] as Dictionary)[mid] = int(S.PACT_COMPLEMENT_TH)
			_b = "complementSeen[%s]=%d (=PACT_COMPLEMENT_TH，正压在 :4448 那道门上)" % [oc, int(S.PACT_COMPLEMENT_TH)]
		"weather_today":
			var cur := String(S.weather_today)
			for wt in (S.weather.get("types", {}) as Dictionary):
				if String(wt) != cur:
					S.weather_today = String(wt); break
			_b = "%s→%s" % [cur, String(S.weather_today)]
		"day":
			S.day = int(S.day) + 3
		"factions_world":
			# 世界级派生视图（每夜全量重建）。改它 = 问"它在下一次重建之前会被读到吗"。
			# 用**真** medoid id 建桶，理由同上一组：假 id 的桶谁也查不到。
			(S.factions as Dictionary)[_other(S, mid)] = [mid]
		"area":
			# `area` 是 `_area_key(space,floor,pos)` 的缓存。**只改缓存不改真源** = 问
			# "邻近枚举读的是缓存还是真源"。这是一条刻意的不一致探针。
			_b = "area %s→__ac1__(只改缓存,不动 space/floor/pos)" % String(A.get("area", ""))
			A["area"] = "__ac1__"
		"talk_with":
			# 唯一的读点是 `:1361` 的 `talk_with == "player"`（玩家专属"站住听完"门）。
			# 写别的值按构造命中不了 ⇒ 只有写 "player" 这一臂才有判别力。
			# ⚠ headless bench 里**没有玩家**，这条读路径能不能被走到本身就是要量的东西。
			A["talk_with"] = "player"
			_b = "talk_with=\"player\"（:1361 唯一读点的那个字面量；bench 无玩家）"
		"inventory_gift":
			(A["inventory"] as Dictionary)["gift"] = int((A["inventory"] as Dictionary).get("gift", 0)) + 5
	return _b

# ══════════════════════════════════════════════════════════════════════════
## 取一个**真实存在**的、不是被改动者的 agent id。按 id 查表的那些字段全靠它才有判别力。
func _other(S, mid: String) -> String:
	for o in S.agents:
		if String(o["id"]) != mid:
			return String(o["id"])
	return mid

## 阳性对照用的**全状态**指纹：把 save_game 会存的那一整坨折成一个数。
## 它比任何逐字段指纹都宽 ⇒ "干预落地了没有"这个判断不依赖我对该字段的理解是否正确。
func _full_fp(S) -> int:
	var h: int = Inv.CHAIN_INIT
	for p in S.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var nm := String(p["name"])
		if nm in SAVE_DERIVED or nm in SAVE_VIEW_PARAMS or nm in SAVE_BENCH_ONLY:
			continue
		var v = S.get(nm)
		if v is Object or v is Callable or nm == "agents":
			continue
		h = SimScript.fnv1a32_into(h, "%s=%s" % [nm, var_to_bytes(v).hex_encode()])
	for ag in S.agents:
		for k in (ag as Dictionary).keys():
			var vv = (ag as Dictionary)[k]
			if vv is Object:
				# memory 是嵌套 Object：折它的 items 条数与末条文本（够分辨"多了一条记忆"）
				if vv != null and "items" in vv:
					var it: Array = vv.items
					h = SimScript.fnv1a32_into(h, "mem:%d:%s" % [it.size(),
						String((it[it.size() - 1] as Dictionary).get("text", "")) if not it.is_empty() else ""])
				continue
			h = SimScript.fnv1a32_into(h, "%s.%s=%s" % [String(ag["id"]), String(k), var_to_bytes(vv).hex_encode()])
	return h

func _boot():
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if n_agents > 0:
		S.spawn_count = n_agents
	S.start_new(seed_base)
	return S

## 通用扰动：返回 [成功?, 新值]。**不就地改**（返回深拷贝）⇒ 调用方恢复原值时不会拿到被污染的对象。
func _perturb(v) -> Array:
	if v is bool: return [true, not v]
	if v is int: return [true, int(v) + 1]
	if v is float: return [true, float(v) + 1.0]
	if v is String: return [true, String(v) + "Z"]
	if v is StringName: return [true, StringName(String(v) + "Z")]
	if v is Vector2i: return [true, Vector2i(v.x + 1, v.y)]
	if v is Vector2: return [true, Vector2(v.x + 1.0, v.y)]
	if v is Dictionary:
		var d: Dictionary = (v as Dictionary).duplicate(true)
		if d.is_empty():
			d["__ac1__"] = 1
			return [true, d]
		var k = d.keys()[0]
		var sub := _perturb(d[k])
		if bool(sub[0]):
			d[k] = sub[1]
		else:
			d["__ac1__"] = 1
		return [true, d]
	if v is Array:
		var a: Array = (v as Array).duplicate(true)
		if a.is_empty():
			a.append("__ac1__")
			return [true, a]
		var sub2 := _perturb(a[0])
		if bool(sub2[0]):
			a[0] = sub2[1]
		else:
			a.append("__ac1__")
		return [true, a]
	if v is PackedStringArray:
		var ps: PackedStringArray = v
		var ps2 := PackedStringArray(ps)
		ps2.append("__ac1__")
		return [true, ps2]
	return [false, null]
