extends SceneTree
## quick diagnostic: confrontation-scene rate + conflict resolution by mode (logic / CHARACTER / +DRAMA).
const SimScript = preload("res://scripts/Sim.gd")
func _init():
	var seeds := [1, 2, 3, 4, 5, 6]
	var days := 60
	var tc := 0; var ta := 0; var tl := 0; var tr := 0; var tt := 0
	for sd in seeds:
		var S = SimScript.new()
		get_root().add_child(S)
		S._load_data(); S.auto_run = false; S.backend = null
		S.start_new(sd)
		for t in range(days * int(S.TICKS_PER_DAY)):
			S.tick()
		var conf := 0; var apol := 0; var leaks := 0
		var leaker := {}
		for e in S.event_log:
			var ty := String(e.get("type", ""))
			if ty == "confront": conf += 1
			elif ty == "apologize": apol += 1
			elif ty == "betray" or ty == "leak":
				leaks += 1
				var lid := String(e.get("actor", ""))
				leaker[lid] = int(leaker.get(lid, 0)) + 1
		if leaks > 0:
			print("  seed %d leaks=%d by %s" % [sd, leaks, str(leaker)])
		var ling := 0; var repd := 0
		for c in S.conflicts:
			var st := String(c["status"])
			if st == "lingering" or st == "simmering" or st == "escalated": ling += 1
			elif st == "repaired": repd += 1
		tc += conf; ta += apol; tl += ling; tr += repd; tt += S.conflicts.size()
		S.free()
	print("MODE totals over %d seeds×%dd: confront_scenes=%d apologize=%d | conflicts=%d unresolved=%d repaired=%d" % [
		seeds.size(), days, tc, ta, tt, tl, tr])
	quit()
