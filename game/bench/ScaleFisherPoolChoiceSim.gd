extends "res://bench/ScaleFisherPoolSim.gd"

## Read-only choice hooks for one opened failure window. The inherited
## simulation, candidate scoring, and stock rules are unchanged.
var probe_sink: Callable = Callable()
var hunger_sink: Callable = Callable()

func _logic_decide(ag: Dictionary, cands: Array) -> Dictionary:
	var chosen: Dictionary = super._logic_decide(ag, cands)
	if probe_sink.is_valid():
		probe_sink.call(ag, cands, chosen)
	return chosen

func _hunger_instinct(ag: Dictionary, cands: Array) -> Array:
	var kept: Array = super._hunger_instinct(ag, cands)
	if hunger_sink.is_valid():
		hunger_sink.call(ag, cands, kept)
	return kept
