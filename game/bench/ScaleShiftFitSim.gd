extends "res://scripts/Sim.gd"

## Isolated LT-14 trial: do not choose production work that cannot finish in shift.
## Uses the existing travel lower bound; no output, need, or score changes.
var rejected_late_work := 0

func _object_candidates(ag: Dictionary) -> Array:
	var out: Array = super._object_candidates(ag)
	var job: Dictionary = _job_of(String(ag.get("id", "")))
	if String(job.get("title", "")) not in ["渔夫", "环卫工"] or not _in_shift(job):
		return out
	var shifts: Array = job.get("shift", [])
	if shifts.is_empty() or _phase_of(time_of_day()) == "":
		return out
	var remaining := TICKS_PER_DAY
	for ahead in range(1, TICKS_PER_DAY + 1):
		var phase := _phase_of(fmod(time_of_day() + float(ahead) / TICKS_PER_DAY, 1.0))
		if phase not in shifts:
			remaining = ahead
			break
	var kept: Array = []
	for candidate in out:
		if String(candidate.get("action", "")) == _job_action(job):
			var cost := _walk_cost(ag, candidate) + float(candidate.get("dur_total", 0))
			if cost >= remaining:
				rejected_late_work += 1
				continue
		kept.append(candidate)
	return kept

func _exit_tree() -> void:
	print("SHIFT_FIT " + JSON.stringify({"rejected_late_work": rejected_late_work}))
