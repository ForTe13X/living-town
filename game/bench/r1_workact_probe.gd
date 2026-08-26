extends SceneTree
## bench/r1_workact_probe.gd — R1（docs/68 §二）：**只量，不修**。
##
## 回答的问题只有一个，而它是 docs/58 §四② / docs/67 §一② 留下的那条：
##   **「看摊」这条无 job 门的广告位，今天到底是谁在用、在哪个对象上用、在不在班？**
## 派棒 brief 与 docs/58 都把它讲成"任何人都能枚举到看摊 ⇒ 咖啡师的本职被稀释"，
## 而 `Sim._object_candidates:1821` 的**家绑定**那一条与 `_staff_ok` 那一条都可能改变这个故事，
## 所以必须先量：**grep 给结构，运行才给行为。**
##
## 口径纪律（docs/41 §5）：
##   · 走既有只读钩子 `Sim.decision_sink`（:3593，只在 cands.size()>=2 时触发、不抽 RNG、不进 digest）。
##     探针挂上之后 digest 必须与不挂时逐字节相同 —— 本文件自己就跑这条对照（--selfcheck）。
##   · 逐 seed 输出，**不做平均**。
##   · 同时数【被枚举到】与【被选中】两个量：L2 的 `_causal` 那条教训是"能看见"与"会去做"不是一回事。
##
## 用法：
##   godot --headless --path game -s res://bench/r1_workact_probe.gd -- \
##       --agents 12 --seeds 1-3 --days 60 [--selfcheck]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _pick_act: Dictionary = {}      # "action@target" -> 被选中次数
var _pick_by_ag: Dictionary = {}    # "agent|action@target" -> 次数
var _offer_act: Dictionary = {}     # "action@target" -> 被枚举到次数（候选表里出现过）
var _offer_by_ag: Dictionary = {}
var _S = null

func _init() -> void:
	var seeds := _parse_seeds("1-3")
	var days := 60
	var agents := 0
	var selfcheck := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--selfcheck":
			selfcheck = true

	print("=== r1_workact_probe · agents=%d seeds=%s days=%d selfcheck=%s ===" % [
		agents, str(seeds), days, str(selfcheck)])
	for sd in seeds:
		var rec := _run_once(sd, days, agents, true)
		if selfcheck:
			var bare := _run_once(sd, days, agents, false)
			rec["digest_no_probe"] = bare["digest"]
			rec["probe_nonperturbing"] = (String(rec["digest"]) == String(bare["digest"]))
		print("[WORKACT] " + JSON.stringify(rec))
	quit(0)

func _run_once(seed: int, days: int, agents: int, hook: bool) -> Dictionary:
	_pick_act = {}; _pick_by_ag = {}; _offer_act = {}; _offer_by_ag = {}
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	_S = S
	if hook:
		S.decision_sink = Callable(self, "_on_decision")
	S.start_new(seed)
	for _t in range(days * int(S.TICKS_PER_DAY)):
		S.tick()
	var rec: Dictionary = {
		"seed": seed, "n_agents": S.agents.size(), "days": days,
		"digest": str(Inv.digest(S)),
		"work_by_title": (S.prod_stats.get("work", {}) as Dictionary).duplicate(true),
	}
	if hook:
		rec["pick"] = _pick_act.duplicate(true)
		rec["offer"] = _offer_act.duplicate(true)
		rec["pick_by_agent"] = _pick_by_ag.duplicate(true)
		rec["offer_by_agent"] = _offer_by_ag.duplicate(true)
		# 谁是咖啡师 / 她的家在哪 —— 判 counter_1 的看摊对她开不开，靠的是这两个字段
		var who: Dictionary = {}
		for ag in S.agents:
			var jb: Dictionary = S._job_of(String(ag["id"]))
			if not jb.is_empty():
				who[String(ag["id"])] = "%s/%s/home=%s" % [
					String(jb.get("title", "")), String(S._job_action(jb)),
					String(ag.get("home_space", "town"))]
		rec["job_holders"] = who
	get_root().remove_child(S)
	S.free()
	_S = null
	return rec

## 只读钩子：cands 是本次决策的完整候选表，best_i 是被选中的那一条。
func _on_decision(ag: Dictionary, cands: Array, best_i: int) -> void:
	var aid := String(ag["id"])
	for i in cands.size():
		var c = cands[i]
		if not (c is Dictionary):
			continue
		if String((c as Dictionary).get("kind", "")) != "object":
			continue
		var key := "%s@%s" % [String((c as Dictionary).get("action", "")),
			String((c as Dictionary).get("target", ""))]
		_offer_act[key] = int(_offer_act.get(key, 0)) + 1
		var akey := aid + "|" + key
		_offer_by_ag[akey] = int(_offer_by_ag.get(akey, 0)) + 1
		if i == best_i:
			_pick_act[key] = int(_pick_act.get(key, 0)) + 1
			_pick_by_ag[akey] = int(_pick_by_ag.get(akey, 0)) + 1

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
