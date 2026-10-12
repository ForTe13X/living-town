extends "res://scripts/Sim.gd"

## Bench-only read-only tap for single-candidate decisions omitted by decision_sink.
var probe_sink: Callable = Callable()
var hunger_sink: Callable = Callable()
var production_sink: Callable = Callable()
var work_start_sink: Callable = Callable()
var discipline_sink: Callable = Callable()

func _discipline(ag: Dictionary, cands: Array) -> Array:
	var kept: Array = super._discipline(ag, cands)
	if discipline_sink.is_valid():
		discipline_sink.call(ag, cands, kept)
	return kept

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

func _produce_for(ag: Dictionary, action: String) -> void:
	if production_sink.is_valid():
		production_sink.call(ag, action, _in_shift(_job_of(String(ag.get("id", "")))))
	super._produce_for(ag, action)

func _advance_object(ag: Dictionary, opt: Dictionary) -> void:
	var was_travel := String(opt.get("phase", "")) == "travel"
	super._advance_object(ag, opt)
	if was_travel and String(opt.get("phase", "")) == "use" and work_start_sink.is_valid():
		work_start_sink.call(ag, opt, _in_shift(_job_of(String(ag.get("id", "")))))
