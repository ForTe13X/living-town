extends SceneTree
## bench/w1_aid_funnel.gd — W1（docs/88）：**那 42% 的 `aid` 是在哪一级漏掉的？**
##
## V1（docs/84 §四.5）测到 `craft_credit.standing` 打开之后盟约互助 `aid` 从 118 掉到 68（12 seed 里 11 个同向），
## 但**没有找到机制**。本探针把 `aid` 拆成一条**漏斗**，逐级量，让"少发生"落到**某一级**上：
##
##   ① 盟约存在        pact_active_ticksum  = Σ_tick(当时 active 的盟约条数)      ← 供给
##   ② 决策点上有盟友   dp_haspact           = 该 agent 此刻至少有一个 active 盟约
##   ③ 盟友在同区       dp_pactnear          = 至少一个 active 盟友出现在 `_nearby_agents` 里   ← 共位
##   ④ 盟友某 need 低   dp_aidcand           = `_partner_low_need(o) != ""` ⇒ 候选真的被枚举出来  ← 机会
##   ⑤ aid 赢了 argmax  dp_aidpick           = `_logic_decide` 选中了它                         ← 竞争
##
## `aid` 事件数 == ⑤（实测 V1 数据里 `by_type.aid.n` 与 `aid_accepted` 逐 seed 相同 ⇒ **从不被拒**，
## 所以 42% 只可能丢在 ①-⑤ 里，接受判定这条路可以先排除——本探针把它量成数字而不是推断）。
##
## ★零扰动怎么保证的：采集**全部**挂在既有只读钩子 `Sim.decision_sink`
## （`Sim.gd:3783`，注释原文"只读、不抽 RNG、不进 digest"；`EpistemicPromptProbe` / `t1_workfloor_probe` 已用过这条路）。
## 钩子里只调 `_nearby_agents` / `_partner_low_need` / 读 `ag["pacts"]`——三者都是纯读，
## **不碰 `_rel()`**（那个会 auto-create 关系条目 ⇒ 会改状态）。两臂各自的 `digest` 一并输出自证。
##
## 两臂：`--craft on`（出货）/ `--craft off`（删 `production.craft_credit` 键）。
## `off` 臂的判据不是"我觉得它等于改前"，是 **digest 必须等于 V1 记在 `analysis/v1/` 里的那五个数**。
##
## 用法：
##   godot --headless --path game -s res://bench/w1_aid_funnel.gd -- \
##       --agents 12 --seeds 1-12 --days 60 --craft on|off [--out x.jsonl]

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
	var title_over := ""
	var util_over := ""
	var out_path := ""
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
			st_over = String(args[i + 1])   # 剂量-响应臂：覆写 craft_credit.<职位>.standing（键仍在 ⇒ 目击者/信念/记忆照写）
		elif args[i] == "--title" and i + 1 < args.size():
			title_over = String(args[i + 1])   # 换人臂：把同一条 craft_credit 记录挪给另一个职位（同代码路径、同量级、换个人）
		elif args[i] == "--util" and i + 1 < args.size():
			util_over = String(args[i + 1])    # sham 臂：`键=值` 覆写 utility.json 的一个权重（与 standing 无关的等量扰动）
		elif args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	var f: FileAccess = null
	if out_path != "":
		f = FileAccess.open(out_path, FileAccess.WRITE)
	print("=== w1_aid_funnel · agents=%d seeds=%s days=%d craft=%s standing=%s title=%s util=%s ===" % [agents, str(seeds), days, craft, st_over if st_over != "" else "(默认)", title_over if title_over != "" else "(默认)", util_over if util_over != "" else "(默认)"])
	for sd in seeds:
		var rec := _run_once(sd, days, agents, craft, st_over, title_over, util_over)
		var line := JSON.stringify(rec)
		print("[W1FUNNEL] " + line)
		if f: f.store_line(line)
	if f: f.close()
	quit(0)

