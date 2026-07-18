extends SceneTree
## Find aria's betray moments in a seed → tick/day/parties, so we can render a frame there.
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seed := 7
	if OS.get_cmdline_user_args().size() > 0:
		seed = int(OS.get_cmdline_user_args()[0])
	var S = SimScript.new()
	get_root().add_child(S)
	S._load_data(); S.auto_run = false; S.backend = null
	S.start_new(seed)
	var TPD := int(S.TICKS_PER_DAY)
	for t in range(60 * TPD):
		S.tick()
	print("seed %d — betray events:" % seed)
	for e in S.event_log:
		if String(e.get("type", "")) == "betray":
			var tk := int(e.get("tick", 0))
			print("  tick=%d day=%d actor=%s betrayed=%s subject=%s" % [
				tk, tk / TPD + 1, String(e.get("actor", "")), String(e.get("target", "")), String(e.get("subject", ""))])
	quit()
