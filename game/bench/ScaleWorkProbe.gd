extends SceneTree

## LT-14 read-only worker-choice census for shortage diagnosis.

const SimScript = preload("res://bench/ScaleProbeSim.gd")
const Inv = preload("res://bench/Invariants.gd")

var sim: Node
var counters: Dictionary = {}
var latest_job_selection: Dictionary = {}
var latest_work_start: Dictionary = {}
var worker_ids: Array[String] = ["hai", "tie"]
var worker_good: Dictionary = {}

func _init() -> void:
	var seed := -1
	var core_agents := 40
	var days := 60
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--core-agents" and i + 1 < args.size(): core_agents = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
		elif args[i] == "--workers" and i + 1 < args.size():
			worker_ids.clear()
			for id in String(args[i + 1]).split(",", false):
				worker_ids.append(id.strip_edges())
	if seed <= 0 or core_agents < 12 or days <= 0 or worker_ids.is_empty():
		print("SCALE_WORK_FAIL invalid arguments")
		quit(2)
		return
	sim = SimScript.new()
	get_root().add_child(sim)
	sim._load_data()
	sim.auto_run = false
	sim.backend = null
	sim.spawn_count = core_agents
	sim.start_new(seed)
	for id in worker_ids:
		if counters.has(id):
			print("SCALE_WORK_FAIL duplicate worker: " + id)
			quit(2)
			return
		var job: Dictionary = sim._job_of(id)
		var produced: Dictionary = sim.production.get("produce", {})
		var entry: Dictionary = produced.get(String(job.get("title", "")), {})
		var good := String(entry.get("good", ""))
		if job.is_empty() or good.is_empty() or not sim.production.get("goods", {}).has(good):
			print("SCALE_WORK_FAIL worker has no produced good: " + id)
			quit(2)
			return
		worker_good[id] = good
		counters[id] = {"shift_ticks": 0, "shift_crisis_ticks": 0, "shift_job_option_ticks": 0,
			"shift_empty_option_ticks": 0, "decisions": 0, "job_offered": 0,
			"job_chosen": 0, "low_stock_offered": 0, "low_stock_chosen": 0,
			"completed_in_shift": 0, "completed_outside_shift": 0, "outside_shift_samples": [],
			"completed_signed_in_shift": 0, "completed_signed_in_shift_outside": 0,
			"started_in_shift": 0, "completed_started_in_shift_outside": 0,
			"no_job_samples": [], "lost_samples": []}
	sim.probe_sink = _record_decision
	sim.production_sink = _record_production_call
	sim.work_start_sink = _record_work_start
	for _t in range(days * sim.TICKS_PER_DAY):
		sim.tick()
		for id in worker_ids:
			var ag: Dictionary = sim.get_agent(id)
			var jb: Dictionary = sim._job_of(id)
			if not sim._in_shift(jb):
				continue
			var row: Dictionary = counters[id]
			row["shift_ticks"] = int(row["shift_ticks"]) + 1
			if sim._min_need(ag) < sim.SURVIVAL_GATE:
				row["shift_crisis_ticks"] = int(row["shift_crisis_ticks"]) + 1
			var opt = ag.get("option")
			if not (opt is Dictionary):
				row["shift_empty_option_ticks"] = int(row["shift_empty_option_ticks"]) + 1
			elif String(opt.get("action", "")) == sim._job_action(jb):
				row["shift_job_option_ticks"] = int(row["shift_job_option_ticks"]) + 1
	print("SCALE_WORK " + JSON.stringify({"seed": seed, "core_agents": core_agents,
		"actual_total": sim.agents.size(), "days": days,
		"digest": str(Inv.digest(sim)), "event_digest": str(sim.event_digest),
		"work_by_title": sim.prod_stats.get("work", {}), "worker_good": worker_good,
		"workers": counters}))
	get_root().remove_child(sim)
	sim.free()
	quit()

