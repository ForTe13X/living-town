extends SceneTree
## bench/affinity_ledger.gd — B11 诊断台（只读）：全镇 affinity 收支账本 + gossip_rep 拒绝解剖。
##
## 用法（--script 的 _init() 阶段 autoload 尚未挂上（docs/41 §2 更正：autoload 其实是加载的） → preload Sim 实例化，同 Harness.gd 纪律）：
##   godot --headless --path game --script res://bench/affinity_ledger.gd -- \
##       [--seeds 1-12] [--days 60] [--out /tmp/lt_ledger.json]
##
## 三条测量纪律（为什么不能拿「次数 × 常数」当账本）：
##  1) affinity 每一次写入都过 clampf(...,-100,100)（Sim.gd:1677/1798/...）。夹到地板后再拒绝 → 真实变化 = 0。
##     所以名义流量（次数×常数）会【系统性高估】赤字。本台账同时给出 realized（真值）与 nominal（名义）与二者之差 = clamp 损耗。
##  2) realized 取自【每 tick 全量 affinity 矩阵差分】，不是重放常数 → 与引擎实现无关，改常数也不会说谎。
##     省算优化：affinity 的每一处写入都紧邻一次 _log_event（已逐条核对 Sim.gd 全部 13 个写入点），
##     故只在「本 tick 有新事件」时差分；日界做一次全量对账（realized 累计 + 初值 == 实测总和），
##     不符即打 ledger_mismatch → 该优化的前提当场被证伪，不会静默给出错账。
##  3) 归因按 (ordered pair, tick)：某个有向对在某 tick 只被一条事件认领 → 唯一归因；被多条认领 → 计入 ambiguous 桶
##     （报告其占比；占比小才说明账本可信）。绝不猜。
##
## 常量表逐条抄自 scripts/Sim.gd，仅用于算 nominal 与 clamp 损耗；realized 不依赖它。
const SimScript = preload("res://scripts/Sim.gd")

# Sim.gd:1692-1794 —— 接受后双方 [aff_actor, aff_target]
const AFF_ACCEPT := {
	"greet": [2.0, 2.0], "give": [2.0, 6.0], "gossip": [1.0, 1.0], "gossip_rep": [1.0, 1.0],
	"discuss": [1.0, 1.0], "confide": [2.0, 2.0], "leak": [1.0, 1.0], "endorse": [1.0, 1.0],
	"aid": [3.0, 3.0], "invite": [2.0, 2.0],
}
const REFUSE_AFF := -3.0            # Sim.gd:1677/1678 —— 任何社交动作被拒，双方各 -3
const INGROUP_ACTIONS := ["greet", "give", "gossip", "discuss"]   # Sim.gd:1796 同派系额外 +1/+1
const FACTION_INGROUP_AFF := 1.0
const GOSSIP_REP_SUBJ := -2.0       # Sim.gd:1730 —— 接受后 listener 对被议论者 C 的 affinity
const ENDORSE_SUBJ := -3.0          # Sim.gd:1778 —— FACTION_ENDORSE_AFF
const MEET_OK := 3.0                # Sim.gd:1844/1845
const MEET_BROKEN := -5.0           # Sim.gd:1868（只落在被放鸽子的一方）
const CONFRONT_OK := -2.0           # Sim.gd:1954/1955
const CONFRONT_NO := -3.0           # Sim.gd:1966（只落 A→B）
const APOLOGIZE_OK := 6.0           # Sim.gd:1992/1993
const PACT_BROKEN := -8.0           # Sim.gd:3182
const BETRAY_AFF := -30.0           # Sim.gd:1758 BETRAY_AFF_CRASH

# 接受判定里 target 的性格保留项（Sim.gd:2534）
const RESERVED_TRAITS := ["寡言", "温柔"]
const RESERVED_VAL := -15.0
const STANDING_K := 6.0

var _seeds: Array = []
var _days := 60
var _out := ""

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_seeds = _parse_seeds("1-12")
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			_seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			_days = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
	print("=== B11 affinity ledger · seeds=%s days=%d ===" % [str(_seeds), _days])
	var per_seed: Array = []
	for sd in _seeds:
		var r := _run_one(int(sd), _days)
		per_seed.append(r)
		print("[LEDGER]" + JSON.stringify(_compact(r)))
	var agg := _aggregate(per_seed)
	_report(agg, per_seed)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"seeds": per_seed, "agg": agg}, "  "))
			f.close()
			print("→ 明细写入 %s" % _out)
	quit(0)

