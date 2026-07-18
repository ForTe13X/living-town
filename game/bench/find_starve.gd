extends SceneTree
## Pinpoint the seed-4 starvation under endorse-defer: who/which need/where/doing-what.
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 4
	if OS.get_cmdline_user_args().size() > 0: seed = int(OS.get_cmdline_user_args()[0])
	var S = SimScript.new(); get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null; S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	var reported := {}
	for t in range(60 * TPD):
		S.tick()
		for ag in S.agents:
			if String(ag["id"]) == "player": continue
			for nid in ag["needs"]:
				var v := float(ag["needs"][nid])
				if v <= 0.5:
					var kk := "%s:%s" % [ag["id"], nid]
					if not reported.has(kk) or S.tick_no - int(reported[kk]) > 30:
						reported[kk] = S.tick_no
						var opt = ag.get("option")
						var okind = (String(opt.get("kind", "?")) + "/" + String(opt.get("action", ""))) if opt is Dictionary else "idle/none"
						print("STARVE tick=%d day=%d %s need=%s=%.2f pos=%s doing=%s" % [
							S.tick_no, S.tick_no / TPD + 1, S._name(ag), nid, v, str(ag["pos"]), okind])
	quit()
