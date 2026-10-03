extends SceneTree

## LT-14 read-only decisions around a measured need-bottoming episode.

const SimScript = preload("res://bench/ScaleProbeSim.gd")

var sim: Node
var actor_id := "coco"
var first_tick := 0
var last_tick := 0
var choices: Array = []
var filters: Array = []

func _init() -> void:
	var seed := -1
	var core_agents := 40
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--core-agents" and i + 1 < args.size(): core_agents = int(args[i + 1])
		elif args[i] == "--first-tick" and i + 1 < args.size(): first_tick = int(args[i + 1])
		elif args[i] == "--last-tick" and i + 1 < args.size(): last_tick = int(args[i + 1])
		elif args[i] == "--actor" and i + 1 < args.size(): actor_id = String(args[i + 1])
	if seed <= 0 or core_agents < 12 or first_tick < 0 or last_tick <= first_tick or actor_id.is_empty():
		print("SCALE_CHOICE_FAIL invalid arguments")
		quit(2)
		return
	sim = SimScript.new()
	get_root().add_child(sim)
	sim._load_data()
	sim.auto_run = false
	sim.backend = null
	sim.spawn_count = core_agents
	sim.start_new(seed)
	sim.probe_sink = _record_choice
	sim.hunger_sink = _record_hunger_filter
	for t in range(last_tick + 1):
		sim.tick()
	print("SCALE_CHOICE " + JSON.stringify({"seed": seed, "core_agents": core_agents,
		"actual_total": sim.agents.size(), "actor": actor_id,
		"first_tick": first_tick, "last_tick": last_tick, "choices": choices,
		"hunger_filters": filters}))
	get_root().remove_child(sim)
	sim.free()
	quit()

func _record_choice(ag: Dictionary, cands: Array, chosen: Dictionary) -> void:
	if String(ag.get("id", "")) != actor_id or sim.tick_no < first_tick or sim.tick_no > last_tick:
		return
	var ranked: Array = []
	var chosen_key: String = sim._cand_key(chosen)
	for i in cands.size():
		var c: Dictionary = cands[i]
		var selected: bool = sim._cand_key(c) == chosen_key
		ranked.append({"index": i, "kind": String(c.get("kind", "")),
			"need": String(c.get("need", "")), "action": String(c.get("action", "")),
			"target": String(c.get("target", "")), "score": float(c.get("score", 0.0)),
			"amount": float(c.get("amount", 0.0)), "dist": float(c.get("dist", 0.0)),
			"selected": selected})
	ranked.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var top: Array = ranked.slice(0, mini(12, ranked.size()))
	if not top.any(func(c): return bool(c["selected"])):
		top.append(ranked.filter(func(c): return bool(c["selected"]))[0])
	choices.append({"tick": sim.tick_no, "needs": (ag.get("needs", {}) as Dictionary).duplicate(true),
		"space": String(ag.get("space", "")), "count": cands.size(), "top": top})

func _record_hunger_filter(ag: Dictionary, before: Array, after: Array) -> void:
	if String(ag.get("id", "")) != actor_id or sim.tick_no < first_tick or sim.tick_no > last_tick:
		return
	var need_hunger := float((ag.get("needs", {}) as Dictionary).get("hunger", 100.0))
	if need_hunger >= 30.0:
		return
	var before_items: Array = []
	for c in before:
		if c is Dictionary:
			before_items.append({"kind": String(c.get("kind", "")), "need": String(c.get("need", "")),
				"action": String(c.get("action", "")), "target": String(c.get("target", "")),
				"score": float(c.get("score", 0.0))})
	var after_keys: Array = []
	for c in after:
		if c is Dictionary:
			after_keys.append(sim._cand_key(c))
	filters.append({"tick": sim.tick_no, "space": String(ag.get("space", "")),
		"hunger": need_hunger, "snacks": int(ag.get("snacks", 0)),
		"pantry": ag.get("pantry", null),
		"money": int(ag.get("money", 0)), "before": before_items,
		"after_keys": after_keys})
