extends SceneTree

## LT-14 read-only census of mayor duty candidates before/after work discipline.

const SimScript = preload("res://bench/ScaleProbeSim.gd")
const Inv = preload("res://bench/Invariants.gd")

var sim: Node
var offered := 0
var filtered := 0
var retained := 0
var selected := 0
var use_started := 0
var choice_opportunities := 0
var choice_lost := 0
var competing_actions: Dictionary = {}
var largest_score_gap := 0.0
var lost_choice_samples: Array = []
var by_actor: Dictionary = {}
var samples: Array = []

func _init() -> void:
	var seed_spec := ""
	var core_agents := 40
	var days := 60
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] in ["--seed", "--seeds"] and i + 1 < args.size(): seed_spec = String(args[i + 1])
		elif args[i] == "--core-agents" and i + 1 < args.size(): core_agents = int(args[i + 1])
		elif args[i] == "--days" and i + 1 < args.size(): days = int(args[i + 1])
	var seeds := _parse_seeds(seed_spec)
	if seeds.is_empty() or core_agents < 12 or days <= 0:
		print("SCALE_CIVIC_FILTER_FAIL invalid arguments")
		quit(2)
		return
	for seed in seeds:
		_run_once(seed, core_agents, days)
	quit()

func _parse_seeds(spec: String) -> Array[int]:
	var out: Array[int] = []
	if spec.contains("-"):
		var parts := spec.split("-", false, 2)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return out
		var first := int(parts[0]); var last := int(parts[1])
		if first <= 0 or last < first:
			return out
		for seed in range(first, last + 1): out.append(seed)
	else:
		for part in spec.split(",", false):
			if not part.is_valid_int() or int(part) <= 0:
				return []
			out.append(int(part))
	return out

func _run_once(seed: int, core_agents: int, days: int) -> void:
	offered = 0; filtered = 0; retained = 0; selected = 0; use_started = 0
	choice_opportunities = 0; choice_lost = 0; largest_score_gap = 0.0
	competing_actions.clear(); lost_choice_samples.clear(); by_actor.clear(); samples.clear()
	sim = SimScript.new()
	get_root().add_child(sim)
	sim._load_data()
	sim.auto_run = false
	sim.backend = null
	sim.spawn_count = core_agents
	sim.start_new(seed)
	sim.discipline_sink = _record_filter
	sim.probe_sink = _record_choice
	sim.work_start_sink = _record_use_start
	for _t in range(days * sim.TICKS_PER_DAY):
		sim.tick()
	var civic_events := 0
	for e in sim.event_log:
		if String(e.get("type", "")) == "civic_duty": civic_events += 1
	var terms: Array = []
	for term in sim.mayor_log:
		if term is Dictionary:
			terms.append({"winner": String(term.get("winner", "")),
				"term_start": int(term.get("term_start", -1)),
				"duties_done": int(term.get("duties_done", 0))})
	print("SCALE_CIVIC_FILTER " + JSON.stringify({"seed": seed, "core_agents": core_agents,
		"actual_total": sim.agents.size(), "days": days, "digest": str(Inv.digest(sim)),
		"duty_candidates_offered": offered, "duty_candidates_filtered": filtered,
		"duty_candidates_retained": retained, "duty_selected": selected,
		"duty_use_started": use_started, "civic_events": civic_events,
		"duty_choice_opportunities": choice_opportunities, "duty_choice_lost": choice_lost,
		"competing_actions": competing_actions, "largest_score_gap": largest_score_gap,
		"lost_choice_samples": lost_choice_samples,
		"by_actor": by_actor, "samples": samples, "terms": terms}))
	get_root().remove_child(sim)
	sim.free()

func _record_filter(ag: Dictionary, cands: Array, kept: Array) -> void:
	var duty_before := false
	var duty_after := false
	for c in cands:
		if c is Dictionary and String(c.get("action", "")) == "办公":
			duty_before = true
			break
	if not duty_before:
		return
	for c in kept:
		if c is Dictionary and String(c.get("action", "")) == "办公":
			duty_after = true
			break
	var id := String(ag.get("id", ""))
	var job: Dictionary = sim._job_of(id)
	var row: Dictionary = by_actor.get(id, {"title": String(job.get("title", "")),
		"on_site": bool(job.get("on_site", false)), "offered": 0, "filtered": 0,
		"retained": 0, "selected": 0, "use_started": 0})
	offered += 1
	row["offered"] = int(row["offered"]) + 1
	if duty_after:
		retained += 1
		row["retained"] = int(row["retained"]) + 1
	else:
		filtered += 1
		row["filtered"] = int(row["filtered"]) + 1
		if samples.size() < 12:
			samples.append({"tick": sim.tick_no, "actor": id,
				"title": String(job.get("title", "")), "in_shift": sim._in_shift(job),
				"min_need": sim._min_need(ag)})
	by_actor[id] = row

func _record_choice(ag: Dictionary, _cands: Array, chosen: Dictionary) -> void:
	var duty: Dictionary = {}
	for c in _cands:
		if c is Dictionary and String(c.get("action", "")) == "办公":
			duty = c
			break
	if duty.is_empty():
		return
	choice_opportunities += 1
	var id := String(ag.get("id", ""))
	var row: Dictionary = by_actor.get(id, {})
	if String(chosen.get("action", "")) == "办公":
		selected += 1
		row["selected"] = int(row.get("selected", 0)) + 1
	else:
		choice_lost += 1
		var action := String(chosen.get("action", ""))
		competing_actions[action] = int(competing_actions.get(action, 0)) + 1
		var gap := float(chosen.get("score", 0.0)) - float(duty.get("score", 0.0))
		largest_score_gap = maxf(largest_score_gap, gap)
		if lost_choice_samples.size() < 16:
			lost_choice_samples.append({"tick": sim.tick_no, "actor": id,
				"duty_score": float(duty.get("score", 0.0)),
				"chosen_action": action, "chosen_need": String(chosen.get("need", "")),
				"chosen_score": float(chosen.get("score", 0.0)), "gap": gap,
				"min_need": sim._min_need(ag)})
	by_actor[id] = row

func _record_use_start(ag: Dictionary, opt: Dictionary, _in_shift: bool) -> void:
	if String(opt.get("action", "")) != "办公":
		return
	use_started += 1
	var id := String(ag.get("id", ""))
	var row: Dictionary = by_actor.get(id, {})
	row["use_started"] = int(row.get("use_started", 0)) + 1
	by_actor[id] = row