func _record_decision(ag: Dictionary, cands: Array, chosen: Dictionary) -> void:
	var id := String(ag.get("id", ""))
	if not counters.has(id):
		return
	var jb: Dictionary = sim._job_of(id)
	var chosen_job: bool = String(chosen.get("action", "")) == sim._job_action(jb)
	latest_job_selection[id] = {"tick": sim.tick_no, "in_shift": sim._in_shift(jb),
		"target": String(chosen.get("target", ""))} if chosen_job else {}
	if not sim._in_shift(jb):
		return
	var row: Dictionary = counters[id]
	row["decisions"] = int(row["decisions"]) + 1
	var job_action: String = sim._job_action(jb)
	var job_cand: Dictionary = {}
	for c in cands:
		if c is Dictionary and String(c.get("action", "")) == job_action:
			job_cand = c
			break
	var good: String = worker_good[id]
	var cap := int((sim.production["goods"][good] as Dictionary).get("cap", 1))
	var stock: int = sim._stock_of(good)
	var low_stock: bool = stock * 4 <= cap
	if job_cand.is_empty():
		if row["no_job_samples"].size() < 12:
			row["no_job_samples"].append({"tick": sim.tick_no, "stock": stock, "cap": cap,
				"min_need": sim._min_need(ag), "space": String(ag.get("space", "")),
				"chosen_need": String(chosen.get("need", "")), "chosen_action": String(chosen.get("action", ""))})
		return
	row["job_offered"] = int(row["job_offered"]) + 1
	if low_stock:
		row["low_stock_offered"] = int(row["low_stock_offered"]) + 1
	if sim._cand_key(chosen) == sim._cand_key(job_cand):
		row["job_chosen"] = int(row["job_chosen"]) + 1
		if low_stock:
			row["low_stock_chosen"] = int(row["low_stock_chosen"]) + 1
	elif row["lost_samples"].size() < 12 and low_stock:
		row["lost_samples"].append({"tick": sim.tick_no, "stock": stock, "cap": cap,
			"min_need": sim._min_need(ag), "job_score": float(job_cand.get("score", 0.0)),
			"chosen_score": float(chosen.get("score", 0.0)), "chosen_need": String(chosen.get("need", "")),
			"chosen_action": String(chosen.get("action", ""))})

func _record_production_call(ag: Dictionary, action: String, in_shift: bool) -> void:
	var id := String(ag.get("id", ""))
	if not counters.has(id) or action != sim._job_action(sim._job_of(id)):
		return
	var row: Dictionary = counters[id]
	var started: Dictionary = latest_work_start.get(id, {})
	if bool(started.get("in_shift", false)) and not in_shift:
		row["completed_started_in_shift_outside"] = int(row["completed_started_in_shift_outside"]) + 1
	latest_work_start[id] = {}
	var signed: Dictionary = latest_job_selection.get(id, {})
	if bool(signed.get("in_shift", false)):
		row["completed_signed_in_shift"] = int(row["completed_signed_in_shift"]) + 1
		if not in_shift:
			row["completed_signed_in_shift_outside"] = int(row["completed_signed_in_shift_outside"]) + 1
	latest_job_selection[id] = {}
	if in_shift:
		row["completed_in_shift"] = int(row["completed_in_shift"]) + 1
	else:
		row["completed_outside_shift"] = int(row["completed_outside_shift"]) + 1
		if row["outside_shift_samples"].size() < 12:
			row["outside_shift_samples"].append({"tick": sim.tick_no,
				"phase": sim._phase_of(sim.time_of_day()), "space": String(ag.get("space", "")),
				"option": String((ag.get("option", {}) as Dictionary).get("target", ""))})

func _record_work_start(ag: Dictionary, opt: Dictionary, in_shift: bool) -> void:
	var id := String(ag.get("id", ""))
	if not counters.has(id) or String(opt.get("action", "")) != sim._job_action(sim._job_of(id)):
		return
	latest_work_start[id] = {"tick": sim.tick_no, "in_shift": in_shift,
		"target": String(opt.get("target", ""))}
	if in_shift:
		var row: Dictionary = counters[id]
		row["started_in_shift"] = int(row["started_in_shift"]) + 1
