extends "res://bench/ScaleSupply.gd"

const TrialSim = preload("res://bench/ScaleShiftFitSim.gd")

func _make_sim():
	return TrialSim.new()
