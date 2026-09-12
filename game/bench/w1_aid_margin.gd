extends SceneTree
## bench/w1_aid_margin.gd — W1（docs/88）第二把尺子：**aid 输在哪一项上，以及全镇 standing 到底往哪边走。**
##
## `w1_aid_funnel.gd` 量的是漏斗**级差**；本文件量的是漏斗第⑤级（argmax 竞争）里的**分项**，
## 外加一条 `craft_credit` 唯一真正改动的量（`standing`）**在时间上的走向**——
## 因为 `_nightly` 那句 `standing -= sign(standing)` 是**整整 1.0 的跳**，
## 对任何 |s|<1 的值都会**越过 0 打到对面**（s → s−1 → s，周期 2），
## ⇒ "给 +0.25 的好评"在时间平均上**不等于** +0.25。这条要用数据判，不能用推理判。
##
## 采集点同样只有既有只读钩子 `Sim.decision_sink` + 每日界的纯读扫描。
## **不调 `_rel()`**（会 auto-create）：一律 `ag["relationships"].get(id, {})`。
##
## 用法：
##   godot --headless --path game -s res://bench/w1_aid_margin.gd -- \
##       --agents 12 --seeds 1-12 --days 60 --craft on|off [--standing X]

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

var _S = null
var _m: Dictionary = {}

func _init() -> void:
	var seeds := _parse_seeds("1-12")
	var days := 60
	var agents := 0
	var craft := "on"
	var st_over := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--agents" and i + 1 < args.size():
			agents = int(args[i + 1])
		elif args[i] == "--craft" and i + 1 < args.size():
			craft = String(args[i + 1])
		elif args[i] == "--standing" and i + 1 < args.size():
			st_over = String(args[i + 1])
	print("=== w1_aid_margin · agents=%d seeds=%s days=%d craft=%s standing=%s ===" % [agents, str(seeds), days, craft, st_over if st_over != "" else "(默认)"])
	for sd in seeds:
		print("[W1MARGIN] " + JSON.stringify(_run_once(sd, days, agents, craft, st_over)))
	quit(0)

func _fresh() -> Dictionary:
	return {
		# —— aid 候选存在的决策点上的分项（分母 n_pt）——
		"n_pt": 0,
		"aff_x100": 0, "fam_x100": 0, "lowneed_x100": 0,
		"aid_s_x100": 0, "inv_s_x100": 0, "win_s_x100": 0,
		"n_inv": 0,                 # 其中同时也有 invite 候选（同一个盟友）的决策点
		"win_is_aid": 0, "win_is_invite": 0, "win_other": 0,
		"margin_aid_minus_inv_x100": 0,   # aid - invite（只在 n_inv 上累）
		# —— 全镇社交接受率（口径：event_log 里 KNOWN_SOCIAL_ACTIONS 的 accepted/总数）——
		# （在 _run_once 末尾从 event_log 直接数，不在这里）
		# —— standing 的时间走向：每日界扫一次全部已建关系 ——
		"st_days": 0, "st_sum_x1000": 0, "st_pos": 0, "st_neg": 0, "st_pairs": 0,
		"st_frac_pos": 0,           # 0 < s < 1 的对（"被小额好评"的那种）
		"st_frac_neg": 0,           # -1 < s < 0
	}