# ──────────────────────────────────────────────────────────────────────────
func _run_one(sd: int, days: int) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.shadow_on = true          # 纯观测探针（Sim.gd:2543 注释：不消耗 RNG、不 mutate）
	S.start_new(sd)

	var ids: Array = []
	for ag in S.agents:
		ids.append(String(ag["id"]))
	var traits := {}
	var factions0 := {}
	for ag in S.agents:
		traits[String(ag["id"])] = Array(ag.get("persona", {}).get("traits", []))
		factions0[String(ag["id"])] = String(ag.get("faction", ""))

	var prev := _snap(S)
	var total0 := _sum(prev)
	var prev_st := _snap_st(S)
	var total_st0 := _sum(prev_st)

	var realized := {}          # key -> {"d": 总真实变化, "n": 事件数}
	var nominal := {}           # key -> 总名义变化（按常数表）
	var st_realized := {}       # 同法记 standing（#15/#15v2 的放逐信号跑在 standing 上，不是 affinity）
	var st_amb := 0.0
	var st_unatt := 0.0
	var st_unatt_ctx := {}
	var ambiguous := 0.0
	var ambiguous_n := 0
	var unattributed := 0.0
	var daily: Array = []
	var mismatch_max := 0.0
	var ev_seen := 0
	var counts := {}            # "type:ok"/"type:no" -> n
	var floor_ticks := 0        # 「refuse 落在已经贴地板的有向对上」的次数
	var refuse_events := 0
	var img_at_cut := {}
	var cut_tick := 0

	var total_ticks: int = days * int(S.TICKS_PER_DAY)
	var cum := 0.0
	for t in range(total_ticks):
		var before: int = S.event_log.size()
		S.tick()
		var n_new: int = S.event_log.size() - before
		# 日界 tick 必须进块【即使本 tick 零事件】：_nightly() 的全镇 standing 漂移就发生在这里，
		# 漏掉它会让漂移量顺延到下一个有事件的 tick 上、被错记成那条事件的效果（实测漏 2490）。
		var daybreak: bool = ((t + 1) % int(S.TICKS_PER_DAY) == 0)
		if n_new > 0 or daybreak:
			var evs: Array = []
			for i in range(before, S.event_log.size()):
				evs.append(S.event_log[i])
			for e in evs:
				var k := String(e["type"]) + (":ok" if bool(e["accepted"]) else ":no")
				counts[k] = int(counts.get(k, 0)) + 1
			# 有向对 -> 认领它的事件下标
			var claims := {}
			for i in evs.size():
				var e: Dictionary = evs[i]
				var a := String(e["actor"]); var b := String(e["target"]); var sj := String(e["subject"])
				_claim(claims, a + ">" + b, i)
				_claim(claims, b + ">" + a, i)
				if String(e["type"]) in ["gossip_rep", "endorse"] and bool(e["accepted"]) and sj != "" and sj != a and sj != b:
					_claim(claims, b + ">" + sj, i)
			var cur := _snap(S)
			for pk in cur:
				var d := float(cur[pk]) - float(prev.get(pk, 0.0))
				if d == 0.0:
					continue
				cum += d
				var owners: Array = claims.get(pk, [])
				if owners.size() == 1:
					var e2: Dictionary = evs[owners[0]]
					var role := "subject" if pk.split(">")[1] == String(e2["subject"]) and pk.split(">")[0] == String(e2["target"]) else "dyad"
					var key := _key(e2, role)
					var slot: Dictionary = realized.get(key, {"d": 0.0, "n": 0})
					slot["d"] = float(slot["d"]) + d
					slot["n"] = int(slot["n"]) + 1
					realized[key] = slot
					nominal[key] = float(nominal.get(key, 0.0)) + _nominal(e2, role, pk, S)
				elif owners.size() > 1:
					ambiguous += d
					ambiguous_n += 1
				else:
					unattributed += d
			# ── standing 账本（放逐信号的真正载体）──
			# 认领集【逐点精确】：已把 Sim.gd 里全部 11 处 standing 写入点 + 全部 _judge_actor 调用点
			# （1683/1685/1767/1770/1791/1970/1996/3104/3183 + 1729/1776/1848/1869/1967/1994）映射成有向对。
			var st_claims := {}
			for i2 in evs.size():
				for pk3 in _st_pairs(evs[i2], S):
					_claim(st_claims, pk3, i2)
			var cur_st := _snap_st(S)
			# 日界 tick 上 _nightly() 会做【全镇 standing 向 0 漂移一步】(Sim.gd:1238-1240，每 3 天一次)。
			# 它不是任何一条事件的效果，混进事件归因就是撒谎 → 整个日界 tick 的 standing 变化单列一桶。
			# 代价：每 seed 60/14400 个 tick 的事件归因让位给漂移桶（夜间社交本就稀）。
			for pk2 in cur_st:
				var d2 := float(cur_st[pk2]) - float(prev_st.get(pk2, 0.0))
				if d2 == 0.0:
					continue
				if daybreak:
					var sd2: Dictionary = st_realized.get("@nightly_drift", {"pos": 0.0, "neg": 0.0, "n": 0})
					if d2 > 0.0: sd2["pos"] = float(sd2["pos"]) + d2
					else: sd2["neg"] = float(sd2["neg"]) + d2
					sd2["n"] = int(sd2["n"]) + 1
					st_realized["@nightly_drift"] = sd2
					continue
				var own2: Array = st_claims.get(pk2, [])
				if own2.size() == 0:
					st_unatt += absf(d2)
					# 未归因不许静默：按「本 tick 同现的事件类型集合」分桶并在报告里打出来，
					# 好让读者看见账本还漏了哪条通道，而不是把漏账混进结论。
					var ctx: Array = []
					for ee in evs:
						var tn := String(ee["type"]) + ("/ok" if bool(ee["accepted"]) else "/no")
						if not (tn in ctx):
							ctx.append(tn)
					ctx.sort()
					var ck := ",".join(ctx)
					st_unatt_ctx[ck] = float(st_unatt_ctx.get(ck, 0.0)) + absf(d2)
				elif own2.size() == 1:
					var e5: Dictionary = evs[own2[0]]
					var k5 := String(e5["type"]) + (":ok" if bool(e5["accepted"]) else ":no")
					var sl2: Dictionary = st_realized.get(k5, {"pos": 0.0, "neg": 0.0, "n": 0})
					if d2 > 0.0: sl2["pos"] = float(sl2["pos"]) + d2
					else: sl2["neg"] = float(sl2["neg"]) + d2
					sl2["n"] = int(sl2["n"]) + 1
					st_realized[k5] = sl2
				else:
					st_amb += absf(d2)
			prev_st = cur_st
			# 拒绝落在地板上的次数（clamp 吞掉全部惩罚）
			for e3 in evs:
				if not bool(e3["accepted"]):
					refuse_events += 1
					var pa := String(e3["actor"]) + ">" + String(e3["target"])
					if float(prev.get(pa, 0.0)) <= -100.0:
						floor_ticks += 1
			prev = cur
		# 前瞻探针（#15-affinity 试点）：在 days-10 日界拍一张【每 agent 受到的 affinity 画像】。
		# 预测量在前、结果量在后 → 结构上不可能有 docs/31 那种时间泄漏（终态标签 × 全程结果）。
		if t + 1 == (days - 10) * int(S.TICKS_PER_DAY):
			img_at_cut = _agent_end_stats(S)
			cut_tick = int(S.tick_no)
		if (t + 1) % int(S.TICKS_PER_DAY) == 0:
			var now := _snap(S)
			var tot := _sum(now)
			var mm := absf((total0 + cum) - tot)
			if mm > mismatch_max:
				mismatch_max = mm
			prev = now
			daily.append(_day_row(S, now, int((t + 1) / int(S.TICKS_PER_DAY)), tot))
		ev_seen = S.event_log.size()

	# ── shadow 解剖：gossip_rep 的接受判定 ─────────────────────────────
	var shadow := _shadow_stats(S, traits)
	var agents_end := _agent_end_stats(S)
	var outcast := _outcast_window(S)

	var res := {
		"seed": sd, "days": days, "n_agents": S.agents.size(), "events": ev_seen,
		"counts": counts, "realized": realized, "nominal": nominal,
		"st_realized": st_realized, "st_ambiguous": st_amb, "st_unattributed": st_unatt, "st_unatt_ctx": st_unatt_ctx,
		"standing_start": total_st0, "standing_end": _sum(prev_st), "outcast": outcast,
		"ambiguous_delta": ambiguous, "ambiguous_n": ambiguous_n, "unattributed_delta": unattributed,
		"total_affinity_start": total0, "total_affinity_end": _sum(prev),
		"ledger_mismatch_max": mismatch_max,
		"refuse_events": refuse_events, "refuse_on_floor": floor_ticks,
		"daily": daily, "shadow": shadow, "agents_end": agents_end,
		"lookahead": _lookahead(S, img_at_cut, cut_tick),
	}
	get_root().remove_child(S)
	S.free()
	return res

