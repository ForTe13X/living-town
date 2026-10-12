extends SceneTree
## LT-14 read-only window around a measured hard #1 need-bottoming episode.
## Usage: godot --headless --path game --script res://bench/ScaleNeedProbe.gd -- --seed 3 --core-agents 40 --center-tick 6081 --window 200

const SimScript = preload("res://scripts/Sim.gd")

func _init() -> void:
	var seed := -1
	var core_agents := 40
	var center_tick := -1
	var half_window := 200
	var actor_id := "coco"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size(): seed = int(args[i + 1])
		elif args[i] == "--core-agents" and i + 1 < args.size(): core_agents = int(args[i + 1])
		elif args[i] == "--center-tick" and i + 1 < args.size(): center_tick = int(args[i + 1])
		elif args[i] == "--window" and i + 1 < args.size(): half_window = int(args[i + 1])
		elif args[i] == "--actor" and i + 1 < args.size(): actor_id = String(args[i + 1])
	if seed <= 0 or core_agents < 12 or center_tick < 0 or half_window < 20 or actor_id.is_empty():
		print("SCALE_NEED_FAIL invalid arguments")
		quit(2)
		return
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data()
	S.auto_run = false
	S.backend = null
	S.spawn_count = core_agents
	S.start_new(seed)
	var first := maxi(0, center_tick - half_window)
	var last := center_tick + half_window
	var trace: Array = []
	var bottom_by_need := {}
	var min_by_need := {}
	var event_types := {}
	for t in range(last + 1):
		var event_start: int = S.event_log.size()
		S.tick()
		if t < first:
			continue
		var ag: Dictionary = S.get_agent(actor_id)
		if ag.is_empty():
			print("SCALE_NEED_FAIL actor missing")
			quit(1)
			return
		var needs: Dictionary = ag.get("needs", {})
		var bottom: Array = []
		for nid in needs:
			var v := float(needs[nid])
			min_by_need[nid] = minf(float(min_by_need.get(nid, 101.0)), v)
			if v <= 0.5:
				bottom.append(String(nid))
				bottom_by_need[nid] = int(bottom_by_need.get(nid, 0)) + 1
		var opt = ag.get("option")
		var option_text := str(opt) if opt is Dictionary else ""
		var pos: Vector2i = ag.get("pos", Vector2i.ZERO)
		var events: Array = []
		for event_i in range(event_start, S.event_log.size()):
			var ev: Dictionary = S.event_log[event_i]
			if String(ev.get("actor", "")) == actor_id or String(ev.get("target", "")) == actor_id:
				var kind := String(ev.get("type", ""))
				event_types[kind] = int(event_types.get(kind, 0)) + 1
				events.append({"id": int(ev.get("id", -1)), "type": kind,
					"actor": String(ev.get("actor", "")), "target": String(ev.get("target", "")),
					"subject": String(ev.get("subject", "")), "note": String(ev.get("note", ""))})
		trace.append({"t": t, "day": int(S.day), "needs": needs.duplicate(true), "bottom": bottom,
			"space": String(ag.get("space", "town")), "floor": String(ag.get("floor", "outdoor")),
			"pos": [pos.x, pos.y], "option": option_text, "events": events})
	print("SCALE_NEED " + JSON.stringify({"seed": seed, "core_agents": core_agents,
		"actual_total": S.agents.size(), "actor": actor_id, "center_tick": center_tick,
		"first_tick": first, "last_tick": last, "bottom_by_need": bottom_by_need,
		"minimum_in_window": min_by_need, "event_types": event_types, "trace": trace}))
	get_root().remove_child(S)
	S.free()
	quit()
