extends SceneTree
## bench/log_decisions.gd — Phase-0 bake-off dataset (docs/22 §5). Runs the deterministic logic
## floor across seeds; via Sim.decision_sink logs EVERY decision {state, per-candidate features,
## logic-pick, labeling-prompt} to JSONL. No model needed; deterministic; downstream stratifies on
## min_need/crisis to over-sample dramatic tail states. build_prompt reimplemented here (AIBackend.gd
## references the Sim autoload global → can't preload standalone), identical to dump_decide_prompt.gd.
## 用法: godot --headless --path . --script res://bench/log_decisions.gd -- [--seeds 1-4] [--days 20] [--out PATH] [--noprompt]
const SimScript = preload("res://scripts/Sim.gd")

const NEED_ZH := {"hunger": "饥饿", "energy": "精力", "social": "社交", "fun": "趣味", "hygiene": "卫生"}
const ACTION_ZH := {
	"greet": "打招呼", "give": "送礼", "gossip": "说八卦", "gossip_rep": "提醒名声",
	"discuss": "聊看法", "invite": "约见", "confront": "当面理论", "apologize": "道歉",
	"confide": "说心事", "leak": "说漏秘密", "endorse": "统一口径", "rally_oust": "联合施压", "aid": "搭把手",
}

func _sys_prompt() -> String:
	return "你是像素小镇的居民。从下面【候选】里挑一个此刻最想做的行动，只回它的【编号】（一个字符，如 3 或 A），别回任何其它字。 /no_think"

func _phase_zh(tod: float) -> String:
	if tod < 0.22: return "深夜"
	elif tod < 0.34: return "清晨"
	elif tod < 0.55: return "上午"
	elif tod < 0.68: return "午后"
	elif tod < 0.86: return "黄昏"
	return "夜里"

func _rel_hint(agent: Dictionary, oid: String) -> String:
	var rels: Dictionary = agent.get("relationships", {})
	if not rels.has(oid): return "还不熟"
	var r: Dictionary = rels[oid]
	var aff := float(r.get("affinity", 0.0))
	var fam := float(r.get("familiarity", 0.0))
	if aff <= -15.0: return "有过节"
	if fam >= 8.0 and aff >= 15.0: return "老友"
	if fam >= 8.0: return "熟人"
	if aff >= 15.0: return "投缘"
	return "点头之交"

func _mood(agent: Dictionary) -> Array:
	var low_id := ""
	var low_v := 101.0
	for nid in agent.get("needs", {}):
		var v := float(agent["needs"][nid])
		if v < low_v: low_v = v; low_id = nid
	var mood := "还算自在"
	if low_v < 25.0: mood = "有点撑不住了"
	elif low_v < 45.0:
		match low_id:
			"hunger": mood = "肚子有点饿"
			"energy": mood = "有些困乏"
			"social": mood = "想找人说说话"
			"fun": mood = "有点无聊"
			"hygiene": mood = "想收拾一下自己"
			_: mood = "有些不自在"
	return [mood, low_id, low_v]

func _idx_label(i: int) -> String:
	return str(i) if i < 10 else char(65 + i - 10)

## top-36 by score, deterministic (score desc, 平手取原下标小者) → 与 AIBackend._cap_for_llm 同义、但稳定可复现。
func _cap_order(cands: Array) -> Array:
	var idx := []
	for i in cands.size(): idx.append(i)
	idx.sort_custom(func(a, b):
		var sa := float((cands[a] as Dictionary).get("score", 0.0))
		var sb := float((cands[b] as Dictionary).get("score", 0.0))
		if sa != sb: return sa > sb
		return a < b)
	return idx.slice(0, mini(36, idx.size()))