func _claim(claims: Dictionary, pk: String, i: int) -> void:
	var a: Array = claims.get(pk, [])
	if not (i in a):
		a.append(i)
	claims[pk] = a

func _key(e: Dictionary, role: String) -> String:
	return String(e["type"]) + (":ok" if bool(e["accepted"]) else ":no") + (":subject" if role == "subject" else "")

## 名义变化：按常数表算「若无 clamp 本该落多少」（单个有向对）。
func _nominal(e: Dictionary, role: String, pk: String, S) -> float:
	var ty := String(e["type"])
	var acc := bool(e["accepted"])
	var parts := pk.split(">")
	var from_id := String(parts[0])
	if role == "subject":
		return GOSSIP_REP_SUBJ if ty == "gossip_rep" else ENDORSE_SUBJ
	match ty:
		"meet":
			return MEET_OK if acc else MEET_BROKEN
		"confront":
			return CONFRONT_OK if acc else CONFRONT_NO
		"apologize":
			return APOLOGIZE_OK if acc else REFUSE_AFF
		"pact":
			return PACT_BROKEN
		"betray":
			return BETRAY_AFF
		"mediate":
			return 0.0
	if not acc:
		return REFUSE_AFF
	if not AFF_ACCEPT.has(ty):
		return 0.0
	var pair: Array = AFF_ACCEPT[ty]
	var v := float(pair[0]) if from_id == String(e["actor"]) else float(pair[1])
	if ty in INGROUP_ACTIONS:
		var A: Dictionary = S._agent_by_id.get(String(e["actor"]), {})
		var B: Dictionary = S._agent_by_id.get(String(e["target"]), {})
		if not A.is_empty() and not B.is_empty() and String(A["faction"]) != "" and String(A["faction"]) == String(B["faction"]):
			v += FACTION_INGROUP_AFF
	return v

