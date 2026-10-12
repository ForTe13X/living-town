extends "res://bench/ScaleSupply.gd"

## Runs the ordinary ScaleSupply accounting on the isolated work-bonus trial.
const TrialSim = preload("res://bench/ScaleSupplyRescueSim.gd")

func _make_sim():
	var sim = TrialSim.new()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--work-bonus" and i + 1 < args.size():
			sim.work_bonus = maxf(0.0, float(args[i + 1]))
		elif args[i] == "--healthy-need" and i + 1 < args.size():
			sim.min_healthy_need = clampf(float(args[i + 1]), 0.0, 100.0)
	return sim