func _fresh_metrics() -> Dictionary:
	return {
		"dp": 0,                    # decision_sink 被调用次数（=cands>=2 的决策点）
		"dp_soc_shut_surv": 0,      # `_social_candidates` 开头第一道：_min_need < SURVIVAL_GATE ⇒ 整段返 []
		"dp_soc_shut_full": 0,      # 第二道：social >= SOCIAL_FULL ⇒ 整段返 []（社交需求已饱和）
		"dp_soc_open": 0,           # 两道都过 ⇒ 社交候选段真的在跑
		"soc_need_x100": 0,         # Σ ag.needs.social ×100（分母 dp）——测"全镇社交饱和度"整体挪没挪
		"dp_haspact": 0,            # 该 agent 此刻至少有一个 active 盟约
		"dp_pactnear": 0,           # 至少一个 active 盟友在同区
		"dp_pactnear_open": 0,      # 同上，且社交段没被两道门关掉
		"dp_aidcand": 0,            # cands 里真的有 aid 候选
		"dp_aidpick": 0,            # argmax 选中了 aid
		"pair_pactnear": 0,         # 计对：同区 active 盟友的人次
		"pair_talking": 0,          # 其中：`o["talking"]>0` ⇒ `_social_candidates` 直接 continue 掉他
		"pair_lowneed": 0,          # 其中：need 低（`_partner_low_need != ""`）的人次
		"cand_aid": 0,              # 枚举出来的 aid 候选总条数
		"aid_score_x100": 0,        # aid 候选分数和 ×100（只在 aid 候选存在的决策点累）
		"win_score_x100": 0,        # 同一批决策点上 argmax 胜者的分数和 ×100
		"lost_to": {},              # aid 候选存在却没被选中时，赢家的 action -> 次数
		"pn_minneed_x100": 0,       # 同区盟友的 min(need) 之和 ×100（分母 pair_pactnear）
		"cands_n": 0,               # 决策点候选条数总和（分母 dp）
		"pact_ticksum": 0,          # Σ_tick(active 盟约条数)
		"pact_formed": 0,
		"pact_dissolved": 0,
		"aid_by_pair": {},          # "a|b" -> 次数（谁在互助）
	}

## Sim.decision_sink 回调：**纯读**。不调 `_rel()`（会 auto-create）、不抽 RNG、不写任何仿真状态。
func _on_pick(ag: Dictionary, cands: Array, best_i: int) -> void:
	_m["dp"] = int(_m["dp"]) + 1
	_m["cands_n"] = int(_m["cands_n"]) + cands.size()
	var soc := float(ag["needs"].get("social", 100.0))
	_m["soc_need_x100"] = int(_m["soc_need_x100"]) + int(round(soc * 100.0))
	# `_social_candidates` 开头那两道门（Sim.gd 里逐字对照，不是近似）
	var soc_open := true
	if _S._min_need(ag) < _S.SURVIVAL_GATE:
		_m["dp_soc_shut_surv"] = int(_m["dp_soc_shut_surv"]) + 1
		soc_open = false
	elif soc >= _S.SOCIAL_FULL:
		_m["dp_soc_shut_full"] = int(_m["dp_soc_shut_full"]) + 1
		soc_open = false
	else:
		_m["dp_soc_open"] = int(_m["dp_soc_open"]) + 1
	var pacts: Dictionary = ag["pacts"]
	var has_pact := false
	for k in pacts:
		if String((pacts[k] as Dictionary)["status"]) == "active":
			has_pact = true
			break
	if has_pact:
		_m["dp_haspact"] = int(_m["dp_haspact"]) + 1
	var near_pact := 0
	var low_pact := 0
	var talk_pact := 0
	if has_pact:
		for o in _S._nearby_agents(ag):
			if not _S._active_pact(ag, String(o["id"])):
				continue
			near_pact += 1
			if int(o["talking"]) > 0:
				talk_pact += 1
			var mn := 100.0
			for nid in o["needs"]:
				mn = minf(mn, float(o["needs"][nid]))
			_m["pn_minneed_x100"] = int(_m["pn_minneed_x100"]) + int(round(mn * 100.0))
			if String(_S._partner_low_need(o)) != "":
				low_pact += 1
	_m["pair_pactnear"] = int(_m["pair_pactnear"]) + near_pact
	_m["pair_lowneed"] = int(_m["pair_lowneed"]) + low_pact
	_m["pair_talking"] = int(_m["pair_talking"]) + talk_pact
	if near_pact > 0:
		_m["dp_pactnear"] = int(_m["dp_pactnear"]) + 1
		if soc_open:
			_m["dp_pactnear_open"] = int(_m["dp_pactnear_open"]) + 1
	# 候选侧（以 Sim 真正枚举出来的东西为准，不用上面的谓词代替它——两者对不上本身就是发现）
	var n_aid := 0
	var best_aid := -1000000.0
	for c in cands:
		if String(c.get("action", "")) == "aid":
			n_aid += 1
			best_aid = maxf(best_aid, float(c.get("score", 0.0)))
	_m["cand_aid"] = int(_m["cand_aid"]) + n_aid
	if n_aid > 0:
		_m["dp_aidcand"] = int(_m["dp_aidcand"]) + 1
		_m["aid_score_x100"] = int(_m["aid_score_x100"]) + int(round(best_aid * 100.0))
		var win: Dictionary = cands[best_i] if best_i >= 0 and best_i < cands.size() else {}
		_m["win_score_x100"] = int(_m["win_score_x100"]) + int(round(float(win.get("score", 0.0)) * 100.0))
		var wa := String(win.get("action", ""))
		if wa == "aid":
			_m["dp_aidpick"] = int(_m["dp_aidpick"]) + 1
			var pk := String(ag["id"]) + "|" + String(win.get("partner", ""))
			(_m["aid_by_pair"] as Dictionary)[pk] = int((_m["aid_by_pair"] as Dictionary).get(pk, 0)) + 1
		else:
			var lt: Dictionary = _m["lost_to"]
			lt[wa] = int(lt.get(wa, 0)) + 1