## 一条事件【可能】改哪些有向对的 standing —— 逐点抄自 Sim.gd，不做超集猜测。
func _st_pairs(e: Dictionary, S) -> Array:
	var ty := String(e["type"])
	var a := String(e["actor"]); var b := String(e["target"]); var sj := String(e["subject"])
	var acc := bool(e["accepted"])
	var ws: Array = e["witnesses"]
	var out: Array = []
	match ty:
		"meet":
			return [a + ">" + b, b + ">" + a]                       # :1848/1849 守约；:1869 爽约
		"confront":
			if acc:
				return []                                            # :1954 只动 affinity
			out.append(a + ">" + b)                                  # :1967 否认
			for w in ws: out.append(String(w) + ">" + b)             # :1970
			return out
		"apologize":
			if acc:
				out.append(b + ">" + a)                              # :1994 ra=_rel(A=target,B=actor)
				for w in ws: out.append(String(w) + ">" + a)         # :1996
				return out
		"betray":
			out.append(b + ">" + a)                                  # :1759 被背叛者(=target)对泄密者
			out.append(b + ">" + a)
			for w in ws: out.append(String(w) + ">" + a)             # :1770
			return out
		"pact":
			return [a + ">" + b]                                     # :3183 victim>freerider
		"rally_oust":
			for ag in S.agents: out.append(String(ag["id"]) + ">" + b)   # :3104 全体派系成员判 target
			return out
		"conflict":
			return []
	if not acc:
		out.append(a + ">" + b)                                      # :1683 提议者判拒绝者
		for w in ws: out.append(String(w) + ">" + b)                 # :1685 旁观者判拒绝者
		return out
	match ty:
		"gossip_rep": return [b + ">" + sj] if sj != "" and S._agent_by_id.has(sj) else []   # :1729
		"endorse":    return [b + ">" + sj] if sj != "" and S._agent_by_id.has(sj) else []   # :1776
		"aid":        return [b + ">" + a]                            # :1791
		"leak":       return [b + ">" + a]                            # 泄密本身的 target 判定走 betray 事件
	return []

func _snap(S) -> Dictionary:
	var out := {}
	for ag in S.agents:
		var aid := String(ag["id"])
		var rels: Dictionary = ag["relationships"]
		for oid in rels:
			out[aid + ">" + String(oid)] = float(rels[oid]["affinity"])
	return out

func _snap_st(S) -> Dictionary:
	var out := {}
	for ag in S.agents:
		var aid := String(ag["id"])
		var rels: Dictionary = ag["relationships"]
		for oid in rels:
			out[aid + ">" + String(oid)] = float(rels[oid]["standing"])
	return out

func _sum(m: Dictionary) -> float:
	var s := 0.0
	for k in m:
		s += float(m[k])
	return s

func _day_row(S, snap: Dictionary, day: int, tot: float) -> Dictionary:
	var n := snap.size()
	var neg := 0; var flo := 0; var mn := 0.0
	for k in snap:
		var v := float(snap[k])
		if v < 0.0: neg += 1
		if v <= -99.5: flo += 1
		if v < mn: mn = v
	var st_neg := 0; var st_sum := 0.0; var st_n := 0
	for ag in S.agents:
		var rels: Dictionary = ag["relationships"]
		for oid in rels:
			var st := float(rels[oid]["standing"])
			st_sum += st; st_n += 1
			if st <= -2.0: st_neg += 1
	return {"day": day, "total": tot, "dyads": n, "mean": tot / float(maxi(1, n)),
		"neg_dyads": neg, "floor_dyads": flo, "min": mn,
		"standing_mean": st_sum / float(maxi(1, st_n)), "standing_le_-2": st_neg}

