extends "res://bench/ScaleFisherPoolSim.gd"

## LT-14 bench-only decision guard. If hunger is the lowest need and already
## below the existing survival gate, do not start a different long journey
## while an eligible food option exists. This changes the initial commitment,
## not the in-flight preemption threshold (which has known livelock failures).
func _logic_decide(ag: Dictionary, cands: Array) -> Dictionary:
	var chosen: Dictionary = super._logic_decide(ag, cands)
	var needs: Dictionary = ag.get("needs", {})
	var hunger := float(needs.get("hunger", 100.0))
	if hunger >= SURVIVAL_GATE or hunger > _min_need(ag):
		return chosen
	if String(chosen.get("kind", "")) != "journey" or String(chosen.get("need", "")) == "hunger":
		return chosen
	var food: Array = []
	for candidate in cands:
		if candidate is Dictionary and String(candidate.get("need", "")) == "hunger":
			food.append(candidate)
	if food.is_empty():
		return chosen
	return super._logic_decide(ag, food)