func _build_prompt(S, agent: Dictionary, cands: Array, ctx: Dictionary) -> String:
	var p: Dictionary = agent.get("persona", {})
	var traits: Array = p.get("traits", [])
	var lines := []
	lines.append("[人设] %s：性格%s，口吻%s" % [p.get("name", ""), "·".join(traits), p.get("style", "")])
	var m := _mood(agent)
	lines.append("[此刻] 第%d天·%s，%s" % [int(ctx.get("day", 1)), _phase_zh(float(ctx.get("tod", 0.0))), String(m[0])])
	if String(m[1]) != "":
		lines.append("[状态] 最想满足:%s(%d/100)" % [NEED_ZH.get(m[1], m[1]), int(m[2])])
	var mem_obj = agent.get("memory")
	if mem_obj != null:
		var mem: Array = mem_obj.retrieve([], int(ctx.get("tick", 0)), 2)
		if not mem.is_empty():
			lines.append("[近事] " + "；".join(mem))
	var opts := []
	for i in cands.size():
		var c: Dictionary = cands[i]
		var act := String(c.get("action", ""))
		var label := String(ACTION_ZH.get(act, act))
		if String(c.get("kind", "")) == "social":
			var pid := String(c.get("partner", ""))
			label += "→%s(%s)" % [S._name(S.get_agent(pid)), _rel_hint(agent, pid)]
		opts.append("%s=%s" % [_idx_label(i), label])
	lines.append("[候选] " + " ".join(opts))
	return "\n".join(lines)

# ── 富态 canonical case packet（codex 评审 Phase B/C）：只含【角色可知】信息，teacher 与独立 judge 共用同一份。──
# ①需求按量表呈现，只有低于阈值才标 urgent（71/100 = 完全不急，而非"最想满足饥饿"→ 杜绝 need-greedy 诱导）。
# ②候选用【不透明 id + 确定性乱序】（不按 logic score 排）→ 杜绝"顺序=分数"泄漏。
# ③补 bio/role、动作 meaning、角色已知秘密、相关关系/承诺/冲突 → teacher/judge 有足够信息做社会判断。
const NEED_URGENT := 45.0