## gossip_rep 接受判定的解剖：margin 分项 + 谁拒谁 + 集中度。
## margin ≡ aff + reserved + standing*K + fac + jitter − thr(=accept_gossip=0)  ← 判定式左端全部可见项
func _shadow_stats(S, traits: Dictionary) -> Dictionary:
	var by_action := {}
	var pair_att := {}          # "actor>target" -> [attempts, refused]（gossip_rep）
	var tgt_ref := {}           # listener -> refused
	var act_ref := {}           # speaker  -> refused
	var terms_ref := {"aff": 0.0, "res": 0.0, "st": 0.0, "fac": 0.0, "jit": 0.0, "n": 0}
	var terms_ok := {"aff": 0.0, "res": 0.0, "st": 0.0, "fac": 0.0, "jit": 0.0, "n": 0}
	var ident_err := 0.0
	var by_trait := {}          # listener trait class -> [attempts, refused]
	for rec in S.shadow_trace:
		var act := String(rec["action"])
		var a2: Array = by_action.get(act, [0, 0, 0])   # attempts, refused, hard
		a2[0] += 1
		if not bool(rec["accepted"]): a2[1] += 1
		if bool(rec["hard"]): a2[2] += 1
		by_action[act] = a2
		if act != "gossip_rep":
			continue
		var sp := String(rec["actor"]); var li := String(rec["target"])
		var pk := sp + ">" + li
		var p: Array = pair_att.get(pk, [0, 0])
		p[0] += 1
		var tl: Array = traits.get(li, [])
		var cls := "爱八卦" if "爱八卦" in tl else ("寡言/温柔" if ("寡言" in tl or "温柔" in tl) else "普通")
		var bt: Array = by_trait.get(cls, [0, 0])
		bt[0] += 1
		var reserved := 0.0
		if not bool(rec["hard"]):
			for tr in RESERVED_TRAITS:
				if tr in tl:
					reserved = RESERVED_VAL
					break
		if not bool(rec["accepted"]):
			p[1] += 1; bt[1] += 1
			tgt_ref[li] = int(tgt_ref.get(li, 0)) + 1
			act_ref[sp] = int(act_ref.get(sp, 0)) + 1
		pair_att[pk] = p; by_trait[cls] = bt
		if bool(rec["hard"]):
			continue    # 硬接受不走数值式
		var st := float(rec["standing"]) * STANDING_K
		var recon := float(rec["aff"]) + reserved + st + float(rec["fac"]) + float(rec["jitter"])
		ident_err = maxf(ident_err, absf(recon - float(rec["margin"])))
		var bag: Dictionary = terms_ok if bool(rec["accepted"]) else terms_ref
		bag["aff"] = float(bag["aff"]) + float(rec["aff"])
		bag["res"] = float(bag["res"]) + reserved
		bag["st"] = float(bag["st"]) + st
		bag["fac"] = float(bag["fac"]) + float(rec["fac"])
		bag["jit"] = float(bag["jit"]) + float(rec["jitter"])
		bag["n"] = int(bag["n"]) + 1
	# 集中度：拒绝在有向对上的分布
	var pairs: Array = []
	for k in pair_att:
		pairs.append([k, pair_att[k][0], pair_att[k][1]])
	pairs.sort_custom(func(x, y): return int(x[2]) > int(y[2]) if int(x[2]) != int(y[2]) else String(x[0]) < String(y[0]))
	var tot_ref := 0
	for p2 in pairs:
		tot_ref += int(p2[2])
	var top5 := 0
	for i in mini(5, pairs.size()):
		top5 += int(pairs[i][2])
	return {"by_action": by_action, "gossip_rep_pairs": pairs.slice(0, 12),
		"n_pairs": pairs.size(), "refusals": tot_ref, "top5_share": float(top5) / float(maxi(1, tot_ref)),
		"by_listener_trait": by_trait, "refused_by_listener": tgt_ref, "refused_by_speaker": act_ref,
		"terms_refused": terms_ref, "terms_accepted": terms_ok, "margin_identity_maxerr": ident_err}

## 就地复刻 tools/exile_v2.py 的【绑定约束】：共识 outcast 窗口内、中立弱关系 greet/invite 的曝光数。
## 阈值全部冻结自 docs/30（不许改）：OUTCAST_IMG=-0.8 / OUTCAST_NEG=0.67 / OUTCAST_COV=0.5 /
## WEAK_TIE=0.5 / FRIEND_AFF=20 / MIN_WT=8。此处只算 n（是否够评），判定仍以 exile_v2.py 为准。
func _outcast_window(S) -> Dictionary:
	var tot := 0; var in_win := 0
	var wt_by_actor := {}
	for rec in S.shadow_trace:
		tot += 1
		var zf := float(rec["img"]) * float(rec["cov"])
		var oc := zf <= -0.8 and float(rec["neg"]) >= 0.67 and float(rec["cov"]) >= 0.5
		if oc:
			in_win += 1
		var act := String(rec["action"])
		if oc and (act == "greet" or act == "invite") \
				and absf(float(rec["standing"])) <= 0.5 and float(rec["aff"]) < 20.0:
			var a := String(rec["actor"])
			wt_by_actor[a] = int(wt_by_actor.get(a, 0)) + 1
	var mx := 0
	for a in wt_by_actor:
		mx = maxi(mx, int(wt_by_actor[a]))
	return {"decisions": tot, "in_outcast_window": in_win,
		"window_share": float(in_win) / float(maxi(1, tot)),
		"max_weak_tie_in_window": mx, "min_wt_threshold": 8, "per_actor": wt_by_actor}

## #15-affinity 试点（探索性，非结论）：用 days-10 日界的 affinity 画像去【预测】其后 10 天的
## greet/invite 被接受率。预测量严格早于结果量 → 无时间泄漏。对照 = 同 seed 其余 actor（leave-one-out）。
## 阈值一律不新设：只报相关与极值，不设 PASS/FAIL —— 立门要走 docs/30 的预注册 + held-out 流程。
func _lookahead(S, img: Dictionary, cut: int) -> Dictionary:
	if img.is_empty():
		return {}
	var prop := {}
	var acc := {}
	for rec in S.shadow_trace:
		if int(rec["tick"]) <= cut:
			continue
		var a := String(rec["action"])
		if a != "greet" and a != "invite":
			continue
		var who := String(rec["actor"])
		prop[who] = int(prop.get(who, 0)) + 1
		if bool(rec["accepted"]):
			acc[who] = int(acc.get(who, 0)) + 1
	var rows: Array = []
	for who in img:
		var n := int(prop.get(who, 0))
		if n < 8:
			continue                      # 同 exile_v2 的 MIN_WT=8：样本不够就不评
		rows.append({"actor": who, "img_aff": float(img[who]["in_aff"]), "img_st": float(img[who]["in_st"]),
			"n": n, "rate": float(acc.get(who, 0)) / float(n)})
	rows.sort_custom(func(x, y): return float(x["img_aff"]) < float(y["img_aff"]))
	var out := {"cut_tick": cut, "rows": rows, "evaluable": rows.size()}
	if rows.size() >= 2:
		var lo: Dictionary = rows[0]
		var on := 0; var oa := 0.0
		for i in range(1, rows.size()):
			on += int(rows[i]["n"]); oa += float(rows[i]["rate"]) * float(rows[i]["n"])
		out["worst_actor"] = lo["actor"]; out["worst_img_aff"] = lo["img_aff"]
		out["worst_rate"] = lo["rate"]; out["worst_n"] = lo["n"]
		out["town_loo_rate"] = oa / float(maxi(1, on)); out["town_loo_n"] = on
	return out

