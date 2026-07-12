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

# --- logging state ---
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
	if _with_prompt:
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
