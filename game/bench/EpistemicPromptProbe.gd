extends Node
## bench/EpistemicPromptProbe.gd — Q2：量【递给模型的那份东西】到底暴露了谁的私有状态。
##
## 背景：docs/63（P1）证明了信念层的知识局部性在【零模型地板】上逐字节成立，
## 并明写「模型路一个数据点都没有」。本探针补的就是那一格。
##
## ★ 为什么不复用 bench/dump_decide_prompt.gd（reuse-first 红线 #5 的交代）：
##   它是 `--script` 模式下对 build_prompt 的【手抄件】，而抄件已经漂了——
##   它的 `_idx_label` 还是旧的 0-9/A-Z 字母表，`_sys_prompt` 还带着 docs/42 §7.3-1
##   已经删掉的那个字面示例编号「如 3 或 A」。拿它去论证"模型看到了什么"，
##   论的是一份出货树上不存在的 prompt。
##   ⇒ 本文件走【scene 模式】直接调 AIBackend 的真函数（_system_prompt / _cap_for_llm /
##      build_prompt / _idx_label），零重实现、零漂移。这与 bench/PickCtxDump.gd 是同一条路子，
##      本文件的骨架（decision_sink 采集 + 摘钩子求基线）正是从它复用来的。
##
## 零扰动论证（红线 #1），与 PickCtxDump 同源：
##   · 采集挂在既有的只读钩子 Sim.decision_sink（不抽 RNG、不进 event_log/digest）。
##   · backend 恒 null ⇒ 世界完全由 logic 地板推进；本探针只读、只拼字符串。
##   · 唯一的"额外求值"是 AIBackend.build_prompt，它只读 agent/candidates/ctx，不写任何仿真态。
##
## 用法：
##   godot --headless --path game res://bench/EpistemicPromptProbe.tscn -- \
##       --seeds 1-3 --days 8 --agents 12 [--out <abs>.jsonl]
##
## 输出三块：
##   ① 字段清单（EMPIRICAL FIELD INVENTORY）——候选字典里【实际出现过】的每一个 key，按 kind 分组，
##      并标注它有没有被渲染进 prompt 文本。不是读代码读出来的，是跑出来的。
##   ② 泄漏判据（CONTAINMENT）——逐 prompt 逐字符检查：候选表里的 subject / partner-id /
##      target-id / score 有没有出现在文本里。
##   ③ 存在性普查（EXISTENTIAL CENSUS）——真正的泄漏通道：某个选项【存在】这件事本身，
##      是不是以另一个 agent 的私有状态为条件。这一条 ② 抓不到，所以必须单独量。

const XREAD := {                       # 存在条件读了【别人的】私有状态的动作 → 它出现在候选表里就是一次泄漏
	"gossip":     "对方 beliefs 缺这一条（_unspread_belief）",
	"confide":    "对方 beliefs 缺我的这个秘密（_confidable_secret）+ 全镇 pos 扫 EARSHOT",
	"leak":       "对方 beliefs 缺【第三人托付给我】的秘密（_leakable_secret）",
	"discuss":    "对方 attitudes[t] 与我的差在 (MINDIFF, eps] 内",
	"gossip_rep": "对方对缺席第三方 C 的私有 standing 比我高",
	"endorse":    "对方 faction == 我的 + 对方对缺席 C 的 standing 比我高",
	"rally_oust": "对方 faction != 我的",
	"aid":        "对方某个 need 低于 AID_NEED_TH",
}
const LOCALS := {                      # 存在条件只读【自己的】状态或公共事实
	"greet": 1, "give": 1, "invite": 1, "confront": 1, "apologize": 1,
}

var _f: FileAccess = null
var _seed := 0
var _rows := 0

