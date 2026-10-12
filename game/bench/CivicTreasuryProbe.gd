extends SceneTree
## LT-15 design evidence: read-only treasury and reserve samples around the first mayor term.
## Usage: godot --headless --path game --script res://bench/CivicTreasuryProbe.gd -- --seeds 1-12 --core-agents 12 --days 35

const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var first_seed := 1
	var last_seed := 12
	var core_agents := 12
	var days := 35
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			var pieces := String(args[i + 1]).split("-")
			if pieces.size() != 2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int():
				print("CIVIC_TREASURY_FAIL invalid seed range")
				quit(2)
				return
			first_seed = int(pieces[0])
			last_seed = int(pieces[1])
		elif args[i] == "--core-agents" and i + 1 < args.size():
			core_agents = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i + 1])
	if first_seed <= 0 or last_seed < first_seed or core_agents < 12 or days < 30:
		print("CIVIC_TREASURY_FAIL invalid bounds")
		quit(2)
		return
	for seed in range(first_seed, last_seed + 1):
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		S.spawn_count = core_agents
		S.start_new(seed)
		var seen := {}
		for _step in range(days * int(S.TICKS_PER_DAY)):
			S.tick()
			if int(S.day) in [28, 29, 30, 35] and int(S.tick_no) % int(S.TICKS_PER_DAY) == 0 and not seen.has(int(S.day)):
				seen[int(S.day)] = true
				var policy: Dictionary = S.fiscal_policy()
				var floor_coin := int(policy.get("subsidy_floor", 0))
				print("CIVIC_TREASURY " + JSON.stringify({"seed": seed, "core_agents": core_agents,
					"actual_total": S.agents.size(), "day": int(S.day), "tick": int(S.tick_no),
					"town_coin": int(S.town_coin), "reserve_floor": floor_coin,
					"spendable_above_floor": maxi(0, int(S.town_coin) - floor_coin),
					"mayor": String(S.mayor_state.get("mayor", "")),
					"term_start": int(S.mayor_state.get("term_start", -1)),
					"term_end": int(S.mayor_state.get("term_end", -1))}))
		get_root().remove_child(S)
		S.free()
	quit()
