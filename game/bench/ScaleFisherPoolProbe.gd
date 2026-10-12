extends "res://bench/ScaleSupply.gd"

const TrialSim = preload("res://bench/ScaleFisherPoolSim.gd")

func _make_sim():
	return TrialSim.new()
