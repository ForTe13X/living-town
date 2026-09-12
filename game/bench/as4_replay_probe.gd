extends SceneTree
## bench/as4_replay_probe.gd — 车道 E2a BLOCKER-1（docs/154 §二.1）：external_coin per-run 重置的【回放一致】命门验证。
##
## goto_tick(Sim.gd:1146) 在一个【已经跑过一局、external_coin 局末非零】的 Sim 实例上再调 start_new 重演。
## 若 start_new 不把 external_coin 清零，第二遍的 econ_total0 = money_total() 会把上一局的 external 残值算进基准 ⇒
##   · econ_total0 不再逐局恒定（被污染）；
##   · goto_tick 后的 money_total 相对 fresh 跑位移；
##   · #34 因基准与总量同带残值可能反把 bug 盖绿。
## 本探针把它钉死：一个【脏】Sim（跑满一局）goto_tick(T) 的账户状态，必须与一个【新】Sim start_new+tick 到 T 逐字段相同。
##
## 用法：
##   godot --headless --path game -s res://bench/as4_replay_probe.gd -- --seeds 1-6 --days 60 --target 7200
##   --target = goto_tick 的目标 tick（缺省 = days×TICKS_PER_DAY / 2，即半局）。
## 逐 seed 一行 [AS4RPL]{json}；末尾 [AS4RPLSUM] 全绿/红。任一 seed 对不上 quit(1)。

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _init() -> void:
	var seeds := _parse_seeds("1-6")
	var days := 60
	var target := -1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = _parse_seeds(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
		elif args[i] == "--target" and i + 1 < args.size():
			target = int(args[i + 1])
	var all_ok := true
	print("=== as4_replay_probe · seeds=%s days=%d target=%s ===" % [str(seeds), days, str(target)])
	for sd in seeds:
		var rec := _one(sd, days, target)
		print("[AS4RPL] " + JSON.stringify(rec))
		if not bool(rec["match"]):
			all_ok = false
	print("[AS4RPLSUM] " + JSON.stringify({"all_match": all_ok, "seeds": str(seeds)}))
	quit(0 if all_ok else 1)

func _one(seed: int, days: int, target: int) -> Dictionary:
	var tpd := int(SimScript.TICKS_PER_DAY)
	var T := target if target >= 0 else (days * tpd) / 2
	# ── 【脏】路径：跑满一局把 external_coin 弄成非零，再 goto_tick(T) 重演 ──
	var A = SimScript.new()
	get_root().add_child(A)
	A._load_data(); A.auto_run = false; A.backend = null
	A.start_new(seed)
	for _t in range(days * tpd):
		A.tick()
	var dirty_external := int(A.external_coin)          # 局末 external（应 > 0，证明"脏"确实成立）
	var dirty_econ0 := int(A.econ_total0)               # 这一局的基准（fresh，应 == 开局理论值）
	A.goto_tick(T)                                       # 内部再 start_new(seed)+重演到 T —— 命门在这
	var a := _snap(A)
	get_root().remove_child(A); A.free()
	# ── 【新】路径：全新 Sim start_new+tick 到 T（fresh 参照） ──
	var B = SimScript.new()
	get_root().add_child(B)
	B._load_data(); B.auto_run = false; B.backend = null
	B.start_new(seed)
	for _t in range(T):
		B.tick()
	var b := _snap(B)
	get_root().remove_child(B); B.free()
	var match_all: bool = (a["econ_total0"] == b["econ_total0"] and a["external_coin"] == b["external_coin"]
		and a["town_coin"] == b["town_coin"] and a["money_total"] == b["money_total"]
		and a["digest"] == b["digest"] and a["event_digest"] == b["event_digest"])
	return {
		"seed": seed, "target_tick": T,
		"dirty_run_external_coin": dirty_external,        # 脏证据：跑满一局 external 非零
		"dirty_run_econ_total0": dirty_econ0,
		"goto_tick_after": a, "fresh_ref": b,
		"econ_total0_stable": (a["econ_total0"] == dirty_econ0 and a["econ_total0"] == b["econ_total0"]),
		"match": match_all,
	}

func _snap(S) -> Dictionary:
	return {
		"econ_total0": int(S.econ_total0), "external_coin": int(S.external_coin),
		"town_coin": int(S.town_coin), "money_total": int(S.money_total()),
		"digest": str(Inv.digest(S)), "event_digest": str(S.event_digest),
	}

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