# ── 累加器 ────────────────────────────────────────────────────────────────
var _keys_by_kind := {}                # kind -> {key -> 出现次数}
var _act_count := {}                   # action -> 次数（全部候选）
var _kind_count := {}                  # kind -> 次数
var _prompts := 0
var _prompts_with_xread := 0
var _xread_opts := 0
var _local_opts := 0
var _empty_label := 0                  # 渲染出来是空标签的候选（"C=" 后面什么都没有）
var _empty_label_kind := {}
# containment（真实 prompt）
var _c_subject := 0                    # subject 串出现在 prompt 里的次数
var _c_subject_in_cand := 0            # 其中【落在候选行】的次数——只有这一档才是渲染器泄漏
var _c_subject_n := 0                  # 非空 subject 的候选总数
var _c_partner_id := 0
var _c_partner_n := 0
var _c_target := 0
var _c_target_n := 0
var _c_need := 0
var _c_need_n := 0
# containment（负对照：把 subject 追加进文本之后，同一个 checker 必须变红）
var _mut_subject_hit := 0
var _mut_partner_hit := 0
# 名字普查
var _names_nonnearby := 0              # prompt 里出现了【当时不在场】的 agent 名字的 prompt 数
var _names_nonnearby_examples: Array = []
var _dup_names := 0                    # 重名的 agent 数（N>12 时 persona 会复用 → 名字不再是身份）
var _per_seed := {}                    # seed -> [decision points, prompts with >=1 XREAD]（契约 §5：给展布不给均值）
var _xread_per_partner := {}           # k -> 次数：同一个 prompt 里【对同一个被点名的人】同时开出的跨主体选项数
var _subject_hit_examples: Array = []  # subject 真的落进文本的例子（要逐条看清是不是渲染器泄的）
var _sample_prompts: Array = []


func _ready() -> void:
	var seeds := _parse_seeds("1-3")
	var days := 8
	var agents := 12
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size(): seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size(): agents = int(args[i + 1])
		elif args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]

	if out != "":
		_f = FileAccess.open(out, FileAccess.WRITE)
		if _f == null:
			printerr("无法写 %s (err %d)" % [out, FileAccess.get_open_error()])
			get_tree().quit(1)
			return

	Sim.spawn_count = agents
	Sim.auto_run = false
	Sim.backend = null
	print("=== EpistemicPromptProbe seeds=%s days=%d N=%d ===" % [str(seeds), days, agents])
	print("system_prompt 原文（AIBackend._system_prompt，非抄件）：")
	print("  <<<%s>>>" % AIBackend._system_prompt())
	for sd in seeds:
		_seed = sd
		Sim.start_new(sd)
		Sim.decision_sink = Callable(self, "_on_decision")
		var total: int = days * int(Sim.TICKS_PER_DAY)
		for t in range(total):
			Sim.tick()
		Sim.decision_sink = Callable()
		print("  seed %d 完成（累计 %d 个决策点）" % [sd, _prompts])
	if _f != null:
		_f.close()
	_report()
	_render_selftest()
	get_tree().quit(0)


## 构造性渲染自检：有几个动作在 30 天窗口里【一次没出现过】(confide/leak/aid/attend)，
## 所以"它们渲染成什么样"不能靠等。这里手搓一份覆盖【每一种 kind 与每一个社交动作】的候选表，
## 交给真的 AIBackend.build_prompt 渲染，把结果原样打出来。
## ⚠ 这是【纯渲染】：不进 Sim、不落地、不写任何状态，只是拿真函数照一张相。
func _render_selftest() -> void:
	print("\n=== ⑦ 构造性渲染自检（覆盖自然窗口里没出现过的动作）===")
	var ag: Dictionary = Sim.agents[0]
	var pid := String(Sim.agents[1]["id"])
	var synth: Array = []
	for a in ["greet", "give", "gossip", "gossip_rep", "discuss", "invite", "confront",
			"apologize", "confide", "leak", "endorse", "rally_oust", "aid"]:
		synth.append({"kind": "social", "action": a, "partner": pid,
			"subject": "SUBJECT_CANARY", "need": "social", "score": 1.0, "say": ""})
	synth.append({"kind": "object", "action": "吃饭", "target": "OBJ_CANARY", "need": "hunger",
		"amount": 30, "dur_total": 4, "score": 1.0, "say": ""})
	synth.append({"kind": "journey", "action": "喝咖啡", "target": "OBJ_CANARY2", "need": "fun",
		"dest_space": "cafe", "dest_floor": "indoor", "amount": 20, "dur_total": 4, "score": 1.0, "say": ""})
	# attend 照 Sim._attend_candidates 的【原样字段集】造：它没有 action 键。
	synth.append({"kind": "attend", "area": "AREA_CANARY", "commit": "COMMIT_CANARY", "score": 1.0, "say": ""})
	var out: String = AIBackend.build_prompt(ag, synth, Sim._context(ag))
	print(out)
	var cand_line := String(out.split("[候选]")[-1])
	print("\n  候选行里出现 SUBJECT_CANARY : %s" % str(cand_line.find("SUBJECT_CANARY") >= 0))
	print("  候选行里出现 OBJ_CANARY     : %s" % str(cand_line.find("OBJ_CANARY") >= 0))
	print("  候选行里出现 AREA_CANARY    : %s" % str(cand_line.find("AREA_CANARY") >= 0))
	print("  候选行里出现 COMMIT_CANARY  : %s" % str(cand_line.find("COMMIT_CANARY") >= 0))
	print("  候选行里出现 partner id(%s) : %s" % [pid, str(cand_line.find(pid) >= 0)])