func _hstr(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = ((h ^ s.unicode_at(i)) * 16777619) & 0x7fffffff
	return h

func _band_aff(v: float) -> String:
	if v <= -15.0: return "有过节"
	if v >= 25.0: return "亲密"
	if v >= 12.0: return "投缘"
	if v >= 3.0: return "一般交情"
	return "冷淡"

func _band_fam(v: float) -> String:
	if v >= 12.0: return "老相识"
	if v >= 6.0: return "熟识"
	if v >= 2.0: return "点头之交"
	return "几乎不熟"

func _role_of(aid: String) -> String:
	var jobs: Dictionary = _S.jobs.get("jobs", {}) if _S.jobs is Dictionary else {}
	return String((jobs.get(aid, {}) as Dictionary).get("title", ""))

func _known_facts(ag: Dictionary) -> Array:
	var out := []
	for subj in ag.get("beliefs", {}):
		var b = ag["beliefs"][subj]
		if b is Dictionary and bool(b.get("secret", false)):
			var who := String(b.get("owner", ""))
			var tag := "（我自己的秘密）" if who == String(ag["id"]) else "（%s的秘密，我知情）" % _S._name(_S.get_agent(who))
			var claim := String(b.get("claim", "")).strip_edges()
			if claim != "": out.append(claim + tag)
	return out

func _need_block(ag: Dictionary) -> Dictionary:
	var needs := {}
	var urgent := []
	for nid in ag.get("needs", {}):
		var v := int(round(float(ag["needs"][nid])))
		needs[NEED_ZH.get(nid, nid)] = v
		if float(v) < NEED_URGENT:
			urgent.append(NEED_ZH.get(nid, nid))
	return {"needs": needs, "urgent": urgent}

func _rels_for(ag: Dictionary, pids: Dictionary) -> Array:
	var out := []
	for pid in pids:
		var rel: Dictionary = (ag.get("relationships", {}) as Dictionary).get(pid, {})
		out.append({"who": _S._name(_S.get_agent(pid)),
			"交情": _band_aff(float(rel.get("affinity", 0.0))),
			"熟悉度": _band_fam(float(rel.get("familiarity", 0.0)))})
	return out

## 主题/对象描述：人→名字；信念 cid→其 claim（gossip 说的是"什么事"，不是原始 belief key）；topic→原样。
func _subj_desc(ag: Dictionary, sid: String) -> String:
	if sid == "": return ""
	if _S._agent_by_id.has(sid): return _S._name(_S.get_agent(sid))
	var b = (ag.get("beliefs", {}) as Dictionary).get(sid, {})
	if b is Dictionary and String(b.get("claim", "")) != "":
		return "「%s」" % String(b["claim"])
	return sid

func _action_meaning(ag: Dictionary, c: Dictionary) -> String:
	var act := String(c.get("action", ""))
	var pid := String(c.get("partner", ""))
	var pn: String = _S._name(_S.get_agent(pid)) if pid != "" else ""
	var sid := String(c.get("subject", ""))
	var sn: String = _subj_desc(ag, sid)
	match act:
		"greet": return "找%s寒暄两句" % pn
		"give": return "送%s一份小礼物" % pn
		"gossip": return "把自己知道的%s的近况说给%s听" % [sn, pn]
		"gossip_rep": return "向%s提%s最近的风评/名声" % [pn, sn]
		"discuss": return "找%s聊聊对%s的看法" % [pn, sn]
		"invite": return "约%s改天见一面" % pn
		"confide": return "向%s吐露一桩自己的心事" % pn
		"leak": return "把%s的秘密说给%s听" % [sn, pn]
		"endorse": return "和%s统一口径、一起说%s的好话" % [pn, sn]
		"rally_oust": return "联合%s一起孤立/施压%s" % [pn, sn]
		"confront": return "当面找%s把话说开/理论" % pn
		"apologize": return "向%s道歉、把疙瘩解开" % pn
		"aid": return "搭把手帮%s一下" % pn
		"mediate": return "居中调解一场矛盾"
		_:
			var nd := String(c.get("need", ""))
			return "去%s%s" % [String(ACTION_ZH.get(act, act)), ("（休整%s）" % NEED_ZH.get(nd, nd) if nd != "" else "")]

## 战前分层（在两个策略选择【之前】按候选构成定义）→ 不用 logic 的输出定义 social stratum（评审 #4）。
func _strata(ag: Dictionary, cands: Array, nb: Dictionary) -> Dictionary:
	var kinds := {}
	var acts := {}
	for c in cands:
		kinds[String(c.get("kind", ""))] = true
		acts[String(c.get("action", ""))] = true
	return {
		"has_conflict_cand": acts.has("confront") or acts.has("apologize") or acts.has("mediate"),
		"has_secret_cand": acts.has("confide") or acts.has("leak") or acts.has("gossip"),
		"has_reputation_cand": acts.has("endorse") or acts.has("rally_oust") or acts.has("gossip_rep"),
		"has_social_cand": kinds.has("social"),
		"object_only": not kinds.has("social"),
		"need_urgent": not (nb["urgent"] as Array).is_empty(),
		"persona": String(ag.get("persona_key", "")),
		"ncand_bin": ("≤8" if cands.size() <= 8 else ("9-20" if cands.size() <= 20 else ">20")),
	}

## 富态 case packet：候选乱序 + 不透明 id；返回 {case, id_map(opaque→orig下标), logic_pick_id, strata}。
func _case_packet(ag: Dictionary, cands: Array, ctx: Dictionary, pick_i: int) -> Dictionary:
	var p: Dictionary = ag.get("persona", {})
	var aid := String(ag["id"])
	var nb := _need_block(ag)
	# 候选：确定性乱序（按 hash，不按 score）+ 不透明 id
	var order := range(cands.size())
	order.sort_custom(func(a, b): return _hstr("%d:%d:%s:%d" % [_seed, _S.tick_no, aid, a]) < _hstr("%d:%d:%s:%d" % [_seed, _S.tick_no, aid, b]))
	var partner_ids := {}
	var cand_out := []
	var id_map := {}
	var logic_pick_id := ""
	for oi in order:
		var c: Dictionary = cands[oi]
		var cid := "c%x" % (_hstr("%d:%d:%s:%d" % [_seed, _S.tick_no, aid, oi]) % 0xffff)
		id_map[cid] = oi
		if oi == pick_i: logic_pick_id = cid
		var pid := String(c.get("partner", ""))
		if pid != "": partner_ids[pid] = true
		var e := {"id": cid, "action": String(c.get("action", "")), "含义": _action_meaning(ag, c)}
		if pid != "": e["对象"] = _S._name(_S.get_agent(pid))
		var sid := String(c.get("subject", ""))
		if sid != "" and _S._agent_by_id.has(sid): e["涉及"] = _S._name(_S.get_agent(sid))
		cand_out.append(e)
	var case := {
		"居民": {"name": p.get("name", ""), "性格": p.get("traits", []), "身份": p.get("bio", ""), "职业": _role_of(aid)},
		"此刻": {"第几天": int(ctx.get("day", 1)), "时段": _phase_zh(float(ctx.get("tod", 0.0))),
			"位置": _S._area_label(ag["pos"]),
			"需求量表": "0=严重不足, 100=完全满足", "需求": nb["needs"], "迫切需求": nb["urgent"] if not (nb["urgent"] as Array).is_empty() else "无"},
		"近事": (ag["memory"].retrieve([], int(ctx.get("tick", 0)), 3) if ag.get("memory") != null else []),
		"关系": _rels_for(ag, partner_ids),
		"我知道的私密": _known_facts(ag),
		"候选": cand_out,
	}
	return {"case": case, "id_map": id_map, "logic_pick_id": logic_pick_id, "strata": _strata(ag, cands, nb)}

# --- logging state ---
var _packet := false
var _S = null
var _seed := 0
var _f: FileAccess = null
var _n := 0
var _with_prompt := true

func _on_decision(ag, cands, pick_i) -> void:
	var cand_recs := []
	for i in cands.size():
		var c: Dictionary = cands[i]
		var rec := {"i": i, "kind": String(c.get("kind", "")), "action": String(c.get("action", "")),
			"need": String(c.get("need", "")), "score": float(c.get("score", 0.0)),
			"partner": String(c.get("partner", "")), "subject": String(c.get("subject", ""))}
		var pid := String(c.get("partner", ""))
		if pid != "":
			var rel: Dictionary = (ag.get("relationships", {}) as Dictionary).get(pid, {})
			rec["aff"] = float(rel.get("affinity", 0.0))
			rec["fam"] = float(rel.get("familiarity", 0.0))
			rec["trust"] = float(rel.get("trust", 0.0))
		cand_recs.append(rec)
	var min_need: float = _S._min_need(ag)
	var order := _cap_order(cands)              # top-36 by score (稳定平手)：喂 LLM/teacher 的闭集，标签 0-9/A-Z
	var row := {
		"seed": _seed, "tick": _S.tick_no, "day": _S.day, "tod": _S.time_of_day(),
		"agent": String(ag.get("id", "")), "persona": String(ag.get("persona_key", "")),
		"needs": ag.get("needs", {}), "min_need": min_need, "crisis": min_need < float(_S.NEED_CRISIS),
		"n": cands.size(), "pick": pick_i, "cands": cand_recs,
		"cap_order": order, "pick_in_cap": order.find(pick_i),   # teacher 回标签 k → order[k]=原下标；pick_in_cap=logic 选择的标签位(-1=被裁,罕见)
	}
	if _packet:                                  # Phase-B 富态 case packet（角色可知信息，teacher/judge 共用）
		var pk := _case_packet(ag, cands, _S._context(ag), pick_i)
		row["case"] = pk["case"]
		row["id_map"] = pk["id_map"]
		row["logic_pick_id"] = pk["logic_pick_id"]
		row["strata"] = pk["strata"]
	elif _with_prompt:
		var capped := []
		for j in order: capped.append(cands[j])
		var user := _build_prompt(_S, ag, capped, _S._context(ag))
		row["prompt"] = "<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n" % [_sys_prompt(), user]
	_f.store_line(JSON.stringify(row))
	_n += 1

func _parse_seeds(s: String) -> Array:
	if "-" in s:
		var ab := s.split("-")
		var out := []
		for v in range(int(ab[0]), int(ab[1]) + 1): out.append(v)
		return out
	return [int(s)]

func _init() -> void:
	var seeds := _parse_seeds("1-4")
	var days := 20
	var out_path := "user://decisions.jsonl"   # 默认写 Godot user 数据目录；--out <abs> 覆盖到任意路径
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out_path = args[i + 1]
		elif args[i] == "--noprompt": _with_prompt = false
		elif args[i] == "--packet": _packet = true      # Phase-B 富态 case packet

	_f = FileAccess.open(out_path, FileAccess.WRITE)
	if _f == null:
		printerr("cannot open out: %s (err %d)" % [out_path, FileAccess.get_open_error()]); quit(1); return

	var crisis := 0
	for sd in seeds:
		_seed = sd
		_S = SimScript.new()
		get_root().add_child(_S)
		_S._load_data()
		_S.auto_run = false
		_S.backend = null
		_S.decision_sink = Callable(self, "_on_decision")
		_S.start_new(sd)
		var total: int = days * int(_S.TICKS_PER_DAY)
		for t in range(total):
			_S.tick()
		_S.decision_sink = Callable()
		_S.free()
	_f.close()
	print("=== log_decisions: seeds=%s days=%d → %d decisions → %s ===" % [str(seeds), days, _n, out_path])
	quit(0)
