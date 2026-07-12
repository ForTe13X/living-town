extends SceneTree
## bench/dump_decide_prompt.gd — dump a REAL Living Town decision prompt (Genie/Qwen chat
## format, think-off) for the NPU latency spike (docs/22 Phase-2). Faithful copy of
## AIBackend.build_prompt/_system_prompt (reimplemented here because AIBackend.gd references
## the `Sim` autoload global and can't be preloaded in --script mode). Picks the agent with the
## LARGEST legal candidate set (worst-case prefill) after a few in-game days of developed state.
## 用法: godot --headless --path . --script res://bench/dump_decide_prompt.gd -- [--seed 12] [--ticks 720]
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

func _build_prompt(S, agent: Dictionary, candidates: Array, ctx: Dictionary) -> String:
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
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var act := String(c.get("action", ""))
		var label := String(ACTION_ZH.get(act, act))
		if String(c.get("kind", "")) == "social":
			var pid := String(c.get("partner", ""))
			label += "→%s(%s)" % [S._name(S.get_agent(pid)), _rel_hint(agent, pid)]
		opts.append("%s=%s" % [_idx_label(i), label])
	lines.append("[候选] " + " ".join(opts))
	return "\n".join(lines)

func _init() -> void:
	var seed := 12
	var ticks := 720
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--ticks" and i + 1 < args.size(): ticks = int(args[i + 1])

	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.start_new(seed)
	for t in range(ticks):
		S.tick()

	var target := 12   # "typical" candidate count to bracket against worst-case
	for i in args.size():
		if args[i] == "--typical" and i + 1 < args.size(): target = int(args[i + 1])

	var best_ag = null            # worst-case: most candidates
	var best_cands: Array = []
	var typ_ag = null             # typical: candidate count closest to target
	var typ_cands: Array = []
	var typ_dist := 1 << 30
	var counts: Array = []
	for ag in S.agents:
		var cands: Array = S.agent_candidates(ag)
		counts.append(cands.size())
		if cands.size() > best_cands.size():
			best_ag = ag; best_cands = cands
		var dist: int = abs(cands.size() - target)
		if cands.size() >= 4 and dist < typ_dist:
			typ_dist = dist; typ_ag = ag; typ_cands = cands
	if best_ag == null:
		printerr("no agent with candidates"); quit(1); return

	var sys := _sys_prompt()
	print("=== DUMP seed=%d ticks=%d agents=%d cand_counts=%s ===" % [seed, ticks, S.agents.size(), str(counts)])
	for tag in [["WORST", best_ag, best_cands], ["TYP", typ_ag, typ_cands]]:
		var nm: String = tag[0]
		var ag = tag[1]
		var cands: Array = tag[2]
		if ag == null: continue
		var user := _build_prompt(S, ag, cands, S._context(ag))
		var full := "<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n" % [sys, user]
		print("%s agent: %s  candidates=%d  user_chars=%d" % [nm, String(ag.get("id", "?")), cands.size(), user.length()])
		print("===PROMPT_%s_BEGIN===" % nm)
		print(full)
		print("===PROMPT_%s_END===" % nm)
	quit(0)