## 采集一个决策点。ag/cands 由 Sim.decision_sink 给（只读）。
func _on_decision(ag, cands, _pick_i) -> void:
	var capped: Array = AIBackend._cap_for_llm(cands)
	if capped.size() < 2:
		return
	var ctx: Dictionary = Sim._context(ag)
	var prompt: String = AIBackend.build_prompt(ag, capped, ctx)
	_prompts += 1

	# 当时【在场】的人（引擎的空间门），用于名字普查
	var nearby := {}
	for o in Sim._nearby_agents(ag):
		nearby[String(Sim._name(o))] = true

	var has_xread := false
	var mut_tokens: Array = []          # 负对照要追加的 subject 串
	var mut_pids: Array = []
	var xr_by_partner := {}             # partner id -> 本 prompt 里针对他开出的跨主体选项数
	for i in capped.size():
		var c: Dictionary = capped[i]
		var kind := String(c.get("kind", ""))
		var act := String(c.get("action", ""))
		_kind_count[kind] = int(_kind_count.get(kind, 0)) + 1
		_act_count[act] = int(_act_count.get(act, 0)) + 1
		if not _keys_by_kind.has(kind):
			_keys_by_kind[kind] = {}
		for k in c.keys():
			var kk := String(k)
			_keys_by_kind[kind][kk] = int(_keys_by_kind[kind].get(kk, 0)) + 1

		# 渲染出来的标签（照 build_prompt 的规则判空：ACTION_ZH 缺 key 就吐 action 本身，
		# action 本身为空 ⇒ 整个标签为空 ⇒ 模型看到一个没有内容的槽位）
		if act == "":
			_empty_label += 1
			_empty_label_kind[kind] = int(_empty_label_kind.get(kind, 0)) + 1

		if XREAD.has(act):
			_xread_opts += 1
			has_xread = true
			var xp := String(c.get("partner", ""))
			xr_by_partner[xp] = int(xr_by_partner.get(xp, 0)) + 1
		elif LOCALS.has(act) or kind in ["object", "journey", "attend"]:
			_local_opts += 1

		# ── containment：候选表里的原始串有没有落进文本 ──
		var subj := String(c.get("subject", ""))
		if subj != "":
			_c_subject_n += 1
			if prompt.find(subj) >= 0:
				_c_subject += 1
				# 关键：命中在【候选行】还是在【近事】行？前者才是渲染器泄漏，后者是本人的记忆。
				var in_cand: bool = String(prompt.split("[候选]")[-1]).find(subj) >= 0
				if in_cand:
					_c_subject_in_cand += 1
				if _subject_hit_examples.size() < 12:
					_subject_hit_examples.append("seed%d t%d %s action=%s subject=<%s> 命中于 %s" % [
						_seed, Sim.tick_no, String(ag["id"]), act, subj,
						("候选行 ← 渲染器泄漏" if in_cand else "非候选行(近事/人设) ← 本人记忆，非候选表")])
			mut_tokens.append(subj)
		var pid := String(c.get("partner", ""))
		if pid != "":
			_c_partner_n += 1
			if prompt.find(pid) >= 0:
				_c_partner_id += 1
			mut_pids.append(pid)
		var tgt := String(c.get("target", ""))
		if tgt != "":
			_c_target_n += 1
			if prompt.find(tgt) >= 0:
				_c_target += 1
		var nd := String(c.get("need", ""))
		if nd != "":
			_c_need_n += 1
			if prompt.find(nd) >= 0:
				_c_need += 1

	if has_xread:
		_prompts_with_xread += 1
	for k in xr_by_partner:
		var v := int(xr_by_partner[k])
		_xread_per_partner[v] = int(_xread_per_partner.get(v, 0)) + 1
	if not _per_seed.has(_seed):
		_per_seed[_seed] = [0, 0]
	_per_seed[_seed][0] = int(_per_seed[_seed][0]) + 1
	if has_xread:
		_per_seed[_seed][1] = int(_per_seed[_seed][1]) + 1

	# ── 负对照（§2.5 detects 必须跑出来）──────────────────────────────────
	# 不重写 build_prompt（那正是 dump_decide_prompt.gd 犯的错），只对【真 prompt 的字符串】
	# 做一次事后变异：假装渲染器把 subject / partner-id 也写了进去。同一个 checker 必须当场变红。
	if not mut_tokens.is_empty():
		var mutated: String = prompt + " " + " ".join(mut_tokens)
		for s in mut_tokens:
			if mutated.find(s) >= 0:
				_mut_subject_hit += 1
	if not mut_pids.is_empty():
		var mutated2: String = prompt + " " + " ".join(mut_pids)
		for s in mut_pids:
			if mutated2.find(s) >= 0:
				_mut_partner_hit += 1

	# ── 名字普查：prompt 里出现了当时不在场的人吗？（[近事] 会合法地提到旧人）──
	# ⚠ 名字不是身份：N>12 时 spawn 会复用 persona ⇒ 出现重名。自己的名字也在 [人设] 行里。
	#   两者都要排掉，否则这一格会报出一个纯属伪影的高百分比（第一版就踩了，实测 84.4% 全是自己）。
	var self_name := String(Sim._name(ag))
	var offstage: Array = []
	for o in Sim.agents:
		var nm := String(Sim._name(o))
		if nm == "" or String(o["id"]) == String(ag["id"]) or nm == self_name:
			continue
		if not nearby.has(nm) and prompt.find(nm) >= 0 and not offstage.has(nm):
			offstage.append(nm)
	if not offstage.is_empty():
		_names_nonnearby += 1
		if _names_nonnearby_examples.size() < 5:
			_names_nonnearby_examples.append("seed%d t%d %s → %s" % [
				_seed, Sim.tick_no, String(ag["id"]), str(offstage)])

	if _sample_prompts.size() < 6 and has_xread:
		_sample_prompts.append("--- seed%d tick%d agent=%s ---\n%s" % [_seed, Sim.tick_no, String(ag["id"]), prompt])

	if _f != null:
		var crec := []
		for c in capped:
			crec.append({"kind": c.get("kind", ""), "action": c.get("action", ""),
				"partner": c.get("partner", ""), "subject": c.get("subject", ""),
				"target": c.get("target", ""), "need": c.get("need", "")})
		_f.store_line(JSON.stringify({
			"seed": _seed, "tick": Sim.tick_no, "agent": String(ag["id"]),
			"n": cands.size(), "n_cap": capped.size(),
			"prompt": prompt, "cands": crec, "nearby": nearby.keys()}))
		_rows += 1


