extends SceneTree
## Find aria's endorse moments (she huddles with a faction-mate to badmouth a third party).
## Endorse isn't in event_log and its target-memory is low-importance (evicted by day 60) → watch the
## endorse_events counter per tick and grab the fresh memory that tick.
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 1
	if OS.get_cmdline_user_args().size() > 0: seed = int(OS.get_cmdline_user_args()[0])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var prev := 0
	print("seed %d — aria endorse moments:" % seed)
	for t in range(60 * TPD):
		S.tick()
		if S.endorse_events > prev:
			prev = S.endorse_events
			for ag in S.agents:
				if ag.get("memory") == null: continue
				for it in ag["memory"].items:
					if int(it.get("tick", 0)) == S.tick_no and "endorse" in it.get("tags", []):
						var tags = it.get("tags", [])
						print("  tick=%d day=%d partner=%s subject=%s | %s" % [
							S.tick_no, S.tick_no / TPD + 1, S._name(ag), str(tags[0]), String(it.get("text", ""))])
	quit()