## 终局每 agent：收到的平均 affinity / standing（看赤字是「均匀下沉」还是「打出弃民」）
func _agent_end_stats(S) -> Dictionary:
	var out := {}
	for ag in S.agents:
		var aid := String(ag["id"])
		var s_aff := 0.0; var s_st := 0.0; var n := 0
		for b in S.agents:
			if String(b["id"]) == aid:
				continue
			var rels: Dictionary = b["relationships"]
			if rels.has(aid):
				s_aff += float(rels[aid]["affinity"]); s_st += float(rels[aid]["standing"]); n += 1
		out[aid] = {"in_aff": s_aff / float(maxi(1, n)), "in_st": s_st / float(maxi(1, n)), "raters": n}
	return out

# ── 汇总 / 报告 ────────────────────────────────────────────────────────────
func _aggregate(per: Array) -> Dictionary:
	var counts := {}; var realized := {}; var nominal := {}; var st_real := {}
	var tot_end := 0.0; var amb := 0.0; var amb_n := 0; var unatt := 0.0; var mmx := 0.0
	var ref_floor := 0; var ref_ev := 0
	var st_amb := 0.0; var st_unatt := 0.0; var st_end := 0.0; var st_uctx := {}
	var oc_tot := 0; var oc_in := 0; var oc_max := 0
	for r in per:
		for k in r["st_realized"]:
			var s2: Dictionary = st_real.get(k, {"pos": 0.0, "neg": 0.0, "n": 0})
			s2["pos"] = float(s2["pos"]) + float(r["st_realized"][k]["pos"])
			s2["neg"] = float(s2["neg"]) + float(r["st_realized"][k]["neg"])
			s2["n"] = int(s2["n"]) + int(r["st_realized"][k]["n"])
			st_real[k] = s2
		st_amb += float(r["st_ambiguous"]); st_unatt += float(r["st_unattributed"]); st_end += float(r["standing_end"])
		for ck2 in r["st_unatt_ctx"]:
			st_uctx[ck2] = float(st_uctx.get(ck2, 0.0)) + float(r["st_unatt_ctx"][ck2])
		oc_tot += int(r["outcast"]["decisions"]); oc_in += int(r["outcast"]["in_outcast_window"])
		oc_max = maxi(oc_max, int(r["outcast"]["max_weak_tie_in_window"]))
	for r in per:
		for k in r["counts"]:
			counts[k] = int(counts.get(k, 0)) + int(r["counts"][k])
		for k in r["realized"]:
			var s: Dictionary = realized.get(k, {"d": 0.0, "n": 0})
			s["d"] = float(s["d"]) + float(r["realized"][k]["d"])
			s["n"] = int(s["n"]) + int(r["realized"][k]["n"])
			realized[k] = s
		for k in r["nominal"]:
			nominal[k] = float(nominal.get(k, 0.0)) + float(r["nominal"][k])
		tot_end += float(r["total_affinity_end"])
		amb += float(r["ambiguous_delta"]); amb_n += int(r["ambiguous_n"])
		unatt += float(r["unattributed_delta"])
		mmx = maxf(mmx, float(r["ledger_mismatch_max"]))
		ref_floor += int(r["refuse_on_floor"]); ref_ev += int(r["refuse_events"])
	return {"counts": counts, "realized": realized, "nominal": nominal, "st_realized": st_real,
		"mean_total_affinity_end": tot_end / float(maxi(1, per.size())),
		"mean_total_standing_end": st_end / float(maxi(1, per.size())), "st_ambiguous": st_amb, "st_unattributed": st_unatt, "st_unatt_ctx": st_uctx,
		"ambiguous_delta": amb, "ambiguous_n": amb_n, "unattributed_delta": unatt,
		"ledger_mismatch_max": mmx, "refuse_on_floor": ref_floor, "refuse_events": ref_ev,
		"outcast_decisions": oc_tot, "outcast_in_window": oc_in, "outcast_max_wt": oc_max,
		"n_seeds": per.size()}

func _compact(r: Dictionary) -> Dictionary:
	var sh: Dictionary = r["shadow"]
	var gr: Array = sh["by_action"].get("gossip_rep", [0, 0, 0])
	var gt: Array = sh["by_action"].get("greet", [0, 0, 0])
	return {"seed": r["seed"], "aff_end": snappedf(float(r["total_affinity_end"]), 0.1),
		"gossip_rep": {"att": gr[0], "ref": gr[1], "rate": snappedf(float(gr[1]) / float(maxi(1, gr[0])), 0.001)},
		"greet": {"att": gt[0], "ref": gt[1], "rate": snappedf(float(gt[1]) / float(maxi(1, gt[0])), 0.001)},
		"mismatch": snappedf(float(r["ledger_mismatch_max"]), 0.001),
		"amb_n": r["ambiguous_n"], "refuse_on_floor": r["refuse_on_floor"]}

