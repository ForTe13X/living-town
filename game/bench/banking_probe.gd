extends SceneTree
## P5a impact receipt. Usage: godot --headless --path game --script res://bench/banking_probe.gd -- --seeds 1-12 --days 60

const SimScript = preload("res://scripts/Sim.gd")
const Inv = preload("res://bench/Invariants.gd")

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return String(args[i + 1]) if i >= 0 and i + 1 < args.size() else fallback

func _seeds(spec: String) -> Array:
	var bits := spec.split("-")
	if bits.size() == 1: return [int(bits[0])]
	var out := []
	for s in range(int(bits[0]), int(bits[1]) + 1): out.append(s)
	return out

func _initialize() -> void:
	var seeds := _seeds(_arg("--seeds", "1-12")); var days := int(_arg("--days", "60"))
	var totals := {"bank_deposit": 0, "bank_withdraw": 0, "bank_loan": 0, "bank_repay": 0}
	var hard_ok := 0
	for seed in seeds:
		var S = SimScript.new(); root.add_child(S); S._load_data(); S.backend = null; S.auto_run = false; S.start_new(seed)
		for _i in range(days * int(S.TICKS_PER_DAY)): S.tick()
		var counts := totals.duplicate(); for k in counts: counts[k] = 0
		for e in S.event_log:
			if String(e.get("type", "")) != "pay": continue
			var head := String(e.get("note", "")).split("*")[0]
			if counts.has(head): counts[head] = int(counts[head]) + 1; totals[head] = int(totals[head]) + 1
		var inv47 := false
		for result in Inv.check_all(S, 0):
			if int(result.get("id", -1)) == 47: inv47 = bool(result.get("ok", false)); break
		if inv47: hard_ok += 1
		print("[BANK] " + JSON.stringify({"seed": seed, "reserve": S.bank_coin, "deposits": S.bank_deposit_total(),
			"lendable": S.bank_available_capital(), "active_loans": S.bank_loans.values().filter(func(v): return int((v as Dictionary).get("outstanding", 0)) > 0).size(),
			"events": counts, "inv47": inv47}))
		root.remove_child(S); S.free()
	print("[BANK_SUMMARY] " + JSON.stringify({"seeds": seeds.size(), "days": days, "hard_ok": hard_ok, "events": totals}))
	quit(0 if hard_ok == seeds.size() else 1)
