extends Node
## AR2 throwaway probe (NOT committed to game/): counts rendered event types over
## N seeds × D days, split accepted/rejected, marks FEED_SKIP. Mirrors Harness.gd's
## --script pattern (autoload not compile-visible → preload + instance in the tree).
##   godot --headless --path game --script res://scripts/ar2_typehist_probe.gd -- [--seeds 1-12] [--days 30]
const SimScript = preload("res://scripts/Sim.gd")
const MainScript = preload("res://scripts/Main.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var s0 := 1
	var s1 := 12
	var days := 30
	for i in args.size():
		if args[i] == "--seeds" and i + 1 < args.size():
			var parts: PackedStringArray = String(args[i+1]).split("-")
			s0 = int(parts[0]); s1 = int(parts[parts.size()-1])
		elif args[i] == "--days" and i + 1 < args.size():
			days = int(args[i+1])
	var skip: Array = MainScript.FEED_SKIP
	var S = SimScript.new()
	get_tree().get_root().add_child(S)
	S.auto_run = false
	S.backend = null
	S.record_decisions = false
	var tot := {}
	var acc := {}
	var rej := {}
	for seed in range(s0, s1 + 1):
		S.start_new(seed)
		var ticks := days * int(S.TICKS_PER_DAY)
		for _t in range(ticks):
			S.tick()
		for e in S.event_log:
			var ty := String(e.get("type", ""))
			tot[ty] = int(tot.get(ty, 0)) + 1
			if bool(e.get("accepted", true)):
				acc[ty] = int(acc.get(ty, 0)) + 1
			else:
				rej[ty] = int(rej.get(ty, 0)) + 1
	print("=== AR2 event-type histogram · seeds %d-%d × %d days ===" % [s0, s1, days])
	print("%-12s %8s %8s %8s  %s" % ["type", "total", "accept", "reject", "feed?"])
	var keys: Array = tot.keys()
	keys.sort_custom(func(a, b): return int(tot[a]) > int(tot[b]))
	for ty in keys:
		var feed := "SKIP" if ty in skip else "feed"
		print("%-12s %8d %8d %8d  %s" % [ty, int(tot[ty]), int(acc.get(ty,0)), int(rej.get(ty,0)), feed])
	get_tree().quit(0)
