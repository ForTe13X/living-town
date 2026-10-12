extends SceneTree
## Read-only startup roster inventory for the declared LT-14 core-population grid.
## Usage: godot --headless --path game --script res://bench/ScaleRoster.gd -- --core-agents 12,16,24,40 --seed 1

const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var sizes := [12, 16, 24, 40]
	var seed := 1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--core-agents" and i + 1 < args.size():
			sizes.clear()
			for part in String(args[i + 1]).split(","):
				if not String(part).strip_edges().is_valid_int() or int(part) <= 0:
					print("SCALE_ROSTER_FAIL invalid core size: " + String(part))
					quit(2)
					return
				sizes.append(int(part))
		elif args[i] == "--seed" and i + 1 < args.size():
			seed = int(args[i + 1])
	if sizes.is_empty():
		print("SCALE_ROSTER_FAIL no core sizes")
		quit(2)
		return
	for requested_core in sizes:
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data()
		S.auto_run = false
		S.backend = null
		S.spawn_count = requested_core
		var authored: Dictionary = S._read_json("res://data/agents.json")
		var authored_core := {}
		var authored_affiliates := {}
		for definition in authored.get("agents", []):
			authored_core[String(definition.get("id", ""))] = true
		for definition in authored.get("affiliates", []):
			authored_affiliates[String(definition.get("id", ""))] = true
		S.start_new(seed)
		var named_residents: Array = []
		var affiliates: Array = []
		var clones: Array = []
		var job_holders: Array = []
		var pure_consumers: Array = []
		var seen := {}
		var job_table: Dictionary = S.jobs.get("jobs", {})
		for ag in S.agents:
			var aid := String(ag.get("id", ""))
			if aid.is_empty() or seen.has(aid):
				print("SCALE_ROSTER_FAIL duplicate or empty runtime id at core=%d" % requested_core)
				quit(1)
				return
			seen[aid] = true
			if authored_core.has(aid): named_residents.append(aid)
			elif authored_affiliates.has(aid): affiliates.append(aid)
			else: clones.append(aid)
			if job_table.has(aid): job_holders.append(aid)
			else: pure_consumers.append(aid)
		var reconciled: bool = int(S.core_population) == requested_core \
			and named_residents.size() + clones.size() == requested_core \
			and named_residents.size() + affiliates.size() + clones.size() == S.agents.size() \
			and job_holders.size() + pure_consumers.size() == S.agents.size()
		var row := {"seed": seed, "requested_core": requested_core,
			"actual_core": int(S.core_population), "actual_total": S.agents.size(),
			"named_residents": named_residents, "affiliates": affiliates, "clones": clones,
			"job_holders": job_holders, "pure_consumers": pure_consumers,
			"reconciled": reconciled}
		print("SCALE_ROSTER " + JSON.stringify(row))
		get_root().remove_child(S)
		S.free()
		if not reconciled:
			print("SCALE_ROSTER_FAIL population mismatch at core=%d" % requested_core)
			quit(1)
			return
	quit(0)