func _on_pick(ag: Dictionary, cands: Array, best_i: int) -> void:
	var aid_s := -1.0e9
	var aid_pid := ""
	for c in cands:
		if String(c.get("action", "")) == "aid" and float(c.get("score", 0.0)) > aid_s:
			aid_s = float(c.get("score", 0.0)); aid_pid = String(c.get("partner", ""))
	if aid_pid == "":
		return
	_m["n_pt"] = int(_m["n_pt"]) + 1
	var rel: Dictionary = (ag["relationships"] as Dictionary).get(aid_pid, {})
	_m["aff_x100"] = int(_m["aff_x100"]) + int(round(float(rel.get("affinity", 0.0)) * 100.0))
	_m["fam_x100"] = int(_m["fam_x100"]) + int(round(float(rel.get("familiarity", 0.0)) * 100.0))
	var o: Dictionary = _S._agent_by_id.get(aid_pid, {})
	var mn := 100.0
	if not o.is_empty():
		for nid in o["needs"]:
			mn = minf(mn, float(o["needs"][nid]))
	_m["lowneed_x100"] = int(_m["lowneed_x100"]) + int(round(mn * 100.0))
	_m["aid_s_x100"] = int(_m["aid_s_x100"]) + int(round(aid_s * 100.0))
	# 同一个盟友身上的 invite 候选（aid 的头号对手，由 funnel 的 lost_to 指认）
	var inv_s := -1.0e9
	for c in cands:
		if String(c.get("action", "")) == "invite" and String(c.get("partner", "")) == aid_pid:
			inv_s = maxf(inv_s, float(c.get("score", 0.0)))
	if inv_s > -1.0e8:
		_m["n_inv"] = int(_m["n_inv"]) + 1
		_m["inv_s_x100"] = int(_m["inv_s_x100"]) + int(round(inv_s * 100.0))
		_m["margin_aid_minus_inv_x100"] = int(_m["margin_aid_minus_inv_x100"]) + int(round((aid_s - inv_s) * 100.0))
	var win: Dictionary = cands[best_i] if best_i >= 0 and best_i < cands.size() else {}
	_m["win_s_x100"] = int(_m["win_s_x100"]) + int(round(float(win.get("score", 0.0)) * 100.0))
	var wa := String(win.get("action", ""))
	if wa == "aid":
		_m["win_is_aid"] = int(_m["win_is_aid"]) + 1
	elif wa == "invite":
		_m["win_is_invite"] = int(_m["win_is_invite"]) + 1
	else:
		_m["win_other"] = int(_m["win_other"]) + 1

func _scan_standing(S) -> void:
	_m["st_days"] = int(_m["st_days"]) + 1
	for a in S.agents:
		for oid in a["relationships"]:
			var s := float((a["relationships"][oid] as Dictionary).get("standing", 0.0))
			_m["st_pairs"] = int(_m["st_pairs"]) + 1
			_m["st_sum_x1000"] = int(_m["st_sum_x1000"]) + int(round(s * 1000.0))
			if s > 0.0005:
				_m["st_pos"] = int(_m["st_pos"]) + 1
				if s < 1.0:
					_m["st_frac_pos"] = int(_m["st_frac_pos"]) + 1
			elif s < -0.0005:
				_m["st_neg"] = int(_m["st_neg"]) + 1
				if s > -1.0:
					_m["st_frac_neg"] = int(_m["st_frac_neg"]) + 1

func _run_once(seed: int, days: int, agents: int, craft: String, st_over: String) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	if craft == "off":
		S.production.erase("craft_credit")
		S._production_raw.erase("craft_credit")
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	if st_over != "" and craft != "off":
		var tbl = S.production.get("craft_credit", {})
		if tbl is Dictionary:
			for t in tbl:
				(tbl[t] as Dictionary)["standing"] = float(st_over)
	_S = S
	_m = _fresh()
	S.decision_sink = Callable(self, "_on_pick")
	var tpd := int(S.TICKS_PER_DAY)
	for t in range(days * tpd):
		S.tick()
		if (t + 1) % tpd == 0:
			_scan_standing(S)
	S.decision_sink = Callable()

	var soc_prop := 0; var soc_acc := 0
	var ev_aid := 0
	for ev in S.event_log:
		var ty := String(ev.get("type", ""))
		if ty in S.KNOWN_SOCIAL_ACTIONS:
			soc_prop += 1
			if bool(ev.get("accepted", false)):
				soc_acc += 1
		if ty == "aid":
			ev_aid += 1
	var rec: Dictionary = {
		"seed": seed, "craft": craft, "standing": st_over,
		"digest": str(Inv.digest(S)),
		"ev_aid": ev_aid, "soc_proposed": soc_prop, "soc_accepted": soc_acc,
		"m": _m.duplicate(true),
	}
	get_root().remove_child(S)
	S.free()
	_S = null
	return rec

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