func _report() -> void:
	print("\n=== ① 字段清单（跑出来的，不是读代码读出来的）===")
	print("候选字典里出现过的 key，按 kind：")
	var kinds := _keys_by_kind.keys()
	kinds.sort()
	for kind in kinds:
		var ks: Array = (_keys_by_kind[kind] as Dictionary).keys()
		ks.sort()
		print("  [%s] n=%d  keys=%s" % [kind, int(_kind_count.get(kind, 0)), str(ks)])
	print("\nctx 的 key（Sim._context）：%s" % str(Sim._context(Sim.agents[0]).keys()))

	print("\n=== ② CONTAINMENT：候选表里的原始串有没有落进 prompt 文本 ===")
	print("  subject     出现 %d / %d 个非空 subject 候选，其中落在【候选行】的 %d" % [
		_c_subject, _c_subject_n, _c_subject_in_cand])
	print("  partner(id) 出现 %d / %d 个社交候选" % [_c_partner_id, _c_partner_n])
	print("  target(id)  出现 %d / %d 个物件/行程候选" % [_c_target, _c_target_n])
	print("  need(id)    出现 %d / %d 个带 need 的候选" % [_c_need, _c_need_n])
	print("  【负对照】把 subject 追加进文本后，同一 checker 命中 %d 次（必须 >0，否则 checker 是装饰）" % _mut_subject_hit)
	print("  【负对照】把 partner-id 追加进文本后，命中 %d 次" % _mut_partner_hit)
	if not _subject_hit_examples.is_empty():
		print("  ⚠ subject 命中明细（判断是渲染器泄的、还是本人记忆里本来就有那个词）：")
		for e in _subject_hit_examples:
			print("      %s" % e)

	print("\n=== ③ EXISTENTIAL CENSUS：选项【存在】这件事泄漏了什么 ===")
	print("  决策点总数                     : %d" % _prompts)
	print("  至少含一个跨主体条件选项的 prompt: %d  (%.1f%%)" % [
		_prompts_with_xread, _pct(_prompts_with_xread, _prompts)])
	print("  跨主体条件选项 / 局部条件选项    : %d / %d" % [_xread_opts, _local_opts])
	var sds := _per_seed.keys()
	sds.sort()
	var line := ""
	for sd in sds:
		var a: Array = _per_seed[sd]
		line += "  seed%d: %d/%d (%.1f%%)" % [sd, int(a[1]), int(a[0]), _pct(a[1], a[0])]
	print("  逐 seed 展布（契约 §5：给展布不给均值）:%s" % line)
	var ks := _xread_per_partner.keys()
	ks.sort()
	var hist := ""
	for k in ks:
		hist += " %d个→%d次" % [int(k), int(_xread_per_partner[k])]
	print("  同一 prompt 里【针对同一个被点名的人】同时开出的跨主体选项数分布:%s" % hist)
	var acts := _act_count.keys()
	acts.sort()
	print("  逐动作计数（★=存在条件读了别人的私有状态）：")
	for a in acts:
		var mark := "★" if XREAD.has(a) else "  "
		var why: String = String(XREAD.get(a, ""))
		print("   %s %-12s %6d   %s" % [mark, (a if a != "" else "<无 action>"), int(_act_count[a]), why])

	print("\n=== ④ 渲染缺陷：空标签 ===")
	print("  渲染成空标签的候选: %d  按 kind: %s" % [_empty_label, str(_empty_label_kind)])

	print("\n=== ⑤ 名字普查 ===")
	var seen_names := {}
	for o in Sim.agents:
		var nm := String(Sim._name(o))
		seen_names[nm] = int(seen_names.get(nm, 0)) + 1
	for nm in seen_names:
		if int(seen_names[nm]) > 1:
			_dup_names += 1
	print("  重名的显示名个数: %d（>0 ⇒ 名字不再唯一标识一个人，本节读数要打折）" % _dup_names)
	print("  prompt 里出现【当时不在场】agent 名字的决策点: %d  (%.1f%%)" % [
		_names_nonnearby, _pct(_names_nonnearby, _prompts)])
	for e in _names_nonnearby_examples:
		print("    例: %s" % e)

	print("\n=== ⑥ 样本 prompt（含跨主体条件选项）===")
	for s in _sample_prompts:
		print(s)
	if _f != null:
		print("\n（%d 行明细已写出）" % _rows)


func _pct(x, d) -> float:
	if int(d) == 0:
		return 0.0
	return 100.0 * float(x) / float(d)


func _parse_seeds(s: String) -> Array:
	if "-" in s:
		var ab := s.split("-")
		var out := []
		for v in range(int(ab[0]), int(ab[1]) + 1): out.append(v)
		return out
	if "," in s:
		var out2 := []
		for v in s.split(","): out2.append(int(v))
		return out2
	return [int(s)]