func _report(agg: Dictionary, per: Array) -> void:
	print("\n── 账本自检 ──")
	print("  日界对账最大偏差 = %.4f （0 = 「affinity 只在有事件的 tick 变」这一前提成立，账本闭合）" % float(agg["ledger_mismatch_max"]))
	print("  ambiguous 归因: %d 笔 / Δ=%.1f ；unattributed Δ=%.1f" % [int(agg["ambiguous_n"]), float(agg["ambiguous_delta"]), float(agg["unattributed_delta"])])
	print("  拒绝事件 %d，其中 %d 落在已贴 -100 地板的有向对上（clamp 全额吞掉惩罚）" % [int(agg["refuse_events"]), int(agg["refuse_on_floor"])])

	print("\n── affinity 账本（%d seeds 合计；realized=真值 nominal=次数×常数 loss=clamp 吞掉）──" % int(agg["n_seeds"]))
	var keys: Array = []
	for k in agg["realized"]:
		keys.append(k)
	keys.sort_custom(func(a, b): return absf(float(agg["realized"][a]["d"])) > absf(float(agg["realized"][b]["d"])))
	print("  %-24s %10s %12s %12s %10s" % ["source", "n", "realized", "nominal", "clamp_loss"])
	var sum_r := 0.0; var sum_n := 0.0
	for k in keys:
		var d := float(agg["realized"][k]["d"])
		var nm := float(agg["nominal"].get(k, 0.0))
		sum_r += d; sum_n += nm
		print("  %-24s %10d %12.1f %12.1f %10.1f" % [k, int(agg["realized"][k]["n"]), d, nm, nm - d])
	print("  %-24s %10s %12.1f %12.1f %10.1f" % ["TOTAL", "", sum_r, sum_n, sum_n - sum_r])
	print("  每 seed 平均终局全镇 affinity 总和 = %.1f" % float(agg["mean_total_affinity_end"]))

	print("\n── 尝试/拒绝（%d seeds 合计）──" % int(agg["n_seeds"]))
	var acts := {}
	for k in agg["counts"]:
		var parts = k.split(":")
		var a := String(parts[0])
		var row: Array = acts.get(a, [0, 0])
		if String(parts[1]) == "ok": row[0] += int(agg["counts"][k])
		else: row[1] += int(agg["counts"][k])
		acts[a] = row
	var alist: Array = []
	for a in acts:
		alist.append(a)
	alist.sort_custom(func(x, y): return (acts[x][0] + acts[x][1]) > (acts[y][0] + acts[y][1]))
	print("  %-16s %8s %8s %8s %8s" % ["type", "attempts", "ok", "refused", "ref%"])
	for a in alist:
		var ok := int(acts[a][0]); var no := int(acts[a][1])
		print("  %-16s %8d %8d %8d %7.1f%%" % [a, ok + no, ok, no, 100.0 * float(no) / float(maxi(1, ok + no))])

	# gossip_rep 解剖（跨 seed 合并）
	var gr_att := 0; var gr_ref := 0; var gr_hard := 0
	var tr := {"aff": 0.0, "res": 0.0, "st": 0.0, "fac": 0.0, "jit": 0.0, "n": 0}
	var to := {"aff": 0.0, "res": 0.0, "st": 0.0, "fac": 0.0, "jit": 0.0, "n": 0}
	var bt := {}
	var idmax := 0.0
	var top5 := 0.0
	for r in per:
		var sh: Dictionary = r["shadow"]
		var g: Array = sh["by_action"].get("gossip_rep", [0, 0, 0])
		gr_att += int(g[0]); gr_ref += int(g[1]); gr_hard += int(g[2])
		for f in ["aff", "res", "st", "fac", "jit"]:
			tr[f] = float(tr[f]) + float(sh["terms_refused"][f])
			to[f] = float(to[f]) + float(sh["terms_accepted"][f])
		tr["n"] = int(tr["n"]) + int(sh["terms_refused"]["n"])
		to["n"] = int(to["n"]) + int(sh["terms_accepted"]["n"])
		for c in sh["by_listener_trait"]:
			var row2: Array = bt.get(c, [0, 0])
			row2[0] += int(sh["by_listener_trait"][c][0]); row2[1] += int(sh["by_listener_trait"][c][1])
			bt[c] = row2
		idmax = maxf(idmax, float(sh["margin_identity_maxerr"]))
		top5 += float(sh["top5_share"])
	print("\n── gossip_rep 接受判定解剖（判定式 = aff + reserved + standing*6 + fac + jitter > 0；【无 subject 项】）──")
	print("  尝试 %d，拒绝 %d（%.1f%%），其中 hard-accept(爱八卦) %d" % [gr_att, gr_ref, 100.0 * float(gr_ref) / float(maxi(1, gr_att)), gr_hard])
	print("  margin 恒等式重建最大误差 = %.6f（0 → 分项解释了判定式的全部）" % idmax)
	print("  %-10s %8s %9s %9s %9s %9s %9s" % ["outcome", "n", "aff", "reserved", "standing*6", "faction", "jitter"])
	for nm in [["refused", tr], ["accepted", to]]:
		var b: Dictionary = nm[1]
		var n := maxi(1, int(b["n"]))
		print("  %-10s %8d %9.2f %9.2f %9.2f %9.2f %9.2f" % [nm[0], int(b["n"]),
			float(b["aff"]) / n, float(b["res"]) / n, float(b["st"]) / n, float(b["fac"]) / n, float(b["jit"]) / n])
	print("  按 listener 性格：")
	for c in bt:
		print("    %-10s 尝试 %6d 拒绝 %6d  (%.1f%%)" % [c, int(bt[c][0]), int(bt[c][1]), 100.0 * float(bt[c][1]) / float(maxi(1, bt[c][0]))])
	print("  拒绝集中度：top-5 有向对占全部拒绝 %.1f%%（均值 across seeds）" % (100.0 * top5 / float(maxi(1, per.size()))))

	# ── standing 账本：放逐信号真正跑在这上面 ──
	print("\n── standing 账本（%d seeds 合计；正=名声修复 负=名声打击）──" % int(agg["n_seeds"]))
	var sk: Array = []
	for k in agg["st_realized"]:
		sk.append(k)
	sk.sort_custom(func(a, b): return float(agg["st_realized"][a]["neg"]) < float(agg["st_realized"][b]["neg"]))
	print("  %-24s %10s %12s %12s" % ["source", "n", "st_neg", "st_pos"])
	var tneg := 0.0; var tpos := 0.0
	for k in sk:
		tneg += float(agg["st_realized"][k]["neg"]); tpos += float(agg["st_realized"][k]["pos"])
		print("  %-24s %10d %12.1f %12.1f" % [k, int(agg["st_realized"][k]["n"]),
			float(agg["st_realized"][k]["neg"]), float(agg["st_realized"][k]["pos"])])
	print("  %-24s %10s %12.1f %12.1f  (ambiguous |Δ| %.1f / unattributed |Δ| %.1f)" % ["TOTAL", "", tneg, tpos, float(agg["st_ambiguous"]), float(agg["st_unattributed"])])
	var uc: Dictionary = agg["st_unatt_ctx"]
	if not uc.is_empty():
		var ucl: Array = []
		for k2 in uc:
			ucl.append(k2)
		ucl.sort_custom(func(a, b): return float(uc[a]) > float(uc[b]))
		print("  未归因 |Δ| 的同现事件类型（账本仍缺的通道，按量降序，前 6）：")
		for k2 in ucl.slice(0, 6):
			print("     %-52s |Δ| %.1f" % [k2, float(uc[k2])])
	if tneg != 0.0:
		var grn := float(agg["st_realized"].get("gossip_rep:no", {"neg": 0.0})["neg"])
		print("  → gossip_rep 拒绝占全镇负向 standing 的 %.1f%%" % (100.0 * grn / tneg))
	print("  每 seed 平均终局全镇 standing 总和 = %.2f" % float(agg["mean_total_standing_end"]))

	print("\n── #15v2 绑定约束（就地复刻 exile_v2 阈值；判定仍以 tools/exile_v2.py 为准）──")
	print("  决策总数 %d，落在共识 outcast 窗口内 %d（%.2f%%）" % [int(agg["outcast_decisions"]), int(agg["outcast_in_window"]),
		100.0 * float(agg["outcast_in_window"]) / float(maxi(1, int(agg["outcast_decisions"])))])
	print("  任一 actor 在其 outcast 窗口内的【中立弱关系 greet/invite】最大曝光 = %d（可评门槛 MIN_WT=8）" % int(agg["outcast_max_wt"]))

	print("\n── 全镇 affinity 轨迹（seed %s，逐 10 天）──" % str(per[0]["seed"]))
	print("  %5s %10s %8s %8s %8s %8s %10s" % ["day", "total", "mean", "neg", "floor", "min", "st_mean"])
	for row in per[0]["daily"]:
		if int(row["day"]) % 10 != 0:
			continue
		print("  %5d %10.1f %8.2f %8d %8d %8.1f %10.3f" % [int(row["day"]), float(row["total"]), float(row["mean"]),
			int(row["neg_dyads"]), int(row["floor_dyads"]), float(row["min"]), float(row["standing_mean"])])

	print("\n── 终局每 agent 收到的平均 affinity / standing（seed %s）——赤字是均匀下沉还是打出弃民？──" % str(per[0]["seed"]))
	var ae: Dictionary = per[0]["agents_end"]
	var lst: Array = []
	for a in ae:
		lst.append(a)
	lst.sort_custom(func(x, y): return float(ae[x]["in_aff"]) < float(ae[y]["in_aff"]))
	for a in lst:
		print("    %-6s in_aff %8.2f   in_standing %7.3f" % [a, float(ae[a]["in_aff"]), float(ae[a]["in_st"])])

func _parse_seeds(spec: String) -> Array:
	var out: Array = []
	if "-" in spec:
		var ab := spec.split("-")
		for s in range(int(ab[0]), int(ab[1]) + 1):
			out.append(s)
	elif "," in spec:
		for s in spec.split(","):
			out.append(int(s))
	else:
		out.append(int(spec))
	return out