func _run_once(seed: int, days: int, agents: int, craft: String, st_over: String, title_over: String, util_over: String) -> Dictionary:
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	if craft == "off":
		# 与 V1 §四.1 的"删掉那个 JSON 键"逐字节等价：start_new 会从 _production_raw 重算 production，
		# 所以两处都要摘（GDScript 里二者是同一个 Dictionary 引用，摘一次即可；写两行是防将来解耦）。
		S.production.erase("craft_credit")
		S._production_raw.erase("craft_credit")
	if util_over != "":
		var kv := util_over.split("=")
		S.utility[String(kv[0])] = float(kv[1])
	S.auto_run = false
	S.backend = null
	if agents > 0:
		S.spawn_count = agents
	S.start_new(seed)
	if title_over != "" and craft != "off":
		var t0 = S.production.get("craft_credit", {})
		if t0 is Dictionary and not (t0 as Dictionary).is_empty():
			var k0 := String((t0 as Dictionary).keys()[0])
			var rec0 = (t0 as Dictionary)[k0]
			(t0 as Dictionary).clear()
			(t0 as Dictionary)[title_over] = rec0
	if st_over != "" and craft != "off":
		# start_new 里 production 由 _pool_rescale 从 _production_raw 重算 ⇒ 必须在它【之后】覆写。
		var tbl = S.production.get("craft_credit", {})
		if tbl is Dictionary:
			for t in tbl:
				(tbl[t] as Dictionary)["standing"] = float(st_over)
	_S = S
	_m = _fresh_metrics()
	S.decision_sink = Callable(self, "_on_pick")

	var tpd := int(S.TICKS_PER_DAY)
	for _t in range(days * tpd):
		S.tick()
		var act := 0
		for p in S.pacts_index:
			if String(p["status"]) == "active":
				act += 1
		_m["pact_ticksum"] = int(_m["pact_ticksum"]) + act

	S.decision_sink = Callable()
	# 事件侧的地面真值（漏斗第⑤级的独立复核 + aid 从不被拒的复核）
	var ev_aid := 0; var ev_aid_acc := 0
	var ev_pact_form := 0; var ev_pact_diss := 0
	for ev in S.event_log:
		var ty := String(ev.get("type", ""))
		if ty == "aid":
			ev_aid += 1
			if bool(ev.get("accepted", false)):
				ev_aid_acc += 1
		elif ty == "pact":
			if String(ev.get("note", "")) == "formed":
				ev_pact_form += 1
			else:
				ev_pact_diss += 1
	_m["pact_formed"] = ev_pact_form
	_m["pact_dissolved"] = ev_pact_diss

	var rec: Dictionary = {
		"seed": seed, "craft": craft, "standing": st_over, "title": title_over, "util": util_over,
		"n_agents": S.agents.size(), "days": days,
		"digest": str(Inv.digest(S)),
		"ev_aid": ev_aid, "ev_aid_accepted": ev_aid_acc, "aid_accepted_ctr": int(S.aid_accepted),
		"pacts_alive_end": _alive_pacts(S),
		"funnel": _m.duplicate(true),
	}
	get_root().remove_child(S)
	S.free()
	_S = null
	return rec

func _alive_pacts(S) -> int:
	var n := 0
	for p in S.pacts_index:
		if String(p["status"]) == "active":
			n += 1
	return n

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
